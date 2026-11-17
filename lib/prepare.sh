#!/usr/bin/env bash
# ch4n24n-os prepare: kali-live の作業コピーに、自分用の版（variant-ch4n24n）を組み立てる。root は要らない
# 毎回まっさらから作り直す（メイン PC の設定・hackdeck・雛形の今を写す）
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=flavor.sh
source "$HERE/lib/flavor.sh"   # FLAVOR・OS_NAME・OS_SLUG・OS_USER・FL・W
KL=$W/kali-live
V=$KL/kali-config/variant-$FLAVOR
IC=$V/includes.chroot
SK=$IC/etc/skel
DESK=$HOME/git/tools/desktop
BLOG=$HOME/git/Ch4n24n.github.io/content/notes
log() { printf '[*] %s\n' "$*"; }

# 1. kali-live（Kali 公式のビルド一式）を最新に。手を入れるのは auto/config だけで、毎回元に戻してから当てる
mkdir -p "$W/src"
[ -d "$KL/.git" ] || git clone -q https://gitlab.com/kalilinux/build-scripts/kali-live.git "$KL"
git -C "$KL" checkout -q -- auto/config
git -C "$KL" pull -q --ff-only || log "kali-live を最新にできなかった（手元の版で続ける）"
python3 "$HERE/lib/patch-autoconfig.py" "$KL/auto/config" "$OS_NAME"

# 2. 案件の雛形（Hacking-Op）を最新に。USB では GitHub から clone できないので、手元のリポジトリとして同梱する
if [ -d "$W/src/Hacking-Op/.git" ]; then
  GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15' git -C "$W/src/Hacking-Op" pull -q --ff-only \
    || log "Hacking-Op を最新にできなかった（手元の版で続ける）"
else
  GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15' git clone -q git@github.com:Ch4n24n/Hacking-Op.git "$W/src/Hacking-Op"
fi

# 3. variant を作り直す（共通の一覧のうち、linux-headers と仮想化は上書きして減らす）
rm -rf "$V"
mkdir -p "$V/package-lists" "$V/hooks/live" "$V/bootloaders/grub-pc" "$V/bootloaders/syslinux_common" \
         "$V/includes.binary/isolinux" "$SK"
cp "$HERE/share/packages.list" "$V/package-lists/kali.list.chroot"
# 版ごとの足し算は、別の一覧にする（live-build は package-lists/ の全部を読む）
if [ -f "$FL/packages.list" ]; then cp "$FL/packages.list" "$V/package-lists/$FLAVOR.list.chroot"; fi
printf '## Ch4n24n OS: カーネルのヘッダは入れない（DKMS で組む物を入れないため）\n' > "$V/package-lists/linux-headers.list.chroot"
printf '## Ch4n24n OS: VM で試すときの2つだけ\nqemu-guest-agent\nspice-vdagent\n' > "$V/package-lists/virtualization.list.chroot"
# 起動メニューの項目名と、hook の sudo の行は、版の名前・live のユーザに替えて写す
sed "s/Ch4n24n OS/$OS_NAME/g" "$HERE/share/grub.cfg" > "$V/bootloaders/grub-pc/grub.cfg"
cp "$HERE/share/config.cfg" "$V/bootloaders/grub-pc/"
sed "s/Ch4n24n OS/$OS_NAME/g" "$HERE/share/live.cfg.in" > "$V/bootloaders/syslinux_common/live.cfg.in"
sed "s/@OS_USER@/$OS_USER/g" "$HERE/share/hook.chroot" > "$V/hooks/live/ch4n24n.chroot"
chmod 755 "$V/hooks/live/ch4n24n.chroot"
# 時刻帯を /etc/timezone の値で張り直す live-config の部品（0070-tzdata の直後に流れる）
install -D -m 755 "$HERE/share/live-config-timezone" "$IC/usr/lib/live/config/0071-ch4n24n-timezone"

# 起動メニューの題を版の名前に（Kali の物を写して、題の行だけ替える。替えられなければ止まる）
C=$KL/kali-config/common/bootloaders
mkdir -p "$V/bootloaders/grub-pc/theme"
sed "s|text = \"Kali Linux live menu (UEFI mode)\"|text = \"$OS_NAME (UEFI mode)\"|" "$C/grub-pc/theme/theme.txt" > "$V/bootloaders/grub-pc/theme/theme.txt"
sed "s|^menu title Kali Linux live menu (BIOS mode)\$|menu title $OS_NAME (BIOS mode)|" "$C/syslinux_common/menu.cfg" > "$V/bootloaders/syslinux_common/menu.cfg"
grep -q "$OS_NAME (UEFI mode)" "$V/bootloaders/grub-pc/theme/theme.txt" || { echo "[!] GRUB のテーマの題を替えられない（kali-live が変わった）" >&2; exit 1; }
grep -q "^menu title $OS_NAME" "$V/bootloaders/syslinux_common/menu.cfg" || { echo "[!] isolinux の題を替えられない（kali-live が変わった）" >&2; exit 1; }
# 版の色: 選んだ行の帯（Kali の select_*.png の形のまま色だけ替える）と、背景の地の色
if [ -n "$GRUB_ACCENT" ]; then
  python3 - "$C/grub-pc/theme" "$V/bootloaders/grub-pc/theme" "$GRUB_ACCENT" <<'PY'
import sys
from PIL import Image
src, dst, rgb = sys.argv[1], sys.argv[2], tuple(int(v) for v in sys.argv[3].split(","))
for n in ("select_w.png", "select_c.png", "select_e.png"):
    im = Image.open(f"{src}/{n}").convert("RGBA")
    out = Image.new("RGBA", im.size, rgb + (255,))
    out.putalpha(im.getchannel("A"))
    out.save(f"{dst}/{n}")
PY
  sed -i 's|^desktop-color: .*|desktop-color: "#09090b"|' "$V/bootloaders/grub-pc/theme/theme.txt"
fi

# 4. 自分の印（アイコン・壁紙・起動メニューの背景）
ICON_SVG=$HERE/branding/icon.svg
if [ -f "$FL/icon.svg" ]; then ICON_SVG=$FL/icon.svg; fi
python3 "$HERE/branding/render.py" "$W/brand" --name "$OS_NAME" "${BRAND_ARGS[@]}"
cp "$W/brand/splash.png" "$V/bootloaders/grub-pc/splash.png"
cp "$W/brand/splash-640.png" "$V/includes.binary/isolinux/splash.png"
install -D -m 644 "$W/brand/wallpaper.png" "$IC/usr/share/backgrounds/$OS_SLUG/wallpaper.png"
install -D -m 644 "$ICON_SVG" "$IC/usr/share/icons/hicolor/scalable/apps/$OS_SLUG.svg"
for s in 48 128 256; do
  install -D -m 644 "$W/brand/icon-$s.png" "$IC/usr/share/icons/hicolor/${s}x${s}/apps/$OS_SLUG.png"
done

# 5. デスクトップの設定（desktop ツールの gsettings.tsv を dconf の既定に）
mkdir -p "$IC/etc/dconf/db/local.d" "$IC/etc/dconf/db/ibus.d"
DCONF_EXTRA=()   # 版ごとの上書きは、共通の上書きの後に重ねる
if [ -f "$FL/dconf-overrides.ini" ]; then DCONF_EXTRA=("$FL/dconf-overrides.ini"); fi
python3 "$HERE/lib/gsettings2dconf.py" "$DESK/gsettings.tsv" "$HERE/share/dconf-overrides.ini" "$IC/etc/dconf/db/local.d/zz-ch4n24n" "${DCONF_EXTRA[@]}"
cp "$IC/etc/dconf/db/local.d/zz-ch4n24n" "$IC/etc/dconf/db/ibus.d/zz-ch4n24n"   # ibus は自分の profile（system-db:ibus）を読む

# 6. ホームの雛形（/etc/skel。live のユーザが作られるとき、ここが写される）
for f in .bashrc .tmux.conf .gitconfig .config/gtk-3.0/settings.ini .config/environment.d/50-gtk-im-ibus.conf; do
  install -D -m 644 "$DESK/files/$f" "$SK/$f"
done
python3 "$HERE/lib/patch-zshrc.py" "$DESK/files/.zshrc" "$SK/.zshrc"
mkdir -p "$SK/.tmux" && cp -a "$HOME/.tmux/plugins" "$SK/.tmux/"
install -D -m 600 "$HOME/.config/mozc/config1.db" "$SK/.config/mozc/config1.db"
install -D -m 644 "$HOME/.config/mozc/ibus_config.textproto" "$SK/.config/mozc/ibus_config.textproto"
printf 'SELECTED_EDITOR="/usr/bin/vim.basic"\n' > "$SK/.selected_editor"
# fastfetch（neofetch の後継）で自分のマーク（ω口の猫）を出す。neofetch と打っても同じ物が出る
FF=$HERE/share/fastfetch
if [ -d "$FL/fastfetch" ]; then FF=$FL/fastfetch; fi
install -D -m 644 -t "$SK/.config/fastfetch" "$FF"/*
install -D -m 755 "$HERE/share/neofetch-wrapper" "$IC/usr/local/bin/neofetch"

# hackdeck と雛形。hackdeck は雛形が手元の git なら、そこから clone する（session.py の case_make）
# コマンド帳は、USB で読む本（OS_BOOKS。既定 physical）だけを写す。普段の ctf は、USB に道具が入っていないので入れない。
# hackdeck の .git も写さない（履歴に ctf の中身が入っている。2026-11-15、本人「俺の指示はあくまで、OSに閉じていたのに」）
OS_BOOKS=${OS_BOOKS:-physical}
mkdir -p "$SK/git" "$SK/.local/bin"
rsync -a --delete --exclude '__pycache__' --exclude '/.git' --exclude '/books/' "$HOME/git/hackdeck/" "$SK/git/hackdeck/"
for b in $OS_BOOKS; do
  [ -d "$HOME/git/hackdeck/books/$b" ] || { echo "[!] hackdeck の本が無い: $b" >&2; exit 1; }
  mkdir -p "$SK/git/hackdeck/books/$b"
  rsync -a --delete --exclude '__pycache__' "$HOME/git/hackdeck/books/$b/" "$SK/git/hackdeck/books/$b/"
done
rsync -a --delete "$W/src/Hacking-Op/" "$SK/git/Hacking-Op/"
# symlink にしない: kali-live の auto/config は variant を cp -rTL で写すので、symlink は実ファイルに化ける。
# hackdeck の起動口は realpath(__file__) から本体を探すため、化けると ~/.local の下を探して起動できない
printf '#!/bin/sh\n# Ch4n24n OS: hackdeck の本体を呼ぶ（symlink の代わり）\nexec "$HOME/git/hackdeck/bin/hackdeck" "$@"\n' > "$SK/.local/bin/hackdeck"
chmod 755 "$SK/.local/bin/hackdeck"
python3 - "$HOME/.config/hackdeck/settings.json" "$SK/.config/hackdeck/settings.json" "$OS_BOOKS" <<'PY'
import json, os, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
s["template"] = "~/git/Hacking-Op"
s["books"] = sys.argv[3].split()   # USB で読むコマンド帳（hackdeck の設定「読むコマンド帳」）
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
json.dump(s, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY

# ブログの「物理アクセス」の2本を、オフラインで読めるように
install -D -m 644 "$BLOG/2026-11-13-chntpw.md" "$SK/Documents/物理アクセス/Windows にログイン（chntpw）.md"
install -D -m 644 "$BLOG/2026-11-13-shadow.md" "$SK/Documents/物理アクセス/Linux にログイン（passwd --root）.md"

# 版ごとの部品を上から重ねる
if [ -d "$FL/includes.chroot" ]; then cp -a "$FL/includes.chroot/." "$IC/"; fi
if [ -d "$FL/skel" ]; then cp -a "$FL/skel/." "$SK/"; fi
if [ -f "$FL/zshrc.append" ]; then cat "$FL/zshrc.append" >> "$SK/.zshrc"; fi

# 7. 秘密が紛れていないか（ISO は暗号化されないので、ここに鍵やトークンを入れない）
if grep -rIlE 'BEGIN [A-Z ]*PRIVATE KEY|wpscan-api-token' "$V" | grep -v '/git/hackdeck/' | head -5 | grep .; then
  echo "[!] 秘密らしき物がある。止める" >&2; exit 1
fi
[ ! -e "$SK/.config/hackdeck/wpscan-api-token" ] || { echo "[!] WPScan のトークンが入っている" >&2; exit 1; }

# 8. 壊れた symlink を外す（cp -rTL が実体をたどれず、ビルドごと止まるため）。生きている symlink は実ファイルに化けるだけ
find "$V" -xtype l -print -delete | sed 's/^/[?] 壊れた symlink を外した: /'

log "組み立てた: $V（$(du -sh "$V" | cut -f1)）"
