# Windows 11 ARM64 на Redmi Note 12 4G — экспериментальная установка

Windows 11 Pro ARM64 22H2 (22621.1) загрузилась с внутреннего накопителя **Redmi Note 12 4G NFC (`topaz`, 256 ГБ)**. UEFI Mu-Silicium запускается временно из Fastboot. USB-мышь работает через OTG-хаб. Для Adreno 610 прошёл аппаратный тест Direct3D через Mesa/freedreno.

Порт остаётся экспериментальным. В графическом режиме наблюдались сильные задержки и чёрный экран с курсором. Для рабочего стола можно выбрать **Windows without GPU** в загрузочном меню. Wi-Fi и звук описаны в документации Topaz WOA и требуют прошивок с собственного телефона.

Для чистой установки нужны разблокированный загрузчик, OrangeFox с ADB, ПК с Windows, ARM64-образ Windows и резервная копия. Установка стирает данные Android. Прошивка UEFI в загрузочный раздел для описанного способа не требуется.

Начните с `README.md` в репозитории. Пошаговая установка находится в `docs/INSTALL.md`, сборка UEFI — в `docs/BUILD-UEFI.md`, установка драйверов — в `docs/DRIVERS.md`, восстановление загрузки — в `docs/TROUBLESHOOTING.md`.

Спасибо разработчикам [Topaz WOA](https://github.com/MakrSas/topaz-woa), [Project Silicium](https://github.com/Project-Silicium/Mu-Silicium), Mesa/freedreno и [NTDEV exynos9810-woa](https://github.com/ntdevlabs/exynos9810-woa).
