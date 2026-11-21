#!/usr/bin/env python3
"""Builds the App Icon set from the master artwork (docs/icon-alternative-no-letter.png: a string of
beads, no letters). The dark and tinted variants (iOS 18+) are recoloured from the same pixels, so
all three share the exact geometry and anti-aliasing."""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "docs" / "icon-alternative-no-letter.png"
OUT = ROOT / "ZIKR" / "Assets.xcassets" / "AppIcon.appiconset"

# Reference colours sampled from the master artwork.
BG = (24, 96, 78)        # green background (centre of the radial gradient)
BEAD = (232, 227, 205)   # cream beads
GOLD = (196, 160, 88)    # gold beads and tassel


def weights(px):
    """Soft membership of a pixel in (background, bead, gold) by inverse colour distance."""
    ds = [sum((a - b) ** 2 for a, b in zip(px, ref)) + 1 for ref in (BG, BEAD, GOLD)]
    inv = [1 / d ** 1.5 for d in ds]
    s = sum(inv)
    return [x / s for x in inv]


def recolour(img, bg_fn, bead, gold):
    src = img.convert("RGB")
    w, h = src.size
    out = Image.new("RGB", (w, h))
    sp, op = src.load(), out.load()
    cache = {}
    for y in range(h):
        for x in range(w):
            px = sp[x, y]
            k = cache.get(px)
            if k is None:
                k = cache[px] = weights(px)
            bg = bg_fn(x, y, w, h)
            op[x, y] = tuple(int(k[0] * bg[i] + k[1] * bead[i] + k[2] * gold[i]) for i in range(3))
    return out


def radial(inner, outer):
    def fn(x, y, w, h):
        t = min(1.0, ((x - w / 2) ** 2 + (y - h / 2) ** 2) ** 0.5 / (w * 0.71))
        return tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
    return fn


master = Image.open(MASTER).convert("RGB").resize((1024, 1024), Image.LANCZOS)
master.save(OUT / "AppIcon.png")
recolour(master, radial((22, 40, 34), (6, 10, 9)), bead=(226, 221, 200), gold=(214, 180, 108)).save(OUT / "AppIcon-Dark.png")
recolour(master, lambda *_: (0, 0, 0), bead=(200, 200, 200), gold=(255, 255, 255)).save(OUT / "AppIcon-Tinted.png")
print("icons written")
