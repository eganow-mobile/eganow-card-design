"""Minimal PNG read/write (8-bit RGBA, non-interlaced) — no third-party deps."""
import struct, zlib
import numpy as np


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
    pos, idat, ihdr = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', body)
        elif ctype == b'IDAT':
            idat.append(body)
        elif ctype == b'IEND':
            break
        pos += 12 + length

    w, h, depth, colour, comp, filt, interlace = ihdr
    assert depth == 8 and interlace == 0, (depth, interlace)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b''.join(idat))

    stride = w * channels
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.uint8)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = np.frombuffer(raw[p:p + stride], dtype=np.uint8).astype(np.int32).copy()
        p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            line = (line + prev.astype(np.int32)) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = int(line[i - channels]) if i >= channels else 0
                b = int(prev[i])
                c = int(prev[i - channels]) if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        line = line.astype(np.uint8)
        out[y] = line
        prev = line
    return out.reshape(h, w, channels)


def write_png(path, arr):
    h, w, channels = arr.shape
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = b''.join(b'\x00' + arr[y].tobytes() for y in range(h))

    def chunk(tag, body):
        return (struct.pack('>I', len(body)) + tag + body +
                struct.pack('>I', zlib.crc32(tag + body) & 0xFFFFFFFF))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, colour, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    open(path, 'wb').write(png)
