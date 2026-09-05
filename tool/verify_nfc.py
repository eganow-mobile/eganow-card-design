"""Confirms the drawn geometry reproduces the printed mark."""
import numpy as np
from png_tool import read_png

W, H = 2016, 1278
CX, CY = 0.24777 * W, 0.43545 * H
RADII = [r * W for r in (0.01982, 0.03351, 0.04883, 0.06462)]
SWEEPS = [62.5, 49.9, 46.2, 43.8]
STROKE = 0.00729 * W

SRC = '/Users/naj/Desktop/eganow/mockups/assets'
BOX = (490, 445, 665, 660)

for name in ('eganow_boss_card', 'eganow_freedom_card'):
    img = read_png(f'{SRC}/{name}.png')
    x0, y0, x1, y1 = BOX
    reg = img[y0:y1, x0:x1]
    m = (reg[:, :, :3].astype(np.int32).min(axis=2) > 195) & (reg[:, :, 3] > 128)
    ys, xs = np.nonzero(m)
    r = np.hypot(xs + x0 - CX, ys + y0 - CY)
    a = np.degrees(np.arctan2(ys + y0 - CY, xs + x0 - CX))

    covered = np.zeros(len(r), dtype=bool)
    for rad, sw in zip(RADII, SWEEPS):
        covered |= (np.abs(r - rad) <= STROKE / 2 + 1.0) & (np.abs(a) <= sw + 1.5)

    print(f'{name}: {covered.mean() * 100:5.1f}% of the printed mark is '
          f'reproduced by the drawn arcs (n={len(r)})')
