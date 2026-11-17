#!/usr/bin/env bash
# ch4n24n-os usb: USB に OS（Ch4n24n OS）を書き、保存領域を作る（list 以外は root。ch4n24n-os usb が sudo で呼ぶ）
#
# できる形（MBR の4区画）:
#   1・2  ISO（本体と、UEFI の起動の区画）… 先頭 8GiB を ISO のために空けておく（作り直した ISO を書き直せるように）
#   3     保存領域: LUKS で暗号化した ext4（label persistence、persistence.conf は "/ union"）… 既定 40GiB
#   4     受け渡し用: exFAT（label は CH4N24N）… 残り全部。Windows・Mac でも開ける。暗号化しない
#
# 使い方:
#   usb.sh list                            挿さっている USB の一覧
#   usb.sh write <デバイス> <ISO> [GiB]     ISO を書いてから、保存領域と受け渡し用を作る（USB の中身は全部消える）
#   usb.sh data  <デバイス> [GiB]           ISO が書いてある USB に、保存領域と受け渡し用だけを作る
# 試験用の環境変数（VM の中で流すとき）: CH4N24N_OS_TEST_PASS（パスフレーズ）・CH4N24N_OS_YES=1（確認を飛ばす）
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=flavor.sh
source "$HERE/lib/flavor.sh"   # 版（XFER_LABEL）。ch4n24n-os usb が sudo env で CH4N24N_OS_FLAVOR を渡す

ISO_GIB=8
GIB=2097152   # 1GiB を 512 バイトの区画で数えた数
die() { echo "[!] $*" >&2; exit 1; }
log() { echo "[*] $*"; }

list_usb() {
  echo "USB でつながっているディスク:"
  lsblk -dpno NAME,TRAN,SIZE,MODEL | awk '$2=="usb"{$2=""; print "  " $0}' | grep . || echo "  （無い）"
}

part() { if [[ $1 =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "${1}$2"; fi; }

check_device() {
  local dev=$1 sys
  [ -b "$dev" ] || die "$dev はブロックデバイスでない"
  [ "$(lsblk -dno TYPE "$dev")" = disk ] || die "$dev はディスク全体でない（sdb1 ではなく sdb のように指定する）"
  [ "$(lsblk -dno TRAN "$dev")" = usb ] || die "$dev は USB でつながっていない（内蔵のディスクを消さないため止める）"
  for m in / /boot /boot/efi /home; do
    sys=$(findmnt -no SOURCE "$m" 2>/dev/null) || continue
    [ -b "$sys" ] || continue
    if [ "$(lsblk -no PKNAME "$sys" 2>/dev/null | head -1)" = "$(basename "$dev")" ] || [ "$sys" = "$dev" ]; then
      die "$dev には今の PC の $m がある"
    fi
  done
}

show_device() {
  local dev=$1
  echo
  echo "書き込む先: $dev  $(lsblk -dno SIZE,MODEL "$dev")"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$dev" | sed 's/^/    /'
  echo
}

confirm() {
  local dev=$1 ans
  [ "${CH4N24N_OS_YES:-}" = 1 ] && return 0
  echo "この USB の中身は、全部消える。"
  read -r -p "消してよければ、デバイス名（$(basename "$dev")）を打つ: " ans
  [ "$ans" = "$(basename "$dev")" ] || die "やめた"
}

release() {  # 開いている暗号の区画を閉じ、マウントを外す（GNOME が自動でマウントするため、書く前後に呼ぶ）
  local dev=$1 n t
  while read -r n t; do
    [ "$t" = crypt ] && cryptsetup close "$n" 2>/dev/null || true
  done < <(lsblk -lnpo NAME,TYPE "$dev" | tac)
  for n in $(lsblk -lnpo NAME "$dev" | tail -n +2); do umount "$n" 2>/dev/null || true; done
}

read_pass() {
  if [ -n "${CH4N24N_OS_TEST_PASS:-}" ]; then PASS=$CH4N24N_OS_TEST_PASS; return; fi
  local p2
  echo "保存領域のパスフレーズを決める（起動のたびに打つ。キー配列は US で打つ）"
  while :; do
    read -rs -p "  パスフレーズ: " PASS; echo
    read -rs -p "  もう一度: " p2; echo
    [ -n "$PASS" ] || { echo "  空は使えない"; continue; }
    [ "$PASS" = "$p2" ] && break
    echo "  一致しない。もう一度"
  done
}

write_iso() {
  local dev=$1 iso=$2
  [ -f "$iso" ] || die "ISO が無い: $iso"
  [ "$(stat -c %s "$iso")" -lt $(( ISO_GIB * 1024 * 1024 * 1024 )) ] || die "ISO が ${ISO_GIB}GiB を超える"
  log "ISO を書く: $(basename "$iso") → $dev"
  dd if="$iso" of="$dev" bs=4M conv=fsync oflag=direct status=progress
  sync
  partprobe "$dev" 2>/dev/null || true
  udevadm settle || true
  sleep 2
  release "$dev"
}

make_data() {
  local dev=$1 persist=$2 total iso_end start3 size3 start4 p3 p4 map m
  total=$(blockdev --getsz "$dev")
  # 今ある区画（ISO の1・2）の終わりが、ISO 用の 8GiB に収まっているか
  iso_end=$(sfdisk -d "$dev" 2>/dev/null | awk -F'[=,]' '/start=/{s=$2+0; z=$4+0; if (s+z>e) e=s+z} END{print e+0}')
  [ "$iso_end" -gt 0 ] || die "$dev に ISO が書かれていない"
  [ "$(sfdisk -d "$dev" 2>/dev/null | grep -c 'start=')" -eq 2 ] || die "$dev には ISO の2区画のほかに区画がある（write で書き直す）"
  [ "$iso_end" -le $(( ISO_GIB * GIB )) ] || die "ISO が ${ISO_GIB}GiB の枠を超えている"
  # 保存領域の大きさ: 指定が無ければ 40GiB。USB が小さければ、残りの半分まで
  if [ -z "$persist" ]; then
    persist=40
    local half=$(( (total / GIB - ISO_GIB) / 2 ))
    [ "$persist" -le "$half" ] || persist=$half
  fi
  start3=$(( ISO_GIB * GIB )); size3=$(( persist * GIB )); start4=$(( start3 + size3 ))
  [ $(( total - start4 )) -ge "$GIB" ] || die "USB が小さすぎる（保存領域 ${persist}GiB を取ると、受け渡し用が 1GiB に満たない）"
  log "区画を足す: 保存領域 ${persist}GiB（暗号化）・受け渡し用 $(( (total - start4) / GIB ))GiB（exFAT）"
  # --wipe never: ISO の印（iso9660）を消さない
  printf 'start=%s, size=%s, type=83\nstart=%s, type=7\n' "$start3" "$size3" "$start4" \
    | sfdisk --append --no-reread --wipe never --wipe-partitions never -q "$dev"
  partx -u "$dev" 2>/dev/null || partprobe "$dev" 2>/dev/null || true
  udevadm settle || true
  p3=$(part "$dev" 3); p4=$(part "$dev" 4)
  for _ in $(seq 20); do [ -b "$p3" ] && [ -b "$p4" ] && break; sleep 0.5; done
  [ -b "$p3" ] && [ -b "$p4" ] || die "区画 3・4 が見えない（$p3 $p4）"
  release "$dev"
  wipefs -qa "$p3" "$p4"

  read_pass
  log "保存領域を暗号化する（LUKS2）"
  printf '%s' "$PASS" | cryptsetup -q luksFormat --type luks2 --key-file - "$p3"
  map=$FLAVOR-persistence-$$
  printf '%s' "$PASS" | cryptsetup open --key-file - "$p3" "$map"
  unset PASS
  mkfs.ext4 -q -L persistence "/dev/mapper/$map"
  m=$(mktemp -d)
  mount "/dev/mapper/$map" "$m"
  echo "/ union" > "$m/persistence.conf"
  umount "$m"; rmdir "$m"
  cryptsetup close "$map"
  log "受け渡し用を作る（exFAT・$XFER_LABEL）"
  mkfs.exfat -q -L "$XFER_LABEL" "$p4" >/dev/null 2>&1 || mkfs.exfat -L "$XFER_LABEL" "$p4"
  sync
  release "$dev"
  echo
  lsblk -o NAME,SIZE,FSTYPE,LABEL "$dev" | sed 's/^/    /'
}

cmd=${1:-list}
case "$cmd" in
  list) list_usb ;;
  write)
    [ "$(id -u)" -eq 0 ] || die "root で動かす（ch4n24n-os usb から呼ぶ）"
    dev=${2:?デバイス}; iso=${3:?ISO}
    for c in sfdisk partx cryptsetup mkfs.ext4 mkfs.exfat wipefs; do
      command -v "$c" >/dev/null || { [ "$c" = mkfs.exfat ] && apt-get install -y exfatprogs >/dev/null; } || die "$c が無い"
    done
    check_device "$dev"; show_device "$dev"; confirm "$dev"
    release "$dev"
    write_iso "$dev" "$iso"
    make_data "$dev" "${4:-}"
    echo
    echo "[+] できた。この USB から起動する（PC の起動メニュー。F12・F11・Esc など機種による）"
    echo "    初めての PC では MokManager で ENROLL_THIS_KEY_IN_MOKMANAGER.cer を1回登録 → 起動のたびにパスフレーズ"
    ;;
  data)
    [ "$(id -u)" -eq 0 ] || die "root で動かす"
    dev=${2:?デバイス}
    check_device "$dev"; show_device "$dev"; confirm "$dev"
    release "$dev"
    make_data "$dev" "${3:-}"
    ;;
  *) die "使い方: usb.sh list | write <デバイス> <ISO> [GiB] | data <デバイス> [GiB]" ;;
esac
