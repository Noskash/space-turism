class_name CrewMember
extends CharacterBody2D
## One player-controlled crew member walking around the ship map.
## The node's origin is the FEET (crew sheet anchor 8,15), so y-sorting works.
##
## Look: a skin from sprites/crew_skins (CrewSprite), or a placeholder astronaut block
## when `skin` is empty. A role-coloured ring under the feet shows who is who.

signal skin_changed(skin: String)

const SPEED := 80.0      # px/s in the 480x270 world
const RUN_SPEED := 135.0  # while the run key is held

## Radiation sickness (set by the game from the sim's state.crew): slower walking and station work.
var sick := false

## Input scheme from Controls.SCHEMES ("p1", ...).
@export var scheme := "p1"
## Crew role(s): "navigator", "comms+scientist" when one player covers two stations,
## or "all" in single player (can use every station).
@export var role := "all"
## Skin name from skins.json, or "" for the placeholder astronaut.
@export var skin := "":
	set(value):
		skin = value
		if is_node_ready():
			_apply_skin()

const ALARM_TIME := 1.0  # seconds of the alarm animation when a ticket hits our role

var ship_map: ShipMap
## Carrying a toolbox (lockers in Cargo / Engine Room): needed to patch hull breaches. Synced.
var has_toolbox := false:
	set(value):
		has_toolbox = value
		if _tool:
			_tool.queue_redraw()
var _tool: Node2D                # draws the toolbox / extinguisher in hand, over the sprite
var _patch_id := -1              # breach being patched (HOLD USE next to it with a toolbox)
var _patch := 0.0
## Carrying an extinguisher (racks in the Mission Hub / Bridge): puts out fires. One item at a time:
## toolbox OR extinguisher. Synced, like the toolbox.
var has_extinguisher := false:
	set(value):
		has_extinguisher = value
		if _tool:
			_tool.queue_redraw()
## Spraying a flame right now (synced, so every peer draws the foam).
var spraying := false
var _douse_id := -1              # flame being put out (HOLD USE next to it with an extinguisher)
var _douse := 0.0

## Burn shove (state.shove from the sim): a walking crew member is thrown and slides for SHOVE_TIME s;
## docked crew hold on. Each peer moves only its own crew member.
const SHOVE_SPEED := 150.0       # px/s at strength 1, fading out over SHOVE_TIME
const SHOVE_TIME := 0.55
const PING_COOLDOWN := 0.8
const ROLE_NAMES := {navigator = "NAVIGATOR", engineer = "ENGINEER", comms = "COMMS", scientist = "SCIENTIST",
		team = "EVERYONE"}
var _shove_v := Vector2.ZERO
var _shove_left := 0.0
var _shove_seq := -1
var _ping_cd := 0.0
## Network puppet: driven by snapshots from its owner instead of the keyboard.
var remote := false
## Draw a small marker over the head (which one is me, in co-op).
var show_marker := false
## Player name for the role-coloured name tag ("" = no tag, e.g. offline).
var display_name := ""
## Run key held while moving (synced, so others see the faster animation).
var running := false
## Ship-only interactions (toolbox lockers, hull patching, radio). Off in the hangar, where the
## scene handles SPACE itself.
var world_actions := true

var _station: Station = null     # station whose ring we stand in
var _docked: Station = null      # station we are operating
var _wait_release := false       # the USE press that docked must be released first
var _facing := Vector2.DOWN
var _sprite: CrewSprite
var _alarm_left := 0.0
var _anim_moving := false
var _anim_special := ""
var _net_target := Vector2.ZERO
var _tag: Node2D                 # name tag / marker, drawn above the lighting


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING  # top-down: no floor, no gravity
	collision_layer = 2  # crew don't block each other (for now)
	collision_mask = ShipMap.WALL_LAYER
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 4)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -2)  # footprint just above the feet
	add_child(collider)
	_apply_skin()
	_tool = Node2D.new()
	_tool.name = "Toolbox"
	_tool.z_index = 1  # over the skin sprite
	_tool.draw.connect(_draw_toolbox)
	add_child(_tool)
	Events.event_started.connect(_on_event_started)
	Events.state_changed.connect(_on_state)
	# Name tag + "this is me" marker on their own node above the ship lighting (z 40/41).
	_tag = Node2D.new()
	_tag.z_index = 45
	_tag.draw.connect(_draw_tag)
	add_child(_tag)


## Red toolbox held at the side the crew member faces.
func _draw_toolbox() -> void:
	var side := -1.0 if _facing.x < -0.1 else 1.0
	if has_extinguisher:   # red canister held at the side, nozzle forward
		var e := Vector2(5.0 * side - 2.0, -9.0)
		_tool.draw_rect(Rect2(e + Vector2(1, -2), Vector2(2, 2)), Color("2a2a30"))
		_tool.draw_rect(Rect2(e + Vector2(3.0 if side > 0 else -1.0, -2), Vector2(2, 1)), Color("2a2a30"))
		_tool.draw_rect(Rect2(e, Vector2(4, 6)), Color("e0402e"))
		_tool.draw_rect(Rect2(e + Vector2(3, 0), Vector2(1, 6)), Color("8c2a22"))
		_tool.draw_rect(Rect2(e + Vector2(1, 2), Vector2(2, 1)), Color("f2f2f2"))
		return
	if not has_toolbox:
		return
	var o := Vector2(5.0 * side - 3.0, -7.0)
	_tool.draw_rect(Rect2(o + Vector2(1, -2), Vector2(4, 1)), Color("3a3a44"))   # handle
	_tool.draw_rect(Rect2(o, Vector2(6, 4)), Color("d8402e"))
	_tool.draw_rect(Rect2(o + Vector2(0, 1), Vector2(6, 1)), Color("8c2a22"))
	_tool.draw_rect(Rect2(o + Vector2(2, 2), Vector2(2, 1)), Color("f2c14a"))   # latch


func _physics_process(delta: float) -> void:
	_alarm_left = maxf(_alarm_left - delta, 0.0)
	_shove_left = maxf(_shove_left - delta, 0.0)
	_ping_cd = maxf(_ping_cd - delta, 0.0)
	if remote:
		_process_remote(delta)
	elif Tutorial.is_blocking():
		velocity = Vector2.ZERO
		running = false
		_shove_left = 0.0
		if _docked:
			_docked.set_holding(false)
		_animate(false, "")
	else:
		if world_actions and _ping_cd <= 0.0 and Input.is_action_just_pressed(_act("ping")):
			_ping()
		if _docked:
			_process_docked()
		else:
			_process_walking()
	queue_redraw()


func _process_walking() -> void:
	var shoved := _shove_left > 0.0
	if not shoved and (_process_hull() or _process_fire()):
		return
	var dir := Input.get_vector(_act("left"), _act("right"), _act("up"), _act("down"))
	running = dir != Vector2.ZERO and Input.is_action_pressed(_act("run"))
	velocity = dir * (RUN_SPEED if running else SPEED) * (Astronauts.dose("sick_slowdown") if sick else 1.0)
	if shoved:   # thrown by a burn: little control until the slide fades
		velocity = velocity * 0.3 + _shove_v * (_shove_left / SHOVE_TIME)
	if dir != Vector2.ZERO:
		_facing = dir
	move_and_slide()
	_update_station()
	if shoved:
		_animate(true, "alarm")
		return
	var use := Input.is_action_just_pressed(_act("interact"))
	if _station and _station.is_free() and use:
		_dock(_station)
		Sfx.play("dock")
		return
	var hull := HullDamage.current if world_actions else null
	var fire := ShipFire.current if world_actions else null
	var hands_full := has_toolbox or has_extinguisher
	if _station == null and hull and not has_extinguisher and hull.locker_in_reach(global_position) >= 0 and use:
		has_toolbox = not has_toolbox
		Sfx.play("clank")
	elif _station == null and fire and not has_toolbox and fire.rack_in_reach(global_position) >= 0 and use:
		has_extinguisher = not has_extinguisher
		Sfx.play("clank", 1.4)
	elif _station == null and hull and not hands_full and not hull.toolbox_near(global_position).is_empty() and use:
		Events.action_requested.emit("team", {type = "take_tool", id = int(hull.toolbox_near(global_position).id)})
		has_toolbox = true
		Sfx.play("clank", 1.2)
	elif _station == null and fire and not hands_full and not fire.extinguisher_near(global_position).is_empty() and use:
		Events.action_requested.emit("team", {type = "take_tool", id = int(fire.extinguisher_near(global_position).id)})
		has_extinguisher = true
		Sfx.play("clank", 1.5)
	elif _station == null and world_actions and RadioSet.in_reach(global_position) and use:
		Events.action_requested.emit("team", {type = "radio"})
		Sfx.play("toggle")
	elif _station == null and has_toolbox and hull and hull.breach_near(global_position).is_empty() and use:
		# Nothing else to use here: put the toolbox down on the floor (anyone can pick it up).
		Events.action_requested.emit("team", {type = "drop_tool", x = global_position.x, y = global_position.y - 2.0})
		has_toolbox = false
		Sfx.play("clank", 0.8)
	elif _station == null and has_extinguisher and fire and fire.flame_near(global_position).is_empty() and use:
		Events.action_requested.emit("team", {type = "drop_tool", kind = "extinguisher",
				x = global_position.x, y = global_position.y - 2.0})
		has_extinguisher = false
		Sfx.play("clank", 1.0)
	var moving := get_real_velocity().length() > 1.0
	_animate(moving, "alarm" if _alarm_left > 0.0 else "")


## Putting out a flame: standing next to one with an extinguisher and holding USE. Returns true while
## spraying (stands still and works instead of walking).
func _process_fire() -> bool:
	var fire := ShipFire.current if world_actions else null
	var flame: Dictionary = fire.flame_near(global_position) if fire else {}
	if flame.is_empty() or not has_extinguisher or not Input.is_action_pressed(_act("interact")):
		if _douse_id != -1 or spraying:
			_cancel_douse()
		return false
	if int(flame.id) != _douse_id:
		_douse_id = int(flame.id)
		_douse = 0.0
	spraying = true
	velocity = Vector2.ZERO
	running = false
	_facing = (Vector2(flame.x, flame.y) - global_position).normalized()
	_douse += get_physics_process_delta_time() / ShipFire.DOUSE_TIME
	var above: bool = flame.y < global_position.y - 2
	_animate(false, "work_up" if above else "work_down")
	if _douse >= 1.0:
		Events.action_requested.emit("team", {type = "douse", id = _douse_id})
		Sfx.play("fixed", 1.2)
		_douse = 0.0
		_douse_id = -1
	fire.douse_id = _douse_id
	fire.douse_progress = _douse
	return true


func _cancel_douse() -> void:
	_douse_id = -1
	_douse = 0.0
	spraying = false
	if ShipFire.current:
		ShipFire.current.douse_id = -1
		ShipFire.current.douse_progress = 0.0


## The burn fired (state.shove): throw this crew member unless docked (holding on) or in a dialog.
func _on_state(state: Dictionary) -> void:
	if remote:
		return
	var shove: Dictionary = state.get("shove", {})
	var seq := int(shove.get("seq", 0))
	if _shove_seq == -1 or seq < _shove_seq:   # first state (or a new mission): just remember it
		_shove_seq = seq
		return
	if seq == _shove_seq:
		return
	_shove_seq = seq
	if _docked or Tutorial.is_blocking() or not world_actions:
		return
	_shove_v = Vector2(float(shove.get("x", 0.0)), float(shove.get("y", 0.0))) * SHOVE_SPEED * float(shove.get("strength", 1.0))
	_shove_left = SHOVE_TIME
	_cancel_douse()
	if _patch_id != -1:
		_patch_id = -1
		_patch = 0.0
		if HullDamage.current:
			HullDamage.current.patch_id = -1
			HullDamage.current.patch_progress = 0.0


## G: a call-out marker for the whole crew, worded from where you stand.
func _ping() -> void:
	_ping_cd = PING_COOLDOWN
	var here := global_position
	var text := "HELP!"
	var tint := role.split("+")[0]
	var st: Station = _docked if _docked else (ship_map.station_at(here) if ship_map else null)
	var fire := ShipFire.current
	var hull := HullDamage.current
	if fire and not fire.flame_near(here, 32.0).is_empty():
		text = "FIRE HERE!"
		tint = "fire"
	elif hull and not hull.breach_near(here).is_empty():
		text = "BREACH HERE!"
		tint = "breach"
	elif st and not can_use(st):
		text = "NEED " + str(ROLE_NAMES.get(st.role, st.role.to_upper()))
		tint = st.role
	elif st:
		text = "ON IT!"
	Events.action_requested.emit("team", {type = "ping", from = str(name), x = here.x, y = here.y,
			text = text, role = tint})


## Unit vector the crew member faces (for sprays and props).
func facing_dir() -> Vector2:
	return _facing.normalized() if _facing.length() > 0.01 else Vector2.DOWN


## Patching a hull breach: standing next to one with a toolbox and holding USE. Returns true while
## patching (the crew member stands still and works instead of walking).
func _process_hull() -> bool:
	var hull := HullDamage.current if world_actions else null
	var breach: Dictionary = hull.breach_near(global_position) if hull else {}
	if breach.is_empty() or not has_toolbox or not Input.is_action_pressed(_act("interact")):
		if _patch_id != -1:
			_patch_id = -1
			_patch = 0.0
			if hull:
				hull.patch_id = -1
				hull.patch_progress = 0.0
		return false
	if int(breach.id) != _patch_id:
		_patch_id = int(breach.id)
		_patch = 0.0
	var dt := get_physics_process_delta_time()
	var before := _patch
	_patch += dt / HullDamage.PATCH_TIME
	if int(before * 6.0) != int(_patch * 6.0):
		Sfx.play("work_tick", 1.3)
	velocity = Vector2.ZERO
	running = false
	_facing = Vector2(breach.x, breach.y) - global_position
	var above: bool = breach.y < global_position.y - 2
	_animate(false, "work_up" if above else "work_down")
	if _patch >= 1.0:
		Events.action_requested.emit("team", {type = "patch", id = _patch_id})
		Sfx.play("fixed")
		_patch_id = -1
		_patch = 0.0
	hull.patch_id = _patch_id
	hull.patch_progress = _patch
	return true


## Docked: ←/→ = station choices, hold USE = work, Q (or ↑/↓) = leave.
func _process_docked() -> void:
	velocity = Vector2.ZERO
	running = false
	if Input.is_action_just_pressed(_act("leave")) or Input.is_action_just_pressed(_act("up")) \
			or Input.is_action_just_pressed(_act("down")):
		_undock()
		Sfx.play("undock")
		_process_walking()
		return
	if Input.is_action_just_pressed(_act("left")):
		_docked.control("left")
	if Input.is_action_just_pressed(_act("right")):
		_docked.control("right")
	var use_held := Input.is_action_pressed(_act("interact"))
	if _wait_release:
		_wait_release = use_held
		use_held = false
	_docked.set_holding(use_held)
	var above := _docked.global_position.y < global_position.y - 4
	_animate(false, ("work_up" if above else "work_down") if use_held else "")


func _dock(station: Station) -> void:
	_docked = station
	_wait_release = true
	station.dock(self)
	_facing = (station.global_position - global_position)
	if _facing.length() < 2.0:
		_facing = Vector2.UP


func _undock() -> void:
	if _docked:
		_docked.undock(self)
	_docked = null


func _animate(moving: bool, special: String) -> void:
	_anim_moving = moving
	_anim_special = special
	if _sprite:
		_sprite.show_state(_facing, moving, special, running)


func _act(verb: String) -> StringName:
	return Controls.action(scheme, verb)


func _on_event_started(event: Dictionary) -> void:
	if has_role(str(event.get("role", ""))):
		_alarm_left = ALARM_TIME


func has_role(station_role: String) -> bool:
	return CrewRoles.has(role, station_role)


func can_use(station: Station) -> bool:
	return has_role(station.role) or station.role == "team"


## Colour of the first role ("comms+scientist" -> comms green).
func role_color() -> Color:
	return CrewRoles.color(role)


# --- network ---------------------------------------------------------------------------

## What other peers need to draw this crew member:
## [pos, facing, moving, special, docked, skin, running, toolbox, extinguisher, spraying].
func snapshot() -> Array:
	return [position, _facing, _anim_moving, _anim_special,
			_docked.role if _docked else "", skin, running, has_toolbox, has_extinguisher, spraying]


func apply_snapshot(data: Array) -> void:
	if data.size() < 6:
		return
	_net_target = data[0]
	_facing = data[1]
	_anim_moving = data[2]
	_anim_special = data[3]
	running = data.size() > 6 and data[6]
	var tool: bool = data.size() > 7 and data[7]
	if tool != has_toolbox:
		has_toolbox = tool
	var ext: bool = data.size() > 8 and data[8]
	if ext != has_extinguisher:
		has_extinguisher = ext
	spraying = data.size() > 9 and data[9]
	if data[5] != skin:
		skin = data[5]
	var docked_role: String = data[4]
	if (_docked.role if _docked else "") != docked_role:
		_undock()
		var station := ship_map.station_for_role(docked_role) if ship_map and docked_role != "" else null
		if station and station.is_free():
			_docked = station
			station.dock(self)


func _process_remote(delta: float) -> void:
	if position.distance_to(_net_target) > 40.0:
		position = _net_target  # too far behind: snap instead of sliding through walls
	else:
		position = position.lerp(_net_target, minf(delta * 15.0, 1.0))
	_animate(_anim_moving, _anim_special)


func _apply_skin() -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null
	if skin != "" and CrewSprite.has_skin(skin):
		_sprite = CrewSprite.new()
		_sprite.set_skin(skin)
		add_child(_sprite)
	queue_redraw()
	skin_changed.emit(skin)


## Station whose ring we stand in (null = none). For the event walkthroughs.
func near_station() -> Station:
	return _docked if _docked else _station


func docked_station() -> Station:
	return _docked


func _update_station() -> void:
	var found: Station = null
	if ship_map:
		found = ship_map.station_at(global_position)
		if found and not can_use(found):
			found = null
	if found == _station:
		return
	if _station:
		_station.remove_visitor(self)
	_station = found
	if _station:
		_station.add_visitor(self)


func _exit_tree() -> void:
	_undock()
	if _station:
		_station.remove_visitor(self)


func _draw() -> void:
	if _tool:
		_tool.queue_redraw()  # follows facing
	var c := role_color()
	if _tag:
		_tag.queue_redraw()
	_draw_ellipse(Vector2(0, -1), Vector2(5, 2), Color(0, 0, 0, 0.35))  # shadow
	_draw_ellipse_outline(Vector2(0, -1), Vector2(6, 2.5), Color(c, 0.8))  # role ring
	if _sprite:
		return
	# Placeholder astronaut.
	draw_rect(Rect2(-3, -11, 6, 9), c)                         # suit
	draw_rect(Rect2(-3, -15, 6, 5), Color("f0f0f0"))           # helmet
	var visor := Vector2(-2, -14) + Vector2(_facing.x, maxf(_facing.y, 0)).round()
	draw_rect(Rect2(visor, Vector2(4, 2)), Color("1b2a4a"))    # visor shows facing


## Role-coloured name tag over the head (co-op) and a white arrow over your own crew member.
func _draw_tag() -> void:
	var c := role_color()
	var top := -20.0 if _sprite else -19.0
	if show_marker:
		_tag.draw_colored_polygon(PackedVector2Array([Vector2(-2, top), Vector2(3, top), Vector2(0.5, top + 3)]),
				Color.WHITE)
		top -= 2
	if display_name == "":
		return
	var label := display_name.to_upper()
	var w := UiKit.text_w(label, 6) + 6
	var h := maxf(9.0, UiKit.line_h(6) + 2)
	var r := Rect2(roundf(-w / 2.0), top - h, roundf(w), h)
	UiKit.panel(_tag, r, UiKit.PANEL_DARK, c)
	UiKit.text(_tag, Vector2(r.position.x + 3, r.end.y - 2), label, 6, c, 0)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_colored_polygon(_ellipse_points(center, radii), color)


func _draw_ellipse_outline(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := _ellipse_points(center, radii)
	points.append(points[0])
	draw_polyline(points, color, 1.0)


static func _ellipse_points(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
