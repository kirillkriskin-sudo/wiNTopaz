# Установка Windows 11 ARM64 на внутренний UFS

Проверенный аппарат — **Redmi Note 12 4G NFC, `topaz`, 256 ГБ**. Этот способ использует OrangeFox для доступа к накопителю и DISM на ПК для развёртывания Windows. WinPE с USB на проверенном аппарате перезагружался перед запуском установки.

> [!CAUTION]
> Шаги разметки и форматирования ниже стирают `userdata` Android. Сделайте копию фотографий и других данных вне телефона. Сохраните подходящую заводскую прошивку для восстановления и проверьте, что можете вернуться в Fastboot и recovery. Если Windows уже установлена, переходите к разделу [первой загрузки](#5-загрузите-windows).

## 1. Подготовьте файлы и проверьте UEFI

- ПК с Windows 10 или 11, [PowerShell 7.4+](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows), Python 3 и [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools#downloads). Добавьте `adb.exe` и `fastboot.exe` в PATH.
- Разблокированный загрузчик и работающий [OrangeFox для Redmi Note 12 4G](https://orangefox.download/device/65a5a3287ac2a93129dc9543) с ADB. Для проверки использовался R12.0. Установите recovery по инструкции его автора для своей версии. В проверенной конфигурации активен слот A.
- Образ `Mu-topaz-v4-USB.img` из [описанной сборки UEFI](BUILD-UEFI.md), USB-кабель для данных, OTG-хаб, мышь и клавиатура.
- ISO Windows **ARM64** с `sources\install.wim`. Проверена Windows 11 Pro 22H2 (`22621.1`). [Страница Microsoft с ARM64 ISO](https://www.microsoft.com/software-download/windows11arm64) предлагает актуальные образы. Совместимость актуальной версии на этой конфигурации не проверялась. Старые сборки можно собрать из доступных пакетов Microsoft через [UUP dump](https://uupdump.net/).
- [Пакеты драйверов ARM64](DRIVERS.md). Для первой загрузки достаточно UEFI и USB-мыши.

Зажмите **Power + Vol−**, подключите телефон напрямую к ПК и запустите команды из папки проекта. Ожидаемые ответы — `topaz`, `no`, `a`.

```text
fastboot devices
fastboot getvar product
fastboot getvar is-userspace
fastboot getvar current-slot
fastboot boot Mu-topaz-v4-USB.img
```

До установки достаточно увидеть меню **Choose an option**. Сообщение об отсутствии Windows на пустом диске ожидаемо. При несовпадении модели, слота или загрузчика остановитесь и проверьте конфигурацию.

## 2. Снимите обе копии GPT в OrangeFox

Загрузите OrangeFox и подключите телефон напрямую. Отключите MTP в recovery и размонтируйте внутренние разделы, включая `Data`. В `adb shell cat /proc/mounts` не должно быть монтирований `/dev/block/sda*` и путей `/data`, `/metadata`, `/cache`.

Следующие команды выполните в **cmd.exe на ПК**. Перенаправление бинарного вывода в cmd сохраняет сырые байты. Ожидаются `recovery`, `topaz`, `_a`, `4096`, `495501312` и ссылка `/dev/block/sda19`.

```cmd
adb get-state
adb shell getprop ro.product.device
adb shell getprop ro.boot.slot_suffix
adb shell cat /sys/class/block/sda/queue/logical_block_size
adb shell cat /sys/class/block/sda/size
adb shell readlink /dev/block/by-name/userdata
adb shell sgdisk --print /dev/block/sda
adb shell sgdisk --verify /dev/block/sda
mkdir topaz-backup
adb exec-out "dd if=/dev/block/sda bs=4096 count=64 2>/dev/null" > topaz-backup\first64.bin
adb exec-out "dd if=/dev/block/sda bs=4096 skip=61937600 count=64 2>/dev/null" > topaz-backup\last64.bin
py -3 tools\plan-gpt.py topaz-backup\first64.bin topaz-backup\last64.bin topaz-backup\plan
```

Планировщик сверяет обе копии GPT, контрольные суммы, список разделов и границы `userdata`. Если он завершился с ошибкой или обнаружились посторонние разделы, продолжать нельзя. Готовый план оставляет первые 18 записей GPT без изменений, сохраняет GUID и начало `userdata`, выделяет ему около 80 ГиБ, создаёт `esp` на 512 МиБ и отдаёт остаток под `win`. Храните всю папку `topaz-backup` у себя.

## 3. Запишите GPT через USB Mass Storage

На ПК включите экспорт UFS. После переключения USB ADB может отключиться на несколько секунд. Закрывайте любые предложения Windows отформатировать или инициализировать диск.

```cmd
adb push tools\recovery-ums.sh /tmp/wintopaz-ums.sh
adb shell sh /tmp/wintopaz-ums.sh on
```

В **PowerShell 7 от администратора на ПК** найдите диск **Linux File-Stor Gadget**, USB, примерно 236,3 ГиБ, логический сектор 4096 байт. Замените `N` на его номер в обеих командах.

```powershell
Get-Disk | Format-Table Number,FriendlyName,BusType,Size,LogicalSectorSize,IsBoot,IsSystem
.\tools\Write-TopazGpt.ps1 -DiskNumber N -PlanDirectory .\topaz-backup\plan -WhatIf
.\tools\Write-TopazGpt.ps1 -DiskNumber N -PlanDirectory .\topaz-backup\plan
```

`-WhatIf` проверяет диск и снимки без записи. При выполнении второй команды подтвердите действие и введите `WIPE USERDATA`. Ожидается сообщение `GPT written and read back`. При любой ошибке сохраните исходные файлы и остановитесь.

Отключите экспорт и перезагрузитесь в OrangeFox, чтобы перечитать GPT.

```cmd
adb wait-for-device
adb shell sh /tmp/wintopaz-ums.sh off
adb reboot recovery
```

Проверьте обе копии GPT и имена разделов. Должны быть `userdata` → `sda19`, `esp` → `sda20`, `win` → `sda21`, а `sgdisk --verify` должен завершиться без ошибок. Используйте длинные параметры `sgdisk` в OrangeFox.

```cmd
adb shell sgdisk --verify /dev/block/sda
adb shell sgdisk --print /dev/block/sda
adb shell ls -l /dev/block/by-name/userdata /dev/block/by-name/esp /dev/block/by-name/win
```

В OrangeFox выберите **Wipe → Format Data** и подтвердите очистку Android `userdata`. Если сенсор не отвечает, в проверенном OrangeFox R12.0 это действие можно выполнить командой `adb shell twrp format data` после проверки разделов выше. После форматирования снова размонтируйте внутренние тома, отключите MTP и включите USB Mass Storage теми же командами `adb push` и `adb shell ... on`. После перезапуска папка `/tmp` очищается.

## 4. Разверните Windows на ПК

Смонтируйте ISO на ПК. Ниже буква `I:` обозначает ISO, `S:` — EFI-раздел телефона, `W:` — будущий том Windows телефона. Подставьте свободные буквы. В CMD от администратора проверьте редакцию и архитектуру. Здесь `Индекс` заменяется числом для ARM64 Windows Pro.

```cmd
dism /Get-WimInfo /WimFile:I:\sources\install.wim
dism /Get-WimInfo /WimFile:I:\sources\install.wim /Index:Индекс
```

В PowerShell на ПК заново найдите номер диска UFS. В следующем блоке установите его вместо `N`. До форматирования убедитесь, что номер, тип GPT-раздела, смещение и размер соответствуют плану. Команды рассчитаны на два новых пустых раздела.

```powershell
$ErrorActionPreference = 'Stop'
$n = N
$disk = Get-Disk -Number $n
$esp = Get-Partition -DiskNumber $n -PartitionNumber 20
$win = Get-Partition -DiskNumber $n -PartitionNumber 21
$plan = Get-Content .\topaz-backup\plan\plan.json -Raw | ConvertFrom-Json
if ($disk.BusType -ne 'USB' -or $disk.FriendlyName -notlike '*Linux File-Stor Gadget*' -or
    $disk.IsBoot -or $disk.IsSystem -or $disk.IsReadOnly -or
    [guid]$disk.Guid -ne [guid]$plan.diskGuid -or $disk.LogicalSectorSize -ne 4096 -or
    $esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -or
    $win.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -or
    $esp.Offset -ne 96407126016 -or $esp.Size -ne 536870912 -or
    $win.Offset -ne 96943996928 -or $win.Size -ne 156752654336) {
    throw 'Unexpected partitions. Stop.'
}
foreach ($partition in $esp, $win) {
    $existing = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
    if ($existing.FileSystem -in 'FAT32','NTFS','exFAT','ReFS') {
        throw "Partition $($partition.PartitionNumber) already has a filesystem. Stop before formatting."
    }
}
Format-Volume -Partition $esp -FileSystem FAT32 -AllocationUnitSize 4096 -NewFileSystemLabel WINESP -Confirm
Format-Volume -Partition $win -FileSystem NTFS -AllocationUnitSize 4096 -NewFileSystemLabel TopazWin -Confirm
if ((Get-Volume -Partition $esp).FileSystemLabel -ne 'WINESP' -or
    (Get-Volume -Partition $win).FileSystemLabel -ne 'TopazWin') {
    throw 'Expected formatted volumes not found. Stop.'
}
if (-not (Get-Partition -DiskNumber $n -PartitionNumber 20).DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $n -PartitionNumber 20 -AccessPath 'S:\'
}
if (-not (Get-Partition -DiskNumber $n -PartitionNumber 21).DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $n -PartitionNumber 21 -AccessPath 'W:\'
}
Get-Partition -DiskNumber $n | Where-Object PartitionNumber -in 20,21 |
    Format-Table PartitionNumber,DriveLetter,Size
```

Перед развёртыванием запишите фактические буквы разделов. Если `S:` или `W:` уже заняты, используйте свободные буквы в командах выше. Выполните следующие команды по одной в **CMD от администратора**. После каждой проверьте, что команда завершилась успешно.

```cmd
dism /Apply-Image /ImageFile:I:\sources\install.wim /Index:Индекс /ApplyDir:W:\
bcdboot W:\Windows /s S: /f UEFI
dir S:\EFI\Boot\bootaa64.efi
dir S:\EFI\Microsoft\Boot\BCD
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} testsigning on
bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum {default}
```

Тестовая подпись понадобится для драйверов сообщества. В проверенной установке также были выставлены `nointegritychecks on` и `recoveryenabled no` в том же BCD. Первый параметр ослабляет проверку целостности, второй отключает автоматическое восстановление. Для стандартного сценария с тест-подписанными драйверами сначала используйте `testsigning on`. [Документация Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option)

Если требуется, сейчас можно скопировать распакованные драйверы в `W:\topaz\drivers\CI-227` и подготовленную прошивку в `W:\topaz\fw`. После загрузки Windows эти файлы будут на диске `C:`. Закройте программы, использующие тома телефона, размонтируйте их на ПК (`mountvol W: /p` и `mountvol S: /p` с фактическими буквами), отключите экспорт командой `adb shell sh /tmp/wintopaz-ums.sh off` и вернитесь в Fastboot.

## 5. Загрузите Windows

1. Подключите телефон в Fastboot напрямую к ПК и снова выполните `fastboot boot Mu-topaz-v4-USB.img`. Вместо ручной команды можно запустить `pwsh -File .\tools\Boot-Windows.ps1` из папки проекта.
2. Подключите OTG-хаб с мышью и клавиатурой при появлении подсказки о USB. Временно отключите кабель ПК, чтобы телефон мог дать питание хабу. Если подсказки не видно, смените кабель на хаб при входе в меню UEFI, до выбора Windows.
3. Выберите **Windows without GPU** для первой загрузки. Дождитесь первоначальной настройки. В проверенной 22621 на экране подключения к сети можно открыть консоль клавишами `Shift+F10` и выполнить `OOBE\BYPASSNRO`, если этот файл присутствует. После перезагрузки опять запустите UEFI через Fastboot и выберите настройку без интернета.
4. На рабочем столе проверьте время. Продолжайте с [драйверами](DRIVERS.md).

Если Windows не видна в UEFI, есть бутлуп или чёрный экран, откройте [диагностику](TROUBLESHOOTING.md).
