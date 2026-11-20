# Драйверы для Windows 11 ARM64

В проверенной установке использовались [Topaz WOA CI №227](https://github.com/MakrSas/topaz-woa/actions/runs/37225417803) и [Mesa UMD CI №94](https://github.com/MakrSas/topaz-woa/actions/runs/37137241113). Исходники драйверов и сценарии установки доступны в [ревизии Topaz WOA `bfe5c15`](https://github.com/MakrSas/topaz-woa/tree/bfe5c15). Для скачивания артефактов Actions потребуется вход в GitHub. Если конкретный запуск больше не отдаёт файлы, используйте исходные [сценарии сборки драйверов](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/.github/workflows/build.yml) и [сборки Mesa](https://github.com/MakrSas/topaz-woa/blob/0cab1dc/.github/workflows/mesa.yml). Результат повторной сборки может отличаться, в частности у него будет свой тестовый сертификат. [Как скачать артефакты Actions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## Подготовка

Распакуйте каждый архив `ИмяДрайвера-arm64` в свою папку `C:\topaz\drivers\CI-227\ИмяДрайвера` на телефоне. Артефакты `TopazGpuW` и `TopazAudio` уже содержат вложенные папки. Артефакт `topazgpu-umd-arm64` распакуйте в `C:\topaz\drivers\CI-227\Mesa-UMD`. Сохраните структуру. Можно скопировать всё на внутренний диск заранее через [OrangeFox и USB Mass Storage](INSTALL.md#4-разверните-windows-на-пк), а можно перенести через флешку после первой загрузки.

Проверьте, что часы Windows выставлены правильно. Все команды установки выполняются в **cmd от администратора на телефоне**. Один пакет содержит `.inf`, `.cat`, `.sys`, `topaz-woa-test.cer` и, если сборка его включила, ARM64 `devcon.exe`. Ставьте только сертификаты из проверенного артефакта. Повторите импорт для другой серии пакетов, если сертификат отличается.

```cmd
set "D=C:\topaz\drivers\CI-227"
cd /d "%D%\TopazTouch"
certutil -addstore -f Root topaz-woa-test.cer
certutil -addstore -f TrustedPublisher topaz-woa-test.cer
devcon.exe install TopazTouch.inf "Root\TopazTouch"
```

`devcon install` создаёт новое root-устройство. Для повторной установки проверьте `devcon status "Root\TopazTouch"`. Если устройство уже есть, используйте `devcon update TopazTouch.inf "Root\TopazTouch"`. Та же схема применима к другим root-пакетам из таблицы. Для GPU с ACPI используйте отдельную последовательность ниже.

## Рекомендуемый порядок

| Шаг | Пакет | Действия |
| --- | --- | --- |
| 1 | `TopazTouch` | Установите командой выше. Проверьте ввод. Журнал `C:\TopazTouch.log`. Работоспособность зависит от контроллера панели |
| 2 | `TopazButtons` | `devcon install TopazButtons.inf "Root\TopazButtons"` из папки этого пакета. Проверьте кнопки |
| 3 | `TopazBattery` | Скопируйте пакет на `C:` и извлеките флешку перед запуском. `devcon install TopazBattery.inf "Root\TopazBattery"` из локальной папки. На проверенном экземпляре пропадал кардридер при установке. Журнал `C:\TopazBattery.log` |
| 4 | `TopazDisplay` (по желанию) | Дополнительный framebuffer-драйвер. Если базовый экран устраивает, оставьте его. Для установки и отката используйте [install-display.cmd](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/tools/deploy/install-display.cmd) и [uninstall-display.cmd](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/tools/deploy/uninstall-display.cmd) рядом с его INF. Для установки тестово-подписанного пакета также нужен сертификат |
| 5 | `TopazWifi` (по желанию) | Подготовьте прошивку модема и установите по разделу [Wi-Fi](#wi-fi) |
| 6 | `TopazAudio` → `TopazSpeaker` (по желанию) | Подготовьте ADSP и используйте раздел [Звук](#звук) |
| 7 | `TopazGpuW` + Mesa UMD (по желанию) | Устанавливайте после получения стабильного рабочего стола. См. [Adreno 610](#adreno-610) |

В CI также есть `TopazBacklight`, `TopazCpu`, `TopazRpm`, `TopazModem` и `TopazGpu`. Они нужны для отдельных экспериментов и диагностики. `TopazGpu` — ранний драйвер для проверки железа. Для ускорения рабочего стола используется `TopazGpuW`. Для обычной установки оставьте параметры разгона CPU и GPU в исходном состоянии.

## Прошивки с собственного устройства

Скопируйте файлы в `C:\topaz\fw` на телефоне. Одинаковые имена файлов от другого аппарата не гарантируют совместимость.

| Подсистема | Что положить |
| --- | --- |
| Wi-Fi | `image\` из FAT-раздела `modem_a`, включая `modem.mdt`, его сегменты, `wlanmdsp.mbn`, `bdwlan.*` и вложенные каталоги `modem_pr`. В `efs\` положите `modemst1.bin`, `modemst2.bin`, `fsc.bin` и `fsg.bin` с этого же телефона |
| Динамик | `image\adsp.mdt` и все сегменты `adsp.bNN` из того же образа. Сохраните также относящиеся к ADSP файлы из `image\` |
| GPU | `gpu\a610_zap.mdt`, комплект `a610_zap.bNN` и штатный `gpu\a630_sqe.fw` из Android `vendor/firmware`. В проверенном наборе также лежал `a610_zap.elf` |

Пример чтения с собственного телефона на слоте A в OrangeFox. Выполняйте в **cmd.exe на ПК**. Эти команды читают разделы. Храните дампы EFS локально, они могут содержать данные конкретного устройства.

```cmd
adb get-state
adb shell getprop ro.product.device
adb shell getprop ro.boot.slot_suffix
mkdir fw\efs
mkdir fw\gpu
adb exec-out "dd if=/dev/block/by-name/modem_a bs=1048576 2>/dev/null" > modem_a.img
for %G in (modemst1 modemst2 fsc fsg) do adb exec-out "dd if=/dev/block/by-name/%G bs=1048576 2>/dev/null" > fw\efs\%G.bin
```

Сверьте длины и контрольные суммы дампов с выводом `adb shell blockdev --getsize64 /dev/block/by-name/ИМЯ` и `adb shell sha256sum /dev/block/by-name/ИМЯ`. Откройте `modem_a.img` в архиваторе, который умеет читать FAT-образы, или извлеките `image` из Linux/WSL. Проверьте, что вложенные каталоги сохранились.

```bash
mcopy -n -s -i modem_a.img ::/image fw/
```

Для GPU, если OrangeFox уже смонтировал Android Vendor, найдите нужные файлы в `/vendor/firmware`. При отсутствии этого каталога и наличии mapper-устройства `vendor_a` воспользуйтесь монтированием только для чтения. После копирования размонтируйте Vendor до включения [экспорта UFS](INSTALL.md#3-запишите-gpt-через-usb-mass-storage).

```cmd
adb shell "mkdir -p /tmp/wintopaz-vendor && (mount -t erofs -o ro /dev/block/mapper/vendor_a /tmp/wintopaz-vendor || mount -t ext4 -o ro,noload /dev/block/mapper/vendor_a /tmp/wintopaz-vendor)"
for %G in (a610_zap.mdt a610_zap.b00 a610_zap.b01 a610_zap.b02 a630_sqe.fw) do adb pull /tmp/wintopaz-vendor/firmware/%G fw\gpu\
adb shell umount /tmp/wintopaz-vendor
```

См. также [разбор Wi-Fi и модема](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/docs/HANDOFF_wifi_windows.md), [звука](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/docs/P9_audio.md) и [GPU](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/docs/P8_gpu.md) у авторов порта.

## Wi-Fi

Скопируйте [`install-wifi.cmd`](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/tools/deploy/install-wifi.cmd) в папку `TopazWifi`. Проверьте наличие `C:\topaz\fw\image\modem.mdt` и остальных файлов перед запуском. Загрузитесь после полного выключения, пропустите тест модема в UEFI и запустите сценарий от администратора. Он удаляет root-устройство `TopazModem`, если оно было установлено. Оба драйвера используют один модем, поэтому отдельная установка `TopazModem` для Wi-Fi не требуется. После установки подождите 30 секунд, перезапустите Windows через UEFI и проверьте **Параметры → Сеть и Интернет → Wi-Fi**. Журнал `C:\TopazWifi.log`. В исходном проекте проверяли WPA2 и скорость соединения до 54 Мбит/с в legacy-режиме. [Статус WLAN](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/docs/STATUS_wifi.md)

## Звук

Экспериментальная установка. Из папки `TopazAudio\TopazAudio` сначала создайте маркер первого запуска `audio.arm`, затем установите `TopazAudio`. Дождитесь успешного запуска ADSP в `C:\TopazAudio.log` и только после этого поставьте `TopazSpeaker` из его папки.

```cmd
echo on>C:\topaz\audio.arm
cd /d "C:\topaz\drivers\CI-227\TopazAudio\TopazAudio"
devcon.exe install TopazAudio.inf "Root\TopazAudio"
```

```cmd
cd /d "C:\topaz\drivers\CI-227\TopazSpeaker"
devcon.exe install TopazSpeaker.inf "Root\TopazSpeaker"
```

В Windows выберите **Динамики (Topaz Speaker)** и проверьте звук с низкой громкостью. Маркер `audio.arm` расходуется при старте. В исходном проекте `TopazSpeaker` восстанавливает его после успешного запуска тракта. [Результаты разработчиков](https://github.com/MakrSas/topaz-woa/blob/bfe5c15/docs/P9_audio.md)

## Adreno 610

1. Загрузите **Windows without GPU** и проверьте `C:\topaz\fw\gpu`. Импортируйте сертификат пакета `TopazGpuW`, если он ещё не импортирован.
2. Скопируйте Mesa DLL в `System32`. INF оставьте в распакованной папке драйвера и добавьте в Driver Store.

```cmd
set "D=C:\topaz\drivers\CI-227"
copy "%D%\Mesa-UMD\src\gallium\targets\d3d10umd\topazgpu_d3d10.dll" "%SystemRoot%\System32\"
pnputil /add-driver "%D%\TopazGpuW\TopazGpuW\TopazGpuW.inf"
```

3. Выключите телефон, загрузите UEFI из Fastboot и выберите **Continue**. Для первого запуска проверьте статус ACPI-адаптера.

```cmd
"C:\topaz\drivers\CI-227\TopazGpuW\TopazGpuW\devcon.exe" status "ACPI\TPZG0610"
```

4. При работающем драйвере включите Mesa и перезагрузитесь тем же способом с **Continue**.

```cmd
type nul > C:\topaz\umd.enable
```

5. Запустите тест и проверьте, что первым адаптером выбран Qualcomm Adreno 610. Успешный результат проверенного аппарата и ожидаемый пиксель приведены ниже.

```cmd
"C:\topaz\drivers\CI-227\TopazGpuW\tgputest\d3dtest.exe" copy
```

```text
adapter 0: Qualcomm Adreno 610 (topaz-woa)
D3D11CreateDevice: 00000000, feature level a000
pixel[0,0] = ff4080ff, pixel[63,63] = ff4080ff (expect ff4080ff)
```

`a000` соответствует feature level 10.0 при вызове Direct3D 11 API. Тест проверяет рендеринг и чтение пикселя. Плавность рабочего стола проверяйте отдельно. При чёрном экране или зависаниях вернитесь к **Windows without GPU**. [Диагностика](TROUBLESHOOTING.md#чёрный-экран-или-задержки-с-gpu)
