# -*- coding: utf-8 -*-
"""Extract the editable PNG out of a fastfetch .txt logo.

    python logo-to-png.py character.txt character.png [zoom]

The .txt uses half blocks: U+2580 with fg = upper pixel and bg = lower pixel,
U+2584 with fg = lower pixel and the upper one transparent. This walks that
backwards and recovers the real pixel grid (width = columns, height = rows*2).
With zoom > 1 the PNG comes out nearest-neighbour enlarged, handy for a look;
use zoom 1 when you intend to edit it and feed it back in.
"""
import os, re, sys
from PIL import Image

TOK = re.compile(r"\033\[([0-9;]*)m")
src  = sys.argv[1]
dst  = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".png"
zoom = int(sys.argv[3]) if len(sys.argv) > 3 else 1

lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
grid = []
for line in lines:
    top, bot, fg, bg, pos = [], [], None, None, 0

    def emit(chunk):
        for c in chunk:
            if c == "\u2580":
                top.append(fg); bot.append(bg)
            elif c == "\u2584":
                top.append(None); bot.append(fg)
            else:
                top.append(None); bot.append(None)

    for m in TOK.finditer(line):
        emit(line[pos:m.start()])
        p = (m.group(1) or "0").split(";")
        i = 0
        while i < len(p):
            v = p[i] or "0"
            if v == "0":                       fg = bg = None
            elif v == "49":                    bg = None
            elif v in ("38", "48") and i + 4 < len(p) and p[i+1] == "2":
                col = tuple(int(x) for x in p[i+2:i+5])
                if v == "38": fg = col
                else:         bg = col
                i += 4
            i += 1
        pos = m.end()
    emit(line[pos:])
    grid.append(top); grid.append(bot)

w = max(len(r) for r in grid)
img = Image.new("RGBA", (w, len(grid)), (0, 0, 0, 0))
px = img.load()
for y, row in enumerate(grid):
    for x, c in enumerate(row):
        if c:
            px[x, y] = (*c, 255)
if zoom > 1:
    img = img.resize((w * zoom, len(grid) * zoom), Image.Resampling.NEAREST)
img.save(dst)
print("%s -> %s  (%dx%d pixel%s)" % (os.path.basename(src), os.path.basename(dst),
                                     w, len(grid), ", zoom %dx" % zoom if zoom > 1 else ""))
