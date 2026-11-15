# Assembly Hangar: pixel-art assets

The hub where a run starts. The crew walks between role shelves, reads parts (F), carries them
(SPACE) to the assembly bay, swaps the ship class at the stands, and readies up at the launch door.
Top-down 3/4 view at 480x270, in the same palette as `lab_assets` (the ship map).
Every coordinate in `hangar_layout.json` is in that 480x270 space.

**Parts are never drawn here.** Shelves, carried items and the ship use the existing sprites in
`base_kit_assets/` and `upgrade_kit_assets/`. A part with no sprite gets a labelled crate in
`placeholders/` (right now only `whipple_shield`).

## Files
| File | What it is |
|---|---|
| `maps/hangar_480x270.png` (+ `960x540`, `1920x1080`) | Game background. Shelves are **empty** (only a painted outline of each part, shadow-board style). The bay cradle is empty. No crew. |
| `maps/hangar_overlay_480x270.png` (+ 2x, 4x) | Transparent layer to draw **above the crew**: the gantry crane beam, trolley and hook. |
| `preview/hangar_preview_full_1920x1080.png` | Mock-up: stocked shelves, balanced ship on the bay, 4 crew carrying parts, an open info card, board numbers from `design_stats.json`. |
| `hangar_layout.json` | Walkable area, collision, interaction points, board fields (reference below). |
| `ui/info_card.png` (+ `@4x`) | Empty 9-slice panel for the F info card, 48x48. Margins: left 6, top 14 (header band), right 6, bottom 6. |
| `sockets/cell_glow.png`, `sockets/mount_glow.png` (+ `@4x`) | **White** glows for open upgrade cells (16x16, draw at cell -2,-2) and external mount points (11x11, centre at -5,-5). Modulate them with the role colour. |
| `placeholders/icons/<id>.png`, `placeholders/mounted/<id>.png` (+ `@4x`) | Crate stand-ins for parts with no sprite. |
| `source/draw_hangar.py` | Regenerates everything above. |

## Regenerate
```
python3 sprites/hangar_assets/source/draw_hangar.py sprites/hangar_assets [--no-crew] [--class light|balanced|heavy]
```
Needs Pillow. The output is the same on every run (seeded). `--class` only picks the ship on the bay
in the **preview**, and `--no-crew` hides the crew and the info card in the preview.
The game map is the same for every class. Paths default to the project layout. Override them with
`--sprites <sprites dir>` and `--stats <design_stats.json>`. Layout numbers are constants at the
top of the script (`RACKS`, `BOARD`, `BAY`, `ANCHOR`, `BENCHES`, `STANDS_TOP`, `SPAWNS`, ...).

## Floor plan
```
 [ENGINEER rack]  [===== WALL BOARD =====]  [COMMS rack] [LAUNCH DOOR]
                  |- gantry ------------|                  ^ launch zone
 [bench]          |   ASSEMBLY BAY      |          [bench]
 IN> spawns 1-4   |   (ship in cradle)  |                    [crates]
                  |_____________________|                    [tools]
                   [LIGHT] [BALANCED] [HEAVY]
 [SCIENTIST rack]                                [NAVIGATOR rack]
```
Flow: enter west → role shelf → bay → class stands → launch door (north-east).

## How the game should use it
- **Shelves.** For each `shelf_slots[i]`, draw its `mounted` sprite centred in `bin`:
  `pos = bin.xy + (bin.wh - sprite.size) / 2` (int division, the same rule as `ShipPreview._draw_centered`).
  When a part is taken, stop drawing it and the painted outline shows the empty spot.
  Shelves show `mounted/` sprites (8–44 px, world scale). The 32x32 `icons/` are twice a crew
  member's height, so they go on the info card instead.
- **Interacting.** Pick the nearest slot whose `interact_radius` (measured from `x, y`) contains the
  player's feet. Every slot was checked to be reachable with the crew's 8x4 foot collider
  (closest standing spot: 23 px for north racks, 22 px for south racks) and to be the nearest slot
  from at least one spot. Role restriction is game logic. `racks[]` gives each rack's rectangle for
  "not your shelf" feedback.
- **Carrying.** Draw the carried part's `mounted` sprite bottom-centred at `feet + carry.offset` (0, -16).
- **Assembly bay.** The ship is drawn at runtime, not baked into the map, because it changes with
  the class and with every part mounted. Put a `ShipPreview` node at `assembly.preview_origin`
  (= `body_anchor - (80, 62)`). The coordinates in `parts_base.json` are relative to that origin:
  open cell = `preview_origin + body_origin + cell.xy`; mount anchor = `preview_origin + mounts[...]`.
  Light the open cells with `cell_glow` in the role colour of the part being carried. Mark wings
  (engineer), top (comms) and boom (scientist) with `mount_glow`. The worst case (heavy + large
  solar array + dish + magnetometer) fits inside the platform. The platform is walkable, so players
  can reach inner cells. Only the gantry feet block.
- **Class stands.** All three bodies are baked in as display models. SPACE at a stand swaps the
  class. Light `lamp` (2 px) and/or draw a frame around `plinth` for the active class.
- **Wall board.** The labels MASS / POWER / BUDGET / SLOTS / ROCKET / CLASS are baked in.
  `board.fields.<id>.bar` is an empty 60x3 track to fill. `.value`, `class` and `rocket` are text
  boxes for full-resolution UI text. The preview shows the intended look (numbers from `DesignRules.evaluate`).
- **Launch door.** `ready_lights` are 4 lamp centres (unlit = dark red, light them green per READY player).
  `zone` is the hazard-striped floor in front of the door.
- **Overlay.** Draw `maps/hangar_overlay_480x270.png` above the crew so they walk under the beam.

## Notes / open items
- `whipple_shield` has **no sprite and no entry** in `parts_upgrades.json` or `design_stats.json`.
  It sits on the NAV shelf as a crate placeholder. The info card and the designer need its stats
  (mass, power, cost, desc, effects) added before it can be bought.
- There is no `sprites/crew/` folder. The preview uses the placeholder astronaut from `draw_ship.py`
  with the game's role ring. If `sprites/crew/<role>/sheet.png` appears, the script uses it.
- Scale only by whole numbers with nearest filtering (Godot: texture filter Nearest).
