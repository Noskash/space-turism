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
## Network puppet: driven by snapshots from its owner instead of the keyboard.
var remote := false
## Draw a small marker over the head (which one is me, in co-op).
var show_marker := false
## Run key held while moving (synced, so others see the faster animation).
var running := false

var _station: Station = null     # station whose ring we stand in
var _docked: Station = null      # station we are operating
var _wait_release := false       # the USE press that docked must be released first
var _facing := Vector2.DOWN
var _sprite: CrewSprite
var _alarm_left := 0.0
var _anim_moving := false
var _anim_special := ""
var _net_target := Vector2.ZERO


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
	Events.event_started.connect(_on_event_started)


func _physics_process(delta: float) -> void:
	_alarm_left = maxf(_alarm_left - delta, 0.0)
	if remote:
		_process_remote(delta)
	elif Tutorial.is_blocking():
		velocity = Vector2.ZERO
		running = false
		if _docked:
			_docked.set_holding(false)
		_animate(false, "")
	elif _docked:
		_process_docked()
	else:
		_process_walking()
	queue_redraw()


func _process_walking() -> void:
	var dir := Input.get_vector(_act("left"), _act("right"), _act("up"), _act("down"))
	running = dir != Vector2.ZERO and Input.is_action_pressed(_act("run"))
	velocity = dir * (RUN_SPEED if running else SPEED)
	if dir != Vector2.ZERO:
		_facing = dir
	move_and_slide()
	_update_station()
	if _station and _station.is_free() and Input.is_action_just_pressed(_act("interact")):
		_dock(_station)
		Sfx.play("dock")
		return
	if _station == null and RadioSet.in_reach(global_position) and Input.is_action_just_pressed(_act("interact")):
		Events.action_requested.emit("team", {type = "radio"})
		Sfx.play("toggle")
	var moving := get_real_velocity().length() > 1.0
	_animate(moving, "alarm" if _alarm_left > 0.0 else "")


## Docked: ←/→ = station choices, hold USE = work, ↑/↓ = leave.
func _process_docked() -> void:
	velocity = Vector2.ZERO
	running = false
	if Input.is_action_just_pressed(_act("up")) or Input.is_action_just_pressed(_act("down")):
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
## [pos, facing, moving, special, docked, skin, running].
func snapshot() -> Array:
	return [position, _facing, _anim_moving, _anim_special,
			_docked.role if _docked else "", skin, running]


func apply_snapshot(data: Array) -> void:
	if data.size() < 6:
		return
	_net_target = data[0]
	_facing = data[1]
	_anim_moving = data[2]
	_anim_special = data[3]
	running = data.size() > 6 and data[6]
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
	var c := role_color()
	if show_marker:
		var y := -20.0 if _sprite else -19.0
		draw_colored_polygon(PackedVector2Array([Vector2(-2, y), Vector2(3, y), Vector2(0.5, y + 3)]),
				Color.WHITE)
	_draw_ellipse(Vector2(0, -1), Vector2(5, 2), Color(0, 0, 0, 0.35))  # shadow
	_draw_ellipse_outline(Vector2(0, -1), Vector2(6, 2.5), Color(c, 0.8))  # role ring
	if _sprite:
		return
	# Placeholder astronaut.
	draw_rect(Rect2(-3, -11, 6, 9), c)                         # suit
	draw_rect(Rect2(-3, -15, 6, 5), Color("f0f0f0"))           # helmet
	var visor := Vector2(-2, -14) + Vector2(_facing.x, maxf(_facing.y, 0)).round()
	draw_rect(Rect2(visor, Vector2(4, 2)), Color("1b2a4a"))    # visor shows facing


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
