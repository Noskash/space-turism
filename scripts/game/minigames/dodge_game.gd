class_name DodgeGame
extends CanvasLayer
## Full-screen debris dodge for the Navigator (Spacewar-style flying, no guns), ~6 s, fast.
## A/D turn · W thrust · S brake · the screen wraps. Survive until the timer runs out.
## Parts: reaction wheels = fast turning, no fuel for turning; star tracker = warning marks at the
## edge before a chunk flies in. Runs locally on the pilot's machine, then emits `finished`
## with {hits, thrust, turning} (seconds of thruster use -> the sim charges fuel).
## Ship MASS (from the design) sets the feel: a light ship is quick and small, a heavy one is slow to
## speed up, turns slower, is bigger (easier to hit) but gets knocked around less. Hull % is shown.
## SIMPLIFIED: real comet debris is mostly dust; here it is fist-sized chunks so you can see them.

signal finished(result: Dictionary)

const SIZE := Vector2(480, 270)
const INTRO := 0.9
const SHIP_R := 3.5
const ACCEL := 280.0
const MAX_SPEED := 180.0
const TURN_SLOW := 4.4          # rad/s with thrusters
const TURN_FAST := 7.0          # with reaction wheels
const INVULN := 0.9
const OUTRO := 1.1
const REF_MASS := 380.0         # balanced ship, bare kit = the feel the constants were tuned for

var duration := 6.0
var wheels := false
var tracker := false
var mass := REF_MASS            # kg, from the design
var hull := 100.0               # hull % going in (more hits = more breach risk, shown on the HUD)
var density := 1.0              # share of the field we fly through (course change on the radar: 0.3..1)

var _agility := 1.0             # REF_MASS / mass, clamped: >1 light and nimble, <1 heavy and sluggish
var _size := 1.0                # drawn size + hitbox (heavier = bigger)

var _canvas: Node2D
var _t := -INTRO
var _ship := SIZE / 2.0
var _vel := Vector2.ZERO
var _angle := -PI / 2.0
var _rocks: Array[Dictionary] = []
var _stars: Array[Vector3] = []
var _sparks: Array[Dictionary] = []
var _spawn := 0.0
var _hits := 0
var _invuln := 0.0
var _thrust_time := 0.0
var _turn_time := 0.0
var _thrusting := false
var _shake := 0.0
var _done := false
var _outro := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 15
	_rng.randomize()
	_agility = clampf(REF_MASS / maxf(mass, 1.0), 0.55, 1.45)
	_size = clampf(sqrt(1.0 / _agility), 0.85, 1.3)
	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_game)
	add_child(_canvas)
	for i in 70:
		_stars.append(Vector3(_rng.randf() * SIZE.x, _rng.randf() * SIZE.y, _rng.randf_range(0.2, 1.0)))
	for i in 4:
		_spawn_rock(true)
	Tutorial.hold(true)  # crew + station input off while flying
	Sfx.play("alarm")
	Sfx.set_loop("rocket", true)
	Sfx.tune_loop("rocket", -80.0)


func _exit_tree() -> void:
	Tutorial.hold(false)
	Sfx.set_loop("rocket", false)


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(_shake - delta * 3.0, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	for i in _stars.size():
		var st := _stars[i]
		st.x = fposmod(st.x - _vel.x * delta * 0.15 * st.z - 20.0 * delta * st.z, SIZE.x)
		st.y = fposmod(st.y - _vel.y * delta * 0.15 * st.z, SIZE.y)
		_stars[i] = st
	if _done:
		_outro += delta
		_step_sparks(delta)
		if _outro >= OUTRO:
			finished.emit({hits = _hits, thrust = _thrust_time, turning = _turn_time})
			queue_free()
		_canvas.queue_redraw()
		return
	_fly(delta)
	if _t >= 0.0:
		_spawn -= delta
		if _spawn <= 0.0:
			_spawn = lerpf(0.4, 0.26, clampf(_t / duration, 0.0, 1.0)) / maxf(density, 0.3)  # busier; thinner at the edge
			_spawn_rock(false)
	_move_rocks(delta)
	_step_sparks(delta)
	if _t >= duration:
		_done = true
		Sfx.set_loop("rocket", false)
		Sfx.play("fixed" if _hits == 0 else "orbit")
	_canvas.queue_redraw()


func _fly(delta: float) -> void:
	var turn := Input.get_axis(Controls.action("p1", "left"), Controls.action("p1", "right"))
	_angle += turn * (TURN_FAST if wheels else TURN_SLOW) * clampf(pow(_agility, 0.4), 0.75, 1.15) * delta
	if turn != 0.0:
		_turn_time += delta
	_thrusting = Input.is_action_pressed(Controls.action("p1", "up"))
	if _thrusting:
		_vel += Vector2.from_angle(_angle) * ACCEL * _agility * delta
		_thrust_time += delta
	if Input.is_action_pressed(Controls.action("p1", "down")):
		_vel = _vel.move_toward(Vector2.ZERO, ACCEL * 0.9 * _agility * delta)
	_vel = _vel.limit_length(MAX_SPEED * sqrt(_agility))
	_ship = Vector2(fposmod(_ship.x + _vel.x * delta, SIZE.x), fposmod(_ship.y + _vel.y * delta, SIZE.y))  # wraps
	Sfx.tune_loop("rocket", -8.0 if _thrusting else -80.0, 1.4)


## Chunks come in from the edges, roughly at the ship, some fast and small, some slow and big.
func _spawn_rock(initial: bool) -> void:
	var r := _rng.randf_range(4.0, 12.0)
	var p: Vector2
	if initial:
		p = Vector2(_rng.randf() * SIZE.x, _rng.randf() * SIZE.y)
		if p.distance_to(_ship) < 90.0:
			p = _ship + (p - _ship).normalized() * 110.0
	else:
		var edge := _rng.randi() % 4
		var outside := r + (48.0 if tracker else 24.0)   # spawned off-screen; tracker: warned earlier
		match edge:
			0: p = Vector2(_rng.randf() * SIZE.x, -outside)
			1: p = Vector2(SIZE.x + outside, _rng.randf() * SIZE.y)
			2: p = Vector2(_rng.randf() * SIZE.x, SIZE.y + outside)
			_: p = Vector2(-outside, _rng.randf() * SIZE.y)
	var aim := (_ship - p).angle() + _rng.randf_range(-0.55, 0.55)
	var speed := _rng.randf_range(60.0, 125.0) * (12.0 / (r + 6.0))
	if tracker and not initial:
		speed *= 1.1
	var pts := PackedVector2Array()
	var n := _rng.randi_range(7, 10)
	for i in n:
		pts.append(Vector2.from_angle(TAU * i / n) * r * _rng.randf_range(0.7, 1.15))
	_rocks.append({p = p, v = Vector2.from_angle(aim) * speed * (0.4 if initial else 1.0), r = r,
			rot = _rng.randf() * TAU, spin = _rng.randf_range(-3.0, 3.0), pts = pts, entered = initial})


func _move_rocks(delta: float) -> void:
	var view := Rect2(Vector2.ZERO, SIZE)
	for i in range(_rocks.size() - 1, -1, -1):
		var rock := _rocks[i]
		rock.p += rock.v * delta
		rock.rot += rock.spin * delta
		if view.grow(-rock.r).has_point(rock.p):
			rock.entered = true
		if rock.entered and not view.grow(rock.r + 60.0).has_point(rock.p):
			_rocks.remove_at(i)
			continue
		if _invuln <= 0.0 and _t >= 0.0 and rock.p.distance_to(_ship) < rock.r * 0.85 + SHIP_R * _size:
			_hit(rock)


func _hit(rock: Dictionary) -> void:
	_hits += 1
	_invuln = INVULN
	_shake = 1.0
	_vel = (_ship - rock.p).normalized() * 120.0 * _agility + rock.v * 0.4 * _agility   # heavy = knocked less
	Sfx.play("impact", _rng.randf_range(0.8, 1.1))
	Sfx.play("explode", 1.6, -8.0)
	for k in 24:
		_sparks.append({p = _ship, v = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30, 140),
				life = 0.5, col = [Color.WHITE, Color("ffd890"), Color("ff7a2a")][k % 3]})


func _step_sparks(delta: float) -> void:
	for i in range(_sparks.size() - 1, -1, -1):
		var s := _sparks[i]
		s.life -= delta
		s.p += s.v * delta
		s.v *= 1.0 - minf(delta * 2.0, 1.0)
		if s.life <= 0.0:
			_sparks.remove_at(i)


# --- drawing --------------------------------------------------------------------------------

func _draw_game() -> void:
	var c := _canvas
	var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * 4.0
	c.draw_rect(Rect2(Vector2(-8, -8), SIZE + Vector2(16, 16)), Color("05060d"))
	for st in _stars:
		c.draw_rect(Rect2(Vector2(st.x, st.y).floor() + off * 0.3, Vector2(1, 1)), Color(0.8, 0.85, 1.0, 0.25 + st.z * 0.5))
	# Red chevrons at the edge where a chunk is about to fly in (star tracker: it warns earlier).
	if true:
		for rock in _rocks:
			if not rock.entered:
				var edge := Vector2(clampf(rock.p.x, 6, SIZE.x - 6), clampf(rock.p.y, 6, SIZE.y - 6))
				var dir: Vector2 = (rock.v as Vector2).normalized()
				var a := 0.5 + 0.5 * sin(_t * 20.0)
				c.draw_colored_polygon(PackedVector2Array([edge + dir * 5, edge + dir.rotated(2.4) * 4, edge + dir.rotated(-2.4) * 4]),
						Color(1, 0.3, 0.25, a))
	for rock in _rocks:
		var pts := PackedVector2Array()
		for q: Vector2 in rock.pts:
			pts.append((rock.p + q.rotated(rock.rot) + off).round())
		c.draw_colored_polygon(pts, Color("5e5448"))
		var rim := pts.duplicate()
		rim.append(pts[0])
		c.draw_polyline(rim, Color("a89880"), 1.0)
		c.draw_circle(rock.p + Vector2(-rock.r * 0.3, -rock.r * 0.3).rotated(rock.rot) + off, rock.r * 0.22, Color("463e35"))
	for s in _sparks:
		c.draw_rect(Rect2((s.p + off).round(), Vector2(2, 2)), Color(s.col, clampf(s.life * 2.0, 0.0, 1.0)))
	if _invuln <= 0.0 or fmod(_t, 0.12) < 0.06:
		_draw_ship(_ship + off)
	_draw_hud()


func _draw_ship(at: Vector2) -> void:
	var c := _canvas
	var f := Vector2.from_angle(_angle) * _size
	var r := f.orthogonal()
	if _thrusting:
		var l := 6.0 + _rng.randf_range(0.0, 4.0)
		c.draw_colored_polygon(PackedVector2Array([at - f * 3 + r * 2, at - f * 3 - r * 2, at - f * (3 + l)]), Color("ffc640"))
		c.draw_colored_polygon(PackedVector2Array([at - f * 3 + r * 1, at - f * 3 - r * 1, at - f * (3 + l * 0.6)]), Color("fff3a0"))
	var hull := PackedVector2Array([at + f * 7, at - f * 4 + r * 5, at - f * 2, at - f * 4 - r * 5])
	c.draw_colored_polygon(hull, Color("d8dce8"))
	var outline := hull.duplicate()
	outline.append(hull[0])
	c.draw_polyline(outline, Color("4fd8ff"), 1.0)
	c.draw_rect(Rect2((at + f * 2).round() - Vector2(1, 1), Vector2(2, 2)), Color("4fd8ff"))


func _draw_hud() -> void:
	var c := _canvas
	var font := UiFont.font()
	var left := clampf(duration - maxf(_t, 0.0), 0.0, duration)
	var bar := Rect2(140, 10, 200, 5)
	c.draw_rect(bar, Color(1, 1, 1, 0.15))
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * left / duration, bar.size.y)), Color("4fd8ff"))
	var title := "SURVIVE %.1fs" % left
	c.draw_string(font, Vector2(240 - UiFont.width(title, 9) / 2.0, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9), Color.WHITE)
	var hits := "HITS %d" % _hits
	c.draw_string(font, Vector2(470 - UiFont.width(hits, 9), 16), hits, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9),
			Color("ff5050") if _hits > 0 else Color("9aa4b8"))
	c.draw_string(font, Vector2(10, 16), "COMET DEBRIS · SIMPLIFIED", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b7390"))
	var feel := "LIGHT: QUICK" if _agility > 1.12 else ("HEAVY: SLUGGISH" if _agility < 0.88 else "BALANCED")
	c.draw_string(font, Vector2(10, 27), "MASS %d KG · %s" % [int(mass), feel], HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("9aa4b8"))
	var hull_col := Color("ff5050") if hull < 40.0 else (Color("ffc640") if hull < 70.0 else Color("9aa4b8"))
	c.draw_string(font, Vector2(470 - UiFont.width("HULL %d%%" % int(hull), 7), 27), "HULL %d%%" % int(hull),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), hull_col)
	var hint := "A/D TURN · W THRUST · S BRAKE"
	c.draw_string(font, Vector2(240 - UiFont.width(hint, 8) / 2.0, 262), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("9aa4b8"))
	var part := "REACTION WHEELS: FAST TURNS, NO FUEL" if wheels else "THRUSTERS: TURNING BURNS FUEL"
	c.draw_string(font, Vector2(10, 262), part, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6), Color("6b7390"))
	if _t < 0.0:
		var t := "DODGE THE DEBRIS!"
		c.draw_string(font, Vector2(240 - UiFont.width(t, 16) / 2.0, 120), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(16), Color("ffc640"))
	elif _done:
		var t := "CLEAR - NO HITS!" if _hits == 0 else "THROUGH - %d HIT%s" % [_hits, "" if _hits == 1 else "S"]
		c.draw_string(font, Vector2(240 - UiFont.width(t, 16) / 2.0, 120), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(16),
				Color("5cf07a") if _hits == 0 else Color("ff8a5c"))
