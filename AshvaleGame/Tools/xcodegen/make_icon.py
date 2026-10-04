#!/usr/bin/env python3
"""Paints the Ashvale app icon (1024x1024, opaque): dusk sky, pale sun,
a dead power line and a black pine treeline."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
img = Image.new("RGB", (S, S))
px = img.load()
top, mid, low = (14, 18, 22), (58, 52, 44), (196, 120, 46)
for y in range(S):
    t = y / S
    if t < 0.62:
        k = t / 0.62
        c = tuple(int(top[i] + (mid[i] - top[i]) * k ** 1.4) for i in range(3))
    else:
        k = (t - 0.62) / 0.38
        c = tuple(int(mid[i] + (low[i] - mid[i]) * k ** 0.8) for i in range(3))
    for x in range(S):
        px[x, y] = c

# Sun with soft glow.
glow = Image.new("RGB", (S, S), (0, 0, 0))
gd = ImageDraw.Draw(glow)
cx, cy = 600, 560
for r in range(330, 0, -6):
    a = (1 - r / 330) ** 2
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(int(220 * a), int(150 * a), int(70 * a)))
base = img.load()
g = glow.load()
for y in range(S):
    for x in range(S):
        r0, g0, b0 = base[x, y]
        r1, g1, b1 = g[x, y]
        base[x, y] = (min(255, r0 + r1), min(255, g0 + g1), min(255, b0 + b1))
d = ImageDraw.Draw(img)
d.ellipse([cx - 120, cy - 120, cx + 120, cy + 120], fill=(238, 206, 150))

# Fog bands.
fog = Image.new("L", (S, S), 0)
fd = ImageDraw.Draw(fog)
for i, yy in enumerate([700, 760, 820]):
    fd.rectangle([0, yy, S, yy + 26], fill=40 - i * 8)
fog = fog.filter(ImageFilter.GaussianBlur(18))
img = Image.composite(Image.new("RGB", (S, S), (200, 170, 130)), img, fog)
d = ImageDraw.Draw(img)

# Power line pole and sagging cables.
pole = (12, 12, 14)
d.polygon([(250, 260), (268, 260), (300, 900), (276, 900)], fill=pole)
d.rectangle([180, 300, 350, 316], fill=pole)
for x0, y0 in [(190, 316), (338, 316)]:
    pts = [(x0 + (S - x0) * t, y0 + 120 * math.sin(math.pi * t) * 0.9 + 40 * t) for t in [i / 40 for i in range(41)]]
    d.line(pts, fill=pole, width=5)

# Pine treeline.
rng = random.Random(7)
def pine(x, base_y, h, w):
    layers = 7
    for i in range(layers):
        t = i / layers
        ww = w * (1 - t * 0.85)
        y = base_y - h * t
        d.polygon([(x - ww, y), (x + ww, y), (x, y - h * 0.32)], fill=(6, 8, 8))
    d.rectangle([x - w * 0.08, base_y - 10, x + w * 0.08, S], fill=(6, 8, 8))
for i in range(28):
    x = rng.uniform(-40, S + 40)
    h = rng.uniform(220, 470)
    pine(x, S - rng.uniform(0, 60), h, h * 0.22)
d.rectangle([0, S - 70, S, S], fill=(6, 8, 8))
img.save(out)
print("wrote", out)
