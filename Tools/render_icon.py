#!/usr/bin/env python3
"""Renders Hardset's app icon, concept A "The Single".

A flat `canvas` tile carrying a tall condensed slab "1" in `chalk` (the measured single, the only
figure the app calls High) and, at its baseline, a small `chalkDim` "≈" whose height is 28/88 of
the "1"'s: the estimate ceiling against the monument. Drawn as polygons, not font text, so the
output is identical on any machine. Palette from DESIGN.md.

Usage:
  uv run --with pillow==11.3.0 python3 -I Tools/render_icon.py            render + previews
  uv run --with pillow==11.3.0 python3 -I Tools/render_icon.py --check    verify, exit non-zero on failure

Writes Hardset/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (Contents.json is not touched)
and squircle-masked previews at 29 and 60 px on black and white into docs/release/icon-previews/.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Hardset/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
PREVIEWS = ROOT / "docs/release/icon-previews"

SS = 4096            # drawing size
OUT = 1024           # delivered size
K = SS / OUT         # design units are 1024-px units

CANVAS = "#050608"
CHALK = "#F3F3F5"
CHALK_DIM = "#B6B8C3"

MIN_STROKE = 72.0    # px at 1024, which is 2 px at 29
MIN_CONTRAST = 7.0

# --- Geometry, in 1024-px units -------------------------------------------------------------
H = 800.0                        # glyph height of the "1"
STEM_W = 150.0
FOOT_W, FOOT_H = 330.0, 84.0
FLAG_ANGLE = math.radians(35)    # flag descends to the left at this angle below horizontal
FLAG_LEN, FLAG_T = 150.0, 84.0   # flag length along its axis, thickness across it
EST_H = H * 28 / 88              # the "≈" envelope: the estimate ceiling against the monument
WAVE_T = 80.0                    # vertical thickness of each tilde band
WAVE_P = 36.0                    # peak-to-peak of the tilde
WAVE_W = 280.0                   # width of the "≈"
GAP_X = 56.0                     # foot to "≈"
WAVE_STEPS = 96

GROUP_W = FOOT_W + GAP_X + WAVE_W
FOOT_X0 = (OUT - GROUP_W) / 2
Y_TOP = (OUT - H) / 2
Y_BASE = Y_TOP + H               # the shared baseline


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def one_parts():
    """The "1" as convex polygons that overlap into one shape."""
    stem_x = FOOT_X0 + (FOOT_W - STEM_W) / 2
    stem = [(stem_x, Y_TOP), (stem_x + STEM_W, Y_TOP), (stem_x + STEM_W, Y_BASE), (stem_x, Y_BASE)]
    foot = [(FOOT_X0, Y_BASE - FOOT_H), (FOOT_X0 + FOOT_W, Y_BASE - FOOT_H),
            (FOOT_X0 + FOOT_W, Y_BASE), (FOOT_X0, Y_BASE)]
    d = (-math.cos(FLAG_ANGLE), math.sin(FLAG_ANGLE))
    n = (math.sin(FLAG_ANGLE), math.cos(FLAG_ANGLE))
    p0 = (stem_x + 1.0, Y_TOP)
    p1 = (p0[0] + FLAG_LEN * d[0], p0[1] + FLAG_LEN * d[1])
    flag = [p0, p1, (p1[0] + FLAG_T * n[0], p1[1] + FLAG_T * n[1]),
            (p0[0] + FLAG_T * n[0], p0[1] + FLAG_T * n[1])]
    return {"stem": stem, "foot": foot, "flag": flag}


def tilde_curves(y_center, x0):
    top, bottom = [], []
    for i in range(WAVE_STEPS + 1):
        u = i / WAVE_STEPS
        x = x0 + WAVE_W * u
        yc = y_center - (WAVE_P / 2) * math.sin(2 * math.pi * u)
        top.append((x, yc - WAVE_T / 2))
        bottom.append((x, yc + WAVE_T / 2))
    return top, bottom


def approx_parts():
    x0 = FOOT_X0 + FOOT_W + GAP_X
    gap = EST_H - 2 * WAVE_T - WAVE_P          # vertical gap between the two bands
    lower_c = Y_BASE - WAVE_P / 2 - WAVE_T / 2
    upper_c = lower_c - WAVE_T - gap
    bands = []
    for yc in (upper_c, lower_c):
        top, bottom = tilde_curves(yc, x0)
        bands.append(top + bottom[::-1])
    return bands, gap


# --- Measurement ----------------------------------------------------------------------------
def convex_min_width(pts):
    best = float("inf")
    for i in range(len(pts)):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % len(pts)]
        ex, ey = bx - ax, by - ay
        ln = math.hypot(ex, ey)
        ext = max(abs((px - ax) * ey - (py - ay) * ex) / ln for px, py in pts)
        best = min(best, ext)
    return best


def point_to_polyline(p, line):
    best = float("inf")
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        ex, ey = bx - ax, by - ay
        t = max(0.0, min(1.0, ((p[0] - ax) * ex + (p[1] - ay) * ey) / (ex * ex + ey * ey)))
        best = min(best, math.hypot(p[0] - (ax + t * ex), p[1] - (ay + t * ey)))
    return best


def band_min_width():
    best = float("inf")
    for yc in (0.0,):
        top, bottom = tilde_curves(yc, 0.0)
        for p in top:
            best = min(best, point_to_polyline(p, bottom))
        for p in bottom:
            best = min(best, point_to_polyline(p, top))
    return best


def strokes():
    parts = one_parts()
    result = {name: convex_min_width(pts) for name, pts in parts.items()}
    result["tilde band"] = band_min_width()
    return result


def luminance(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# --- Rendering ------------------------------------------------------------------------------
def render():
    img = Image.new("RGB", (SS, SS), rgb(CANVAS))
    d = ImageDraw.Draw(img)
    for pts in one_parts().values():
        d.polygon([(x * K, y * K) for x, y in pts], fill=rgb(CHALK))
    bands, _ = approx_parts()
    for pts in bands:
        d.polygon([(x * K, y * K) for x, y in pts], fill=rgb(CHALK_DIM))
    return img.resize((OUT, OUT), Image.LANCZOS)


def squircle_mask(size, n=5.0, ss=8):
    big = size * ss
    m = Image.new("L", (big, big), 0)
    px = m.load()
    c = (big - 1) / 2
    r = big / 2
    for y in range(big):
        dy = abs(y - c) / r
        for x in range(big):
            if (abs(x - c) / r) ** n + dy ** n <= 1.0:
                px[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)


def previews(icon):
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    written = []
    for size in (29, 60):
        tile = icon.resize((size, size), Image.LANCZOS)
        mask = squircle_mask(size)
        for name, bg in (("black", "#000000"), ("white", "#FFFFFF")):
            pad = size // 2
            canvas = Image.new("RGB", (size + 2 * pad, size + 2 * pad), rgb(bg))
            canvas.paste(tile, (pad, pad), mask)
            real = PREVIEWS / f"icon-{size}-on-{name}.png"
            canvas.save(real, "PNG")
            big = PREVIEWS / f"icon-{size}-on-{name}-x8.png"
            canvas.resize((canvas.width * 8, canvas.height * 8), Image.NEAREST).save(big, "PNG")
            written += [real, big]
    return written


# --- Check ----------------------------------------------------------------------------------
def check():
    failures = []

    def need(ok, msg):
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            failures.append(msg)

    if not ICON.exists():
        print("FAIL  missing", ICON)
        return 1
    img = Image.open(ICON)
    need(img.size == (1024, 1024), f"size {img.size}")
    need(img.mode == "RGB", f"mode {img.mode}, no alpha")
    if img.mode == "RGB":
        px = img.load()
        corners = [px[0, 0], px[1023, 0], px[0, 1023], px[1023, 1023]]
        need(all(c == rgb(CANVAS) for c in corners), f"corners {corners} == {rgb(CANVAS)}")
        need(list(img.getdata()) == list(render().getdata()), "pixels equal a fresh deterministic render")
    widths = strokes()
    for name, w in widths.items():
        print(f"      stroke {name}: {w:.1f} px at 1024 ({w * 29 / 1024:.2f} px at 29)")
    narrowest = min(widths.values())
    need(narrowest >= MIN_STROKE, f"narrowest stroke {narrowest:.1f} px >= {MIN_STROKE:.0f}")
    _, gap = approx_parts()
    print(f"      tilde gap {gap:.1f} px, estimate height {EST_H:.1f} px = 28/88 of {H:.0f}")
    for label, colour in (("1 (chalk)", CHALK), ("≈ (chalkDim)", CHALK_DIM)):
        ratio = contrast(colour, CANVAS)
        need(ratio >= MIN_CONTRAST, f"contrast {label} on tile {ratio:.2f}:1 >= {MIN_CONTRAST:.0f}:1")
    return 1 if failures else 0


def main():
    if "--check" in sys.argv[1:]:
        sys.exit(check())
    icon = render()
    icon.save(ICON, "PNG", optimize=True)
    print("wrote", ICON.relative_to(ROOT))
    for p in previews(icon):
        print("wrote", p.relative_to(ROOT))


main()
