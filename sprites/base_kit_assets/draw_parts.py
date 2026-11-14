"""Pixel-art base-kit parts for the spacecraft designer (top-down view).

Outputs (all 1x, plus @4x copies):
  icons/<id>.png        32x32 catalog icons with a role-coloured frame
  mounted/<id>.png      tight sprites as they look mounted on the ship
  bodies/<class>.png    empty class bodies (light / balanced / heavy) with upgrade slots
  previews/<class>_basekit.png   each class with the base kit fitted (160x128)
  base_kit_sheet.png    overview sheet
  parts_base.json       ids, roles, files, grid cells per class, mount anchors
Usage: python3 draw_parts.py <out_dir>
"""
import json
import math
import os
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
for d in ("icons", "mounted", "bodies", "previews"):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)

C = {
    "void": (9, 8, 22), "ink": (16, 14, 30),
    "metalD": (56, 60, 82), "metal": (96, 102, 128), "metalL": (148, 156, 180), "metalH": (200, 206, 222),
    "cyan": (72, 226, 236), "cyanD": (28, 110, 132),
    "orange": (255, 148, 50), "orangeD": (160, 72, 30), "yellow": (255, 214, 84),
    "green": (96, 230, 124), "greenD": (34, 116, 66),
    "purple": (186, 118, 244), "purpleD": (92, 58, 146),
    "panel": (36, 52, 120), "panelL": (70, 104, 196), "panelH": (130, 170, 236),
    "gold": (214, 168, 64), "goldD": (150, 104, 36), "goldL": (246, 214, 120),
    "silver": (176, 182, 200), "silverD": (120, 126, 148), "silverL": (222, 226, 238),
}
ROLE = {"engineer": ("orange", "orangeD"), "comms": ("green", "greenD"),
        "navigator": ("cyan", "cyanD"), "scientist": ("purple", "purpleD")}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.P = self.img.load()

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            col = C[c] if isinstance(c, str) else c
            self.P[x, y] = tuple(col) + (255,)

    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.px(i, j, c)

    def frame(self, x, y, w, h, c):
        for i in range(x, x + w):
            self.px(i, y, c); self.px(i, y + h - 1, c)
        for j in range(y, y + h):
            self.px(x, j, c); self.px(x + w - 1, j, c)

    def disc(self, cx, cy, r, c):
        for j in range(-r, r + 1):
            for i in range(-r, r + 1):
                if i * i + j * j <= r * r + r * 0.6:
                    self.px(cx + i, cy + j, c)

    def paste(self, other, x, y):
        self.img.alpha_composite(other.img, (x, y))

    def save(self, path, scale=4):
        self.img.save(path)
        root, ext = os.path.splitext(path)
        self.img.resize((self.w * scale, self.h * scale), Image.NEAREST).save(f"{root}@{scale}x{ext}")


def flipped(s):
    m = Canvas(s.w, s.h)
    m.img = s.img.transpose(Image.FLIP_LEFT_RIGHT)
    return m


# ---------------- part sprites (as mounted) ----------------

def spr_solar_small():
    """One wing: strut + 2x4 cell panel. Mirrored for the other side."""
    s = Canvas(30, 14)
    s.rect(0, 6, 4, 2, "metalL")                      # strut
    s.rect(4, 0, 26, 14, "metalD")
    for r in range(2):
        for k in range(4):
            x, y = 5 + k * 6, 1 + r * 6
            s.rect(x, y, 5, 5, "panel")
            s.px(x, y, "panelH"); s.px(x + 1, y, "panelL"); s.px(x, y + 1, "panelL")
            s.px(x + 3, y + 3, "panelL")
    return s


def spr_battery_small():
    s = Canvas(10, 8)
    s.rect(0, 1, 10, 7, "metalD"); s.rect(1, 1, 8, 6, "metal"); s.rect(1, 1, 8, 1, "metalH")
    s.rect(3, 0, 4, 1, "metalL")
    s.rect(2, 3, 4, 3, "green"); s.rect(6, 3, 1, 3, "greenD")
    return s


def spr_computer_std():
    s = Canvas(10, 8)
    s.rect(0, 0, 10, 8, "metalD"); s.rect(1, 1, 8, 6, "ink")
    for i in range(4):
        s.px(2 + i * 2, 2, "orange" if i == 0 else "green")
    s.rect(2, 4, 6, 1, "metal"); s.rect(2, 6, 6, 1, "metal")
    for i in range(0, 10, 2):                         # pins
        s.px(i, 7, "metalH")
    return s


def spr_antenna_low():
    s = Canvas(7, 12)
    s.rect(3, 4, 1, 8, "metalL")                      # mast
    s.disc(3, 3, 3, "metalD"); s.disc(3, 3, 2, "silverL"); s.px(3, 3, "green")
    s.rect(2, 10, 3, 2, "metal")
    return s


def spr_tank_small():
    s = Canvas(11, 11)
    s.disc(5, 5, 5, "metalD"); s.disc(5, 5, 4, "metalL"); s.disc(4, 4, 2, "metalH")
    for k in range(24):
        a = 2 * math.pi * k / 24
        s.px(round(5 + 5 * math.cos(a)), round(5 + 5 * math.sin(a)), "cyanD")
    s.px(5, 5, "cyan")
    return s


def spr_engine_main():
    s = Canvas(14, 10)
    s.rect(4, 0, 6, 3, "metalD")                      # mount
    for j in range(7):                                # bell widening outward
        half = 3 + j * 4 // 6
        s.rect(7 - half, 3 + j, half * 2, 1, "metal" if j < 6 else "metalD")
        s.px(7 - half, 3 + j, "metalL")
    s.rect(5, 8, 4, 2, "orangeD"); s.px(6, 9, "orange"); s.px(7, 9, "yellow")
    return s


def spr_thruster():
    s = Canvas(4, 4)
    s.rect(0, 0, 4, 4, "metalD"); s.rect(1, 1, 2, 2, "metalL"); s.px(1, 1, "metalH")
    return s


def spr_weather_sensor():
    s = Canvas(9, 9)
    s.rect(0, 2, 9, 7, "metalD"); s.rect(1, 3, 7, 5, "metal")
    s.rect(4, 0, 1, 3, "metalL")                      # mast
    s.px(2, 0, "purple"); s.px(6, 0, "purple"); s.rect(2, 1, 5, 1, "metalL")   # wind vane
    s.disc(4, 5, 1, "purpleD"); s.px(4, 5, "purple")
    return s


PARTS = [
    # id, name, role, sprite fn, mount type
    ("solar_small", "Small solar panels", "engineer", spr_solar_small, "wings"),
    ("battery_small", "Small battery", "engineer", spr_battery_small, "cell"),
    ("computer_std", "Standard computer", "engineer", spr_computer_std, "cell"),
    ("antenna_low", "Low-gain antenna", "comms", spr_antenna_low, "top"),
    ("tank_small", "Small propellant tank", "navigator", spr_tank_small, "cell"),
    ("engine_main", "Main engine", "navigator", spr_engine_main, "bottom"),
    ("thrusters_basic", "Basic thrusters", "navigator", spr_thruster, "corners"),
    ("weather_sensor", "Weather sensor", "scientist", spr_weather_sensor, "cell"),
]

# ---------------- icons ----------------


def icon(part_id, role, sprite_fn):
    ic = Canvas(32, 32)
    acc, accD = ROLE[role]
    ic.rect(0, 0, 32, 32, "ink")
    ic.frame(0, 0, 32, 32, accD); ic.frame(1, 1, 30, 30, "metalD")
    ic.rect(1, 1, 30, 2, acc)                          # role-coloured top bar
    for j in range(5, 30, 4):                          # faint backdrop grid
        for i in range(3, 30, 4):
            ic.px(i, j, (26, 26, 48))
    spr = sprite_fn()
    if part_id == "solar_small":                       # both wings, stacked
        pair = Canvas(30, 28)
        pair.paste(spr, 0, 0); pair.paste(flipped(spr), 0, 14)
        art = pair.img
    elif part_id == "thrusters_basic":                 # four nubs around a frame, 2x
        quad = Canvas(12, 12)
        quad.frame(1, 1, 10, 10, "metalD")
        for (x, y) in ((0, 0), (8, 0), (0, 8), (8, 8)):
            quad.paste(spr, x, y)
        art = quad.img.resize((24, 24), Image.NEAREST)
    else:                                              # small sprites scaled 2x to read in a catalog
        k = 2 if max(spr.w, spr.h) <= 14 else 1
        art = spr.img.resize((spr.w * k, spr.h * k), Image.NEAREST)
    bw, bh = art.size
    ic.img.alpha_composite(art, ((32 - bw) // 2, (32 - bh) // 2 + 1))
    return ic


# ---------------- class bodies ----------------
CLASSES = {
    # id: (cells per side, upgrade slots, foil colour, corner chamfer)
    "light": (3, 3, "silver", 2),
    "balanced": (4, 5, "gold", 4),
    "heavy": (5, 8, "gold", 6),
}
CELL = 12
BASE_CELLS = ["tank_small", "battery_small", "computer_std", "weather_sensor"]


def body(class_id):
    n, slots, foil, ch = CLASSES[class_id]
    size = n * CELL + 4
    b = Canvas(size, size)
    fD, f, fL = foil + "D", foil, foil + "L"

    def inside(i, j):
        return not (i + j < ch or (size - 1 - i) + j < ch or i + (size - 1 - j) < ch
                    or (size - 1 - i) + (size - 1 - j) < ch)

    for j in range(size):
        for i in range(size):
            if inside(i, j):
                v = ((i + j * 2) // 3 + (i // 5) * 2 + (j // 7)) % 6     # crinkled thermal foil
                b.px(i, j, fL if v == 0 and (i + j) % 2 == 0 else (fD if v == 3 and (i * j) % 3 == 0 else f))
    for j in range(size):                                         # dark rim on the outline
        for i in range(size):
            if inside(i, j) and not (inside(i - 1, j) and inside(i + 1, j) and inside(i, j - 1) and inside(i, j + 1)):
                b.px(i, j, fD)
    if class_id == "heavy":                                       # reinforcement ribs
        for t in (2 + CELL * 2, 2 + CELL * 3):
            for k in range(3, size - 3):
                if k % 2 == 0:
                    b.px(t, k, "goldD"); b.px(k, t, "goldD")
    centre = (n - 1) / 2
    cells = sorted(((cx, cy) for cy in range(n) for cx in range(n)),
                   key=lambda c: (abs(c[0] - centre) + abs(c[1] - centre), c[1], c[0]))
    layout = []
    for idx, (cx, cy) in enumerate(cells):
        x, y = 2 + cx * CELL, 2 + cy * CELL
        if idx < len(BASE_CELLS):
            b.rect(x + 1, y + 1, CELL - 2, CELL - 2, "metalD")    # mounting plate
            layout.append({"x": x, "y": y, "w": CELL, "h": CELL, "use": BASE_CELLS[idx]})
        elif idx < len(BASE_CELLS) + slots:
            b.rect(x + 1, y + 1, CELL - 2, CELL - 2, "ink")       # empty upgrade slot
            for k in range(1, CELL - 1):
                if k % 2:
                    b.px(x + k, y + 1, "metalL"); b.px(x + k, y + CELL - 2, "metalL")
                    b.px(x + 1, y + k, "metalL"); b.px(x + CELL - 2, y + k, "metalL")
            b.rect(x + 5, y + 4, 2, 4, "metal"); b.rect(x + 4, y + 5, 4, 2, "metal")   # "+" mark
            layout.append({"x": x, "y": y, "w": CELL, "h": CELL, "use": "upgrade_slot"})
    return b, layout


# ---------------- assemble previews ----------------
PREVIEW_W, PREVIEW_H = 160, 128


def assemble(class_id, sprites):
    b, layout = body(class_id)
    pv = Canvas(PREVIEW_W, PREVIEW_H)
    ox, oy = (PREVIEW_W - b.w) // 2, (PREVIEW_H - b.h) // 2 - 2
    anchors = {}
    wing = sprites["solar_small"]
    wy = oy + b.h // 2 - wing.h // 2
    pv.paste(flipped(wing), ox - wing.w, wy)
    pv.paste(wing, ox + b.w, wy)
    anchors["solar_small"] = [{"x": ox - wing.w, "y": wy, "flip": True}, {"x": ox + b.w, "y": wy, "flip": False}]
    pv.paste(b, ox, oy)
    a = sprites["antenna_low"]
    ax, ay = ox + b.w // 2 - a.w // 2, oy - a.h + 2
    pv.paste(a, ax, ay); anchors["antenna_low"] = [{"x": ax, "y": ay}]
    e = sprites["engine_main"]
    ex, ey = ox + b.w // 2 - e.w // 2, oy + b.h - 1
    pv.paste(e, ex, ey); anchors["engine_main"] = [{"x": ex, "y": ey}]
    t = sprites["thrusters_basic"]
    tl = []
    for (x, y) in ((ox - 1, oy - 1), (ox + b.w - 3, oy - 1), (ox - 1, oy + b.h - 3), (ox + b.w - 3, oy + b.h - 3)):
        pv.paste(t, x, y); tl.append({"x": x, "y": y})
    anchors["thrusters_basic"] = tl
    for cell in layout:
        if cell["use"] in sprites:
            s = sprites[cell["use"]]
            x = ox + cell["x"] + (CELL - s.w) // 2
            y = oy + cell["y"] + (CELL - s.h) // 2
            pv.paste(s, x, y)
            anchors[cell["use"]] = [{"x": x, "y": y}]
    return pv, b, layout, {"body_origin": {"x": ox, "y": oy}, "mounts": anchors}


# ---------------- run ----------------
sprites = {}
meta = {"view": "top-down", "units": "1x pixels", "parts": [], "classes": []}
for pid, name, role, fn, mount in PARTS:
    s = fn()
    sprites[pid] = s
    s.save(os.path.join(OUT, "mounted", f"{pid}.png"))
    icon(pid, role, fn).save(os.path.join(OUT, "icons", f"{pid}.png"))
    meta["parts"].append({"id": pid, "name": name, "role": role, "mount": mount, "base_kit": True,
                          "icon": f"icons/{pid}.png", "mounted": f"mounted/{pid}.png",
                          "mounted_size": [s.w, s.h],
                          "stats": {"mass_kg": None, "power_w": None, "cost": None}})

previews = {}
for cid, (n, slots, foil, ch) in CLASSES.items():
    pv, b, layout, mounts = assemble(cid, sprites)
    b.save(os.path.join(OUT, "bodies", f"{cid}.png"))
    pv.save(os.path.join(OUT, "previews", f"{cid}_basekit.png"))
    previews[cid] = pv
    meta["classes"].append({"id": cid, "upgrade_slots": slots, "body": f"bodies/{cid}.png",
                            "body_size": [b.w, b.h], "cell_size": CELL, "cells": layout,
                            "preview": f"previews/{cid}_basekit.png", "preview_size": [PREVIEW_W, PREVIEW_H],
                            **mounts})

sheet = Canvas(3 * PREVIEW_W + 32, 52 + PREVIEW_H + 8)
sheet.rect(0, 0, sheet.w, sheet.h, "void")
for k, (pid, name, role, fn, mount) in enumerate(PARTS):
    step = (sheet.w - 16 - 32) // (len(PARTS) - 1)
    sheet.paste(icon(pid, role, fn), 8 + k * step, 8)
gap = (sheet.w - 3 * PREVIEW_W) // 4
for k, cid in enumerate(CLASSES):
    x = gap + k * (PREVIEW_W + gap)
    sheet.rect(x, 52, PREVIEW_W, PREVIEW_H, (18, 16, 36))
    sheet.paste(previews[cid], x, 52)
sheet.save(os.path.join(OUT, "base_kit_sheet.png"))

with open(os.path.join(OUT, "parts_base.json"), "w") as f:
    json.dump(meta, f, indent=2)
print("ok")
