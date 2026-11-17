#!/usr/bin/env bash
# ch4n24n-os を入れる: ~/.local/bin/ch4n24n-os に symlink を張るだけ（sudo は使わない）
# ビルドに要る live-build などは、ch4n24n-os build が sudo のときに無ければ入れる
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
mkdir -p "$BIN"
ln -sfn "$HERE/bin/ch4n24n-os" "$BIN/ch4n24n-os"
echo "[+] $BIN/ch4n24n-os -> $HERE/bin/ch4n24n-os"
mkdir -p "$HOME/.config/ch4n24n-os"
chmod 700 "$HOME/.config/ch4n24n-os"
echo "[+] ~/.config/ch4n24n-os（Secure Boot の署名の鍵の置き場。リポジトリには入れない）"
