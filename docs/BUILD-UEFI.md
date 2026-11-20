# Сборка UEFI для Redmi Note 12 4G

Используйте вариант **`Mu-topaz-v4-USB.img`** с OTG и пунктом **Windows without GPU**. Временный запуск с этого образа подтверждён на `topaz` с активным слотом A. Если берёте готовый локальный файл проверенной сборки, его SHA-256 есть в [SHA256SUMS.txt](../SHA256SUMS.txt). Собранный заново образ может иметь другую сумму из-за версии инструментов и метаданных сборки.

| Компонент | Ревизия |
| --- | --- |
| Topaz WOA, основа UEFI и ACPI | [`bfe5c15fd63e0038826d84dcbd2a1ff814d52654`](https://github.com/MakrSas/topaz-woa/tree/bfe5c15) |
| Вариант `TopazOtgDxe.c` с ожиданием USB-хаба | [`eb59d95e50a2c32cd6acbc5260d90734108df3d2`](https://github.com/MakrSas/topaz-woa/blob/eb59d95e/uefi/TopazOtgDxe/TopazOtgDxe.c) |
| Mu-Silicium | [`e5f9ec06a6458e6c22dd51e2e6bfc9af06f87d66`](https://github.com/Project-Silicium/Mu-Silicium/tree/e5f9ec06), с подмодулями из коммита |
| AOSP mkbootimg | [`d2bb0af5ba6d3198a3e99529c97eda1be0b5a093`](https://android.googlesource.com/platform/system/tools/mkbootimg/+/d2bb0af5ba6d3198a3e99529c97eda1be0b5a093) |

Проверенная сборка делалась в Ubuntu 24.04 под WSL с LLVM 18, Python 3.12 и GNU-инструментами для AArch64. Храните деревья сборки в файловой системе Linux, например в `~/topaz-build`. Для Mu и подмодулей нужно несколько гигабайт. [Требования Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium/blob/e5f9ec06/Building.md)

Укажите в переменной `GUIDE` абсолютный путь к папке с этим README, например путь под `/mnt/c/` в WSL.

```bash
sudo apt update
sudo apt install git build-essential clang-18 lld-18 llvm-18 nasm uuid-dev \
  gcc-aarch64-linux-gnu python3-venv python3-pil ca-certificates curl

GUIDE=/absolute/path/to/wiNTopaz-GitHub
mkdir -p ~/topaz-build
cd ~/topaz-build
git clone https://github.com/MakrSas/topaz-woa.git
git -C topaz-woa checkout --detach bfe5c15fd63e0038826d84dcbd2a1ff814d52654
git clone https://github.com/Project-Silicium/Mu-Silicium.git
git -C Mu-Silicium checkout --detach e5f9ec06a6458e6c22dd51e2e6bfc9af06f87d66
git -C Mu-Silicium submodule update --init --recursive
git clone https://android.googlesource.com/platform/system/tools/mkbootimg aosp-mkbootimg
git -C aosp-mkbootimg checkout --detach d2bb0af5ba6d3198a3e99529c97eda1be0b5a093

python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r Mu-Silicium/pip-requirements.txt
export PATH="/usr/lib/llvm-18/bin:$PATH"
export MKBOOTIMG_DIR="$PWD/aosp-mkbootimg"

git -C topaz-woa apply "$GUIDE/tools/uefi-build-portability.patch"
git -C topaz-woa show eb59d95e50a2c32cd6acbc5260d90734108df3d2:uefi/TopazOtgDxe/TopazOtgDxe.c \
  > topaz-woa/uefi/TopazOtgDxe/TopazOtgDxe.c
topaz-woa/uefi/build_topaz_uefi.sh "$PWD/Mu-Silicium" "$GUIDE/Mu-topaz-v4-USB.img" RELEASE
python3 "$MKBOOTIMG_DIR/unpack_bootimg.py" --boot_img "$GUIDE/Mu-topaz-v4-USB.img" --out unpacked
sha256sum "$GUIDE/Mu-topaz-v4-USB.img"
```

Проверьте в выводе `unpack_bootimg.py`, что заголовок Android boot image имеет версию **4**. Затем загрузите образ через `fastboot boot` по [инструкции](INSTALL.md#1-подготовьте-файлы-и-проверьте-uefi). Сценарий сборки использует имя платформы `tapas` в Mu-Silicium. Проверка устройства в руководстве выполняется отдельно по ответу Fastboot `topaz`.
