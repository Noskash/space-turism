class_name EvaView
extends CanvasLayer
## Spacewalk (EVA), the outside half: full screen on the spacewalker's machine (layer 15, holds crew input
## like the minigames). The ship's roof seen from outside, the same layout as the interior map scaled by K,
## with what only exists outside: solar wings, the high-gain dish, the radiator, the engine bells.
##   - airlock cycles (CYCLE s), then WASD walks the hull on magnetic boots (slow); you stay on the hull,
##     the masts and the booms (yellow handrails show the way); a tether trails back to the hatch.
##   - open "eva" tickets are marked on the hull; HOLD SPACE at one for its work_time -> {type = "eva_fix", id}.
##   - back at the hatch: SPACE (or Q) = cycle in. Suit O2 runs out -> the tether reels you back in.
##   - no air: no sound outside, only the suit (breathing, muffled boots through the suit). The cabin radio
##     keeps playing - call it the suit radio.
## The crew member is hidden inside (CrewMember.eva) and its `position` follows the walker mapped back to map
## coordinates, so co-op peers see the little suited figure crossing the roof (ShipEva) and the host knows
## who is outside (room "eva": radiation storm dose x1.5).
## SIMPLIFIED: a real suit lasts ~8 hours (EMU), here O2_TIME seconds; real basis of the jobs in fake_mission.

const C_IN := Vector2(240, 136)       # interior map centre...
const C_OUT := Vector2(240, 140)      # ...sits here on this screen
const K := 0.7                        # interior px -> outside px (smaller, so the wings and dish fit)
const SPEED := 46.0                   # magnetic boots: slower than walking inside
const O2_TIME := 75.0
const O2_WARN := 15.0
const CYCLE := 1.3                    # airlock depress / repress
const REACH := 12.0                   # to a fault
const HATCH_REACH := 9.0
const RECALL_SPEED := 120.0
const STEP_PX := 15.0

const BG := Color8(9, 8, 22)
const PLATE := Color("5b6378")
const PLATE_LIGHT := Color("8b93a8")
const PLATE_DARK := Color("3d4458")
const SEAM := Color("454c60")
const GOLD := Color("c9a24a")
const GOLD_DARK := Color("8f6f2c")
const RAIL := Color("ffd84a")
const CELL := Color("2c64c8")
const CELL_DARK := Color("1b3f86")
const CELL_LIGHT := Color("5d9cf5")
const SUIT := Color("eef1f6")
const SUIT_SHADE := Color("b9c0d0")
const VISOR := Color("ffc640")

const HULL := Rect2(84, 56, 300, 168)          # roof; the rounded nose adds NOSE_R to the right
const NOSE_R := Vector2(20, 84)
## Where each outside job is (screen coords of this view).
const SPOTS := {solar_wing = Vector2(240, 51), dish = Vector2(108, 49), radiator = Vector2(132, 234)}
const NAMES := {solar_wing = "SOLAR WING", dish = "ANTENNA DISH", radiator = "RADIATOR"}
const HOW := {solar_wing = "free the jammed hinge", dish = "unjam the gimbal", radiator = "clamp the coolant leak"}
## Walkable besides the roof: the top wing's mast, the dish boom, the radiator strut.
const MASTS := [Rect2(234, 44, 12, 16), Rect2(100, 42, 18, 18), Rect2(124, 218, 16, 24)]

var member: CrewMember
var ship: ShipEva

var _canvas: Node2D
var _t := 0.0
var _phase := "out"                   # out | walk | recall | in
var _cycle := 0.0
var _o2 := O2_TIME
var _pos := Vector2.ZERO
var _hatch := Vector2.ZERO
var _facing := Vector2.DOWN
var _walking := false
var _stride := 0.0
var _work := 0.0
var _work_id := -1
var _tick := 0.0
var _beep := 0.0
var _sent := {}                       # fault ticket ids already reported fixed
var _hint := ""
var _hint_t := 0.0
var _stamp := ""
var _stamp_t := -1.0
var _walk_time := 0.0
var _stars: Array[Vector3] = []
var _parts: Array[Dictionary] = []    # sparks, coolant crystals
var _rng := RandomNumberGenerator.new()
var _closed := false


static func to_outside(p: Vector2) -> Vector2:
	return (p - C_IN) * K + C_OUT


static func to_inside(p: Vector2) -> Vector2:
	return (p - C_OUT) / K + C_IN


func _ready() -> void:
	layer = 15
	_rng.randomize()
	_canvas = Node2D.new()
	UiKit.setup_canvas(_canvas)
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	for i in 90:
		_stars.append(Vector3(_rng.randf() * 480.0, _rng.randf() * 270.0, _rng.randf_range(0.2, 1.0)))
	_hatch = to_outside(ShipEva.HATCH).round()
	_pos = _hatch
	if member:
		member.eva = true
	Tutorial.hold(true)   # crew + station input off while outside
	Codex.unlock(["eva"])
	Sfx.play("airlock")
	Sfx.set_loop("breath", true)
	Sfx.tune_loop("hum", -30.0)       # vacuum: the ship's hum is gone
	Sfx.tune_loop("engine", -30.0)


func _exit_tree() -> void:
	Tutorial.hold(false)
	Sfx.set_loop("breath", false)
	Sfx.tune_loop("hum", 0.0)
	Sfx.tune_loop("engine", 0.0)


func _close() -> void:
	_closed = true
	if member and is_instance_valid(member):
		member.eva = false
		member.position = ShipEva.OUT
	queue_free()


func _process(delta: float) -> void:
	if _closed:
		return
	_t += delta
	_hint_t = maxf(_hint_t - delta, 0.0)
	if _stamp_t >= 0.0:
		_stamp_t += delta
		if _stamp_t > 1.4:
			_stamp_t = -1.0
	var st: Dictionary = ship.state if ship else {}
	if member == null or not is_instance_valid(member) or st.get("lost", "") != "" or not st.get("finished", {}).is_empty():
		_close()   # mission over: everyone is back inside for the report / game over
		return
	for i in _stars.size():
		var s := _stars[i]
		s.x = fposmod(s.x - 6.0 * s.z * delta, 480.0)
		_stars[i] = s
	_step_parts(delta)
	match _phase:
		"out":
			_cycle += delta
			if _cycle >= CYCLE:
				_phase = "walk"
				Sfx.play("dock", 0.7)
		"walk":
			_walk_time += delta
			_o2 = maxf(_o2 - delta, 0.0)
			_walk(delta)
			if _o2 <= 0.0:
				_phase = "recall"
				_work = 0.0
				Sfx.play("alarm")
				_say("SUIT O2 OUT - TETHER RECALL")
		"recall":
			_pos = _pos.move_toward(_hatch, RECALL_SPEED * delta)
			_walking = true
			if _pos.distance_to(_hatch) < 1.0:
				_go_in()
		"in":
			_cycle += delta
			if _cycle >= CYCLE:
				_close()
				return
	if _phase in ["walk", "recall"] and _o2 < O2_WARN:
		_beep -= delta
		if _beep <= 0.0:
			_beep = 1.0 if _o2 > 5.0 else 0.5
			Sfx.play("remind", 1.3)
		Sfx.tune_loop("breath", 0.0, 1.35)   # breathing faster
	member.position = to_inside(_pos)
	_canvas.queue_redraw()


func _go_in() -> void:
	_phase = "in"
	_cycle = 0.0
	_work = 0.0
	_walking = false
	Sfx.play("airlock", 1.1)


func _say(text: String) -> void:
	_hint = text
	_hint_t = 2.5


func _walk(delta: float) -> void:
	var dir := Input.get_vector(_act("left"), _act("right"), _act("up"), _act("down"))
	var spot := _fault_near()
	var working := not spot.is_empty() and Input.is_action_pressed(_act("interact"))
	_walking = false
	if not working and dir != Vector2.ZERO:
		_facing = dir
		var speed := SPEED * (Astronauts.dose("sick_slowdown") if member.sick else 1.0)
		var step := dir * speed * delta
		var before := _pos
		for cand: Vector2 in [_pos + step, _pos + Vector2(step.x, 0), _pos + Vector2(0, step.y)]:
			if _walkable(cand):
				_pos = cand
				break
		var moved := _pos.distance_to(before)
		_walking = moved > 0.01
		_stride += moved
		if _stride >= STEP_PX:
			_stride -= STEP_PX
			Sfx.play("step_eva", _rng.randf_range(0.9, 1.1))   # heard through the suit, not the vacuum
	# Working on a job: hold USE, the ring fills in 3 bolts; letting go starts the bolt again.
	if working:
		if int(spot.id) != _work_id:
			_work_id = int(spot.id)
			_work = 0.0
		var total := maxf(float(spot.get("work_time", 3.0)), 0.5)
		_work += delta / total
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.28
			Sfx.play("work_tick", 0.8 + _work * 0.6)
			_spark(SPOTS.get(spot.get("fault", ""), _pos), 3)
		if _work >= 1.0:
			_sent[int(spot.id)] = true
			Events.action_requested.emit("team", {type = "eva_fix", id = int(spot.id)})
			Sfx.play("fixed")
			_stamp = "FIXED!"
			_stamp_t = 0.0
			_work = 0.0
			_spark(SPOTS.get(spot.get("fault", ""), _pos), 14)
	else:
		_work = 0.0
	var at_hatch := _pos.distance_to(_hatch) <= HATCH_REACH
	if at_hatch and spot.is_empty() and Input.is_action_just_pressed(_act("interact")):
		_go_in()
	elif Input.is_action_just_pressed(_act("leave")):
		if at_hatch:
			_go_in()
		else:
			_say("WALK BACK TO THE HATCH TO GO IN")


func _act(verb: String) -> StringName:
	return Controls.action(member.scheme if member else "p1", verb)


## The open job within reach (not reported yet), or {}.
func _fault_near() -> Dictionary:
	for e: Dictionary in _open_faults():
		var p: Vector2 = SPOTS.get(e.get("fault", ""), Vector2(-99, -99))
		if _pos.distance_to(p) <= REACH:
			return e
	return {}


func _open_faults() -> Array:
	if ship == null:
		return []
	return ship.faults.filter(func(e: Dictionary) -> bool: return not _sent.has(int(e.id)))


func _fault_open(fault: String) -> bool:
	for e: Dictionary in _open_faults():
		if e.get("fault", "") == fault:
			return true
	return false


func _walkable(p: Vector2) -> bool:
	if Rect2(HULL.position + Vector2(3, 4), HULL.size - Vector2(3, 8)).has_point(p):
		return true
	var d := (p - Vector2(HULL.end.x, HULL.get_center().y)) / (NOSE_R - Vector2(3, 4))
	if p.x >= HULL.end.x and d.length() <= 1.0:
		return true
	for r: Rect2 in MASTS:
		if r.has_point(p):
			return true
	return false


# --- particles -----------------------------------------------------------------------------------

func _spark(at: Vector2, n: int) -> void:
	for i in n:
		_parts.append({p = at, v = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(15, 45),
				life = 0.5, col = Color("fff3a0") if i % 2 == 0 else Color("ffc640")})


func _step_parts(delta: float) -> void:
	if _fault_open("radiator") and fmod(_t, 0.12) < delta:   # coolant freezing into crystals as it leaks
		_parts.append({p = SPOTS.radiator + Vector2(_rng.randf_range(-3, 3), 2),
				v = Vector2(_rng.randf_range(-12, 12), _rng.randf_range(4, 18)), life = 1.6, col = Color("d8f4ff")})
	for i in range(_parts.size() - 1, -1, -1):
		var q: Dictionary = _parts[i]
		q.life -= delta
		q.p += q.v * delta   # no drag: vacuum
		if q.life <= 0.0:
			_parts.remove_at(i)


# --- drawing -------------------------------------------------------------------------------------

func _draw_all() -> void:
	var c := _canvas
	c.draw_rect(Rect2(0, 0, 480, 270), BG)
	for s in _stars:
		var col := Color(1, 1, 1, 0.25 + 0.6 * s.z)
		c.draw_rect(Rect2(Vector2(s.x, s.y).floor(), Vector2.ONE), col)
	_draw_mars(c)
	_draw_wing(c, Rect2(170, 26, 140, 20), _fault_open("solar_wing"))
	_draw_wing(c, Rect2(170, 240, 140, 28), false)
	c.draw_rect(Rect2(238, 46, 4, 12), PLATE_DARK)       # top mast
	c.draw_rect(Rect2(238, 222, 4, 20), PLATE_DARK)      # bottom mast
	_draw_dish(c, _fault_open("dish"))
	_draw_radiator(c, _fault_open("radiator"))
	_draw_engines(c)
	_draw_hull(c)
	_draw_rails(c)
	_draw_hatch(c)
	for q: Dictionary in _parts:
		c.draw_rect(Rect2(q.p.round(), Vector2.ONE), Color(q.col, clampf(q.life * 2.0, 0.0, 1.0)))
	_draw_faults(c)
	_draw_other_walkers(c)
	if _phase in ["walk", "recall"]:
		_draw_tether(c, _hatch, _pos)
		_draw_walker(c, _pos, _facing, _walking, member.role_color() if member else UiKit.TEXT)
	_draw_hud(c)


func _draw_mars(c: CanvasItem) -> void:
	var st: Dictionary = ship.state if ship else {}
	var days := float(st.get("cruise_days", 0.0))
	var k := clampf(float(st.get("day", 0.0)) / days, 0.0, 1.0) if days > 0.0 else 0.3
	var r := roundf(6.0 + 12.0 * k)
	var at := Vector2(452, 246)
	for y in range(-r, r + 1):
		var w := floorf(sqrt(maxf(r * r - y * y, 0.0)))
		var col := Color("c4532f") if (int(y + r) / 3) % 3 != 1 else Color("e8834f")
		c.draw_rect(Rect2(at.x - w, at.y + y, w * 2.0 + 1.0, 1), col)
		c.draw_rect(Rect2(at.x + w * 0.35, at.y + y, w * 0.65 + 1.0, 1), Color("86331e"))   # night side


func _draw_wing(c: CanvasItem, r: Rect2, jammed: bool) -> void:
	var halves := [Rect2(r.position, Vector2(r.size.x / 2.0 - 2.0, r.size.y)),
			Rect2(r.position + Vector2(r.size.x / 2.0 + 2.0, 0), Vector2(r.size.x / 2.0 - 2.0, r.size.y))]
	for i in 2:
		var h: Rect2 = halves[i]
		if jammed and i == 1:   # half-folded: shorter, askew, cells dark
			var pts := PackedVector2Array([h.position + Vector2(0, 4), h.position + Vector2(h.size.x - 10, -6),
					h.position + Vector2(h.size.x - 6, 6), h.position + Vector2(0, h.size.y - 3)])
			c.draw_colored_polygon(pts, CELL_DARK)
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), UiKit.INK, 1.0)
			for x in range(4, int(h.size.x) - 12, 7):
				c.draw_line(h.position + Vector2(x, 6 - x * 0.1), h.position + Vector2(x + 2, h.size.y - 6), CELL, 1.0)
			continue
		c.draw_rect(h.grow(1), UiKit.INK)
		c.draw_rect(h, CELL)
		for x in range(int(h.position.x) + 6, int(h.end.x), 7):
			c.draw_rect(Rect2(x, h.position.y, 1, h.size.y), CELL_DARK)
		for y in range(int(h.position.y) + 6, int(h.end.y), 7):
			c.draw_rect(Rect2(h.position.x, y, h.size.x, 1), CELL_DARK)
		c.draw_rect(Rect2(h.position.x, h.position.y, h.size.x, 1), CELL_LIGHT)


func _draw_dish(c: CanvasItem, jammed: bool) -> void:
	c.draw_line(Vector2(114, 58), Vector2(106, 44), PLATE_DARK, 3.0)   # boom
	var tilt := 0.65 if jammed else 0.0
	var ctr := Vector2(96, 38)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append((ctr + Vector2(cos(a) * 14.0, sin(a) * 7.0).rotated(tilt)).round())
	c.draw_colored_polygon(pts, Color("d8dce8"))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), UiKit.INK, 1.0)
	c.draw_rect(Rect2(ctr + Vector2(-6, 0).rotated(tilt), Vector2(12, 2)), Color("aab4c8"))
	c.draw_line(ctr, ctr + Vector2(0, -8).rotated(tilt), Color("8d96ad"), 1.0)          # feed horn
	c.draw_rect(Rect2((ctr + Vector2(0, -9).rotated(tilt)).round() - Vector2(1, 1), Vector2(2, 2)), Color("4d5573"))


func _draw_radiator(c: CanvasItem, leaking: bool) -> void:
	var r := Rect2(98, 230, 64, 24)
	c.draw_rect(Rect2(129, 222, 6, 10), PLATE_DARK)     # strut
	c.draw_rect(r.grow(1), UiKit.INK)
	c.draw_rect(r, Color("d8dce8"))
	for x in range(int(r.position.x) + 3, int(r.end.x), 4):
		c.draw_rect(Rect2(x, r.position.y, 1, r.size.y), Color("aab4c8"))
	if leaking:
		c.draw_rect(Rect2(SPOTS.radiator - Vector2(2, 1), Vector2(4, 3)), Color("2a2f3e"))


func _draw_engines(c: CanvasItem) -> void:
	for y in [88.0, 182.0]:
		var pts := PackedVector2Array([Vector2(86, y - 7), Vector2(86, y + 7), Vector2(70, y + 11), Vector2(70, y - 11)])
		c.draw_colored_polygon(pts, Color("8d96ad"))
		c.draw_polyline(pts + PackedVector2Array([pts[0]]), UiKit.INK, 1.0)
		c.draw_rect(Rect2(70, y - 9, 3, 18), Color("2a2f3e"))


func _draw_hull(c: CanvasItem) -> void:
	var nose := PackedVector2Array()
	var mid := HULL.get_center().y
	for i in 25:
		var a := -PI / 2.0 + PI * i / 24.0
		nose.append((Vector2(HULL.end.x, mid) + Vector2(cos(a) * NOSE_R.x, sin(a) * NOSE_R.y)).round())
	var outline := PackedVector2Array([HULL.position, Vector2(HULL.end.x, HULL.position.y)])
	outline.append_array(nose)
	outline.append_array(PackedVector2Array([Vector2(HULL.position.x, HULL.end.y), HULL.position]))
	c.draw_colored_polygon(outline, PLATE)
	# Gold foil blankets (MLI), dithered so they read as crinkled foil.
	for g: Rect2 in [Rect2(146, 70, 44, 22), Rect2(296, 178, 48, 30), Rect2(196, 150, 30, 20), Rect2(100, 120, 26, 40)]:
		c.draw_rect(g, GOLD)
		for y in range(int(g.position.y), int(g.end.y)):
			for x in range(int(g.position.x) + (y % 2), int(g.end.x), 4):
				c.draw_rect(Rect2(x, y, 1, 1), GOLD_DARK)
		c.draw_rect(Rect2(g.position.x, g.position.y, g.size.x, 1), Color("e8cf7a"))
	# Plate seams + rivets.
	for x in range(110, int(HULL.end.x), 26):
		c.draw_rect(Rect2(x, HULL.position.y + 1, 1, HULL.size.y - 2), SEAM)
		for y in range(int(HULL.position.y) + 5, int(HULL.end.y), 9):
			c.draw_rect(Rect2(x + 2, y, 1, 1), PLATE_LIGHT)
	for y in [98, 182]:
		c.draw_rect(Rect2(HULL.position.x + 1, y, HULL.size.x - 1, 1), SEAM)
	c.draw_rect(Rect2(HULL.position.x + 1, HULL.position.y + 1, HULL.size.x, 1), PLATE_LIGHT)   # sunlit edge
	c.draw_rect(Rect2(HULL.position.x + 1, HULL.end.y - 2, HULL.size.x, 1), PLATE_DARK)
	c.draw_polyline(outline, UiKit.INK, 1.0)
	# Bridge windows in the nose.
	for i in 3:
		c.draw_rect(Rect2(HULL.end.x + 4, mid - 22 + i * 16, 5, 9), Color("1b3f86"))
		c.draw_rect(Rect2(HULL.end.x + 4, mid - 22 + i * 16, 5, 1), CELL_LIGHT)


## Yellow handrails from the hatch to each job (real EVA crews move hand over hand along them).
func _draw_rails(c: CanvasItem) -> void:
	var h := _hatch
	var paths := [
		[h, Vector2(h.x, 66), Vector2(240, 66), Vector2(240, 52)],
		[Vector2(240, 66), Vector2(112, 66), Vector2(108, 56)],
		[h, Vector2(h.x, 212), Vector2(132, 212), Vector2(132, 226)],
	]
	for path: Array in paths:
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var n := maxi(int(a.distance_to(b)), 1)
			for k in n + 1:
				var p := a.lerp(b, float(k) / n).round()
				c.draw_rect(Rect2(p + Vector2(1, 1), Vector2.ONE), Color(0, 0, 0, 0.5))
				c.draw_rect(Rect2(p, Vector2.ONE), RAIL if k % 10 != 0 else Color("b8902a"))


func _draw_hatch(c: CanvasItem) -> void:
	var h := _hatch
	for i in 16:
		var a := TAU * i / 16.0
		var p := (h + Vector2(cos(a), sin(a) * 0.8) * 7.0).round()
		c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), RAIL if i % 2 == 0 else Color("1a1c26"))
	var open := _phase in ["walk", "recall"]
	c.draw_rect(Rect2(h - Vector2(5, 4), Vector2(10, 8)), Color("0b0d16") if open else Color("4d5573"))
	if not open:
		c.draw_rect(Rect2(h - Vector2(3, 0), Vector2(6, 1)), Color("8d96ad"))
	if _phase == "walk" and _pos.distance_to(_hatch) <= HATCH_REACH and _fault_near().is_empty():
		_prompt(c, h + Vector2(0, -16), "GO IN")


func _draw_faults(c: CanvasItem) -> void:
	for e: Dictionary in _open_faults():
		var f := str(e.get("fault", ""))
		var p: Vector2 = SPOTS.get(f, Vector2.ZERO)
		var pulse := 6.0 + 2.0 * sin(_t * 6.0)
		_ring(c, p, pulse, UiKit.BAD if fmod(_t, 0.5) < 0.3 else UiKit.WARN, 18, 1.0)
		var near := _pos.distance_to(p) <= REACH
		if near and _work > 0.0 and int(e.id) == _work_id:
			_ring(c, p, 10.0, UiKit.FAINT, 24, 1.0)
			_ring(c, p, 10.0, UiKit.GOOD, 24, _work)
			for b in 3:   # the three bolts
				var lit := _work >= (b + 1) / 3.0
				c.draw_rect(Rect2(p + Vector2(-6 + b * 5, 13), Vector2(3, 3)), UiKit.GOOD if lit else UiKit.FAINT)
		var label: String = NAMES.get(f, f.to_upper())
		var ly := p.y - 12.0 if p.y > 60.0 else p.y + 20.0
		if f in ["solar_wing", "dish"]:
			ly = p.y + 22.0
		UiKit.text_c(c, p.x, ly, label, 6, UiKit.WARN, 1)
		if near and _phase == "walk":
			_prompt(c, Vector2(p.x, ly + 10), "HOLD  " + str(HOW.get(f, "fix it")).to_upper())


func _ring(c: CanvasItem, p: Vector2, r: float, col: Color, n: int, frac: float) -> void:
	for i in roundi(n * clampf(frac, 0.0, 1.0)):
		var a := -PI / 2.0 + TAU * i / n
		c.draw_rect(Rect2((p + Vector2(cos(a), sin(a)) * r).round(), Vector2.ONE), col)


func _prompt(c: CanvasItem, at: Vector2, verb: String) -> void:
	var key := Controls.key_name(member.scheme if member else "p1", "interact")
	var w := UiKit.keycap_size(key, 6).x + 3.0 + UiKit.text_w(verb, 6)
	var x := roundf(at.x - w / 2.0)
	UiKit.dither(c, Rect2(x - 3, at.y - 8, w + 6, 11), Color(0, 0, 0, 0.8))
	var kr := UiKit.keycap(c, Vector2(x, at.y - 7), key, 6)
	UiKit.text(c, Vector2(kr.end.x + 3, at.y), verb, 6, UiKit.TEXT, 1)


func _draw_tether(c: CanvasItem, a: Vector2, b: Vector2) -> void:
	var dist := a.distance_to(b)
	if dist < 2.0:
		return
	var side := (b - a).orthogonal().normalized()
	var mid := (a + b) / 2.0 + side * (minf(dist * 0.15, 18.0) + sin(_t * 1.7) * 2.0)
	var n := maxi(int(dist / 1.5), 2)
	for i in n + 1:
		var k := float(i) / n
		var q := a.lerp(mid, k).lerp(mid.lerp(b, k), k).round()
		c.draw_rect(Rect2(q + Vector2(1, 1), Vector2.ONE), Color(0, 0, 0, 0.45))
		c.draw_rect(Rect2(q, Vector2.ONE), Color("e8e2c8"))


## The spacesuit: white suit, life-support backpack, gold visor on the side you face, the role's colour
## as leg stripes (real crews tell spacewalkers apart by the stripes on their suits).
func _draw_walker(c: CanvasItem, p: Vector2, facing: Vector2, walking: bool, stripe: Color) -> void:
	var bob := roundf(sin(_t * 2.2)) if not walking else 0.0   # floats a little when standing
	var o := p.round() + Vector2(-5, -15 + bob)
	var step := walking and fmod(_t * 5.0, 2.0) < 1.0
	var up := facing.y < -0.5 and absf(facing.x) < 0.5
	var pieces := [Rect2(2, 0, 6, 6), Rect2(1, 6, 8, 5), Rect2(0, 6, 1, 4), Rect2(9, 6, 1, 4),
			Rect2(2, 11, 2, 4 - (1 if step else 0)), Rect2(6, 11, 2, 4 - (0 if step else 1))]
	c.draw_rect(Rect2(o + Vector2(1, 3), Vector2(8, 7)).grow(1), UiKit.INK)   # backpack + suit silhouette
	for r: Rect2 in pieces:
		c.draw_rect(Rect2(o + r.position, r.size).grow(1), UiKit.INK)
	if not up:
		c.draw_rect(Rect2(o + Vector2(1, 3), Vector2(8, 7)), Color("8d96ad"))    # backpack peeks out
	for r: Rect2 in pieces:
		c.draw_rect(Rect2(o + r.position, r.size), SUIT)
	c.draw_rect(Rect2(o + Vector2(1, 9), Vector2(8, 2)), SUIT_SHADE)
	if up:
		c.draw_rect(Rect2(o + Vector2(2, 5), Vector2(6, 6)), Color("aab4c8"))   # backpack from behind
	else:
		var vx := 3.0
		if facing.x < -0.5:
			vx = 2.0
		elif facing.x > 0.5:
			vx = 4.0
		c.draw_rect(Rect2(o + Vector2(vx, 2), Vector2(4 if absf(facing.x) < 0.5 else 3, 2)), VISOR)
		c.draw_rect(Rect2(o + Vector2(vx, 2), Vector2(1, 1)), Color.WHITE)
	c.draw_rect(Rect2(o + Vector2(2, 13), Vector2(2, 1)), stripe)
	c.draw_rect(Rect2(o + Vector2(6, 13), Vector2(2, 1)), stripe)
	if _phase == "walk" and _o2 < O2_WARN and fmod(_t, 0.5) < 0.25:
		c.draw_rect(Rect2(o + Vector2(7, 3), Vector2(2, 2)), UiKit.BAD)   # suit warning light


## Co-op: other spacewalkers (their crew member's position, mapped back out).
func _draw_other_walkers(c: CanvasItem) -> void:
	if ship == null or ship.crew == null:
		return
	for m in ship.crew.get_children():
		if m is CrewMember and m != member and m.eva:
			var p := to_outside(m.position)
			_draw_tether(c, _hatch, p)
			_draw_walker(c, p, m.facing_dir(), false, m.role_color())


func _draw_hud(c: CanvasItem) -> void:
	var col := member.role_color() if member else UiKit.TEXT
	# Top bar: title + suit oxygen.
	var bar := Rect2(2, 2, 476, 20)
	UiKit.panel(c, bar, UiKit.PANEL, col)
	UiKit.icon(c, "spacewalk", bar.position + Vector2(3, 2), 1, Color.WHITE)
	UiKit.text(c, Vector2(bar.position.x + 23, bar.end.y - 5), "SPACEWALK", 10, col)
	var low := _o2 < O2_WARN
	var o2_col := UiKit.BAD if low else Color("8cf0ff")
	var sw := UiKit.seg_bar_width(20, 6)
	var bx := roundf(240 - sw / 2.0)
	UiKit.text_r(c, bx - 4, bar.end.y - 6, "SUIT O2", 7, o2_col)
	UiKit.seg_bar(c, Rect2(bx, bar.position.y + 7, sw, 7), _o2 / O2_TIME, o2_col if not low or fmod(_t, 0.5) < 0.3 else UiKit.TEXT, 20)
	UiKit.text(c, Vector2(bx + sw + 4, bar.end.y - 6), "%d s" % ceili(_o2), 7, o2_col)
	var jobs := _open_faults()
	UiKit.text_r(c, bar.end.x - 6, bar.end.y - 6, "JOBS LEFT %d" % jobs.size() if not jobs.is_empty() else "ALL FIXED - GO IN",
			8, UiKit.WARN if not jobs.is_empty() else UiKit.GOOD)
	# Job list under the bar, right.
	var y := 28.0
	for e: Dictionary in jobs:
		var f := str(e.get("fault", ""))
		var text := "%s: %s" % [NAMES.get(f, f), HOW.get(f, "")]
		var w := UiKit.text_w(text, 6) + 16.0
		var r := Rect2(476 - w, y, w, 11)
		UiKit.panel(c, r, UiKit.PANEL_DARK)
		UiKit.icon(c, "eva", r.position + Vector2(2, 1.5), 1, Color.WHITE)
		UiKit.text(c, Vector2(r.position.x + 12, r.end.y - 3), text, 6, UiKit.TEXT, 0)
		y += 13.0
	# Space weather: get inside!
	var st: Dictionary = ship.state if ship else {}
	var cme: Dictionary = st.get("cme", {})
	var dust: Dictionary = st.get("dust", {})
	var warn := ""
	if cme.get("phase", "") == "warning":
		warn = "RADIATION STORM IN %d s - GET INSIDE!" % ceili(float(cme.get("time_left", 0.0)))
	elif cme.get("phase", "") == "wave":
		warn = "RADIATION WAVE - NO SHELTER OUT HERE"
	elif dust.get("phase", "") in ["warning", "stream", "flying"]:
		warn = "COMET DEBRIS AHEAD - GET INSIDE!"
	if warn != "" and fmod(_t, 0.8) < 0.55:
		var w := UiKit.text_w(warn, 8) + 12.0
		var r := Rect2(roundf(240 - w / 2.0), 26, w, 13)
		UiKit.panel(c, r, Color("3a0d12"), UiKit.BAD)
		UiKit.text_c(c, 240, r.end.y - 3, warn, 8, UiKit.WARN, 1)
	# Airlock cycling.
	if _phase in ["out", "in"]:
		var r := Rect2(150, 118, 180, 34)
		UiKit.panel(c, r, UiKit.PANEL, col)
		UiKit.text_c(c, 240, r.position.y + 13, "AIRLOCK: " + ("DEPRESSURISING" if _phase == "out" else "REPRESSURISING"), 8, UiKit.TEXT)
		UiKit.seg_bar(c, Rect2(160, r.position.y + 19, 160, 7), clampf(_cycle / CYCLE, 0.0, 1.0), col, 16)
	# Footer: controls, and the vacuum fact for the first seconds.
	var hint := "WASD MOVE   HOLD SPACE AT A JOB   SPACE AT THE HATCH = GO IN"
	UiKit.dither(c, Rect2(0, 258, 480, 12), Color(0, 0, 0, 0.85))
	UiKit.text_c(c, 240, 267, hint, 6, UiKit.DIM, 0)
	if _phase == "walk" and _walk_time < 6.0:
		UiKit.text_c(c, 240, 251, "No air out here = no sound. You only hear your own suit.  (SIMPLIFIED: real suits last ~8 h)", 6, UiKit.FAINT.lightened(0.4), 1)
	if _hint_t > 0.0:
		UiKit.text_c(c, 240, 112, _hint, 9, UiKit.WARN, 2)
	if _stamp_t >= 0.0:
		UiKit.stamp(c, Vector2(240, 135), _stamp, UiKit.GOOD, clampf(1.0 - _stamp_t / 0.18, 0.0, 1.0), 20)
