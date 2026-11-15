"""Pixel-art upgrade parts (optional, bought in the designer), top-down view.

Every upgrade uses one upgrade slot. Cell parts sit in the slot; external parts
(large solar array, high-gain dish, magnetometer boom) mount outside the body and
their slot shows a "linked" plate. Replacements: solar_large -> solar_small,
antenna_high -> antenna_low.

Outputs (1x + @4x):
  icons/<id>.png, mounted/<id>.png, frames/slot_<role>.png, frames/linked_<role>.png,
  loadouts/<class>_example.png, upgrades_sheet.png, parts_upgrades.json
Usage: python3 draw_upgrades.py <out_dir>
"""
import json
import math
import os
import sys

from PIL import Image

import draw_parts as base
from draw_parts import Canvas, ROLE, CELL, PREVIEW_W, PREVIEW_H, body, flipped

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
base.C.update({"heat1": (120, 40, 160), "heat2": (220, 60, 80), "heat3": (255, 150, 50),
               "heat4": (255, 230, 120), "red": (232, 62, 72), "redD": (120, 30, 40),
               "white": (238, 240, 250)})


def line(s, x0, y0, x1, y1, c):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        s.px(x0, y0, c)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x0 += sx
        if e2 <= dx:
            err += dx; y0 += sy


# ---------------- sprites ----------------

def spr_solar_large():
    s = Canvas(44, 18)
    s.rect(0, 8, 4, 2, "metalL")
    s.rect(4, 0, 40, 18, "metalD")
    for r in range(3):
        for k in range(6):
            x, y = 5 + k * 6 + (1 if k >= 3 else 0), 1 + r * 6
            s.rect(x, y, 5, 5, "panel")
            s.px(x, y, "panelH"); s.px(x + 1, y, "panelL"); s.px(x, y + 1, "panelL"); s.px(x + 3, y + 3, "panelL")
    s.rect(23, 1, 1, 16, "goldD")                     # hinge between the two folds
    return s


def spr_antenna_high():
    s = Canvas(17, 20)
    s.rect(7, 14, 3, 6, "metalL"); s.rect(8, 14, 1, 6, "metalH")      # mast
    s.disc(8, 8, 8, "silverD"); s.disc(8, 8, 7, "silverL"); s.disc(8, 8, 5, "silver"); s.disc(8, 8, 2, "silverD")
    for (x, y) in ((3, 4), (13, 4), (8, 15)):                          # feed tripod
        line(s, 8, 8, x, y, "metal")
    s.px(8, 8, "green"); s.px(7, 7, "white")
    return s


def spr_battery_large():
    s = Canvas(10, 10)
    for k in range(2):
        x = k * 5
        s.rect(x, 1, 5, 9, "metalD"); s.rect(x + 1, 2, 3, 7, "metal"); s.rect(x + 1, 0, 3, 1, "metalL")
        s.rect(x + 1, 4, 3, 5, "green"); s.rect(x + 1, 4, 3, 1, "metalH")
    return s


def spr_rtg():
    s = Canvas(10, 10)
    for k in range(8):
        a = k * math.pi / 4
        line(s, round(4.5 + 2 * math.cos(a)), round(4.5 + 2 * math.sin(a)),
             round(4.5 + 4.6 * math.cos(a)), round(4.5 + 4.6 * math.sin(a)), "metalL")
    s.disc(5, 5, 2, "metalD"); s.px(5, 5, "orange"); s.px(4, 5, "orangeD"); s.px(5, 4, "yellow")
    return s


def spr_radiator():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.rect(1, 1, 8, 7, "silverL")
    for i in range(2, 9, 2):
        s.rect(i, 1, 1, 7, "silverD")
    s.rect(1, 8, 8, 1, "orange"); s.px(1, 8, "yellow")
    return s


def spr_computer_radhard():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.rect(2, 2, 6, 6, "ink")
    for (x, y) in ((0, 0), (8, 0), (0, 8), (8, 8)):                    # shielding corners
        s.rect(x, y, 2, 2, "yellow")
    s.px(3, 3, "green"); s.px(5, 3, "green"); s.px(3, 5, "cyan"); s.rect(5, 5, 2, 2, "orange")
    return s


def spr_rad_shielding():
    """Shielded avionics vault: thick tantalum-grey walls + shield-capacitor bank (cyan cells)."""
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.frame(0, 0, 10, 10, "silverD"); s.frame(1, 1, 8, 8, "metal")
    s.rect(2, 2, 6, 6, "ink")
    for i in range(3):
        s.rect(3 + i * 2, 3, 1, 3, "cyan" if i < 2 else "cyanD")
    s.rect(3, 7, 4, 1, "yellow"); s.px(7, 7, "orange")
    return s


def spr_particle_monitor():
    """Energetic particle detector: a stack of sensor discs looking sunward + a telescope tube."""
    s = Canvas(9, 9)
    s.rect(0, 0, 9, 9, "metalD"); s.rect(1, 1, 7, 7, "ink")
    s.disc(4, 4, 2, "metal"); s.disc(4, 4, 1, "purpleD"); s.px(4, 4, "yellow")
    s.rect(6, 1, 2, 3, "metalL"); s.px(7, 1, "purple")
    s.px(1, 7, "purple"); s.px(2, 7, "purpleD")
    return s


def spr_whipple_shield():
    """Whipple shield: thin bumper sheets stacked with gaps in front of the hull wall."""
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD")
    for i, c in enumerate(["silverL", "silver", "silverD"]):
        s.rect(1 + i * 3, 1, 2, 8, c)
    s.px(1, 3, "cyan"); s.px(4, 6, "cyanD"); s.px(2, 7, "white")
    return s


def spr_recorder_small():
    s = Canvas(8, 8)
    s.rect(0, 0, 8, 8, "metalD"); s.rect(1, 1, 6, 6, "ink")
    for i, c in enumerate(["green", "green", "greenD"]):
        s.rect(2 + i * 2, 2, 1, 4, c)
    return s


def spr_recorder_large():
    s = Canvas(10, 10)
    for k in range(2):
        y = k * 5
        s.rect(0, y, 10, 4, "metalD"); s.rect(1, y + 1, 8, 2, "ink")
        for i in range(4):
            s.px(2 + i * 2, y + 1, "green" if i < 3 - k else "yellow")
        s.rect(1, y + 4, 8, 1, "metal")
    return s


def spr_relay_radio():
    s = Canvas(10, 10)
    s.rect(0, 5, 10, 5, "metalD"); s.rect(1, 6, 8, 3, "metal"); s.px(2, 7, "green")
    for k in range(5):                                                 # helix antenna
        s.px(6 + (k % 2), 4 - k, "greenD" if k % 2 else "green")
    s.px(6, 0, "white")
    return s


def spr_tank_large():
    s = Canvas(12, 8)
    s.disc(3, 4, 3, "metalD"); s.disc(8, 4, 3, "metalD")
    s.rect(3, 1, 6, 7, "metalD")
    s.disc(3, 4, 2, "metalL"); s.disc(8, 4, 2, "metalL"); s.rect(3, 2, 6, 5, "metalL")
    s.rect(2, 2, 3, 1, "metalH")
    s.rect(5, 1, 2, 7, "cyanD"); s.px(5, 4, "cyan")
    return s


def spr_star_tracker():
    s = Canvas(9, 9)
    s.rect(0, 0, 9, 9, "metalD")
    s.disc(4, 4, 3, "metalL"); s.disc(4, 4, 2, "ink"); s.px(4, 4, "cyan"); s.px(3, 3, "white")
    return s


def spr_reaction_wheels():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.rect(1, 1, 8, 8, "ink")
    for (x, y) in ((3, 3), (7, 3), (5, 7)):
        s.disc(x, y, 1, "metal"); s.px(x, y, "metalH")
        for (dx, dy) in ((-2, 0), (2, 0), (0, -2), (0, 2)):
            s.px(x + dx, y + dy, "cyanD")
    return s


def spr_camera_hires():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.rect(1, 1, 8, 8, "metal")
    s.disc(5, 5, 3, "metalL"); s.disc(5, 5, 2, "ink"); s.px(5, 5, "purpleD"); s.px(4, 4, "white"); s.px(6, 6, "purple")
    return s


def spr_spectrometer():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD"); s.rect(1, 1, 8, 8, "metal")
    s.rect(1, 3, 8, 4, "ink")
    for i, c in enumerate(["purple", "panelL", "cyan", "green", "yellow", "orange", "red", "redD"]):
        s.rect(1 + i, 4, 1, 2, c)
    s.px(5, 1, "purple")
    return s


def spr_radar_sounder():
    s = Canvas(10, 10)
    s.rect(2, 3, 6, 4, "metalD"); s.rect(3, 4, 4, 2, "metal"); s.px(4, 4, "purple")
    s.rect(0, 1, 10, 1, "metalL"); s.rect(0, 8, 10, 1, "metalL")       # folded dipole antenna
    for x in (0, 9):
        s.rect(x, 1, 1, 8, "metalL"); s.px(x, 1, "purple"); s.px(x, 8, "purple")
    return s


def spr_thermal_imager():
    s = Canvas(10, 10)
    s.rect(0, 0, 10, 10, "metalD")
    for j in range(6):
        for i in range(6):
            d = max(abs(i - 2.5), abs(j - 2.5))
            s.px(2 + i, 2 + j, "heat4" if d < 1 else ("heat3" if d < 2 else ("heat2" if d < 2.6 else "heat1")))
    return s


def spr_magnetometer():
    s = Canvas(18, 18)
    line(s, 0, 0, 13, 13, "metalL"); line(s, 1, 0, 14, 13, "metalD")
    for k in (4, 8):
        s.rect(k, k, 2, 2, "metal")
    s.rect(13, 13, 5, 5, "purpleD"); s.rect(14, 14, 3, 3, "purple"); s.px(14, 14, "white")
    return s


UPGRADES = [
    # id, name, role, sprite fn, mount, replaces
    ("solar_large", "Large solar array", "engineer", spr_solar_large, "wings", "solar_small"),
    ("rtg", "RTG (nuclear power)", "engineer", spr_rtg, "cell", None),
    ("battery_large", "Large battery", "engineer", spr_battery_large, "cell", None),
    ("radiator", "Radiator / heater", "engineer", spr_radiator, "cell", None),
    ("computer_radhard", "Radiation-hardened computer", "engineer", spr_computer_radhard, "cell", None),
    ("rad_shielding", "Radiation shielding", "engineer", spr_rad_shielding, "cell", None),
    ("antenna_high", "High-gain dish", "comms", spr_antenna_high, "top", "antenna_low"),
    ("recorder_small", "Small data recorder", "comms", spr_recorder_small, "cell", None),
    ("recorder_large", "Large data recorder", "comms", spr_recorder_large, "cell", None),
    ("relay_radio", "Relay radio", "comms", spr_relay_radio, "cell", None),
    ("tank_large", "Large propellant tank", "navigator", spr_tank_large, "cell", None),
    ("star_tracker", "Star tracker", "navigator", spr_star_tracker, "cell", None),
    ("reaction_wheels", "Reaction wheels", "navigator", spr_reaction_wheels, "cell", None),
    ("whipple_shield", "Whipple shield", "navigator", spr_whipple_shield, "cell", None),
    ("camera_hires", "High-res camera", "scientist", spr_camera_hires, "cell", None),
    ("spectrometer", "Spectrometer", "scientist", spr_spectrometer, "cell", None),
    ("radar_sounder", "Radar sounder", "scientist", spr_radar_sounder, "cell", None),
    ("thermal_imager", "Thermal imager", "scientist", spr_thermal_imager, "cell", None),
    ("magnetometer", "Magnetometer", "scientist", spr_magnetometer, "boom", None),
    ("particle_monitor", "Solar particle monitor", "scientist", spr_particle_monitor, "cell", None),
]
BY_ID = {u[0]: u for u in UPGRADES}


# ---------------- icons, frames ----------------

def make_icon(pid, role, fn):
    ic = Canvas(32, 32)
    acc, accD = ROLE[role]
    ic.rect(0, 0, 32, 32, "ink")
    ic.frame(0, 0, 32, 32, accD); ic.frame(1, 1, 30, 30, "metalD")
    ic.rect(1, 1, 30, 2, acc)
    for j in range(5, 30, 4):
        for i in range(3, 30, 4):
            ic.px(i, j, (26, 26, 48))
    spr = fn()
    if pid == "solar_large":
        art = spr.img.crop((4, 0, 32, 18))                 # a section of the big array
    else:
        k = 2 if max(spr.w, spr.h) <= 13 else 1
        art = spr.img.resize((spr.w * k, spr.h * k), Image.NEAREST)
    bw, bh = art.size
    ic.img.alpha_composite(art, ((32 - bw) // 2, (32 - bh) // 2 + 1))
    for (x, y) in ((28, 26), (27, 27), (28, 27), (29, 27), (28, 28)):   # "+" marks an upgrade
        ic.px(x, y, acc)
    return ic


def slot_frame(role):
    f = Canvas(CELL, CELL)
    acc, accD = ROLE[role]
    f.frame(0, 0, CELL, CELL, accD)
    for (x, y) in ((0, 0), (CELL - 1, 0), (0, CELL - 1), (CELL - 1, CELL - 1)):
        f.px(x, y, acc)
    return f


def linked_plate(role):
    """Slot used by an external part: plate + role frame + connector pins."""
    p = Canvas(CELL, CELL)
    acc, _ = ROLE[role]
    p.rect(1, 1, CELL - 2, CELL - 2, "metalD")
    for (x, y) in ((3, 3), (8, 3), (3, 8), (8, 8)):
        p.px(x, y, acc)
    p.rect(5, 5, 2, 2, "metalL")
    p.paste(slot_frame(role), 0, 0)
    return p


# ---------------- loadout assembly ----------------

def assemble_loadout(class_id, upgrade_ids, base_sprites, up_sprites):
    b, layout = body(class_id)
    slots = [c for c in layout if c["use"] == "upgrade_slot"]
    assert len(upgrade_ids) <= len(slots), f"{class_id}: too many upgrades"
    pv = Canvas(PREVIEW_W, PREVIEW_H)
    ox, oy = (PREVIEW_W - b.w) // 2, (PREVIEW_H - b.h) // 2 - 2
    wing = up_sprites["solar_large"] if "solar_large" in upgrade_ids else base_sprites["solar_small"]
    wy = oy + b.h // 2 - wing.h // 2
    pv.paste(flipped(wing), ox - wing.w, wy); pv.paste(wing, ox + b.w, wy)
    if "magnetometer" in upgrade_ids:
        pv.paste(up_sprites["magnetometer"], ox + b.w - 3, oy + b.h - 3)
    pv.paste(b, ox, oy)
    top = up_sprites["antenna_high"] if "antenna_high" in upgrade_ids else base_sprites["antenna_low"]
    pv.paste(top, ox + b.w // 2 - top.w // 2, oy - top.h + 2)
    e = base_sprites["engine_main"]
    pv.paste(e, ox + b.w // 2 - e.w // 2, oy + b.h - 1)
    t = base_sprites["thrusters_basic"]
    for (x, y) in ((ox - 1, oy - 1), (ox + b.w - 3, oy - 1), (ox - 1, oy + b.h - 3), (ox + b.w - 3, oy + b.h - 3)):
        pv.paste(t, x, y)
    for cell in layout:
        if cell["use"] in base_sprites:
            s = base_sprites[cell["use"]]
            pv.paste(s, ox + cell["x"] + (CELL - s.w) // 2, oy + cell["y"] + (CELL - s.h) // 2)
    placed = []
    for uid, cell in zip(upgrade_ids, slots):
        _, _, role, _, mount, _ = BY_ID[uid]
        cx, cy = ox + cell["x"], oy + cell["y"]
        if mount == "cell":
            pv.rect(cx + 1, cy + 1, CELL - 2, CELL - 2, "metalD")
            s = up_sprites[uid]
            pv.paste(s, cx + (CELL - s.w) // 2, cy + (CELL - s.h) // 2)
            pv.paste(slot_frame(role), cx, cy)
        else:
            pv.paste(linked_plate(role), cx, cy)
        placed.append({"upgrade": uid, "slot": {"x": cell["x"], "y": cell["y"]}})
    return pv, placed


EXAMPLES = {
    "light": ["solar_large", "camera_hires", "recorder_small"],
    "balanced": ["antenna_high", "battery_large", "spectrometer", "star_tracker", "recorder_large"],
    "heavy": ["solar_large", "antenna_high", "rtg", "radar_sounder", "thermal_imager",
              "magnetometer", "tank_large", "computer_radhard"],
}


def main():
    for d in ("icons", "mounted", "frames", "loadouts"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    base_sprites = {pid: fn() for pid, _, _, fn, _ in base.PARTS}
    up_sprites, icons = {}, {}
    meta = {"view": "top-down", "units": "1x pixels",
            "rules": {"slot_cost": "every upgrade uses 1 upgrade slot",
                      "external_mounts": "wings/top/boom parts mount outside the body; their slot shows frames/linked_<role>.png"},
            "parts": [], "frames": {}, "example_loadouts": []}
    for pid, name, role, fn, mount, replaces in UPGRADES:
        s = fn()
        up_sprites[pid] = s
        s.save(os.path.join(OUT, "mounted", f"{pid}.png"))
        icons[pid] = make_icon(pid, role, fn)
        icons[pid].save(os.path.join(OUT, "icons", f"{pid}.png"))
        meta["parts"].append({"id": pid, "name": name, "role": role, "mount": mount, "replaces": replaces,
                              "slot_cost": 1, "base_kit": False,
                              "icon": f"icons/{pid}.png", "mounted": f"mounted/{pid}.png", "mounted_size": [s.w, s.h],
                              "stats": {"mass_kg": None, "power_w": None, "cost": None}})
    for role in ROLE:
        slot_frame(role).save(os.path.join(OUT, "frames", f"slot_{role}.png"))
        linked_plate(role).save(os.path.join(OUT, "frames", f"linked_{role}.png"))
        meta["frames"][role] = {"slot": f"frames/slot_{role}.png", "linked": f"frames/linked_{role}.png"}
    loadouts = {}
    for cid, ups in EXAMPLES.items():
        pv, placed = assemble_loadout(cid, ups, base_sprites, up_sprites)
        pv.save(os.path.join(OUT, "loadouts", f"{cid}_example.png"))
        loadouts[cid] = pv
        meta["example_loadouts"].append({"class": cid, "upgrades": ups, "placements": placed,
                                         "file": f"loadouts/{cid}_example.png"})
    per_row = 9
    sheet_w = 3 * PREVIEW_W + 32
    rows = math.ceil(len(UPGRADES) / per_row)
    sheet = Canvas(sheet_w, 8 + rows * 40 + PREVIEW_H + 8)
    sheet.rect(0, 0, sheet.w, sheet.h, "void")
    step = (sheet_w - 16 - 32) // (per_row - 1)
    for k, (pid, *_rest) in enumerate(UPGRADES):
        sheet.paste(icons[pid], 8 + (k % per_row) * step, 8 + (k // per_row) * 40)
    gap = (sheet_w - 3 * PREVIEW_W) // 4
    y0 = 8 + rows * 40
    for k, cid in enumerate(EXAMPLES):
        x = gap + k * (PREVIEW_W + gap)
        sheet.rect(x, y0, PREVIEW_W, PREVIEW_H, (18, 16, 36))
        sheet.paste(loadouts[cid], x, y0)
    sheet.save(os.path.join(OUT, "upgrades_sheet.png"))
    with open(os.path.join(OUT, "parts_upgrades.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("ok", len(UPGRADES), "upgrades")


if __name__ == "__main__":
    main()
