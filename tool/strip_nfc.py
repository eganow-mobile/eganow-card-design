"""Removes the baked contactless mark so Flutter can draw an animated one."""
from collections import deque

import numpy as np
from png_tool import read_png, write_png

BOX = (490, 445, 665, 660)   # x0, y0, x1, y1
W, H = 2016, 1278


def mask_of(img, threshold=150):
    x0, y0, x1, y1 = BOX
    m = np.zeros(img.shape[:2], dtype=bool)
    region = img[y0:y1, x0:x1]
    m[y0:y1, x0:x1] = (
        region[:, :, :3].astype(np.int32).min(axis=2) > threshold
    ) & (region[:, :, 3] > 40)
    return m


def components(m):
    """Label 8-connected blobs — each arc is its own blob."""
    seen = np.zeros_like(m)
    blobs = []
    for sy, sx in zip(*np.nonzero(m)):
        if seen[sy, sx]:
            continue
        q, px = deque([(sy, sx)]), []
        seen[sy, sx] = True
        while q:
            y, x = q.popleft()
            px.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        blobs.append(np.array(px))
    return sorted(blobs, key=len, reverse=True)


def fit_circle(ys, xs):
    A = np.c_[2 * xs, 2 * ys, np.ones(len(xs))]
    b = xs ** 2 + ys ** 2
    cx, cy, c = np.linalg.lstsq(A, b, rcond=None)[0]
    return cx, cy, np.sqrt(c + cx ** 2 + cy ** 2)


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, axis=0), dx, axis=1)
    return out


def inpaint_rows(img, m):
    """The strokes are thin, so interpolating across each row reconstructs the
    background — including where a colour edge runs through the mark."""
    out = img.copy()
    for y in np.unique(np.nonzero(m)[0]):
        row = m[y]
        xs = np.nonzero(row)[0]
        # split into contiguous runs
        breaks = np.nonzero(np.diff(xs) > 1)[0]
        for run in np.split(xs, breaks + 1):
            lo, hi = run[0], run[-1]
            left, right = lo - 1, hi + 1
            cl = out[y, left, :3].astype(np.float64)
            cr = out[y, right, :3].astype(np.float64)
            n = hi - lo + 2
            for i, x in enumerate(range(lo, hi + 1), start=1):
                out[y, x, :3] = np.round(cl + (cr - cl) * (i / n)).astype(np.uint8)
    return out


ref = read_png('assets/images/eganow_boss_card.png')
blobs = components(mask_of(ref))[:4]
fits = []
for px in blobs:
    cx, cy, r = fit_circle(px[:, 0].astype(float), px[:, 1].astype(float))
    fits.append((cx, cy, r, len(px)))
fits.sort(key=lambda f: f[2])

cx = float(np.mean([f[0] for f in fits]))
cy = float(np.mean([f[1] for f in fits]))
print(f'centre = ({cx:.1f}, {cy:.1f}) -> {cx / W:.5f} w, {cy / H:.5f} h')
for i, (bx, by, r, n) in enumerate(fits):
    print(f'  arc {i}: r={r:6.1f} -> {r / W:.5f} w   (fit centre {bx:.1f},{by:.1f}, {n}px)')

ys = np.nonzero(mask_of(ref))[0]
half = (ys.max() - ys.min()) / 2
print(f'half-sweep = {np.degrees(np.arcsin(min(1, half / fits[-1][2]))):.1f} deg')

# --- strip both artworks -----------------------------------------------------
for name in ('eganow_boss_card', 'eganow_freedom_card'):
    img = read_png(f'assets/images/{name}.png')
    m = dilate(mask_of(img, threshold=90), 2)
    m[:, :BOX[0]] = False
    m[:, BOX[2]:] = False
    m[:BOX[1], :] = False
    m[BOX[3]:, :] = False
    cleaned = inpaint_rows(img, m)
    write_png(f'assets/images/{name}.png', cleaned)
    print(f'stripped {name}: {m.sum()} px inpainted')
