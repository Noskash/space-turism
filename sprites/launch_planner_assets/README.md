# Launch window planner — pixel-art interactable

A Navigator console for the design hub: walk up, interact, open the launch window planner.
Top-down 3/4 view, same palette as the ship map. Regenerate with `python draw_planner.py` (Pillow).

## Files
- `planner_sheet.png` (+ `@4x`): 48x48 frames.
  Row 0 `idle` (6 frames, 4 fps) · row 1 `highlight` (player in range, cyan outline, 6 fps) · row 2 `offline` (1 frame).
- `planner.json`: frame size, `anchor` (feet point), `interact` point + radius, `obstacle` rect,
  `screen_rect` (to draw live data on the screen), `screen_geometry` (Sun, orbit radii, 44° lead).
- `preview/`: `planner_in_hub.png` (+ `@4x`) placed in the current Mission Hub (demo position
  272,176), `planner_closeup.png`, `planner_anim.gif`.

## What the screen shows (real geometry, simplified)
Sun, Earth's and Mars' orbits; Earth on launch day on the left; Mars **~44° ahead** (where it must be
for a minimum-energy launch); the dashed transfer arc over the top (~259 days) with the spacecraft
moving along it; a blinking hollow **ghost Mars** at arrival, opposite Earth; a date strip with the
good window in green. Desk: date dial, date slider, STANDARD (green) / FAST (orange) buttons.
