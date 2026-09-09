"""Centre fit driven by the arc centrelines, not the raw stroke pixels."""
from collections import deque
import numpy as np
from png_tool import read_png

W, H = 2016, 1278
SRC = '/Users/naj/Desktop/eganow/Cards/assets/images'
BOX = (490, 445, 665, 660)

img = read_png(f'{SRC}/eganow_boss_card.png')
x0, y0, x1, y1 = BOX
reg = img[y0:y1, x0:x1]
mask = np.zeros(img.shape[:2], dtype=bool)
mask[y0:y1, x0:x1] = (reg[:, :, :3].astype(np.int32).min(axis=2) > 195) & \
                     (reg[:, :, 3] > 128)

seen = np.zeros_like(mask); blobs = []
for sy, sx in zip(*np.nonzero(mask)):
    if seen[sy, sx]:
        continue
    q, acc = deque([(sy, sx)]), []
    seen[sy, sx] = True
    while q:
        y, x = q.popleft(); acc.append((y, x))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
    if len(acc) > 100:
        blobs.append(np.array(acc, dtype=float))

BINS = 24

def centreline_spread(cx, cy):
    """How far each arc deviates from a true circle about (cx, cy)."""
    total = 0.0
    for b in blobs:
        r = np.hypot(b[:, 1] - cx, b[:, 0] - cy)
        a = np.arctan2(b[:, 0] - cy, b[:, 1] - cx)
        idx = np.clip(((a + np.pi / 2) / np.pi * BINS).astype(int), 0, BINS - 1)
        means = [r[idx == k].mean() for k in range(BINS) if (idx == k).sum() > 8]
        if len(means) > 4:
            total += float(np.std(means))
    return total

best, bc = None, None
for cx in np.arange(470, 545, 0.5):
    for cy in np.arange(540, 575, 0.5):
        c = centreline_spread(cx, cy)
        if best is None or c < best:
            best, bc = c, (cx, cy)
CX, CY = bc
print(f'centre = ({CX:.2f}, {CY:.2f}) -> {CX/W:.5f} w, {CY/H:.5f} h '
      f'(centreline spread {best:.3f}px)')

order = sorted(blobs, key=lambda b: np.hypot(b[:, 1] - CX, b[:, 0] - CY).mean())
radii, sweeps = [], []
for i, b in enumerate(order):
    r = np.hypot(b[:, 1] - CX, b[:, 0] - CY)
    a = np.degrees(np.arctan2(b[:, 0] - CY, b[:, 1] - CX))
    radii.append(r.mean()); sweeps.append(round(max(abs(a.min()), abs(a.max())), 1))
    print(f'  arc {i}: r={r.mean():6.2f} -> {r.mean()/W:.5f} w   '
          f'sweep ±{sweeps[-1]:.1f}°   stroke≈{r.max()-r.min():.1f}px')

print('\nradii :', [round(r / W, 5) for r in radii])
print('sweeps:', sweeps)
