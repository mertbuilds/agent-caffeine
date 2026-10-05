#!/usr/bin/env python3
"""Rebuilds the image layer of Caffeinagent/AppIcon.icon from the icon master.

Run from the repo root:

    uv run --with pillow --with numpy --with scipy python scripts/build-app-icon.py

The master (assets/AppIcon-4096.png) draws the blue tile with its own corner
shape and a transparent margin. macOS 26 puts an icon like that on a gray
plate. The layer is the same tile scaled to fill the canvas, with the outer
rim cut off and the blue carried out to the canvas edge, so the system can
apply its own shape. The robot keeps its share of the tile.
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/AppIcon-4096.png"
LAYER = ROOT / "Caffeinagent/AppIcon.icon/Assets/tile.png"

SIZE = 1024
WORK = 2048
# Share of the tile width that is cut off at the edge: the part of the baked
# rim that follows the old corner shape.
RIM = 0.036

master = Image.open(MASTER).convert("RGBA")
ys, xs = np.where(np.asarray(master)[..., 3] > 128)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
# The tile is a little wider than tall. A square box of the width keeps the
# proportions, and the fill below covers the strips above and below.
side = x1 - x0
cy = (y0 + y1) / 2
tile = master.resize((WORK, WORK), Image.LANCZOS, box=(x0, cy - side / 2, x1, cy + side / 2))

pixels = np.asarray(tile).astype(np.float32)
rgb, alpha = pixels[..., :3], pixels[..., 3]
keep = ndimage.distance_transform_edt(alpha > 250) > RIM * WORK
# Each pixel outside takes the colour of the nearest kept pixel, then a blur
# that grows with the distance takes the streaks out.
dist, nearest = ndimage.distance_transform_edt(~keep, return_indices=True)
fill = rgb[nearest[0], nearest[1]]
soft = np.stack([ndimage.gaussian_filter(fill[..., c], WORK * 0.02) for c in range(3)], -1)
w = np.clip(dist / (WORK * 0.03), 0, 1)[..., None]
w = w * w * (3 - 2 * w)
out = np.where(keep[..., None], rgb, fill * (1 - w) + soft * w)

LAYER.parent.mkdir(parents=True, exist_ok=True)
result = Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB")
result.resize((SIZE, SIZE), Image.LANCZOS).save(LAYER, optimize=True)
print(f"wrote {LAYER.relative_to(ROOT)}")
