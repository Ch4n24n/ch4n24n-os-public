#!/usr/bin/env bash
# ch4n24n-os sign: ビルドした ISO を、Secure Boot を切らずに起動できる形に仕上げる。root は要らない
# 使い方: ch4n24n-os sign [ISO]   （省略すると out/ の一番新しい未署名の ISO）
#
# 変えるのは EFI の起動の部分とカーネルだけ（中身の squashfs には触らない）:
#   EFI/boot/bootx64.efi … Microsoft の署名つきの shim（Debian の shim-signed。live-build も同じ物を入れている）
#   EFI/boot/grubx64.efi … 自分で組んだ GRUB（自分の鍵で署名。要るモジュールを焼き込み、ISO の grub.cfg を読む）
#   EFI/boot/mmx64.efi   … MokManager（初回に自分の鍵を登録する画面）
#   ENROLL_THIS_KEY_IN_MOKMANAGER.cer … 登録する自分の鍵（公開鍵の証明書）
#   live/vmlinuz*・live/memtest … 自分の鍵で署名（grub.cfg は版つきの vmlinuz-<版> を指す）
# UEFI は2か所から起動する: CD として起動するときの El Torito（ISO の中の /boot/grub/efi.img）と、
# USB として起動するときの MBR の2番目のパーティション（ISO の後ろに付け足した efi.img の写し）。両方を差し替える。
# efi.img は元と同じ大きさで作り直す（El Torito の読み込みの長さを、元の記録のまま使えるように）。
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=flavor.sh
source "$HERE/lib/flavor.sh"   # 版の名前と W
# shellcheck source=sb-common.sh
source "$HERE/lib/sb-common.sh"

ISO=${1:-$(ls -t "$W"/out/kali-linux-*-live-"$FLAVOR"-amd64.iso 2>/dev/null | head -1)}
[ -f "$ISO" ] || sb_die "ISO が無い（先に $OS_SLUG build）"
VER=$(basename "$ISO" | sed -E 's/^kali-linux-([^-]+)-.*/\1/')
OUT=$W/out/$OS_SLUG-$VER.iso
sb_tools

T=$(mktemp -d "$W/sign.XXXX")
trap 'rm -rf "$T"' EXIT
echo "[*] 元の ISO: $ISO"

# 1. 署名する物だけを取り出す（squashfs は 3GB あるので取り出さない）
mapfile -t LIVE < <(xorriso -indev "$ISO" -ls /live 2>/dev/null | tr -d "'" | grep -E '^(vmlinuz|memtest)' || true)
[ ${#LIVE[@]} -gt 0 ] || sb_die "/live に vmlinuz が無い"
ex=(-extract /boot/grub/efi.img "$T/efi-orig.img")
for f in "${LIVE[@]}"; do ex+=(-extract "/live/$f" "$T/live/$f"); done
mkdir -p "$T/live"
xorriso -osirrox on -indev "$ISO" "${ex[@]}" 2>/dev/null
chmod -R u+w "$T"

# 2. 自分の GRUB（この ISO の印を探して、ISO の grub.cfg を読む）
MARK=/.disk/$OS_SLUG-$VER
cat > "$T/early.cfg" <<EOF
search --no-floppy --set=root --file $MARK
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF
printf '%s %s\n' "$OS_NAME" "$VER" > "$T/mark"
mkdir -p "$T/esp/EFI/boot"
sb_grub "$T/esp/EFI/boot/grubx64.efi" "$T/early.cfg"
cp "$SB_SHIM" "$T/esp/EFI/boot/bootx64.efi"
cp "$SB_MM" "$T/esp/EFI/boot/mmx64.efi"
cp "$SB_KEYDIR/mok.der" "$T/esp/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"

# 3. カーネルと memtest に署名
maps=()
for f in "${LIVE[@]}"; do
  if sb_sign "$T/live/$f" "$T/live/$f.signed" 2>/dev/null; then
    maps+=(-map "$T/live/$f.signed" "/live/$f"); echo "[+] 署名: /live/$f"
  else
    echo "[?] 署名できない（PE でない）: /live/$f（Secure Boot では起動できない）"
  fi
done

# 4. efi.img を、元と同じ大きさで作り直す
orig=$(stat -c %s "$T/efi-orig.img")
need=$(( $(du -sb "$T/esp" | cut -f1) + 256 * 1024 ))
[ "$need" -le "$orig" ] || sb_die "efi.img に入らない（要る ${need}B・元 ${orig}B）"
mkfs.vfat -C -n EFIBOOT "$T/efi.img" $(( orig / 1024 )) >/dev/null
( cd "$T/esp" && mcopy -s -i "$T/efi.img" ./* ::/ )
[ "$(stat -c %s "$T/efi.img")" -eq "$orig" ] || sb_die "efi.img の大きさが元と違う"
mkdir -p "$T/EFI" && cp -a "$T/esp/EFI/." "$T/EFI/"

# 5. ISO を組み直す（元の起動の仕掛けを replay で写し、変えた物だけ差し替える。付け足しのパーティションも新しい efi.img に）
rm -f "$OUT"
xorriso -indev "$ISO" -outdev "$OUT" -boot_image any replay \
  -append_partition 2 0x01 "$T/efi.img" \
  -map "$T/efi.img" /boot/grub/efi.img \
  -map "$T/EFI" /EFI \
  -map "$T/esp/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" /ENROLL_THIS_KEY_IN_MOKMANAGER.cer \
  -map "$T/mark" "$MARK" \
  "${maps[@]}" 2>&1 | grep -E 'FAILURE|SORRY|WARNING' || true
[ -s "$OUT" ] || sb_die "ISO を書けなかった"

# 6. 確かめる: 付け足しのパーティションの中身が新しい efi.img と同じか、El Torito の EFI の画像が同じか
start=$(xorriso -indev "$OUT" -report_system_area plain 2>/dev/null | awk '/^MBR partition +: +2 /{print $7}')
cmp -s <(dd if="$OUT" bs=512 skip="$start" count=$(( orig / 512 )) status=none) "$T/efi.img" \
  || sb_die "USB 起動用のパーティションが新しい efi.img になっていない"
xorriso -osirrox on -indev "$OUT" -extract /boot/grub/efi.img "$T/check.img" 2>/dev/null
cmp -s "$T/check.img" "$T/efi.img" || sb_die "El Torito の efi.img が新しくなっていない"
( cd "$W/out" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "[+] できた: $OUT（$(du -h "$OUT" | cut -f1)）"
echo "    初めて使う PC では、起動時に MokManager で ENROLL_THIS_KEY_IN_MOKMANAGER.cer を1回だけ登録する"
