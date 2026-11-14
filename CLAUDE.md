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
