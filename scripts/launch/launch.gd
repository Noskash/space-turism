extends Node2D
## Launch mini-game (between the designer and the cruise). Physics is SIMPLIFIED for play.
##
##   MOUSE       grab the throttle lever and push it forward / pull it back (it stays where you leave
##               it). It is heavy: it lags behind the hand, clicks into 10% notches and thuds at the
##               ends (spring + damping + detents, `_read_lever`). W / S nudge it as a fallback.
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
const LEVER_SPEED := 0.6           # W / S fallback: how fast the hand target moves
# Lever feel: the handle is pulled towards the hand by a spring, slowed by damping (heavy) and
# held in 10% notches by detents; it cannot move faster than LEVER_MAX_V.
const LEVER_K := 55.0              # spring towards the hand
const LEVER_DAMP := 13.0           # viscous drag
const LEVER_DETENT := 3.2          # notch pull (the hand must lead by ~DETENT/K to leave a notch)
const LEVER_MAX_V := 1.1           # throttle per second
const LEVER_PIVOT := Vector2(426, 236)
const LEVER_LEN := 74.0
const LEVER_IDLE_DEG := -58.0      # arm angle from vertical at 0% (leans back)
const LEVER_FULL_DEG := 30.0       # ... at 100% (pushed forward)
const LEVER_BOX := Rect2(358, 140, 118, 124)
const VIEW_MARGIN := 8             # the world viewport is 8 px bigger on every side (camera shake)
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
var _lever_v := 0.0                # lever velocity (throttle / s)
var _grab := false                 # mouse holds the handle
var _hand := 0.0                   # where the hand wants the lever (0..1)
var _hover := false
var _keys_held := false
# Pixel world: everything in the world is drawn 1:1 into a 496x286 viewport, then shown scaled
# (Nearest) with the post shader on top. The UI layer stays crisp (UiFont text).
var _view: SubViewport
var _w: Node2D
var _sky_mat: ShaderMaterial
var _post_mat: ShaderMaterial
var _screen: Sprite2D
var _cloud_tex: Array[ImageTexture] = []
var _hills_far := PackedFloat32Array()
var _hills_near := PackedFloat32Array()
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
var _log: Array = []               # host: [t, alt, speed, q] every LOG_STEP s (the report's graph)
var _log_timer := 0.0
var _failed_at := -1.0             # every peer: _time when the failure arrived (report fades in after)
const LOG_STEP := 0.2
const LOG_POINTS := 40             # samples sent with the report (over the network)


static func _new_flight() -> Dictionary:
	return {
		phase = "countdown",   # countdown, pad, ascent, meco, stage2, orbit, failed
		clock = 3.99, alt = 0.0, speed = 0.0, stage = 1, stage_fuel = 100.0, ship_fuel = 100.0,
		stress = 0.0, q = 0.0, strained = false, damage = 0, throttle = 0.0, coast = 0.0,
		vy = 0.0, chute = false,
		msg = "", msg_seq = 0, fail = "", hint = "", attempt = 0,
		# Flight recorder for the failure report (LaunchReport): where the speed came from and went.
		time = 0.0, thrust_dv = 0.0, gravity_dv = 0.0, pad_fuel = 0.0, powered_time = 0.0, thr_sum = 0.0,
		peak_q = 0.0, peak_q_alt = 0.0, peak_q_speed = 0.0, peak_q_thr = 0.0,
		meco_alt = 0.0, meco_speed = 0.0, max_alt = 0.0, max_speed = 0.0, max_thr = 0.0,
		report = {},           # filled by _fail: {kind, samples [[t, alt, speed, q]...], numbers}
	}


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())
	UiFont.max_level = 1  # fixed telemetry rows: TEXT SIZE stops at LARGE here


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	UiFont.max_level = 2
	Sfx.set_loop("rocket", false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


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
		_clouds.append(Vector3(sky_rng.randi_range(-40, 480), sky_rng.randf_range(1.2, 9.0), sky_rng.randi_range(0, 2)))
	for i in 3:
		_cloud_tex.append(_make_cloud(28 + i * 16, 9 + i * 4, 40 + i))
	for x in 496 + 1:
		_hills_far.append(26.0 + 14.0 * sin(x * 0.021) + 9.0 * sin(x * 0.057 + 1.3) + 4.0 * sin(x * 0.13))
		_hills_near.append(12.0 + 7.0 * sin(x * 0.034 + 2.0) + 4.0 * sin(x * 0.09 + 0.4) + 2.0 * sin(x * 0.21))
	_build_view()

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
	UiKit.setup_canvas(_ui)
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	PauseMenu.attach(self, "ABORT TO MAIN MENU", "MOUSE OR W/S THROTTLE · SPACE SEPARATE STAGE · J CODEX · H HELP")
	_tutorial = Tutorial.attach(self, "launch", [
		{title = "Fly the rocket", rect = LEVER_BOX,
		 body = "Grab the throttle lever with the mouse: push it forward for more thrust, pull it back for less. It is heavy and clicks into notches. In co-op the rocket uses the AVERAGE of everyone's levers."},
		{title = "Lift off", rect = LEVER_BOX,
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


## PLAYTEST shortcut: skip the launch, start the cruise with a full tank and no damage.
## F2 or click the button (top right). Host / offline only (the host moves everyone).
const SKIP_BUTTON := Rect2(368, 6, 104, 12)


func _input(event: InputEvent) -> void:
	_lever_input(event)
	if _finished or not _is_host() or Tutorial.any_open():
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and SKIP_BUTTON.has_point(_ui.get_local_mouse_position())
	if key or click:
		get_viewport().set_input_as_handled()
		_finished = true
		var result := {fuel_left = 100.0, damage = 0}
		if Network.is_in_room():
			_to_cruise.rpc(result)
		else:
			_to_cruise(result)


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
	_update_shaders()
	_w.queue_redraw()
	_ui.queue_redraw()


# --- pixel world + shaders -------------------------------------------------------------

## World viewport (496x286, Nearest, 1 texel = 1 world pixel): launch_sky shader at the back, the
## world drawing (_draw_world) on top; shown by _screen with the launch_post lighting shader.
func _build_view() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(480 + VIEW_MARGIN * 2, 270 + VIEW_MARGIN * 2)
	_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.snap_2d_transforms_to_pixel = true
	_view.snap_2d_vertices_to_pixel = true
	add_child(_view)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/launch_sky.gdshader")
	var sky := Node2D.new()
	sky.material = _sky_mat
	sky.draw.connect(func() -> void: sky.draw_rect(Rect2(Vector2.ZERO, Vector2(_view.size)), Color.WHITE))
	_view.add_child(sky)
	_w = Node2D.new()
	_w.position = Vector2(VIEW_MARGIN, VIEW_MARGIN)
	_w.draw.connect(_draw_world)
	_view.add_child(_w)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/launch_post.gdshader")
	_screen = Sprite2D.new()
	_screen.centered = false
	_screen.texture = _view.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.material = _post_mat
	_screen.position = Vector2(-VIEW_MARGIN, -VIEW_MARGIN)
	add_child(_screen)


const SUN_AT := Vector2(312, 34)    # world pixels


func _update_shaders() -> void:
	var alt: float = flight.alt
	var off := Vector2(VIEW_MARGIN, VIEW_MARGIN)
	var ground := GROUND_Y + alt * PX_PER_KM
	var top := _sky(alt + 25.0)
	var bottom := _sky(alt)
	_sky_mat.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	_sky_mat.set_shader_parameter("bottom_col", Vector3(bottom.r, bottom.g, bottom.b))
	_sky_mat.set_shader_parameter("haze", clampf(1.0 - alt / 18.0, 0.0, 1.0))
	_sky_mat.set_shader_parameter("horizon_y", minf(ground, 300.0) + VIEW_MARGIN)
	_sky_mat.set_shader_parameter("stars", clampf((alt - 20.0) / 40.0, 0.0, 1.0))
	_sky_mat.set_shader_parameter("sun_pos", SUN_AT + off)
	_sky_mat.set_shader_parameter("time", _time)

	var lights: Array[Vector4] = []
	var colors: Array[Vector4] = []
	if _engine_on():
		var thr: float = flight.throttle
		var at := _nozzle() + Vector2(0, _flame_len() * 0.4) + off
		lights.append(Vector4(at.x, at.y, 50.0 + thr * 70.0, (0.35 + thr * 0.4) * _rng.randf_range(0.9, 1.05)))
		colors.append(Vector4(1.0, 0.55, 0.2, 1.0))
	if ground < 300.0:   # pad floodlights, brightest before liftoff
		var k := 0.32 if flight.phase in ["countdown", "pad"] else 0.18
		for mx in [160.0, 322.0]:
			lights.append(Vector4(mx + off.x, ground - 47.0 + off.y, 80.0, k))
			colors.append(Vector4(1.0, 0.95, 0.78, 1.0))
	var count := mini(lights.size(), 4)
	while lights.size() < 4:
		lights.append(Vector4(0, 0, 1, 0))
		colors.append(Vector4.ZERO)
	_post_mat.set_shader_parameter("light_count", count)
	_post_mat.set_shader_parameter("lights", lights.slice(0, 4))
	_post_mat.set_shader_parameter("light_colors", colors.slice(0, 4))
	_post_mat.set_shader_parameter("sun_pos", SUN_AT + off)
	_post_mat.set_shader_parameter("space", clampf(alt / 80.0, 0.0, 1.0))
	_post_mat.set_shader_parameter("stress", clampf(flight.stress, 0.0, 1.0))
	_post_mat.set_shader_parameter("flash", clampf((_kick - 1.0) * 0.35, 0.0, 0.5))
	_post_mat.set_shader_parameter("time", _time)


# --- throttle lever ---------------------------------------------------------------------

## Mouse: press on the lever box grabs the handle, the hand angle around the pivot sets where it is
## pulled to; release lets go (the lever stays, settling into the nearest notch).
func _lever_input(event: InputEvent) -> void:
	if _finished or Tutorial.is_blocking():
		_grab = false
		return
	var mouse := _ui.get_local_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and LEVER_BOX.has_point(mouse) and not SKIP_BUTTON.has_point(mouse):
			_grab = true
			_hand = _lever_at(mouse)
			Sfx.play("lever", 0.6)
			get_viewport().set_input_as_handled()
		elif not event.pressed and _grab:
			_grab = false
	elif event is InputEventMouseMotion:
		_hover = LEVER_BOX.has_point(mouse)
		if _grab:
			_hand = _lever_at(mouse)
		Input.set_default_cursor_shape(Input.CURSOR_DRAG if _grab else
				(Input.CURSOR_POINTING_HAND if _hover else Input.CURSOR_ARROW))


## Throttle (0..1) for a hand at `mouse`: its angle around the pivot along the gate.
func _lever_at(mouse: Vector2) -> float:
	var d := mouse - LEVER_PIVOT
	var deg := rad_to_deg(atan2(d.x, -d.y))
	return clampf(inverse_lerp(LEVER_IDLE_DEG, LEVER_FULL_DEG, deg), 0.0, 1.0)


func _lever_angle(value: float) -> float:
	return deg_to_rad(lerpf(LEVER_IDLE_DEG, LEVER_FULL_DEG, value))


## Handle physics (local, every peer): spring to the hand + damping + notch detents + end stops.
func _read_lever(delta: float) -> void:
	if _finished or Tutorial.is_blocking():
		_grab = false
		return
	var keys := 0.0
	if Input.is_action_pressed(Controls.action("p1", "up")):
		keys += 1.0
	if Input.is_action_pressed(Controls.action("p1", "down")):
		keys -= 1.0
	if keys != 0.0:
		if not _grab and not _keys_held:
			_hand = _lever                       # keys start from where the lever is
		_hand = clampf(_hand + keys * LEVER_SPEED * delta, 0.0, 1.0)
	_keys_held = keys != 0.0
	var pulled := _grab or keys != 0.0
	var before := _lever
	var steps := 4
	var dt := delta / steps
	for i in steps:
		var force := -LEVER_DETENT * sin(TAU * _lever * 10.0)   # pull into the nearest 10% notch
		if pulled:
			force += LEVER_K * (_hand - _lever)
		_lever_v += (force - LEVER_DAMP * _lever_v) * dt
		_lever_v = clampf(_lever_v, -LEVER_MAX_V, LEVER_MAX_V)
		_lever += _lever_v * dt
		if _lever < 0.0 or _lever > 1.0:
			if absf(_lever_v) > 0.25:
				Sfx.play("lever", 0.5)           # thud against the end stop
				_kick = maxf(_kick, 0.15)
			_lever = clampf(_lever, 0.0, 1.0)
			_lever_v = -_lever_v * 0.2
	if not pulled and absf(_lever_v) < 0.01 and absf(sin(TAU * _lever * 10.0)) < 0.02:
		_lever_v = 0.0
	if floori(before * 10.0 + 0.5) != floori(_lever * 10.0 + 0.5):
		Sfx.play("lever", 0.8 + _lever * 0.6)  # a click per 10% notch


# --- simulation (host) ------------------------------------------------------------------

func _simulate(dt: float) -> void:
	var f := flight
	var total := 0.0
	for id in roles:
		total += float(levers.get(id, 0.0))
	f.throttle = total / maxf(roles.size(), 1)
	var thr: float = f.throttle
	if f.phase in ["pad", "ascent", "meco", "stage2", "falling"]:   # recorder (time = since ignition)
		f.time += dt
		f.max_alt = maxf(f.max_alt, f.alt)
		f.max_speed = maxf(f.max_speed, f.speed)
		f.max_thr = maxf(f.max_thr, thr)
		_log_timer -= dt
		if _log_timer <= 0.0:
			_log_timer = LOG_STEP
			_log.append([f.time, f.alt, f.speed, f.q, thr])
	if f.phase in ["ascent", "stage2"]:
		f.powered_time += dt
		f.thr_sum += thr * dt
	match f.phase:
		"countdown":
			f.clock -= dt
			if f.clock <= 0.0:
				f.phase = "pad"
				_say("IGNITION - PUSH THE LEVER UP")
		"pad":
			_burn_stage(thr * 0.5, dt)  # hold-down clamps: fuel burns, rocket stays
			f.pad_fuel += STAGE1_BURN * thr * 0.5 * dt
			if thr * _twr1 > 1.0:
				f.phase = "ascent"
				_say("LIFTOFF!")
			elif f.stage_fuel <= 0.0:
				_fail("NOT ENOUGH THRUST - NEVER LEFT THE PAD", "Push the lever past the green LIFT mark.")
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
					f.meco_alt = f.alt
					f.meco_speed = f.speed
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
	if flight.phase in ["ascent", "meco", "stage2"]:   # recorder: speed the engines gave vs gravity took
		flight.thrust_dv += thrust * ACCEL * dt
		flight.gravity_dv += minf(gravity * ACCEL * dt, flight.speed + thrust * ACCEL * dt)
	flight.speed = maxf(flight.speed + (thrust - gravity) * ACCEL * dt, 0.0)
	var vertical := clampf(1.0 - flight.alt / 320.0, 0.3, 1.0)
	flight.alt += flight.speed * vertical * dt


## Dynamic pressure q = speed^2 x air density. Above the structure's limit, stress builds:
## at STRAIN_AT the ship is damaged (a station starts the cruise offline), at 1.0 it breaks up.
## Fast (light) rockets must throttle down through max-Q; slow heavy ones rarely need to.
func _max_q(dt: float) -> void:
	var q: float = flight.speed * flight.speed * exp(-flight.alt / AIR_SCALE) * Q_K
	flight.q = q
	if q > flight.peak_q:
		flight.peak_q = q
		flight.peak_q_alt = flight.alt
		flight.peak_q_speed = flight.speed
		flight.peak_q_thr = flight.throttle
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
	_log.append([flight.time, flight.alt, flight.speed, flight.q, flight.throttle])
	var mass := float(DesignRules.evaluate(DesignRules.chosen if not DesignRules.chosen.is_empty() else DesignRules.new_design()).mass)
	flight.report = LaunchReport.make(flight, _log, LOG_POINTS, mass, float(_launcher.get("capacity_kg", 1.0)), TARGET_SPEED,
			1.0 / _twr1)
	_say(reason)


## Back to the pad with a fresh rocket (any player presses SPACE after a failure).
func _retry() -> void:
	if flight.phase != "failed":
		return
	var attempt: int = flight.attempt + 1
	flight = _new_flight()
	flight.attempt = attempt
	_log.clear()
	_log_timer = 0.0


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
				_failed_at = _time
				Codex.unlock(LaunchReport.terms(f.get("report", {})))
				if str(f.fail).begins_with("STRUCTURAL"):
					Sfx.play("explode")
					Sfx.play("explode", 0.6)
					_kick = 2.0
					_explode_rocket()
				elif str(f.fail).begins_with("NOT ENOUGH"):
					Sfx.play("denied")       # never left the pad: engines just die
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
	_screen.position = Vector2(-VIEW_MARGIN, -VIEW_MARGIN) \
			+ (Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake).round()   # whole pixels

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

func _draw_world() -> void:
	var alt: float = flight.alt
	# The sky (dithered gradient, Sun, stars) is the launch_sky shader under this node.
	# Earth's curve appears once you are high enough.
	if alt > 45.0:
		var rise := clampf((alt - 45.0) * 0.9, 0.0, 70.0)
		var r := 900.0 - minf(alt, 300.0) * 1.2
		var center := Vector2(240, 270 - rise + r)
		_w.draw_circle(center, r + 6, Color(0.35, 0.65, 1.0, 0.25))
		_w.draw_circle(center, r + 2, Color(0.45, 0.75, 1.0, 0.45))
		_w.draw_circle(center, r, Color("1d4f8f"))
		_w.draw_circle(center, r - 1, Color(0.11, 0.3, 0.55, 0.55))
	_draw_hills(alt)
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
			_w.draw_rect(Rect2(x, y, 1, 6 + vspeed * 2.0), Color(1, 1, 1, 0.25 * air))
	_draw_ground(alt)
	for p in _parts:
		if p.smoke:
			_w.draw_rect(Rect2(p.p.round(), Vector2(p.size, p.size)), Color(p.col, 0.55 * p.life / p.max))
	_draw_rocket()
	for p in _parts:
		if not p.smoke:
			_w.draw_rect(Rect2(p.p.round(), Vector2(p.size, p.size)), p.col)


func _sky(alt: float) -> Color:
	var stops := [[0.0, Color("8cc4ff")], [10.0, Color("3f7fd0")], [30.0, Color("1a2f6a")],
			[55.0, Color("0b1028")], [90.0, Color("04050c")]]
	for i in stops.size() - 1:
		if alt <= stops[i + 1][0]:
			var k := inverse_lerp(stops[i][0], stops[i + 1][0], alt)
			return (stops[i][1] as Color).lerp(stops[i + 1][1], clampf(k, 0.0, 1.0))
	return stops[-1][1]


func _cloud(at: Vector2, kind: int) -> void:
	var tex: ImageTexture = _cloud_tex[clampi(kind, 0, _cloud_tex.size() - 1)]
	_w.draw_texture(tex, (at - Vector2(tex.get_size()) / 2.0).round())


## A pixel cumulus: round puffs sitting on a flat base, lit from above (3 tones, Bayer-dithered).
func _make_cloud(w: int, h: int, seed_value: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var blobs: Array[Vector3] = []
	var n := 3 + w / 16
	for i in n:
		var r := rng.randf_range(h * 0.4, h * 0.62)
		if i == 0 or i == n - 1:
			r *= 0.7
		var cx := lerpf(r, w - r, float(i) / maxf(n - 1, 1))
		blobs.append(Vector3(cx, h - r * rng.randf_range(0.6, 1.0), r))
	var tones := [Color("f6f9ff"), Color("dde6f4"), Color("b8c6dc")]
	for y in h:
		for x in w:
			var depth := INF
			for b in blobs:
				if Vector2(x + 0.5 - b.x, y + 0.5 - b.y).length() <= b.z:
					depth = minf(depth, (y - (b.y - b.z)) / (b.z * 2.0))
			if depth == INF:
				continue
			var d: float = depth + (BAYER[(x % 4) + (y % 4) * 4] / 16.0 - 0.5) * 0.3
			var col: Color = tones[0] if d < 0.32 else (tones[1] if d < 0.68 else tones[2])
			if y == h - 1:
				col = Color("a7b4cc")
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## The launch site, in world pixels: far + near hills (slower parallax), dithered grass, the
## concrete apron with hazard stripes and the flame trench, fuel spheres, floodlight masts, a
## blockhouse, and the red service tower with its access arm.
func _draw_hills(alt: float) -> void:
	var far_y := roundf(GROUND_Y + alt * PX_PER_KM * 0.55)
	var near_y := roundf(GROUND_Y + alt * PX_PER_KM * 0.8)
	if far_y - 50.0 > 290.0:
		return
	for x in range(-8, 489):
		var hf := roundf(_hills_far[x + 8])
		_w.draw_rect(Rect2(x, far_y - hf, 1, 300), Color("6a86b0"))
		_w.draw_rect(Rect2(x, far_y - hf, 1, 1), Color("8aa4c8"))
	for x in range(-8, 489):
		var hn := roundf(_hills_near[x + 8])
		_w.draw_rect(Rect2(x, near_y - hn, 1, 300), Color("47705a"))
		if (x + int(hn)) % 3 == 0:
			_w.draw_rect(Rect2(x, near_y - hn, 1, 1), Color("5f8d6c"))


func _draw_ground(alt: float) -> void:
	var ground := roundf(GROUND_Y + alt * PX_PER_KM)
	if ground > 300.0:
		return
	# Grass with a dithered top edge.
	_w.draw_rect(Rect2(-8, ground, 496, 60), Color("3f6b3a"))
	_w.draw_rect(Rect2(-8, ground, 496, 1), Color("6fa05a"))
	for x in range(-8, 488, 2):
		_w.draw_rect(Rect2(x + (0 if int(ground) % 2 == 0 else 1), ground + 1, 1, 1), Color("5d8f4f"))
		_w.draw_rect(Rect2(x + 1, ground + 4, 1, 1), Color("36603a"))
	# Fuel spheres on legs (left).
	for sx in [62.0, 92.0]:
		_w.draw_rect(Rect2(sx - 7, ground - 9, 1, 9), Color("596075"))
		_w.draw_rect(Rect2(sx + 6, ground - 9, 1, 9), Color("596075"))
		_w.draw_circle(Vector2(sx, ground - 17), 10.0, Color("aab3c4"))
		_w.draw_circle(Vector2(sx - 1, ground - 18), 9.0, Color("dfe4ee"))
		_w.draw_rect(Rect2(sx - 5, ground - 23, 2, 2), Color.WHITE)
	_w.draw_rect(Rect2(62, ground - 4, 140, 1), Color("7a8094"))          # fuel pipe to the pad
	# Blockhouse (right) with lit windows.
	_w.draw_rect(Rect2(404, ground - 16, 48, 16), Color("8b8f9a"))
	_w.draw_rect(Rect2(400, ground - 19, 56, 3), Color("a6abb6"))
	for wx in 4:
		_w.draw_rect(Rect2(410 + wx * 10, ground - 11, 5, 3), Color("ffd27a"))
	# Floodlight masts.
	for mx in [160.0, 322.0]:
		_w.draw_rect(Rect2(mx, ground - 46, 1, 46), Color("596075"))
		_w.draw_rect(Rect2(mx - 3, ground - 49, 7, 3), Color("3a4052"))
		_w.draw_rect(Rect2(mx - 2, ground - 48, 5, 1), Color("fff3c0"))
	# Concrete apron, hazard stripes, flame trench.
	_w.draw_rect(Rect2(176, ground - 3, 128, 6), Color("8a8f9c"))
	_w.draw_rect(Rect2(176, ground - 3, 128, 1), Color("b5bac6"))
	for i in 16:
		_w.draw_rect(Rect2(176 + i * 8, ground + 2, 4, 1), Color("ffc640"))
		_w.draw_rect(Rect2(180 + i * 8, ground + 2, 4, 1), Color("23252e"))
	_w.draw_rect(Rect2(226, ground - 2, 28, 5), Color("1b1d26"))
	if _engine_on() and flight.alt < 2.0:
		_w.draw_rect(Rect2(228, ground - 2, 24, 2), Color("ff7a2a"))
	# Service tower: a red steel truss beside the rocket, lightning rod on top.
	var tx := roundf(240.0 + _rocket_idle.get_width() / 2.0 + 8.0)
	var h := roundf(minf(float(_rocket_idle.get_height()) * 0.85, 200.0))
	var col := Color("c0392b")
	var dark := Color("7f2219")
	_w.draw_rect(Rect2(tx, ground - h, 2, h), col)
	_w.draw_rect(Rect2(tx + 10, ground - h, 2, h), dark)
	var y := ground - h
	while y < ground - 9.0:
		_w.draw_line(Vector2(tx + 1, y), Vector2(tx + 11, y + 10), dark, 1.0)
		_w.draw_line(Vector2(tx + 11, y), Vector2(tx + 1, y + 10), col, 1.0)
		_w.draw_rect(Rect2(tx, y, 12, 1), col)
		y += 10
	_w.draw_rect(Rect2(tx + 5, ground - h - 12, 1, 12), Color("9aa0b0"))
	_w.draw_rect(Rect2(tx + 4, ground - h - 13, 3, 1), Color("ff5050") if fmod(_time, 1.0) < 0.5 else Color("6b2020"))
	if flight.phase == "countdown":  # access arm until ignition
		var ax := roundf(240 + _rocket_idle.get_width() / 2.0)
		_w.draw_rect(Rect2(ax, roundf(ground - h * 0.8), tx - ax, 2), col)
		_w.draw_rect(Rect2(ax, roundf(ground - h * 0.8) + 2, tx - ax, 1), dark)


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
			_w.draw_texture_rect_region(_rocket_fire, Rect2(x, roundf(bottom), w, roundf(flame)),
					Rect2(0, h, w, fh))
		_w.draw_texture(_rocket_idle, Vector2(x, roundf(bottom - h)))
	else:
		var top_bottom := bottom
		if flame > 0.0:
			_draw_small_flame(Vector2(240 + wobble, top_bottom), flame)
		_w.draw_texture_rect_region(_rocket_idle, Rect2(x, roundf(top_bottom - split), w, split), Rect2(0, 0, w, split))
		if not _dropped.is_empty():
			var stage_h := h - split
			_w.draw_set_transform(Vector2(240, top_bottom + 20 + _dropped.y + stage_h / 2.0), _dropped.rot, Vector2.ONE)
			_w.draw_texture_rect_region(_rocket_idle, Rect2(-w / 2.0, -stage_h / 2.0, w, stage_h), Rect2(0, split, w, stage_h))
			_w.draw_set_transform(Vector2.ZERO)


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
		_w.draw_colored_polygon(pts, Color("e84a3c") if i % 2 == 0 else Color("f2efe6"))
	_w.draw_rect(Rect2(center.x - r, center.y - 1, r * 2, 2), Color("b8352a"))
	for i in 5:
		var x := lerpf(-r, r, i / 4.0)
		_w.draw_line(center + Vector2(x, 0), nose + Vector2(0, 2), Color("d8dce8"), 1.0)


## After touchdown the canopy collapses on the ground beside the rocket.
func _draw_canopy_heap(at: Vector2) -> void:
	for i in 6:
		var x := at.x + i * 6
		var hgt := 4.0 + (i % 3) * 2.0
		_w.draw_rect(Rect2(x, at.y - hgt, 6, hgt), Color("e84a3c") if i % 2 == 0 else Color("f2efe6"))
	_w.draw_line(at + Vector2(0, -2), at + Vector2(-6, -30), Color("d8dce8"), 1.0)


func _draw_small_flame(at: Vector2, length: float) -> void:
	var colors := [Color("ff7a2a"), Color("ffc640"), Color("fff3a0")]
	for i in 3:
		var half := 3.0 - i
		var l := length * (1.0 - i * 0.28)
		_w.draw_colored_polygon(PackedVector2Array([at + Vector2(-half - 1, 0), at + Vector2(half + 1, 0),
				at + Vector2(0, l)]), colors[i])


# --- drawing: UI (does not shake) ----------------------------------------------------------

func _draw_ui() -> void:
	var f := flight
	var ui := _ui
	# Telemetry, top left, on a raised block.
	UiKit.panel(ui, Rect2(4, 5, 152, 96 + (15 if f.damage > 0 else 0)), UiKit.PANEL)
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
	_draw_skip(ui)

	if f.phase == "failed":
		_draw_failure(ui)
	elif f.q > 1.0 and fmod(_time, 0.4) < 0.28:
		var t := "MAX-Q: PULL THE LEVER BACK"
		_text(ui, Vector2(240 - UiFont.width(t, 11) / 2.0, 70), t, Color("ff5050"), 11)

	# Banner, centre top.
	if f.phase == "failed":
		pass
	elif _banner_time > 0.0 and _banner != "":
		var big := 16 if _banner.length() <= 3 else 11
		var w := UiKit.text_w(_banner, big)
		var a := clampf(_banner_time * 2.0, 0.0, 1.0)
		UiKit.panel(ui, Rect2(roundf(240 - w / 2.0 - 8), 28, roundf(w + 16), UiFont.px(big) + 10), Color(UiKit.PANEL, a), Color(UiKit.WARN, a))
		_text(ui, Vector2(240 - w / 2.0, 30 + big + 1), _banner, Color(1, 1, 1, a), big)
	elif f.phase == "meco":
		var left: float = maxf(STAGE_WINDOW - f.coast, 0.0)
		var urgent: bool = f.coast >= STAGE_WINDOW * 0.75
		if fmod(_time, 0.3 if urgent else 0.6) < (0.2 if urgent else 0.4):
			var t := ("SEPARATE NOW!  %.1f" if urgent else "PRESS SPACE: SEPARATE STAGE  %.0f") % left
			_text(ui, Vector2(240 - UiKit.text_w(t, 11) / 2.0, 46), t, Color("ff5050") if urgent else Color("ffc640"), 11)
	elif f.phase == "pad" and f.throttle * _twr1 <= 1.0:
		var t := "NOT ENOUGH THRUST - PUSH THE LEVER FORWARD"
		_text(ui, Vector2(240 - UiFont.width(t, 10) / 2.0, 46), t, Color("ffc640"), 10)

	var info := "%s  ·  SHIP %d KG / ROCKET LIFTS %d KG  ·  SIMPLIFIED PHYSICS" % [
			str(_launcher.get("name", "")).to_upper(),
			DesignRules.evaluate(DesignRules.chosen if not DesignRules.chosen.is_empty() else DesignRules.new_design()).mass,
			_launcher.get("capacity_kg", 0)]
	_text(ui, Vector2(10, 262), info, Color("9aa4b8"), 7)


func _draw_skip(ui: Node2D) -> void:
	if not _is_host() or _finished:
		return
	var hot := SKIP_BUTTON.has_point(ui.get_local_mouse_position())
	ui.draw_rect(SKIP_BUTTON, Color(1, 1, 1, 0.16 if hot else 0.06))
	ui.draw_rect(SKIP_BUTTON, Color(1, 1, 1, 0.6 if hot else 0.3), false, 1.0)
	_text(ui, SKIP_BUTTON.position + Vector2(4, 9), "SKIP LAUNCH [F2]", Color(1, 1, 1, 0.9 if hot else 0.6), 7)


## Failure: the full report (graph + what happened + the physics + fix + real rockets) fades in once
## the explosion / landing has played; before that (or without a report) the short box.
func _draw_failure(ui: Node2D) -> void:
	var since := _time - _failed_at if _failed_at >= 0.0 else 99.0
	if not flight.get("report", {}).is_empty() and since >= LaunchReport.DELAY:
		LaunchReport.draw(ui, flight, since - LaunchReport.DELAY, _time)
		return
	var r := Rect2(86, 112, 308, 96)
	UiKit.frame(ui, r, UiKit.BAD, Color("1a0c10"))
	var title := "LAUNCH FAILED"
	_text(ui, Vector2(240 - UiKit.text_w(title, 14) / 2.0, r.position.y + 20), title, Color("ff5050"), 14)
	var reason := str(flight.fail)
	_text(ui, Vector2(240 - UiKit.text_w(reason, 9) / 2.0, r.position.y + 36), reason, Color.WHITE, 9)
	var hint := str(flight.hint)
	_text(ui, Vector2(240 - UiKit.text_w(hint, 7) / 2.0, r.position.y + 50), hint, Color("9aa4b8"), 7)
	var keys := "SPACE: NEW ROCKET     D: REDESIGN SHIP"
	var blink := 1.0 if fmod(_time, 1.0) < 0.7 else 0.6
	_text(ui, Vector2(240 - UiKit.text_w(keys, 9) / 2.0, r.position.y + 72), keys, Color(1.0, 0.78, 0.25, blink), 9)


## Throttle quadrant (UI layer, drawn in whole pixels): a riveted panel, an arc gate with 10%
## notches, the LIFT mark, crew markers, and a heavy arm on a pivot. While held, a ghost knob shows
## where the hand is - the gap is the lever's resistance.
func _draw_lever(ui: Node2D) -> void:
	var box := LEVER_BOX
	var r := LEVER_LEN
	var me_col := CrewRoles.color(roles.get(_me, "all"))
	var warn: bool = flight.q > 1.0 and fmod(_time, 0.4) < 0.25
	# Panel with a bevel and rivets.
	ui.draw_rect(box, Color(0.07, 0.08, 0.13, 0.92))
	ui.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), Color("3a4466"))
	ui.draw_rect(Rect2(box.position, Vector2(1, box.size.y)), Color("3a4466"))
	ui.draw_rect(Rect2(box.position + Vector2(0, box.size.y - 1), Vector2(box.size.x, 1)), Color("05060a"))
	ui.draw_rect(Rect2(box.position + Vector2(box.size.x - 1, 0), Vector2(1, box.size.y)), Color("05060a"))
	for c in [Vector2(3, 3), Vector2(box.size.x - 5, 3), Vector2(3, box.size.y - 5), Vector2(box.size.x - 5, box.size.y - 5)]:
		ui.draw_rect(Rect2(box.position + c, Vector2(2, 2)), Color("596075"))
	if warn or (_hover and not _grab):
		var edge := Color("ff5050") if warn else Color(me_col, 0.6)
		ui.draw_rect(box.grow(1), edge, false, 1.0)
	_text(ui, box.position + Vector2(8, 13), "THROTTLE", Color.WHITE, 7)
	# Gate slot along the arc.
	var deg := LEVER_IDLE_DEG
	while deg <= LEVER_FULL_DEG:
		var p := _lever_point(deg_to_rad(deg), r)
		ui.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color("05060a"))
		ui.draw_rect(Rect2(p + Vector2(-1, 2), Vector2(3, 1)), Color("2c3454"))
		deg += 1.0
	# Notches every 10% (inner side), long at 0 / 50 / 100.
	for i in 11:
		var a := _lever_angle(i / 10.0)
		var long := i % 5 == 0
		for k in (5 if long else 3):
			ui.draw_rect(Rect2(_lever_point(a, r - 5.0 - k), Vector2(1, 1)), Color("8a93ad") if long else Color("5a6382"))
	_text(ui, box.position + Vector2(6, 72), "IDLE", Color("9aa4b8"), 6)
	_text(ui, Vector2(box.end.x - 20, 204), "FULL", Color("9aa4b8"), 6)
	if flight.stage == 1:
		var la := _lever_angle(clampf(1.0 / _twr1, 0.0, 1.0))
		for k in 13:
			ui.draw_rect(Rect2(_lever_point(la, r - 9.0 + k), Vector2(1, 1)), Color("5cf07a"))
		var lp := _lever_point(la, r - 22.0)
		_text(ui, lp + Vector2(-8, 3), "LIFT", Color("5cf07a"), 6)
	# Other players' levers.
	for id in levers:
		if id == _me or not roles.has(id):
			continue
		var op := _lever_point(_lever_angle(float(levers[id])), r - 13.0)
		ui.draw_rect(Rect2(op - Vector2(1, 1), Vector2(3, 3)), CrewRoles.color(roles[id]))
	# Ghost knob at the hand (resistance gap).
	if _grab and absf(_hand - _lever) > 0.01:
		var hp := _lever_point(_lever_angle(_hand), r)
		_pixel_ring(ui, hp, 4, Color(me_col, 0.7))
	# Max-Q: chevrons on the idle side of the knob.
	var a_now := _lever_angle(_lever)
	if warn:
		for k in 3:
			var cp := _lever_point(a_now - deg_to_rad(9.0 + k * 6.0), r)
			ui.draw_rect(Rect2(cp - Vector2(1, 1), Vector2(2, 2)), Color("ff5050"))
	# The arm: shadow, body, highlight; then the pivot hub and the knob.
	var knob := _lever_point(a_now, r)
	var dir := (knob - LEVER_PIVOT).normalized()
	var steps := int(r)
	for t in steps:
		var p := (LEVER_PIVOT + dir * t).round()
		ui.draw_rect(Rect2(p + Vector2(0, 1), Vector2(3, 2)), Color("0a0c12"))
	for t in steps:
		var p := (LEVER_PIVOT + dir * t).round()
		ui.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color("7d8498"))
		ui.draw_rect(Rect2(p - Vector2(1, 1), Vector2(1, 1)), Color("c9cfdc"))
	_pixel_disc(ui, LEVER_PIVOT, 6, Color("0a0c12"))
	_pixel_disc(ui, LEVER_PIVOT, 5, Color("4a5578"))
	_pixel_disc(ui, LEVER_PIVOT, 2, Color("8a93ad"))
	var kr := 7 if _grab else 6
	_pixel_disc(ui, knob.round(), kr, Color("0a0c12"))
	_pixel_disc(ui, knob.round(), kr - 1, me_col.darkened(0.25))
	_pixel_disc(ui, knob.round() + Vector2(-1, -1), kr - 3, me_col)
	ui.draw_rect(Rect2(knob.round() + Vector2(-3, -3), Vector2(2, 2)), Color(1, 1, 1, 0.85))
	# Readout.
	var screen := Rect2(box.position + Vector2(6, 88), Vector2(38, 14))
	ui.draw_rect(screen, Color("05140c"))
	ui.draw_rect(screen, Color("1f3a2a"), false, 1.0)
	var label := "%d%%" % roundi(flight.throttle * 100.0)
	_text(ui, screen.position + Vector2(screen.size.x / 2.0 - UiFont.width(label, 9) / 2.0, 11), label, Color("5cf07a"), 9)
	if roles.size() > 1:
		_text(ui, box.position + Vector2(6, 111), "AVG OF CREW", Color("9aa4b8"), 6)
	var hint_on: bool = not _grab and (_lever < 0.05 and flight.phase in ["countdown", "pad"]) and fmod(_time, 1.0) < 0.6
	_text(ui, box.position + Vector2(6, 119), "DRAG THE LEVER" if hint_on or _hover else "MOUSE: DRAG",
			Color("ffc640") if hint_on else Color("6b7390"), 6)


func _lever_point(angle: float, radius: float) -> Vector2:
	return (LEVER_PIVOT + Vector2(sin(angle), -cos(angle)) * radius).round()


## Filled circle out of 1-px rows (stays pixel art when the UI layer is scaled).
func _pixel_disc(ui: Node2D, center: Vector2, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		var half := floori(sqrt(float(radius * radius - dy * dy)) + 0.3)
		ui.draw_rect(Rect2(center.x - half, center.y + dy, half * 2 + 1, 1), color)


func _pixel_ring(ui: Node2D, center: Vector2, radius: int, color: Color) -> void:
	for i in 24:
		var a := TAU * i / 24.0
		ui.draw_rect(Rect2((center + Vector2(cos(a), sin(a)) * radius).round(), Vector2(1, 1)), color)


## Segmented bar (UI kit).
func _bar(ui: Node2D, r: Rect2, fill: float, color: Color) -> void:
	UiKit.seg_bar(ui, Rect2(r.position.x, r.position.y - 1, r.size.x, 6), clampf(fill, 0.0, 1.0), color, 16)


func _text(ui: Node2D, pos: Vector2, text: String, color: Color, size := 8) -> void:
	UiKit.text(ui, pos, text, size, color, 2)
