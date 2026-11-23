#!/usr/bin/env python3
"""今の PC の ~/.zshrc（chezmoi の原本 ~/src/local/dotfiles の dot_zshrc を chezmoi cat で書き出した物）を、USB 用に手当てして写す。

使い方: patch-zshrc.py <元の .zshrc> <出力>
USB に無い物（pyenv・vhack）を呼ぶ行に「あれば」のガードを付け、ビルドするユーザの home の絶対パスを $HOME にする。
元の .zshrc は書き換えない。毎回ここから作り直すので、メイン PC で .zshrc を変えれば次のビルドで揃う。
"""
import os
import sys

HOME = os.path.expanduser("~")

LINES = {
    'eval "$(pyenv init -)"': 'command -v pyenv >/dev/null && eval "$(pyenv init -)"',
    'eval "$(pyenv virtualenv-init -)"': 'command -v pyenv >/dev/null && eval "$(pyenv virtualenv-init -)"',
    'source "$HOME/.local/bin/vhack.zsh"': '[ -f "$HOME/.local/bin/vhack.zsh" ] && source "$HOME/.local/bin/vhack.zsh"',
}


def main(src, dst):
    out, hit = [], set()
    for line in open(src, encoding="utf-8").read().split("\n"):
        s = line.strip()
        if s in LINES:
            line = line.replace(s, LINES[s])
            hit.add(s)
        if HOME + "/" in line:
            line = line.replace(HOME + "/", "$HOME/")
            hit.add("$HOME")
        out.append(line)
    head = "# Ch4n24n OS: メイン PC の ~/.zshrc を USB 用に手当てした写し（lib/patch-zshrc.py が生成）\n"
    open(dst, "w", encoding="utf-8").write(head + "\n".join(out))
    for s in LINES:
        if s not in hit:
            print(f"[?] .zshrc に無かった（手当て不要）: {s}", file=sys.stderr)
    print(f"[+] .zshrc: {len(hit)} 種類の行を手当てした")


if __name__ == "__main__":
    main(*sys.argv[1:3])
