#!/usr/bin/env bash
# ch4n24n-os のビルドのうち、root で動かす部分。ch4n24n-os build が sudo で呼ぶ
# 使い方: sudo bash build-root.sh <作業ディレクトリ> <ユーザ名> [版（ch4n24n）]
set -euo pipefail
W=$1
U=$2
F=${3:-ch4n24n}   # 版。variant と hostname の名前になる
[ "$(id -u)" -eq 0 ] || { echo "[!] root で動かす（ch4n24n-os build から呼ぶ）" >&2; exit 1; }

# 終わり方に関わらず、終了コードを残す（Claude の見張りが、これを見て続きに進む）
mkdir -p "$W/out" "$W/logs"
status=$W/logs/build.status
rm -f "$status"
finish() {
  local rc=$?
  echo "$rc $(date -Is)" > "$status"
  chown -R "$U:" "$W/out" "$W/logs" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then echo "[+] ビルドが終わった。続きは Claude が署名と VM での確認をする"
  else echo "[!] 失敗した（rc=$rc）。ログ: $W/out/*.log（無ければ、この端末の上のほう）"; fi
}
trap finish EXIT

# ビルドと署名に要る物（無ければ入れる）
need=(live-build cdebootstrap sbsigntool mokutil)
missing=()
for p in "${need[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "[*] 入れる: ${missing[*]}"
  # 今の PC の apt の設定に、署名の切れたリポジトリなどがあっても止まらない（入れるのに要るのは Kali の一覧だけ。
  # 2026-11-14 に /etc/apt/sources.list の stretch/updates が「not signed」で update を失敗させ、ここで止まった）
  apt-get update -qq || echo "[?] apt-get update でエラーのリポジトリがある（ビルドには関係ないので続ける）"
  apt-get install -y "${missing[@]}"
fi

cd "$W/kali-live"
./build.sh --variant "$F" --hostname "$F" --version "$(date +%Y%m%d)" --output "$W/out"
