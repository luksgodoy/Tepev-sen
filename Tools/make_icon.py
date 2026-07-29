#!/usr/bin/env python3
"""Draw the app icon.

The icon is the machine seen from directly above: brushed aluminum, the reel
in its well, and the single orange accent the product is allowed. No text — a
recorder you identify by its reel.

Renders at 2x and box-downsamples, so the circles have clean edges without
needing an imaging library. Pure stdlib: zlib for the PNG, nothing else.

    python3 Tools/make_icon.py

Writes tepevesen/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import math
import os
import struct
import zlib

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "tepevesen", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
)

SIZE = 1024
SS = 2                      # supersample factor
S = SIZE * SS

# Palette, matching TEDesign.swift exactly.
BODY_TOP = (0xD8, 0xDA, 0xD6)
BODY_BOTTOM = (0xB6, 0xB9, 0xB4)
WELL_TOP = (0x8E, 0x91, 0x8C)
WELL_BOTTOM = (0xB0, 0xB3, 0xAE)
CAP_TOP = (0xF0, 0xF1, 0xEE)
CAP_BOTTOM = (0xCF, 0xD1, 0xCC)
LEGEND = (0x6E, 0x73, 0x70)
REC = (0xFF, 0x4A, 0x17)


def lerp(a, b, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return (
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    )


def shade(c, amount):
    """amount > 0 lightens, < 0 darkens."""
    if amount >= 0:
        return lerp(c, (255, 255, 255), amount)
    return lerp(c, (0, 0, 0), -amount)


# Geometry, in supersampled pixels.
CX = CY = S / 2
R_WELL = S * 0.400
R_FACE = S * 0.352
R_RING = S * 0.386          # the position arc, drawn in the well
RING_W = S * 0.014
R_WINDOW = S * 0.068
R_WINDOW_ORBIT = S * 0.240
R_HUB = S * 0.092
R_SPINDLE = S * 0.026
ARC_SWEEP = math.radians(96)   # a quarter turn of tape wound on

# Deterministic brushing, same idea as BrushedMetal's linear grain.
grain = []
seed = 0x9E3779B97F4A7C15
for _ in range(S):
    seed = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    grain.append(((seed >> 33) & 0xFFFF) / 65535.0)


def pixel(x, y):
    dx = x - CX
    dy = y - CY
    r = math.hypot(dx, dy)

    # Chassis: vertical gradient plus horizontal brushing.
    base = lerp(BODY_TOP, BODY_BOTTOM, y / S)
    base = shade(base, (grain[int(y)] - 0.5) * 0.055)

    if r > R_WELL:
        return base

    # The well the reel sits in: light pools at the bottom of the pit.
    well = lerp(WELL_TOP, WELL_BOTTOM, (dy / R_WELL + 1) / 2)

    # Position ring — a quarter of a turn, starting at twelve o'clock.
    if abs(r - R_RING) <= RING_W / 2:
        angle = (math.atan2(dy, dx) + math.pi / 2) % (2 * math.pi)
        if angle <= ARC_SWEEP:
            return REC

    if r > R_FACE:
        return well

    # Reel face: turned on a lathe, so the grain is circular and the light
    # falls across it from the top left.
    face = lerp(CAP_TOP, CAP_BOTTOM, (r / R_FACE) * 0.55 + 0.22)
    face = shade(face, (-dx - dy) / (R_FACE * 2) * 0.16)
    face = shade(face, (grain[int(r) % S] - 0.5) * 0.05)

    # A milled lip where the face meets the well.
    if r > R_FACE - S * 0.006:
        face = shade(face, -0.16)

    # Three windows through the reel, at 120 degrees. Rotated so none of them
    # sits under the index notch at twelve o'clock.
    for i in range(3):
        a = math.radians(-30 + i * 120)
        wx = CX + math.cos(a) * R_WINDOW_ORBIT
        wy = CY + math.sin(a) * R_WINDOW_ORBIT
        d = math.hypot(x - wx, y - wy)
        if d <= R_WINDOW:
            hole = lerp(WELL_TOP, WELL_BOTTOM, ((y - wy) / R_WINDOW + 1) / 2)
            if d > R_WINDOW - S * 0.004:
                hole = shade(hole, -0.25)
            return hole

    # Index notch, milled into the rim so the reel has an orientation.
    if R_FACE * 0.86 < r < R_FACE * 0.965:
        a = math.atan2(dy, dx)
        if abs(((a + math.pi / 2 + math.pi) % (2 * math.pi)) - math.pi) < 0.026:
            return LEGEND

    # Hub and spindle.
    if r <= R_SPINDLE:
        return shade(WELL_TOP, -0.30)
    if r <= R_HUB:
        hub = lerp(CAP_TOP, CAP_BOTTOM, (dy / R_HUB + 1) / 2)
        if r > R_HUB - S * 0.005:
            hub = shade(hub, -0.20)
        return hub

    return face


def render():
    print(f"rendering {S}x{S} …")
    rows = []
    for y in range(S):
        row = [pixel(x + 0.5, y + 0.5) for x in range(S)]
        rows.append(row)
        if y % 256 == 0:
            print(f"  {y}/{S}")
    return rows


def downsample(rows):
    print(f"downsampling to {SIZE}x{SIZE} …")
    out = bytearray()
    n = SS * SS
    for y in range(SIZE):
        for x in range(SIZE):
            r = g = b = 0.0
            for dy in range(SS):
                src = rows[y * SS + dy]
                for dx in range(SS):
                    c = src[x * SS + dx]
                    r += c[0]
                    g += c[1]
                    b += c[2]
            out.append(max(0, min(255, int(r / n + 0.5))))
            out.append(max(0, min(255, int(g / n + 0.5))))
            out.append(max(0, min(255, int(b / n + 0.5))))
    return out


def write_png(path, width, height, rgb):
    """8-bit RGB, no alpha — an app icon must be fully opaque."""
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)                          # filter type: none
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    write_png(OUT, SIZE, SIZE, downsample(render()))
    print(f"wrote {OUT} ({os.path.getsize(OUT):,} bytes)")
