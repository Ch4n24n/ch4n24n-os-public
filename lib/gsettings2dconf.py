#!/usr/bin/env python3
"""マシンの台帳（~/src/local/machine の Ansible）の GNOME の設定を、dconf のシステム DB 用のキーファイルに写す。

使い方: gsettings2dconf.py <group_vars/all.yml> <overrides.ini> <出力> [版の overrides.ini ...]
- 読むのは all.yml の gnome_dconf（{key: dconf のパス, value: gsettings get の形の値} の並び。役割 gnome_settings が実機に書く物と同じ）
  2026-11-23 まで読んでいた desktop ツールの gsettings.tsv は、ここに移った
- コマンドに vdictate を含むカスタムショートカットは写さない（USB に音声入力は入れない）
- overrides.ini の値で上書き・追加する（版の overrides.ini があれば、その後にさらに重ねる）
"""
import re
import sys

import yaml

SKIP_CMD = re.compile(r"vdictate")


def read_vars(path):
    # (区分のパス（末尾に /）, キー, 値) の並びにする。/org/gnome/desktop/interface/gtk-theme → (/org/gnome/desktop/interface/, gtk-theme, …)
    rows = []
    for item in (yaml.safe_load(open(path, encoding="utf-8")) or {}).get("gnome_dconf") or []:
        full, value = str(item["key"]), str(item["value"])
        if "{{" in value:
            print(f"[!] 値が Ansible の変数を使っている: {full}（写さない）", file=sys.stderr)
            continue
        p, _, k = full.rpartition("/")
        rows.append((p + "/", k, value))
    if not rows:
        sys.exit(f"[!] {path} に gnome_dconf が無い")
    return rows


def main(src, ovr, out, *more):
    rows = read_vars(src)
    drop = {p for p, k, v in rows if k == "command" and SKIP_CMD.search(v)}
    groups = {}
    for p, k, v in rows:
        if p in drop:
            continue
        if k == "custom-keybindings":
            keep = [i for i in re.findall(r"'([^']*)'", v) if i not in drop]
            v = "[" + ", ".join(f"'{i}'" for i in keep) + "]"
        groups.setdefault(p.strip("/"), {})[k] = v
    for o in (ovr, *more):
        cur = None
        for line in open(o, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                cur = line[1:-1].strip("/")
                groups.setdefault(cur, {})
                continue
            k, v = line.split("=", 1)
            groups[cur][k.strip()] = v.strip()
    with open(out, "w", encoding="utf-8") as f:
        f.write("# Ch4n24n OS: ~/src/local/machine/ansible/group_vars/all.yml の gnome_dconf と share/dconf-overrides.ini から生成（手で直さない）\n")
        for g, kv in groups.items():
            f.write(f"\n[{g}]\n")
            for k, v in kv.items():
                f.write(f"{k}={v}\n")
    print(f"[+] dconf: {sum(len(v) for v in groups.values())} キー / {len(groups)} 区分（vdictate のショートカット {len(drop)} 個は外した）")


if __name__ == "__main__":
    main(*sys.argv[1:])
