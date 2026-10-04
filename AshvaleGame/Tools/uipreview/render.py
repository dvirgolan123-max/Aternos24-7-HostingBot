#!/usr/bin/env python3
"""Renders the UI layout dumps (ui_*.json) to PNGs at 2x and reports text that
overflows its label. Backdrops come from the headless game renders."""
import glob, json, os, sys
from PIL import Image, ImageDraw, ImageFont

out_dir, frames_dir = sys.argv[1], sys.argv[2]
S = 2  # pixels per point
FONTS = {
    "regular": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "bold": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "monobold": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
}
_cache = {}
def font(size, weight, mono):
    bold = weight >= 0.3
    key = ("mono" if mono else "") + ("bold" if bold else "regular") if mono else ("bold" if bold else "regular")
    key = {"monoregular": "mono"}.get(key, key)
    path = FONTS.get(key, FONTS["regular"])
    k = (path, round(size * S))
    if k not in _cache:
        _cache[k] = ImageFont.truetype(path, max(1, round(size * S * 0.92)))
    return _cache[k]

BACKDROPS = {"fp": "game_fp_rifle.png", "tp": "game_tp_rifle.png", "menu": "town_street.png"}

def col(c, alpha=1.0):
    return tuple(int(max(0, min(1, v)) * 255) for v in c[:3]) + (int(max(0, min(1, c[3] * alpha)) * 255),)

def text_width(runs_line):
    w = 0
    for t, f, kern in runs_line:
        for ch in t:
            w += f.getlength(ch) + kern * S
    return w

def layout_lines(runs, max_w, wrap):
    """Splits styled runs into lines (explicit newlines, optional word wrap)."""
    lines, cur = [], []
    for r in runs:
        f = font(r["size"], r["weight"], r["mono"])
        parts = r["text"].split("\n")
        for i, part in enumerate(parts):
            if i > 0:
                lines.append(cur); cur = []
            if not wrap:
                cur.append((part, f, r["kern"], r))
                continue
            words = part.split(" ")
            for j, wd in enumerate(words):
                piece = wd if j == 0 else " " + wd
                trial = cur + [(piece, f, r["kern"], r)]
                if cur and text_width([(t, ff, k) for t, ff, k, _ in trial]) > max_w:
                    lines.append(cur); cur = [(wd, f, r["kern"], r)]
                else:
                    cur.append((piece, f, r["kern"], r))
    lines.append(cur)
    return lines

def render(path):
    doc = json.load(open(path))
    W, H = int(doc["width"] * S), int(doc["height"] * S)
    img = Image.new("RGBA", (W, H), (8, 9, 10, 255))
    bd = BACKDROPS.get(doc["backdrop"])
    if bd and os.path.exists(os.path.join(frames_dir, bd)):
        b = Image.open(os.path.join(frames_dir, bd)).convert("RGBA").resize((W, H))
        img.alpha_composite(b)
    issues = []
    for n in doc["nodes"]:
        x, y, w, h = n["x"] * S, n["y"] * S, n["w"] * S, n["h"] * S
        if w <= 0 or h <= 0:
            continue
        cx, cy, cw, ch = [v * S for v in n["clip"]]
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        a = n["alpha"]
        r = n.get("radius", 0) * S
        box = [x, y, x + w - 1, y + h - 1]
        if "gradient" in n and n["gradient"]["colors"]:
            g = n["gradient"]; cols = g["colors"]
            sx, sy = g["start"]; ex, ey = g["end"]
            steps = 48
            for i in range(steps):
                t0, t1 = i / steps, (i + 1) / steps
                tt = (t0 + t1) / 2 * (len(cols) - 1)
                k = min(int(tt), len(cols) - 2) if len(cols) > 1 else 0
                f = tt - k
                c = [cols[k][j] * (1 - f) + cols[min(k + 1, len(cols) - 1)][j] * f for j in range(4)]
                if abs(ex - sx) >= abs(ey - sy):
                    xa = x + w * (sx + (ex - sx) * t0); xb = x + w * (sx + (ex - sx) * t1)
                    d.rectangle([min(xa, xb), y, max(xa, xb), y + h], fill=col(c, a))
                    if i == steps - 1 and ex < 1: d.rectangle([x + w * ex, y, x + w, y + h], fill=col(cols[-1], a))
                    if i == 0 and sx > 0: d.rectangle([x, y, x + w * sx, y + h], fill=col(cols[0], a))
                else:
                    ya = y + h * (sy + (ey - sy) * t0); yb = y + h * (sy + (ey - sy) * t1)
                    d.rectangle([x, min(ya, yb), x + w, max(ya, yb)], fill=col(c, a))
                    if i == steps - 1 and ey < 1: d.rectangle([x, y + h * ey, x + w, y + h], fill=col(cols[-1], a))
                    if i == 0 and sy > 0: d.rectangle([x, y, x + w, y + h * sy], fill=col(cols[0], a))
        if "bg" in n and n["bg"][3] > 0:
            d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), fill=col(n["bg"], a))
        if "border" in n:
            bw = max(1, round(n["border"][0] * S))
            d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), outline=col(n["border"][1:], a), width=bw)
        if "segments" in n:
            items = n["segments"]["items"]; sel = n["segments"]["selected"]
            d.rounded_rectangle(box, radius=8, fill=(60, 60, 64, int(220 * a)))
            sw = w / max(1, len(items))
            for i, it in enumerate(items):
                if i == sel:
                    d.rounded_rectangle([x + i * sw + 2, y + 2, x + (i + 1) * sw - 2, y + h - 2], radius=7, fill=(219, 158, 61, int(255 * a)))
                f = font(11, 0.4, False)
                tw = f.getlength(it)
                d.text((x + i * sw + (sw - tw) / 2, y + h / 2 - 11 * S * 0.5), it, font=f, fill=(255, 255, 255, int(255 * a)))
                if tw > sw - 4: issues.append(f"segment '{it}' overflows ({tw / S:.0f}pt > {sw / S:.0f}pt)")
        if "switch" in n:
            on = n["switch"]
            d.rounded_rectangle(box, radius=h / 2, fill=(219, 158, 61, int(255 * a)) if on else (90, 90, 95, int(255 * a)))
            kx = x + w - h + 2 if on else x + 2
            d.ellipse([kx, y + 2, kx + h - 4, y + h - 2], fill=(255, 255, 255, int(255 * a)))
        if "slider" in n:
            t = n["slider"]; my = y + h / 2
            d.rounded_rectangle([x, my - 2, x + w, my + 2], radius=2, fill=(110, 110, 115, int(255 * a)))
            d.rounded_rectangle([x, my - 2, x + w * t, my + 2], radius=2, fill=(219, 158, 61, int(255 * a)))
            d.ellipse([x + w * t - 13, my - 13, x + w * t + 13, my + 13], fill=(255, 255, 255, int(255 * a)))
        if n.get("image"):
            d.rectangle(box, outline=(200, 200, 200, int(120 * a)))
        if "text" in n:
            tx = n["text"]
            wrap = tx["lines"] != 1
            lines = layout_lines(tx["runs"], w, wrap)
            if tx["lines"] > 0:
                lines = lines[:tx["lines"]]
            heights = [max([f.size for _, f, _, _ in ln] or [12]) * 1.25 for ln in lines]
            total = sum(heights)
            yy = y + (h - total) / 2
            if total > h + 2 * S:
                issues.append(f"text clipped vertically: '{tx['runs'][0]['text'][:40]}' needs {total / S:.0f}pt in {h / S:.0f}pt")
            for ln, lh in zip(lines, heights):
                lw = text_width([(t, f, k) for t, f, k, _ in ln])
                if lw > w + 2 * S and not tx["shrink"]:
                    issues.append(f"text overflows width: '{''.join(t for t, _, _, _ in ln)[:50]}' needs {lw / S:.0f}pt in {w / S:.0f}pt")
                scale = min(1, w / lw) if tx["shrink"] and lw > 0 else 1
                al = tx["align"]
                xx = x if al in (0, 4) else (x + (w - lw * scale) / 2 if al == 1 else x + w - lw * scale)
                for t, f, k, rr in ln:
                    ff = font(rr["size"] * scale, rr["weight"], rr["mono"]) if scale < 1 else f
                    for chh in t:
                        d.text((xx, yy + (lh - ff.size * 1.15)), chh, font=ff, fill=col(rr["color"], a))
                        xx += ff.getlength(chh) + k * S * scale
                yy += lh
        # Apply clip.
        if cw > 0 and ch > 0:
            mask = Image.new("L", (W, H), 0)
            ImageDraw.Draw(mask).rectangle([cx, cy, cx + cw, cy + ch], fill=255)
            clipped = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            clipped.paste(layer, (0, 0), mask)
            layer = clipped
        img.alpha_composite(layer)
    # Safe area guides.
    t, l, b, rr = [v * S for v in doc["safe"]]
    g = ImageDraw.Draw(img)
    if l > 0: g.line([(l, 0), (l, H)], fill=(255, 0, 255, 90), width=1)
    if rr > 0: g.line([(W - rr, 0), (W - rr, H)], fill=(255, 0, 255, 90), width=1)
    if b > 0: g.line([(0, H - b), (W, H - b)], fill=(255, 0, 255, 90), width=1)
    png = path.replace(".json", ".png")
    img.convert("RGB").save(png)
    return png, issues

for p in sorted(glob.glob(os.path.join(out_dir, "ui_*.json"))):
    png, issues = render(p)
    print(os.path.basename(png), "OK" if not issues else "")
    for i in sorted(set(issues)):
        print("   ", i)
