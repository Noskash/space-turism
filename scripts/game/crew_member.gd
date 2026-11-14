class_name CrewMember
extends CharacterBody2D
## One player-controlled astronaut walking around the ship map.
## The node's origin is the FEET (matches the crew sheet anchor 8,15), so y-sorting works.
##
## Placeholder look: a coloured block until the crew sprite sheets arrive — then replace
## _draw() with an AnimatedSprite2D using offset (-8, -15).

const SPEED := 80.0  # px/s in the 480x270 world

## Input scheme from Controls.SCHEMES ("p1", ...).
@export var scheme := "p1"
## Crew role, or "all" in single-player (can use every station).
@export var role := "all"

var ship_map: ShipMap
var _station: Station = null
var _facing := Vector2.DOWN


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


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector(
			Controls.action(scheme, "left"), Controls.action(scheme, "right"),
			Controls.action(scheme, "up"), Controls.action(scheme, "down"))
	velocity = dir * SPEED
	if dir != Vector2.ZERO:
		_facing = dir
	move_and_slide()
	_update_station()
	if _station and Input.is_action_just_pressed(Controls.action(scheme, "interact")):
		_station.use(self)
	queue_redraw()


func can_use(station: Station) -> bool:
	return role == "all" or station.role == role or station.role == "team"


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
	if _station:
		_station.remove_visitor(self)


func _draw() -> void:
	var c: Color = Station.ROLE_COLORS.get(role, Color("e8e8e8"))
	draw_rect(Rect2(-4, -2, 8, 3), Color(0, 0, 0, 0.35))       # shadow
	draw_rect(Rect2(-3, -11, 6, 9), c)                         # suit
	draw_rect(Rect2(-3, -15, 6, 5), Color("f0f0f0"))           # helmet
	var visor := Vector2(-2, -14) + Vector2(_facing.x, maxf(_facing.y, 0)).round()
	draw_rect(Rect2(visor, Vector2(4, 2)), Color("1b2a4a"))    # visor shows facing
