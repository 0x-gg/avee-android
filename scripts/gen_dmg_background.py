#!/usr/bin/env python3
"""Generate the macOS DMG installer background (assets/dmg/background.png).

Deterministic (no randomness) so the committed PNG can be regenerated verbatim
by anyone with Pillow installed:

    python3 scripts/gen_dmg_background.py

Design language mirrors the app's dark-only "Lumina" system (see
lib/common/lumina.dart): a near-black base, two soft gold accent glows, and a
neutral drag arrow pointing from the app icon toward the Applications symlink.
No text is drawn so the artwork is locale-safe.

Geometry: the DMG Finder window is 660x400 pt. We render at @2x (1320x800 px)
and tag the PNG with 144 dpi metadata so Finder scales it back to 660x400 pt.
create-dmg places the app icon center at (165, 200) pt and the Applications
drop link at (495, 200) pt; at 128 pt icon size each spans +/-64 pt. The arrow
therefore lives in the clear gap between them (roughly x 245..415 pt), rendered
at @2x below.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# ---- Canvas ---------------------------------------------------------------
SCALE = 2  # @2x retina render
W, H = 660 * SCALE, 400 * SCALE  # 1320 x 800
DPI = (72 * SCALE, 72 * SCALE)  # (144, 144) -> Finder renders at 660x400 pt

# ---- Brand palette (dropweb greens) ---------------------------------------
# Sourced from the theme header `fidelity,#15803D,#009938,#2BFF7A,4`.
BASE = (0x0A, 0x0F, 0x0B)  # green-tinted near-black base #0A0F0B
GREEN_MID = (0x00, 0x99, 0x38)  # primary accent #009938 (bottom-right glow)
GREEN_BRIGHT = (0x2B, 0xFF, 0x7A)  # bright accent #2BFF7A (top-left glow)
ARROW = (0xFF, 0xFF, 0xFF)  # white — every foreground element stays light


def _radial_glow(size, center, radius, color, peak_alpha):
    """A soft circular glow as an RGBA layer.

    Drawn as a filled circle then Gaussian-blurred so the edge falls off
    smoothly; peak_alpha caps the opacity at the center (0-255).
    """
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = center
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=color + (peak_alpha,),
    )
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def _arrow_layer(size):
    """Horizontal drag arrow: rounded shaft + triangular head, gray + alpha."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    y = 200 * SCALE  # icon center line
    x_start = 250 * SCALE  # just right of the app icon (edge at 229 pt)
    x_head = 408 * SCALE  # just left of Applications (edge at 431 pt)
    shaft_end = x_head - 18 * SCALE  # shaft stops before the head tip
    alpha = 217  # ~85% opacity
    rgba = ARROW + (alpha,)

    # Shaft with rounded end caps.
    draw.line([(x_start, y), (shaft_end, y)], fill=rgba, width=6 * SCALE)
    cap = 3 * SCALE
    for x in (x_start, shaft_end):
        draw.ellipse([x - cap, y - cap, x + cap, y + cap], fill=rgba)

    # Triangular head.
    hh = 16 * SCALE  # half-height
    draw.polygon(
        [(x_head, y), (shaft_end, y - hh), (shaft_end, y + hh)],
        fill=rgba,
    )
    return layer


def build():
    img = Image.new("RGB", (W, H), BASE)

    # Green accent glow anchored bottom-right, brighter echo top-left.
    br = _radial_glow(
        (W, H), (W - 40 * SCALE, H - 20 * SCALE), 260 * SCALE, GREEN_MID, 34)
    tl = _radial_glow(
        (W, H), (60 * SCALE, 40 * SCALE), 200 * SCALE, GREEN_BRIGHT, 18)
    img = Image.alpha_composite(img.convert("RGBA"), br)
    img = Image.alpha_composite(img, tl)

    # Drag arrow between the two icon slots.
    img = Image.alpha_composite(img, _arrow_layer((W, H)))

    out = Path(__file__).resolve().parent.parent / "assets" / "dmg" / "background.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", dpi=DPI)
    print(f"wrote {out} ({W}x{H} @ {DPI[0]}dpi)")


if __name__ == "__main__":
    build()
