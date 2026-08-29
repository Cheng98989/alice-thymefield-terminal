# -*- coding: utf-8 -*-
"""Turn a hand-edited PNG back into a fastfetch .txt logo.

    python logo-from-png.py character.png character.txt

Usually you do not call this directly: "fastfetch icon <file.png>" runs it for
you, drops the result next to the picture and updates config.jsonc.

No resampling and no colour reduction: pixels land in the .txt one by one,
exactly as drawn. Height must be even (each text cell holds two vertical
pixels); an odd one gets a transparent row appended at the bottom. Alpha
below 128 counts as transparent.

Afterwards update "width" and "height" in config.jsonc with the values
printed here.
"""
import os, sys
from PIL import Image

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".txt"

img = Image.open(src).convert("RGBA")
w, h = img.size
if h % 2:
    n = Image.new("RGBA", (w, h + 1), (0, 0, 0, 0)); n.paste(img, (0, 0)); img, h = n, h + 1
px = img.load()

out = []
for y in range(0, h, 2):
    buf, cf, cb = [], None, None
    for x in range(w):
        t, b = px[x, y], px[x, y + 1]
        ts, bs = t[3] >= 128, b[3] >= 128
        if not ts and not bs:
            if cf or cb:
                buf.append("\033[0m"); cf = cb = None
            buf.append(" "); continue
        if ts and bs:   f, bg, ch = t[:3], b[:3], "\u2580"
        elif ts:        f, bg, ch = t[:3], None, "\u2580"
        else:           f, bg, ch = b[:3], None, "\u2584"
        if f != cf:
            buf.append("\033[38;2;%d;%d;%dm" % f); cf = f
        if bg != cb:
            buf.append(("\033[48;2;%d;%d;%dm" % bg) if bg else "\033[49m"); cb = bg
        buf.append(ch)
    out.append("".join(buf) + "\033[0m")
while out and not out[0].strip("\033[0m "): out.pop(0)
while out and not out[-1].strip("\033[0m "): out.pop()

open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
used = {px[x, y][:3] for y in range(h) for x in range(w) if px[x, y][3] >= 128}
# Absolute paths, so it is always obvious which file was read and where the
# result landed - the usual mistake is running this from the wrong directory.
print("read   %s" % os.path.abspath(src))
print("wrote  %s   (%d colours)" % (os.path.abspath(dst), len(used)))
print()
print('In config.jsonc, set  "width": %d, "height": %d' % (w, len(out)))
print('(or let "fastfetch icon" do it)')
