#!/usr/bin/env python3
"""Renders Hardset's interim app icon: a front-on machine weight stack with one selector pin.

Geometric only, drawn at 4x and downsampled for clean edges. Palette from DESIGN.md.
A stand-in until the final icon is chosen; replace AppIcon-1024.png when it is.

Usage: uv run --with pillow python3 -I Tools/render_interim_icon.py \
         Hardset/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
import sys
from PIL import Image, ImageDraw

S = 4096
OUT = sys.argv[1]

def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def vertical_gradient(w, h, top, bottom):
    strip = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        strip.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return strip.resize((w, h))

def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m

img = vertical_gradient(S, S, rgb("#202026"), rgb("#0A0A0C"))
d = ImageDraw.Draw(img)

plates, selected = 6, 3
plate_w, plate_h = int(S * 0.62), int(S * 0.078)
gap = int(S * 0.020)
radius = int(plate_h * 0.26)
stack_h = plates * plate_h + (plates - 1) * gap
x0 = (S - plate_w) // 2
y0 = (S - stack_h) // 2 + int(S * 0.025)

# Guide rod behind the stack, rising above the top plate.
rod_w = int(S * 0.036)
d.rounded_rectangle([S // 2 - rod_w // 2, y0 - int(S * 0.085), S // 2 + rod_w // 2, y0 + stack_h],
                    radius=rod_w // 2, fill=rgb("#3A3A42"))

plate_face = vertical_gradient(plate_w, plate_h, rgb("#44444D"), rgb("#2B2B31"))
plate_mask = rounded_mask(plate_w, plate_h, radius)
shadow = Image.new("RGB", (plate_w, plate_h), rgb("#060607"))

for i in range(plates):
    py = y0 + i * (plate_h + gap)
    img.paste(shadow, (x0, py + int(S * 0.008)), plate_mask)
    img.paste(plate_face, (x0, py), plate_mask)
    # A one-pixel (at 1024) machined highlight along the top edge, kept clear of the corners.
    d.rectangle([x0 + radius, py + int(S * 0.002), x0 + plate_w - radius, py + int(S * 0.005)],
                fill=rgb("#5A5A64"))
    hole = int(plate_h * 0.28)
    cy = py + plate_h // 2
    d.ellipse([S // 2 - hole, cy - hole, S // 2 + hole, cy + hole], fill=rgb("#16161A"))

# The selector pin: a cyan shank from the hole to a ringed head past the plate's centre.
py = y0 + selected * (plate_h + gap)
cy = py + plate_h // 2
head = int(plate_h * 0.66)
shank_len = int(S * 0.165)
shank_h = int(plate_h * 0.30)
d.rounded_rectangle([S // 2, cy - shank_h // 2, S // 2 + shank_len, cy + shank_h // 2],
                    radius=shank_h // 2, fill=rgb("#46B4C6"))
hx = S // 2 + shank_len
d.ellipse([hx - head, cy - head, hx + head, cy + head], fill=rgb("#2A8796"))
inner = int(head * 0.80)
d.ellipse([hx - inner, cy - inner, hx + inner, cy + inner], fill=rgb("#5ED3E6"))
dot = int(head * 0.24)
d.ellipse([hx - dot, cy - dot, hx + dot, cy + dot], fill=rgb("#2A8796"))

img.resize((1024, 1024), Image.LANCZOS).save(OUT, "PNG", optimize=True)
img.resize((120, 120), Image.LANCZOS).save(OUT.replace(".png", "-120.png"), "PNG")
print("wrote", OUT)
