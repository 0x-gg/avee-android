#!/usr/bin/env python3
"""Generate the macOS DMG installer background (assets/dmg/background.png).

Deterministic (no randomness) so the committed PNG can be regenerated verbatim
by anyone with Pillow installed:

    python3 scripts/gen_dmg_background.py

Light direction: a clean near-white background lets Finder render its
(hardcoded black) icon labels natively and readably, so no baked label pads or
custom art are needed. A single black hugeicons-style drag arrow points from
the app icon toward the Applications symlink. No text is drawn so the artwork
is locale-safe.

Geometry: the DMG Finder window is 660x400 pt. We render at @2x (1320x800 px)
and tag the PNG with 144 dpi metadata so Finder scales it back to 660x400 pt.
create-dmg places the app icon center at (165, 200) pt and the Applications
drop link at (495, 200) pt; the arrow lives in the clear gap between them.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# ---- Canvas ---------------------------------------------------------------
SCALE = 2  # @2x retina render
W, H = 660 * SCALE, 400 * SCALE  # 1320 x 800
DPI = (72 * SCALE, 72 * SCALE)  # (144, 144) -> Finder renders at 660x400 pt

# ---- Palette --------------------------------------------------------------
BASE = (0xF7, 0xF9, 0xF7)  # near-white #F7F9F7, a hair off pure white
ARROW = (0x1C, 0x1C, 0x1E)  # near-black #1C1C1E hugeicons-style stroke


def _stroke(draw, p0, p1, width, fill):
    """A single round-capped stroke: the line plus a disc at each endpoint."""
    draw.line([p0, p1], fill=fill, width=width)
    r = width // 2
    for x, y in (p0, p1):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def _arrow_layer(size):
    """hugeicons-style drag arrow: horizontal shaft + chevron ">" head.

    Stroke-based with round caps/joins (not a filled triangle). Coordinates
    are already @2x pixels; supersampled 4x then downscaled for clean AA.
    """
    ss = 4
    layer = Image.new("RGBA", (size[0] * ss, size[1] * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    width = 14 * ss
    fill = ARROW + (255,)
    tip = (790 * ss, 400 * ss)

    _stroke(draw, (500 * ss, 400 * ss), tip, width, fill)  # shaft
    _stroke(draw, tip, (730 * ss, 340 * ss), width, fill)  # chevron upper
    _stroke(draw, tip, (730 * ss, 460 * ss), width, fill)  # chevron lower

    return layer.resize(size, Image.Resampling.LANCZOS)


def build():
    img = Image.new("RGB", (W, H), BASE).convert("RGBA")
    img = Image.alpha_composite(img, _arrow_layer((W, H)))

    out = Path(__file__).resolve().parent.parent / "assets" / "dmg" / "background.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", dpi=DPI)
    print(f"wrote {out} ({W}x{H} @ {DPI[0]}dpi)")


if __name__ == "__main__":
    build()
