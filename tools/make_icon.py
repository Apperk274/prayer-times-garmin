#!/usr/bin/env python3
"""Generate resources/drawables/launcher_icon.png (60x60 crescent, no PIL)."""
import struct
import zlib
import sys

SIZE = 60
COLOR = (245, 177, 75)  # amber


def crescent(x, y):
    # Inside the big disc, outside the offset disc.
    cx, cy = SIZE / 2 - 1, SIZE / 2
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    if dx * dx + dy * dy > (SIZE*0.4375) ** 2:
        return 0
    ox, oy = cx + SIZE*0.175, cy - SIZE*0.1
    dx2, dy2 = x + 0.5 - ox, y + 0.5 - oy
    if dx2 * dx2 + dy2 * dy2 < (SIZE*0.375) ** 2:
        return 0
    return 255


def chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def main(path):
    raw = b""
    for y in range(SIZE):
        raw += b"\x00"
        for x in range(SIZE):
            a = crescent(x, y)
            raw += bytes(COLOR) + bytes([a])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "resources/drawables/launcher_icon.png")
