class_name Orbits
extends RefCounted
## The Mars orbit the crew picks in the designer (data/orbits.json): low polar, high elliptical or
## aerobrake. It decides two things:
##   1. how much fuel the Mars Orbit Insertion brake needs (moi_fuel), and
##   2. what the ship achieves AFTER the game's cruise ends: the report's "IN MARS ORBIT" page
##      (result), which counts toward the score. Lifetime there = fuel left / the orbit's drag.
## No single best orbit: low = most science but a big brake and short contact with Earth;
## elliptical = cheap brake, long contact, little science; aerobrake = low-orbit science for a
## small brake, paid for in months of lifetime. Pure functions of the design / sim state, so every
## co-op peer computes the same numbers. SIMPLIFIED (labelled on screen).

const PATH := "res://data/orbits.json"
const MAX_YEARS := 3.0          # primary + extended mission, in Mars years (1 Mars year = 687 days)
const MONTHS_PER_YEAR := 22.6   # Earth months in a Mars year
const OBS_PER_YEAR := 2.0       # observations a year in orbit (x params.science per observation)
const CONTACT_K := 5.0          # data sent a year = downlink_rate x contact_mult x this x recorder bonus
# Tuned so orbit science is worth ~1-2 stars (36-200 points), not more than the whole cruise.
const FAVOURED := 1.3           # the mission's science suits this kind of orbit
const POWER_STARVED := 0.7      # negative power budget: the battery runs flat in Mars' shadow
const ORBIT_POINTS := 1         # score per unit of science sent home from orbit

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {order = [], orbits = {}, parts = {}, default = ""}
	return _data


static func order() -> Array:
	return data().get("order", [])


static func default_id() -> String:
	return str(data().get("default", "elliptical"))


static func info(id: String) -> Dictionary:
	return data().orbits.get(id, data().orbits.get(default_id(), {}))


## The design's orbit id (old designs without one get the default).
static func id_of(design: Dictionary) -> String:
	var id := str(design.get("orbit", ""))
	return id if data().orbits.has(id) else default_id()


static func next_id(id: String) -> String:
	var ids := order()
	return ids[(ids.find(id) + 1) % ids.size()] if ids.size() > 0 else id


## Fuel % the brake burn needs: the mission's base x the orbit x the design (large tank = smaller share).
static func moi_fuel(design: Dictionary) -> float:
	var base := float(Missions.sim().get("moi_fuel", 15.0))
	return base * float(info(id_of(design)).get("moi_mult", 1.0)) * float(DesignRules.mission_params(design).get("moi_mult", 1.0))


## Does the current mission's science suit this orbit? (missions.json "favoured_orbit" = low | elliptical)
static func favoured(id: String) -> bool:
	return str(Missions.current().get("favoured_orbit", "")) == str(info(id).get("final", ""))


## Months before science starts (aerobraking), after the parts that speed it up.
static func delay_years(design: Dictionary) -> float:
	var id := id_of(design)
	var years := float(info(id).get("delay_years", 0.0))
	if years <= 0.0:
		return 0.0
	for part: String in design.get("upgrades", []):
		years += float(data().parts.get(part, {}).get("delay_years", 0.0))
	return maxf(years, 0.1)


## What the ship does in Mars orbit after the brake burn (the report's IN MARS ORBIT page).
## {orbit, years, fuel_years, delay, observed_year, cap_year, sent, bottleneck, favoured, starved, lines}
static func result(state: Dictionary) -> Dictionary:
	var design: Dictionary = state.get("design", {})
	var id := id_of(design)
	var o := info(id)
	var out := {orbit = id, years = 0.0, fuel_years = 0.0, delay = 0.0, observed_year = 0.0, cap_year = 0.0,
			sent = 0, bottleneck = "", favoured = favoured(id), starved = false, lines = []}
	if str(state.get("finished", {}).get("outcome", "")) != "orbit" or str(state.get("lost", "")) != "":
		return out
	var p := DesignRules.mission_params(design)
	var base_storage := float(DesignRules.data().stats.base.storage)
	var fuel := maxf(float(state.get("fuel", 0.0)), 0.0)
	var drag := maxf(float(o.get("drag", 1.0)), 0.1)
	out.fuel_years = minf(fuel / drag, MAX_YEARS)
	out.delay = delay_years(design)
	out.years = maxf(out.fuel_years - out.delay, 0.0)
	var observed: float = float(p.science) * OBS_PER_YEAR * float(o.get("science_mult", 1.0))
	if out.favoured:
		observed *= FAVOURED
	out.starved = float(DesignRules.evaluate(design).net_w) < 0.0
	if out.starved:
		observed *= POWER_STARVED
	var recorder := 1.0 + (float(p.storage) - base_storage) / (base_storage * 3.0)
	var cap: float = float(p.downlink_rate) * float(o.get("contact_mult", 1.0)) * CONTACT_K * recorder
	out.observed_year = observed
	out.cap_year = cap
	out.bottleneck = "downlink" if observed > cap else "instruments"
	out.sent = int(minf(observed, cap) * out.years)
	out.lines = _lines(out, design, drag)
	return out


static func points(state: Dictionary) -> int:
	return int(result(state).sent) * ORBIT_POINTS


## "Why" lines for the report: the bottleneck, the lifetime, aerobraking, mission fit, power.
static func _lines(r: Dictionary, design: Dictionary, drag: float) -> Array[String]:
	var out: Array[String] = []
	if r.bottleneck == "downlink":
		out.append("DOWNLINK was the bottleneck: Mars gave %d science a year, the radio sent only %d. A dish, a bigger recorder or an orbit with more Earth contact would send more." % [
				int(r.observed_year), int(r.cap_year)])
	else:
		out.append("INSTRUMENTS were the bottleneck: the radio could send %d a year, but only %d was observed. More instruments or a lower orbit see more." % [
				int(r.cap_year), int(r.observed_year)])
	if r.fuel_years < MAX_YEARS:
		out.append("Fuel ran out after %.1f Mars years: holding this orbit costs %d%% fuel a year." % [r.fuel_years, int(drag)])
	else:
		out.append("Fuel lasted the whole %d-Mars-year mission." % int(MAX_YEARS))
	if r.delay > 0.0:
		var why: Array[String] = []
		for part: String in design.get("upgrades", []):
			var fx: Dictionary = data().parts.get(part, {})
			if fx.has("why"):
				why.append(str(fx.why))
		out.append("Aerobraking took %d months before science began%s." % [roundi(r.delay * MONTHS_PER_YEAR),
				(" (" + ", ".join(why) + ")") if why.size() > 0 else ""])
	if r.favoured:
		out.append("This orbit suits the mission's science: +%d%%." % roundi((FAVOURED - 1.0) * 100.0))
	if r.starved:
		out.append("Negative power budget: the battery ran flat in Mars' shadow, -%d%% science." % roundi((1.0 - POWER_STARVED) * 100.0))
	return out
