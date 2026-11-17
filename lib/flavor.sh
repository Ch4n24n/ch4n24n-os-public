#!/usr/bin/env bash
# OS の名前と作業場所。bin・lib のスクリプトが、HERE（ch4n24n-os/）を決めてから source する
FLAVOR=${CH4N24N_OS_FLAVOR:-ch4n24n}
BRAND_ARGS=()   # branding/render.py に渡す（印・字・色）
GRUB_ACCENT=""  # 起動メニューの選んだ行の色（R,G,B）。空なら Kali のまま
case "$FLAVOR" in
  ch4n24n)
    OS_NAME="Ch4n24n OS"; OS_SLUG=ch4n24n-os; OS_USER=kali; XFER_LABEL=CH4N24N ;;
  *) echo "[!] 知らない版: $FLAVOR（ch4n24n）" >&2; exit 1 ;;
esac
FL=$HERE/flavors/$FLAVOR   # 版ごとの部品（無い物は足さない）
W=${CH4N24N_OS_WORK:-$HOME/work/$OS_SLUG}
export CH4N24N_OS_FLAVOR=$FLAVOR CH4N24N_OS_WORK=$W
