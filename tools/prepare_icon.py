#!/usr/bin/env python3
"""Turns the designer's rounded-corner icon artwork (docs/icon-master.png) into App Store icons:
square, full-bleed, no alpha (iOS applies its own corner mask). The white corners and the light
rim of the rounded square are replaced by extending the neighbouring background, then the dark
and tinted iOS 18+ variants are derived from it."""
import pathlib
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "docs" / "icon-master.png"
OUT = ROOT / "ZIKR" / "Assets.xcassets" / "AppIcon.appiconset"

img = np.asarray(Image.open(MASTER).convert("RGB")).astype(np.float32)
h, w, _ = img.shape
# Interior = not near-white; then erode to drop the anti-aliased edge and the light rim.
inside = img.min(axis=2) < 235
ys, xs = np.where(inside)
top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
mask_img = Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(23))
valid = np.asarray(mask_img) > 0

# Flood the invalid pixels with the average of already-valid neighbours until everything is filled.
filled = img * valid[..., None]
known = valid.astype(np.float32)
for _ in range(400):
    if known.min() > 0:
        break
    s = np.zeros_like(filled); c = np.zeros_like(known)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        s += np.roll(np.roll(filled, dy, 0), dx, 1)
        c += np.roll(np.roll(known, dy, 0), dx, 1)
    grow = (known == 0) & (c > 0)
    filled[grow] = s[grow] / c[grow][:, None]
    known[grow] = 1

# Soften the filled band slightly so no seams show at the iOS mask edge.
result = Image.fromarray(filled.clip(0, 255).astype(np.uint8))
blurred = result.filter(ImageFilter.GaussianBlur(6))
band = Image.fromarray(((~valid) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
result = Image.composite(blurred, result, band)

# Crop to the rounded square's box (a few px inside the rim) and size for the App Store.
inset = 6
square = result.crop((left + inset, top + inset, right - inset, bottom - inset)).resize((1024, 1024), Image.LANCZOS)
square.save(OUT / "AppIcon.png")

arr = np.asarray(square).astype(np.float32)
lum = arr @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
# Dark: keep the bright artwork (beads, gold), push the green background towards near-black.
bright = np.clip((lum - 60) / 120, 0, 1)[..., None]
dark = arr * (0.35 + 0.65 * bright) * np.array([0.85, 0.95, 0.95])
Image.fromarray(dark.clip(0, 255).astype(np.uint8)).save(OUT / "AppIcon-Dark.png")
# Tinted: greyscale on black; iOS tints by luminance.
tint = np.clip((lum - 40) * 1.25, 0, 255)
Image.fromarray(tint.astype(np.uint8)).convert("RGB").save(OUT / "AppIcon-Tinted.png")
print("icons written from", MASTER.name)
