# Upgrade parts — spacecraft designer (pixel art, top-down)

17 optional parts. Every file has a 1x original and an @4x copy. Scale only by whole
numbers with no smoothing (`image-rendering: pixelated` / `ctx.imageSmoothingEnabled = false`).

Rules baked into the assets (see `parts_upgrades.json`):
- Every upgrade uses 1 upgrade slot (Light 3 / Balanced 5 / Heavy 8).
- Every upgrade costs budget, mass AND power — `stats` are left null for balancing.
- `mount: "cell"` parts sit inside a slot; draw `frames/slot_<role>.png` on top of the slot.
- External parts (`wings`, `top`, `boom`) mount outside the body; their slot shows
  `frames/linked_<role>.png`. `solar_large` replaces `solar_small`, `antenna_high` replaces `antenna_low`.

Folders:
- `icons/` — 32x32 catalog icons (role-coloured top bar, "+" = upgrade)
- `mounted/` — sprites as fitted on the ship
- `frames/` — role-coloured slot frames and linked plates
- `loadouts/` — example builds for each class (160x128)
- `upgrades_sheet.png` — overview
- `draw_upgrades.py` (+ `draw_parts.py`, which it imports) — regenerate: `python3 draw_upgrades.py <out_dir>`

| Role | Upgrades |
|---|---|
| Engineer (orange) | Large solar array, RTG, Large battery, Radiator/heater, Rad-hardened computer |
| Comms (green) | High-gain dish, Small recorder, Large recorder, Relay radio |
| Navigator (cyan) | Large tank, Star tracker, Reaction wheels |
| Scientist (purple) | High-res camera, Spectrometer, Radar sounder, Thermal imager, Magnetometer |
