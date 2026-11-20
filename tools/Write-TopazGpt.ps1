#Requires -Version 7.4
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [uint32] $DiskNumber,
    [Parameter(Mandatory)] [string] $PlanDirectory
)

$ErrorActionPreference = 'Stop'
$sector = 4096
$totalSectors = 61937664L
$target = Get-Disk -Number $DiskNumber
if ($target.BusType -ne 'USB' -or $target.FriendlyName -notlike '*Linux File-Stor Gadget*' -or
    $target.Size -ne ($totalSectors * $sector) -or $target.LogicalSectorSize -ne $sector -or
    $target.IsBoot -or $target.IsSystem -or $target.IsReadOnly) {
    throw 'The selected disk is not the expected writable Topaz recovery USB gadget.'
}

$plan = Get-Content -LiteralPath (Join-Path $PlanDirectory 'plan.json') -Raw | ConvertFrom-Json
$expected = [ordered]@{
    'secondary-entries.bin' = @{ Lba = 61937659; Bytes = 16384 }
    'secondary-header.bin' = @{ Lba = 61937663; Bytes = 4096 }
    'primary-entries.bin' = @{ Lba = 2; Bytes = 16384 }
    'primary-header.bin' = @{ Lba = 1; Bytes = 4096 }
}

function Get-Sha256([byte[]] $Data) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Data))
}

function Read-Region([IO.FileStream] $Stream, [long] $Lba, [int] $Length) {
    [void]$Stream.Seek($Lba * $sector, [IO.SeekOrigin]::Begin)
    $data = [byte[]]::new($Length)
    $Stream.ReadExactly($data)
    return ,$data
}

function Confirm-Snapshot([IO.FileStream] $Stream) {
    $first = Read-Region $Stream 0 (64 * $sector)
    $last = Read-Region $Stream ($totalSectors - 64) (64 * $sector)
    $guid = [Guid]::new([byte[]]($first[4152..4167]))
    $firstHash = Get-Sha256 $first
    $lastHash = Get-Sha256 $last
    $matches = @($plan.allowedSnapshots | Where-Object {
        $_.first -eq $firstHash -and $_.last -eq $lastHash
    })
    if ($guid -ne [Guid]$plan.diskGuid -or $matches.Count -ne 1) {
        throw 'The live GPT differs from the GPT captured in recovery. Stop and keep the snapshots.'
    }
}

function Write-Region([IO.FileStream] $Stream, [long] $Lba, [byte[]] $Data) {
    [void]$Stream.Seek($Lba * $sector, [IO.SeekOrigin]::Begin)
    $Stream.Write($Data, 0, $Data.Length)
    $Stream.Flush($true)
    $actual = Read-Region $Stream $Lba $Data.Length
    if ((Get-Sha256 $actual) -ne (Get-Sha256 $Data)) {
        throw "Read-back mismatch at LBA $Lba."
    }
}

if ($plan.writes.Count -ne $expected.Count) { throw 'Unexpected plan length.' }
$regions = @()
foreach ($name in $expected.Keys) {
    $operation = @($plan.writes | Where-Object name -eq $name)
    $range = $expected[$name]
    if ($operation.Count -ne 1 -or $operation[0].lba -ne $range.Lba -or
        $operation[0].bytes -ne $range.Bytes) { throw "Invalid plan range for $name." }
    $data = [IO.File]::ReadAllBytes((Join-Path $PlanDirectory $name))
    if ($data.Length -ne $range.Bytes -or (Get-Sha256 $data) -ne $operation[0].sha256) {
        throw "Invalid GPT data for $name."
    }
    $regions += @{ Lba = $range.Lba; Data = $data }
}

$path = '\\.\PhysicalDrive' + $DiskNumber
$reader = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
try { Confirm-Snapshot $reader } finally { $reader.Dispose() }
Write-Host "Verified $path, Topaz GPT $($plan.diskGuid)."
if (-not $PSCmdlet.ShouldProcess($path, 'Replace both GPT copies and resize Android userdata')) { return }
if ((Read-Host 'Type WIPE USERDATA to proceed') -cne 'WIPE USERDATA') { throw 'Cancelled.' }

$disk = [IO.FileStream]::new($path, 'Open', 'ReadWrite', 'ReadWrite', $sector, 'WriteThrough')
try {
    Confirm-Snapshot $disk
    $started = New-Object 'System.Collections.Generic.List[hashtable]'
    try {
        foreach ($region in $regions) {
            $saved = Read-Region $disk $region.Lba $region.Data.Length
            $started.Add(@{ Lba = $region.Lba; Data = $saved })
            Write-Region $disk $region.Lba $region.Data
        }
    } catch {
        $failure = $_
        try {
            foreach ($region in $started) { Write-Region $disk $region.Lba $region.Data }
        } catch {
            throw "GPT write failed and rollback could not be verified. Keep the original snapshots. $failure / $_"
        }
        throw "GPT write failed. Changed regions were restored and checked. $failure"
    }
    Write-Host 'GPT written and read back. Reboot to recovery and verify both tables before formatting.'
} finally {
    $disk.Dispose()
}
