"""Friend skins — 16x16 crew sheets in the same format as the crew sprites.

    python draw_skins.py            # writes <skin>/sheet.png, sheet@4x.png and skins.json here

Sheet: 8 cols x 4 rows of 16x16 frames, feet anchor (8, 15).
  row 0: idle down x2, up x2, left x2, right x2
  row 1: walk down 0-3, walk up 4-7
  row 2: walk left 0-3, walk right 4-7
  row 3: work_up 0-1, work_down 2-3, alarm 4-5

Each skin is drawn from ASCII templates (rows 0-12 = head + torso, legs are generated),
so the pixels are easy to review and tweak. Right-facing frames mirror the left ones.
Legend:
  .  transparent      H/h hair / hair highlight     R hair bow
  S  skin             c cheek        E eye
  J/j jacket / jacket highlight      W white shirt  T/t tie / tie stripe
  D/d dress / dress shade            P trousers     L bare leg     K shoes
"""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = 16
COLS, ROWS = 8, 4

SKINS = {
    # friend_1: thick straight black fringe, rosy cheeks, black puffer jacket,
    # white shirt + navy tie, dark trousers.
    "friend_1": {
        "label": "Friend 1",
        "height_cm": 173,
        "palette": {
            "H": "#16131b", "h": "#2e2a38", "S": "#e7b393", "c": "#db8b7c", "E": "#1d1420",
            "J": "#1f2129", "j": "#454a5c", "W": "#eef1f5", "T": "#1f2b55", "t": "#1f2b55",
            "P": "#3b4058", "K": "#121216",
        },
        "legs": "trousers",
        "down": [
            "................",
            ".....HHHHHH.....",
            "....HHhhHHHH....",
            "....HHHHHHHH....",
            "....HHHHHHHH....",
            "....HSESSESH....",
            "....ScSSSScS....",
            ".....SSSSSS.....",
            "....JJWWWWJJ....",
            "...JJjWTTWjJJ...",
            "...JJjJTTJjJJ...",
            "...JJjJJJJjJJ...",
            "...SJJJJJJJJS...",
        ],
        "up": [
            "................",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "....HHhhHHHH....",
            "....HHHHHHHH....",
            "....HHHHHHHH....",
            "....SHHHHHHS....",
            ".....SHHHHS.....",
            "....JJJJJJJJ....",
            "...JJJJJJJJJJ...",
            "...JJjJJJJjJJ...",
            "...JJJJJJJJJJ...",
            "...SJJJJJJJJS...",
        ],
        "left": [
            "................",
            ".....HHHHH......",
            "....HHHHHHH.....",
            "....HHHHhHHH....",
            "....HHHHHHHH....",
            "....SESSHHHH....",
            "....ScSSSSHH....",
            ".....SSSSHH.....",
            ".....WJJJJJ.....",
            ".....TJjJJJ.....",
            ".....JJjJJJ.....",
            ".....JJjJJJ.....",
            ".....JJSJJJ.....",
        ],
    },
    # friend_2: voluminous wavy dark-brown hair over the ears, brown jacket worn open,
    # white shirt, navy tie with a green stripe.
    "friend_2": {
        "label": "Friend 2",
        "height_cm": 178,
        "palette": {
            "H": "#2a1c16", "h": "#453024", "S": "#efc6a6", "c": "#efc6a6", "E": "#24160f",
            "J": "#7a5536", "j": "#94704c", "W": "#eef1f5", "T": "#1d2747", "t": "#2f8a5a",
            "P": "#3d4257", "K": "#1a1414",
        },
        "legs": "trousers",
        "down": [
            "......H.H.......",
            "....HHHHHHH.....",
            "...HHHhHHHHH....",
            "...HHHHHHhHHH...",
            "...HHHHSHHHHH...",
            "...HHSESSESHH...",
            "...HHSSSSSSHH...",
            "....HSSSSSSH....",
            "....JJWWWWJJ....",
            "...JJJWTTWJJJ...",
            "...JJjWtTWjJJ...",
            "...JJjWTTWjJJ...",
            "...SJJjWWjJJS...",
        ],
        "up": [
            "......H.H.......",
            "....HHHHHHH.....",
            "...HHHHHHHHH....",
            "...HHHhHHHHHH...",
            "...HHHHHHHHHH...",
            "...HHHHHhHHHH...",
            "...HHHHHHHHHH...",
            "....HHHHHHHH....",
            "....JJJJJJJJ....",
            "...JJJJJJJJJJ...",
            "...JJjJJJJjJJ...",
            "...JJJJJJJJJJ...",
            "...SJJJJJJJJS...",
        ],
        "left": [
            "......H.H.......",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "...HHHHHhHHHH...",
            "...HSHHHHHHHH...",
            "....SESSHHHHH...",
            "....SSSSSHHHH...",
            ".....SSSHHHH....",
            ".....WJJJJJ.....",
            ".....TJjJJJ.....",
            ".....tJjJJJ.....",
            ".....JJjJJJ.....",
            ".....JJSJJJ.....",
        ],
    },
    # Companion: ~150 cm, so 13 px tall instead of 15. Long dark hair, pink bow, pink dress.
    "friend_1_girl": {
        "label": "Friend 1's companion",
        "height_cm": 150,
        "palette": {
            "H": "#2b1a17", "h": "#4a2f28", "R": "#ff4f9a", "S": "#f0c4a8", "c": "#ee9a9a",
            "E": "#22151a", "D": "#ff86bd", "d": "#e05a9c", "L": "#f0c4a8", "K": "#c23b78",
        },
        "legs": "bare",
        "down": [
            "................",
            "................",
            "................",
            ".....HHHHHH.....",
            "....HHHhHHRR....",
            "....HHHHHHHH....",
            "....HSESSESH....",
            "....HcSSSScH....",
            "....HHSSSSHH....",
            "....HHDDDDHH....",
            "....HDDDDDDH....",
            "...SDDdDDdDDS...",
            ".....DDDDDD.....",
        ],
        "up": [
            "................",
            "................",
            "................",
            ".....HHHHHH.....",
            "....HHHHHHRR....",
            "....HHHhHHHH....",
            "....HHHHHHHH....",
            "....HHHHHHHH....",
            "....HHHHHHHH....",
            "....HHHHHHHH....",
            "....DHHHHHHD....",
            "...SDDHHHHDDS...",
            ".....DDDDDD.....",
        ],
        "left": [
            "................",
            "................",
            "................",
            ".....HHHHH......",
            "....HHHHHRR.....",
            "....HHHhHHHH....",
            "....SESSHHHH....",
            "....ScSSSHHH....",
            ".....SSSHHHH....",
            ".....DDDHHHH....",
            ".....DDDDHHH....",
            ".....DDSDDH.....",
            ".....DDDDDD.....",
        ],
    },
}

# Leg rows 13-15 per pose. "step_a"/"step_b" alternate which foot is lifted.
LEGS = {
    "trousers": {
        "front": {
            "idle":   ["....PPPPPPPP....", ".....PP..PP.....", ".....KK..KK....."],
            "step_a": ["....PPPPPPPP....", ".....PP..KK.....", ".....KK........."],
            "step_b": ["....PPPPPPPP....", ".....KK..PP.....", ".........KK....."],
        },
        "side": {
            "idle":   [".....PPPPPP.....", "......PPPP......", ".....KKKK......."],
            "step_a": [".....PPPPPP.....", ".....PP..PP.....", "....KK....KK...."],
            "step_b": [".....PPPPPP.....", "......PPPP......", "......KKK......."],
        },
    },
    "bare": {
        "front": {
            "idle":   ["....DdDDDDdD....", "......L..L......", ".....KK..KK....."],
            "step_a": ["....DdDDDDdD....", "......L..K......", ".....KK........."],
            "step_b": ["....DdDDDDdD....", "......K..L......", ".........KK....."],
        },
        "side": {
            "idle":   ["....DDDdDDDD....", ".......LL.......", "......KKK......."],
            "step_a": ["....DDDdDDDD....", "......L..L......", ".....KK..KK....."],
            "step_b": ["....DDDdDDDD....", ".......LL.......", "......KKK......."],
        },
    },
}


def pose(skin, facing, legs="idle"):
    """Returns a 16x16 list of chars."""
    upper = skin["up" if facing == "up" else "left" if facing in ("left", "right") else "down"]
    leg_set = LEGS[skin["legs"]]["side" if facing in ("left", "right") else "front"][legs]
    grid = [list(row) for row in upper + leg_set]
    assert len(grid) == FRAME and all(len(r) == FRAME for r in grid), (facing, legs)
    if facing == "right":
        grid = [row[::-1] for row in grid]
    return grid


def hands(grid):
    """Hand pixels = skin pixels below the head (row >= 9) on the outer columns."""
    return [(x, y) for y in range(9, 13) for x in (3, 12) if grid[y][x] == "S"]


def move_hands(grid, targets):
    g = [row[:] for row in grid]
    for x, y in hands(g):
        g[y][x] = "."
    for x, y in targets:
        g[y][x] = "S"
    return g


def body_top(skin):
    """First torso row (collar / neckline) of the down template."""
    for y, row in enumerate(skin["down"]):
        if any(ch in row for ch in "JD"):
            return y
    return 8


def frames_for(skin):
    """All 32 frames in sheet order (None = empty)."""
    top = body_top(skin)
    out = []
    # Row 0: idle x2 per direction (two identical frames for now).
    for facing in ("down", "up", "left", "right"):
        base = pose(skin, facing)
        out += [base, base]
    # Row 1: walk down, walk up.
    for facing in ("down", "up"):
        out += [pose(skin, facing, l) for l in ("idle", "step_a", "idle", "step_b")]
    # Row 2: walk left, walk right.
    for facing in ("left", "right"):
        out += [pose(skin, facing, l) for l in ("idle", "step_a", "idle", "step_b")]
    # Row 3: work_up x2 (hands raised to the console), work_down x2 (typing), alarm x2.
    back = pose(skin, "up")
    front = pose(skin, "down")
    out += [move_hands(back, [(4, top + 1), (11, top + 2)]),
            move_hands(back, [(4, top + 2), (11, top + 1)])]
    out += [move_hands(front, [(4, top + 3), (11, top + 4)]),
            move_hands(front, [(4, top + 4), (11, top + 3)])]
    out += [move_hands(front, [(2, top - 1), (13, top - 1)]),
            move_hands(front, [(2, top), (13, top)])]
    out += [None, None]
    return out


def hex_rgba(value):
    value = value.lstrip("#")[:6]
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def render(skin):
    palette = {k: hex_rgba(v) for k, v in skin["palette"].items()}
    sheet = Image.new("RGBA", (FRAME * COLS, FRAME * ROWS), (0, 0, 0, 0))
    for i, grid in enumerate(frames_for(skin)):
        if grid is None:
            continue
        ox, oy = (i % COLS) * FRAME, (i // COLS) * FRAME
        for y, row in enumerate(grid):
            for x, ch in enumerate(row):
                if ch != ".":
                    sheet.putpixel((ox + x, oy + y), palette[ch])
    return sheet


def main():
    manifest = {
        "frame_size": [FRAME, FRAME],
        "columns": COLS,
        "rows": ROWS,
        "feet_anchor": [8, 15],
        "animations": {
            "idle_down": [[0, 0], [0, 1]], "idle_up": [[0, 2], [0, 3]],
            "idle_left": [[0, 4], [0, 5]], "idle_right": [[0, 6], [0, 7]],
            "walk_down": [[1, 0], [1, 1], [1, 2], [1, 3]],
            "walk_up": [[1, 4], [1, 5], [1, 6], [1, 7]],
            "walk_left": [[2, 0], [2, 1], [2, 2], [2, 3]],
            "walk_right": [[2, 4], [2, 5], [2, 6], [2, 7]],
            "work_up": [[3, 0], [3, 1]], "work_down": [[3, 2], [3, 3]],
            "alarm": [[3, 4], [3, 5]],
        },
        "skins": {},
    }
    for name, skin in SKINS.items():
        folder = os.path.join(HERE, name)
        os.makedirs(folder, exist_ok=True)
        sheet = render(skin)
        sheet.save(os.path.join(folder, "sheet.png"))
        sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(
            os.path.join(folder, "sheet@4x.png"))
        manifest["skins"][name] = {
            "label": skin["label"],
            "height_cm": skin["height_cm"],
            "sheet": f"{name}/sheet.png",
        }
    with open(os.path.join(HERE, "skins.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print("wrote", ", ".join(SKINS))


if __name__ == "__main__":
    main()
