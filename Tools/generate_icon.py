#!/usr/bin/env python3
"""Regenerate the app icon.

The icon is geometry rather than commissioned art, and it is generated rather than drawn so it
stays honest to the locked palette: the two colours below are `Tokens.Color.ground` and
`Tokens.Color.accent`, and if those ever move, this is a one-line change rather than a trip through
a design tool. Same reasoning as `generate_project.py` — the artefact is derived, so the derivation
is the source.

Two constraints that are not stylistic:

  * **Opaque, no alpha channel.** iOS rejects an app icon with transparency at upload. The image is
    composited on `GROUND` and saved as RGB, never RGBA.
  * **Supersampled.** Drawing at 4x and downsampling with LANCZOS is what keeps the rounded ends
    clean; drawing at 1024 directly leaves visible stair-stepping on the shaft.

Run:  python3 Tools/generate_icon.py
"""

from PIL import Image, ImageDraw

SIZE = 1024
SUPERSAMPLE = 4
GROUND = (0x08, 0x0A, 0x0E, 255)   # Tokens.Color.ground
INK = (0xF5, 0xF5, 0xF7, 255)      # Tokens.Color.accent, which is Tokens.Color.textPrimary

OUT = "Hardset/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

# Proportions of the full canvas. The mark spans ~0.70 of the width, which is the usual optical
# fill for an iOS icon once the system's rounded-rect mask is applied.
SHAFT_W, SHAFT_H = 0.354, 0.061
COLLAR_W, COLLAR_H = 0.050, 0.177
PLATE_W, PLATE_H = 0.061, 0.354
GAP = 0.031


def main() -> None:
    canvas = SIZE * SUPERSAMPLE
    image = Image.new("RGBA", (canvas, canvas), GROUND)
    draw = ImageDraw.Draw(image)
    cx = cy = canvas // 2

    def px(fraction: float) -> int:
        return int(canvas * fraction)

    def bar(x0: int, y0: int, x1: int, y1: int, radius: int) -> None:
        draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=INK)

    shaft_w, shaft_h = px(SHAFT_W), px(SHAFT_H)
    collar_w, collar_h = px(COLLAR_W), px(COLLAR_H)
    plate_w, plate_h = px(PLATE_W), px(PLATE_H)
    gap = px(GAP)

    bar(cx - shaft_w // 2, cy - shaft_h // 2, cx + shaft_w // 2, cy + shaft_h // 2, shaft_h // 2)

    for sign in (-1, 1):
        collar_outer = cx + sign * (shaft_w // 2 + gap)
        collar_inner = collar_outer + sign * collar_w
        x0, x1 = sorted((collar_outer, collar_inner))
        bar(x0, cy - collar_h // 2, x1, cy + collar_h // 2, collar_w // 3)

        plate_outer = collar_inner + sign * gap
        plate_inner = plate_outer + sign * plate_w
        x0, x1 = sorted((plate_outer, plate_inner))
        bar(x0, cy - plate_h // 2, x1, cy + plate_h // 2, plate_w // 3)

    # RGB, not RGBA: an icon with an alpha channel is rejected at upload.
    image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB").save(OUT, "PNG")
    print(f"wrote {OUT} ({SIZE}x{SIZE}, RGB)")


if __name__ == "__main__":
    main()
