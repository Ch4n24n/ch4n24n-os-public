#!/usr/bin/env python3
"""desktop ツールの gsettings.tsv を、dconf のシステム DB 用のキーファイルに写す。

使い方: gsettings2dconf.py <gsettings.tsv> <overrides.ini> <出力> [版の overrides.ini ...]
- スキーマのパスは、このマシンの /usr/share/glib-2.0/schemas/*.gschema.xml から引く
  （org.freedesktop.ibus.general が /desktop/ibus/general/ のように、ID とパスが違うものがあるため）
- コマンドに vdictate を含むカスタムショートカットは写さない（USB に音声入力は入れない）
- overrides.ini の値で上書き・追加する（版の overrides.ini があれば、その後にさらに重ねる）
"""
import glob
import re
import sys
import xml.etree.ElementTree as ET

SKIP_CMD = re.compile(r"vdictate")


def schema_paths():
    m = {}
    for f in glob.glob("/usr/share/glib-2.0/schemas/*.gschema.xml"):
        try:
            for s in ET.parse(f).getroot().iter("schema"):
                if s.get("path"):
                    m[s.get("id")] = s.get("path")
        except ET.ParseError:
            pass
    return m


def read_tsv(tsv, paths):
    rows = []
    for line in open(tsv, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        schema, key, value = parts[0], parts[1], parts[2]
        if ":/" in schema:
            path = schema.split(":", 1)[1]
        else:
            path = paths.get(schema)
        if not path:
            print(f"[!] パスが分からない: {schema}（写さない）", file=sys.stderr)
            continue
        rows.append((path, key, value))
    return rows


def main(tsv, ovr, out, *more):
    rows = read_tsv(tsv, schema_paths())
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
        f.write("# Ch4n24n OS: ~/git/tools/desktop/gsettings.tsv と share/dconf-overrides.ini から生成（手で直さない）\n")
        for g, kv in groups.items():
            f.write(f"\n[{g}]\n")
            for k, v in kv.items():
                f.write(f"{k}={v}\n")
    print(f"[+] dconf: {sum(len(v) for v in groups.values())} キー / {len(groups)} 区分（vdictate のショートカット {len(drop)} 個は外した）")


if __name__ == "__main__":
    main(*sys.argv[1:])
