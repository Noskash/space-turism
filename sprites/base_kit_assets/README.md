# Base kit — spacecraft parts (pixel art, top-down)

Every file has a 1x original and an @4x copy. Scale only by whole numbers with no smoothing
(`image-rendering: pixelated` / `ctx.imageSmoothingEnabled = false`).

- `icons/` — 32x32 catalog icons; top bar colour = role (orange Engineer, green Comms, cyan Navigator, purple Scientist)
- `mounted/` — parts as they sit on the ship (solar wing is the right-hand wing; flip it for the left)
- `bodies/` — empty Light (3 slots) / Balanced (5) / Heavy (8) bodies; dark dotted squares = upgrade slots
- `previews/` — each class with the full base kit fitted, 160x128
- `base_kit_sheet.png` — overview
- `parts_base.json` — part ids/roles/files, each class's grid cells (base kit vs upgrade slot) and mount anchors.
  `stats` (mass, power, cost) are left null for you to balance.
- `draw_parts.py` — regenerates everything: `python3 draw_parts.py <out_dir>` (needs Pillow)

Base kit: small solar panels, small battery, standard computer, low-gain antenna,
small propellant tank, main engine, basic thrusters, weather sensor.
