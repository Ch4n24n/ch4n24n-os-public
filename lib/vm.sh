#!/usr/bin/env bash
# ch4n24n-os vm: できた ISO を VM の窓で起動して見る（USB に挿した形で繋ぐ）。root は要らない
# 使い方: ch4n24n-os vm [--sb] [--reset] [ISO]
#   --sb     Secure Boot を有効にした PC（Microsoft の鍵だけ入った、Windows の PC と同じ状態）として起動
#   --reset  VM の UEFI の変数（登録した鍵）を消して、初めての PC に戻す
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=flavor.sh
source "$HERE/lib/flavor.sh"   # 版の名前と W
mode=nosb reset=0 iso=""
for a in "$@"; do
  case "$a" in
    --sb) mode=sb ;;
    --reset) reset=1 ;;
    *) iso=$a ;;
  esac
done
iso=${iso:-$(ls -t "$W"/out/"$OS_SLUG"-*.iso 2>/dev/null | head -1)}
[ -f "$iso" ] || { echo "[!] ISO が無い（先に $OS_SLUG build と sign）" >&2; exit 1; }
S=$W/vm-$mode
mkdir -p "$S"
[ "$reset" = 1 ] && rm -f "$S/vars.fd"
O=/usr/share/OVMF
if [ "$mode" = sb ]; then
  code=$O/OVMF_CODE_4M.secboot.fd vars=$O/OVMF_VARS_4M.ms.fd sec=(-global driver=cfi.pflash01,property=secure,value=on)
else
  code=$O/OVMF_CODE_4M.fd vars=$O/OVMF_VARS_4M.fd sec=()
fi
[ -f "$S/vars.fd" ] || cp "$vars" "$S/vars.fd"
echo "[*] $iso を起動（$mode）。閉じれば終わる"
exec qemu-system-x86_64 -name "$OS_NAME ($mode)" -machine q35,smm=on,accel=kvm -cpu host -smp 2 -m 4096 \
  "${sec[@]}" \
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
  -drive "if=pflash,format=raw,unit=1,file=$S/vars.fd" \
  -device qemu-xhci,id=xhci \
  -drive "if=none,id=usb0,format=raw,readonly=on,file=$iso" -device usb-storage,bus=xhci.0,drive=usb0,bootindex=0 \
  -vga virtio -display gtk,zoom-to-fit=on
