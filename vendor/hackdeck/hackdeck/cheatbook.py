"""コマンド帳の読み込み・変数の依存の順・置き換え。

コマンド帳は、ツールの books/ の中のフォルダ1つが1冊（paths.BOOKS_DIR。中に cheats/*.cheat と opts/*.tsv）。読むのは設定の
books に名前を書いた本（ON にした本）だけ（今の PC は ctf、USB の OS は physical のように、使う場所で選ぶ。2026-11-15）。
読む順は名前の順（設定の画面の並びと同じ）。コマンドはどれのものも並べ、同じ名前の $ の定義と opts は、名前の順で後の本が勝つ。本は1冊だけで動くように作る（変数の定義も本ごとに持つ。check が本ごとに確かめる）"""
from contextlib import contextmanager

from .paths import BOOKS_DIR
from .text import DOLLAR_RE, VAR_RE
from . import settings


_BOOK_DIRS = {}   # 読む本の名前 → コマンド帳のフォルダ（1回の窓の中では、設定が変わらなければ同じ）
_ONLY = None      # 点検が本を1冊ずつ読むときだけ、設定の books の代わりに使う名前（only_books）


def all_books():
    """books/ の中の本の名前（設定の画面の「未選択」と、本ごとの点検に使う）"""
    return sorted(p.name for p in BOOKS_DIR.iterdir() if p.is_dir()) if BOOKS_DIR.is_dir() else []


def book_about(name):
    """本の用途（books/<本>/about.txt の1行目。設定の画面の列に出す。2026-11-15、本人「使用用途を列に書いてくれないと
    わからない」）"""
    try:
        return (BOOKS_DIR / name / "about.txt").read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, IndexError):
        return ""


@contextmanager
def only_books(names):
    """その間だけ、設定の books ではなく names の本を読む（点検が1冊ずつ確かめるため）"""
    global _ONLY
    _ONLY = tuple(names)
    try:
        yield
    finally:
        _ONLY = None


def book_dirs():
    """読むコマンド帳のフォルダ（名前の順。books/ に無い名前は飛ばす）"""
    books = _ONLY if _ONLY is not None else tuple(settings.get("books"))
    if books not in _BOOK_DIRS:
        dirs = []
        for b in sorted(set(books)):
            p = BOOKS_DIR / b
            if b and "/" not in b and p.is_dir() and p not in dirs:
                dirs.append(p)
        _BOOK_DIRS[books] = dirs
    return list(_BOOK_DIRS[books])


_OPTS = {}   # コマンド帳のフォルダの並び → opts の一覧（1回の窓の中では変わらないので、探し直さない）


def opts_files():
    """opts の一覧 {名前: ファイル}（同じ名前は、あとのコマンド帳のもの）。窓を開くたびに流れの図のために何十回も呼ばれ、
    そのたびにフォルダを探し直していた（窓を開くのが 0.2 秒ほど遅れていた。2026-11-01）ので、フォルダの並びごとに覚える"""
    dirs = tuple(book_dirs())
    if dirs not in _OPTS:
        _OPTS[dirs] = {f.stem: f for d in dirs for f in sorted((d / "opts").glob("*.tsv"))}
    return _OPTS[dirs]


def opts_file(name):
    """opts/<name>.tsv（無ければ None）"""
    return opts_files().get(name)


def book_label(f):
    """コマンド帳のファイルの、画面と点検に出す名前（books/ からの場所。例 ctf/cheats/01-探索.cheat）"""
    return f.relative_to(BOOKS_DIR).as_posix()


def var_names_in(text):
    """<var> の出現順・重複なしの一覧"""
    return list(dict.fromkeys(VAR_RE.findall(text)))


VAR_DESCS = {}   # 変数ごとの、何を入れるかの説明（00-vars.cheat の ? の行。parse_cheat_files が読む）


def parse_cheat_files():
    """コマンド帳の cheats/*.cheat を読む。navi は使わず自分で解釈する。
    戻り値: (エントリの一覧 [{tag, comment, command, where}], 変数定義 {名前: (候補コマンド, where, 例)})
    % は見出し（複数タグをカンマ区切りで持てるが、表示にそのまま使うだけ）。@ vars は読まない
    （$ 定義は 00-vars.cheat 1か所に集め、全ファイルから共通に見える前提で作っているため。自分のコマンド帳の $ の定義も、
    どのファイルからも見える）。
    `$` 定義の直後の行が `! ` で始まれば、それを「この変数にどんな値を入れるか」の例として読む
    （2026-10-28、「オプションを設定する際に、どういった値を入れることが期待されているのか知るために
    例があると嬉しい」との指摘で追加。候補が無い＝その場で打つ変数ほど効く）。`? ` で始まれば、何を入れるかの説明
    （VAR_DESCS。2026-10-30、本人の指摘「IP を入れるのかホストを入れるのか、ホストの中でも DC なのかが分からない」）"""
    entries, defs = {}, {}
    VAR_DESCS.clear()
    tag = ""
    for f in [f for d in book_dirs() for f in sorted((d / "cheats").glob("*.cheat"))]:
        lines = f.read_text(encoding="utf-8").splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("% "):
                tag = line[2:].strip()
            elif line.startswith("$ "):
                name, _, rest = line[2:].partition(":")
                example, desc = "", ""
                for nxt in lines[i + 1:i + 3]:   # 直後の2行まで（! 例・? 説明）
                    if nxt.startswith("! "):
                        example = example or nxt[2:].strip()
                    elif nxt.startswith("? "):
                        desc = desc or nxt[2:].strip()
                    else:
                        break
                defs[name.strip()] = (rest.strip(), f"{book_label(f)}:{i + 1}", example)
                VAR_DESCS[name.strip()] = desc
            elif line.startswith("#"):
                comment = line[1:].strip()
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                if nxt and not nxt.startswith(("%", "#", "$", "@", ";")):
                    entries[(tag, comment, nxt)] = {"tag": tag, "comment": comment, "command": nxt,
                                                      "where": f"{book_label(f)}:{i + 2}"}
            i += 1
    return list(entries.values()), defs


def var_deps(cmd):
    """この $ 定義のコマンド文字列が、他のどの変数の値を先に要るか（<var> と $var の両方）"""
    return [d for d in var_names_in(cmd) + DOLLAR_RE.findall(cmd)]


def compute_var_order(template, defs):
    """template の <var> を、依存（その定義の中でさらに使われている変数）を先に解決する順で返す。
    依存の輪があれば RuntimeError（check が検出する）"""
    order, visiting, done = [], set(), set()

    def visit(name):
        if name in done or name in order:
            return
        if name in visiting:
            raise RuntimeError(f"変数の依存が循環している: {name}")
        visiting.add(name)
        cmd, _, _ = defs.get(name, ("", "", ""))
        for d in var_deps(cmd):
            if d != name:
                visit(d)
        visiting.discard(name)
        done.add(name)
        order.append(name)

    for name in var_names_in(template):
        visit(name)
    return order


def substitute(text, resolved):
    """resolved: [(名前, 値), ...]。text 中の <名前> をそれぞれの値に置き換える（バックスラッシュも安全）"""
    mapping = dict(resolved)
    return VAR_RE.sub(lambda m: mapping.get(m.group(1), m.group(0)), text)
