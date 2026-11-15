class_name Missions
extends RefCounted
## The Mars campaign: three short missions based on real NASA missions (data/missions.json),
## flown as a future crewed mission (the report compares with what the real robot did).
##
## Which mission is flown: the room's LevelData.mission (synced to every co-op peer with the room
## info), or `offline_id` when playing without a room. "" = sandbox (no goals, endless cruise,
## every hazard on) - the old behaviour, still used by tests.
## Goals are evaluated from the sim state only, so the HUD, the walkthroughs and the report agree
## on every peer. Best stars per mission are saved in user://campaign.cfg.

const PATH := "res://data/missions.json"
const SAVE := "user://campaign.cfg"

const SANDBOX := "sandbox"         # missions.json "sandbox": double budget, no goals, hazard switches

static var offline_id := ""
static var offline_options := {storms = true, debris = true, hull = false, conjunction = true}
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {missions = {}, order = []}
	return _data


static func order() -> Array:
	return data().get("order", [])


static func mission(id: String) -> Dictionary:
	if id == SANDBOX:
		return data().get("sandbox", {})
	return data().missions.get(id, {})


## In a room the room's mission decides (even "": a level without missions) - never a stale offline_id.
static func current_id() -> String:
	if Network.is_in_room() and Network.level:
		return Network.level.mission
	return offline_id


static func current() -> Dictionary:
	return mission(current_id())


static func failure_card() -> Dictionary:
	return data().get("failure_card", {})


## Sim settings of the current mission (empty = defaults in fake_mission). The SANDBOX mission lays the
## hazard switches from the mission picker over its own block (room info, so every peer agrees).
static func sim() -> Dictionary:
	var s: Dictionary = current().get("sim", {})
	if current_id() != SANDBOX:
		return s
	s = s.duplicate()
	var o := sandbox_options()
	s.storms = bool(o.get("storms", true))
	s.debris = bool(o.get("debris", true))
	s.hull = bool(o.get("hull", false))
	if not bool(o.get("conjunction", true)):
		s.conjunction_at = -1
	return s


static func sandbox_options() -> Dictionary:
	if Network.is_in_room() and Network.level and not Network.level.options.is_empty():
		return Network.level.options
	return offline_options


# --- goals ------------------------------------------------------------------------------------

static func goal_text(goal: Dictionary) -> String:
	var text := str(goal.get("text", ""))
	return text % int(goal.get("target", 0)) if "%d" in text else text


## {done, short} for one goal against the current sim state. Orbit only counts once the brake
## burn succeeded; "lose less than" stays done until the limit is crossed.
static func goal_progress(goal: Dictionary, state: Dictionary) -> Dictionary:
	var target := int(goal.get("target", 0))
	var outcome := str(state.get("finished", {}).get("outcome", ""))
	match str(goal.get("kind", "")):
		"storms_recorded":
			var n := int(state.get("storms_recorded", 0))
			return {done = n >= target, short = "STORMS %d/%d" % [mini(n, target), target]}
		"science_sent":
			var n := int(state.get("science_sent", 0))
			if n > target:   # past the goal: the rest is BONUS DATA (extra points)
				return {done = true, short = "SENT %d/%d +%d BONUS" % [target, target, n - target]}
			return {done = n >= target, short = "SENT %d/%d" % [n, target]}
		"science_lost_max":
			var n := int(state.get("science_lost", 0))
			return {done = n < target, short = "LOST %d (<%d)" % [n, target]}
		"orbit":
			var days := int(state.get("cruise_days", current().get("cruise_days", 0)))   # planner may change it
			var short := "MARS: DAY %d/%d" % [mini(int(state.get("day", 0)), days), days]
			if state.get("moi", {}).get("phase", "") == "window":
				short = "MOI: BRAKE NOW!"
			elif outcome != "":
				short = "ORBIT" if outcome == "orbit" else outcome.to_upper()
			return {done = outcome == "orbit", short = short}
	return {done = false, short = ""}


static func goals(state: Dictionary) -> Array:
	var out := []
	for g: Dictionary in current().get("goals", []):
		var p := goal_progress(g, state)
		p.text = goal_text(g)
		p.kind = g.kind
		out.append(p)
	return out


## 1 star per goal met (lost ship = 0).
static func stars(state: Dictionary) -> int:
	if str(state.get("lost", "")) != "":
		return 0
	var n := 0
	for g: Dictionary in goals(state):
		n += 1 if g.done else 0
	return n


## Points: STAR_POINTS per star + BONUS_POINTS per unit of science sent beyond the mission's SENT
## goal + HEALTHY_POINTS per astronaut without radiation sickness. Sent data still reaches Earth on a
## flyby / miss, so it counts there too; a lost ship scores 0.
## Hard rule 4: points only come from the mission outcome - sent science is part of it.
const STAR_POINTS := 100
const BONUS_POINTS := 2
const HEALTHY_POINTS := 50   # per astronaut who reaches the end without radiation sickness

static func bonus_data(state: Dictionary) -> int:
	var target := 0
	for g: Dictionary in current().get("goals", []):
		if g.get("kind", "") == "science_sent":
			target = int(g.get("target", 0))
	if target <= 0 and current().get("goals", []).is_empty() and current_id() != "":
		return int(state.get("science_sent", 0))   # sandbox: no SENT goal, all of it counts
	return maxi(int(state.get("science_sent", 0)) - target, 0) if target > 0 else 0


static func score(state: Dictionary) -> int:
	if str(state.get("lost", "")) != "":
		return 0
	return stars(state) * STAR_POINTS + bonus_data(state) * BONUS_POINTS + healthy_crew(state) * HEALTHY_POINTS \
			+ Orbits.points(state)   # science sent home from Mars orbit after the brake burn (0 unless in orbit)


## Astronauts without radiation sickness (state.crew from the sim).
static func healthy_crew(state: Dictionary) -> int:
	var n := 0
	for key: String in state.get("crew", {}):
		n += 0 if state.crew[key].get("sick", false) else 1
	return n


static func best_score(id: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return int(cfg.get_value("score", id, 0))


## Saves a new best; returns true if it was one.
static func save_score(id: String, points: int) -> bool:
	if id == "" or points <= best_score(id):
		return false
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("score", id, points)
	cfg.save(SAVE)
	return true


static func best_stars(id: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return int(cfg.get_value("stars", id, 0))


static func save_stars(id: String, n: int) -> void:
	if id == "" or n <= best_stars(id):
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("stars", id, n)
	cfg.save(SAVE)
