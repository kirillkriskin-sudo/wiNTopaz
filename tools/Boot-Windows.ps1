param(
    [string] $Image = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Mu-topaz-v4-USB.img')
)

$ErrorActionPreference = 'Stop'
$fastboot = (Get-Command fastboot.exe -CommandType Application).Source
$imagePath = (Resolve-Path -LiteralPath $Image).Path
$devices = @(& $fastboot devices)
if ($LASTEXITCODE -ne 0 -or $devices.Count -ne 1) {
    throw 'Connect one Redmi Note 12 4G directly to the PC in bootloader Fastboot.'
}
$checks = [ordered]@{ 'product' = 'topaz'; 'is-userspace' = 'no'; 'current-slot' = 'a' }
foreach ($key in $checks.Keys) {
    $value = & $fastboot getvar $key 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $value -notmatch "(?m)^\s*${key}:\s+$($checks[$key])\s*$") {
        throw "Unexpected Fastboot state. Expected $key = $($checks[$key])."
    }
}

& $fastboot boot $imagePath
if ($LASTEXITCODE -ne 0) { throw 'Temporary UEFI boot failed.' }
