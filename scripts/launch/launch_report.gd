class_name LaunchReport
extends RefCounted
## "Why the launch failed" panel: a graph of the flight, what happened (this flight's numbers), the
## physics behind it, how to fix it (picked from what actually went wrong) and what real rockets do.
## Three failures, one lesson each:
##   breakup  - dynamic pressure q = 1/2 x air density x speed^2 (max-Q)
##   fuel     - the rocket equation (payload mass) + gravity loss (slow climbs waste speed)
##   staging  - dead mass: an empty stage the rocket can't accelerate
## The host builds the report once in launch._fail (make) and it travels inside the flight dictionary,
## so every co-op peer draws the same panel. Game physics is SIMPLIFIED; the explanations are the real
## physics it imitates. Real-rocket facts: Shuttle throttled to ~65-72% through max-Q, back up near
## 60 s ("go at throttle up"); rockets are ~85-90% propellant at liftoff; orbit = 7.8 km/s but the
## climb takes ~9.4 km/s (gravity + drag losses).

const DELAY := 1.4               # s after the failure: let the explosion / landing play first
const RED := Color("ff5050")
const GOLD := Color("ffc640")
const DIM := Color("9aa4b8")
const HEAD := Color("6b7390")


## Host: the report dictionary (plain data, goes over the network). samples = [[t, alt, speed, q, throttle]].
## lift = throttle needed to leave the pad (1 / thrust-to-weight of stage 1).
static func make(f: Dictionary, history: Array, points: int, mass: float, capacity: float, target: float, lift: float) -> Dictionary:
	var kind := "fuel"
	var fail := str(f.fail)
	if fail.begins_with("STRUCTURAL"):
		kind = "breakup"
	elif fail.begins_with("STAGE"):
		kind = "staging"
	elif fail.begins_with("NOT ENOUGH"):
		kind = "liftoff"
	var samples := []
	var step := maxf(float(history.size()) / float(maxi(points, 2)), 1.0)
	var i := 0.0
	while int(i) < history.size():
		samples.append(_snap(history[int(i)]))
		i += step
	if not history.is_empty() and samples[-1] != _snap(history[-1]):
		samples.append(_snap(history[-1]))
	return {
		kind = kind, samples = samples, mass = mass, capacity = capacity, target = target,
		load = mass / maxf(capacity, 1.0),
		peak_q = float(f.peak_q), peak_q_alt = float(f.peak_q_alt), peak_q_speed = float(f.peak_q_speed),
		peak_q_thr = float(f.peak_q_thr),
		thrust_dv = float(f.thrust_dv), gravity_dv = float(f.gravity_dv), speed = float(f.speed),
		max_speed = float(f.max_speed), max_alt = float(f.max_alt),
		pad_fuel = float(f.pad_fuel), avg_thr = float(f.thr_sum) / maxf(float(f.powered_time), 0.01),
		meco_alt = float(f.meco_alt), meco_speed = float(f.meco_speed), coast = float(f.coast),
		lift = lift, max_thr = float(f.get("max_thr", 0.0)),
	}


static func _snap(s: Array) -> Array:
	var out := []
	for v in s:
		out.append(snappedf(float(v), 0.01))
	return out


## Codex terms the report explains (unlocked when it appears).
static func terms(r: Dictionary) -> Array:
	match str(r.get("kind", "")):
		"breakup": return ["max_q", "dynamic_pressure"]
		"liftoff": return ["thrust_to_weight"]
		"staging": return ["staging", "rocket_equation"]
		"fuel": return ["rocket_equation", "gravity_loss", "delta_v"]
	return []


## {what, formula, physics, fix, real}: text for the panel, from the numbers.
static func text(r: Dictionary) -> Dictionary:
	var load_pct := roundi(float(r.load) * 100.0)
	match str(r.kind):
		"liftoff":
			var lift_pct := ceili(float(r.lift) * 100.0)
			var lift_fix: Array[String] = ["Push the lever past the green LIFT mark - this ship needed %d%%." % lift_pct]
			if float(r.load) > 0.82:
				lift_fix.append("The ship is %d%% of what this rocket can lift, so it needs a lot of throttle just to rise. A lighter ship rises easier." % load_pct)
			return {
				what = "The rocket never left the pad. The throttle reached %d%%, but this ship needed %d%% for the engines to push harder than the rocket weighs. The first stage burned all its fuel standing still." % [
						roundi(float(r.max_thr) * 100.0), lift_pct],
				formula = "acceleration = (thrust - weight) / mass",
				physics = "Weight = mass x gravity, pulling down all the time. Thrust only lifts the rocket once it is BIGGER than the weight (thrust-to-weight above 1). Only the extra thrust speeds the rocket up - the rest just holds it up.",
				fix = lift_fix,
				real = "REAL: rockets stay clamped to the pad until the engines are at full thrust - then the clamps let go.",
			}
		"breakup":
			var fix: Array[String] = ["Throttle DOWN (S) as the STRESS bar rises - here around %d km - then back to full above ~20 km, where the air is thin." % maxi(roundi(float(r.peak_q_alt)), 1)]
			if float(r.load) < 0.6:
				fix.append("Your ship is only %d%% of what the rocket can lift: a light load accelerates hard, so max-Q comes fast." % load_pct)
			return {
				what = "The air pushed %.1fx harder than the rocket is built for, %.1f km up at %.2f km/s, with the throttle at %d%%." % [
						float(r.peak_q), float(r.peak_q_alt), float(r.peak_q_speed), roundi(float(r.peak_q_thr) * 100.0)],
				formula = "q = 1/2 x air density x speed x speed",
				physics = "Dynamic pressure q is the push of the air on the rocket. Speed counts TWICE: twice as fast = 4x the push. The air thins out fast with height, so q peaks low and fast (max-Q). Past its limit the structure bends, then breaks.",
				fix = fix,
				real = "REAL: the Space Shuttle throttled down to ~65-72% through max-Q, then 'go at throttle up' about a minute after liftoff.",
			}
		"staging":
			var stage_fix: Array[String] = ["Press SPACE within 6 s of 'STAGE 1 EMPTY' - the faster, the less speed gravity steals while you coast."]
			return {
				what = "Stage 1 burned out %.1f km up at %.2f km/s. Nobody separated it in 6 s: the rocket topped out at %.1f km and fell back." % [
						float(r.meco_alt), float(r.meco_speed), float(r.max_alt)],
				formula = "speed gained = exhaust speed x ln(full mass / empty mass)",
				physics = "An empty stage is dead weight: tanks and engines that no longer push. With no thrust, gravity takes ~9.8 m/s off your speed EVERY second, so the rocket slows, stops and falls. Dropping the empty stage makes 'empty mass' small again - a fresh start for the rocket equation.",
				fix = stage_fix,
				real = "REAL: Saturn V had three stages. Falcon 9 has two - and flies its empty first stage back to land.",
			}
	# Out of fuel: where did the speed go?
	var fuel_fix: Array[String] = []
	if float(r.pad_fuel) > 6.0:
		fuel_fix.append("%d%% of stage 1 burned on the pad before liftoff: push past the LIFT mark at once." % roundi(float(r.pad_fuel)))
	if float(r.avg_thr) < 0.85:
		fuel_fix.append("Average throttle was %d%%: a slow climb holds the rocket up against gravity longer. Full throttle (except through max-Q)." % roundi(float(r.avg_thr) * 100.0))
	if float(r.coast) > 2.0:
		fuel_fix.append("%.1f s coasting before staging - no thrust, but gravity kept pulling. Separate the stage faster." % float(r.coast))
	if float(r.load) > 0.82:
		fuel_fix.append("The ship is %d%% of what this rocket can lift - almost no margin. Lighter ship, or a bigger rocket (D: redesign)." % load_pct)
	if fuel_fix.is_empty():
		fuel_fix.append("Fly at full throttle except through max-Q, and stage fast. Or make the ship lighter.")
	return {
		what = "Rocket and spacecraft tanks ran dry at %.2f of %.1f km/s. The engines gave %.1f km/s, gravity took %.1f km/s back." % [
				float(r.max_speed), float(r.target), float(r.thrust_dv), float(r.gravity_dv)],
		formula = "speed gained = exhaust speed x ln(full mass / empty mass)",
		physics = "The rocket equation: your spacecraft rides on top, so it counts as 'empty' mass. A heavier ship = a smaller mass ratio = less speed from the same fuel. And every second spent climbing slowly, part of the thrust only holds the rocket up: GRAVITY LOSS.",
		fix = fuel_fix,
		real = "REAL: rockets are ~85-90% fuel at liftoff. Orbit is 7.8 km/s, but the climb takes ~9.4 km/s - the rest is lost to gravity and air drag.",
	}


# --- drawing ---------------------------------------------------------------------------------

## The panel on the launch UI layer. t = seconds since it appeared (fade), time = clock for blinking.
static func draw(ui: Node2D, flight: Dictionary, t: float, time: float) -> void:
	var r: Dictionary = flight.report
	var k := clampf(t / 0.35, 0.0, 1.0)
	var tx := text(r)
	var box := Rect2(26, 20, 428, 232)
	ui.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.45 * k))
	ui.draw_rect(box, Color(0.05, 0.02, 0.04, 0.94 * k))
	ui.draw_rect(box, Color(RED, k), false, 1.0)
	var title := "LAUNCH FAILED"
	_t(ui, title, Vector2(240 - UiFont.width(title, 14) / 2.0, box.position.y + 17), 14, Color(RED, k))
	var reason := str(flight.fail)
	_t(ui, reason, Vector2(240 - UiFont.width(reason, 9) / 2.0, box.position.y + 30), 9, Color(1, 1, 1, k))
	# Left: the flight graph.
	var graph := Rect2(box.position.x + 12, box.position.y + 44, 168, 92)
	_graph(ui, r, graph, k)
	# Right: what happened + the physics.
	var x := graph.end.x + 12
	var w := box.end.x - 10 - x
	var y := graph.position.y + 4
	_t(ui, "WHAT HAPPENED", Vector2(x, y), 6, Color(HEAD, k))
	y += 9
	for line in MissionSelect._wrap(str(tx.what), w, 7):
		_t(ui, line, Vector2(x, y), 7, Color(1, 1, 1, k))
		y += 8
	y += 5
	_t(ui, "THE PHYSICS", Vector2(x, y), 6, Color(HEAD, k))
	y += 9
	for line in MissionSelect._wrap(str(tx.formula), w, 7):
		_t(ui, line, Vector2(x, y), 7, Color(Color("4fd8ff"), k))
		y += 8
	y += 2
	for line in MissionSelect._wrap(str(tx.physics), w, 6):
		_t(ui, line, Vector2(x, y), 6, Color(DIM, k))
		y += 7
	# Bottom: fix + real rockets (full width).
	var bx := box.position.x + 12
	var bw := box.size.x - 24
	var by := maxf(graph.end.y + 20, y + 6)
	_t(ui, "HOW TO FIX IT", Vector2(bx, by), 6, Color(HEAD, k))
	by += 9
	for fix: String in tx.fix:
		for line in MissionSelect._wrap("- " + fix, bw, 7):
			if by > box.end.y - 30:
				break
			_t(ui, line, Vector2(bx, by), 7, Color(GOLD, k))
			by += 8
	for line in MissionSelect._wrap(str(tx.real), bw, 6):
		if by > box.end.y - 22:
			break
		by += 1
		_t(ui, line, Vector2(bx, by + 2), 6, Color(Color("8cffb0"), k))
		by += 7
	var keys := "SPACE: NEW ROCKET     D: REDESIGN SHIP"
	var blink := 1.0 if fmod(time, 1.0) < 0.7 else 0.6
	_t(ui, keys, Vector2(240 - UiFont.width(keys, 9) / 2.0, box.end.y - 7), 9, Color(1.0, 0.78, 0.25, blink * k))


## breakup: q over time vs the structure's limit · fuel: speed vs the orbit line · staging: altitude.
static func _graph(ui: Node2D, r: Dictionary, g: Rect2, k: float) -> void:
	ui.draw_rect(g, Color(0, 0, 0, 0.5 * k))
	ui.draw_rect(g, Color(0.3, 0.34, 0.5, k), false, 1.0)
	var kind := str(r.kind)
	var col: Color = {breakup = RED, fuel = Color("5cf07a"), staging = Color("4fd8ff"), liftoff = GOLD}.get(kind, Color.WHITE)
	var idx: int = {breakup = 3, fuel = 2, staging = 1, liftoff = 4}.get(kind, 2)
	var label: String = {breakup = "AIR PRESSURE q", fuel = "SPEED km/s", staging = "ALTITUDE km", liftoff = "THROTTLE"}.get(kind, "")
	var samples: Array = r.get("samples", [])
	var t_max := 1.0
	var v_max := 0.0
	for s: Array in samples:
		t_max = maxf(t_max, float(s[0]))
		v_max = maxf(v_max, float(s[idx]))
	var ref := 0.0   # reference line: the structure's limit / orbital speed
	var ref_text := ""
	match kind:
		"breakup":
			ref = 1.0
			ref_text = "LIMIT"
		"fuel":
			ref = float(r.target)
			ref_text = "ORBIT %.1f" % ref
		"liftoff":
			ref = float(r.lift)
			ref_text = "LIFT %d%%" % ceili(ref * 100.0)
	v_max = maxf(maxf(v_max, ref) * 1.15, 0.1)
	var inner := g.grow(-4)
	inner.position.y += 6
	inner.size.y -= 6
	if ref > 0.0:
		var ry := _px(inner, 0.0, ref, t_max, v_max).y
		if kind == "breakup":   # danger zone above the limit
			ui.draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, ry - inner.position.y), Color(RED, 0.12 * k))
		elif kind == "liftoff":   # the zone the throttle had to reach
			ui.draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, ry - inner.position.y), Color(Color("5cf07a"), 0.12 * k))
		var xx := inner.position.x
		while xx < inner.end.x:   # dashed line
			ui.draw_rect(Rect2(xx, ry, 3, 1), Color(1, 1, 1, 0.55 * k))
			xx += 6
		_t(ui, ref_text, Vector2(inner.end.x - UiFont.width(ref_text, 6), ry - 2), 6, Color(1, 1, 1, 0.7 * k))
	if kind == "staging" and float(r.meco_alt) > 0.0:   # where stage 1 ran dry
		for s: Array in samples:
			if float(s[1]) >= float(r.meco_alt) - 0.01:
				var p := _px(inner, float(s[0]), float(s[1]), t_max, v_max)
				ui.draw_rect(Rect2(p.x, inner.position.y, 1, inner.size.y), Color(GOLD, 0.5 * k))
				var tag := "STAGE 1 EMPTY"
				_t(ui, tag, Vector2(minf(p.x + 2, inner.end.x - UiFont.width(tag, 6)), inner.position.y + 6), 6, Color(GOLD, k))
				break
	var pts := PackedVector2Array()
	for s: Array in samples:
		pts.append(_px(inner, float(s[0]), float(s[idx]), t_max, v_max))
	if pts.size() >= 2:
		ui.draw_polyline(pts, Color(col, k), 1.0)
	if kind == "breakup" and pts.size() > 0:   # mark the peak
		var best := pts[0]
		for p in pts:
			if p.y < best.y:
				best = p
		ui.draw_rect(Rect2(best - Vector2(1, 1), Vector2(3, 3)), Color(1, 1, 1, k))
		var pk := "PEAK x%.1f" % float(r.peak_q)
		var pw := UiFont.width(pk, 6)
		var py := best.y - 3 if best.y > inner.position.y + 10 else best.y + 9
		_t(ui, pk, Vector2(clampf(best.x - pw / 2.0, inner.position.x, inner.end.x - pw), py), 6, Color(1, 1, 1, k))
	_t(ui, label, Vector2(g.position.x + 4, g.position.y + 8), 6, Color(col, k))
	_t(ui, "TIME", Vector2(g.end.x - 4 - UiFont.width("TIME", 6), g.end.y - 2), 6, Color(HEAD, k))
	_t(ui, "GAME PHYSICS SIMPLIFIED", Vector2(g.position.x, g.end.y + 8), 5, Color(HEAD, k))


static func _px(inner: Rect2, tt: float, v: float, t_max: float, v_max: float) -> Vector2:
	return Vector2(inner.position.x + inner.size.x * tt / t_max, inner.end.y - inner.size.y * clampf(v / v_max, 0.0, 1.0))


static func _t(ui: Node2D, text: String, at: Vector2, size: int, col: Color) -> void:
	ui.draw_string(UiFont.font(), at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), col)
