#!/usr/bin/env python3
"""kali-live の auto/config を Ch4n24n OS 用に書き換える（prepare が、git で元に戻してから毎回当てる）。

使い方: patch-autoconfig.py <kali-live/auto/config> [OS の名前（既定 Ch4n24n OS）]
- 圧縮を zstd に（既定の xz より解凍が速い。lb_config(1) の --chroot-squashfs-compression-type）
- 起動の引数に、時刻帯・キー配列（US＋CapsLock→Ctrl）を足す（live-config の timezone / keyboard-*）
- splash を外す（Kali の起動画面のテーマ kali は script 型で、保存領域のパスフレーズの問い合わせを描かない。
  2026-11-14 の VM で、竜の画面のまま入力欄が見えなかった。外すと文字の画面で問い合わせが見える）
- インストーラを外す（USB で起動して使うだけなので要らない）
- ISO の名前を OS の名前に
1つでも当たらなければ止まる（kali-live が変わったら、ここを直す）
"""
import sys

def rules(name):
    return [
    ("lb_opts+=(--debian-installer live)", "lb_opts+=(--debian-installer none)"),
    ('--iso-application "Kali Linux"', f'--iso-application "{name}"'),
    ('--iso-publisher "Kali"', '--iso-publisher "Ch4n24n"'),
    ('--iso-volume "Kali Live"', f'--iso-volume "{name}"'),
    ('--bootappend-live "boot=live components quiet splash noeject"',
     '--bootappend-live "boot=live components quiet noeject timezone=Asia/Tokyo keyboard-layouts=us keyboard-options=ctrl:nocaps"'),
    ('  "${lb_opts[@]}" \\\n', '  --chroot-squashfs-compression-type zstd \\\n  "${lb_opts[@]}" \\\n'),
]


def main(path, name="Ch4n24n OS"):
    t = open(path, encoding="utf-8").read()
    RULES = rules(name)
    for old, new in RULES:
        if t.count(old) != 1:
            sys.exit(f"[!] auto/config に当たらない（{t.count(old)} 箇所）: {old.strip()}")
        t = t.replace(old, new)
    open(path, "w", encoding="utf-8").write(t)
    print(f"[+] auto/config: {len(RULES)} 箇所を書き換えた")


if __name__ == "__main__":
    main(*sys.argv[1:3])
