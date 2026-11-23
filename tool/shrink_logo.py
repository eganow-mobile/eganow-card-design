"""Shrinks the Eganow lockup printed at the top-right of both card fronts.

Usage: python3 tool/shrink_logo.py SRC_DIR [OUT_DIR]

SRC_DIR must hold the pre-shrink PNGs (see tool/README.md); OUT_DIR defaults to
assets/images. Pixels outside the lockup's bounding box are copied unchanged.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_tool import read_png, write_png  # noqa: E402

LOGO_SCALE = 0.75

CARDS = ('eganow_boss_card', 'eganow_freedom_card')
SEARCH = (1250, 70, 1960, 320)  # x0, y0, x1, y1 window that contains the lockup
MARGIN = 6
CORE_DIFF = 90
ANGLES = np.arange(-90.0, 90.0, 0.25)
ANGLE_PENALTY = 0.1
LINE_MIN_GAIN = 3.0
LINE_REACH = 160
LINE_RING = 40
BOOTSTRAP_ROWS = 8
MAX_SLOPE = 2.5
LINE_MATCH_TOL = 9.0
LINE_MAX_TURN = 8.0
LINE_MIN_SPAN = 40.0
LINE_SNAP = 3.5
RIDGE_OPEN = 7
RIDGE_SIGMA = 0.8


def lockup_mask(img):
    x0, y0, x1, y1 = SEARCH
    rgb = img[y0:y1, x0:x1, :3].astype(np.int32)
    white = rgb.min(axis=2) > 110
    blue = (rgb[:, :, 2] > rgb[:, :, 0] + 40) & (rgb[:, :, 2] > 80)
    m = np.zeros(img.shape[:2], dtype=bool)
    m[y0:y1, x0:x1] = white | blue
    return m


def bbox(m):
    ys, xs = np.nonzero(m)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def bilinear(img, xs, ys):
    h, w = img.shape[:2]
    xs = np.clip(xs, 0, w - 1.0001)
    ys = np.clip(ys, 0, h - 1.0001)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = (xs - x0)[..., None]
    fy = (ys - y0)[..., None]
    top = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    bot = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bot * fy


def box_blur(a, r):
    p = np.pad(a, r, mode='edge')
    c = np.cumsum(np.cumsum(p, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    n = 2 * r + 1
    return (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)


def ray_ends(gx, gy, box, angle):
    """Distances from each hole pixel to the first pixel outside the box along
    the line at `angle`, forwards and backwards."""
    x0, y0, x1, y1 = box
    dx, dy = np.cos(np.radians(angle)), np.sin(np.radians(angle))
    big = 1e9

    def reach(sign):
        sx, sy = dx * sign, dy * sign
        tx = np.full(gx.shape, big)
        ty = np.full(gx.shape, big)
        if abs(sx) > 1e-9:
            tx = ((x1 + 1 if sx > 0 else x0 - 1) - gx) / sx
        if abs(sy) > 1e-9:
            ty = ((y1 + 1 if sy > 0 else y0 - 1) - gy) / sy
        return np.minimum(tx, ty), sx, sy

    return reach(1), reach(-1)


def directional_fill(img, box):
    """Rebuilds the rectangle `box` by interpolating along the straight line
    through each pixel, picking per pixel the angle whose two ends agree best.
    Straight edges and thin lines crossing the box continue through it."""
    x0, y0, x1, y1 = box
    gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(np.float64)
    original = img[:, :, :3].astype(np.float64)
    lines = match_ridges(img, box)
    src = suppress_ridges(original, box) if lines else original

    def interpolate(angle, sel=None, source=None):
        source = src if source is None else source
        (tp, sxp, syp), (tm, sxm, sym) = ray_ends(gx, gy, box, angle)
        if sel is not None:
            gxs, gys, tp, tm = gx[sel], gy[sel], tp[sel], tm[sel]
        else:
            gxs, gys = gx, gy
        vp = bilinear(source, gxs + sxp * tp, gys + syp * tp)
        vm = bilinear(source, gxs + sxm * tm, gys + sym * tm)
        total = (tp + tm)[..., None]
        return (vm * tp[..., None] + vp * tm[..., None]) / total, vp, vm

    costs = np.empty((len(ANGLES),) + gx.shape, dtype=np.float32)
    for i, a in enumerate(ANGLES):
        _, vp, vm = interpolate(a)
        costs[i] = box_blur(np.abs(vp - vm).sum(axis=2), 2)

    dominant = ANGLES[np.argmin(costs.mean(axis=(1, 2)))]
    diff = np.abs(ANGLES - dominant)
    diff = np.minimum(diff, 180 - diff)
    best = np.argmin(costs + (ANGLE_PENALTY * diff)[:, None, None], axis=0)

    out = np.zeros(gx.shape + (3,))
    for i, a in enumerate(ANGLES):
        sel = best == i
        if sel.any():
            out[sel] = interpolate(a, sel)[0]
    return draw_ridges(out, original, box, lines)


def row_peaks(lum_row, x_lo):
    """Sub-pixel positions of narrow bright ridges in one row; steps (colour
    edges) are rejected because their two flanks differ."""
    n = len(lum_row)
    base = box_blur(lum_row[None, :], 4)[0]
    height = lum_row - base
    left = np.pad(lum_row, 4, mode='edge')[:n]
    right = np.pad(lum_row, 4, mode='edge')[8:8 + n]
    is_peak = (
        (lum_row >= np.roll(lum_row, 1)) & (lum_row > np.roll(lum_row, -1))
        & (height > LINE_MIN_GAIN)
        & (np.abs(right - left) < 0.5 * height)
    )
    out = []
    for i in np.nonzero(is_peak)[0]:
        if i < 1 or i > n - 2:
            continue
        a, b, c = lum_row[i - 1], lum_row[i], lum_row[i + 1]
        d = a - 2 * b + c
        off = 0.5 * (a - c) / d if d != 0 else 0.0
        out.append(x_lo + i + off)
    return out


def follow(peaks_by_row, rows, x0, slope):
    pts = [(rows[0], x0)]
    miss = 0
    for k in range(1, len(rows)):
        recent = pts[-10:]
        if len(recent) >= 4:
            ys = np.array([q[0] for q in recent], dtype=float)
            slope = np.polyfit(ys, np.array([q[1] for q in recent]), 1)[0]
        pred = pts[-1][1] + slope * (rows[k] - pts[-1][0])
        peaks = peaks_by_row[k]
        if len(peaks) and np.abs(peaks - pred).min() < 1.2:
            pts.append((rows[k], peaks[np.abs(peaks - pred).argmin()]))
            miss = 0
        else:
            miss += 1
            if miss >= 5:
                break
    return pts


def track_lines(lum, rows, x_lo):
    """Follows each ridge away from the box through `rows` (ordered outwards),
    trying every plausible starting slope since two families can cross.
    Returns (intercept, slope) of x = a + s * y for each ridge seen throughout."""
    peaks_by_row = [np.array(row_peaks(lum[r], x_lo)) for r in rows]
    ahead = peaks_by_row[BOOTSTRAP_ROWS]
    lines = []
    for x in peaks_by_row[0]:
        best = []
        for c in ahead[np.abs(ahead - x) < BOOTSTRAP_ROWS * MAX_SLOPE]:
            pts = follow(peaks_by_row, rows, x, (c - x) / (rows[BOOTSTRAP_ROWS] - rows[0]))
            if len(pts) > len(best):
                best = pts
        if len(best) < len(rows) * 0.7:
            continue
        ys = np.array([q[0] for q in best], dtype=float)
        s, a = np.polyfit(ys, np.array([q[1] for q in best]), 1)
        lines.append((a, s))
    return lines


def ridge_tracks(lum, box):
    """Ridges leaving each side of the box, as (anchor, unit direction into the
    box) in image coordinates."""
    x0, y0, x1, y1 = box
    h, w = lum.shape
    xl, xh = max(x0 - LINE_REACH, 0), min(x1 + LINE_REACH, w - 1)
    yl, yh = max(y0 - LINE_REACH, 0), min(y1 + LINE_REACH, h - 1)
    across = lum[:, xl:xh + 1]
    down = lum.T[:, yl:yh + 1]
    ring = range(LINE_RING)
    out = []
    for a, sl in track_lines(across, [y0 - 1 - i for i in ring], xl):
        out.append(((a + sl * (y0 - 1), y0 - 1), (sl, 1.0)))
    for a, sl in track_lines(across, [y1 + 1 + i for i in ring], xl):
        out.append(((a + sl * (y1 + 1), y1 + 1), (-sl, -1.0)))
    for a, sl in track_lines(down, [x0 - 1 - i for i in ring], yl):
        out.append(((x0 - 1, a + sl * (x0 - 1)), (1.0, sl)))
    for a, sl in track_lines(down, [x1 + 1 + i for i in ring], yl):
        out.append(((x1 + 1, a + sl * (x1 + 1)), (-1.0, -sl)))
    return [(np.array(p), np.array(d) / np.hypot(*d)) for p, d in out]


def rect_span(p, d, box):
    """Parameters t where the line p + t*d is inside the box, or None."""
    x0, y0, x1, y1 = box
    lo, hi = -np.inf, np.inf
    for k, (b0, b1) in enumerate(((x0 - 1, x1 + 1), (y0 - 1, y1 + 1))):
        if abs(d[k]) < 1e-9:
            if not b0 <= p[k] <= b1:
                return None
            continue
        t0, t1 = sorted(((b0 - p[k]) / d[k], (b1 - p[k]) / d[k]))
        lo, hi = max(lo, t0), min(hi, t1)
    return (lo, hi) if lo < hi else None


def snap_to_ridge(lum, point, box):
    """Moves a point on the box perimeter onto the ridge actually printed there."""
    x0, y0, x1, y1 = box
    on_row = min(abs(point[1] - (y0 - 1)), abs(point[1] - (y1 + 1))) < 1.5
    if on_row:
        row = int(round(point[1]))
        lo = int(point[0]) - 8
        peaks = row_peaks(lum[row, lo:lo + 17], lo)
        axis = 0
    else:
        col = int(round(point[0]))
        lo = int(point[1]) - 8
        peaks = row_peaks(lum[lo:lo + 17, col], lo)
        axis = 1
    if not peaks:
        return None
    best = min(peaks, key=lambda v: abs(v - point[axis]))
    if abs(best - point[axis]) > LINE_SNAP:
        return None
    snapped = point.copy()
    snapped[axis] = best
    return snapped


def match_ridges(img, box):
    """Straight ridges that cross the box, paired end to end from the printed
    pattern around it. Returns perimeter endpoint pairs."""
    lum = img[:, :, :3].astype(np.float64) @ np.array([0.299, 0.587, 0.114])
    tracks = []
    for p, d in ridge_tracks(lum, box):
        span = rect_span(p, d, box)
        if span is not None:
            tracks.append((p, d, p + d * span[0]))

    pairs = []
    for i, (pi, di, ei) in enumerate(tracks):
        for j in range(i + 1, len(tracks)):
            pj, dj, ej = tracks[j]
            turn = np.degrees(np.arccos(np.clip(-(di @ dj), -1, 1)))
            if turn > LINE_MAX_TURN or np.hypot(*(ej - ei)) < LINE_MIN_SPAN:
                continue
            offset = 0.5 * (abs(di[0] * (ej - pi)[1] - di[1] * (ej - pi)[0])
                            + abs(dj[0] * (ei - pj)[1] - dj[1] * (ei - pj)[0]))
            if offset < LINE_MATCH_TOL:
                pairs.append((offset + turn, i, j))
    pairs.sort()
    used, lines = set(), []
    for _, i, j in pairs:
        if i in used or j in used:
            continue
        a = snap_to_ridge(lum, tracks[i][2], box)
        b = snap_to_ridge(lum, tracks[j][2], box)
        if a is None or b is None:
            continue
        used.update((i, j))
        lines.append((a, b, tracks[i][1], tracks[j][1]))
    print(f'  ridges matched through the box: {len(lines)} of {len(tracks)} tracked')
    return lines


def suppress_ridges(src, box):
    """Replaces thin bright ridges around the box by their surroundings so the
    fill below is smooth; matched ridges are drawn back afterwards."""
    x0, y0, x1, y1 = box
    pad = 14
    ys, xs = slice(max(y0 - pad, 0), y1 + pad + 1), slice(max(x0 - pad, 0), x1 + pad + 1)
    crop = src[ys, xs]

    def sweep(a, fn):
        r = RIDGE_OPEN // 2
        for axis in (0, 1):
            p = np.pad(a, [(r, r) if k == axis else (0, 0) for k in range(3)], mode='edge')
            n = a.shape[axis]
            a = fn([np.take(p, range(i, i + n), axis=axis) for i in range(RIDGE_OPEN)], axis=0)
        return a

    opened = sweep(sweep(crop, np.min), np.max)
    out = src.copy()
    out[ys, xs] = opened
    return out


def ridge_amplitude(src, point, direction, box):
    """Per-channel area of the ridge's cross-section (perpendicular to the
    ridge) measured where it meets the box perimeter."""
    x0, y0, x1, y1 = box
    on_row = min(abs(point[1] - (y0 - 1)), abs(point[1] - (y1 + 1))) < 1.5
    if on_row:
        row, c = int(round(point[1])), int(round(point[0]))
        win = src[row, c - 8:c + 9]
        scale = abs(direction[1])
    else:
        col, c = int(round(point[0])), int(round(point[1]))
        win = src[c - 8:c + 9, col]
        scale = abs(direction[0])
    baseline = 0.5 * (win[2] + win[-3])
    area = np.clip(win[4:-4] - baseline, 0, None).sum(axis=0)
    return area * scale


def draw_ridges(base, src, box, lines):
    """Redraws each matched ridge as a cubic Hermite curve between its two
    perimeter points, so a gently curved line stays curved."""
    x0, y0, x1, y1 = box
    h, w = y1 - y0 + 1, x1 - x0 + 1
    excess = np.zeros((h, w, 3))
    sigma = RIDGE_SIGMA
    for a, b, ta, tb in lines:
        area = 0.5 * (ridge_amplitude(src, a, ta, box) + ridge_amplitude(src, b, tb, box))
        amp = area / (sigma * np.sqrt(2 * np.pi))
        length = np.hypot(*(b - a))
        t = np.linspace(0, 1, int(length / 0.3) + 2)[:, None]
        h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
        h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        pts = h00 * a + h10 * ta * length + h01 * b + h11 * (-tb) * length
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                px = np.round(pts[:, 0]).astype(int) + dx
                py = np.round(pts[:, 1]).astype(int) + dy
                keep = (px >= x0) & (px <= x1) & (py >= y0) & (py <= y1)
                d2 = (px - pts[:, 0]) ** 2 + (py - pts[:, 1]) ** 2
                val = amp[None, :] * np.exp(-d2 / (2 * sigma ** 2))[:, None]
                np.maximum.at(excess, (py[keep] - y0, px[keep] - x0), val[keep])
    return base + excess


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy == 0 and dx == 0:
                continue
            sh = np.zeros_like(m)
            ys = slice(max(dy, 0), m.shape[0] + min(dy, 0))
            xs = slice(max(dx, 0), m.shape[1] + min(dx, 0))
            yd = slice(max(-dy, 0), m.shape[0] + min(-dy, 0))
            xd = slice(max(-dx, 0), m.shape[1] + min(-dx, 0))
            sh[ys, xs] = m[yd, xd]
            out |= sh
    return out


def fill_holes(m):
    outside = np.zeros_like(m)
    outside[0, :] = outside[-1, :] = outside[:, 0] = outside[:, -1] = True
    outside &= ~m
    while True:
        grown = outside.copy()
        grown[1:] |= outside[:-1]
        grown[:-1] |= outside[1:]
        grown[:, 1:] |= outside[:, :-1]
        grown[:, :-1] |= outside[:, 1:]
        grown &= ~m
        if (grown == outside).all():
            return ~outside
        outside = grown


def extract_layer(orig, bg):
    """Premultiplied RGBA of the lockup. Alpha is the projection of the pixel's
    offset from the background onto the offset to the nearest solid colour."""
    diff = np.abs(orig - bg).sum(axis=2)
    core = fill_holes(diff > CORE_DIFF)
    fg = np.where(core[..., None], orig, 0.0)
    known = core.copy()
    for _ in range(4):
        acc = np.zeros_like(fg)
        cnt = np.zeros(core.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                v = np.roll(np.roll(fg, dy, 0), dx, 1)
                acc += np.where(k[..., None], v, 0.0)
                cnt += k
        new = ~known & (cnt > 0)
        fg[new] = acc[new] / cnt[new][:, None]
        known |= new

    d = fg - bg
    denom = (d * d).sum(axis=2)
    num = ((orig - bg) * d).sum(axis=2)
    alpha = np.where(denom > 1, np.clip(num / np.maximum(denom, 1), 0, 1), 1.0)
    alpha = np.where(core, 1.0, alpha)
    alpha[~dilate(core, 3)] = 0.0
    alpha[alpha < 0.02] = 0.0
    return np.dstack([fg * alpha[..., None], alpha]), core


def resample_matrix(n, scale, anchor):
    """Row-weights mapping a length-n axis scaled about `anchor`. Each output
    pixel averages the source interval it covers (a 1px box when enlarging,
    which is bilinear); anything outside the source counts as transparent."""
    width = max(1 / scale, 1.0)
    centre = anchor + (np.arange(n) + 0.5 - anchor) / scale
    lo = centre - width / 2
    hi = centre + width / 2
    edges = np.arange(n + 1, dtype=np.float64)
    overlap = np.minimum(hi[:, None], edges[None, 1:]) - np.maximum(lo[:, None], edges[None, :-1])
    return np.clip(overlap, 0, None) / width


def process(src_path, dst_path, scale):
    orig_img = read_png(src_path)
    assert orig_img.shape[2] == 4
    m = lockup_mask(orig_img)
    tx0, ty0, tx1, ty1 = bbox(m)
    box = (tx0 - MARGIN, ty0 - MARGIN, tx1 + MARGIN, ty1 + MARGIN)
    x0, y0, x1, y1 = box
    assert (orig_img[y0:y1 + 1, x0:x1 + 1, 3] == 255).all()

    bg = directional_fill(orig_img, box)
    orig = orig_img[y0:y1 + 1, x0:x1 + 1, :3].astype(np.float64)
    layer, core = extract_layer(orig, bg)

    ay = ty0 - y0
    ax = tx1 + 1 - x0
    h, w = layer.shape[:2]
    wy = resample_matrix(h, scale, ay)
    wx = resample_matrix(w, scale, ax)
    small = np.einsum('ij,jkc->ikc', wy, layer)
    small = np.einsum('kj,ijc->ikc', wx, small)

    a = small[..., 3:4]
    rgb = small[..., :3] + (1 - a) * bg

    out = orig_img.copy()
    out[y0:y1 + 1, x0:x1 + 1, :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    write_png(dst_path, out)
    print(f'{os.path.basename(dst_path)}: lockup x {tx0}..{tx1} y {ty0}..{ty1}, '
          f'box {box}, scale {scale}')


if __name__ == '__main__':
    src_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else 'assets/images'
    for name in CARDS:
        process(os.path.join(src_dir, f'{name}.png'),
                os.path.join(out_dir, f'{name}.png'), LOGO_SCALE)
