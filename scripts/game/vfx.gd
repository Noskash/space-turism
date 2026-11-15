class_name Vfx
extends Node2D
## Pixel-art effects for the ship scene. Everything is derived from Events (diffs between
## successive sim states), never from local input, so every co-op peer sees the same thing.
##
##   ticket fixed     -> role-coloured sparks + ring         ticket missed -> explosion + shake
##   science missed   -> grey fizzle                          station offline -> smoke + sparks
##   new ticket       -> red alarm vignette                   burn -> thruster plumes + shake
##   downlink         -> green data beam towards Earth        brownout -> lights flicker
##   ambient          -> stars streaming past (the ship flies right), gentle hull bob, animated
##                       engine flames + reactor glow, footstep dust (under the crew)
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
var _stars: Array[Vector3] = []   # x, y, speed px/s (parallax layer)
const HULL := Rect2(24, 14, 438, 243)  # stars are hidden behind this
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

## Ticket reminders: past 75% of a ticket's time, a clock tick that speeds up to the end.
const REMIND_AT := 0.25           # fraction of time left
var _ticket_time := {}            # id -> [time_left, duration], counted down locally between states
var _warned := {}                 # id -> true once its 75% chirp played
var _remind_timer := 0.0
# Space weather (state.cme / state.blackout / state.dust).
var _cme_phase := ""
var _siren_timer := 0.0
var _dust_phase := ""
var _shields := false
var _grains: Array[Vector3] = []  # x, y, speed: comet dust streaking past outside the hull
# Meteoroid hitting the powerless ship (state.meteor): rock drawn flying in, then the crash.
const METEOR_SHOW := 2.5
const HULL_FRONT := 462.0
var _meteor_left := -1.0
var _meteor_y := 135.0
var _meteor_seq := 0
var _flash := 0.0                 # white screen flash on impact
# Mission lost: chain of explosions across the ship, then GameOver breaks it apart.
const DOOM_TIME := 2.6
var _doom := 0.0
var _doom_boom := 0.0
var _proximity := 0.0             # proximity alarm beep timer
# Science bookkeeping made visible: "+10 SCIENCE" at the lab, "+6 SENT HOME" at Comms, "-3 LOST".
var _texts: Array[Dictionary] = []   # {p, text, col, life}

# Burn shove: BRACE warning while a burn spools up, then a whoosh when it throws the crew.
var _brace := -1.0                # seconds until the spooled burn fires (-1 = none)
var _klaxon := 0.0
var _shove_seq := -1
# Ticket grades: a stamp pops over the station (PERFECT / GOOD / LATE / MISSED) + the streak.
const GRADE_LOOK := {
	perfect = ["PERFECT!", Color("ffc640")], good = ["GOOD", Color("5cf07a")],
	late = ["LATE", Color("ff9a3c")], missed = ["MISSED", Color("ff5050")],
}
var _grade_seq := -1
var _stamps: Array[Dictionary] = []  # {p, text, col, streak, life}
var _sent_acc := 0.0
var _lost_acc := 0.0
var _sci_timer := 0.0


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
	for i in 90:
		var layer: float = [5.0, 12.0, 28.0][i % 3]
		_stars.append(Vector3(stars_rng.randf_range(0, 480), stars_rng.randi_range(0, 269), layer))
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
	_ticket_time.clear()
	for event: Dictionary in state.get("events", []):
		now_ids[event.id] = true
		if float(event.time_left) >= 0.0 and float(event.duration) > 0.0:
			_ticket_time[event.id] = [float(event.time_left), float(event.duration)]
			if event.time_left / event.duration < REMIND_AT and not _warned.has(event.id):
				_warned[event.id] = true
				Sfx.play("warn")
	var was_offline: Array = _prev.get("offline", [])
	var offline: Array = state.get("offline", [])
	for event: Dictionary in _prev.get("events", []):
		if now_ids.has(event.id) or event.get("kind", "") == "fire":
			continue   # (a fire ticket ends when its last flame is out: ShipFire shows that)
		var at := _station_pos(event.role)
		if event.role in offline and event.role not in was_offline:
			_explode(at)
		elif not event.repair and event.time_left >= 0.0 and event.time_left < 0.4:
			_fizzle(at)  # ran out of time without breaking anything (missed science)
		else:
			_success(at, Station.ROLE_COLORS.get(event.role, Color.WHITE))

	if state.get("lost", "") != "" and _prev.get("lost", "") == "":
		_doom = DOOM_TIME
		Sfx.set_loop("engine", false)
		Sfx.set_loop("hum", false)
	_science_numbers(state)
	_weather(state)
	_burn_shove(state)
	_grades(state)
	var punctured: bool = int(state.get("dust", {}).get("hits", 0)) > int(_prev.get("dust", {}).get("hits", 0))
	if not punctured and float(state.get("fuel", 0)) < float(_prev.get("fuel", 0)) - 1.0:
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


## Sounds + shakes for radiation storms, blackouts and dust impacts.
func _weather(state: Dictionary) -> void:
	var cme: String = state.get("cme", {}).get("phase", "")
	var shields: bool = state.get("cme", {}).get("shields", false)
	if shields and not _shields:
		Sfx.play("orbit", 0.8)
	_shields = shields
	if cme != _cme_phase:
		if cme == "warning":
			_siren_timer = 0.0
		elif cme == "wave":
			Sfx.play("wave")
			_shake = maxf(_shake, 0.8)
			_alarm = 1.0
		_cme_phase = cme
	if float(state.get("blackout", 0)) > 0.0 and float(_prev.get("blackout", 0)) <= 0.0:
		_flicker = 2.0
		Sfx.play("brownout")
		Sfx.play("explode", 0.5, -6.0)
	var meteor: Dictionary = state.get("meteor", {})
	_meteor_left = float(meteor.get("time_left", -1.0))
	_meteor_y = float(meteor.get("y", 135.0))
	if int(meteor.get("seq", 0)) > _meteor_seq:
		_meteor_crash(Vector2(HULL_FRONT - 4.0, _meteor_y))
	_meteor_seq = int(meteor.get("seq", 0))
	var dust: Dictionary = state.get("dust", {})
	_dust_phase = dust.get("phase", "")
	var hits := int(dust.get("hits", 0)) - int(_prev.get("dust", {}).get("hits", 0))
	for i in maxi(hits, 0):
		# Impact somewhere on the hull's front half.
		var at := Vector2(_rng.randf_range(250, 455), [18.0, 252.0][_rng.randi() % 2])
		if _rng.randf() < 0.4:
			at = Vector2(_rng.randf_range(440, 462), _rng.randf_range(40, 230))
		Sfx.play("impact", _rng.randf_range(0.85, 1.15))
		_shake = maxf(_shake, 0.7)
		_rings.append({p = at, r = 2.0, speed = 40.0, life = 0.3, max = 0.3, col = Color.WHITE})
		for k in 18:
			_spark(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30, 90),
					[Color.WHITE, Color("ffd890"), Color("c8b89a")][k % 3], 0.45, 0.0)


## The big one: rock meets hull. Flash, heavy shake, crunch, debris, hull breach smoke.
func _meteor_crash(at: Vector2) -> void:
	_meteor_left = -1.0
	_flash = 1.0
	_shake = maxf(_shake, 1.8)
	_alarm = 1.0
	Sfx.play("impact", 0.55)
	Sfx.play("explode", 0.45)
	Sfx.play("wave", 0.7, -4.0)
	Sfx.play("creak", 0.8)
	_rings.append({p = at, r = 3.0, speed = 160.0, life = 0.4, max = 0.4, col = Color.WHITE})
	_rings.append({p = at, r = 2.0, speed = 90.0, life = 0.5, max = 0.5, col = FIRE[1]})
	for i in 40:
		var dir := Vector2.from_angle(_rng.randf_range(PI * 0.5, PI * 1.5))  # sprays back into the ship
		_spark(at, dir * _rng.randf_range(40, 160), FIRE[i % FIRE.size()], _rng.randf_range(0.4, 0.9), 60.0,
				2 if i % 3 == 0 else 1)
	for i in 16:  # rock and hull fragments bouncing off into space
		var dir := Vector2.from_angle(_rng.randf_range(-PI * 0.45, PI * 0.45))
		_spark(at, dir * _rng.randf_range(30, 110), [Color("8a7a66"), Color("5e5348"), Color("b0a490")][i % 3],
				_rng.randf_range(0.8, 1.5), 0.0, 2)
	for i in 10:
		_smoke(at + Vector2(_rng.randf_range(-12, 2), _rng.randf_range(-6, 6)), 1.8)


func _science_numbers(state: Dictionary) -> void:
	var stored := float(state.get("science_stored", 0.0)) - float(_prev.get("science_stored", 0.0))
	var sent := float(state.get("science_sent", 0.0)) - float(_prev.get("science_sent", 0.0))
	if stored + maxf(sent, 0.0) > 5.0:   # a burst (observation / storm data), not the slow trickle
		_float_text(_station_pos("scientist") + Vector2(0, 18), "+%d SCIENCE" % roundi(stored + maxf(sent, 0.0)), Color("d0a8ff"))
	_sent_acc += maxf(sent, 0.0)
	_lost_acc += maxf(float(state.get("science_lost", 0.0)) - float(_prev.get("science_lost", 0.0)), 0.0)


## BRACE klaxon while a burn spools up; whoosh + dust kicked up under everyone when it fires.
func _burn_shove(state: Dictionary) -> void:
	var brace := float(state.get("brace", {}).get("time_left", -1.0))
	if brace >= 0.0 and _brace < 0.0:
		_klaxon = 0.0   # sound right away
	_brace = brace
	var shove: Dictionary = state.get("shove", {})
	var seq := int(shove.get("seq", 0))
	if _shove_seq != -1 and seq > _shove_seq:
		var dir := Vector2(float(shove.get("x", 0.0)), float(shove.get("y", 0.0)))
		var strength := float(shove.get("strength", 1.0))
		Sfx.play("whoosh", 1.2 - 0.2 * strength)
		_shake = maxf(_shake, 0.3 + 0.3 * strength)
		if _crew:
			for member in _crew.get_children():
				if member is CrewMember and member.docked_station() == null:
					for i in 6:   # skid dust trailing behind the slide
						_dust.append({p = member.position + Vector2(_rng.randf_range(-3, 3), -1),
								v = -dir * _rng.randf_range(10, 30) + Vector2(_rng.randf_range(-6, 6), -4),
								life = 0.5, max = 0.5})
	_shove_seq = seq


## A stamp over the station for every newly graded ticket (sim grade_log, so all peers agree).
func _grades(state: Dictionary) -> void:
	var entries: Array = state.get("grade_log", [])
	var seq := int(state.get("grades", {}).get("seq", 0))
	if _grade_seq == -1:
		_grade_seq = seq   # don't replay the old ones when joining
		return
	for g: Dictionary in entries:
		if int(g.seq) <= _grade_seq:
			continue
		var look: Array = GRADE_LOOK.get(str(g.grade), ["", Color.WHITE])
		var at := _station_pos(str(g.role)) + Vector2(0, -30)
		_stamps.append({p = at, text = look[0], col = look[1], streak = int(g.streak), life = 1.4, max = 1.4})
		if g.grade == "perfect":
			Sfx.play("perfect", 1.0 + minf(int(g.streak), 8) * 0.04)   # climbs with the streak
	_grade_seq = maxi(_grade_seq, seq)


func _float_text(at: Vector2, text: String, col: Color) -> void:
	_texts.append({p = at, text = text, col = col, life = 1.6})


## One blast of the final chain: fire, smoke, a shockwave ring; sounds thinned out so they don't clip.
func _doom_explosion(at: Vector2, k: float) -> void:
	_doom_boom -= 1.0
	if _doom_boom <= 0.0:
		_doom_boom = 2.0
		Sfx.play("explode", _rng.randf_range(0.5, 0.9))
		if _rng.randf() < 0.4:
			Sfx.play("impact", 0.5, -4.0)
	for i in int(18 + 20 * k):
		_spark(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40, 140 + 80 * k),
				FIRE[i % FIRE.size()], _rng.randf_range(0.4, 0.9), 40.0, 2 if i % 3 == 0 else 1)
	for i in 4:
		_smoke(at + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), 1.6)
	_rings.append({p = at, r = 3.0, speed = 110.0 + 80.0 * k, life = 0.35, max = 0.35, col = FIRE[1]})
	_flash = maxf(_flash, 0.25 * k)


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

	_flash = maxf(_flash - delta * 2.5, 0.0)
	_sci_timer -= delta
	if _sci_timer <= 0.0:
		_sci_timer = 1.0
		if _sent_acc >= 1.0:
			_float_text(_station_pos("comms") + Vector2(0, 18), "+%d SENT HOME" % roundi(_sent_acc), Color("8cffb0"))
			_sent_acc = 0.0
		if _lost_acc >= 1.0:
			_float_text(_station_pos("scientist") + Vector2(0, 28), "-%d LOST (STORAGE FULL)" % roundi(_lost_acc), Color("ff6a5a"))
			_lost_acc = 0.0
	if _brace >= 0.0:
		_brace = maxf(_brace - delta, 0.0)
		_klaxon -= delta
		if _klaxon <= 0.0:
			_klaxon = 0.5
			Sfx.play("klaxon")
	for i in range(_stamps.size() - 1, -1, -1):
		_stamps[i].life -= delta
		if _stamps[i].life <= 0.0:
			_stamps.remove_at(i)
	for i in range(_texts.size() - 1, -1, -1):
		var ft: Dictionary = _texts[i]
		ft.life -= delta
		ft.p += Vector2(0, -12.0 * delta)
		if ft.life <= 0.0:
			_texts.remove_at(i)
	if _doom > 0.0:
		_doom -= delta
		var k := 1.0 - _doom / DOOM_TIME           # 0 -> 1: more, bigger, faster
		_shake = maxf(_shake, 0.8 + 1.4 * k)
		_alarm = 1.0
		if _every("doom", lerpf(0.22, 0.06, k), delta):
			var at := Vector2(_rng.randf_range(HULL.position.x + 20, HULL.end.x - 20), _rng.randf_range(HULL.position.y + 20, HULL.end.y - 20))
			_doom_explosion(at, k)
		if _doom <= 0.0:
			_flash = 1.0
			Sfx.play("explode", 0.35)
			Sfx.play("wave", 0.5)
	if _meteor_left > 0.0:
		_meteor_left -= delta
		if _meteor_left < METEOR_SHOW:
			_proximity -= delta
			if _proximity <= 0.0:   # proximity alarm: faster as it closes in
				_proximity = lerpf(0.12, 0.45, _meteor_left / METEOR_SHOW)
				Sfx.play("remind", 1.6, -2.0)
			if _every("meteor_trail", 0.03, delta):
				var p := _meteor_pos()
				_spark(p + Vector2(_rng.randf_range(-3, 3), -6), Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-70, -30)),
						[Color("ffd890"), Color("c8b89a"), Color("8a7a66")][_rng.randi() % 3], 0.4)
	_tick_reminders(delta)
	if _cme_phase == "warning":
		_siren_timer -= delta
		if _siren_timer <= 0.0:
			_siren_timer = 1.6
			Sfx.play("siren")
	# Comet dust: grains streak past the hull (spawned only during the stream).
	if _dust_phase in ["stream", "flying"] and _every("grain", 0.03, delta):
		_grains.append(Vector3(490.0, _rng.randf_range(0, 270), _rng.randf_range(260, 520)))
	for i in range(_grains.size() - 1, -1, -1):
		var g := _grains[i]
		g.x -= g.z * delta
		if g.x < -20.0:
			_grains.remove_at(i)
		else:
			_grains[i] = g

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
				# Footstep SOUNDS are CrewMember's (_footsteps); this is only the dust. Nobody on a spacewalk.
				if not member.eva and member.position.distance_to(last) > 0.3 						and _every("dust_%d" % member.get_instance_id(), 0.14 if member.running else 0.22, delta):
					_dust.append({p = member.position + Vector2(_rng.randf_range(-2, 2), -1),
							v = Vector2(_rng.randf_range(-6, 6), -3), life = 0.35, max = 0.35})
				seen[member] = member.position
		_crew_last = seen  # forget crew that left

	_step(_parts, delta)
	_step(_dust, delta)
	for ring in _rings:
		ring.r += ring.speed * delta
		ring.life -= delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.life > 0.0)

	for i in _stars.size():  # space streams past: the ship is flying to the right
		var s := _stars[i]
		s.x -= s.z * delta
		if s.x < -4.0:
			s.x += 488.0
		_stars[i] = s
	if _game:
		var amp := ceilf(_shake * 4.0)
		var shake := Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1)) * amp if amp > 0 else Vector2.ZERO
		var bob := Vector2(sin(_t * 0.7) * 0.6, sin(_t * 1.1) * 1.2)  # drifting in free fall
		_game.position = bob + shake
	queue_redraw()
	if _under:
		_under.queue_redraw()


func _tick_reminders(delta: float) -> void:
	var most_urgent := 1.0
	for id in _ticket_time:
		var t: Array = _ticket_time[id]
		t[0] = maxf(t[0] - delta, 0.0)
		most_urgent = minf(most_urgent, t[0] / t[1])
	if most_urgent >= REMIND_AT:
		_remind_timer = 0.0
		return
	_remind_timer -= delta
	if _remind_timer <= 0.0:
		var k := most_urgent / REMIND_AT          # 1 = just crossed 75%, 0 = out of time
		_remind_timer = lerpf(0.22, 0.9, k)
		Sfx.play("remind", 1.0 + (1.0 - k) * 0.5)


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
	# Stars live in screen space (counter the ship's bob/shake) and hide behind the hull.
	var cam := -_game.position if _game else Vector2.ZERO
	var off := UiKit.world_offset           # the camera moves the map down; stars still fill the whole screen
	for s in _stars:
		var p := Vector2(s.x, s.y)
		if HULL.has_point(p - off):
			continue
		var a := 0.3 + s.z / 40.0
		var streak := 1.0 + (2.0 if s.z > 20.0 else 0.0)
		draw_rect(Rect2(cam - off + p, Vector2(streak, 1)), Color(0.85, 0.9, 1.0, a))

	# Radiation shield: a shimmering bubble around the hull while it is up (brighter in the wave).
	if _shields:
		var strong := 1.0 if _cme_phase == "wave" else 0.45
		var pts := PackedVector2Array()
		for i in 65:
			var a := TAU * i / 64.0
			var wob := 1.0 + 0.012 * sin(a * 9.0 + _t * 5.0)
			pts.append(Vector2(243, 135) + Vector2(cos(a) * 236.0, sin(a) * 130.0) * wob)
		draw_polyline(pts, Color(0.45, 0.85, 1.0, (0.35 + 0.2 * sin(_t * 6.0)) * strong), 2.0)
		draw_polyline(pts, Color(0.8, 0.95, 1.0, 0.25 * strong), 1.0)
	# Incoming meteoroid (only while the ship is dead in space).
	if _meteor_left > 0.0 and _meteor_left < METEOR_SHOW:
		var mp := cam + _meteor_pos()
		var size := 7.0 + 3.0 * (1.0 - _meteor_left / METEOR_SHOW)
		draw_circle(mp + Vector2(-10, 14), size, Color(0, 0, 0, 0.3))   # its shadow on the hull
		var pts := PackedVector2Array()
		for i in 9:
			var a := TAU * i / 9.0 + _t * 2.0
			var r := size * (0.75 + 0.25 * sin(i * 2.7))
			pts.append(mp + Vector2(cos(a), sin(a)) * r)
		draw_circle(mp, size + 3.0, Color(1.0, 0.7, 0.4, 0.15))
		draw_colored_polygon(pts, Color("6e6152"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("a8987e"), 1.0)
		draw_rect(Rect2(mp + Vector2(-2, -2), Vector2(2, 2)), Color("4a4038"))
	for g in _grains:
		var gp := Vector2(g.x, g.y)
		if not HULL.has_point(gp - off):
			draw_rect(Rect2(cam - off + gp, Vector2(g.z / 40.0, 1)), Color(0.85, 0.78, 0.65, 0.75))

	# Engines: layered flickering flames + glow at both nozzles, longer while burning.
	for nozzle: Vector2 in NOZZLES:
		var length := 7.0 + 2.0 * sin(_t * 23.0 + nozzle.y) + _rng.randf_range(-1.0, 1.0)
		if _burn > 0.0:
			length += 8.0
		draw_circle(nozzle + Vector2(-2, 0), 7.0, Color(1.0, 0.55, 0.2, 0.12 + 0.05 * sin(_t * 9.0)))
		var layers := [[3.0, 1.0, FIRE[2]], [2.0, 0.75, FIRE[1]], [1.0, 0.45, FIRE[0]]]
		for layer in layers:
			var half: float = layer[0]
			var l: float = length * layer[1]
			draw_colored_polygon(PackedVector2Array([nozzle + Vector2(0, -half), nozzle + Vector2(0, half + 1),
					nozzle + Vector2(-l, 0.5)]), layer[2])
	# Reactor in the Engine Room breathes.
	var glow := 0.5 + 0.5 * sin(_t * 2.4)
	draw_arc(ENGINE_CORE, 15.0 + glow, 0, TAU, 32, Color(1.0, 0.7, 0.25, 0.15 + 0.15 * glow), 2.0)

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
	for ft in _texts:
		var w := UiFont.width(ft.text, 8)
		var a := clampf(ft.life / 0.5, 0.0, 1.0)
		var pos := ((ft.p as Vector2) - Vector2(w / 2.0, 0)).round()
		draw_string_outline(UiFont.font(), pos, ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 2, Color(0, 0, 0, 0.8 * a))
		draw_string(UiFont.font(), pos, ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color(ft.col, a))
	_draw_brace(margin)
	_draw_stamps()
	if _flash > 0.0:  # meteoroid impact
		draw_rect(margin, Color(1.0, 0.95, 0.85, 0.7 * _flash * _flash))


## Burn spooling up: amber hazard bands at the screen edges + a blinking "BRACE!" tag over everyone
## who is not holding on (docked crew are safe).
func _draw_brace(margin: Rect2) -> void:
	if _brace < 0.0:
		return
	var on := fmod(_t, 0.3) < 0.18
	var amber := Color(1.0, 0.75, 0.15, 0.35 if on else 0.15)
	for x in range(int(margin.position.x), int(margin.end.x), 12):   # striped bands top + bottom
		draw_rect(Rect2(x + (int(_t * 30.0) % 12), margin.position.y + 6, 6, 3), amber)
		draw_rect(Rect2(x + (int(_t * 30.0) % 12), margin.end.y - 9, 6, 3), amber)
	if not _crew or not on:
		return
	for member in _crew.get_children():
		if member is CrewMember and member.docked_station() == null:
			var label := "BRACE! %.1f" % _brace
			var w := roundf(UiKit.text_w(label, 7) + 6)
			var r := Rect2(roundf(member.position.x - w / 2.0), member.position.y - 46.0, w, 10)   # above prompts
			UiKit.panel(self, r, Color("3a2400"), UiKit.WARN)
			UiKit.text(self, Vector2(r.position.x + 3, r.end.y - 2), label, 7, UiKit.WARN, 0)


## Grade stamps: pop in (whole-pixel bounce), hold, then rise and fade. Streak of 3+ adds "xN".
func _draw_stamps() -> void:
	for s: Dictionary in _stamps:
		var age: float = s.max - s.life
		var hop := roundf(maxf(0.0, 6.0 * (1.0 - age / 0.2)))   # drops in from above
		var rise := roundf(maxf(0.0, (age - 0.8) * 20.0))
		if s.life < 0.3 and fmod(s.life, 0.1) < 0.05:
			continue
		var label: String = s.text
		if int(s.streak) >= 3 and s.text != "MISSED":
			label += "  x%d" % int(s.streak)
		var w := roundf(UiKit.text_w(label, 8) + 8)
		var h := maxf(12.0, UiKit.line_h(8) + 3)
		var p: Vector2 = s.p
		var r := Rect2(clampf(roundf(p.x - w / 2.0), 2.0, 478.0 - w), p.y - hop - rise, w, h)
		UiKit.panel(self, r, UiKit.PANEL_DARK, s.col)
		UiKit.text(self, Vector2(r.position.x + 4, r.end.y - 3), label, 8, s.col, 0)


## Where the meteoroid is now: dives in from above the top-right (seen over the hull in the top-down
## view) and speeds up into the hull's nose.
func _meteor_pos() -> Vector2:
	var k := clampf(_meteor_left / METEOR_SHOW, 0.0, 1.0)
	var e := k * k * 0.6 + k * 0.4   # accelerates towards impact
	return Vector2(HULL_FRONT - 4.0, _meteor_y).lerp(Vector2(470.0, -24.0), e) + Vector2(-60.0, 0.0) * sin(e * PI) 


func _draw_under() -> void:
	for d in _dust:
		var k: float = d.life / d.max
		_under.draw_rect(Rect2(d.p.round(), Vector2(1, 1)), Color(0.75, 0.78, 0.85, 0.5 * k))
