# Mars Mission Ship — pixel-art assets

Top-down (3/4 view) ship interior. Base resolution 480x270; all coordinates in
`ship_layout.json` are in that base space — multiply by your display scale.

## Files
- `maps/ship_480x270_nocrew.png` — base map for the game (use this in code)
- `maps/ship_960x540_nocrew.png`, `maps/ship_1920x1080_nocrew.png` — pre-scaled 2x / 4x
- `preview/ship_preview_with_crew_1920x1080.png` — preview with 4 astronauts for scale
- `ship_layout.json` — rooms (walkable), doors, stations (interaction points + radius), obstacles (collision rects)
- `source/draw_ship.py` — regenerates everything: `python3 draw_ship.py <out_dir> [--no-crew]` (needs Pillow)

## Rendering
Scale by whole numbers only, with no smoothing:
- CSS: `image-rendering: pixelated;`
- Canvas: `ctx.imageSmoothingEnabled = false;`

## Stations
| Role | Room | Color |
|---|---|---|
| Navigator (NAV) | Bridge | cyan |
| Engineer (PWR) | Engine room | orange |
| Comms (COM) | Comms | green |
| Scientist (SCI) | Science lab | purple |
| Team planning (PLAN) | Mission hub holo-table | cyan |
