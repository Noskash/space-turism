#!/usr/bin/env python3
"""ASSEMBLY HANGAR for the Mars mission game: top-down (3/4 view) pixel-art map + layout JSON.

Everything is drawn procedurally at 480x270 and exported with 2x / 4x nearest-neighbour copies,
in the same palette and style as sprites/lab_assets/source/draw_ship.py.
Parts are never drawn here: the existing sprites from base_kit_assets/ and upgrade_kit_assets/
are composited (preview, shadow-board outlines) or referenced (hangar_layout.json). A part whose
sprite is missing gets a labelled crate placeholder (placeholders/), never a new part design.

Usage: python3 draw_hangar.py <out_dir> [--no-crew] [--class light|balanced|heavy]
                              [--sprites DIR] [--stats FILE]
  <out_dir>   usually sprites/hangar_assets
  --no-crew   preview without crew and info card
  --class     ship class sitting on the assembly bay in the preview (default balanced)
  --sprites   the project's sprites/ folder (default: two levels above this script)
  --stats     design_stats.json (default: <project>/data/design_stats.json)
Needs Pillow.
"""
import argparse
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(description="Draw the assembly hangar map, layout and preview.")
ap.add_argument("out_dir")
ap.add_argument("--no-crew", action="store_true", help="preview without crew / info card")
ap.add_argument("--class", dest="ship_class", default="balanced", choices=("light", "balanced", "heavy"))
ap.add_argument("--sprites", default=str(HERE.parents[1]), help="the project's sprites/ folder")
ap.add_argument("--stats", default=None, help="design_stats.json")
ARGS = ap.parse_args()

OUT = Path(ARGS.out_dir).resolve()
SPR = Path(ARGS.sprites).resolve()
ROOT = SPR.parent
BASE_DIR = SPR / "base_kit_assets"
UPG_DIR = SPR / "upgrade_kit_assets"
CREW_DIR = SPR / "crew"                     # optional <role>/sheet.png (16x16 frames, feet at 8,15)
STATS_PATH = Path(ARGS.stats) if ARGS.stats else ROOT / "data" / "design_stats.json"
FONT_PATH = ROOT / "ui" / "fonts" / "ShareTechMono-Regular.ttf"   # preview-only UI text
rng = random.Random(7)

W, H = 480, 270
C = {   # draw_ship.py palette + a few hangar tones
    "void": (9, 8, 22),
    "hullD": (30, 32, 52), "hull": (52, 56, 82), "hullL": (84, 90, 122), "hullH": (128, 136, 168),
    "wallTop": (22, 22, 38), "faceD": (44, 48, 76), "face": (62, 68, 104), "faceL": (88, 96, 138),
    "metalD": (56, 60, 82), "metal": (96, 102, 128), "metalL": (148, 156, 180), "metalH": (200, 206, 222),
    "scr": (8, 16, 24), "scrL": (16, 30, 40),
    "cyan": (72, 226, 236), "cyanD": (28, 110, 132),
    "orange": (255, 148, 50), "orangeD": (160, 72, 30), "yellow": (255, 214, 84), "yellowD": (150, 112, 30),
    "red": (232, 62, 72), "redD": (120, 30, 40),
    "green": (96, 230, 124), "greenD": (34, 116, 66),
    "purple": (186, 118, 244), "purpleD": (92, 58, 146),
    "white": (238, 240, 250), "grey": (150, 150, 172), "frost": (200, 226, 240),
    "visor": (40, 60, 90), "visorL": (140, 200, 230),
    "crate": (150, 104, 60), "crateD": (104, 70, 40), "crateL": (186, 140, 90),
    # hangar floor (painted epoxy, 16 px tiles) and assembly platform (diamond plate)
    "flr": (58, 64, 96), "flr2": (62, 68, 101), "flrG": (48, 53, 82), "flrW": (70, 77, 110),
    "plate": (78, 84, 114), "plateL": (104, 110, 142), "plateD": (60, 65, 92),
    "hazD": (30, 28, 40), "bin": (26, 28, 44), "binD": (18, 19, 32),
}
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
ROLE = {"engineer": ("orange", "orangeD"), "comms": ("green", "greenD"),
        "navigator": ("cyan", "cyanD"), "scientist": ("purple", "purpleD")}

# ============================ layout (all in 480x270 space) ============================
ROOF_H, FACE = 8, 12            # dark wall-top band y 0..7, north wall face y 8..19
FY0, FY1 = ROOF_H + FACE, 262   # floor rows y 20..261, south wall below
FX0, FX1 = 8, 472               # floor columns x 8..471
RACK_DEPTH, RACK_FACE = 26, 7   # rack top (bins) and front face heights

# Shelf contents: exactly the 20 upgrades, grouped by role (order = left to right on the rack).
SHELVES = {
    "engineer": ["solar_large", "rtg", "battery_large", "radiator", "computer_radhard", "rad_shielding"],
    "comms": ["antenna_high", "recorder_small", "recorder_large", "relay_radio"],
    "navigator": ["tank_large", "star_tracker", "reaction_wheels", "whipple_shield"],
    "scientist": ["camera_hires", "spectrometer", "radar_sounder", "thermal_imager", "magnetometer",
                  "particle_monitor"],
}
SHORT = {   # stencil under each bin (fits 4 chars in a 16 px bin)
    "solar_large": "SOLAR", "rtg": "RTG", "battery_large": "BATT", "radiator": "RAD",
    "computer_radhard": "CPU", "rad_shielding": "SHLD", "antenna_high": "DISH", "recorder_small": "REC",
    "recorder_large": "REC+", "relay_radio": "RLY", "tank_large": "TANK", "star_tracker": "STAR",
    "reaction_wheels": "RW", "whipple_shield": "WHIP", "camera_hires": "CAM", "spectrometer": "SPEC",
    "radar_sounder": "RDR", "thermal_imager": "IR", "magnetometer": "MAG", "particle_monitor": "SPM",
}
RACKS = [   # north racks stand against the wall (reach from below); south racks against the south wall
    {"role": "engineer", "side": "north", "x": 10, "label": "ENGINEER - PWR"},
    {"role": "comms", "side": "north", "x": 324, "label": "COMMS - COM"},
    {"role": "scientist", "side": "south", "x": 10, "label": "SCIENTIST - SCI"},
    {"role": "navigator", "side": "south", "right": 466, "label": "NAVIGATOR - NAV"},
]
BOARD = (160, 2, 160, 42)               # big wall board (hangs over the wall face)
BAY = (156, 48, 168, 104)               # assembly platform top surface (front face 3 px below)
ANCHOR = (240, 100)                     # centre of the ship body on the bay
PREVIEW_BOX = (160, 128)                # ShipPreview draws in a 160x128 box, body centre at (80, 62)
PREVIEW_ORIGIN = (ANCHOR[0] - 80, ANCHOR[1] - 62)
GANTRY_LEGS = (158, 318)                # left x of each gantry leg post (4 px wide, on the bay corners)
GANTRY_FOOT_Y = 84                      # where the legs stand (beam drawn overhead at y 45..50)
BENCHES = [(92, 92, 48, 12), (340, 92, 48, 12)]   # workbench tops (drop zones), 4 px face below
STANDS_TOP = 172                        # class stands row (bodies on plinths)
STAND_GAP = 10
ENTRANCE = (0, 126, 8, 40)              # airlock in the west wall
SPAWNS = [(30, 136), (50, 136), (30, 156), (50, 156)]   # feet positions
LAUNCH_DOOR = (406, 0, 64, 20)          # frame on the north wall (panels inside)
LAUNCH_ZONE = (406, 20, 64, 24)         # hazard-striped floor in front of the door
CRATES = [(448, 112, 18, 9), (448, 126, 18, 9), (448, 140, 18, 9)]
TOOL_CHEST = (444, 178, 22, 10)

LAYOUT = {"base_size": [W, H], "walkable": [], "obstacles": []}


def obstacle(x, y, w, h, kind):
    LAYOUT["obstacles"].append({"kind": kind, "x": x, "y": y, "w": w, "h": h})


# ============================ drawing helpers ============================
class Canvas:
    def __init__(self, img):
        self.img, self.P = img, img.load()
        self.w, self.h = img.size
        self.rgba = img.mode == "RGBA"


CV = None


def use(canvas):
    global CV
    CV = canvas
    return canvas


def col(c):
    return C[c] if isinstance(c, str) else tuple(c[:3])


def _put(x, y, c):
    CV.P[x, y] = (c[0], c[1], c[2], 255) if CV.rgba else (c[0], c[1], c[2])


def _get(x, y):
    return CV.P[x, y][:3]


def px(x, y, c):
    if 0 <= x < CV.w and 0 <= y < CV.h:
        _put(x, y, col(c))


def rect(x, y, w, h, c):
    c = col(c)
    for j in range(max(0, y), min(CV.h, y + h)):
        for i in range(max(0, x), min(CV.w, x + w)):
            _put(i, j, c)


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


def ellipse_ring(cx, cy, rx, ry, c, step=1):
    n = int(2 * math.pi * max(rx, ry) * 1.6)
    for k in range(0, n, step):
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
            if not (0 <= i < CV.w and 0 <= j < CV.h):
                continue
            d = math.sqrt(((i - cx) / r) ** 2 + ((j - cy) / ry) ** 2)
            if d >= 1:
                continue
            lvl = strength * (1 - d) ** 1.4 * 3
            base = math.floor(lvl)
            if (lvl - base) * 16 > BAYER[j % 4][i % 4]:
                base += 1
            if base:
                _put(i, j, mix(_get(i, j), gc, min(base / 3 * 0.75, 0.75)))


def shade(x, y, w, h, t=0.35):
    for j in range(max(0, y), min(CV.h, y + h)):
        for i in range(max(0, x), min(CV.w, x + w)):
            _put(i, j, mix(_get(i, j), (0, 0, 0), t))


def hazard(x, y, w, h, flip=False, period=3, a="yellow", b="hazD"):
    for j in range(y, y + h):
        for i in range(x, x + w):
            k = (i - j) if flip else (i + j)
            px(i, j, a if (k // period) % 2 == 0 else b)


def blit(spr, x, y, flip=False):
    """Composite an RGBA sprite at (x, y) (top-left), clipped to the canvas."""
    if spr is None:
        return
    if flip:
        spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
    sp = spr.load()
    for j in range(spr.height):
        for i in range(spr.width):
            r, g, b, a = sp[i, j]
            if a == 0 or not (0 <= x + i < CV.w and 0 <= y + j < CV.h):
                continue
            _put(x + i, y + j, (r, g, b) if a == 255 else mix(_get(x + i, y + j), (r, g, b), a / 255))


def tint(spr, c):
    """Multiply a (white) sprite by a colour; used for the socket glows."""
    c = col(c)
    out = spr.copy()
    p = out.load()
    for j in range(out.height):
        for i in range(out.width):
            r, g, b, a = p[i, j]
            p[i, j] = (r * c[0] // 255, g * c[1] // 255, b * c[2] // 255, a)
    return out


FONT = {   # 3x5 pixel font (draw_ship.py glyphs + the rest of the alphabet)
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111",
    "0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
    "4": "101101111001001", "5": "111100110001110", "6": "011100110101010", "7": "111001010010010",
    "8": "010101010101010", "9": "010101011001110",
    " ": "000000000000000", "-": "000000111000000", ".": "000000000000010", "/": "001001010100100",
    ":": "000010000010000", "+": "000010111010000", "?": "110001010000010", "%": "101001010100101",
    "$": "011110010011110", "!": "010010010000010", "^": "010101000000000", ">": "100010001010100",
    "<": "001010100010001",
}


def text(x, y, s, c, scale=1):
    for ch in s:
        g = FONT[ch]
        for k, b in enumerate(g):
            if b == "1":
                rect(x + (k % 3) * scale, y + (k // 3) * scale, scale, scale, c)
        x += 4 * scale


def text_w(s, scale=1):
    return (len(s) * 4 - 1) * scale


def text_c(cx, y, s, c, scale=1):
    text(cx - text_w(s, scale) // 2, y, s, c, scale)


def desk(x, y, w, h, top="metalL", front="metal", kind="desk", trim=None, face=4):
    """Top-down 3/4 furniture: top surface, front face, soft shadow (as in draw_ship.py)."""
    shade(x + 1, y + h + face, w, 2, 0.35)
    rect(x, y, w, h, top)
    rect(x, y, w, 1, "metalH")
    rect(x, y + h, w, face, front)
    rect(x, y + h + face - 1, w, 1, "metalD")
    if trim:
        rect(x + 1, y + h + 1, w - 2, 1, trim)
    if kind:
        obstacle(x, y, w, h + face, kind)


# ============================ data: parts, classes, stats ============================
BASE = json.loads((BASE_DIR / "parts_base.json").read_text(encoding="utf-8"))
UPG = json.loads((UPG_DIR / "parts_upgrades.json").read_text(encoding="utf-8"))
STATS = json.loads(STATS_PATH.read_text(encoding="utf-8")) if STATS_PATH.exists() else None
PARTS = {}
for _p in BASE["parts"]:
    PARTS[_p["id"]] = dict(_p, dir=BASE_DIR)
for _p in UPG["parts"]:
    PARTS[_p["id"]] = dict(_p, dir=UPG_DIR)
CLASSES = {c["id"]: c for c in BASE["classes"]}
FRAMES = UPG.get("frames", {})
_SPRITES = {}


def load(path):
    path = Path(path)
    if path not in _SPRITES:
        _SPRITES[path] = Image.open(path).convert("RGBA") if path.exists() else None
    return _SPRITES[path]


def art_path(pid, kind):
    """Path of an existing sprite (kind = 'icon' | 'mounted'), or None if the pack lacks it."""
    p = PARTS.get(pid)
    if p and p.get(kind) and (p["dir"] / p[kind]).exists():
        return p["dir"] / p[kind]
    return None


def part_name(pid):
    return PARTS.get(pid, {}).get("name") or pid.replace("_", " ").capitalize()


def res(path):
    try:
        return "res://" + Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return Path(path).as_posix()


def role_of(pid):
    return next(r for r, ids in SHELVES.items() if pid in ids)


# ============================ placeholders (missing sprites) ============================
PLACEHOLDER = {}   # pid -> {"icon": Image, "mounted": Image}


def crate_mounted(label):
    """World-scale crate with a paper label: stands in for a missing mounted/ sprite."""
    w, h = text_w(label) + 6, 13
    im = use(Canvas(Image.new("RGBA", (w, h), (0, 0, 0, 0))))
    rect(0, 0, w, h, "crateD")
    rect(1, 1, w - 2, 2, "crateL")                 # lid
    rect(1, 3, w - 2, 1, "crateD")
    rect(1, 4, w - 2, h - 5, "crate")
    rect(2, 5, w - 4, 7, "frost")                  # paper label
    text(3, 6, label, "wallTop")
    px(1, 1, "crate"); px(w - 2, 1, "crate")
    return im.img


def crate_icon(pid, role):
    """32x32 icon: the role's icon frame (copied from an existing icon) with a labelled crate."""
    rc, rd = ROLE[role]
    donor = next((art_path(q, "icon") for q in SHELVES[role] if art_path(q, "icon")), None)
    if donor:
        img = load(donor).copy()
        tile = img.crop((2, 3, 10, 11))            # 8x8 of plain icon background
        for ty in range(3, 31, 8):
            for tx in range(2, 30, 8):
                img.paste(tile.crop((0, 0, min(8, 30 - tx), min(8, 31 - ty))), (tx, ty))
    else:
        img = Image.new("RGBA", (32, 32), col("binD") + (255,))
    use(Canvas(img))
    if not donor:
        frame(0, 0, 32, 32, rd); rect(1, 1, 30, 2, rc)
    rect(7, 4, 18, 14, "crateD")
    rect(8, 5, 16, 3, "crateL"); rect(8, 8, 16, 1, "crateD"); rect(8, 9, 16, 8, "crate")
    line(8, 9, 23, 16, "crateD"); line(8, 16, 23, 9, "crateD")     # cross braces
    rect(13, 10, 6, 6, "frost")
    text(14, 10, "?", "wallTop")
    label = part_name(pid).split()[0].upper()[:7]
    text_c(16, 20, label, rc)                      # rows 20-24, clear of the "+" at 27-29
    rect(28, 27, 1, 3, rc); rect(27, 28, 3, 1, rc)   # the pack's "+" upgrade marker
    return img


for _role, _ids in SHELVES.items():
    for _pid in _ids:
        if not art_path(_pid, "icon") or not art_path(_pid, "mounted"):
            PLACEHOLDER[_pid] = {"icon": crate_icon(_pid, _role), "mounted": crate_mounted(SHORT[_pid])}


def part_sprite(pid, kind):
    path = art_path(pid, kind)
    return load(path) if path else PLACEHOLDER[pid][kind]


# ============================ socket glows (white, game modulates) ============================
def make_cell_glow():
    """16x16: bright ring on a 12x12 cell (offset 2) + dithered halo. White: tint per role."""
    im = use(Canvas(Image.new("RGBA", (16, 16), (0, 0, 0, 0))))
    frame(2, 2, 12, 12, "white")
    for j in range(16):
        for i in range(16):
            d = max(abs(i - 7.5), abs(j - 7.5))
            if 6.5 < d < 7.5 and BAYER[j % 4][i % 4] < 8:
                px(i, j, "white")
            if 7.5 < d and BAYER[j % 4][i % 4] < 3:
                px(i, j, "white")
            if d < 4.5 and BAYER[j % 4][i % 4] == 0:   # faint dotted fill
                px(i, j, "white")
    for (i, j) in ((3, 3), (12, 3), (3, 12), (12, 12)):
        px(i, j, "white")
    return im.img


def make_mount_glow():
    """11x11 diamond ring + dithered halo for external mount points (wings / top / boom)."""
    im = use(Canvas(Image.new("RGBA", (11, 11), (0, 0, 0, 0))))
    for j in range(11):
        for i in range(11):
            d = abs(i - 5) + abs(j - 5)
            if d == 3:
                px(i, j, "white")
            elif d in (4, 5) and BAYER[j % 4][i % 4] < (8 if d == 4 else 3):
                px(i, j, "white")
    px(5, 5, "white")
    return im.img


CELL_GLOW, MOUNT_GLOW = make_cell_glow(), make_mount_glow()


# ============================ info card (9-slice, no text) ============================
CARD_MARGINS = {"left": 6, "top": 14, "right": 6, "bottom": 6}


def make_info_card():
    w = h = 48
    im = use(Canvas(Image.new("RGBA", (w, h), (0, 0, 0, 0))))
    rect(0, 0, w, h, "wallTop")                    # 1 px outline
    rect(1, 1, w - 2, h - 2, "metal")              # 2 px bevelled frame
    rect(1, 1, w - 2, 1, "metalL"); rect(1, 1, 1, h - 2, "metalL")
    rect(1, h - 2, w - 2, 1, "metalD"); rect(w - 2, 1, 1, h - 2, "metalD")
    rect(3, 3, w - 6, 9, "faceD")                  # header band (name goes here)
    rect(3, 3, w - 6, 1, "face")
    rect(3, 12, w - 6, 1, "metalD")                # separator
    rect(3, 13, w - 6, h - 16, (14, 18, 32))       # body
    rect(3, 13, w - 6, 1, (24, 30, 48))
    for (i, j) in ((4, 5), (w - 5, 5), (4, h - 5), (w - 5, h - 5)):   # rivets in the fixed corners
        px(i, j, "metalH")
    return im.img


INFO_CARD = make_info_card()


def nine_slice(src, w, h, m):
    out = Image.new("RGBA", (w, h))
    sw, sh = src.size
    xs = [(0, m["left"], 0, m["left"]), (m["left"], sw - m["right"], m["left"], w - m["right"]),
          (sw - m["right"], sw, w - m["right"], w)]
    ys = [(0, m["top"], 0, m["top"]), (m["top"], sh - m["bottom"], m["top"], h - m["bottom"]),
          (sh - m["bottom"], sh, h - m["bottom"], h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            part = src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.paste(part, (dx0, dy0))
    return out


# ================================================================================
#                                   THE MAP
# ================================================================================
MAP = use(Canvas(Image.new("RGB", (W, H), C["wallTop"])))

# ---------- floor: painted epoxy, 16 px tiles, light wear ----------
for j in range(FY0, FY1):
    for i in range(FX0, FX1):
        c = "flrG" if (i % 16 == 0 or j % 16 == 4) else ("flr2" if ((i // 16) + ((j - 4) // 16)) % 2 else "flr")
        r = rng.random()
        if c != "flrG" and r < 0.012:
            c = "flrW"
        elif c != "flrG" and r < 0.02:
            c = "flrG"
        px(i, j, c)
LAYOUT["walkable"].append({"x": FX0, "y": FY0, "w": FX1 - FX0, "h": FY1 - FY0})

# ---------- walls ----------
rect(0, 0, W, ROOF_H, "wallTop")                                    # roof edge of the north wall
rect(0, ROOF_H, W, FACE, "face")                                    # north wall face
rect(0, ROOF_H, W, 1, "faceL")
rect(0, ROOF_H + FACE - 2, W, 2, "faceD")
for i in range(6, W, 24):
    rect(i, ROOF_H + 2, 1, FACE - 4, "faceD")                       # panel seams
shade(FX0, FY0, FX1 - FX0, 2, 0.3)                                  # contact shadow under the wall
rect(0, ROOF_H, FX0, H - ROOF_H, "wallTop")                         # west wall (seen from above)
rect(FX0 - 1, ROOF_H, 1, FY1 - ROOF_H, "hullL")
rect(FX1, ROOF_H, W - FX1, H - ROOF_H, "wallTop")                   # east wall
rect(FX1, ROOF_H, 1, FY1 - ROOF_H, "hullL")
rect(0, FY1, W, H - FY1, "wallTop")                                 # south wall (cut away)
rect(FX0 - 1, FY1, FX1 - FX0 + 2, 1, "hullL")
rect(FX0 - 1, FY1 + 1, FX1 - FX0 + 2, 1, "hull")
shade(FX0, FY0, 2, FY1 - FY0, 0.2)
for y in range(40, FY1 - 8, 48):                                    # structural columns in the side walls
    for x in (1, FX1 + 1):
        rect(x, y, 6, 7, "hull"); rect(x, y, 6, 1, "hullL"); rect(x + 1, y + 2, 4, 3, "hullD")

# ---------- painted floor: lanes, zones, stencils (before props) ----------
bx, by, bw, bh = BAY
for i in range(bx - 4, bx + bw + 4):                                # bay keep-out line (dashed)
    if (i // 4) % 2 == 0:
        px(i, by + bh + 6, "yellowD")
for j in range(by, by + bh + 7):
    if (j // 4) % 2 == 0:
        px(bx - 4, j, "yellowD"); px(bx + bw + 3, j, "yellowD")
text_c(240, 161, "ASSEMBLY BAY 1", "yellowD")
for k in range(3):                                                  # launch lane: chevrons to the door
    cx, cy = LAUNCH_ZONE[0] + LAUNCH_ZONE[2] // 2, 70 - k * 9
    for d in range(4):
        px(cx - d, cy + d, "yellowD"); px(cx + d, cy + d, "yellowD")
        px(cx - d, cy + d + 1, "yellowD"); px(cx + d, cy + d + 1, "yellowD")
ex, ey, ew, eh = ENTRANCE                                            # entrance mat + arrow
rect(FX0, ey + 2, 12, eh - 4, "hazD")
for j in range(ey + 3, ey + eh - 3, 3):
    rect(FX0 + 1, j, 10, 1, "hull")
for d in range(3):
    px(24 + d, 146 - 2 + d, "yellowD"); px(24 + d, 146 + 2 - d, "yellowD")
for k, (sx, sy) in enumerate(SPAWNS):                               # spawn marks (neutral; role ring is runtime)
    ellipse_ring(sx, sy - 1, 7, 4, "frost", 1)
    ellipse_ring(sx, sy - 1, 6, 3, "hullL", 2)
    text_c(sx, sy - 3, str(k + 1), "frost")
text(24, 168, "CREW", "metal")

# ---------- light pools: overhead lights + role / bay accents (props drawn after stay crisp) ----------
for (gx, gy) in [(80, 100), (400, 100), (90, 190), (400, 200), (240, 212)]:
    glow(gx, gy, 46, "white", 0.17, 30)
glow(ANCHOR[0], ANCHOR[1], 96, "cyan", 0.28, 62)                    # assembly bay
glow(LAUNCH_ZONE[0] + 32, 30, 44, "yellow", 0.3, 22)                # launch door
glow(14, ey + eh // 2, 22, "green", 0.3, 26)                        # entrance light

# ---------- shelf racks ----------
SHELF_SLOTS = []
RACK_RECTS = []


def bin_w(pid):
    return max(16, part_sprite(pid, "mounted").width + 4)


def draw_rack(cfg):
    role, side = cfg["role"], cfg["side"]
    rc, rd = ROLE[role]
    ids = SHELVES[role]
    widths = [bin_w(p) for p in ids]
    w = 4 + sum(widths) + 2 * (len(ids) - 1)
    x0 = cfg["x"] if "x" in cfg else cfg["right"] - w
    top = FY0 if side == "north" else FY1 - RACK_FACE - RACK_DEPTH
    face_y = top + RACK_DEPTH
    glow(x0 + w // 2, (face_y + 10) if side == "north" else (top - 10), w // 2 + 10, rc, 0.32, 14)
    # header with the role label: backboard on the wall face (north) / plate on the back rim (south)
    if side == "north":
        hy, hh = 3, FY0 - 3
        rect(x0, hy, w, hh, "wallTop"); frame(x0, hy, w, hh, rd)
        rect(x0 + 1, hy + 1, w - 2, 1, rc)
        text_c(x0 + w // 2, hy + 3, cfg["label"], rc)
        for j in range(hy + 10, hy + hh - 1, 3):                     # pegboard holes
            for i in range(x0 + 3, x0 + w - 3, 3):
                px(i, j, "faceD")
        obstacle(x0, top, w, RACK_DEPTH + RACK_FACE, f"rack-{role}")
        head_rect = (x0, hy, w, hh)
    else:
        hy, hh = top - 8, 9
        shade(x0, hy - 2, w, 2, 0.25)
        rect(x0 + 1, hy, 2, hh + 2, "metalD"); rect(x0 + w - 3, hy, 2, hh + 2, "metalD")   # posts
        rect(x0 + 3, hy, w - 6, hh - 1, "wallTop"); frame(x0 + 3, hy, w - 6, hh - 1, rd)
        rect(x0 + 4, hy + 1, w - 8, 1, rc)
        text_c(x0 + w // 2, hy + 2, cfg["label"], rc)
        obstacle(x0, hy, w, FY1 - hy, f"rack-{role}")
        head_rect = (x0, hy, w, hh)
    # top surface + bins
    rect(x0, top, w, RACK_DEPTH, "metal")
    rect(x0, top, w, 1, "metalH")
    rect(x0, top + RACK_DEPTH - 1, w, 1, "metalD")
    bx_ = x0 + 2
    for pid, bw_ in zip(ids, widths):
        bx0, by0, bh_ = bx_, top + 2, RACK_DEPTH - 4
        rect(bx0, by0, bw_, bh_, "bin")
        rect(bx0, by0, bw_, 1, "binD"); rect(bx0, by0, 1, bh_, "binD")       # inner shadow
        rect(bx0, by0 + bh_ - 1, bw_, 1, mix(col("bin"), col(rd), 0.35))   # role-tinted lip
        spr = part_sprite(pid, "mounted")                                    # shadow-board outline
        sx, sy = bx0 + (bw_ - spr.width) // 2, by0 + (bh_ - spr.height) // 2
        a = spr.load()
        for j in range(spr.height):
            for i in range(spr.width):
                if a[i, j][3] == 0:
                    continue
                edge = any(not (0 <= i + di < spr.width and 0 <= j + dj < spr.height) or a[i + di, j + dj][3] == 0
                           for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                px(sx + i, sy + j, mix(col("bin"), col(rd), 0.7) if edge else "binD")
        # face: role stripe + stencil name under the bin
        cx = bx0 + bw_ // 2
        SHELF_SLOTS.append({
            "part_id": pid, "role": role, "name": part_name(pid),
            "x": cx, "y": by0 + bh_ // 2,
            "interact_radius": 28 if side == "north" else 26,   # closest stand: 23 / 22 px
            "bin": {"x": bx0, "y": by0, "w": bw_, "h": bh_},
            "icon": res(art_path(pid, "icon")) if art_path(pid, "icon") else res(OUT / "placeholders/icons" / f"{pid}.png"),
            "mounted": res(art_path(pid, "mounted")) if art_path(pid, "mounted") else res(OUT / "placeholders/mounted" / f"{pid}.png"),
            "missing_art": pid in PLACEHOLDER,
        })
        bx_ += bw_
        if bx_ < x0 + w - 2:                                                 # divider
            rect(bx_, top + 1, 2, RACK_DEPTH - 2, "metalL")
            rect(bx_ + 1, top + 1, 1, RACK_DEPTH - 2, "metal")
            bx_ += 2
    shade(x0, face_y + RACK_FACE, w, 2, 0.35)
    rect(x0, face_y, w, RACK_FACE, "face")
    rect(x0, face_y, w, 1, rc)
    rect(x0, face_y + RACK_FACE - 1, w, 1, "faceD")
    for s in SHELF_SLOTS[-len(ids):]:
        text_c(s["x"], face_y + 1, SHORT[s["part_id"]], mix(col(rc), col("white"), 0.25))
    # loading-zone line on the floor in front of the rack
    ly = face_y + RACK_FACE + 5 if side == "north" else hy - 5
    for i in range(x0, x0 + w):
        if (i // 3) % 2 == 0:
            px(i, ly, rd)
    RACK_RECTS.append({"role": role, "label": cfg["label"], "x": x0, "y": min(top, head_rect[1]),
                       "w": w, "h": max(face_y + RACK_FACE, head_rect[1] + head_rect[3]) - min(top, head_rect[1]),
                       "side": side})


for _cfg in RACKS:
    draw_rack(_cfg)

# ---------- wall board (limits) ----------
gx, gy, gw, gh = BOARD
BOARD_FIELDS = {}
shade(gx + 2, gy + gh, gw - 2, 3, 0.4)
for cxb in (gx + 12, gx + gw - 13):                                 # hanging cables
    rect(cxb, 0, 1, gy + 1, "metalL")
rect(gx, gy, gw, gh, "wallTop")
frame(gx + 1, gy + 1, gw - 2, gh - 2, "metal")
rect(gx + 1, gy + 1, gw - 2, 1, "metalL")
rect(gx + 1, gy + gh - 2, gw - 2, 1, "metalD")
sx0, sy0, sx1, sy1 = gx + 3, gy + 3, gx + gw - 3, gy + gh - 3
rect(sx0, sy0, sx1 - sx0, sy1 - sy0, "scr")
for j in range(sy0, sy1, 2):                                        # faint scanlines
    for i in range(sx0, sx1):
        if BAYER[j % 4][i % 4] < 2:
            px(i, j, "scrL")
text(gx + 6, gy + 5, "SPACECRAFT BUILD", "cyan")
text(gx + 90, gy + 5, "CLASS", "cyanD")
BOARD_FIELDS["class"] = {"x": gx + 112, "y": gy + 3, "w": 44, "h": 8}
rect(sx0 + 1, gy + 11, sx1 - sx0 - 2, 1, "cyanD")
rows = [("mass", "MASS", "cyan"), ("power", "POWER", "green"), ("budget", "BUDGET", "yellow"), ("slots", "SLOTS", "purple")]
for k, (fid, label, c) in enumerate(rows):
    ry = gy + 14 + k * 6
    text(gx + 6, ry, label, mix(col(c), col("white"), 0.2))
    frame(gx + 32, ry, 62, 5, "metalD")
    rect(gx + 33, ry + 1, 60, 3, "scrL")
    for i in range(gx + 33 + 15, gx + 93, 15):
        px(i, ry + 1, "metalD"); px(i, ry + 3, "metalD")          # quarter ticks
    BOARD_FIELDS[fid] = {"bar": {"x": gx + 33, "y": ry + 1, "w": 60, "h": 3},
                         "value": {"x": gx + 96, "y": ry - 1, "w": 30, "h": 7}}
rkx, rky, rkw, rkh = gx + 128, gy + 13, 27, 26
frame(rkx, rky, rkw, rkh, "cyanD")
text_c(rkx + rkw // 2, rky + 2, "ROCKET", "cyanD")
rcx = rkx + rkw // 2                                                # tiny rocket pictogram
rect(rcx - 1, rky + 9, 3, 8, "metalL"); px(rcx, rky + 8, "metalL"); px(rcx, rky + 7, "white")
px(rcx - 2, rky + 15, "metal"); px(rcx + 2, rky + 15, "metal"); px(rcx - 2, rky + 16, "metal"); px(rcx + 2, rky + 16, "metal")
px(rcx, rky + 17, "orange")
BOARD_FIELDS["rocket"] = {"x": rkx + 1, "y": rky + 18, "w": rkw - 2, "h": 7}
obstacle(152, FY0, 172, BOARD[1] + BOARD[3] - FY0 + 2, "board")
LAYOUT["board"] = {"x": gx, "y": gy, "w": gw, "h": gh, "fields": BOARD_FIELDS}

# ---------- launch door (north wall) ----------
lx, ly, lw, lh = LAUNCH_DOOR
rect(lx, ly, lw, lh, "hullD")
frame(lx, ly, lw, lh, "metalD")
rect(lx + 1, ly + 1, lw - 2, 1, "metal")
READY_LIGHTS = []
for k in range(4):                                                  # one READY lamp per player (lit at runtime)
    lxk = lx + 11 + k * 13
    rect(lxk - 2, ly + 1, 5, 3, "wallTop")
    rect(lxk - 1, ly + 2, 3, 1, "redD")
    READY_LIGHTS.append({"x": lxk, "y": ly + 2})
dx0, dy0, dw, dh = lx + 3, ly + 5, lw - 6, lh - 5
mid = dx0 + dw // 2
hazard(dx0, dy0, mid - dx0, dh, flip=False)                         # chevrons point at the seam
hazard(mid, dy0, dx0 + dw - mid, dh, flip=True)
rect(dx0, dy0, dw, 1, "metalL"); rect(dx0, dy0 + dh - 1, dw, 1, "hazD")
rect(mid - 1, dy0, 2, dh, "hazD"); rect(mid, dy0 + 1, 1, dh - 2, "frost")   # seam with daylight
zx, zy, zw, zh = LAUNCH_ZONE
hazard(zx, zy, zw, 2); hazard(zx, zy + zh - 2, zw, 2)
hazard(zx, zy, 2, zh); hazard(zx + zw - 2, zy, 2, zh)
text_c(zx + zw // 2, zy + 9, "LAUNCH", "yellow")
LAYOUT["launch_door"] = {"x": lx, "y": ly, "w": lw, "h": lh, "ready_lights": READY_LIGHTS,
                         "zone": {"x": zx, "y": zy, "w": zw, "h": zh}}

# ---------- assembly bay: raised platform, cradle, gantry ----------
shade(bx + 2, by + bh + 3, bw, 2, 0.35)
for j in range(by, by + bh):                                        # diamond plate
    for i in range(bx, bx + bw):
        c = "plate"
        if (i % 6, j % 6) in ((1, 1), (4, 4)):
            c = "plateL"
        elif (i % 6, j % 6) in ((2, 2), (5, 5)):
            c = "plateD"
        px(i, j, mix(_get(i, j), col(c), 0.8))                      # keep a hint of the bay glow
hazard(bx, by, bw, 3); hazard(bx, by + bh - 3, bw, 3)
hazard(bx, by, 3, bh); hazard(bx + bw - 3, by, 3, bh)
rect(bx, by + bh, bw, 3, "faceD"); rect(bx, by + bh, bw, 1, "face")      # low front step
for rx_ in (bx + 20, bx + bw - 36):                                 # ramps up onto the platform
    rect(rx_, by + bh - 3, 16, 6, "metal")
    for i in range(rx_ + 1, rx_ + 15, 2):
        rect(i, by + bh - 2, 1, 4, "metalL")
ax, ay = ANCHOR
CRADLE = (ax - 37, ay - 37, 74, 74)
cx_, cy_, cw_, ch_ = CRADLE
rect(cx_, cy_, cw_, ch_, "hull")
frame(cx_, cy_, cw_, ch_, "metalD")
rect(cx_ + 1, cy_ + 1, cw_ - 2, 1, "hullL")
for j in range(cy_ + 2, cy_ + ch_ - 1):
    for i in range(cx_ + 2, cx_ + cw_ - 1):
        if (i - cx_) % 12 == 7 or (j - cy_) % 12 == 7:
            px(i, j, "hullD")                                        # 12 px build grid
for half, c in ((20, "cyanD"), (26, "cyanD"), (32, "cyan")):        # size guides: light / balanced / heavy
    for sx_, sy_ in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x_, y_ = ax + sx_ * half - (1 if sx_ > 0 else 0), ay + sy_ * half - (1 if sy_ > 0 else 0)
        rect(min(x_, x_ - sx_ * 3), y_, 4, 1, c)
        rect(x_, min(y_, y_ - sy_ * 3), 1, 4, c)
for sx_, sy_ in ((-1, -1), (1, -1), (-1, 1), (1, 1)):               # clamps
    x_, y_ = ax + sx_ * 35, ay + sy_ * 35
    rect(x_ - 2, y_ - 2, 4, 4, "yellowD"); rect(x_ - 1, y_ - 1, 2, 2, "yellow")
text(cx_ + 3, cy_ + ch_ - 7, "L B H", "cyanD")
gfy = GANTRY_FOOT_Y                                                 # gantry crane: legs here, beam in the overlay
shade(bx, gfy - 1, bw, 3, 0.25)                                     # beam shadow across the bay
for lgx in GANTRY_LEGS:
    shade(lgx - 1, gfy + 3, 7, 2, 0.4)
    rect(lgx - 2, gfy - 1, 8, 4, "metalD"); rect(lgx - 2, gfy - 1, 8, 1, "metal")
    rect(lgx, 50, 4, gfy - 50, "yellowD"); rect(lgx, 50, 1, gfy - 50, "yellow")
    for j in range(54, gfy - 2, 8):
        rect(lgx, j, 4, 1, "hazD")
    obstacle(lgx - 2, gfy - 2, 8, 6, "gantry-leg")
LAYOUT["assembly"] = {
    "x": bx, "y": by, "w": bw, "h": bh,
    "body_anchor": {"x": ax, "y": ay},
    "preview_origin": {"x": PREVIEW_ORIGIN[0], "y": PREVIEW_ORIGIN[1]},
    "cradle": {"x": cx_, "y": cy_, "w": cw_, "h": ch_},
}

# ---------- workbenches ----------
BENCH_LIST = []
for (wx, wy, ww, wh) in BENCHES:
    desk(wx, wy, ww, wh, "metalL", "metal", "bench", "yellowD")
    rect(wx + 2, wy + 2, ww - 4, wh - 3, "hullD")                   # rubber mat
    for i in range(wx + 2, wx + ww - 2, 4):
        for j in range(wy + 2, wy + wh - 1, 4):
            px(i, j, "hull")
    rect(wx - 2, wy + wh, 2, 4, "metalD"); rect(wx + ww, wy + wh, 2, 4, "metalD")   # vise jaws
    BENCH_LIST.append({"x": wx + 2, "y": wy + 2, "w": ww - 4, "h": wh - 3})
LAYOUT["benches"] = BENCH_LIST

# ---------- class stands: the 3 bodies on plinths ----------
order = ["light", "balanced", "heavy"]
sizes = {k: CLASSES[k]["body_size"] for k in order}
total = sum(sizes[k][0] + 6 for k in order) + STAND_GAP * 2
sx = 240 - total // 2
STANDS = []
for k in order:
    bw_, bh_ = sizes[k]
    pw, ph = bw_ + 6, bh_ + 6
    shade(sx + 1, STANDS_TOP + ph + 7, pw, 2, 0.35)
    rect(sx, STANDS_TOP, pw, ph, "metalD")
    rect(sx, STANDS_TOP, pw, 1, "metal")
    rect(sx + 1, STANDS_TOP + 1, pw - 2, ph - 2, "hullD")
    frame(sx + 1, STANDS_TOP + 1, pw - 2, ph - 2, "hull")
    rect(sx, STANDS_TOP + ph, pw, 7, "face")
    rect(sx, STANDS_TOP + ph, pw, 1, "faceL")
    rect(sx, STANDS_TOP + ph + 6, pw, 1, "faceD")
    name = CLASSES[k]["id"].upper()
    text(sx + 2, STANDS_TOP + ph + 1, name, "metalH")
    slots_n = CLASSES[k]["upgrade_slots"]
    for s_ in range(slots_n):                                       # one pip per upgrade slot
        px(sx + pw - 3 - s_ * 2, STANDS_TOP + ph + 3, "cyan")
    lamp = {"x": sx + pw - 3, "y": STANDS_TOP + 2}
    rect(lamp["x"] - 1, lamp["y"], 2, 2, "wallTop"); px(lamp["x"], lamp["y"], "metal")
    body = load(BASE_DIR / CLASSES[k]["body"])
    blit(body, sx + 3, STANDS_TOP + 3)
    obstacle(sx, STANDS_TOP, pw, ph + 7, f"stand-{k}")
    STANDS.append({"class": k, "x": sx + 3 + bw_ // 2, "y": STANDS_TOP + 3 + bh_ // 2,
                   "interact_radius": bh_ // 2 + 18, "lamp": lamp,
                   "plinth": {"x": sx, "y": STANDS_TOP, "w": pw, "h": ph + 7}})
    sx += pw + STAND_GAP
LAYOUT["class_stands"] = STANDS

# ---------- entrance airlock (west wall) ----------
rect(ex, ey, ew, eh, "hullD")
rect(ex + 1, ey + 1, ew - 2, eh - 2, "metal")
rect(ex + ew // 2 - 1, ey + 1, 1, eh - 2, "metalD")
rect(ex, ey - 2, ew + 2, 2, "metalD"); rect(ex, ey + eh, ew + 2, 2, "metalD")
rect(ex + 2, ey + 4, 3, 2, "green")
LAYOUT["entrance"] = {"x": ex, "y": ey, "w": ew, "h": eh}
LAYOUT["spawns"] = [{"x": x, "y": y} for (x, y) in SPAWNS]

# ---------- decor: delivery crates + tool chest (east side) ----------
for (cx2, cy2, cw2, ch2) in CRATES:
    desk(cx2, cy2, cw2, ch2, "crateL", "crate", None)
    rect(cx2, cy2 + ch2 // 2, cw2, 1, "crateD"); rect(cx2 + cw2 // 2, cy2, 1, ch2, "crateD")
obstacle(CRATES[0][0], CRATES[0][1], CRATES[0][2], CRATES[-1][1] + CRATES[-1][3] + 4 - CRATES[0][1], "crates")
tx, ty, tw, th = TOOL_CHEST
desk(tx, ty, tw, th, "red", "redD", "tool-chest")
for k in range(3):
    rect(tx + 2, ty + th + 1 + k, tw - 4, 1, "redD" if k % 2 else "red")
rect(tx + tw // 2 - 2, ty + 3, 4, 2, "metalL")

# ---------- vignette (darker corners = mood) ----------
for y in range(H):
    for x in range(W):
        d = math.sqrt(((x - 240) / 262) ** 2 + ((y - 135) / 152) ** 2)
        if d > 0.78 and BAYER[y % 4][x % 4] < (d - 0.78) * 40:
            _put(x, y, mix(_get(x, y), (0, 0, 0), 0.22))

MAP_IMG = MAP.img.copy()

# ================================================================================
#                 OVERLAY (above the crew): the gantry crane beam
# ================================================================================
OVL = use(Canvas(Image.new("RGBA", (W, H), (0, 0, 0, 0))))
gl, gr = GANTRY_LEGS[0] - 2, GANTRY_LEGS[1] + 6     # beam spans the bay only (clear of the racks)
rect(gl, 44, gr - gl, 7, "wallTop")
rect(gl + 1, 45, gr - gl - 2, 5, "yellow")
rect(gl + 1, 45, gr - gl - 2, 1, (255, 236, 150))
rect(gl + 1, 49, gr - gl - 2, 1, "yellowD")
for i in range(gl + 4, gr - 4, 10):
    px(i, 47, "yellowD"); px(i + 1, 47, "yellowD")                 # bolt line
trx = 278                                                           # trolley + hook
rect(trx - 6, 43, 13, 9, "wallTop"); rect(trx - 5, 44, 11, 7, "metal")
rect(trx - 5, 44, 11, 1, "metalL"); rect(trx - 3, 46, 7, 3, "metalD")
rect(trx, 52, 1, 11, "metalL")
rect(trx - 2, 63, 5, 2, "metal"); px(trx - 2, 65, "metalL"); px(trx - 2, 66, "metalL")
px(trx - 1, 67, "metalL"); px(trx, 67, "metalL"); px(trx + 1, 66, "metalL")
OVL_IMG = OVL.img.copy()
LAYOUT["overlay"] = {"note": "draw above the crew (gantry beam overhead)", "z": "above_crew"}


# ================================================================================
#                 PREVIEW: stocked shelves, ship on the bay, crew carrying parts
# ================================================================================
def ship_preview(ox0, oy0, cls_id, upgrades):
    """Port of scripts/design/ship_preview.gd _draw(): identical placement of body + parts."""
    cls = CLASSES[cls_id]
    body = load(BASE_DIR / cls["body"])
    bw_, bh_ = body.size
    ox = ox0 + (PREVIEW_BOX[0] - bw_) // 2
    oy = oy0 + (PREVIEW_BOX[1] - bh_) // 2 - 2
    wing = part_sprite("solar_large", "mounted") if "solar_large" in upgrades \
        else load(BASE_DIR / PARTS["solar_small"]["mounted"])
    wy = oy + bh_ // 2 - wing.height // 2
    blit(wing, ox - wing.width, wy, flip=True)
    blit(wing, ox + bw_, wy)
    if "magnetometer" in upgrades:
        blit(part_sprite("magnetometer", "mounted"), ox + bw_ - 3, oy + bh_ - 3)
    blit(body, ox, oy)
    top = part_sprite("antenna_high", "mounted") if "antenna_high" in upgrades \
        else load(BASE_DIR / PARTS["antenna_low"]["mounted"])
    blit(top, ox + bw_ // 2 - top.width // 2, oy - top.height + 2)
    eng = load(BASE_DIR / PARTS["engine_main"]["mounted"])
    blit(eng, ox + bw_ // 2 - eng.width // 2, oy + bh_ - 1)
    thr = load(BASE_DIR / PARTS["thrusters_basic"]["mounted"])
    for (tx_, ty_) in ((ox - 1, oy - 1), (ox + bw_ - 3, oy - 1), (ox - 1, oy + bh_ - 3), (ox + bw_ - 3, oy + bh_ - 3)):
        blit(thr, tx_, ty_)
    slots = []
    for cell in cls["cells"]:
        if cell["use"] == "upgrade_slot":
            slots.append(cell)
        else:
            spr = load(BASE_DIR / PARTS[cell["use"]]["mounted"])
            blit(spr, ox + cell["x"] + (12 - spr.width) // 2, oy + cell["y"] + (12 - spr.height) // 2)
    for i, pid in enumerate(upgrades[:len(slots)]):
        at = (ox + slots[i]["x"], oy + slots[i]["y"])
        p = PARTS[pid]
        fr = FRAMES.get(p["role"], {})
        if p["mount"] == "cell":
            rect(at[0] + 1, at[1] + 1, 10, 10, "metalD")
            spr = part_sprite(pid, "mounted")
            blit(spr, at[0] + (12 - spr.width) // 2, at[1] + (12 - spr.height) // 2)
            blit(load(UPG_DIR / fr["slot"]), *at)
        else:
            blit(load(UPG_DIR / fr["linked"]), *at)
    return {"ox": ox, "oy": oy, "bw": bw_, "bh": bh_, "open": slots[len(upgrades):], "wing": wing, "wy": wy}


def evaluate(cls_id, upgrades):
    """Port of DesignRules.evaluate (needs design_stats.json)."""
    if not STATS:
        return None
    cls, base = STATS["classes"][cls_id], STATS["base"]
    mass, cost = float(cls["dry_mass_kg"]), float(cls["cost"])
    gen = float(base["solar_w"])
    draw = -float(base["base_w"] + base["instruments_w"] + base["transmitter_w"])
    for pid in upgrades:
        p = STATS["parts"].get(pid, {})
        mass += p.get("mass_kg", 0); cost += p.get("cost", 0)
        wv = p.get("power_w", 0)
        if wv >= 0:
            gen += wv
        else:
            draw -= wv
    launcher = next((l for l in STATS["launchers"] if mass <= l["capacity_kg"] * 0.9), None)
    if launcher:
        cost += launcher["cost"]
    return {"mass": mass, "mass_limit": float(cls["mass_limit_kg"]), "cost": cost, "budget": float(STATS["total_budget"]),
            "gen": gen, "draw": draw, "net": gen - draw, "slots_used": len(upgrades),
            "slots": CLASSES[cls_id]["upgrade_slots"], "launcher": launcher, "class": cls["name"]}


def astronaut(x, y, suit, facing=1, arms_up=False):
    """draw_ship.py's astronaut (top-left x, y; feet at y + 14)."""
    shade(x - 1, y + 13, 9, 2, 0.4)
    dark = mix(col(suit), (0, 0, 0), 0.3)
    rect(x, y + 6, 7, 6, suit)
    if arms_up:
        rect(x - 1, y + 1, 1, 7, suit); rect(x + 7, y + 1, 1, 7, suit)
    else:
        rect(x + (7 if facing > 0 else -2), y + 7, 2, 3, suit)
        rect(x + (-1 if facing > 0 else 7), y + 7, 2, 4, dark)
    rect(x + 1, y + 12, 2, 2, "metalD"); rect(x + 4, y + 12, 2, 2, "metalD")
    disc(x + 3, y + 3, 3, "white")
    rect(x + (3 if facing > 0 else 0), y + 2, 4, 3, "visor")
    px(x + (5 if facing > 0 else 1), y + 2, "visorL")
    rect(x + 1, y + 9, 5, 1, mix(col(suit), (255, 255, 255), 0.3))


def crew(fx, fy, role, facing=1, carry=None):
    rc = ROLE[role][0]
    ellipse_ring(fx, fy - 1, 6, 2.5, rc)                            # role ring, as CrewMember draws it
    sheet = load(CREW_DIR / role / "sheet.png")
    if sheet is not None:
        shade(fx - 4, fy - 1, 9, 2, 0.4)
        blit(sheet.crop((0, 0, 16, 16)), fx - 8, fy - 15)
    else:
        astronaut(fx - 3, fy - 14, rc, facing, arms_up=carry is not None)
    if carry:
        spr = part_sprite(carry, "mounted")
        blit(spr, fx - spr.width // 2, fy - 16 - spr.height)


PV = use(Canvas(MAP_IMG.convert("RGBA")))
cls_id = ARGS.ship_class
mounted_upgrades = ["antenna_high", "recorder_small"]               # already on the ship
carried = {} if ARGS.no_crew else {"engineer": "battery_large", "comms": "recorder_large",
                                   "scientist": "camera_hires"}
taken = set(mounted_upgrades) | set(carried.values()) | (set() if ARGS.no_crew else {"rtg"})
for s in SHELF_SLOTS:                                               # stock the shelves
    if s["part_id"] in taken:
        continue
    spr = part_sprite(s["part_id"], "mounted")
    b = s["bin"]
    blit(spr, b["x"] + (b["w"] - spr.width) // 2, b["y"] + (b["h"] - spr.height) // 2)
for st in STANDS:                                                   # active class: lamp on + dashed frame
    if st["class"] == cls_id:
        px(st["lamp"]["x"], st["lamp"]["y"], "green"); px(st["lamp"]["x"] - 1, st["lamp"]["y"], "greenD")
        pl = st["plinth"]
        for i in range(pl["x"] - 2, pl["x"] + pl["w"] + 2):
            if (i // 2) % 2 == 0:
                px(i, pl["y"] - 2, "green"); px(i, pl["y"] + pl["h"] + 1, "green")
        for j in range(pl["y"] - 2, pl["y"] + pl["h"] + 2):
            if (j // 2) % 2 == 0:
                px(pl["x"] - 2, j, "green"); px(pl["x"] + pl["w"] + 1, j, "green")
if not ARGS.no_crew:
    for lamp in LAYOUT["launch_door"]["ready_lights"][:2]:          # 2 of 4 players READY
        rect(lamp["x"] - 1, lamp["y"], 3, 1, "green")
        px(lamp["x"], lamp["y"] - 1, "greenD"); px(lamp["x"], lamp["y"] + 1, "greenD")
    bench0 = LAYOUT["benches"][0]                                   # a part parked on a workbench
    spr = part_sprite("rtg", "mounted")
    blit(spr, bench0["x"] + 6, bench0["y"] + (bench0["h"] - spr.height) // 2)
ship = ship_preview(PREVIEW_ORIGIN[0], PREVIEW_ORIGIN[1], cls_id, mounted_upgrades)
sock_role = "scientist" if not ARGS.no_crew else None               # carrier on the bay lights the open cells
for cell in ship["open"]:
    at = (ship["ox"] + cell["x"], ship["oy"] + cell["y"])
    blit(tint(CELL_GLOW, ROLE[sock_role][0] if sock_role else "white"), at[0] - 2, at[1] - 2)
    if sock_role:
        blit(load(UPG_DIR / FRAMES[sock_role]["slot"]), *at)
o_x, o_y, o_bw, o_bh = ship["ox"], ship["oy"], ship["bw"], ship["bh"]
for (mx, my, r) in ((o_x - 2, o_y + o_bh // 2, "engineer"), (o_x + o_bw + 1, o_y + o_bh // 2, "engineer"),
                    (o_x + o_bw - 1, o_y + o_bh - 1, "scientist")):  # wings + boom mount points
    blit(tint(MOUNT_GLOW, ROLE[r][0]), mx - 5, my - 5)

nav_slot = next(s for s in SHELF_SLOTS if s["part_id"] == "star_tracker")
if not ARGS.no_crew:
    b = nav_slot["bin"]
    frame(b["x"] - 1, b["y"] - 1, b["w"] + 2, b["h"] + 2, "white")   # focused slot
    people = [(126, 86, "engineer", 1), (306, 128, "comms", -1), (206, 136, "scientist", 1),
              (nav_slot["x"], nav_slot["bin"]["y"] - 13, "navigator", 1)]
    for (fx, fy, role, facing) in sorted(people, key=lambda p: p[1]):
        crew(fx, fy, role, facing, carried.get(role))
blit(OVL_IMG, 0, 0)

ev = evaluate(cls_id, mounted_upgrades)
if ev:                                                              # board bars at 1x
    def bar(fid, frac, c):
        f = BOARD_FIELDS[fid]["bar"]
        n = max(0, min(f["w"], round(frac * f["w"])))
        rect(f["x"], f["y"], n, f["h"], c)
        rect(f["x"], f["y"], n, 1, mix(col(c), (255, 255, 255), 0.35))
    bar("mass", ev["mass"] / ev["mass_limit"], "cyan" if ev["mass"] <= ev["mass_limit"] else "red")
    bar("power", min(1.0, ev["draw"] / max(1.0, ev["gen"])), "green" if ev["net"] >= 0 else "red")
    bar("budget", ev["cost"] / ev["budget"], "yellow" if ev["cost"] <= ev["budget"] else "red")
    bar("slots", ev["slots_used"] / ev["slots"], "purple")

CARD = None
if not ARGS.no_crew:                                                # F info card over the navigator
    cw, chh = 140, 64
    cx0 = max(FX0 + 2, min(FX1 - 2 - cw, nav_slot["x"] - cw // 2))
    cy0 = nav_slot["bin"]["y"] - 13 - 18 - chh - 4
    blit(nine_slice(INFO_CARD, cw, chh, CARD_MARGINS), cx0, cy0)
    tip_x = nav_slot["x"]
    for d in range(4):                                              # little pointer to the player
        rect(tip_x - 3 + d, cy0 + chh - 1 + d, 7 - 2 * d, 1, "metal" if d < 3 else "metalD")
    blit(part_sprite("star_tracker", "icon"), cx0 + 6, cy0 + 17)
    CARD = (cx0, cy0, cw, chh)

S = 4
big = PV.img.resize((W * S, H * S), Image.NEAREST)
dr = ImageDraw.Draw(big)
dr.fontmode = "1"                                                   # crisp, no anti-aliasing


def font(size):
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        return ImageFont.load_default(size)


def t4(x, y, s, c, size, anchor="la"):
    dr.text((round(x * S), round(y * S)), s, fill=col(c), font=font(size), anchor=anchor)


if ev:
    v = BOARD_FIELDS
    t4(v["class"]["x"], v["class"]["y"] + 0.5, ev["class"].upper(), "white", 26)
    for fid, s, c in (("mass", f"{ev['mass']:.0f}/{ev['mass_limit']:.0f}KG", "cyan"),
                      ("power", f"{ev['net']:+.0f} W", "green" if ev["net"] >= 0 else "red"),
                      ("budget", f"${ev['cost']:.0f}/{ev['budget']:.0f}M", "yellow"),
                      ("slots", f"{ev['slots_used']}/{ev['slots']}", "purple")):
        f = v[fid]["value"]
        t4(f["x"], f["y"] + 0.5, s, c, 24)
    f = v["rocket"]
    name = ev["launcher"]["name"].split()[0].upper() if ev["launcher"] else "NONE"
    t4(f["x"] + f["w"] / 2, f["y"] + 0.5, name, "white", 22, "ma")
if CARD:
    cx0, cy0, cw, chh = CARD
    pid = "star_tracker"
    t4(cx0 + 6, cy0 + 3.5, part_name(pid).upper(), "white", 30)
    t4(cx0 + cw - 6, cy0 + 4.5, "NAVIGATOR", "cyan", 22, "ra")
    st = (STATS or {}).get("parts", {}).get(pid, {})
    words, lines, cur = st.get("desc", "No data in design_stats.json").split(), [], ""
    for wd in words:
        if len(cur) + len(wd) + 1 > 30:
            lines.append(cur); cur = wd
        else:
            cur = (cur + " " + wd).strip()
    lines.append(cur)
    for k, ln in enumerate(lines[:4]):
        t4(cx0 + 44, cy0 + 17 + k * 6.5, ln, "frost", 21)
    stats_y = cy0 + chh - 13
    t4(cx0 + 6, stats_y, f"{st.get('mass_kg', '--')} KG", "cyan", 24)
    t4(cx0 + 50, stats_y, f"{st.get('power_w', 0):+d} W" if st else "-- W", "green" if st.get("power_w", 0) >= 0 else "red", 24)
    t4(cx0 + 96, stats_y, f"${st.get('cost', '--')}M", "yellow", 24)

# ================================================================================
#                                   EXPORT
# ================================================================================
for sub in ("maps", "preview", "ui", "sockets", "placeholders/icons", "placeholders/mounted"):
    (OUT / sub).mkdir(parents=True, exist_ok=True)


def save_scaled(img, path_1x, scales=(2, 4), names=None):
    img.save(path_1x)
    for k, s in enumerate(scales):
        target = names[k] if names else path_1x.with_name(path_1x.stem + f"@{s}x.png")
        img.resize((img.width * s, img.height * s), Image.NEAREST).save(target)


save_scaled(MAP_IMG, OUT / "maps/hangar_480x270.png",
            names=[OUT / "maps/hangar_960x540.png", OUT / "maps/hangar_1920x1080.png"])
save_scaled(OVL_IMG, OUT / "maps/hangar_overlay_480x270.png",
            names=[OUT / "maps/hangar_overlay_960x540.png", OUT / "maps/hangar_overlay_1920x1080.png"])
big.convert("RGB").save(OUT / "preview/hangar_preview_full_1920x1080.png")
save_scaled(INFO_CARD, OUT / "ui/info_card.png", scales=(4,))
save_scaled(CELL_GLOW, OUT / "sockets/cell_glow.png", scales=(4,))
save_scaled(MOUNT_GLOW, OUT / "sockets/mount_glow.png", scales=(4,))
for pid, ph in PLACEHOLDER.items():
    save_scaled(ph["icon"], OUT / f"placeholders/icons/{pid}.png", scales=(4,))
    save_scaled(ph["mounted"], OUT / f"placeholders/mounted/{pid}.png", scales=(4,))

LAYOUT["map"] = res(OUT / "maps/hangar_480x270.png")
LAYOUT["overlay"]["texture"] = res(OUT / "maps/hangar_overlay_480x270.png")
LAYOUT["shelf_slots"] = SHELF_SLOTS
LAYOUT["racks"] = RACK_RECTS
LAYOUT["carry"] = {"offset": {"x": 0, "y": -16},
                   "note": "draw the carried part's mounted sprite bottom-centred at feet + offset"}
LAYOUT["sockets"] = {
    "cell_glow": res(OUT / "sockets/cell_glow.png"), "cell_glow_offset": {"x": -2, "y": -2},
    "mount_glow": res(OUT / "sockets/mount_glow.png"), "mount_glow_offset": {"x": -5, "y": -5},
    "note": "white sprites: modulate with the role colour. Cells = preview_origin + body_origin + cell; "
            "mounts = preview_origin + parts_base.json class mounts.",
}
LAYOUT["info_card"] = {"texture": res(OUT / "ui/info_card.png"), "patch_margins": CARD_MARGINS}
LAYOUT["placeholders"] = {pid: {"icon": res(OUT / f"placeholders/icons/{pid}.png"),
                                "mounted": res(OUT / f"placeholders/mounted/{pid}.png")} for pid in PLACEHOLDER}
order_keys = ["base_size", "map", "overlay", "walkable", "obstacles", "shelf_slots", "racks", "assembly",
              "class_stands", "benches", "board", "launch_door", "entrance", "spawns", "carry", "sockets",
              "info_card", "placeholders"]
with open(OUT / "hangar_layout.json", "w", encoding="utf-8") as f:
    json.dump({k: LAYOUT[k] for k in order_keys}, f, indent=2)

print(f"ok: {len(SHELF_SLOTS)} shelf slots, {len(LAYOUT['obstacles'])} obstacles, "
      f"placeholders: {', '.join(PLACEHOLDER) or 'none'}, preview class: {cls_id}")
