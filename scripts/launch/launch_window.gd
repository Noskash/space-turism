class_name LaunchWindow
extends RefCounted
## Launch window planner maths (SIMPLIFIED, shown as such on screen). Static, no nodes.
##
## Earth and Mars on circular orbits. A transfer only works if Mars is the right angle ahead of
## Earth on launch day (~44 deg for the minimum-energy Hohmann path), so it reaches the meeting
## point together with the ship. Every day Earth gains ~0.46 deg on Mars, so the right angle comes
## back only every ~26 months (the synodic period): that is a launch window.
##
## The plan = {offset = days from the best STANDARD date, speed = "standard" | "fast"}.
## Being off the ideal angle costs extra departure delta-v (a bowl, like a real porkchop plot).
## The rocket covers the standard departure plus a little spare when the ship is light (lift margin);
## the rest is burned from the SPACECRAFT's own tank -> less fuel for the Mars brake burn.
## FAST = shorter trip (earlier science, fewer hazards) but more departure delta-v and a faster
## arrival, so the brake burn needs more fuel (moi_mult).
##
## Result stored in the design as design.plan (goes over the network unchanged):
##   {offset, speed, date, trip_days, dv, fuel_cost, moi_mult}
## Read by fake_mission (cruise length, fuel after departure), Orbits.moi_fuel (FAST brake) and
## MissionReport (why it went that way).

const EARTH_DEG_PER_DAY := 360.0 / 365.25
const MARS_DEG_PER_DAY := 360.0 / 687.0
const CLOSE_DEG_PER_DAY := EARTH_DEG_PER_DAY - MARS_DEG_PER_DAY   # ~0.462: Earth gains on Mars
const SYNODIC_DAYS := 780                                            # ~26 months between windows
const RANGE_DAYS := 120                                              # date slider: +/- this many days
const DAY_STEP := 2

const PATHS := {
	"standard": {name = "STANDARD", trip = 259.0, sweep = 180.0, dv = 2.9, moi_mult = 1.0,
			desc = "Minimum-energy (Hohmann) half-orbit. Least fuel, longest trip."},
	"fast": {name = "FAST", trip = 180.0, sweep = 150.0, dv = 3.8, moi_mult = 1.4,
			desc = "Shorter, steeper path: Mars sooner, but more push at departure and a faster arrival to brake."},
}
const ORDER := ["standard", "fast"]
const DV_PER_DEG2 := 0.004     # km/s of extra departure delta-v per (degree off the ideal angle)^2
const FUEL_PER_KMS := 22.0     # % of the ship's tank per km/s it has to burn itself
const SPARE_PER_MARGIN := 2.5  # km/s of rocket spare per unit of lift margin above the 10% minimum
const MAX_SPARE := 1.2
const DEFAULT_DATE := "2026-11-20"   # sandbox: the late-2026 Mars window (approximate)


static func default_plan() -> Dictionary:
	return {offset = 0, speed = "standard"}


static func plan_of(design: Dictionary) -> Dictionary:
	var p: Dictionary = design.get("plan", {})
	if p.is_empty():
		return default_plan()
	return {offset = int(p.get("offset", 0)), speed = str(p.get("speed", "standard"))}


## Angle (deg) Mars must lead Earth by on launch day for this path to meet it.
static func ideal_lead(speed: String) -> float:
	var p: Dictionary = PATHS.get(speed, PATHS.standard)
	return float(p.sweep) - MARS_DEG_PER_DAY * float(p.trip)


## How far Mars actually leads Earth `offset` days after the best STANDARD date.
static func lead(offset: int) -> float:
	return ideal_lead("standard") - CLOSE_DEG_PER_DAY * offset


## Best date offset for a path (FAST needs Mars further ahead -> launch earlier).
static func best_offset(speed: String) -> int:
	return roundi((ideal_lead("standard") - ideal_lead(speed)) / CLOSE_DEG_PER_DAY)


## Extra delta-v the rocket can give on top of the standard departure: light ships get spare.
static func rocket_spare(design: Dictionary) -> float:
	var ev := DesignRules.evaluate(design)
	if ev.launcher.is_empty():
		return 0.0
	var margin := 1.0 - float(ev.mass) / float(ev.launcher.capacity_kg)
	return clampf((margin - (1.0 - DesignRules.LIFT_MARGIN)) * SPARE_PER_MARGIN, 0.0, MAX_SPARE)


## Everything the planner screen shows for this design + plan.
static func evaluate(design: Dictionary, plan: Dictionary) -> Dictionary:
	var speed := str(plan.get("speed", "standard"))
	if not PATHS.has(speed):
		speed = "standard"
	var offset := clampi(int(plan.get("offset", 0)), -RANGE_DAYS, RANGE_DAYS)
	var p: Dictionary = PATHS[speed]
	var l := lead(offset)
	var il := ideal_lead(speed)
	var err := l - il
	var dv := float(p.dv) + DV_PER_DEG2 * err * err
	var rocket := float(PATHS.standard.dv) + rocket_spare(design)
	var extra := maxf(dv - rocket, 0.0)
	var fuel_cost := extra * FUEL_PER_KMS
	var bare := design.duplicate(true)
	bare.erase("plan")
	var moi := Orbits.moi_fuel(bare) * float(p.moi_mult)
	var arrival_mars := 180.0 - l - MARS_DEG_PER_DAY * float(p.trip)   # where Mars is when the ship arrives
	var path_end := 180.0 - float(p.sweep)                               # where the path meets Mars' orbit
	var verdict := "GOOD WINDOW - THE ROCKET DOES ALL THE WORK"
	if fuel_cost >= 100.0:
		verdict = "IMPOSSIBLE - NOT EVEN A FULL TANK REACHES MARS"
	elif fuel_cost + moi > 100.0:
		verdict = "REACHES MARS, BUT NO FUEL LEFT TO BRAKE (FLYBY)"
	elif fuel_cost > 0.5:
		verdict = "OFF THE WINDOW - THE SHIP BURNS ITS OWN FUEL"
	return {
		offset = offset, speed = speed, path = p, date = date_text(offset),
		lead = l, ideal_lead = il, lead_error = err,
		dv = dv, rocket_dv = rocket, extra_dv = extra, fuel_cost = fuel_cost,
		moi = moi, moi_mult = float(p.moi_mult), trip_days = float(p.trip),
		arrival_mars = arrival_mars, path_end = path_end,
		miss_deg = wrapf(arrival_mars - path_end, -180.0, 180.0),
		ok = fuel_cost < 100.0, verdict = verdict,
	}


## The design with the plan written into it (what the launch and the cruise read).
static func apply(design: Dictionary, plan: Dictionary) -> Dictionary:
	var e := evaluate(design, plan)
	var out := design.duplicate(true)
	out.plan = {offset = e.offset, speed = e.speed, date = e.date, trip_days = e.trip_days,
			dv = snappedf(e.dv, 0.01), fuel_cost = snappedf(e.fuel_cost, 0.1), moi_mult = e.moi_mult}
	return out


## Cruise length chosen in the planner (0 = no plan: the mission's own cruise_days).
static func trip_days(design: Dictionary) -> float:
	return float(design.get("plan", {}).get("trip_days", 0.0))


## % of the ship's tank burned at departure (0 without a plan).
static func fuel_cost(design: Dictionary) -> float:
	return float(design.get("plan", {}).get("fuel_cost", 0.0))


## Brake-burn multiplier from the path (FAST arrives faster).
static func moi_mult(design: Dictionary) -> float:
	return float(design.get("plan", {}).get("moi_mult", 1.0))


## Best date for the current mission (NASA's real launch date; sandbox: the 2026 window).
static func base_date() -> String:
	return str(Missions.current().get("launch_date", DEFAULT_DATE))


## "2001-04-07" + offset days.
static func date_text(offset: int, base := "") -> String:
	var b := base if base != "" else base_date()
	var unix := Time.get_unix_time_from_datetime_string(b + "T12:00:00")
	return Time.get_date_string_from_unix_time(int(unix) + offset * 86400)
