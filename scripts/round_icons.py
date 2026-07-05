#!/usr/bin/env python3
"""Apply anti-aliased rounded corners to dropweb desktop app icons.

Owner spec: radius 26 at the 128px reference size, scaled proportionally
(radius = round(size * 26 / 128)) for every output size. Android is EXCLUDED
(adaptive icons are masked by the launcher itself).

Master source: assets/images/icon.png (converted to RGBA). Every output is
derived by LANCZOS-resizing the master to the target size, then applying a
per-size rounded-rect alpha mask (4x supersampled then downscaled for
anti-aliasing). Corners become fully transparent (alpha=0).

Outputs (relative to repo root):
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16,32,64,128,256,512,1024}.png
  assets/images/icon.png                       (1024, RGBA, rounded)
  windows/runner/resources/app_icon.ico        (sizes 256/128/64/48/32/16)
  /tmp/icons_proof.png                          (original vs rounded @256, side-by-side)

Deterministic: same input -> same output. No network, no randomness.

Usage:
  python3 scripts/round_icons.py            # run from repo root
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER_PATH = os.path.join(REPO, "assets", "images", "icon.png")

REF_SIZE = 128
REF_RADIUS = 26
SUPERSAMPLE = 4

MACOS_DIR = os.path.join(
    REPO, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_PATH = os.path.join(REPO, "windows", "runner", "resources", "app_icon.ico")
ICO_SIZES = [256, 128, 64, 48, 32, 16]


def radius_for(size: int) -> int:
    """Proportional corner radius for a given icon edge size."""
    return round(size * REF_RADIUS / REF_SIZE)


def rounded_mask(size: int, radius: int) -> Image.Image:
    """Anti-aliased L-mode rounded-rect mask (supersampled then downscaled)."""
    hi = size * SUPERSAMPLE
    mask_hi = Image.new("L", (hi, hi), 0)
    draw = ImageDraw.Draw(mask_hi)
    draw.rounded_rectangle(
        (0, 0, hi - 1, hi - 1), radius=radius * SUPERSAMPLE, fill=255
    )
    return mask_hi.resize((size, size), Image.Resampling.LANCZOS)


def round_icon(master: Image.Image, size: int) -> Image.Image:
    """Resize master to `size` and apply the per-size rounded alpha mask."""
    img = master.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = rounded_mask(size, radius_for(size))
    # Multiply existing alpha by the mask so corners go fully transparent.
    r, g, b, a = img.split()
    a = Image.composite(a, Image.new("L", img.size, 0), mask)
    img.putalpha(a)
    return img


def main() -> None:
    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.size != (1024, 1024):
        master = master.resize((1024, 1024), Image.Resampling.LANCZOS)

    # macOS appiconset (7 sizes, 1:1 filename -> dimension).
    for size in MACOS_SIZES:
        out = round_icon(master, size)
        out.save(os.path.join(MACOS_DIR, f"app_icon_{size}.png"))
        print(f"macos app_icon_{size}.png radius={radius_for(size)}")

    # Master brand icon (1024) -> RGBA rounded, feeds linux + release logo.
    round_icon(master, 1024).save(MASTER_PATH)
    print(f"assets/images/icon.png radius={radius_for(1024)}")

    # Windows .ico: PIL derives all sizes from one rounded RGBA image.
    ico_master = round_icon(master, 256)
    ico_master.save(ICO_PATH, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"windows app_icon.ico sizes={ICO_SIZES}")

    # Visual proof: original (square) vs rounded, at 256px.
    _write_proof(master, round_icon(master, 256))


def _write_proof(master: Image.Image, rounded256: Image.Image) -> None:
    gap = 16
    checker = Image.new("RGBA", (256 * 2 + gap, 256), (48, 48, 48, 255))
    orig = master.resize((256, 256), Image.Resampling.LANCZOS).convert("RGBA")
    checker.alpha_composite(orig, (0, 0))
    checker.alpha_composite(rounded256, (256 + gap, 0))
    checker.convert("RGBA").save("/tmp/icons_proof.png")
    print("proof /tmp/icons_proof.png")


if __name__ == "__main__":
    main()
