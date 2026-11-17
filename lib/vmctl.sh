#!/usr/bin/env bash
# QEMU の VM を、画面なしで動かし、画面の写し（PNG）とキー入力で操る（vm.sh と試験から source する）
# Secure Boot は OVMF の secboot 版＋Microsoft の鍵入りの変数（Windows の PC と同じ状態）で再現する
#
# vm_start <状態のディレクトリ> <sb|nosb> <ディスク...>  起動（ディスクは USB 挿しの形で繋ぐ）
# vm_shot  <状態のディレクトリ> <名前>                 画面を <状態>/<名前>.png に撮る
# vm_key   <状態のディレクトリ> <キー...>               キーを押す（QEMU の sendkey の名前: ret down up tab esc y ...）
# vm_stop  <状態のディレクトリ>

OVMF_DIR=/usr/share/OVMF

vm_mon() { printf '%s\n' "$2" | socat - "UNIX-CONNECT:$1/mon.sock" >/dev/null; }

vm_start() {
  local s=$1 mode=$2; shift 2
  mkdir -p "$s"
  local code=$OVMF_DIR/OVMF_CODE_4M.fd vars=$OVMF_DIR/OVMF_VARS_4M.fd sec=()
  if [ "$mode" = sb ]; then
    code=$OVMF_DIR/OVMF_CODE_4M.secboot.fd vars=$OVMF_DIR/OVMF_VARS_4M.ms.fd
    sec=(-global driver=cfi.pflash01,property=secure,value=on)
  fi
  [ -f "$s/vars.fd" ] || cp "$vars" "$s/vars.fd"   # 変数（登録した鍵）は、消すまで次の起動に持ち越す
  local disks=() i=0 d
  for d in "$@"; do
    disks+=(-drive "if=none,id=usb$i,format=raw,file=$d" -device "usb-storage,bus=xhci.0,drive=usb$i,bootindex=$i")
    i=$((i + 1))
  done
  qemu-system-x86_64 -name ch4n24n-os-test -machine q35,smm=on,accel=kvm -cpu host -smp 2 -m 4096 \
    "${sec[@]}" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,unit=1,file=$s/vars.fd" \
    -device qemu-xhci,id=xhci "${disks[@]}" \
    -device virtio-serial -chardev "socket,path=$s/qga.sock,server=on,wait=off,id=qga0" \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    -vga std -display none -serial "file:$s/serial.log" \
    -monitor "unix:$s/mon.sock,server,nowait" -daemonize -pidfile "$s/qemu.pid"
}

vm_shot() {
  local s=$1 n=$2
  rm -f "$s/$n.ppm"
  vm_mon "$s" "screendump $s/$n.ppm"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$s/$n.ppm" ] && break; sleep 0.3; done
  python3 -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])' "$s/$n.ppm" "$s/$n.png"
  rm -f "$s/$n.ppm"
  echo "$s/$n.png"
}

vm_key() {
  local s=$1 k; shift
  for k in "$@"; do vm_mon "$s" "sendkey $k"; sleep 0.4; done
}

vm_stop() {
  local s=$1
  [ -f "$s/qemu.pid" ] && kill "$(cat "$s/qemu.pid")" 2>/dev/null
  rm -f "$s/qemu.pid"
}
