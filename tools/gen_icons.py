#!/usr/bin/env python3
"""Draws the dark and tinted App Icon variants (iOS 18+) in the same geometry as AppIcon.png."""
import math
import pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "ZIKR" / "Assets.xcassets" / "AppIcon.appiconset"
S = 1024
SCALE = 4  # supersampling for smooth edges


def draw(bg, bead, bead_ring, gold, glyph, gradient=None):
    size = S * SCALE
    img = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(img)
    if gradient:
        inner, outer = gradient
        for r in range(size // 2, 0, -8):
            t = r / (size / 2)
            color = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
            d.ellipse([size / 2 - r * 1.42, size / 2 - r * 1.42, size / 2 + r * 1.42, size / 2 + r * 1.42], fill=color)
    c = size / 2
    ring = 315 * SCALE
    br = 30 * SCALE
    for i in range(33):
        a = -math.pi / 2 + i * 2 * math.pi / 33
        x, y = c + math.cos(a) * ring, c + math.sin(a) * ring
        fill = gold if i == 25 else bead
        d.ellipse([x - br, y - br, x + br, y + br], fill=fill)
        d.ellipse([x - br * 0.82, y - br * 0.82, x + br * 0.82, y + br * 0.82], outline=bead_ring, width=int(2.2 * SCALE))
    # "Z" as a polygon so no font is needed.
    w, h, t = 150 * SCALE, 170 * SCALE, 30 * SCALE
    x0, y0 = c - w / 2, c - h / 2
    d.polygon([(x0, y0), (x0 + w, y0), (x0 + w, y0 + t), (x0 + t * 1.25, y0 + h - t), (x0 + w, y0 + h - t),
               (x0 + w, y0 + h), (x0, y0 + h), (x0, y0 + h - t), (x0 + w - t * 1.25, y0 + t), (x0, y0 + t)], fill=glyph)
    return img.resize((S, S), Image.LANCZOS)


draw(bg=(10, 16, 14), bead=(54, 140, 108), bead_ring=(10, 16, 14), gold=(222, 188, 116), glyph=(236, 232, 214),
     gradient=((22, 40, 34), (8, 13, 11))).save(OUT / "AppIcon-Dark.png")
draw(bg=(0, 0, 0), bead=(150, 150, 150), bead_ring=(0, 0, 0), gold=(255, 255, 255), glyph=(255, 255, 255)).save(OUT / "AppIcon-Tinted.png")
print("icons written")
