"""Filmstrip of the travelling-chase animation, drawn on the stripped artwork."""
import numpy as np
from png_tool import read_png, write_png

W, H = 2016, 1278
CX, CY = 0.24777 * W, 0.43545 * H
RADII = [r * W for r in (0.01982, 0.03351, 0.04883, 0.06462)]
SWEEPS = [62.5, 49.9, 46.2, 43.8]
STROKE = 0.00729 * W
FALLOFF, DIM = 1.35, 0.2


def opacity(index, t):
    """Mirrors ContactlessMarkPainter.opacityAt."""
    if t is None:
        return 1.0
    head = -1.5 + (len(RADII) + 2) * t
    lit = min(max(1 - abs(index - head) / FALLOFF, 0.0), 1.0)
    return DIM + (1 - DIM) * lit


base = read_png('assets/images/eganow_boss_card.png').astype(np.float64)
yy, xx = np.mgrid[0:H, 0:W]
r = np.hypot(xx - CX, yy - CY)
a = np.degrees(np.arctan2(yy - CY, xx - CX))
bands = [(np.abs(r - rad) <= STROKE / 2) & (np.abs(a) <= sw)
         for rad, sw in zip(RADII, SWEEPS)]

frames = []
for t in (None, 0.15, 0.32, 0.5, 0.68, 0.85):
    img = base.copy()
    for i, band in enumerate(bands):
        al = opacity(i, t)
        for c in range(3):
            img[:, :, c] = np.where(band, img[:, :, c] * (1 - al) + 255 * al,
                                    img[:, :, c])
    frames.append(np.clip(img[450:670, 470:700], 0, 255).astype(np.uint8))
    lit = [round(opacity(i, t), 2) for i in range(4)]
    print(f't={str(t):5s} arc opacities {lit}')

strip = np.concatenate(
    [np.pad(f, ((0, 0), (6, 6), (0, 0))) for f in frames], axis=1)
strip = np.repeat(np.repeat(strip, 2, axis=0), 2, axis=1)
write_png('/tmp/chase.png', strip)
print('wrote /tmp/chase.png', strip.shape)
