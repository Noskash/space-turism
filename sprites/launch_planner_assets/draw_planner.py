"""Launch window planner console: a pixel-art interactable for the design hub (top-down 3/4 view).

Same palette and look as the ship map (sprites/lab_assets/source/draw_ship.py). The screen shows the
real geometry of a minimum-energy (Hohmann) Earth -> Mars transfer:
  - Sun in the middle, Earth's orbit (blue) and Mars' orbit (red), squashed by the 3/4 view
  - Earth at departure on the left; Mars ~44 deg AHEAD of Earth (where it must be on launch day)
  - the dotted transfer arc over the top (half an ellipse, ~259 days), the spacecraft moving along it
  - a blinking hollow "ghost Mars" where Mars will be on arrival, opposite Earth
On the desk: date dial, date slider, STANDARD / FAST buttons; "LAUNCH" on the front face.

Outputs (out_dir, default = this folder):
  planner_sheet.png (+ @4x)  48x48 frames; row 0 idle (6 frames), row 1 highlight (player in range),
                             row 2 offline (1 frame, dead screen)
  planner.json               frame size, anchor, interact point, obstacle, screen rect, animations
  preview/planner_in_hub.png (+ @4x)  demo: placed in the Mission Hub of the current ship map
  preview/planner_closeup.png         6x close-up of that corner
  preview/planner_anim.gif            6x animation of the idle + highlight rows
Usage: python draw_planner.py [out_dir]    (needs Pillow)
"""
import json
import math
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
FW, FH = 48, 48          # frame size
FRAMES = 6
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

C = {   # subset of the ship palette (draw_ship.py)
    "hullD": (30, 32, 52), "hull": (52, 56, 82), "hullL": (84, 90, 122), "hullH": (128, 136, 168),
    "faceD": (44, 48, 76), "face": (62, 68, 104), "faceL": (88, 96, 138),
    "metalD": (56, 60, 82), "metal": (96, 102, 128), "metalL": (148, 156, 180), "metalH": (200, 206, 222),
    "scr": (8, 16, 24), "scrL": (16, 30, 40),
    "cyan": (72, 226, 236), "cyanD": (28, 110, 132),
    "orange": (255, 148, 50), "orangeD": (160, 72, 30), "yellow": (255, 214, 84), "yellowD": (150, 112, 30),
    "red": (232, 62, 72), "redD": (120, 30, 40),
    "green": (96, 230, 124), "greenD": (34, 116, 66),
    "mars": (212, 98, 60), "marsD": (146, 56, 38), "marsL": (240, 152, 102),
    "earth": (64, 126, 222), "earthD": (32, 66, 146),
    "white": (238, 240, 250),
}
FONT = {
    "A": ["010", "101", "111", "101", "101"], "C": ["011", "100", "100", "100", "011"],
    "H": ["101", "101", "111", "101", "101"], "L": ["100", "100", "100", "100", "111"],
    "N": ["110", "101", "101", "101", "101"], "U": ["101", "101", "101", "101", "111"],
}


class Canvas:
    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.P = self.img.load()
        self.w, self.h = w, h

    def px(self, x, y, c, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            rgb = C[c] if isinstance(c, str) else c
            self.P[x, y] = (*rgb, a)

    def rect(self, x, y, w, h, c, a=255):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.px(i, j, c, a)

    def disc(self, cx, cy, r, c):
        for j in range(-r, r + 1):
            for i in range(-r, r + 1):
                if i * i + j * j <= r * r + r * 0.6:
                    self.px(cx + i, cy + j, c)

    def ring(self, cx, cy, rx, ry, c, skip=None):
        n = int(2 * math.pi * max(rx, ry) * 1.6)
        for k in range(n):
            if skip and skip(k):
                continue
            a = 2 * math.pi * k / n
            self.px(round(cx + rx * math.cos(a)), round(cy + ry * math.sin(a)), c)

    def text(self, x, y, s, c):
        for ch in s:
            for j, row in enumerate(FONT[ch]):
                for i, b in enumerate(row):
                    if b == "1":
                        self.px(x + i, y + j, c)
            x += 4


# ---- geometry (frame coordinates) ----
DESK_X, DESK_Y, DESK_W, DESK_H = 3, 29, 42, 8      # desk top surface
FACE_H = 6                                           # desk front face (3/4 view)
SCR_X, SCR_Y, SCR_W, SCR_H = 7, 5, 34, 20           # screen glass (inside the housing)
SUN = (SCR_X + 17, SCR_Y + 10)                       # sun on screen
R_EARTH = (6, 3.6)                                   # orbit radii on screen (x, y) - squashed by the 3/4 view
R_MARS = (12, 7.2)                                   # Mars at 1.52 AU -> ~2x Earth's ring here (readability)
LEAD_DEG = 44                                        # Mars leads Earth by ~44 deg at a Hohmann launch


def orbit_pt(r, deg):
    """Point on an orbit ring; deg measured counter-clockwise on screen from +x (y up)."""
    a = math.radians(deg)
    return (SUN[0] + r[0] * math.cos(a), SUN[1] - r[1] * math.sin(a))


def transfer_pt(t):
    """Transfer half-ellipse from Earth (180 deg, t=0) over the top to the far side of Mars' orbit (0 deg, t=1)."""
    a = math.pi * (1 - t)                            # 180 -> 0 deg, through 90 (top)
    cx = SUN[0] + (R_MARS[0] - R_EARTH[0]) / 2
    rx = (R_MARS[0] + R_EARTH[0]) / 2
    ry = R_EARTH[1] + (R_MARS[1] - R_EARTH[1]) * (0.2 + 0.25 * math.sin(a))   # bulges out like a real ellipse,
    # kept well inside Mars' ring so the dashes don't merge with it
    return (cx + rx * math.cos(a), SUN[1] - ry * math.sin(a))


def draw_body(cv, ox, oy):
    """Housing, desk, controls (everything except the screen contents)."""
    # floor shadow (dithered, semi-transparent)
    for j in range(DESK_Y + DESK_H + FACE_H, DESK_Y + DESK_H + FACE_H + 4):
        for i in range(DESK_X + 1, DESK_X + DESK_W + 2):
            if BAYER[j % 4][i % 4] < 10:
                cv.px(ox + i, oy + j, (0, 0, 0), 80)
    # screen housing (stands at the back of the desk)
    hx, hy, hw, hh = SCR_X - 3, SCR_Y - 3, SCR_W + 6, SCR_H + 6
    cv.rect(ox + hx, oy + hy, hw, hh, "faceD")
    cv.rect(ox + hx, oy + hy, hw, 1, "faceL")                     # top highlight
    cv.rect(ox + hx, oy + hy, 1, hh, "face")
    cv.rect(ox + hx + hw - 1, oy + hy, 1, hh, "hullD")
    cv.rect(ox + hx + 1, oy + hy + hh - 1, hw - 2, 1, "hullD")
    cv.rect(ox + SCR_X - 1, oy + SCR_Y - 1, SCR_W + 2, SCR_H + 2, "cyanD")   # navigator-cyan bezel
    for i in range(3):                                            # vents on the housing top
        cv.rect(ox + hx + 4 + i * 3, oy + hy + 1, 2, 1, "hull")
    # neck between screen and desk
    cv.rect(ox + 20, oy + hy + hh, 8, DESK_Y - (hy + hh), "metalD")
    cv.rect(ox + 20, oy + hy + hh, 1, DESK_Y - (hy + hh), "metal")
    # desk top
    cv.rect(ox + DESK_X, oy + DESK_Y, DESK_W, DESK_H, "metalL")
    cv.rect(ox + DESK_X, oy + DESK_Y, DESK_W, 1, "metalH")
    cv.rect(ox + DESK_X, oy + DESK_Y, 1, DESK_H, "metalH")
    cv.rect(ox + DESK_X + DESK_W - 1, oy + DESK_Y, 1, DESK_H, "metal")
    # desk front face with the label
    fy = DESK_Y + DESK_H
    cv.rect(ox + DESK_X, oy + fy, DESK_W, FACE_H, "face")
    cv.rect(ox + DESK_X, oy + fy + FACE_H - 1, DESK_W, 1, "metalD")
    cv.rect(ox + DESK_X + 2, oy + fy, DESK_W - 4, 1, "cyanD")
    cv.text(ox + DESK_X + (DESK_W - 23) // 2, oy + fy + 1, "LAUNCH", "cyan")
    # controls on the desk: date dial (left), date slider (middle), STANDARD / FAST buttons (right)
    cv.disc(ox + 9, oy + DESK_Y + 4, 3, "metalD")
    cv.disc(ox + 9, oy + DESK_Y + 3, 3, "metal")
    cv.disc(ox + 9, oy + DESK_Y + 3, 1, "metalH")
    cv.px(ox + 9, oy + DESK_Y + 1, "cyan")                        # dial pointer
    cv.rect(ox + 15, oy + DESK_Y + 3, 15, 2, "hullD")             # slider track
    for i in range(0, 15, 3):
        cv.px(ox + 15 + i, oy + DESK_Y + 6, "metal")              # day ticks
    cv.rect(ox + 21, oy + DESK_Y + 1, 3, 5, "metalH")             # slider knob
    cv.rect(ox + 21, oy + DESK_Y + 5, 3, 1, "metalD")
    cv.rect(ox + 33, oy + DESK_Y + 2, 4, 3, "greenD")             # STANDARD
    cv.rect(ox + 33, oy + DESK_Y + 2, 4, 1, "green")
    cv.rect(ox + 38, oy + DESK_Y + 2, 4, 3, "orangeD")            # FAST
    cv.rect(ox + 38, oy + DESK_Y + 2, 4, 1, "orange")


def draw_screen(cv, ox, oy, k, mode):
    """Screen contents for animation frame k. mode: idle | hi | off."""
    x0, y0 = ox + SCR_X, oy + SCR_Y
    for j in range(SCR_H):                                        # glass with faint scanlines
        cv.rect(x0, y0 + j, SCR_W, 1, "scrL" if (j % 3 == 0 and mode != "off") else "scr")
    if mode == "off":
        for j in range(SCR_H):                                    # dead screen: dim red static
            for i in range(SCR_W):
                if (i * 7 + j * 13) % 11 == 0:
                    cv.px(x0 + i, y0 + j, "redD")
        cv.rect(x0 + 13, y0 + 9, 8, 2, "redD")
        return
    sx, sy = ox + SUN[0], oy + SUN[1]
    cv.ring(sx, sy, *R_EARTH, "earthD")
    cv.ring(sx, sy, *R_MARS, "marsD", skip=lambda n: n % 3 != 0)  # Mars' orbit sparse dots (fainter)
    cv.disc(sx, sy, 1, "yellow")                                  # Sun
    for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
        cv.px(sx + dx, sy + dy, "yellowD")
    # launch-angle wedge: faint rays Sun -> Earth and Sun -> Mars (the 44 deg rule)
    ex, ey = orbit_pt(R_EARTH, 180)
    mx, my = orbit_pt(R_MARS, 180 - LEAD_DEG)
    for t in (0.35, 0.55, 0.75):
        cv.px(round(sx + (ex - SUN[0]) * t), round(sy + (ey - SUN[1]) * t), "cyanD")
        cv.px(round(sx + (mx - SUN[0]) * t), round(sy + (my - SUN[1]) * t), "cyanD")
    # dotted transfer arc, the spacecraft moving along it
    for n in range(34):     # bright dashes: the path is the star of the screen
        tx, ty = transfer_pt(n / 33)
        if n % 3 != 2:
            cv.px(ox + round(tx), oy + round(ty), "cyan" if (mode == "hi" or n % 3 == 0) else "cyanD")
    scx, scy = transfer_pt((k + 0.5) / FRAMES)
    cv.px(ox + round(scx), oy + round(scy), "white")
    cv.px(ox + round(scx) - 1, oy + round(scy), "cyan")
    # Earth (departure) and Mars (launch-day position, 44 deg ahead)
    cv.disc(ox + round(ex), oy + round(ey), 1, "earth")
    cv.px(ox + round(ex), oy + round(ey) - 1, "white")
    cv.disc(ox + round(mx), oy + round(my), 1, "mars")
    cv.px(ox + round(mx) - 1, oy + round(my) - 1, "marsL")
    # ghost Mars at arrival (opposite Earth), blinking
    gx, gy = orbit_pt(R_MARS, 0)
    if k % 2 == 0 or mode == "hi":
        cv.ring(ox + round(gx), oy + round(gy), 2, 2, "marsL" if mode == "hi" else "mars")
    # date strip along the bottom of the screen: launch window bar + chosen-day marker
    by = y0 + SCR_H - 3
    cv.rect(x0 + 3, by, SCR_W - 6, 1, "hull")
    cv.rect(x0 + 12, by, 9, 1, "greenD")
    cv.rect(x0 + 15, by - 1, 2, 3, "green" if k % 3 != 2 else "white")
    # status LED on the housing (blinks)
    cv.px(ox + SCR_X + SCR_W, oy + SCR_Y - 2, "cyan" if (k % 2 == 0 or mode == "hi") else "cyanD")


def outline(cv, ox, oy, c="cyan"):
    """1-px outline around the opaque pixels of one frame (player in range)."""
    solid = [[cv.P[ox + i, oy + j][3] > 200 for i in range(FW)] for j in range(FH)]
    for j in range(FH):
        for i in range(FW):
            if solid[j][i]:
                continue
            if any(0 <= i + di < FW and 0 <= j + dj < FH and solid[j + dj][i + di]
                   for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                cv.px(ox + i, oy + j, c)


def build_sheet():
    sheet = Canvas(FW * FRAMES, FH * 3)
    for row, mode in enumerate(("idle", "hi", "off")):
        for k in range(FRAMES if mode != "off" else 1):
            ox, oy = k * FW, row * FH
            draw_body(sheet, ox, oy)
            draw_screen(sheet, ox, oy, k, mode)
            if mode == "hi":
                outline(sheet, ox, oy)
    return sheet.img


# Where it stands in the CURRENT ship map for the demo (Mission Hub, right of the holo-table).
DEMO_POS = (272, 176)        # top-left of the frame on the 480x270 map


def layout_json():
    feet = (FW // 2, DESK_Y + DESK_H + FACE_H)     # bottom centre of the desk
    return {
        "name": "launch_planner",
        "label": "LAUNCH WINDOW PLANNER",
        "role": "navigator",
        "sheet": "planner_sheet.png",
        "frame_size": [FW, FH],
        "anchor": list(feet),
        "animations": {
            "idle": {"row": 0, "frames": FRAMES, "fps": 4},
            "highlight": {"row": 1, "frames": FRAMES, "fps": 6},
            "offline": {"row": 2, "frames": 1, "fps": 1},
        },
        "interact": {"x": feet[0], "y": feet[1] + 8, "radius": 14},
        "obstacle": {"x": DESK_X, "y": DESK_Y - 2, "w": DESK_W, "h": DESK_H + FACE_H + 2},
        "screen_rect": {"x": SCR_X, "y": SCR_Y, "w": SCR_W, "h": SCR_H},
        "screen_geometry": {
            "sun": list(SUN), "earth_orbit": list(R_EARTH), "mars_orbit": list(R_MARS),
            "mars_lead_deg": LEAD_DEG,
            "note": "angles counter-clockwise from +x with y up; Earth at 180 deg on launch day, "
                    "arrival at 0 deg (Hohmann: 180 deg transfer, ~259 days)",
        },
        "demo_position_in_ship_map": {"x": DEMO_POS[0], "y": DEMO_POS[1],
                                      "note": "Mission Hub, right of the holo-table (demo only)"},
    }


def dither_glow(img, cx, cy, rx, ry, rgb, strength=0.5):
    P = img.load()
    for j in range(cy - ry, cy + ry + 1):
        for i in range(cx - rx, cx + rx + 1):
            if not (0 <= i < img.width and 0 <= j < img.height):
                continue
            d = math.sqrt(((i - cx) / rx) ** 2 + ((j - cy) / ry) ** 2)
            if d >= 1:
                continue
            lvl = strength * (1 - d) ** 1.4 * 3
            base = math.floor(lvl)
            if (lvl - base) * 16 > BAYER[j % 4][i % 4]:
                base += 1
            if base:
                r, g, b = P[i, j][:3]
                t = min(base / 3 * 0.75, 0.75)
                P[i, j] = (round(r + (rgb[0] - r) * t), round(g + (rgb[1] - g) * t),
                           round(b + (rgb[2] - b) * t))


def previews(sheet):
    os.makedirs(os.path.join(OUT, "preview"), exist_ok=True)
    ship_path = os.path.join(HERE, "..", "lab_assets", "maps", "ship_480x270_nocrew.png")
    if os.path.exists(ship_path):
        ship = Image.open(ship_path).convert("RGB")
        x, y = DEMO_POS
        dither_glow(ship, x + FW // 2, y + DESK_Y + DESK_H + FACE_H + 4, 26, 9, C["cyan"], 0.45)
        ship = ship.convert("RGBA")
        ship.alpha_composite(sheet.crop((0, FH, FW, FH * 2)), (x, y))   # highlight: player in range
        ship = ship.convert("RGB")
        ship.save(os.path.join(OUT, "preview", "planner_in_hub.png"))
        ship.resize((ship.width * 4, ship.height * 4), Image.NEAREST).save(
            os.path.join(OUT, "preview", "planner_in_hub@4x.png"))
        crop = ship.crop((200, 130, 330, 250))
        crop.resize((crop.width * 6, crop.height * 6), Image.NEAREST).save(
            os.path.join(OUT, "preview", "planner_closeup.png"))
    frames = []
    for row in (0, 1):
        for k in range(FRAMES):
            f = Image.new("RGBA", (FW, FH), (24, 26, 40, 255))
            f.alpha_composite(sheet.crop((k * FW, row * FH, (k + 1) * FW, (row + 1) * FH)))
            frames.append(f.convert("RGB").resize((FW * 6, FH * 6), Image.NEAREST))
    frames[0].save(os.path.join(OUT, "preview", "planner_anim.gif"), save_all=True,
                   append_images=frames[1:], duration=220, loop=0)


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = build_sheet()
    sheet.save(os.path.join(OUT, "planner_sheet.png"))
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
        os.path.join(OUT, "planner_sheet@4x.png"))
    with open(os.path.join(OUT, "planner.json"), "w") as f:
        json.dump(layout_json(), f, indent=2)
    previews(sheet)
    print("ok", sheet.size)


if __name__ == "__main__":
    main()
