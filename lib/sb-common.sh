#!/usr/bin/env bash
# Secure Boot の署名の共通部分（sign.sh と試験から source する）
#
# 起動の鎖: UEFI（Microsoft の鍵）→ shimx64（Microsoft の署名。Debian の shim-signed）
#   → grubx64（自分で組んだ GRUB。自分の鍵で署名）→ vmlinuz（自分の鍵で署名）
# 自分の鍵は、PC ごとに1回だけ MokManager で登録する（ESP の ENROLL_THIS_KEY_IN_MOKMANAGER.cer）。
# shim は、自分が直接読む物（GRUB）には .sbat を要求する。カーネルは GRUB が shim に確かめさせる。

SB_KEYDIR=${SB_KEYDIR:-$HOME/.config/ch4n24n-os}
SB_CACHE=${SB_CACHE:-${CH4N24N_OS_WORK:-$HOME/work/ch4n24n-os}/cache}

# GRUB に焼き込むモジュール。Secure Boot の下では、ディスクからの insmod が禁じられるので、要る物は全部ここに入れる
SB_GRUB_MODULES="all_video boot cat chain configfile echo efifwsetup ext2 fat font gettext gfxmenu gfxterm
gfxterm_background gzio halt help iso9660 jpeg keystatus loadenv loopback linux ls lsefi minicmd normal part_gpt
part_msdos play png probe reboot regexp search search_fs_uuid search_fs_file search_label serial sleep squash4 test
true video tpm"

sb_die() { echo "[!] $*" >&2; exit 1; }

# 道具と部品を揃える（sbsign は入っていれば本物、無ければ apt から落として展開した物）
sb_tools() {
  [ -f "$SB_KEYDIR/mok.key" ] || sb_die "鍵が無い: $SB_KEYDIR/mok.key"
  local p d
  for p in shim-signed shim-helpers-amd64-signed sbsigntool; do
    d="$SB_CACHE/deb-$p"
    if ! ls "$d"/*.deb >/dev/null 2>&1; then
      rm -rf "$d"; mkdir -p "$d/x"
      (cd "$d" && apt-get download -q "$p" >/dev/null) || sb_die "$p を落とせなかった"
      dpkg-deb -x "$d"/*.deb "$d/x"
    fi
  done
  SB_SHIM=$SB_CACHE/deb-shim-signed/x/usr/lib/shim/shimx64.efi.signed
  SB_MM=$SB_CACHE/deb-shim-helpers-amd64-signed/x/usr/lib/shim/mmx64.efi.signed
  SB_SIGN=$(command -v sbsign || echo "$SB_CACHE/deb-sbsigntool/x/usr/bin/sbsign")
  [ -x "$SB_SIGN" ] && [ -f "$SB_SHIM" ] && [ -f "$SB_MM" ] || sb_die "shim・MokManager・sbsign が揃わない"
}

sb_sign() {  # <入力> <出力>
  "$SB_SIGN" --key "$SB_KEYDIR/mok.key" --cert "$SB_KEYDIR/mok.crt" --output "$2" "$1" >/dev/null
}

# 自分の GRUB を組んで署名する。<出力> <最初に読む設定>
sb_grub() {
  local out=$1 early=$2 tmp mods m
  tmp=$(mktemp -d)
  mods=""
  for m in $SB_GRUB_MODULES; do
    [ -f "/usr/lib/grub/x86_64-efi/$m.mod" ] && mods="$mods $m" || echo "[?] GRUB のモジュールが無い: $m" >&2
  done
  local gv; gv=$(dpkg-query -W -f='${Version}' grub-efi-amd64-bin)
  cat > "$tmp/sbat.csv" <<EOF
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
grub,5,Free Software Foundation,grub,${gv%%-*},https://www.gnu.org/software/grub/
grub.ch4n24n,1,Ch4n24n OS,grub2,$gv,https://www.kali.org/
EOF
  # shellcheck disable=SC2086
  grub-mkimage -O x86_64-efi -p /boot/grub --sbat "$tmp/sbat.csv" -c "$early" -o "$tmp/grubx64.efi" $mods
  sb_sign "$tmp/grubx64.efi" "$out"
  rm -rf "$tmp"
}
