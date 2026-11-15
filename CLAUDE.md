# CLAUDE.md — Mars mission co-op game (NASA Space Apps hackathon)

## How to work with me
- Claude writes the code; we review it together afterwards. Explain what was built, the trade-offs
  taken, and anything that needs a decision.
- For real design choices (gameplay, controls, contract changes), give 2–3 options, what each trades
  off, and your pick — decide small technical things yourself and say so.
- Engine: **Godot 4, GDScript**. Two programmers (me + partner), two-day hackathon.

## The game in one paragraph
An educational, **Overcooked-style co-op** game about designing and flying a real NASA-style Mars
mission. 1–4 players, each with a crew role. Phase 1: the team designs a spacecraft under mass,
power and budget limits. Phase 2: plan the launch and transfer to Mars. Phase 3: live operations —
everyone runs between stations on a top-down ship map, putting out fires (solar storms, comms
blackouts, drift, battery drain) while the mission flies. Phase 4: report explaining *why* it
succeeded or failed, plus a "here's what NASA actually did" comparison. Core lesson: **there is no
single best design — every choice is a trade-off, and fixing one bottleneck exposes the next.**

## Hard rules (do not break)
1. **Every upgrade costs mass AND power (plus budget). No pure-bonus upgrades.** Mass and power are
   the core balancer of the game.
2. **Whole game is pixel art.** Top-down 3/4 view for the ship map and characters. Never smooth
   textures (Nearest filter, integer scaling).
3. Scientifically grounded: no aliens, no asteroid fields between Earth and Mars. Hazards are real
   phenomena (see Events). Physics may be simplified/exaggerated for gameplay — label it "simplified".
4. Points come only from mission outcome, never from buying parts.

## Crew roles (up to 4 players, local co-op on one keyboard first)
| Role | Colour | Decides in design | Busy with during mission | Keys |
|---|---|---|---|---|
| Navigator | cyan | path, launch date, fuel | course corrections, Mars Orbit Insertion brake | Q W E R |
| Engineer (power+heat) | orange | solar, battery, launcher | switching loads, resetting storm faults | Z X C V |
| Comms | green | antenna, data storage | downlink during ground passes, conjunction prep | U I O P |
| Scientist | purple | instruments | catching science opportunities, toggling instruments | B N M , |

Built-in conflicts: Scientist↔Engineer (instruments drain power), Scientist↔Comms (data fills
storage), Navigator↔Comms (turning to burn points antenna away from Earth), Navigator↔Engineer
(burns draw power). Everyone shares one mass + budget limit in design.

Fewer players: 1 = all stations, Tab to switch, slower events; 2 = Nav+Eng / Comms+Sci;
3 = Nav / Eng / Comms+Sci. Event rate scales with player count.

Input architecture: all input becomes action dictionaries (`{type:"burn", dir:"prograde"}`)
sent through a signal bus → one place applies them. Keyboard first; phones-as-controllers
(Jackbox style, over network) is a stretch goal that reuses the same actions.

## Phases
1. **Design** (~3 min): pick ship class, buy upgrades into slots.
2. **Launch planner** (calm): sliders for launch day + departure Δv; dotted predicted path; ghost
   Mars shows where Mars will be on arrival. Launcher max Δv drops with spacecraft mass.
3. **Cruise** (live, ~90 s): drift + events; Navigator taps small burns (cost fuel + power).
4. **Mars Orbit Insertion**: in capture zone, hold brake ~4 s; needs fuel AND power at that moment.
   Outcomes: Orbit (full science phase ~90 s) / Flyby (partial) / Miss.
5. **Report**: launch angle vs ideal ~44°, trip time vs ~259 days, fuel used, science returned,
   why it went that way, NASA comparison card, 1–3 stars.

## Design phase (built 2026-11-14, `scenes/design/designer.tscn`)
Flow: level select → lobby → **Designer** → cruise (`game.tscn`). Mars' LevelData points at the designer.
- One shared screen; every player has a cursor (WASD + SPACE). Columns: SHIP (class + READY) shared;
  NAV / PWR / COM / SCI reachable only by players holding that role (`CrewRoles`). One shared pool of
  slots, mass, power and budget, so roles compete. Launch when all players are READY and the ship
  has no errors; any change un-readies everyone.
- Rocket = cheapest launcher that lifts the ship's mass; its price comes out of the budget.
- Power can go negative (allowed, shown red): the battery then drains in cruise — that is the lesson.
- `DesignRules` (`scripts/design/design_rules.gd`): totals, limits, `check_add`, `mission_params(design)`.
  Numbers: `data/design_stats.json` (first guesses, not balanced). Art/slots: asset JSONs.
- Design → cruise: `DesignRules.chosen` → `Mission.start(design)`; fake_mission reads `mission_params`
  (battery Wh, solar W, load watts, storage, data rate, downlink, DSN pass, burn fuel, repair time,
  storm/leak rates, science per window).
- Co-op: host owns the design; clients send `{type = toggle|class|ready}`; cursors relayed via host.
- Known stretch: solar_large and RTG *make* power (net +W) — they "pay" in mass and budget instead.

## Launch mini-game (built 2026-11-14, `scenes/launch/launch.tscn`)
Flow: Designer → **Launch** → cruise. ~30-45 s, SIMPLIFIED physics (labelled on screen).
- W/S push/pull a throttle lever (stays put). Co-op: throttle = AVERAGE of all players' levers.
- Thrust/weight from ship mass vs rocket capacity (`DesignRules.evaluate`): heavy ships need more lever to lift off.
- Max-Q = dynamic pressure (speed² × air density). Over the limit, STRESS builds: 75% = strained (+1 damage),
  100% = **breakup → launch failed**. Fast/light rockets must throttle down; slow heavy ones barely reach max-Q.
- Stage 1 burnout → SPACE to separate (auto after 4 s). Rocket dry before 7.8 km/s → the spacecraft's tank
  finishes the climb; if that runs dry → **out of fuel, launch failed**. Failure: SPACE = new rocket, D = redesign.
- Designer picks the cheapest rocket with a **10% lift margin** (`DesignRules.LIFT_MARGIN`). Ships at that
  margin reach orbit only flown at full throttle with fast staging, with ~5% fuel left.
- Result `{fuel_left, damage}` → `DesignRules.chosen.launch` → cruise starts with that fuel, and one station
  OFFLINE (repair ticket) per damage hit.
- Rocket sprites: light = electron, medium = zenit, heavy = proton (`sprites/rockets`). Host runs the flight.
- Staging window: after stage 1 burnout, SPACE within 6 s (`STAGE_WINDOW`; beeps speed up after 75%). Missed ->
  rocket falls back, parachute at 3 km, lands -> **launch failed** (same SPACE / D options).

## Space weather (built 2026-11-15, in `fake_mission.gd`; port to Mission.gd later)
- **Solar radiation storm** (solar particle event): first ~24 s, then every 42-58 s. Warning (siren + banner):
  9 s from the base-kit weather sensor, 16 s with the **solar particle monitor** (SCI upgrade, `cme_warning: 7`).
  What the crew can do depends on the design:
  - **Radiation shielding bought** (PWR upgrade, 50 kg, `shields: 1`): ticket kind "shields", role "team"
    (Mission Hub holo-table, anyone). SPACE opens `ShieldGame` (`scripts/game/minigames/shield_game.gd`): a needle
    sweeps a gauge, SPACE in the green zone charges a capacitor (3; rad-hard CPU -> 2; each charge = faster
    needle, smaller zone; miss = 0.4 s lockout). Success -> `cme.shields = true` (bubble around the hull) ->
    wave is harmless + bonus storm science.
  - **No shielding**: ticket kind "safe_mode", role "engineer". SPACE opens `SafeModeGame`
    (`minigames/safe_mode_game.gd`): a row of breakers, cut the blinking one each time (A/D move, SPACE flip;
    random order; wrong one = 0.5 s lockout; 4 breakers, rad-hard CPU -> 3) -> `cme.safe = true`: all loads off
    and locked until the wave has passed (no science, no downlink), but no damage.
  - Neither done when the wave (6 s) hits = **ship disabled**: blackout 10 s (solar bus tripped, loads off,
    -15% battery; only `storm_proof_w` = RTG still generates), Engine room + one random station offline.
- **Comet debris** (real: comet trails; hard rule #3 kept, it is labelled comet debris): first ~50 s, then every
  45-60 s. Warning 7 s (+4 star tracker), then phase "stream" waits up to 8 s for a pilot. The Navigator docked
  at the Bridge gets `DodgeGame` (`minigames/dodge_game.gd`): FULL SCREEN, Spacewar-style (A/D turn, W thrust,
  S brake, screen wraps, no guns), 6 s, rocks fly in from the edges faster and faster. Runs on the pilot's
  machine: `dodge_start` -> phase "flying" -> `dodge_result {hits, thrust, turning}`. No pilot = 3 hits.
  Each hit: random station offline or -8% fuel. Reaction wheels: faster turning, turning costs no fuel.
  Star tracker: earlier warning + red edge chevrons before rocks fly in. While flying, no downlink.
- Minigames are CanvasLayers (layer 15) that call `Tutorial.hold()` so crew/station input is off meanwhile.
  They share one look (`MinigameFrame`, see UI kit). Q closes shields / safe mode on that machine only (the
  ticket stays, anyone can reopen it); the dodge game has no close (it would have to report a result).
- State: `cme {phase, time_left, duration, shielding, shields, safe}`, `blackout`,
  `dust {phase, time_left, hits, wheels, tracker}`.
- Part effects (data/design_stats.json): rad_shielding `shields`, particle_monitor `cme_warning`, rtg
  `storm_proof_w`, computer_radhard `cme_tasks: -1` (= one fewer shield charge), star_tracker `dust_warning: 4`,
  reaction_wheels `steer_free: 1` -> `DesignRules.mission_params`. New part art: `draw_upgrades.py` (19 upgrades).
- Visuals: HUD banner, wave band sweeping from the Sun, blackout darkness, shield bubble, debris grains
  outside the hull, hull impact sparks; sounds siren / wave / impact / static.

## Radio (`scripts/game/radio_set.gd` object + `scripts/game/radio.gd` audio)
- A boombox on the Mission Hub bench (RadioSet, use point 308,158). Walk up, SPACE = on/off
  (CrewMember sends `{type = "radio"}`; sim keeps `state.radio = {on, track}`, so co-op peers hear the same radio;
  switching on tunes to the next track). Notes float up while it plays.
- 5 CC0 jazz tracks from OpenGameArt in `music/` (authors in `music/CREDITS.md`), on a "Music" bus (ESC menu
  MUSIC level, saved). Dies in a blackout, static during a radiation wave.

## ESC menu (`scripts/ui/pause_menu.gd`, class `PauseMenu`)
- `PauseMenu.attach(scene, leave_text, controls_text)` on designer / launch / cruise: RESUME, HOW TO PLAY, SOUND
  (Master bus, saved in `user://settings.cfg`), MUSIC, TEXT SIZE (NORMAL / LARGE / HUGE, `UiFont`), FULLSCREEN,
  LEAVE (press twice), QUIT (press twice). The footer lists the screen's controls (`controls_text`).
- Offline it pauses the tree; in co-op the mission keeps running and only local input is blocked
  (`Tutorial.hold()` shares the tutorial's input gate). Tutorial + PauseMenu + Sfx run with PROCESS_MODE_ALWAYS.

## Cruise lighting (`scripts/game/ship_lighting.gd`, `shaders/light_*.gdshader`)
- SIMPLIFIED: progress = day / 259 on the transfer ellipse (a 1.26 AU, e 0.206) -> Sun 1.00 -> 1.52 AU,
  sunlight 1/r^2 (100% -> 43%). The Sun's screen direction sweeps left -> upper-right (exaggerated).
  HUD shows "DAY n  x.xx AU".
- Shadows (layer between map and crew): room walls, layout obstacles and crew (sheared sprite silhouette)
  cast away from the Sun; longer and fainter as light weakens.
- `light_shade` (multiply): far side darker, global dimming with distance, vignette, red emergency
  lighting when power < ~22%. `light_glow` (add): sunlight + god rays, Earthshine fading, Mars glow growing,
  station light pools (pulse on pending ticket, flicker offline), solar-storm shimmer.
- Station nodes use z_index 45 so their panels sit above the lighting (z 40/41); Vfx particles are z 50.
- Not done: solar panel output in the sim does NOT yet fall with distance (fake_mission / Person A).

## Tutorial (`scripts/ui/tutorial.gd`, class `Tutorial`)
- `Tutorial.attach(scene, id, panes)`: dialog panes `{title, body, rect}` (rect = highlight in 480x270 units).
  Shown once per screen (designer / launch / cruise); SKIP on any pane turns it off everywhere; H reopens.
  State in `user://tutorial.cfg`. While open, `Tutorial.is_blocking()` gates gameplay input; the host's open
  tutorial holds the launch countdown and the cruise sim tick.
- Cruise tickets: a "warn" chirp at 75% of a ticket's time, then "remind" beeps that speed up (`vfx.gd`).
- **Event walkthroughs** (`scripts/game/event_guide.gd`, `EventGuide`): the first time each event happens
  (radiation storm shielded / safe-mode, comet debris, blackout, the 3 faults, science window, repair, low
  battery, full storage), a dialog explains it (real basis, who, how, which parts help; sim paused), then a live
  "HOW TO BEAT IT" checklist under the HUD's alert strip + arrow over the station ticks off steps from sim state,
  then an outcome stamp. Seen state `seen/event_<id>` in tutorial.cfg; off with SKIP TUTORIAL. In co-op only the
  host's open dialog pauses the sim. Pane highlights use `UiKit.hud_rect(...)`, not fixed numbers.

## Presentation
- Gameplay scenes use `PixelMode` (480x270, integer scale, **canvas_items** stretch) so UI text renders at
  full resolution; pixel art keeps Nearest filtering. UI font: Share Tech Mono (OFL, `ui/fonts/`) via `UiFont`.
- Cruise: stars stream past the hull (3 parallax layers), the ship bobs gently, engines flicker, reactor glows,
  engine drone loop.

## UI kit (built 2026-11-15; "Soul Knight x Among Us" feel, our own art)
- `UiKit` (`scripts/ui/ui_kit.gd`): palette (INK outline, PANEL, TEXT/DIM/FAINT, GOOD/WARN/BAD, `ROLE_COLORS`,
  `RESOURCE_COLORS` = owner role's colour) + immediate-mode helpers called from `_draw()`: `panel` (1 px ink
  outline, cut corners, light top / dark bottom bevel, optional accent top edge), `frame` (big 2 px frame),
  `seg_bar` (segments, red "lost" / light "incoming" ghost), `chip`, `keycap`, `icon`, `text/text_c/text_r`
  (ink outline), `fit`, `wrap`, `dither` (50% checker), `stamp` ("DONE"). Rules: whole pixels, no gradients or
  blur (dither or hard bands instead), every block has an ink outline. Call `UiKit.setup_canvas(node)`.
- `UiJuice` (`scripts/ui/ui_juice.gd`): kick(key) -> pop / flash / shake / bounce values. Kick only from sim
  state diffs so co-op peers see the same juice.
- Text: always through `UiKit.text*` or `UiFont.px(size)`; TEXT SIZE scales 1 / 1.25 / 1.5. Dense screens cap it
  with `UiFont.max_level` (designer + launch stop at LARGE; set in _enter_tree, reset in _exit_tree).
- Icons: `sprites/ui_icons/` (8x8 + 16x16 + @4x), drawn by `draw_icons.gd` (GDScript, no Python needed):
  `Godot_console --headless --path . -s res://sprites/ui_icons/draw_icons.gd`, then open the editor to import.
  Designs are fill maps; the script adds the ink outline and bottom/right shade. White icons are tinted in game.
- Cruise HUD = corner blocks (`hud.gd`): top-left resources (`ResourceBar`), top-centre Earth->Mars progress +
  DSN / sent / lost, alert strip and toasts under it, top-right task list (`TaskList`, TAB folds; replaces the
  ticket strip), bottom-right action button (`ActionButton`, verb from `Station.action_info()`, key cap from
  `Controls.key_name`), bottom-left you (name + role colour), radio, controls hint for the first 30 s.
  Alerts (`AlertBanner`): slab slides across (icon + 2-4 words), then folds into the strip; `show_slab()` for
  new alerts (MOI, breach...). Block rects are published in `UiKit.hud` every frame; station panels move below
  the station if they would sit under one (`UiKit.hits_hud`), the event checklist stacks under the strip.
- Crew: role-coloured name tags in co-op (`CrewMember.display_name`, drawn on a z 45 child above the lighting).
- `MinigameFrame` (`scripts/ui/minigame_frame.gd`): dim backdrop, big frame in the station colour, title bar
  with icon, Q CLOSE key cap, deadline bar, footer hint + note, stamp. Full-screen games use `draw_bar`.
- New class_name files need one editor scan (or `--headless --import`) before `-s` scripts can see them.
- Not yet on the kit: the Control-based menus (main menu, level select, lobby, join, characters; `space_theme.tres`).
  Not built, so nothing to restyle: report, codex, briefing, goal line, radar minigame, HULL / O2 bars (would need
  new sim state keys: contract change, agree with Person A first).

## Cruise gameplay (decided 2026-11-14)
Overcooked loop: background pressure (battery drain, data filling, drift, DSN passes) + **tickets**
(events) that pop on a station with a countdown.
- **Docking:** walk into a station's ring (hold Shift to run), tap USE to dock. While docked, ←/→ are the station's
  choices, USE is held to work, ↑/↓ leaves. One set of 5 keys per player for any station.
- **Hold to work:** holding USE fills a progress ring (ticket `work_time`, 1–3 s); releasing resets.
  The client tracks progress and sends `resolve` when full.
- **Missed ticket → station OFFLINE** until someone docks and holds a repair (no timer). An offline
  station's normal verbs are refused by the sim. Missed science windows are just lost.
- Station verbs: Navigator ←/→ = burn (fuel + power). Engineer ←/→ = pick a load, tap USE = toggle it
  (instruments / transmitter / heater). Comms hold USE = downlink (only during a DSN pass, transmitter
  on). Scientist hold USE = observe during a science window (instruments must be on).
  A pending ticket always takes USE first.
- Score = science **downlinked** + arrival outcome + resources left. Data that overflows storage is lost.

### Contract draft (agree with Person A before building the real sim)
All plain dictionaries so they go over the network unchanged.
```gdscript
# Events.action_requested(role, action) — role = station role acting
{type = "resolve", id = 7}                 # work finished on ticket 7 (any role)
{type = "burn", dir = "left" | "right"}    # navigator
{type = "toggle_load", load = "instruments" | "transmitter" | "heater"}  # engineer
{type = "downlink", on = true | false}     # comms, while USE is held

# Events.state_changed(state)
{ day, power, fuel, data,            # 0-100 (data = storage used)
  science_sent, science_lost,
  dsn = {site = "GOLDSTONE" | "MADRID" | "CANBERRA" | "", time_left},
  loads = {instruments = true, transmitter = true, heater = false},
  offline = ["engineer", ...],       # stations knocked out by missed tickets
  events = [ {id, kind, role, title, time_left, duration, work_time, repair} ],  # time_left < 0 = no timer
  last_action, action_seq }          # HUD toast text; seq bumps on every new message
```
`scripts/game/fake_mission.gd` implements exactly this with made-up numbers until `Mission.gd` lands.

## Network co-op (in-game sync, `scripts/game/net_sync.gd`)
Rooms/lobby: `Network` autoload (`scripts/network.gd`). In the game scene, `NetSync` (at `/root/Game/NetSync`):
- **Host is the authority**: only the host runs `Mission.start/tick`. Clients forward every
  `Events.action_requested` to the host; the host re-emits state / event_started / event_ended to clients.
  So the sim never needs to know about the network — it only talks to `Events`.
- Each peer owns its crew member (`Crew_<peer id>`) and streams `[pos, facing, moving, anim, docked role, skin]`
  at 20 Hz through the host; others show it as a puppet (`CrewMember.remote`). Docking is synced, so a
  station in use by another player shows "IN USE".
- Roles by player count (sorted peer ids, host first): 1 all · 2 Nav+Eng / Comms+Sci · 3 Nav / Eng / Comms+Sci · 4 one each.
- Not yet: event rate scaling by player count (sim side), late join, host migration.
- Test on one laptop: run the game twice, host creates a room, the other joins `127.0.0.1`.

## Orbit simulation (shared by planner and cruise)
- Units AU and days; Sun fixed at origin; Earth/Mars on circles (1.0 AU / 365 d, 1.52 AU / 687 d)
  computed from time, not simulated.
- Spacecraft: position + velocity, Sun gravity only, velocity Verlet, fixed dt ≈ 0.5 day, many
  substeps per frame. Predicted path = run the same step forward ~400 days; recompute only after a burn.
- Gameplay fudges: correction burns ~10× real strength, capture zone ~0.05 AU (real SOI ~0.004).
- Teaching moments: aim where Mars *will be*; you already carry Earth's ~30 km/s; speeding up raises
  the far side of the orbit so you arrive *later*; fuel is mass.

## Paths (no single best — each mission brief should quietly favour one)
| Path | Basis | Bonus | Danger / busy role |
|---|---|---|---|
| Fast (~180 d) | high-energy transfer | earliest science, time bonus | big launch push, fast arrival → hard insertion (Nav+Eng) |
| Standard (~259 d) | minimum-energy (Hohmann) | least fuel | balanced |
| Venus flyby (longest) | gravity assist | free speed → heavier ship, bonus Venus science | heat, more solar storms, precise flyby (Eng, Nav) |
Day-1 scope: Fast + Standard. Venus needs Venus gravity in the sim → day 2.

## Events (pressure)
| Event | Real basis | Effect | Who |
|---|---|---|---|
| Solar storm | radiation hits electronics | random faults to reset; rad-hard computer reduces them | Engineer |
| Solar conjunction | Sun between Earth and craft (~every 26 months, ~2 weeks) | warning countdown → comms blackout; storage may overflow | Comms (+Sci) |
| Comet dust stream | comet debris trails | turn to shield → antenna off Earth | Nav + Comms |
| Course drift | launch error + solar wind | path slides; correction burns | Navigator |
| Thruster leak / stuck | propulsion faults | fuel drain or slow spin | Nav + Eng |
| Heat near Sun | Venus path only | overheating, radiator juggling | Engineer |
| Science opportunity | Mars dust storm, ice, moon pass | timed window; instruments cost power + storage | Scientist |

Constant chores: Deep Space Network passes (California/Spain/Australia — downlink only when in
view), eclipse cycles in Mars orbit (solar → 0, battery drains), data storage filling.

## Ship classes + parts
| Class | Upgrade slots | Mass limit | Budget left | Natural path |
|---|---|---|---|---|
| Light (silver foil) | 3 | low | most | Fast |
| Balanced (gold) | 5 | medium | medium | Standard |
| Heavy (gold + ribs) | 8 | high | least | Venus |

**Base kit (free, every class):** small solar panels, small battery, standard computer, low-gain
antenna, small propellant tank, main engine, basic thrusters, weather sensor.

**Upgrades (each uses 1 slot, costs budget + mass + power):**
- Engineer: large solar array (replaces small), RTG, large battery, radiator/heater, rad-hard computer
- Comms: high-gain dish (replaces low-gain), small recorder, large recorder, relay radio
- Navigator: large tank, star tracker, reaction wheels
- Scientist: high-res camera, spectrometer, radar sounder, thermal imager, magnetometer (boom)

The best upgrades take pressure off one crew member while adding load elsewhere
(e.g. rad-hard computer = fewer Engineer faults; large recorder = Comms survives conjunction).
Stats (mass_kg, power_w, cost) are **not balanced yet** — null in the JSON, to be tuned.

Launchers: Light / Medium / Heavy rocket (capacity vs cost). The designed thing is the
*spacecraft*; the rocket only launches it. Planned: launch-pad screen with a rocket cutaway showing
the folded spacecraft in the fairing (not drawn yet).

## Assets (generated, pixel art) — expected under `res://assets/`
- `ship/` — `ship_480x270_nocrew.png` (base map), 2×/4× versions, `ship_layout.json`
  (rooms, doors, stations with interact point + radius, obstacle rects for collision).
  Rooms: Comms, Science Lab, Bridge, Engine Room, Mission Hub (holo-table = team planning), Cargo.
- `parts/base/` — base kit: `icons/` (32×32), `mounted/`, `bodies/` (light/balanced/heavy with a
  12×12 cell grid), `previews/`, `parts_base.json` (parts, class cell grids, mount anchors).
- `parts/upgrades/` — 17 upgrades: `icons/`, `mounted/`, `frames/` (role-coloured slot frames,
  linked plates for external parts), `loadouts/` examples, `parts_upgrades.json`.
- `crew/` — `<role>/sheet.png` (16×16 frames, 8 cols × 4 rows), `portraits/` (32×32), `crew.json`.
  Feet anchor (8,15). Rows: 0 idle d/u/l/r ×2; 1 walk down 0-3, up 4-7; 2 walk left 0-3, right 4-7;
  3 work_up 0-1, work_down 2-3, alarm 4-5. Play `alarm` when an event hits that role's station.
- Every PNG has an `@4x` copy; coordinates in JSON are 1× pixels. Python generator scripts (Pillow)
  are included next to the assets if art needs tweaking.

## Godot setup
- Viewport 480×270, stretch mode `viewport`, scale mode `integer`, default texture filter Nearest.
- `.gitignore` `.godot/`; commit `.uid` files (Godot 4.4+).
- Contract between the two halves = autoloads + signals:
```gdscript
# Events.gd (signal bus — the only link between halves)
signal action_requested(role: String, action: Dictionary)   # game/UI → sim
signal state_changed(state: Dictionary)                     # sim → game/UI
signal event_started(event: Dictionary)
signal event_ended(id: String)
signal mission_finished(report: Dictionary)
# Mission.gd (sim owner): start(design), tick(dt), predict_path() -> PackedVector2Array
```

## Sound + VFX
- `Sfx` autoload (`scripts/sfx.gd`): `Sfx.play(name, pitch, db)`, `Sfx.set_loop(name, on)`. Every Button gets
  hover/click sounds automatically — menu scenes need no sound code.
- Chiptune WAVs in `sounds/`, generated by `sounds/gen_sounds.py` (stdlib only; edit + re-run).
- `scripts/game/vfx.gd`: pixel particles, alarm vignette, shake. Game sounds + effects are triggered from
  sim state diffs (`Events`), so every co-op peer sees/hears the same thing.

## Work split
- **Person A — "the brain" (scripts):** `Mission.gd`, `OrbitSim.gd` (RefCounted), `EventDirector.gd`,
  `DesignRules.gd` (mass/power/budget/slots), scoring + report data, JSON loading;
  scenes `LaunchPlanner.tscn`, `Report.tscn`; day 2: balancing numbers. Test via a console TestRunner scene.
- **Person B — "the body" (scenes):** `ShipMap.tscn` (map sprite + StaticBody2D collision from
  ship_layout.json), `Player.tscn` (CharacterBody2D + AnimatedSprite2D from crew sheets), `Station.tscn`
  (Area2D → emits action_requested), input map, `Designer.tscn`, `HUD.tscn`, effects,
  predicted path as Line2D from `predict_path()`.
- Merge rules: one owner per `.tscn`; `Main.tscn` only instances child scenes; `project.godot`
  edited only at checkpoints (B owns input map, A adds autoloads); merge to main several times a day.
- Checkpoints: (1) contract frozen → (2) player walks to station, presses key, state changes, HUD
  updates → (3) designer output flies in sim → (4) events live → (5) feature freeze, balance + demo.

## Demo script (3 min) — build everything to serve this
Pick a mission → overload instruments → fail on data downlink with the explanation → fix it two
different ways → both succeed with different scores → NASA comparison.

## Still open
- Final mission list (based on real NASA Mars missions, with end-of-game reveal) and win conditions.
- Part stats / balance numbers; event frequencies (station walking distances matter — Comms↔Bridge
  is the longest run).
- Launcher sprites and the launch-pad rocket-cutaway screen.
