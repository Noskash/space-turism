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

## Assembly hangar hub (built 2026-11-15, `scenes/design/hangar.tscn`, `scripts/design/hangar.gd`)
Flow now: level select / MissionSelect → lobby → **Hangar** → launch pad → cruise (launch "D = redesign", report and game
over also return here). The menu Designer (`designer.tscn` → `planner.tscn`) still works but nothing points at it.
- Map, collision, shelves, bay, stands, board, door: `sprites/hangar_assets/hangar_layout.json`. Crew = `CrewMember` with
  `world_actions = false` (no hull/radio). Overlay (gantry) drawn above the crew.
- SPACE at your role's shelf = pick the part up (drawn over your head); F = info card (9-slice `info_card.png`).
  SPACE on the bay installs (`DesignRules.check_add`, free cells glow in the part's role colour); SPACE next to a fitted
  part's cell takes it off (owner role only); SPACE at its shelf puts it back. A part is on its shelf when it is neither
  installed nor carried, so shelves have no state. SPACE at a class stand switches class (extra parts drop back).
- Wall board = `DesignRules.evaluate` (mass / power / budget / slots / rocket). Toast strip at the bottom shows the
  first problem or "EVERYONE TO THE LAUNCH DOOR".
- **Planner console** (`sprites/launch_planner_assets`, feet at 400,200 by the NAV rack): SPACE opens `planner.gd` in
  EMBEDDED mode as an overlay (CanvasLayer 15): NAV holder moves date (A/D) / path (W/S) / Mars orbit (SPACE), Q closes.
  Others can look. The console screen edge + tag show the plan (green / amber / red).
- **Launch door zone** = READY (lights 1-4 by sorted peer id). All READY, no design errors, plan possible →
  `LaunchWindow.apply(design, plan)` → `DesignRules.chosen` → launch.tscn. Any ship or plan change un-readies everyone.
- Co-op: host owns `{design, plan, ready_by, carried}`; actions `take / return / install / remove / class / orbit / date /
  speed / ready`; crew snapshots relayed through the host at 20 Hz. A player who leaves drops their part back on the shelf.
- New key: F = `inspect` (Controls). Tutorial id "hangar" (7 panes); MissionBriefing first, as in the designer.
- TEXT SIZE: board numbers are painted into fixed map boxes (`SIGN_PX` 6, ignore the setting); the F card is laid
  out from rows (`_card_rows`) so it grows with the text; prompts sit on a dark plate. The planner (both modes) caps
  TEXT SIZE at LARGE (`UiFont.max_level = 1`, like the designer) and its gaps grow with `_step()`.

## Launch window planner (built 2026-11-15, `scenes/launch/planner.tscn`)
Flow: Hangar planner console (overlay) → launch pad → cruise; standalone screen kept for the old Designer. SIMPLIFIED physics, labelled on screen. Maths in `LaunchWindow`
(`scripts/launch/launch_window.gd`, static); screen `scripts/launch/planner.gd`.
- Earth/Mars on circles. Mars must lead Earth by the path's ideal angle on launch day (STANDARD Hohmann 259 d,
  sweep 180° -> ~44°; FAST 180 d, sweep 150° -> ~56°, so its best day is ~25 days earlier). Earth gains 0.462°/day.
- Plan `{offset (days from the mission's best date, ±120), speed}`. Departure Δv = path Δv (2.9 / 3.8 km/s) +
  0.004 × (deg off ideal)². Rocket gives 2.9 + spare from lift margin (`rocket_spare`, max 1.2); the rest is burned
  from the SHIP's tank at 22 %/km/s. STANDARD is free within ~±20 days; ±60 d ≈ 63 %; beyond ~±70 d impossible.
- Best date = the mission's real NASA launch date (`missions.json` `launch_date`: Odyssey 2001-04-07, MRO 2005-08-12,
  MAVEN 2013-11-18); sandbox 2026-11-20 (approx. window). Screen also shows "next window +26 months".
- Screen: orbit diagram (Earth, Mars now, angle wedge, path coloured by cost, Mars on arrival + miss line),
  numbers (Δv, rocket, tank burn, brake need, tank after departure), fuel-vs-date chart (green dip = window).
- Co-op: designer pattern (host owns the plan). Only a NAV holder moves the date (A/D hold or drag the chart) / path (W/S);
  SPACE = READY for all; any change un-readies. Impossible date (cost ≥ 100%) can't be READY.
- `LaunchWindow.apply` writes `design.plan = {offset, speed, date, trip_days, dv, fuel_cost, moi_mult}`:
  fake_mission `cruise_days` = trip (cruise_seconds scaled by trip/259), start fuel = launch fuel_left − fuel_cost;
  `Orbits.moi_fuel` × moi_mult (FAST 1.4); goal line uses state.cruise_days; report explains date cost / FAST.
- No plan (tests, mission "") = old behaviour. Later: opens from the planner console in the walk-around hub
  (`sprites/launch_planner_assets`).

## Launch mini-game (built 2026-11-14, `scenes/launch/launch.tscn`)
Flow: Designer → **Launch** → cruise. ~30-45 s, SIMPLIFIED physics (labelled on screen).
- MOUSE drags a heavy throttle lever on a pivot (stays put; W/S nudge as fallback). Feel = spring to the hand + damping +
  10% notch detents + end-stop thud (`LEVER_K/DAMP/DETENT/MAX_V`); a ghost knob shows the hand while it lags.
  Co-op: throttle = AVERAGE of all players' levers.
- Pixel look: the world is drawn 1:1 into a 496x286 SubViewport (`_w`, `_draw_world`) over `shaders/launch_sky.gdshader`
  (dithered banded sky, pixel Sun, stars), shown Nearest with `shaders/launch_post.gdshader` (cruise-style light model,
  dithered: sun-side shade, vignette, engine flame + pad floodlight pools, max-Q red edges, explosion flash). Shake moves
  the view sprite in whole pixels. UI layer (text, pixel-drawn lever quadrant) stays crisp.
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
- PLAYTEST: "SKIP LAUNCH [F2]" button (top right, host/offline) -> cruise with full tank, no damage.
- Staging window: after stage 1 burnout, SPACE within 6 s (`STAGE_WINDOW`; beeps speed up after 75%). Missed ->
  rocket falls back, parachute at 3 km, lands -> **launch failed** (same SPACE / D options).
- Never passing the LIFT mark until stage 1 is empty = **"NOT ENOUGH THRUST - NEVER LEFT THE PAD"** (own failure).
- **Failure report** (`scripts/launch/launch_report.gd`, `LaunchReport`): the host records the flight (`flight.time, thrust_dv,
  gravity_dv, pad_fuel, thr_sum/powered_time, peak_q(+alt/speed/thr), meco_alt/speed, max_alt/speed/thr` + a `[t, alt, speed, q,
  throttle]` log); `_fail` packs `flight.report` (<= 40 samples) so every peer draws it. Fades in 1.4 s after the failure:
  graph (q vs LIMIT / speed vs ORBIT / altitude with STAGE 1 EMPTY / throttle vs LIFT), WHAT HAPPENED (this flight's numbers),
  THE PHYSICS (dynamic pressure / rocket equation + gravity loss / dead mass / thrust-to-weight), HOW TO FIX IT (picked from
  pad fuel, average throttle, coasting, lift margin), REAL (Shuttle 65-72% throttle bucket; rockets ~85-90% fuel; LEO needs
  ~9.4 km/s for 7.8 km/s). Codex: `dynamic_pressure`, `rocket_equation`, `gravity_loss`, `thrust_to_weight`.

## Space weather (built 2026-11-15, in `fake_mission.gd`; port to Mission.gd later)
- **Solar radiation storm** (solar particle event): first ~24 s, then every 42-58 s. Warning (siren + banner):
  9 s from the base-kit weather sensor, 16 s with the **solar particle monitor** (SCI upgrade, `cme_warning: 7`).
  What the crew can do depends on the design:
  - **Radiation shielding bought** (PWR upgrade, 50 kg, `shields: 1`): ticket kind "shields", role "team"
    (Mission Hub holo-table, anyone). SPACE opens `ShieldGame` (`scripts/game/minigames/shield_game.gd`): a needle
    sweeps a gauge, SPACE in the green zone charges a capacitor (3; rad-hard CPU -> 2; each charge = faster
    needle, smaller zone; miss = 0.4 s lockout). SPACE read in `_input`; a press counts if the needle was in
    the zone within the last 0.1 s (`GRACE`, covers render/display lag). Success -> `cme.shields = true` (bubble around the hull) ->
    wave is harmless + bonus storm science.
  - **No shielding**: ticket kind "safe_mode", role "engineer". SPACE opens `SafeModeGame`
    (`minigames/safe_mode_game.gd`): a row of breakers, cut the blinking one each time (A/D move, SPACE flip;
    random order; wrong one = 0.5 s lockout; 4 breakers, rad-hard CPU -> 3) -> `cme.safe = true`: all loads off
    and locked until the wave has passed (no science, no downlink), but no damage.
  - After safe mode or a blackout: engineer ticket **"power_up"** (20 s × pace, hold 2 s) = instruments + transmitter
    back ON in one go (real: one safe-mode recovery sequence). Missed = nothing breaks, loads stay off (switch by hand;
    doing that also clears the ticket). Comms panel says "TRANSMITTER OFF" and the sim warns when the recorder is >70%
    with the transmitter off.
  - Neither done when the wave (6 s) hits = **ship disabled**: blackout 10 s (solar bus tripped, loads off,
    -15% battery; only `storm_proof_w` = RTG still generates), Engine room + one random station offline.
    35% chance (`METEOR_CHANCE`) a meteoroid hits during the blackout (`state.meteor {time_left, y, seq}`): shown
    flying in for 2.5 s (proximity alarm, banner), then crash = flash, heavy shake, crunch sounds, debris; -6% fuel,
    -5% battery, one more station offline.
- **Comet debris** (real: comet trails; hard rule #3 kept, it is labelled comet debris): first ~50 s, then every
  45-60 s. Warning 12 s (+4 star tracker). **Bridge radar** (`scripts/game/radar_screen.gd`, E toggles it while
  docked at the Bridge; E is no longer an interact key): the cloud closes in ahead, dotted projected path. A/D = course burn (fuel, 5 degrees each; cloud half-width 0.3 so 1-2 burns clear it; the cloud is on the
  scope for the whole warning with its extent band + the ship's corridor drawn,
  `dust.course` vs `dust.cloud_y/cloud_w`). The choice: burn fuel now and steer clear (cloud passes, no risk), or
  save it and fly through. Partly clear = `dust.density` 0.3..1 (thinner field, fewer unpiloted hits).
  Then phase "stream" waits up to 8 s for a pilot. The Navigator docked
  at the Bridge gets `DodgeGame` (`minigames/dodge_game.gd`): FULL SCREEN, Spacewar-style (A/D turn, W thrust,
  S brake, screen wraps, no guns), 6 s, rocks fly in from the edges faster and faster. Ship MASS from the design sets
  the feel (light = quick + small, heavy = sluggish, bigger, knocked around less); hull % shown. Runs on the pilot's
  machine: `dodge_start` -> phase "flying" -> `dodge_result {hits, thrust, turning}`. No pilot = 3 hits.
  Each hit: random station offline or -8% fuel. Reaction wheels: faster turning, turning costs no fuel.
  Star tracker: earlier warning + red edge chevrons before rocks fly in. While flying, no downlink.
- **Hull + oxygen** (`fake_mission` `_impact`, `scripts/game/hull_damage.gd`): every debris / meteoroid hit wears
  `state.hull` (damage per hit = class `hull_hit`: light 16 / balanced 12 / heavy 9; Whipple shield (NAV part) halves
  it and cuts breaches). Breach chance per hit = 0.15 + 0.8 x wear. A breach = hole on the map venting air
  (`state.breaches [{id,x,y}]`); each drains O2 1.4 %/s, sealed ship refills 0.6 %/s. Toolboxes: red lockers in Cargo
  (386,240) + Engine Room (132,226), SPACE take/return (synced in the crew snapshot); SPACE anywhere else drops it
  on the floor (`state.toolboxes`, actions drop_tool / take_tool), anyone picks it up; HOLD SPACE on a hole 2.5 s ->
  `{type = "patch", id}` (+3 hull). O2 0 -> `state.lost` -> the ship explodes (Vfx chain of blasts, 2.6 s), then
  `GameOver` (`scripts/game/game_over.gd`) grabs the frame, breaks it into shards drifting apart, then the panel.
  HUD: HULL + O2 bars under the tickets.
- Minigames are CanvasLayers (layer 15) that call `Tutorial.hold()` so crew/station input is off meanwhile.
  They share one look (`MinigameFrame`, see UI kit). Q (Controls "leave") closes shields / safe mode on that machine only (the
  ticket stays, anyone can reopen it); the dodge game has no close (it would have to report a result).
- State: `cme {phase, time_left, duration, shielding, shields, safe}`, `blackout`,
  `dust {phase, time_left, hits, wheels, tracker}`.
- Part effects (data/design_stats.json): rad_shielding `shields`, particle_monitor `cme_warning`, rtg
  `storm_proof_w`, computer_radhard `cme_tasks: -1` (= one fewer shield charge), star_tracker `dust_warning: 4`,
  reaction_wheels `steer_free: 1` -> `DesignRules.mission_params`. New part art: `draw_upgrades.py` (19 upgrades).
- Visuals: HUD banner, wave band sweeping from the Sun, blackout darkness, shield bubble, debris grains
  outside the hull, hull impact sparks; sounds siren / wave / impact / static.

## Mars campaign (built 2026-11-15) — framing A: a future crewed NASA mission re-flying real robot missions
Flow: level select → **Mars card** (`LevelData.has_missions`) → **MissionSelect** (`scenes/mission_select.tscn`, all open,
best stars) → room created with a LevelData copy whose `mission` id is set (synced to every peer in the room info) →
lobby → designer (**MissionBriefing** first, once per mission) → launch → cruise → **MOI** → **MissionReport**.
- `data/missions.json` (numbers = first guesses, a perfect bot gets 3 stars; tune with humans), read by `Missions`
  (`scripts/missions.gd`, static: `current_id()`, `sim()`, `goals(state)`, `stars`, best stars in `user://campaign.cfg`).
  No mission id = sandbox (every hazard on, endless cruise) — tests rely on it.
  | # | Mission (NASA) | Goals (1 star each) | Hazards / twist | Off |
  |---|---|---|---|---|
  | 1 | Radiation Scout (Mars Odyssey 2001, MARIE) | record 3 storms · send 40 · orbit | storms every ~20 s, Halloween-class storm at 70% | debris, hull |
  | 2 | Data Firehose (MRO 2005, HiRISE) | send 120 · lose < 25 · orbit | 2.4× science windows, solar conjunction at 62% | hull |
  | 3 | Thin Air (MAVEN 2013) | record 2 storms · send 80 · orbit | everything incl. breaches + O2 | — |
- Sim (`fake_mission.gd`): `_sim` flags `storms / debris / hull`, `storm_first/gap`, `debris_first/gap`, `science_weight`,
  `fault_weight`, `big_storm_at`, `conjunction_at`, `moi_fuel`; cruise length = `cruise_days` over `cruise_seconds`.
  State adds `mission, cruise_days, storms_recorded, conjunction{phase,time_left}, moi{phase}, finished{outcome,stars,...},
  stats{storms, safe_modes, disabled, knockouts, debris_hits, breaches, big_storm, fuel_at_moi}`.
  - **Storm reading** = instruments ON + lab online as the wave hits. Safe mode turns them off (safe, no reading);
    no shielding + no safe mode = reading but the ship is disabled; shielding = both. That is the Odyssey lesson.
  - **Halloween storm**: +6 s warning, 1.5× wave, +1 breaker/charge; unprotected also fries the Science Lab (like MARIE).
  - **Solar conjunction**: 15 s warning, then 16 s with no DSN/downlink (SIMPLIFIED, really ~2 weeks).
  - **MOI**: at `cruise_days` (day stops there) a navigator ticket `moi` (22 s, hold 4 s). Needs ≥10% battery (else refused,
    ticket stays) and `moi_fuel` (else flyby). Timer runs out = miss. No new hazards after 92% of the cruise.
  - Hull off: `_impact` never breaches, no O2 tick, lockers hidden (`HullDamage.enabled()`), HULL/O2 bars hidden.
- HUD: goal line under the top bar (`GOALS [x] STORMS 1/3 [ ] SENT 12/40 [ ] MARS: DAY 80/200`), toast moved to y 46 with
  a dark strip; banners for MOI and conjunction. `ShipLighting.progress_of(state)` uses the mission's cruise length.
- **Score** (`Missions.score`): 100 per star + 2 per unit of **BONUS DATA** (science sent beyond the SENT goal; counts on
  flyby/miss too, lost ship = 0). Goal line shows "SENT 40/40 +12 BONUS"; report shows SCORE + NEW BEST; best score
  in `campaign.cfg [score]`, shown as "N PTS" on the mission picker cards.
- Storm minigames report success the instant the last charge/breaker lands (the 0.8 s outro is cosmetic), and their
  countdown is resynced from the ticket on every state update.
- **MissionReport** (`scripts/game/mission_report.gd`): result + stars + goals + "why it went this way" (from stats) →
  "What NASA actually did" card (+ Mars Climate Orbiter card after a miss/flyby). Host: SPACE fly again (RPC to all),
  M other mission, ESC menu.
- **Codex** (`scripts/ui/codex.gd`, `data/codex.json`, 26 terms): J or ESC menu → CODEX. Terms unlock from briefing pages,
  first events (`EventGuide.TERMS`) and the report; NEW markers; `user://codex.cfg`. Attached by `PauseMenu.attach`.
- **Briefing** (`scripts/ui/briefing.gd`): pages from the JSON ("GOALS" body = generated goal list), ESC menu
  MISSION BRIEFING reopens it. EventGuide gained `conjunction` and `moi` walkthroughs.
- Facts on screen were checked against NASA/JPL sources (dates, MARIE Oct 28 2003, MRO 3 m dish / HiRISE ~1 m, MAVEN
  ~100 g/s, MCO unit mix-up ~$125M orbiter). Keep new facts sourced.

## Sandbox (built 2026-11-15) — NASA brief: "a sandbox mode to experiment without predefined constraints"
- 4th card on MissionSelect (cards now 110 px wide). `missions.json` top-level `"sandbox"` (not in `order`; `Missions.SANDBOX`,
  `Missions.mission("sandbox")`): `budget_mult` 2 (DesignRules.evaluate budget), no goals/stars, cruise 259 d -> MOI -> report,
  one briefing page, NASA card = trade studies (Mission Design Lab).
- Hazard switches on the card (W/S + SPACE, or click; ENTER / FLY row = go): storms, debris, hull+O2 (default off), conjunction.
  Stored in `Missions.offline_options` -> `LevelData.options` (room info, synced) -> `Missions.sim()` lays them over the sandbox
  block (`fake_mission.start` now reads `Missions.sim()`). Report: "SANDBOX REPORT", HAZARDS FLOWN instead of goals, score =
  ALL data sent (`bonus_data` with no SENT goal) + orbit + healthy crew.
- `Missions.current_id()` in a room now always returns the room's mission (was: fell back to a stale `offline_id` when "").
  The old mission id "" (endless cruise, every hazard) still exists for tests.

## Mars orbit choice (built 2026-11-15) — NASA brief: "several orbital options and explain them"
- Designer SHIP column row "Orbit: X" (shared, SPACE cycles, un-readies everyone) -> `design.orbit`
  (`DesignRules.set_orbit`, host action `{type = "orbit", id}`). Data `data/orbits.json`, logic `Orbits` (`scripts/orbits.gd`, static).
  | Orbit | Brake fuel | Science | Earth contact | Drag (fuel %/Mars yr) | Catch |
  |---|---|---|---|---|---|
  | LOW POLAR | x1.5 | x1.5 | x0.6 | 8 | big brake, downlink-starved without a dish |
  | HIGH ELLIPTICAL (default) | x0.7 | x0.6 | x1.4 | 2 | little science, long life |
  | AEROBRAKE | x0.8 | x1.5 | x0.6 | 8 | 0.6 Mars yr wait (radiator -0.25, large solar -0.15) |
- MOI need = `Orbits.moi_fuel(design)` = mission `moi_fuel` x orbit x `moi_mult` (large tank 0.5). Shown in the designer stats.
- After the game ends in orbit: `Orbits.result(state)` (SIMPLIFIED) = lifetime (fuel left / drag, max 3 Mars yrs, minus aerobrake
  wait) x min(observed/yr = science x 2 x orbit x mission fit 1.3 x power-starved 0.7, radio/yr = downlink x contact x 5 x recorder).
  Report page **IN MARS ORBIT** (lifetime bar, observed vs radio bars, bottleneck, why). 1 point per unit (`finished.orbit_science`).
- Each mission's `favoured_orbit` (Odyssey/MRO low, MAVEN elliptical) + an orbit tip in its Design tips page; Codex
  `polar_orbit`, `elliptical_orbit`, `aerobraking`. Facts: Odyssey 77 days / 332 passes to ~400 km; MRO ~5 months; MAVEN 150 x 6,200 km.

## Astronauts + radiation dose (built 2026-11-15)
- `data/astronauts.json` + `Astronauts` (`scripts/astronauts.gd`): fictional astronauts, one per role (Kai Okafor NAV,
  Mira Petrova PWR, Tomas Reyes COM, Dr. Lena Sato SCI; solo = Commander Sam Hale). Crew role -> astronaut
  (`id_for_role`, first role of a split). The main-menu characters screen now shows this roster.
- Sim: `state.crew[key] = {astronaut, dose, sick, room}`, key = crew node name ("P1" / "Crew_<peer>"). The game (host)
  calls `set_crew(roster)` after start and writes `crew_rooms` (via `ShipMap.room_at`) every frame; the sim can't see the map.
- Dose (SIMPLIFIED, sourced): 1.8 mSv per cruise day (Curiosity RAD); storm wave: shields up or in **Cargo (storm
  shelter, like Orion)** = +10, outside = +150 (Halloween +250). >= 500 = radiation sickness: walk + station work x0.75
  (`CrewMember.sick`, set on every peer from state). NASA career limit 600 mSv shown on bars.
- No shielding = storm warning +6 s (`SHELTER_EXTRA_WARN`) so the Engineer can do safe mode AND everyone reach Cargo.
  Banner "EVERYONE TO CARGO", `CrewPanel` (bottom left: dose bars, SHELTER/OUTSIDE during the warning), safe-mode
  walkthrough has a shelter pane + step.
- Cascade: a debris hit that breaches nothing has a 30% chance (`LEAK_CHANCE`) of a `fuel_leak` navigator ticket with no
  timer, draining 0.45 %/s until sealed (hold 2.5 s) -> can turn the Mars brake burn into a flyby. Report explains it.
- Score adds +50 per astronaut without sickness (`Missions.HEALTHY_POINTS`); report has a CREW page (doses vs 600 mSv).
- Codex: `radiation_dose`, `storm_shelter`. Odyssey briefing ties MARIE to the crew's dose bars.
- Bot runs (Odyssey): sheltered crew ends ~390-400 mSv (healthy); always outside = sick after the 2nd-3rd storm.
- Game user data lives in `%APPDATA%/Godot/app_userdata/Space turism/` (project name), not `space_dick/`.

## Radio (`scripts/game/radio_set.gd` object + `scripts/game/radio.gd` audio)
- A boombox on the Mission Hub bench (RadioSet, use point 308,158). Walk up, SPACE = on/off
  (CrewMember sends `{type = "radio"}`; sim keeps `state.radio = {on, track}`, so co-op peers hear the same radio;
  switching on tunes to the next track). Notes float up while it plays.
- 5 CC0 jazz tracks from OpenGameArt in `music/` (authors in `music/CREDITS.md`), on a "Music" bus (ESC menu
  MUSIC level, saved). Dies in a blackout, static during a radiation wave.

## ESC menu (`scripts/ui/pause_menu.gd`, class `PauseMenu`)
- `PauseMenu.attach(scene, leave_text, controls_text)` on designer / launch / cruise: RESUME, BRIEFING + CODEX (campaign),
  HOW TO PLAY, SOUND (Master bus, saved in `user://settings.cfg`), MUSIC, TEXT SIZE (NORMAL / LARGE ×1.15 / HUGE ×1.3,
  `UiFont`), FULLSCREEN, LEAVE (press twice), QUIT (press twice). The footer lists the screen's controls (`controls_text`).
  Rows squeeze to fit 270 px at big text sizes.
- TEXT SIZE: every `draw_string` size goes through `UiFont.px(size)` (capped per screen by `UiFont.max_level`);
  `UiFont.width(text, base_size)` and `UiFont.label()` scale too (labels resize live via group `ui_font_label`).
  New hand-drawn text must use `UiFont.px()` for the size (or `UiKit.text*`, which does).
- Alone (offline or the only player in a room) the whole game pauses (tree, sound loops, radio). With 2+ players
  it pauses only when EVERY player has the menu open (host counts via RPC on PauseMenu, tells everyone);
  until then the mission runs and only local input is blocked (`Tutorial.hold()`). Tutorial + PauseMenu + Sfx run with PROCESS_MODE_ALWAYS.

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
  host's open dialog pauses the sim. Pane highlights use `UiKit.hud_rect(...)`, not fixed numbers. Priority:
  storm/debris (3) > hull breach (2) > the rest (1); a new unseen event cuts a lower or equal rank-1 walkthrough, so
  first encounters are not missed.

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
- Text: always through `UiKit.text*` or `UiFont.px(size)`; TEXT SIZE scales 1 / 1.15 / 1.3. Dense screens cap it
  with `UiFont.max_level` (designer + launch stop at LARGE; set in _enter_tree, reset in _exit_tree).
- Icons: `sprites/ui_icons/` (8x8 + 16x16 + @4x), drawn by `draw_icons.gd` (GDScript, no Python needed):
  `Godot_console --headless --path . -s res://sprites/ui_icons/draw_icons.gd`, then open the editor to import.
  Designs are fill maps; the script adds the ink outline and bottom/right shade. White icons are tinted in game.
- Cruise HUD = corner blocks (`hud.gd`): top-left resources (`ResourceBar`; + HULL / O2 when `Missions.sim().hull`),
  top-centre Earth->Mars progress + DSN / stored / sent / lost + mission goals (`UiKit.hud.goals`),
  alert strip and toasts under it, top-right task list (`TaskList`, TAB folds; replaces the
  ticket strip), bottom-right action button (`ActionButton`, verb from `Station.action_info()`, key cap from
  `Controls.key_name`), bottom-left you (name + role colour), radio, controls hint for the first 30 s.
  Alerts (`AlertBanner`): slab slides across (icon + 2-4 words), then folds into the strip; `show_slab()` for
  other alerts (MOI, oxygen, meteoroid, breach and conjunction are built in). Block rects are published in `UiKit.hud` every frame; station panels move below
  the station if they would sit under one (`UiKit.hits_hud`), the event checklist stacks under the strip.
- Crew: role-coloured name tags in co-op (`CrewMember.display_name`, drawn on a z 45 child above the lighting).
- `MinigameFrame` (`scripts/ui/minigame_frame.gd`): dim backdrop, big frame in the station colour, title bar
  with icon, Q CLOSE key cap, deadline bar, footer hint + note, stamp. Full-screen games use `draw_bar`.
- New class_name files need one editor scan (or `--headless --import`) before `-s` scripts can see them.
- Not yet on the kit: the Control-based menus (main menu, level select, lobby, join, characters; `space_theme.tres`).
  Still in the older flat look (work, just not on the kit yet): mission report, codex, briefing, mission select,
  launch report, game over, radar screen, crew dose panel (`CrewPanel`, bottom left above the "you" block).

## Cruise gameplay (decided 2026-11-14)
Overcooked loop: background pressure (battery drain, data filling, drift, DSN passes) + **tickets**
(events) that pop on a station with a countdown.
- **Docking:** walk into a station's ring (hold Shift to run), tap USE to dock. While docked, ←/→ are the station's
  choices, USE is held to work, **Q** (or ↑/↓) leaves. Q also closes the tutorial / event dialogs, briefing, Codex,
  ESC menu, and steps out of the shield / safe-mode minigames without failing (the ticket stays).
- Shields up (`cme.shields`) block the downlink until the storm passes (SIMPLIFIED) - a shields-vs-data trade-off. One set of 5 keys per player for any station.
- **Hold to work:** holding USE fills a progress ring (ticket `work_time`, 1–3 s); releasing resets.
  The client tracks progress and sends `resolve` when full.
- **Missed ticket → station OFFLINE** until someone docks and holds a repair (no timer). An offline
  station's normal verbs are refused by the sim. Missed science windows are just lost.
- Station verbs: Navigator ←/→ = burn (fuel + power). Engineer ←/→ = pick a load, tap USE = toggle it
  (instruments / transmitter / heater). Comms hold USE = downlink (only during a DSN pass, transmitter
  on). Scientist hold USE = observe during a science window (instruments must be on).
  A pending ticket always takes USE first.
- Score = science **downlinked** + arrival outcome + resources left. Data that overflows storage is lost.
- **Science loop (made visible 2026-11-15):** observation (science window, instruments ON) -> recorder
  (`state.science_stored` = DATA bar) -> Comms downlinks in a DSN pass -> `science_sent` (= score). A full
  recorder loses new science (`science_lost`). HUD: "STORED / SENT / LOST"; toasts say "+N stored", "STORAGE FULL -
  LOST", or warn when a window opens with instruments OFF / storage full; floating "+N SCIENCE", "+N SENT HOME",
  "-N LOST" (Vfx). `state.observations` counts captured windows (the walkthrough uses it for its outcome).

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
- Event pace by player count (`fake_mission` PACE / TICKET_PACE, index = players): 1 = x1.35 storm/debris gaps, ticket
  timers and cruise length, tickets every ~10-16 s; 2 = x1.2 / ~8-13 s; 3 = x1.1; 4 = x1, tickets every 6-10 s.
- Not yet: late join, host migration.
- Test on one laptop: run the game twice, host creates a room, the other joins `127.0.0.1`.

### Online co-op (built 2026-11-15) — room codes through a relay on Railway
- Railway has no UDP and home routers block ENet, so internet play goes through `relay/server.js` (Node + `ws`,
  `relay/README.md`: protocol, deploy, `npm test`). The relay only hands out 4-letter codes (no I/O) and forwards
  bytes; the host's game stays the authority.
- Godot: `RelayPeer` (`scripts/net/relay_peer.gd`, a `MultiplayerPeerExtension` over `WebSocketPeer`). Host = id 1,
  clients 2, 3, ...; clients only send to the host, Godot's server relay does client <-> client. **No RPC code changed.**
  Everything arrives reliable + ordered (TCP), including `unreliable_ordered` RPCs.
- `Network.online` (default true): `create_room` makes a relay room, the code arrives later (`code_received`,
  `Network.room_code`). Lobby shows the code, plus a host-only button to switch to LOCAL IP (ENet) while alone.
  `join_room(text)`: 4 letters = code, anything else = IP as before. Relay errors -> Russian texts (`RELAY_ERRORS`).
- `Network.RELAY_URL` = `wss://space-turism-relay-production.up.railway.app` (Railway project space-turism-relay, deployed
  with `railway up` from `relay/`; redeploy the same way after changing server.js);
  `--relay=ws://...` on the command line overrides it. Local test: `cd relay && npm start`, run the game twice with
  `--relay=ws://127.0.0.1:8080`, host -> code -> join.

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
- `sprites/launch_planner_assets/` — launch window planner console for the (planned) walk-around design hub:
  48×48 sheet (idle / highlight / offline), `planner.json` (anchor, interact point, obstacle, screen rect),
  previews in the current Mission Hub. Generator `draw_planner.py`. Asset only — not placed in any scene yet.
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

## Next up (agreed 2026-11-15, in this order unless we re-plan)
Gameplay picks (real crew/mission problems):
1. **Solar power fades with distance** — sim solar output x 1/r² (100% -> ~43% at Mars); lighting already shows it,
   fake_mission does not. ~1 h.
2. **Team page and mission phases report** — MissionReport TEAM page (who did what, unattended stations, handoffs)
   + per-phase breakdown design -> launch -> cruise -> MOI -> orbit (NASA brief: collaboration, post-mission analysis).
3. **Backup B-side redundancy upgrade** — new upgrade (mass + power): a broken station switches to its backup with
   a short hold instead of a long repair, once (real probes carry A/B computers, IMUs, wheels).

Planning picks (NASA brief: "mission planning", "launch planning", "mission timeline", "end-of-mission planning"):
4. **Launch window planner** — DONE (logic + screen, see section above; hub console art ready, not placed). Was: the missing phase 2: pick the launch date, dotted transfer path + ghost Mars,
   date sets Δv / fuel left / trip time (Mars windows every ~26 months). Needs the orbit sim (`predict_path()` is a stub).
5. **Mission timeline on the holo-table** — team places plan blocks on day 0..259 (correction burns, pre-conjunction
   recording, drain recorder before MOI); they become scheduled tickets; report PLAN vs ACTUAL. Makes PLAN a real role.
6. **End-of-mission orbit disposal planning** — keep fuel to raise the orbit at end of life (planetary protection);
   plugs into the orbit lifetime calculation.

Not now: crew fatigue/stamina (one bar too many). Later candidates: light-time delay messages, CO2 scrubbers,
exercise station, playable orbit phase with rover relay, data compression, Mars dust storm.
Facts for any of these must be checked against NASA/JPL sources before they go on screen.

## Still open
- Mission balance with real players (targets in data/missions.json); Russian level-select cards vs English game text.
- Part stats / balance numbers; event frequencies (station walking distances matter — Comms↔Bridge
  is the longest run).
- Launcher sprites and the launch-pad rocket-cutaway screen.
