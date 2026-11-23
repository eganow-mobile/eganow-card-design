"""Crop the network logos to their alpha bounding box plus a 2px margin, in place.

Run from the project root: PYTHONPATH=tool python3 tool/trim_logos.py
Idempotent: a trimmed file trims to itself.
"""
import numpy as np
from png_tool import read_png, write_png

LOGOS = ['assets/images/logo_visa.png', 'assets/images/logo_mastercard.png']
MARGIN = 2


def trim(path):
    img = read_png(path)
    assert img.shape[2] == 4, 'expected RGBA'
    ys, xs = np.nonzero(img[:, :, 3])
    y0, y1 = max(ys.min() - MARGIN, 0), min(ys.max() + MARGIN + 1, img.shape[0])
    x0, x1 = max(xs.min() - MARGIN, 0), min(xs.max() + MARGIN + 1, img.shape[1])
    out = np.zeros((y1 - y0 + 0, x1 - x0, 4), dtype=np.uint8)
    out[:] = img[y0:y1, x0:x1]
    write_png(path, out)
    print(f'{path}: {img.shape[1]}x{img.shape[0]} -> {out.shape[1]}x{out.shape[0]}'
          f' (aspect {out.shape[1] / out.shape[0]:.4f})')


for p in LOGOS:
    trim(p)
