#!/usr/bin/env python3
"""ブランドの画像を作る: アイコン（PNG）・壁紙・GRUB の背景。
使い方: render.py <出力ディレクトリ> [--svg 印] [--name 名前] [--font 字] [--fg R,G,B] [--bg R,G,B] [--sub 下の字]
既定は Ch4n24n OS（branding/icon.svg・ch4n24n-mark の Caveat Brush・ピンク）。版は lib/flavor.sh の BRAND_ARGS で替える。
icon.svg は librsvg（GNOME と同じ描画）で描く。"""
import argparse
import os
import gi
gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg
import cairo
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.expanduser("~/git/tools/ch4n24n-mark/share/CaveatBrush-Regular.ttf")
BG, PINK, GRAY = (21, 21, 27), (196, 64, 116), (150, 150, 160)


def rgb(s):
    return tuple(int(v) for v in s.split(","))


def svg_png(svg, size, out):
    h = Rsvg.Handle.new_from_file(svg)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    vp = Rsvg.Rectangle(); vp.x = vp.y = 0; vp.width = vp.height = size
    h.render_document(cairo.Context(surf), vp)
    surf.write_to_png(out)


def scene(a, w, h, icon_px, out, sub=None, top=None):
    """top を渡すと、アイコンだけを上から top（高さの割合）に置く（起動メニューの背景。字はメニューの題が出す）"""
    img = Image.new("RGB", (w, h), a.bg)
    tmp = out + ".icon.png"
    svg_png(a.svg, icon_px, tmp)
    ic = Image.open(tmp).convert("RGBA"); os.remove(tmp)
    y = int(h * top) if top is not None else h // 2 - icon_px // 2 - h // 12
    img.paste(ic, ((w - icon_px) // 2, y), ic)
    if top is not None:
        img.save(out)
        return
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(a.font, icon_px // 3)
    tw = d.textlength(a.name, font=f)
    d.text(((w - tw) / 2, y + icon_px + icon_px // 10), a.name, font=f, fill=a.fg)
    if sub:
        fs = ImageFont.truetype(a.font, icon_px // 7)
        sw = d.textlength(sub, font=fs)
        d.text(((w - sw) / 2, y + icon_px + icon_px // 10 + icon_px // 3 + icon_px // 12), sub, font=fs, fill=GRAY)
    img.save(out)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--svg", default=os.path.join(HERE, "icon.svg"))
    p.add_argument("--name", default="Ch4n24n OS")
    p.add_argument("--font", default=FONT)
    p.add_argument("--fg", type=rgb, default=PINK)
    p.add_argument("--bg", type=rgb, default=BG)
    p.add_argument("--sub", default="based on Kali Linux")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for s in (48, 128, 256):
        svg_png(a.svg, s, os.path.join(a.out, f"icon-{s}.png"))
    scene(a, 1920, 1080, 300, os.path.join(a.out, "wallpaper.png"), sub=a.sub)
    # 起動メニューの背景: メニューの題（GRUB は上から 31%、isolinux は 40% ほど）より上の空きに、アイコンだけを置く
    scene(a, 1024, 768, 140, os.path.join(a.out, "splash.png"), top=0.08)      # GRUB（UEFI）
    scene(a, 640, 480, 104, os.path.join(a.out, "splash-640.png"), top=0.10)   # isolinux（古い BIOS）


if __name__ == "__main__":
    main()
