class_name Vfx
extends Node2D
## Pixel-art effects for the ship scene. Everything is derived from Events (diffs between
## successive sim states), never from local input, so every co-op peer sees the same thing.
##
##   ticket fixed     -> role-coloured sparks + ring         ticket missed -> explosion + shake
##   science missed   -> grey fizzle                          station offline -> smoke + sparks
##   new ticket       -> red alarm vignette                   burn -> thruster plumes + shake
##   downlink         -> green data beam towards Earth        brownout -> lights flicker
##   ambient          -> twinkling stars, idle thruster flicker, footstep dust (under the crew)
##
## Particles are 1-2 px squares drawn at whole pixels (no textures, nothing smoothed).

const NOZZLES := [Vector2(9, 60), Vector2(9, 195)]  # thruster exhausts on the hull's left edge
const ENGINE_CORE := Vector2(90, 197)                # reactor ring in the Engine Room
const EARTH_DIR := Vector2(-0.85, -0.53)             # downlink beam heads off-screen top-left
const SCREEN := Vector2(480, 270)

const FIRE := [Color("fff3a0"), Color("ffc640"), Color("ff7a2a"), Color("ff3b2a")]
const SMOKE := Color("6b7180")

var _game: Node2D        # shaken (HUD is a CanvasLayer, so it stays still)
var _map: ShipMap
var _crew: Node2D
var _under: Node2D       # sits between the map and the crew: footstep dust

var _parts: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _stars: Array[Vector3] = []   # x, y, phase
var _prev := {}
var _crew_last := {}              # CrewMember -> last position
var _rng := RandomNumberGenerator.new()
var _t := 0.0

var _shake := 0.0
var _alarm := 0.0
var _flicker := 0.0
var _burn := 0.0
var _downlink := 0.0
var _emit_acc := {}               # name -> seconds since last emission


func setup(game: Node2D, map: ShipMap, crew: Node2D) -> void:
	_game = game
	_map = map
	_crew = crew
	name = "Vfx"
	z_index = 50
	_under = Node2D.new()
	_under.name = "VfxUnder"
	_under.draw.connect(_draw_under)
	game.add_child(_under)
	game.move_child(_under, map.get_index() + 1)
	game.add_child(self)


func _ready() -> void:
	_rng.randomize()
	var stars_rng := RandomNumberGenerator.new()
	stars_rng.seed = 7  # same sky on every peer
	while _stars.size() < 40:
		var p := Vector2(stars_rng.randi_range(0, 479), stars_rng.randi_range(0, 269))
		# Only the black space around the hull.
		if p.x < 24 or p.x > 462 or p.y < 14 or p.y > 257:
			_stars.append(Vector3(p.x, p.y, stars_rng.randf() * TAU))
	Events.state_changed.connect(_on_state)
	Events.event_started.connect(_on_event_started)


# --- reacting to the sim ---------------------------------------------------------------

func _on_event_started(_event: Dictionary) -> void:
	_alarm = 1.0
	Sfx.play("alarm")


func _exit_tree() -> void:
	Sfx.set_loop("downlink", false)


func _on_state(state: Dictionary) -> void:
	if _prev.is_empty():
		_prev = state.duplicate(true)
		return
	var now_ids := {}
	for event: Dictionary in state.get("events", []):
		now_ids[event.id] = true
	var was_offline: Array = _prev.get("offline", [])
	var offline: Array = state.get("offline", [])
	for event: Dictionary in _prev.get("events", []):
		if now_ids.has(event.id):
			continue
		var at := _station_pos(event.role)
		if event.role in offline and event.role not in was_offline:
			_explode(at)
		elif not event.repair and event.time_left >= 0.0 and event.time_left < 0.4:
			_fizzle(at)  # ran out of time without breaking anything (missed science)
		else:
			_success(at, Station.ROLE_COLORS.get(event.role, Color.WHITE))

	if float(state.get("fuel", 0)) < float(_prev.get("fuel", 0)) - 1.0:
		_burn = 0.6
		Sfx.play("burn", _rng.randf_range(0.9, 1.1))
		_shake = maxf(_shake, 0.35)
		_rings.append({p = ENGINE_CORE, r = 10.0, speed = 50.0, life = 0.35, max = 0.35, col = FIRE[1]})
		for i in 12:
			_spark(ENGINE_CORE, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30, 60),
					FIRE[i % 3], 0.4, 0.0)
	if float(state.get("science_sent", 0)) > float(_prev.get("science_sent", 0)):
		_downlink = 0.4
	var loads: Dictionary = state.get("loads", {})
	var prev_loads: Dictionary = _prev.get("loads", {})
	if float(state.get("power", 1)) <= 0.0 and (true in prev_loads.values()) and not (true in loads.values()):
		_flicker = 1.4
		Sfx.play("brownout")
	_prev = state.duplicate(true)


func _station_pos(role: String) -> Vector2:
	var station := _map.station_for_role(role) if _map else null
	return station.position if station else SCREEN / 2.0


# --- effect recipes --------------------------------------------------------------------

func _success(at: Vector2, color: Color) -> void:
	Sfx.play("fixed")
	for i in 16:
		_spark(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(35, 75),
				color if i % 3 else Color.WHITE, _rng.randf_range(0.35, 0.6), 140.0)
	_rings.append({p = at, r = 3.0, speed = 60.0, life = 0.3, max = 0.3, col = color})


func _explode(at: Vector2) -> void:
	Sfx.play("explode")
	for i in 28:
		_spark(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40, 110),
				FIRE[i % FIRE.size()], _rng.randf_range(0.4, 0.8), 160.0, 2 if i % 4 == 0 else 1)
	for i in 6:
		_smoke(at + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 2)), 1.2)
	_rings.append({p = at, r = 2.0, speed = 90.0, life = 0.25, max = 0.25, col = Color("ff4040")})
	_shake = maxf(_shake, 0.5)


func _fizzle(at: Vector2) -> void:
	Sfx.play("fizzle")
	for i in 5:
		_smoke(at + Vector2(_rng.randf_range(-5, 5), -4), 0.8)


func _spark(p: Vector2, v: Vector2, col: Color, life: float, grav := 0.0, size := 1) -> void:
	_parts.append({p = p, v = v, life = life, max = life, col = col, grav = grav, drag = 2.5,
			size = size, fade = false})


func _smoke(p: Vector2, life: float) -> void:
	_parts.append({p = p, v = Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-14, -8)),
			life = life, max = life, col = SMOKE, grav = 0.0, drag = 0.5, size = 2, fade = true})


## True every `interval` seconds for the emitter `key`.
func _every(key: String, interval: float, delta: float) -> bool:
	var acc: float = _emit_acc.get(key, 0.0) + delta
	if acc >= interval:
		_emit_acc[key] = acc - interval if acc - interval < interval else 0.0
		return true
	_emit_acc[key] = acc
	return false


# --- per-frame emitters + simulation ---------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(_shake - delta, 0.0)
	_alarm = maxf(_alarm - delta * 1.4, 0.0)
	_flicker = maxf(_flicker - delta, 0.0)
	_burn = maxf(_burn - delta, 0.0)
	_downlink = maxf(_downlink - delta, 0.0)

	# Thrusters: idle flicker, big plumes while burning.
	for nozzle: Vector2 in NOZZLES:
		var burning := _burn > 0.0
		if _every("noz%d" % int(nozzle.y), 0.02 if burning else 0.12, delta):
			var speed := _rng.randf_range(60, 120) if burning else _rng.randf_range(15, 30)
			_spark(nozzle + Vector2(0, _rng.randi_range(-2, 2)),
					Vector2(-speed, _rng.randf_range(-12, 12) if burning else 0.0),
					FIRE[_rng.randi() % (4 if burning else 2)],
					_rng.randf_range(0.15, 0.35) if burning else 0.12, 0.0, 2 if burning and _rng.randf() < 0.4 else 1)

	# Offline stations smoke and spark until repaired.
	for role: String in _prev.get("offline", []):
		var at := _station_pos(role)
		if _every("smoke_" + role, 0.18, delta):
			_smoke(at + Vector2(_rng.randf_range(-4, 4), -6), 1.0)
		if _every("zap_" + role, 0.5, delta):
			for i in 4:
				_spark(at + Vector2(0, -6), Vector2.from_angle(_rng.randf() * TAU) * 40.0,
						FIRE[i % 2], 0.25, 120.0)

	Sfx.set_loop("downlink", _downlink > 0.0)
	# Downlink: a stream of green bits flying towards Earth.
	if _downlink > 0.0 and _every("beam", 0.05, delta):
		var from := _station_pos("comms") + Vector2(0, -8)
		var dir := EARTH_DIR.rotated(_rng.randf_range(-0.06, 0.06))
		_spark(from, dir * 140.0, Color("a8ffb8") if _rng.randf() < 0.7 else Color.WHITE, 1.3)
		_parts[-1].drag = 0.0
		_parts[-1].trail = true

	# Footstep dust for every walking crew member (remote ones too).
	if _crew:
		var seen := {}
		for member in _crew.get_children():
			if member is CrewMember:
				var last: Vector2 = _crew_last.get(member, member.position)
				if member.position.distance_to(last) > 0.3 and _every("dust_%d" % member.get_instance_id(), 0.14 if member.running else 0.22, delta):
					_dust.append({p = member.position + Vector2(_rng.randf_range(-2, 2), -1),
							v = Vector2(_rng.randf_range(-6, 6), -3), life = 0.35, max = 0.35})
					Sfx.play("step", _rng.randf_range(0.85, 1.25), -8.0 if member.remote else 0.0)
				seen[member] = member.position
		_crew_last = seen  # forget crew that left

	_step(_parts, delta)
	_step(_dust, delta)
	for ring in _rings:
		ring.r += ring.speed * delta
		ring.life -= delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.life > 0.0)

	if _game:
		var amp := ceilf(_shake * 4.0)
		_game.position = Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1)) * amp if amp > 0 else Vector2.ZERO
	queue_redraw()
	if _under:
		_under.queue_redraw()


func _step(list: Array[Dictionary], delta: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		p.life -= delta
		if p.life <= 0.0:
			list.remove_at(i)
		else:
			p.v.y += p.get("grav", 0.0) * delta
			p.v *= maxf(1.0 - p.get("drag", 3.0) * delta, 0.0)
			p.p += p.v * delta
		i -= 1


# --- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	for s in _stars:
		var a := 0.35 + 0.65 * maxf(sin(_t * 1.7 + s.z), 0.0)
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(0.85, 0.9, 1.0, a))

	for ring in _rings:
		var k: float = ring.life / ring.max
		draw_arc(ring.p.round(), roundf(ring.r), 0, TAU, 20, Color(ring.col, k), 1.0)

	for p in _parts:
		var k: float = p.life / p.max
		var col: Color = p.col
		if p.fade:
			col = Color(col, 0.7 * k)
		elif k < 0.3:
			col = col.darkened(0.4)  # sparks cool down before vanishing
		if p.get("trail", false):  # data bits: bright head with a fading tail
			draw_line(p.p.round(), (p.p - p.v * 0.04).round(), Color(col, 0.35), 1.0)
			draw_rect(Rect2(p.p.round() - Vector2.ONE, Vector2(2, 2)), col)
		else:
			draw_rect(Rect2(p.p.round(), Vector2(p.size, p.size)), col)

	# Burn: the exhausts flare (they sit at the screen edge, so particles alone are not enough).
	if _burn > 0.0:
		for nozzle: Vector2 in NOZZLES:
			var h := 4.0 + (2.0 if _rng.randf() < 0.5 else 0.0)
			draw_rect(Rect2(0, nozzle.y - h / 2.0, nozzle.x + 1, h), Color(FIRE[1], 0.9))
			draw_rect(Rect2(2, nozzle.y - 1, nozzle.x - 1, 2), FIRE[0])

	var margin := Rect2(-6, -6, SCREEN.x + 12, SCREEN.y + 12)
	if _alarm > 0.0:
		var pulse := minf(_alarm * 1.5, 1.0) * (0.65 + 0.35 * sin(_t * 18.0))
		for band in 4:
			var w := 4.0 * (band + 1) + 6.0
			var col := Color(1.0, 0.12, 0.08, 0.3 * pulse / (band + 1))
			draw_rect(Rect2(margin.position, Vector2(margin.size.x, w)), col)
			draw_rect(Rect2(margin.position.x, margin.end.y - w, margin.size.x, w), col)
			draw_rect(Rect2(margin.position, Vector2(w, margin.size.y)), col)
			draw_rect(Rect2(margin.end.x - w, margin.position.y, w, margin.size.y), col)
	if _flicker > 0.0 and _rng.randf() < 0.6:
		draw_rect(margin, Color(0, 0, 0.03, _rng.randf_range(0.25, 0.6) * minf(_flicker, 1.0)))


func _draw_under() -> void:
	for d in _dust:
		var k: float = d.life / d.max
		_under.draw_rect(Rect2(d.p.round(), Vector2(1, 1)), Color(0.75, 0.78, 0.85, 0.5 * k))
