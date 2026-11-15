extends Node2D
## Launch mini-game (between the designer and the cruise). Physics is SIMPLIFIED for play.
##
##   W / S       push / pull your throttle lever (it stays where you leave it)
##   SPACE       separate the spent first stage (when it burns out)
##
## Lift off: thrust must beat weight - heavier ships (vs the rocket's capacity) need more lever.
## Max-Q: speed^2 x air density over the limit builds STRESS -> strained (damage) -> breakup.
## Staging: stage 1 burns out -> press SPACE within 6 s (reminder beeps speed up after 75%);
## every second coasting loses speed. Miss it: the rocket falls back and lands by parachute.
## Orbit at 7.8 km/s. If the rocket runs dry first the spacecraft burns its own fuel; if that
## runs out too, the launch FAILS. Failures: SPACE = new rocket, D = back to the designer.
## Heavy payloads leave little margin: fly them at full throttle and stage fast.
## Result -> cruise: fuel left (spacecraft tank) and damage (stations start offline).
##
## Co-op: the throttle is the AVERAGE of every player's lever, so the crew has to agree.
## The host runs the flight and sends it to everyone; clients send their lever (NetSync style).

const GAME_SCENE := "res://scenes/game/game.tscn"
const DESIGNER_SCENE := "res://scenes/design/designer.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"
const ROCKET_DIR := "res://sprites/rockets/sprites_1x/"
const ROCKETS := {"light": "electron", "medium": "zenit", "heavy": "proton"}

const TARGET_SPEED := 7.8          # km/s, low Earth orbit
const Q_K := 1.25                  # dynamic pressure scale: q > 1 stresses the structure
const AIR_SCALE := 7.5             # km, air density e-folding height
const STRESS_RATE := 4.8
const STRAIN_AT := 0.75            # stress level that damages the ship (but survives)
const ACCEL := 0.34                # km/s^2 per unit of (thrust/weight - gravity)
const STAGE1_BURN := 6.5           # % of stage fuel per second at full throttle
const STAGE2_BURN := 8.5
const SHIP_BURN := 6.0
const STAGE_SPLIT := 0.45          # bottom part of the sprite that is the first stage
const LEVER_SPEED := 0.9           # lever travel per second while held
const STAGE_WINDOW := 6.0          # seconds to press SPACE after stage 1 burns out
const FALL_GRAVITY := 0.9          # km/s^2 while falling back (time compressed)
const CHUTE_ALT := 3.0             # km: parachute opens
const CHUTE_SPEED := 0.45          # km/s descent under the canopy
const NET_SEND := 1.0 / 15.0

const GROUND_Y := 236.0
const PX_PER_KM := 70.0            # close to the ground; the pad leaves the screen quickly

## Shared flight state (plain dictionary: goes over the network unchanged).
var flight := _new_flight()
var levers := {}                   # peer -> 0..1
var roles := {}

var _me := 1
var _lever := 0.0
var _twr1 := 1.4
var _twr2 := 2.0
var _launcher := {}
var _rocket_idle: Texture2D
var _rocket_fire: Texture2D
var _saved_window := {}
var _ui: Node2D
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _send_timer := 0.0
var _ready_peers := {}
var _host_ready := false
var _prev := {}
var _shake := 0.0
var _kick := 0.0
var _parts: Array[Dictionary] = []
var _clouds: Array[Vector3] = []   # x, altitude km, size
var _stars: Array[Vector3] = []
var _dropped := {}                 # falling first stage: {y, vy, rot}
var _banner := ""
var _banner_time := 0.0
var _finished := false
var _remind_timer := 0.0
var _fall_view := 0.0   # 0 = normal camera, 1 = following the falling rocket
var _font: Font
var _tutorial: Tutorial


static func _new_flight() -> Dictionary:
	return {
		phase = "countdown",   # countdown, pad, ascent, meco, stage2, orbit, failed
		clock = 3.99, alt = 0.0, speed = 0.0, stage = 1, stage_fuel = 100.0, ship_fuel = 100.0,
		stress = 0.0, q = 0.0, strained = false, damage = 0, throttle = 0.0, coast = 0.0,
		vy = 0.0, chute = false,
		msg = "", msg_seq = 0, fail = "", hint = "", attempt = 0,
	}


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	Sfx.set_loop("rocket", false)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Controls.ensure_actions()
	_font = UiFont.font()
	_rng.randomize()
	var design: Dictionary = DesignRules.chosen if not DesignRules.chosen.is_empty() else DesignRules.new_design()
	var ev := DesignRules.evaluate(design)
	_launcher = ev.launcher if not ev.launcher.is_empty() else DesignRules.data().stats.launchers[1]
	# Thrust-to-weight from how close the ship is to the rocket's limit.
	var margin := clampf(1.0 - ev.mass / float(_launcher.capacity_kg), 0.0, 0.6)
	_twr1 = 1.3 + margin * 0.5
	_twr2 = 1.6 + margin * 1.2   # a heavy payload makes the upper stage sluggish
	var sprite: String = ROCKETS.get(_launcher.get("id", "medium"), "zenit")
	_rocket_idle = load(ROCKET_DIR + sprite + "-idle.png")
	_rocket_fire = load(ROCKET_DIR + sprite + ".png")

	var sky_rng := RandomNumberGenerator.new()
	sky_rng.seed = 5
	for i in 70:
		_stars.append(Vector3(sky_rng.randi_range(0, 479), sky_rng.randi_range(0, 269), sky_rng.randf() * TAU))
	for i in 9:
		_clouds.append(Vector3(sky_rng.randi_range(-40, 480), sky_rng.randf_range(1.2, 9.0), sky_rng.randi_range(2, 4)))

	_me = Network.my_id() if Network.is_in_room() else 1
	roles = CrewRoles.assign(Network.players.keys() if Network.is_in_room() else [1])
	if Network.is_in_room():
		Network.room_closed.connect(func(_r: String) -> void: get_tree().change_scene_to_file(JOIN_SCENE))
		Network.room_changed.connect(func() -> void:
			roles = CrewRoles.assign(Network.players.keys())
			for id in levers.keys():
				if not roles.has(id):
					levers.erase(id))
		multiplayer.peer_disconnected.connect(func(id: int) -> void: _ready_peers.erase(id))
		if not Network.is_host():
			_client_ready.rpc_id(1)

	var layer := CanvasLayer.new()  # UI does not shake
	add_child(layer)
	_ui = Node2D.new()
	_ui.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	PauseMenu.attach(self, "ABORT TO MAIN MENU")
	_tutorial = Tutorial.attach(self, "launch", [
		{title = "Fly the rocket", rect = Rect2(410, 50, 56, 192),
		 body = "W / S push and pull the throttle lever. In co-op the rocket uses the AVERAGE of everyone's levers."},
		{title = "Lift off", rect = Rect2(410, 50, 56, 192),
		 body = "Push past the LIFT mark to leave the pad. A heavy ship needs more throttle - and more fuel."},
		{title = "Max-Q", rect = Rect2(6, 8, 150, 82),
		 body = "Too fast in thick air builds STRESS. Yellow mark = damage (a station starts the cruise broken), full bar = breakup. Throttle down when it rises."},
		{title = "Staging",
		 body = "When stage 1 is empty, press SPACE within 6 s to drop it. Miss it and the rocket falls back to Earth on its parachute."},
		{title = "Orbit", rect = Rect2(6, 8, 150, 82),
		 body = "Reach 7.8 km/s. If the rocket runs dry first, the spacecraft burns its own fuel - fuel you will miss on the way to Mars."},
	])
	Sfx.set_loop("rocket", true)
	Sfx.tune_loop("rocket", -80.0)


func _is_host() -> bool:
	return not Network.is_in_room() or Network.is_host()


# --- per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_read_lever(delta)
	levers[_me] = _lever
	# The host's open tutorial holds the countdown (offline it pauses the whole flight).
	var held: bool = _tutorial.is_open() and (flight.phase == "countdown" or not Network.is_in_room())
	if _is_host() and not held:
		_simulate(delta)
		_on_flight(flight)
	var blocked := Tutorial.is_blocking()
	if not blocked and Input.is_action_just_pressed(Controls.action("p1", "interact")) and flight.phase in ["meco", "failed"]:
		if not _is_host():
			_request_stage.rpc_id(1)
		elif flight.phase == "meco":
			_stage()
		else:
			_retry()
	if not blocked and flight.phase == "failed" and Input.is_action_just_pressed(Controls.action("p1", "right")):
		if _is_host():
			_redesign()
		else:
			_request_redesign.rpc_id(1)
	_network(delta)
	_effects(delta)
	queue_redraw()
	_ui.queue_redraw()


func _read_lever(delta: float) -> void:
	if _finished or Tutorial.is_blocking():
		return
	var before := _lever
	if Input.is_action_pressed(Controls.action("p1", "up")):
		_lever = minf(_lever + LEVER_SPEED * delta, 1.0)
	if Input.is_action_pressed(Controls.action("p1", "down")):
		_lever = maxf(_lever - LEVER_SPEED * delta, 0.0)
	if floori(before * 10.0) != floori(_lever * 10.0):
		Sfx.play("lever", 0.8 + _lever * 0.6)  # a click per 10% notch


# --- simulation (host) ------------------------------------------------------------------

func _simulate(dt: float) -> void:
	var f := flight
	var total := 0.0
	for id in roles:
		total += float(levers.get(id, 0.0))
	f.throttle = total / maxf(roles.size(), 1)
	var thr: float = f.throttle
	match f.phase:
		"countdown":
			f.clock -= dt
			if f.clock <= 0.0:
				f.phase = "pad"
				_say("IGNITION - PUSH THE LEVER UP")
		"pad":
			_burn_stage(thr * 0.5, dt)  # hold-down clamps: fuel burns, rocket stays
			if thr * _twr1 > 1.0:
				f.phase = "ascent"
				_say("LIFTOFF!")
			elif f.stage_fuel <= 0.0:
				f.phase = "meco"
		"ascent", "stage2":
			var twr: float = _twr1 if f.stage == 1 else _twr2
			if f.stage_fuel <= 0.0 and f.stage == 2:
				# Rocket empty before orbit: the spacecraft's own engine finishes the job.
				twr *= 0.6
				f.ship_fuel = maxf(f.ship_fuel - SHIP_BURN * thr * dt, 0.0)
				if f.ship_fuel <= 0.0:
					_fail("OUT OF FUEL - FELL BACK TO EARTH",
							"Too heavy for this rocket, or fuel wasted: full throttle and fast staging.")
					return
			else:
				_burn_stage(thr, dt)
			_fly(thr * twr, dt)
			_max_q(dt)
			if f.phase == "failed":
				return
			if f.phase == "ascent":
				if f.stage_fuel <= 0.0:
					f.phase = "meco"
					f.coast = 0.0
					_say("STAGE 1 EMPTY - PRESS SPACE TO SEPARATE")
			if f.speed >= TARGET_SPEED:
				f.phase = "orbit"
				f.clock = 3.0
				_say("ORBIT REACHED!")
		"meco":
			f.coast += dt
			_fly(0.0, dt)
			_max_q(dt)
			if f.coast >= STAGE_WINDOW and f.phase == "meco":
				# Nobody separated the stage: the dead weight drags the rocket back down.
				f.phase = "falling"
				f.vy = f.speed * clampf(1.0 - f.alt / 320.0, 0.3, 1.0)
				f.speed = 0.0
				_say("STAGE NOT SEPARATED - FALLING!")
		"falling":
			_fall(dt)
		"orbit":
			f.clock -= dt
			_fly(0.0, dt)
			if f.clock <= 0.0 and not _finished:
				_finish()


## Ballistic fall, then the parachute; landing ends the attempt.
func _fall(dt: float) -> void:
	var f := flight
	if not f.chute:
		f.vy -= FALL_GRAVITY * dt
		if f.vy < 0.0 and f.alt <= CHUTE_ALT:
			f.chute = true
			_say("PARACHUTE DEPLOYED")
	else:
		f.vy = lerpf(f.vy, -CHUTE_SPEED, minf(dt * 2.5, 1.0))
	f.alt = maxf(f.alt + f.vy * dt, 0.0)
	if f.alt <= 0.0:
		f.vy = 0.0
		_fail("STAGE NOT SEPARATED - LANDED BY PARACHUTE",
				"Press SPACE within 6 s of stage 1 burnout to drop the empty stage.")


func _burn_stage(thr: float, dt: float) -> void:
	var rate: float = STAGE1_BURN if flight.stage == 1 else STAGE2_BURN
	flight.stage_fuel = maxf(flight.stage_fuel - rate * thr * dt, 0.0)


## thrust = thrust-to-weight now (0 = coasting). Gravity loss fades as the rocket pitches over.
func _fly(thrust: float, dt: float) -> void:
	var gravity := clampf(1.0 - flight.alt / 200.0, 0.12, 1.0)
	flight.speed = maxf(flight.speed + (thrust - gravity) * ACCEL * dt, 0.0)
	var vertical := clampf(1.0 - flight.alt / 320.0, 0.3, 1.0)
	flight.alt += flight.speed * vertical * dt


## Dynamic pressure q = speed^2 x air density. Above the structure's limit, stress builds:
## at STRAIN_AT the ship is damaged (a station starts the cruise offline), at 1.0 it breaks up.
## Fast (light) rockets must throttle down through max-Q; slow heavy ones rarely need to.
func _max_q(dt: float) -> void:
	var q: float = flight.speed * flight.speed * exp(-flight.alt / AIR_SCALE) * Q_K
	flight.q = q
	if q > 1.0:
		flight.stress += (q - 1.0) * STRESS_RATE * dt
	else:
		flight.stress = maxf(flight.stress - 0.25 * dt, 0.0)
	if flight.stress >= STRAIN_AT and not flight.strained:
		flight.strained = true
		flight.damage += 1
		_say("STRUCTURE STRAINED! THROTTLE DOWN")
	if flight.stress >= 1.0:
		_fail("STRUCTURAL BREAKUP AT MAX-Q", "Too fast in thick air: throttle down while the STRESS bar rises.")


func _fail(reason: String, hint: String) -> void:
	flight.phase = "failed"
	flight.fail = reason
	flight.hint = hint
	_say(reason)


## Back to the pad with a fresh rocket (any player presses SPACE after a failure).
func _retry() -> void:
	if flight.phase != "failed":
		return
	var attempt: int = flight.attempt + 1
	flight = _new_flight()
	flight.attempt = attempt


func _stage() -> void:
	if flight.phase != "meco":
		return
	flight.stage = 2
	flight.stage_fuel = 100.0
	flight.phase = "stage2"
	_say("STAGE 2 IGNITION")


func _say(text: String) -> void:
	flight.msg = text
	flight.msg_seq += 1


func _finish() -> void:
	_finished = true
	var result := {fuel_left = roundf(flight.ship_fuel), damage = int(flight.damage)}
	if Network.is_in_room():
		_to_cruise.rpc(result)
	else:
		_to_cruise(result)


# --- network ---------------------------------------------------------------------------

func _network(delta: float) -> void:
	if not Network.is_in_room():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = NET_SEND
	if Network.is_host():
		for id: int in _ready_peers:
			_recv_flight.rpc_id(id, flight, levers)
	elif _host_ready:
		_send_lever.rpc_id(1, _lever)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if Network.is_host():
		_ready_peers[multiplayer.get_remote_sender_id()] = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_lever(value: float) -> void:
	if Network.is_host():
		levers[multiplayer.get_remote_sender_id()] = clampf(value, 0.0, 1.0)


@rpc("any_peer", "call_remote", "reliable")
func _request_stage() -> void:
	if not Network.is_host():
		return
	if flight.phase == "meco":
		_stage()
	else:
		_retry()


@rpc("any_peer", "call_remote", "reliable")
func _request_redesign() -> void:
	if Network.is_host():
		_redesign()


func _redesign() -> void:
	if Network.is_in_room():
		_to_designer.rpc()
	else:
		_to_designer()


@rpc("authority", "call_local", "reliable")
func _to_designer() -> void:
	_finished = true
	DesignRules.chosen.erase("launch")
	get_tree().change_scene_to_file(DESIGNER_SCENE)


@rpc("authority", "call_remote", "unreliable_ordered")
func _recv_flight(state: Dictionary, all_levers: Dictionary) -> void:
	_host_ready = true
	flight = state
	for id in all_levers:
		if id != _me:
			levers[id] = all_levers[id]
	_on_flight(flight)


@rpc("authority", "call_local", "reliable")
func _to_cruise(result: Dictionary) -> void:
	_finished = true
	if DesignRules.chosen.is_empty():
		DesignRules.chosen = DesignRules.new_design()
	DesignRules.chosen.launch = result
	get_tree().change_scene_to_file(GAME_SCENE)


# --- reacting to the flight (every peer) -------------------------------------------------

## Sounds, banners and kicks from changes between flight snapshots.
func _on_flight(f: Dictionary) -> void:
	if _prev.is_empty():
		_prev = f.duplicate()
	if f.phase == "countdown" and ceili(f.clock) != ceili(_prev.clock):
		Sfx.play("countdown")
		_banner = str(ceili(f.clock)) if ceili(f.clock) > 0 else ""
		_banner_time = 0.9
	if f.msg_seq != _prev.msg_seq:
		_banner = f.msg
		_banner_time = 2.5
	if f.phase != _prev.phase:
		match f.phase:
			"pad":
				Sfx.play("go")
			"ascent":
				Sfx.play("ignition")
				_kick = 1.0
			"meco":
				Sfx.play("alarm")
				_remind_timer = 1.0
			"falling":
				Sfx.play("brownout")
				_kick = 1.0
			"stage2":
				Sfx.play("stage")
				_kick = 0.8
				_dropped = {y = 0.0, vy = 10.0, rot = 0.0}
			"orbit":
				Sfx.play("orbit")
			"failed":
				if str(f.fail).begins_with("STRUCTURAL"):
					Sfx.play("explode")
					Sfx.play("explode", 0.6)
					_kick = 2.0
					_explode_rocket()
				elif f.chute:
					Sfx.play("toggle", 0.5)  # thud on the ground
					_kick = 0.6
					_landing_dust()
				else:
					Sfx.play("explode")
					_kick = 1.5
			"countdown":
				_dropped = {}
				_parts.clear()
				_banner = "NEW ROCKET ON THE PAD"
				_banner_time = 2.0
	if f.chute and not _prev.get("chute", false):
		Sfx.play("chute")
		_kick = 0.5
	if f.damage > _prev.damage:
		Sfx.play("creak")
		Sfx.play("toggle", 0.5)
		_kick = 1.4
	elif f.stress > 0.5 and _prev.stress <= 0.5:
		Sfx.play("creak", 1.2)
	_prev = f.duplicate()


# --- effects -----------------------------------------------------------------------------

func _stage_reminders(delta: float) -> void:
	if flight.phase != "meco" or _tutorial.is_open():
		return
	var k: float = clampf(flight.coast / STAGE_WINDOW, 0.0, 1.0)
	_remind_timer -= delta
	if _remind_timer <= 0.0:
		_remind_timer = 0.25 if k >= 0.75 else 0.8
		Sfx.play("remind", 1.0 + k * 0.5)


func _landing_dust() -> void:
	for i in 40:
		_parts.append({p = Vector2(240 + _rng.randf_range(-20, 20), GROUND_Y - 2),
				v = Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-30, -5)),
				life = 1.4, max = 1.4, col = Color("b8a888"), size = _rng.randi_range(2, 5), smoke = true})


func _effects(delta: float) -> void:
	_stage_reminders(delta)
	var want := 1.0 if flight.phase == "falling" or (flight.phase == "failed" and flight.chute) else 0.0
	_fall_view = move_toward(_fall_view, want, delta * 1.5)
	var thr: float = flight.throttle
	var burning := _engine_on()
	var air := clampf(1.0 - flight.alt / 60.0, 0.0, 1.0)
	_kick = maxf(_kick - delta * 1.5, 0.0)
	_banner_time = maxf(_banner_time - delta, 0.0)
	var target_shake: float = (thr * 1.6 if burning else 0.0) * (0.35 + 0.65 * air) + flight.stress * 3.0 + _kick * 3.0
	_shake = lerpf(_shake, target_shake, minf(delta * 8.0, 1.0))
	position = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake

	# Engine roar follows throttle; thins out with the air.
	var loud := thr if burning else 0.0
	Sfx.tune_loop("rocket", -30.0 + loud * 30.0 - (1.0 - air) * 8.0 if loud > 0.01 else -80.0, 0.7 + thr * 0.5)

	var nozzle := _nozzle()
	if burning:
		for i in int(2 + thr * 6):
			_parts.append({p = nozzle + Vector2(_rng.randf_range(-4, 4), _flame_len() * 0.8),
					v = Vector2(_rng.randf_range(-20, 20), _rng.randf_range(60, 140)),
					life = _rng.randf_range(0.15, 0.4), max = 0.4, col = [Color("fff3a0"), Color("ffc640"), Color("ff7a2a")][i % 3], size = 1 if i % 2 else 2, smoke = false})
		# Smoke billows off the pad and trails in the lower atmosphere.
		var ground: float = GROUND_Y + flight.alt * PX_PER_KM
		if ground < 300.0 and thr > 0.2:
			for i in 3:
				_parts.append({p = Vector2(240 + _rng.randf_range(-10, 10), minf(ground, nozzle.y + 20)),
						v = Vector2(_rng.randf_range(-90, 90), _rng.randf_range(-25, 5)),
						life = 1.6, max = 1.6, col = Color("c8ccd8"), size = _rng.randi_range(3, 6), smoke = true})
		elif air > 0.3 and _rng.randf() < 0.5:
			_parts.append({p = nozzle + Vector2(0, _flame_len()), v = Vector2(_rng.randf_range(-6, 6), 90),
					life = 1.2, max = 1.2, col = Color("aeb4c4"), size = 3, smoke = true})
	var scroll: float = flight.speed * 40.0 * (0.3 + air)
	var i := _parts.size() - 1
	while i >= 0:
		var p: Dictionary = _parts[i]
		p.life -= delta
		if p.life <= 0.0:
			_parts.remove_at(i)
		else:
			p.p += (p.v + Vector2(0, scroll if p.smoke else 0.0)) * delta
			if p.smoke:
				p.v *= 1.0 - minf(delta * 1.5, 1.0)
		i -= 1
	if not _dropped.is_empty():
		_dropped.vy += 60.0 * delta
		_dropped.y += _dropped.vy * delta
		_dropped.rot += delta * 0.6
		if _dropped.y > 400.0:
			_dropped = {}


func _explode_rocket() -> void:
	var at := Vector2(240, _rocket_bottom() - _rocket_idle.get_height() * 0.4)
	for i in 120:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_parts.append({p = at + dir * _rng.randf_range(0, 30), v = dir * _rng.randf_range(30, 160),
				life = _rng.randf_range(0.5, 1.4), max = 1.4, smoke = i % 3 == 0,
				col = [Color("fff3a0"), Color("ffc640"), Color("ff7a2a"), Color("ff3b2a"), Color("6b7180")][i % 5],
				size = _rng.randi_range(1, 4)})


func _engine_on() -> bool:
	match flight.phase:
		"pad", "ascent":
			return flight.stage_fuel > 0.0 and flight.throttle > 0.02
		"stage2":
			return flight.throttle > 0.02 and (flight.stage_fuel > 0.0 or flight.ship_fuel > 0.0)
	return false


## Where the rocket's bottom sits on screen: on the pad, then a little higher as it speeds up.
## While falling the view drops so the nose and the parachute stay on screen (rockets are tall).
func _rocket_bottom() -> float:
	var ground: float = GROUND_Y + flight.alt * PX_PER_KM
	var lift := minf(flight.speed * 10.0, 40.0)
	var normal := minf(ground, GROUND_Y - lift)
	if _fall_view <= 0.0:
		return normal
	var falling := minf(ground, 70.0 + float(_rocket_idle.get_height()))
	return lerpf(normal, falling, _fall_view)


func _nozzle() -> Vector2:
	return Vector2(240, _rocket_bottom())


func _flame_len() -> float:
	if not _engine_on():
		return 0.0
	var base: float = 10.0 if flight.stage == 2 else float(_rocket_fire.get_height() - _rocket_idle.get_height())
	return base * (0.45 + flight.throttle * 0.75) * _rng.randf_range(0.85, 1.1)


# --- drawing: world ------------------------------------------------------------------------

func _draw() -> void:
	var alt: float = flight.alt
	var margin := Rect2(-8, -8, 496, 286)
	# Sky: blue -> navy -> black with height, lighter towards the horizon.
	var top := _sky(alt + 25.0)
	var bottom := _sky(alt)
	for band in 18:
		var k := band / 17.0
		draw_rect(Rect2(margin.position.x, margin.position.y + band * 16, margin.size.x, 16), top.lerp(bottom, k))
	var star_a := clampf((alt - 20.0) / 40.0, 0.0, 1.0)
	if star_a > 0.0:
		for s in _stars:
			draw_rect(Rect2(s.x, s.y, 1, 1), Color(1, 1, 1, star_a * (0.5 + 0.5 * maxf(sin(_time * 1.5 + s.z), 0.0))))
	# Earth's curve appears once you are high enough.
	if alt > 45.0:
		var rise := clampf((alt - 45.0) * 0.9, 0.0, 70.0)
		var r := 900.0 - minf(alt, 300.0) * 1.2
		var center := Vector2(240, 270 - rise + r)
		draw_circle(center, r + 6, Color(0.35, 0.65, 1.0, 0.25))
		draw_circle(center, r + 2, Color(0.45, 0.75, 1.0, 0.45))
		draw_circle(center, r, Color("1d4f8f"))
		draw_circle(center, r - 1, Color(0.11, 0.3, 0.55, 0.55))
	# Clouds slide down past the rocket.
	for c in _clouds:
		var y := GROUND_Y - (c.y - alt) * PX_PER_KM * 0.35
		if y > -30 and y < 300:
			_cloud(Vector2(c.x + sin(_time * 0.2 + c.y) * 6.0, y), int(c.z))
	# Speed lines in the air.
	var air := clampf(1.0 - alt / 60.0, 0.0, 1.0)
	var vspeed: float = absf(flight.vy) if flight.phase == "falling" else flight.speed
	var dir := -1.0 if flight.phase == "falling" else 1.0   # lines rush up while falling
	if vspeed > 0.3 and air > 0.0:
		for i in int(minf(vspeed * 6.0, 24.0) * air):
			var x := fmod(i * 97.0 + 13.0, 480.0)
			var y: float = fposmod(i * 61.0 + dir * _time * (300.0 + vspeed * 120.0), 300.0) - 15.0
			draw_rect(Rect2(x, y, 1, 6 + vspeed * 2.0), Color(1, 1, 1, 0.25 * air))
	_draw_ground(alt)
	for p in _parts:
		if p.smoke:
			draw_rect(Rect2(p.p.round(), Vector2(p.size, p.size)), Color(p.col, 0.55 * p.life / p.max))
	_draw_rocket()
	for p in _parts:
		if not p.smoke:
			draw_rect(Rect2(p.p.round(), Vector2(p.size, p.size)), p.col)


func _sky(alt: float) -> Color:
	var stops := [[0.0, Color("8cc4ff")], [10.0, Color("3f7fd0")], [30.0, Color("1a2f6a")],
			[55.0, Color("0b1028")], [90.0, Color("04050c")]]
	for i in stops.size() - 1:
		if alt <= stops[i + 1][0]:
			var k := inverse_lerp(stops[i][0], stops[i + 1][0], alt)
			return (stops[i][1] as Color).lerp(stops[i + 1][1], clampf(k, 0.0, 1.0))
	return stops[-1][1]


func _cloud(at: Vector2, size: int) -> void:
	var c := Color(1, 1, 1, 0.85)
	var s := size * 6
	draw_rect(Rect2(at + Vector2(-s, 0), Vector2(s * 2, s / 2.0)), c)
	draw_rect(Rect2(at + Vector2(-s * 0.6, -s / 3.0), Vector2(s * 1.2, s / 2.0)), c)
	draw_rect(Rect2(at + Vector2(-s * 0.2, -s * 0.55), Vector2(s * 0.7, s / 3.0)), c)
	draw_rect(Rect2(at + Vector2(-s, s / 2.0 - 1), Vector2(s * 2, 1)), Color("c9d6ea"))


func _draw_ground(alt: float) -> void:
	var ground := GROUND_Y + alt * PX_PER_KM
	if ground > 290.0:
		return
	draw_rect(Rect2(-8, ground, 496, 60), Color("3f6b3a"))
	draw_rect(Rect2(-8, ground, 496, 2), Color("5d8f4f"))
	draw_rect(Rect2(196, ground - 2, 88, 4), Color("8a8f9c"))       # pad
	draw_rect(Rect2(196, ground - 2, 88, 1), Color("b5bac6"))
	# Launch tower: a steel truss beside the rocket.
	var tx := 240.0 + _rocket_idle.get_width() / 2.0 + 8.0
	var h := minf(float(_rocket_idle.get_height()) * 0.85, 200.0)
	var col := Color("c0392b")
	draw_rect(Rect2(tx, ground - h, 2, h), col)
	draw_rect(Rect2(tx + 10, ground - h, 2, h), col)
	var y := ground - h
	while y < ground - 9.0:
		draw_line(Vector2(tx + 1, y), Vector2(tx + 11, y + 10), col, 1.0)
		draw_line(Vector2(tx + 11, y), Vector2(tx + 1, y + 10), col, 1.0)
		draw_rect(Rect2(tx, y, 12, 1), col)
		y += 10
	if flight.phase == "countdown":  # access arm until ignition
		draw_rect(Rect2(240 + _rocket_idle.get_width() / 2.0, ground - h * 0.8, tx - 240 - _rocket_idle.get_width() / 2.0, 2), col)


func _draw_rocket() -> void:
	if flight.phase == "failed" and str(flight.fail).begins_with("STRUCTURAL"):
		return  # it is debris now
	var w := float(_rocket_idle.get_width())
	var h := float(_rocket_idle.get_height())
	var bottom := _rocket_bottom()
	var wobble: float = sin(_time * 30.0) * flight.stress * 1.5
	var x := roundf(240.0 - w / 2.0 + wobble)
	var split := roundf(h * (1.0 - STAGE_SPLIT))   # rows above the first stage
	var flame := _flame_len()
	if flight.chute and flight.phase == "falling":
		_draw_parachute(Vector2(240 + wobble, roundf(bottom - h)))
	elif flight.chute:
		_draw_canopy_heap(Vector2(roundf(240 + w / 2.0 + 6), roundf(bottom)))
	if flight.stage == 1:
		if flame > 0.0:
			var fh := float(_rocket_fire.get_height()) - h
			draw_texture_rect_region(_rocket_fire, Rect2(x, roundf(bottom), w, roundf(flame)),
					Rect2(0, h, w, fh))
		draw_texture(_rocket_idle, Vector2(x, roundf(bottom - h)))
	else:
		var top_bottom := bottom
		if flame > 0.0:
			_draw_small_flame(Vector2(240 + wobble, top_bottom), flame)
		draw_texture_rect_region(_rocket_idle, Rect2(x, roundf(top_bottom - split), w, split), Rect2(0, 0, w, split))
		if not _dropped.is_empty():
			var stage_h := h - split
			draw_set_transform(Vector2(240, top_bottom + 20 + _dropped.y + stage_h / 2.0), _dropped.rot, Vector2.ONE)
			draw_texture_rect_region(_rocket_idle, Rect2(-w / 2.0, -stage_h / 2.0, w, stage_h), Rect2(0, split, w, stage_h))
			draw_set_transform(Vector2.ZERO)


## Striped canopy above the nose, lines down to it, swaying a little.
func _draw_parachute(nose: Vector2) -> void:
	var sway := sin(_time * 1.6) * 3.0
	var center := nose + Vector2(sway, -34)
	var r := 28.0
	var segments := 8
	for i in segments:
		var a0 := PI + PI * i / segments
		var a1 := PI + PI * (i + 1) / segments
		var pts := PackedVector2Array([center])
		for k in 5:
			var a := lerpf(a0, a1, k / 4.0)
			pts.append(center + Vector2(cos(a), sin(a) * 0.7) * r)
		draw_colored_polygon(pts, Color("e84a3c") if i % 2 == 0 else Color("f2efe6"))
	draw_rect(Rect2(center.x - r, center.y - 1, r * 2, 2), Color("b8352a"))
	for i in 5:
		var x := lerpf(-r, r, i / 4.0)
		draw_line(center + Vector2(x, 0), nose + Vector2(0, 2), Color("d8dce8"), 1.0)


## After touchdown the canopy collapses on the ground beside the rocket.
func _draw_canopy_heap(at: Vector2) -> void:
	for i in 6:
		var x := at.x + i * 6
		var hgt := 4.0 + (i % 3) * 2.0
		draw_rect(Rect2(x, at.y - hgt, 6, hgt), Color("e84a3c") if i % 2 == 0 else Color("f2efe6"))
	draw_line(at + Vector2(0, -2), at + Vector2(-6, -30), Color("d8dce8"), 1.0)


func _draw_small_flame(at: Vector2, length: float) -> void:
	var colors := [Color("ff7a2a"), Color("ffc640"), Color("fff3a0")]
	for i in 3:
		var half := 3.0 - i
		var l := length * (1.0 - i * 0.28)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-half - 1, 0), at + Vector2(half + 1, 0),
				at + Vector2(0, l)]), colors[i])


# --- drawing: UI (does not shake) ----------------------------------------------------------

func _draw_ui() -> void:
	var f := flight
	var ui := _ui
	# Telemetry, top left.
	var x := 10.0
	var y := 18.0
	_text(ui, Vector2(x, y), "ALT   %6.1f KM" % f.alt, Color.WHITE)
	y += 11
	_text(ui, Vector2(x, y), "SPEED %6.2f KM/S" % f.speed, Color.WHITE)
	y += 4
	_bar(ui, Rect2(x, y, 96, 4), f.speed / TARGET_SPEED, Color("5cf07a"))
	_text(ui, Vector2(x + 100, y + 5), "ORBIT 7.8", Color("9aa4b8"), 7)
	y += 15
	_text(ui, Vector2(x, y), "STAGE %d FUEL" % f.stage, Color("ffc640"))
	y += 4
	_bar(ui, Rect2(x, y, 96, 4), f.stage_fuel / 100.0, Color("ffc640"))
	y += 15
	_text(ui, Vector2(x, y), "SPACECRAFT FUEL", Color("4fd8ff"))
	y += 4
	_bar(ui, Rect2(x, y, 96, 4), f.ship_fuel / 100.0, Color("4fd8ff"))
	y += 15
	var in_q: bool = f.q > 1.0
	var stress_col := Color("ff5050") if f.stress > 0.5 and fmod(_time, 0.3) < 0.15 else Color("ff8a5c")
	_text(ui, Vector2(x, y), "STRESS" + ("  MAX-Q!" if in_q else ""), stress_col if in_q or f.stress > 0.0 else Color("6b7390"))
	y += 4
	_bar(ui, Rect2(x, y, 96, 4), f.stress, Color("ff5050"))
	ui.draw_rect(Rect2(x + roundf(96 * STRAIN_AT), y - 1, 1, 6), Color("ffc640"))  # strain mark
	_text(ui, Vector2(x + 100, y + 5), "BREAKUP", Color("6b7390"), 6)
	if f.damage > 0:
		y += 15
		_text(ui, Vector2(x, y), "DAMAGE x%d" % f.damage, Color("ff5050"))

	_draw_lever(ui)

	if f.phase == "failed":
		_draw_failure(ui)
	elif f.q > 1.0 and fmod(_time, 0.4) < 0.28:
		var t := "MAX-Q: THROTTLE DOWN (S)"
		_text(ui, Vector2(240 - UiFont.width(t, 11) / 2.0, 70), t, Color("ff5050"), 11)

	# Banner, centre top.
	if f.phase == "failed":
		pass
	elif _banner_time > 0.0 and _banner != "":
		var big := 16 if _banner.length() <= 3 else 11
		var w := UiFont.width(_banner, big)
		var a := clampf(_banner_time * 2.0, 0.0, 1.0)
		ui.draw_rect(Rect2(240 - w / 2.0 - 6, 30, w + 12, big + 8), Color(0, 0, 0, 0.55 * a))
		_text(ui, Vector2(240 - w / 2.0, 30 + big + 1), _banner, Color(1, 1, 1, a), big)
	elif f.phase == "meco":
		var left: float = maxf(STAGE_WINDOW - f.coast, 0.0)
		var urgent: bool = f.coast >= STAGE_WINDOW * 0.75
		if fmod(_time, 0.3 if urgent else 0.6) < (0.2 if urgent else 0.4):
			var t := ("SEPARATE NOW!  %.1f" if urgent else "PRESS SPACE: SEPARATE STAGE  %.0f") % left
			_text(ui, Vector2(240 - UiFont.width(t, 11) / 2.0, 46), t, Color("ff5050") if urgent else Color("ffc640"), 11)
	elif f.phase == "pad" and f.throttle * _twr1 <= 1.0:
		var t := "NOT ENOUGH THRUST - LEVER UP (W)"
		_text(ui, Vector2(240 - UiFont.width(t, 10) / 2.0, 46), t, Color("ffc640"), 10)

	var info := "%s  ·  SHIP %d KG / ROCKET LIFTS %d KG  ·  SIMPLIFIED PHYSICS" % [
			str(_launcher.get("name", "")).to_upper(),
			DesignRules.evaluate(DesignRules.chosen if not DesignRules.chosen.is_empty() else DesignRules.new_design()).mass,
			_launcher.get("capacity_kg", 0)]
	_text(ui, Vector2(10, 262), info, Color("9aa4b8"), 7)


func _draw_failure(ui: Node2D) -> void:
	var r := Rect2(90, 118, 300, 86)
	ui.draw_rect(r, Color(0.05, 0.02, 0.03, 0.88))
	ui.draw_rect(r, Color("ff5050"), false, 1.0)
	var title := "LAUNCH FAILED"
	_text(ui, Vector2(240 - UiFont.width(title, 14) / 2.0, r.position.y + 20), title, Color("ff5050"), 14)
	var reason := str(flight.fail)
	_text(ui, Vector2(240 - UiFont.width(reason, 9) / 2.0, r.position.y + 36), reason, Color.WHITE, 9)
	var hint := str(flight.hint)
	_text(ui, Vector2(240 - UiFont.width(hint, 7) / 2.0, r.position.y + 50), hint, Color("9aa4b8"), 7)
	var keys := "SPACE: NEW ROCKET     D: REDESIGN SHIP"
	var blink := 1.0 if fmod(_time, 1.0) < 0.7 else 0.6
	_text(ui, Vector2(240 - UiFont.width(keys, 9) / 2.0, r.position.y + 72), keys, Color(1.0, 0.78, 0.25, blink), 9)


func _draw_lever(ui: Node2D) -> void:
	var base := Vector2(436, 222)
	var track_h := 150.0
	var top := base.y - track_h
	# Housing.
	ui.draw_rect(Rect2(base.x - 22, top - 22, 52, track_h + 40), Color(0.05, 0.06, 0.12, 0.75))
	ui.draw_rect(Rect2(base.x - 22, top - 22, 52, track_h + 40), Color("2c3454"), false, 1.0)
	_text(ui, Vector2(base.x - 18, top - 11), "THROTTLE", Color.WHITE, 7)
	# Too much dynamic pressure: the housing flashes red and an arrow says "down".
	if flight.q > 1.0 and fmod(_time, 0.4) < 0.25:
		ui.draw_rect(Rect2(base.x - 22, top - 22, 52, track_h + 40), Color("ff5050"), false, 2.0)
		ui.draw_colored_polygon(PackedVector2Array([Vector2(base.x - 16, base.y - track_h * _lever - 10),
				Vector2(base.x - 10, base.y - track_h * _lever - 10), Vector2(base.x - 13, base.y - track_h * _lever - 4)]),
				Color("ff5050"))
	ui.draw_rect(Rect2(base.x, top, 4, track_h), Color("1b2034"))
	ui.draw_rect(Rect2(base.x, top, 4, track_h), Color("4a5578"), false, 1.0)
	for i in 11:
		var ny := base.y - track_h * i / 10.0
		ui.draw_rect(Rect2(base.x - 6, ny, 4 if i % 5 else 6, 1), Color("6b7390"))
	if flight.stage == 1:
		var lift_y := base.y - track_h * clampf(1.0 / _twr1, 0.0, 1.0)
		ui.draw_rect(Rect2(base.x - 8, lift_y, 20, 1), Color("5cf07a"))
		_text(ui, Vector2(base.x + 13, lift_y + 3), "LIFT", Color("5cf07a"), 6)
	# Other players' levers: small role-coloured ticks; then the shared throttle.
	for id in levers:
		if id == _me or not roles.has(id):
			continue
		var ly := base.y - track_h * float(levers[id])
		var c := CrewRoles.color(roles[id])
		ui.draw_colored_polygon(PackedVector2Array([Vector2(base.x - 12, ly - 3), Vector2(base.x - 7, ly), Vector2(base.x - 12, ly + 3)]), c)
	var hy := base.y - track_h * _lever
	ui.draw_rect(Rect2(base.x - 9, hy - 4, 22, 8), Color("d8dce8"))
	ui.draw_rect(Rect2(base.x - 9, hy - 4, 22, 8), Color("7a8094"), false, 1.0)
	for g in 3:
		ui.draw_rect(Rect2(base.x - 6 + g * 6, hy - 2, 4, 1), Color("7a8094"))
	ui.draw_rect(Rect2(base.x - 9, hy - 4, 22, 2), CrewRoles.color(roles.get(_me, "all")))
	var label := "%d%%" % roundi(flight.throttle * 100.0)
	_text(ui, Vector2(base.x + 2 - UiFont.width(label, 9) / 2.0, base.y + 14), label, Color.WHITE, 9)
	if roles.size() > 1:
		_text(ui, Vector2(base.x - 20, base.y + 22), "AVG OF CREW", Color("9aa4b8"), 6)
	_text(ui, Vector2(base.x - 18, base.y + (32 if roles.size() > 1 else 24)), "W/S: LEVER", Color("9aa4b8"), 6)


func _bar(ui: Node2D, r: Rect2, fill: float, color: Color) -> void:
	ui.draw_rect(r, Color(0, 0, 0, 0.55))
	ui.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(fill, 0.0, 1.0)), r.size.y)), color)


func _text(ui: Node2D, pos: Vector2, text: String, color: Color, size := 8) -> void:
	ui.draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color(0, 0, 0, color.a * 0.8))
	ui.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
