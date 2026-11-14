"""Top-down (3/4 view) pixel-art ship interior for the Mars mission game.

Draws at 480x270 and exports 2x / 4x nearest-neighbour upscales plus a layout JSON
(rooms, doors, station interaction points, obstacle rects) for collision and hotspots.
Usage: python3 draw_ship.py <out_dir> [--no-crew]
"""
import json
import math
import random
import sys
from PIL import Image

W, H = 480, 270
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
DRAW_CREW = "--no-crew" not in sys.argv
img = Image.new("RGB", (W, H))
P = img.load()
rng = random.Random(11)

C = {
    "void": (9, 8, 22), "nebula": (26, 16, 48), "nebula2": (40, 22, 66),
    "hullD": (30, 32, 52), "hull": (52, 56, 82), "hullL": (84, 90, 122), "hullH": (128, 136, 168),
    "wallTop": (22, 22, 38), "faceD": (44, 48, 76), "face": (62, 68, 104), "faceL": (88, 96, 138),
    "metalD": (56, 60, 82), "metal": (96, 102, 128), "metalL": (148, 156, 180), "metalH": (200, 206, 222),
    "scr": (8, 16, 24), "scrL": (16, 30, 40),
    "cyan": (72, 226, 236), "cyanD": (28, 110, 132),
    "orange": (255, 148, 50), "orangeD": (160, 72, 30), "yellow": (255, 214, 84), "yellowD": (150, 112, 30),
    "red": (232, 62, 72), "redD": (120, 30, 40),
    "green": (96, 230, 124), "greenD": (34, 116, 66), "leaf": (60, 170, 80), "leafD": (30, 96, 50),
    "purple": (186, 118, 244), "purpleD": (92, 58, 146),
    "mars": (212, 98, 60), "marsD": (146, 56, 38), "marsL": (240, 152, 102),
    "earth": (64, 126, 222), "earthD": (32, 66, 146),
    "white": (238, 240, 250), "grey": (150, 150, 172), "frost": (200, 226, 240),
    "visor": (40, 60, 90), "visorL": (140, 200, 230),
    # floors
    "comF": (30, 50, 58), "comF2": (36, 58, 66),
    "sciF": (150, 150, 178), "sciF2": (166, 166, 192), "sciG": (128, 128, 158),
    "engF": (46, 40, 44), "engF2": (60, 52, 54),
    "hubF": (54, 62, 92), "hubF2": (62, 72, 104), "hubG": (44, 50, 76),
    "brgF": (26, 32, 62), "brgF2": (32, 40, 74),
    "carF": (64, 60, 66), "carF2": (74, 70, 76),
    "crate": (150, 104, 60), "crateD": (104, 70, 40), "crateL": (186, 140, 90),
}
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def col(c):
    return C[c] if isinstance(c, str) else c


def px(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        P[x, y] = col(c)


def rect(x, y, w, h, c):
    for j in range(max(0, y), min(H, y + h)):
        for i in range(max(0, x), min(W, x + w)):
            P[i, j] = col(c)


def frame(x, y, w, h, c):
    for i in range(x, x + w):
        px(i, y, c); px(i, y + h - 1, c)
    for j in range(y, y + h):
        px(x, j, c); px(x + w - 1, j, c)


def line(x0, y0, x1, y1, c):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        px(x0, y0, c)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x0 += sx
        if e2 <= dx:
            err += dx; y0 += sy


def disc(cx, cy, r, c):
    for j in range(-r, r + 1):
        for i in range(-r, r + 1):
            if i * i + j * j <= r * r + r * 0.6:
                px(cx + i, cy + j, c)


def ellipse_ring(cx, cy, rx, ry, c):
    n = int(2 * math.pi * max(rx, ry) * 1.6)
    for k in range(n):
        a = 2 * math.pi * k / n
        px(round(cx + rx * math.cos(a)), round(cy + ry * math.sin(a)), c)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def glow(cx, cy, r, c, strength=0.45, ry=None):
    """Dithered light pool: banded, ordered-dither falloff so it stays pixel-art."""
    ry = ry or r
    gc = col(c)
    for j in range(cy - ry, cy + ry + 1):
        for i in range(cx - r, cx + r + 1):
            if not (0 <= i < W and 0 <= j < H):
                continue
            d = math.sqrt(((i - cx) / r) ** 2 + ((j - cy) / ry) ** 2)
            if d >= 1:
                continue
            lvl = strength * (1 - d) ** 1.4 * 3
            base = math.floor(lvl)
            if (lvl - base) * 16 > BAYER[j % 4][i % 4]:
                base += 1
            if base:
                P[i, j] = mix(P[i, j], gc, min(base / 3 * 0.75, 0.75))


def shade(x, y, w, h, t=0.35):
    for j in range(max(0, y), min(H, y + h)):
        for i in range(max(0, x), min(W, x + w)):
            P[i, j] = mix(P[i, j], (0, 0, 0), t)


FONT = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"], "G": ["011", "100", "101", "101", "011"],
    "H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
    "L": ["100", "100", "100", "100", "111"], "M": ["101", "111", "111", "101", "101"],
    "N": ["110", "101", "101", "101", "101"], "O": ["010", "101", "101", "101", "010"],
    "R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
    "U": ["101", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    " ": ["000", "000", "000", "000", "000"],
}


def text(x, y, s, c):
    for ch in s:
        for j, row in enumerate(FONT[ch]):
            for i, b in enumerate(row):
                if b == "1":
                    px(x + i, y + j, c)
        x += 4


def text_w(s):
    return len(s) * 4 - 1


LAYOUT = {"base_size": [W, H], "rooms": [], "doors": [], "stations": [], "obstacles": []}


def obstacle(x, y, w, h, kind):
    LAYOUT["obstacles"].append({"kind": kind, "x": x, "y": y, "w": w, "h": h})


def desk(x, y, w, h, top="metalL", front="metal", kind="desk", trim=None):
    """Top-down 3/4 furniture: top surface, 4px front face, soft shadow."""
    shade(x + 1, y + h + 4, w, 2, 0.35)
    rect(x, y, w, h, top)
    rect(x, y, w, 1, "metalH")
    rect(x, y + h, w, 4, front)
    rect(x, y + h + 3, w, 1, "metalD")
    if trim:
        rect(x + 1, y + h + 1, w - 2, 1, trim)
    obstacle(x, y, w, h + 4, kind)


def chair(x, y, c):
    shade(x, y + 7, 8, 2, 0.3)
    rect(x, y, 8, 6, col(c)); rect(x, y, 8, 1, "metalH")
    rect(x + 1, y + 6, 6, 2, "metalD")


# ============ space ============
rect(0, 0, W, H, "void")
for j in range(H):                                           # dithered nebula band
    for i in range(W):
        n = math.sin(i * 0.018 + j * 0.03) + math.sin(i * 0.007 - j * 0.02) * 1.2
        if n > 1.2 and BAYER[j % 4][i % 4] < (n - 1.2) * 20:
            P[i, j] = col("nebula")
        if n > 1.75 and BAYER[j % 4][i % 4] < (n - 1.75) * 18:
            P[i, j] = col("nebula2")
for _ in range(260):
    px(rng.randrange(W), rng.randrange(H), rng.choice(["grey", "grey", "white", "hullL"]))
for _ in range(10):
    sx, sy = rng.randrange(W), rng.randrange(H)
    for d in (-1, 1):
        px(sx + d, sy, "grey"); px(sx, sy + d, "grey")
    px(sx, sy, "white")
# Mars (top-right, partly off-frame) and a tiny Earth far behind (bottom-left)
for j in range(-46, 47):
    for i in range(-46, 47):
        if i * i + j * j <= 46 * 46:
            x, y = 488 + i, 4 + j
            if not (0 <= x < W and 0 <= y < H):
                continue
            c = "mars"
            if (i + 14) ** 2 + (j - 14) ** 2 > 40 * 40:
                c = "marsD"
            elif (i * 7 + j * 13 + (i * j) % 9) % 17 == 0:
                c = "marsD"
            elif i < -26 and j > 10 and (i + j) % 3 == 0:
                c = "marsL"
            px(x, y, c)
disc(14, 262, 4, "earthD"); disc(13, 261, 3, "earth"); px(12, 260, "white")

# ============ hull ============
HX0, HY0, HX1, HY1 = 24, 14, 444, 256
NOSE_CX, NOSE_CY, NOSE_RX, NOSE_RY = 444, 111, 26, 92


def in_hull(x, y):
    if HX0 <= x <= HX1 and HY0 <= y <= HY1:
        r = 10                                              # rounded corners (left side)
        if x < HX0 + r and y < HY0 + r and (x - HX0 - r) ** 2 + (y - HY0 - r) ** 2 > r * r:
            return False
        if x < HX0 + r and y > HY1 - r and (x - HX0 - r) ** 2 + (y - HY1 + r) ** 2 > r * r:
            return False
        return True
    if x > HX1 and ((x - NOSE_CX) / NOSE_RX) ** 2 + ((y - NOSE_CY) / NOSE_RY) ** 2 <= 1:
        return True
    return False


# engines at the back (left), with exhaust glow trailing into space
for ey in (60, 196):
    for k in range(40):
        t = k / 40
        for dy in range(-6, 7):
            if abs(dy) <= 6 * (1 - t) and BAYER[(ey + dy) % 4][k % 4] < 16 * (1 - t):
                px(16 - k, ey + dy, "orange" if abs(dy) < 3 * (1 - t) else "orangeD")
    rect(8, ey - 9, 18, 18, "hullD"); rect(10, ey - 8, 14, 16, "hull")
    rect(8, ey - 5, 3, 10, "yellow"); rect(8, ey - 3, 2, 6, "white")

for y in range(H):
    for x in range(W):
        if in_hull(x, y):
            edge = not (in_hull(x - 2, y) and in_hull(x + 2, y) and in_hull(x, y - 2) and in_hull(x, y + 2))
            P[x, y] = col("hullL" if edge else "wallTop")
for y in range(H):                                          # outer outline
    for x in range(W):
        if in_hull(x, y) and not (in_hull(x - 1, y) and in_hull(x + 1, y) and in_hull(x, y - 1) and in_hull(x, y + 1)):
            P[x, y] = col("hullH" if y < 120 else "hull")

# ============ rooms ============
FACE = 12  # height of a north wall face in 3/4 view


def floor_pattern(x, y, w, h, kind):
    for j in range(y, y + h):
        for i in range(x, x + w):
            if kind == "com":
                c = "comF2" if ((i // 8) + (j // 8)) % 2 else "comF"
            elif kind == "sci":
                c = "sciG" if (i % 12 == 0 or j % 12 == 0) else ("sciF2" if ((i // 12) + (j // 12)) % 2 else "sciF")
            elif kind == "eng":
                c = "engF2" if ((i + j) % 6 == 0 or (i - j) % 6 == 0) else "engF"
            elif kind == "hub":
                c = "hubG" if (i % 16 == 0 or j % 16 == 0) else ("hubF2" if ((i // 16) + (j // 16)) % 2 else "hubF")
            elif kind == "brg":
                c = "brgF2" if (j % 4 == 0 and (i // 2) % 2) else "brgF"
            else:
                c = "carF2" if (i % 20 < 1 or j % 10 < 1) else "carF"
            px(i, j, c)


def room(name, label, x, y, w, h, kind):
    floor_pattern(x, y + FACE, w, h - FACE, kind)
    rect(x, y, w, FACE, "face")                             # north wall face
    rect(x, y, w, 1, "faceL")
    rect(x, y + FACE - 2, w, 2, "faceD")
    for i in range(x + 6, x + w - 4, 24):
        rect(i, y + 2, 1, FACE - 4, "faceD")                # panel seams
    shade(x, y + FACE, w, 2, 0.3)                           # contact shadow under the wall
    shade(x, y + FACE, 2, h - FACE, 0.2)
    pw = text_w(label) + 6                                  # name plate
    rect(x + 6, y + 3, pw, 7, "faceD"); text(x + 9, y + 4, label, "metalL")
    LAYOUT["rooms"].append({"id": name, "label": label, "x": x, "y": y + FACE, "w": w, "h": h - FACE})


ROOMS = {
    "comms": (30, 22, 118, 92, "com", "COMMS"),
    "science": (160, 22, 164, 92, "sci", "SCIENCE LAB"),
    "bridge": (336, 22, 108, 180, "brg", "BRIDGE"),
    "engineering": (30, 126, 118, 124, "eng", "ENGINE ROOM"),
    "hub": (160, 126, 164, 124, "hub", "MISSION HUB"),
    "cargo": (336, 214, 104, 36, "car", "CARGO"),
}
for k, (x, y, w, h, kind, label) in ROOMS.items():
    room(k, label, x, y, w, h, kind)

# bridge floor flows into the nose; the nose rim is a curved window
for y in range(22 + FACE, 202):
    for x in range(HX1, 472):
        if ((x - NOSE_CX) / (NOSE_RX - 6)) ** 2 + ((y - NOSE_CY) / (NOSE_RY - 8)) ** 2 <= 1:
            px(x, y, "brgF2" if (y % 4 == 0 and (x // 2) % 2) else "brgF")
for y in range(H):
    for x in range(HX1 + 3, W):
        d = ((x - NOSE_CX) / (NOSE_RX - 2)) ** 2 + ((y - NOSE_CY) / (NOSE_RY - 3)) ** 2
        dd = ((x - NOSE_CX) / (NOSE_RX - 6)) ** 2 + ((y - NOSE_CY) / (NOSE_RY - 8)) ** 2
        if d <= 1 and dd > 1:
            P[x, y] = col("white") if rng.random() < 0.05 else col("void")
for k in range(60):                                          # window rim highlights
    a = -math.pi / 2 + math.pi * k / 59
    px(round(NOSE_CX + (NOSE_RX - 6) * math.cos(a)), round(NOSE_CY + (NOSE_RY - 8) * math.sin(a)), "cyanD")
    px(round(NOSE_CX + (NOSE_RX - 1) * math.cos(a)), round(NOSE_CY + (NOSE_RY - 2) * math.sin(a)), "hullH")

# doors: openings carved through walls (floor) + frame posts
DOORS = [
    ("comms-science", 146, 66, 16, 26, "v"),
    ("science-bridge", 322, 66, 16, 26, "v"),
    ("comms-engineering", 118, 112, 24, 16, "h"),
    ("science-hub", 226, 112, 28, 16, "h"),
    ("engineering-hub", 146, 182, 16, 26, "v"),
    ("hub-bridge", 322, 150, 16, 26, "v"),
    ("bridge-cargo", 372, 200, 28, 16, "h"),
]
for name, x, y, w, h, o in DOORS:
    if o == "v":
        rect(x, y, w, h, "hubF")
        for j in range(y, y + h):
            if j % 4 == 0:
                rect(x, j, w, 1, "hubG")
        rect(x, y - 4, w, 4, "faceD"); rect(x, y - 4, w, 1, "faceL")   # lintel face
        rect(x + 2, y + 2, 1, h - 4, "yellowD"); rect(x + w - 3, y + 2, 1, h - 4, "yellowD")
        hh = h
    else:
        rect(x, y, w, h + FACE, "hubF")
        for i in range(x, x + w):
            if i % 4 == 0:
                rect(i, y, 1, h + FACE, "hubG")
        rect(x - 2, y, 2, h + FACE, "metalD"); rect(x + w, y, 2, h + FACE, "metalD")
        rect(x + 2, y + h + FACE - 2, w - 4, 1, "yellowD")
        hh = h + FACE
    LAYOUT["doors"].append({"id": name, "x": x, "y": y, "w": w, "h": hh})

# ============ ambient lights (before props so props stay crisp) ============
glow(241, 190, 54, "cyan", 0.42, 44)        # holo-table
glow(90, 196, 46, "orange", 0.5, 40)        # reactor
glow(100, 62, 40, "green", 0.32, 30)        # comms console
glow(240, 66, 70, "white", 0.25, 30)        # lab ceiling light
glow(276, 92, 26, "purple", 0.3, 18)        # spectrometer
glow(426, 112, 40, "cyan", 0.35, 70)        # bridge nose
glow(388, 232, 30, "yellow", 0.2, 14)       # cargo work light
for k in range(90):                         # bridge floor projection ring
    if k % 3:
        a = 2 * math.pi * k / 90
        px(round(372 + 26 * math.cos(a)), round(118 + 16 * math.sin(a)), "cyanD")
glow(372, 118, 30, "cyan", 0.2, 20)
glow(180, 236, 24, "white", 0.15, 12)

# ============ COMMS ============
for i in range(4):                                       # server racks = data storage
    rx, ry = 34, 40 + i * 17
    desk(rx, ry, 18, 10, "metalD", "hullD", "rack")
    for k in range(5):
        px(rx + 3 + k * 3, ry + 3, rng.choice(["green", "green", "yellow", "cyan"]))
        px(rx + 3 + k * 3, ry + 6, rng.choice(["green", "greenD", "red"]))
desk(70, 48, 64, 12, "metalL", "metal", "comms-console", "greenD")
for sx, w in ((74, 18), (95, 22), (120, 12)):              # screens on the desk
    rect(sx, 49, w, 8, "scr"); frame(sx, 49, w, 8, "greenD")
for k in range(18):
    px(97 + k, 53 + round(2 * math.sin(k * 0.8)), "green")
for i in range(3):
    disc(78 + i * 5, 53, 1, "green" if i != 1 else "greenD")
rect(122, 51, 8, 4, "yellow"); rect(122, 51, 3, 4, "red")
chair(98, 68, "greenD")
rect(82, 25, 40, 7, "scr"); frame(82, 25, 40, 7, "greenD")          # DSN status board
for i, lit in enumerate([1, 0, 1]):
    disc(88 + i * 14, 28, 1, "green" if lit else "redD")
disc(128, 96, 7, "metalD"); disc(128, 96, 5, "metal"); disc(128, 96, 2, "green")   # dish feed hatch
obstacle(121, 89, 15, 15, "dish-hatch")
LAYOUT["stations"].append({"role": "comms", "label": "COM", "x": 102, "y": 66, "interact_radius": 14})

# ============ SCIENCE ============
desk(170, 46, 60, 12, "metalH", "metalL", "lab-bench", "purpleD")
rect(176, 44, 4, 8, "metal"); rect(175, 43, 6, 3, "metalD"); disc(178, 50, 2, "metalD")   # microscope
for i, c in enumerate(["mars", "purple", "green", "cyan", "yellow", "mars"]):
    rect(190 + i * 4, 48, 2, 6, "white"); rect(190 + i * 4, 51, 2, 3, c)           # sample tubes
rect(216, 48, 10, 7, "frost"); frame(216, 48, 10, 7, "grey")                        # sample tray
desk(252, 46, 60, 12, "metalH", "metalL", "spectrometer", "purpleD")
rect(256, 47, 26, 9, "scr"); frame(256, 47, 26, 9, "purpleD")
for i, hgt in enumerate([3, 6, 4, 7, 5, 2, 6, 4]):
    rect(259 + i * 3, 55 - hgt, 2, hgt, "purple")
rect(286, 48, 22, 7, "scr"); frame(286, 48, 22, 7, "purpleD")
for j in range(5):
    for i in range(20):
        px(287 + i, 49 + j, "mars" if (i * 3 + j * 5) % 7 else "marsD")
chair(196, 66, "purpleD"); chair(276, 66, "purpleD")
for t in range(3):                                       # hydroponics trays
    tx = 172 + t * 24
    desk(tx, 88, 20, 8, "greenD", "metalD", "hydroponics")
    for k in range(4):
        cx = tx + 3 + k * 5
        px(cx, 90, "leaf"); px(cx + 1, 91, "leafD"); px(cx - 1, 91, "leaf"); px(cx, 92, "leaf"); px(cx, 89, "green")
desk(292, 80, 22, 18, "frost", "grey", "freezer")       # sample freezer
rect(294, 82, 18, 1, "white")
for i in range(3):
    px(296 + i * 6, 90, "cyan")
for wx in (230, 260):                                    # windows on the science face
    rect(wx, 24, 22, 8, "void"); frame(wx - 1, 23, 24, 10, "metalL")
    for _ in range(5):
        px(wx + rng.randrange(22), 24 + rng.randrange(8), "white")
LAYOUT["stations"].append({"role": "scientist", "label": "SCI", "x": 200, "y": 64, "interact_radius": 14})

# ============ ENGINEERING ============
for i, (lvl, c) in enumerate([(7, "green"), (5, "yellow"), (2, "red")]):   # battery banks on the face
    bx = 90 + i * 10
    rect(bx, 128, 8, 9, "scr"); frame(bx, 128, 8, 9, "grey")
    rect(bx + 1, 136 - lvl, 6, lvl, c)
cx, cy = 90, 198                                         # reactor / power core with hazard ring
for j in range(-22, 23):
    for i in range(-22, 23):
        d = math.sqrt(i * i + j * j)
        if 18 <= d <= 21:
            px(cx + i, cy + j, "yellow" if ((math.atan2(j, i) * 8 / math.pi) % 2) < 1 else "wallTop")
shade(cx - 14, cy + 12, 30, 4, 0.4)
disc(cx, cy, 15, "metalD"); disc(cx, cy, 13, "metal"); disc(cx, cy, 9, "orangeD")
disc(cx, cy, 6, "orange"); disc(cx, cy, 3, "yellow"); px(cx - 1, cy - 1, "white"); px(cx, cy - 1, "white")
for a in range(4):
    ang = a * math.pi / 2 + math.pi / 4
    line(round(cx + 9 * math.cos(ang)), round(cy + 9 * math.sin(ang)),
         round(cx + 13 * math.cos(ang)), round(cy + 13 * math.sin(ang)), "metalH")
obstacle(cx - 15, cy - 15, 30, 30, "reactor")
desk(36, 144, 44, 10, "metalL", "metal", "power-console", "orangeD")
for i in range(6):
    rect(39 + i * 6, 146, 3, 5, "metalD"); rect(39 + i * 6, 146 + (i % 2) * 2, 3, 2, "metalH")
    px(40 + i * 6, 152, "red" if i == 4 else "green")
rect(70, 140, 3, 6, "metalL"); rect(68, 138, 7, 3, "orange")                        # breaker lever
chair(52, 160, "orangeD")
for k in range(3):                                       # radiator pipes along the floor edge
    y = 238 + k * 3
    rect(34, y, 108, 2, "orangeD" if k != 1 else "orange")
    rect(34, y, 108, 1, "yellowD" if k == 1 else "redD")
obstacle(34, 238, 108, 9, "pipes")
desk(120, 152, 22, 16, "metalD", "hullD", "solar-controller")
rect(123, 155, 16, 8, "earthD")
for i in range(4):
    rect(124 + i * 4, 156, 3, 6, "earth")
LAYOUT["stations"].append({"role": "engineer", "label": "PWR", "x": 56, "y": 162, "interact_radius": 14})

# ============ HUB ============
tx, ty = 241, 190                                        # mission holo-table
shade(tx - 26, ty + 20, 54, 4, 0.35)
disc(tx, ty + 3, 24, "metalD")
disc(tx, ty, 24, "metal"); disc(tx, ty, 22, "hullD"); disc(tx, ty, 20, "scr")
ellipse_ring(tx, ty, 20, 20, "cyanD")
disc(tx, ty, 2, "yellow")
ellipse_ring(tx, ty, 7, 6, "earthD"); ellipse_ring(tx, ty, 14, 12, "marsD")
px(tx - 7, ty, "earth"); disc(tx + 10, ty - 8, 1, "mars")
for k in range(36):
    if k % 3 == 2:
        continue
    a = math.pi + k / 35 * math.pi * 0.82
    px(round(tx + 10.5 * math.cos(a) + 3.5), round(ty + 9 * math.sin(a)), "cyan")
for k in range(16):                                      # holo shimmer
    if k % 2 == 0:
        px(tx - 8 + k, ty - 22 - (k % 3), "cyanD")
obstacle(tx - 24, ty - 24, 48, 50, "holo-table")
LAYOUT["stations"].append({"role": "team", "label": "PLAN", "x": tx, "y": ty + 32, "interact_radius": 30})
rect(232, 128, 56, 8, "scr"); frame(232, 128, 56, 8, "cyanD")       # mission board on the face
text(240, 130, "SOL 1", "cyan")
for i in range(5):
    rect(262 + i * 4, 131, 2, 3, "cyan" if i < 3 else "cyanD")
desk(170, 140, 18, 8, "metalD", "hullD", "coffee")      # coffee corner
rect(173, 141, 5, 5, "metalL"); disc(183, 143, 2, "white"); px(183, 143, "crateD")
desk(298, 140, 20, 8, "metalL", "metal", "bench")
for (pxx, pyy) in [(312, 232), (168, 232)]:              # potted plants
    disc(pxx, pyy + 4, 4, "crateD"); disc(pxx, pyy + 3, 3, "crate")
    for a in range(7):
        ang = a * 2 * math.pi / 7
        line(pxx, pyy, round(pxx + 5 * math.cos(ang)), round(pyy - 2 + 4 * math.sin(ang)), "leaf")
    disc(pxx, pyy - 1, 2, "green")
    obstacle(pxx - 4, pyy - 4, 9, 12, "plant")

# ============ BRIDGE ============
desk(410, 64, 14, 96, "metalL", "metal", "nav-console", "cyanD")
for i in range(4):
    rect(412, 70 + i * 22, 10, 14, "scr"); frame(412, 70 + i * 22, 10, 14, "cyanD")
ellipse_ring(417, 77, 3, 3, "cyan"); px(417, 77, "yellow")
for k in range(8):
    px(413 + k, 99 + round(2 * math.sin(k)), "cyan")
rect(414, 115, 2, 6, "cyan"); rect(417, 112, 2, 9, "cyan"); rect(420, 117, 2, 4, "cyanD")
for i in range(3):
    disc(417, 137 + i * 4, 1, "red" if i == 0 else "cyan")
chair(398, 106, "cyanD")
desk(352, 44, 34, 10, "metalD", "hullD", "nav-aux")
rect(355, 45, 28, 6, "scr")
for k in range(26):
    px(356 + k, 48 + (1 if (k // 4) % 2 else -1) * (k % 2), "cyanD")
desk(352, 170, 30, 10, "metalD", "hullD", "nav-aux2")
for i in range(5):
    rect(355 + i * 5, 172, 3, 4, "cyan" if i % 2 else "cyanD")
desk(358, 108, 28, 16, "brgF2", "hullD", "star-chart")          # star-chart table
for (sx, sy) in [(362, 111), (367, 114), (373, 112), (379, 118), (370, 120), (382, 110)]:
    px(sx, sy, "white")
line(362, 111, 367, 114, "cyanD"); line(367, 114, 373, 112, "cyanD"); line(373, 112, 379, 118, "cyanD")
rect(386, 24, 44, 8, "scr"); frame(386, 24, 44, 8, "cyanD")    # wall screen: Mars approach
disc(422, 28, 2, "mars")
for k in range(30):
    if k % 2 == 0:
        px(389 + k, 28 + (1 if k > 20 else 0), "cyan")
LAYOUT["stations"].append({"role": "navigator", "label": "NAV", "x": 400, "y": 112, "interact_radius": 14})

# ============ CARGO ============
for (cx2, cy2) in [(348, 234), (362, 234)]:              # propellant tanks (seen from above)
    shade(cx2 - 6, cy2 + 6, 13, 2, 0.4)
    disc(cx2, cy2, 6, "metal"); disc(cx2, cy2, 4, "metalL"); disc(cx2 - 1, cy2 - 1, 1, "metalH")
    ellipse_ring(cx2, cy2, 6, 6, "cyanD")
    obstacle(cx2 - 6, cy2 - 6, 13, 13, "propellant-tank")
for (bx, by) in [(404, 230), (418, 230), (411, 238)]:     # crates
    desk(bx, by, 12, 6, "crateL", "crate", "crate")
    rect(bx, by + 3, 12, 1, "crateD"); rect(bx + 5, by, 1, 6, "crateD")
disc(386, 252, 5, "metalD"); disc(386, 252, 3, "metal")   # airlock hatch
line(383, 252, 389, 252, "yellow"); line(386, 249, 386, 255, "yellow")

# ============ floor cable (vibes) ============
cable = [(148, 216), (170, 216), (170, 226), (300, 226), (300, 168), (340, 168), (340, 184), (404, 184), (404, 166)]
for (a, b) in zip(cable, cable[1:]):
    line(a[0], a[1], b[0], b[1], "hullD")
    line(a[0], a[1] + 1, b[0], b[1] + 1, "metalD")
for (x, y) in [(230, 226), (300, 200), (370, 184)]:
    rect(x - 1, y - 1, 3, 3, "yellowD")

# ============ crew (scale reference; disable with --no-crew) ============


def astronaut(x, y, suit, facing=1):
    shade(x - 1, y + 13, 9, 2, 0.4)
    dark = mix(col(suit), (0, 0, 0), 0.3)
    rect(x, y + 6, 7, 6, suit)                                    # body
    rect(x + (7 if facing > 0 else -2), y + 7, 2, 3, suit)         # arm
    rect(x + (-1 if facing > 0 else 7), y + 7, 2, 4, dark)         # backpack edge
    rect(x + 1, y + 12, 2, 2, "metalD"); rect(x + 4, y + 12, 2, 2, "metalD")   # boots
    disc(x + 3, y + 3, 3, "white")                                 # helmet
    rect(x + (3 if facing > 0 else 0), y + 2, 4, 3, "visor")
    px(x + (5 if facing > 0 else 1), y + 2, "visorL")
    rect(x + 1, y + 9, 5, 1, mix(col(suit), (255, 255, 255), 0.3))  # suit stripe


if DRAW_CREW:
    astronaut(398, 96, "cyan", 1)        # navigator at the helm
    astronaut(54, 150, "orange", -1)     # engineer at the power console
    astronaut(98, 58, "green", 1)        # comms at the console
    astronaut(212, 104, "purple", 1)     # scientist running toward the hub

# ============ vignette inside the hull (darker corners = mood) ============
for y in range(H):
    for x in range(W):
        if in_hull(x, y):
            d = math.sqrt(((x - 240) / 260) ** 2 + ((y - 135) / 150) ** 2)
            if d > 0.75 and BAYER[y % 4][x % 4] < (d - 0.75) * 40:
                P[x, y] = mix(P[x, y], (0, 0, 0), 0.25)

# ============ export ============
suffix = "" if DRAW_CREW else "_nocrew"
img.save(f"{OUT}/ship_480x270{suffix}.png")
img.resize((W * 2, H * 2), Image.NEAREST).save(f"{OUT}/ship_960x540{suffix}.png")
img.resize((W * 4, H * 4), Image.NEAREST).save(f"{OUT}/ship_1920x1080{suffix}.png")
with open(f"{OUT}/ship_layout.json", "w") as f:
    json.dump(LAYOUT, f, indent=2)
print("ok", len(LAYOUT["obstacles"]), "obstacles")
