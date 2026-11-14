class_name Station
extends Node2D
## A console on the ship map. Built by ShipMap from ship_layout.json.
## Crew standing within `radius` can use it; using it sends an action to the sim.

const ROLE_COLORS := {
	"navigator": Color("4fd8ff"),
	"engineer": Color("ff9a3c"),
	"comms": Color("5cf07a"),
	"scientist": Color("b77bff"),
	"team": Color("d8f4ff"),
}

var role := ""
var label_text := ""
var radius := 14.0
var alarm := false:
	set(value):
		alarm = value
		queue_redraw()

var _visitors: Array[Node] = []
var _time := 0.0


func setup(data: Dictionary) -> void:
	role = str(data.get("role", ""))
	label_text = str(data.get("label", role))
	radius = float(data.get("interact_radius", 14))
	position = Vector2(float(data.x), float(data.y))
	name = "Station_" + role


func color() -> Color:
	return ROLE_COLORS.get(role, Color.WHITE)


func can_reach(point: Vector2) -> bool:
	return point.distance_to(global_position) <= radius


func add_visitor(who: Node) -> void:
	if who not in _visitors:
		_visitors.append(who)
		queue_redraw()


func remove_visitor(who: Node) -> void:
	_visitors.erase(who)
	queue_redraw()


## Called by a crew member pressing interact while in range.
func use(_by: Node) -> void:
	Events.action_requested.emit(role, {type = "use_station", station = role})
	_time = 0.0


func _process(delta: float) -> void:
	_time += delta
	if alarm or not _visitors.is_empty():
		queue_redraw()


func _draw() -> void:
	var c := color()
	if alarm:
		# Blinking red ring while an event hits this station.
		if fmod(_time, 0.5) < 0.25:
			draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color("ff4040"), 1.0)
	if _visitors.is_empty():
		return
	# Pulsing ring + label when someone can use it.
	var pulse := 0.6 + 0.4 * sin(_time * 6.0)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(c, pulse), 1.0)
	var font := ThemeDB.fallback_font
	var size := 8
	var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-width / 2.0, -radius - 2), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
