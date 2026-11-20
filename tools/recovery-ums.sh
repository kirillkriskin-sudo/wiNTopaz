#!/system/bin/sh
set -eu

die() { printf '%s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die 'Run in the root recovery ADB shell.'
[ "$(getprop ro.product.device)" = topaz ] || die 'Expected topaz.'
[ "$(getprop ro.boot.slot_suffix)" = _a ] || die 'Expected slot A.'
[ "$(cat /sys/class/block/sda/queue/logical_block_size)" = 4096 ] || die 'Expected 4 KiB sectors.'
[ "$(cat /sys/class/block/sda/size)" = 495501312 ] || die 'Unexpected UFS size.'
[ "$(readlink /dev/block/by-name/userdata)" = /dev/block/sda19 ] || die 'Unexpected userdata.'

cd /config/usb_gadget/g1
lun=functions/mass_storage.0/lun.0
link=configs/b.1/wintopaz-ums
gadget=4e00000.dwc3
[ "$(cat UDC)" = "$gadget" ] || die 'Unexpected USB controller.'

case "${1:-}" in
    on)
        if grep -Eq '^/dev/block/sda|[[:space:]]/(data|sdcard|metadata|cache)(/|[[:space:]])' /proc/mounts; then
            die 'Unmount internal partitions and disable MTP in OrangeFox before continuing.'
        fi
        [ -z "$(cat "$lun/file")" ] && [ ! -e "$link" ] || die 'A USB export is already configured.'
        echo '' > UDC
        trap 'echo "$gadget" > UDC' EXIT
        echo 0 > "$lun/ro"
        echo /dev/block/sda > "$lun/file"
        if ! ln -s /config/usb_gadget/g1/functions/mass_storage.0 "$link"; then
            echo '' > "$lun/file"
            die 'Could not create USB mass storage link.'
        fi
        ;;
    off)
        [ -L "$link" ] && [ "$(cat "$lun/file")" = /dev/block/sda ] || die 'No Topaz export is active.'
        sync
        echo '' > UDC
        trap 'echo "$gadget" > UDC' EXIT
        rm "$link"
        echo '' > "$lun/file"
        ;;
    *) die 'Usage: recovery-ums.sh on|off' ;;
esac
