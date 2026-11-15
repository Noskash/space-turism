class_name RadioSet
extends Node2D
## The ship radio as an object: a little boombox on the Mission Hub bench. Walk up to it and press
## SPACE to switch it on/off (CrewMember sends {type = "radio"}; the sim keeps state.radio, so in
## co-op everyone hears the same radio). Switching it on tunes to the next track.
## Music playback itself is Radio (radio.gd); this node only draws the set and the prompt.

const POS := Vector2(308, 143)      # on the bench (ship_layout obstacle "bench" 298,140 20x12)
const USE_POINT := Vector2(308, 158)
const REACH := 15.0

var crew: Node2D
var _on := false
var _powered := true
var _t := 0.0
var _notes: Array[Vector3] = []     # x, y, age


static func in_reach(point: Vector2) -> bool:
	return point.distance_to(USE_POINT) <= REACH


func _ready() -> void:
	name = "RadioSet"
	z_index = 45  # over the lighting, like the stations
	Events.state_changed.connect(func(s: Dictionary) -> void:
		_on = s.get("radio", {}).get("on", false)
		_powered = float(s.get("blackout", 0.0)) <= 0.0)


func _process(delta: float) -> void:
	_t += delta
	var playing := _on and _powered
	if playing and fmod(_t, 0.7) < delta:
		_notes.append(Vector3(POS.x + randf_range(-4, 4), POS.y - 6, 0.0))
	for i in range(_notes.size() - 1, -1, -1):
		var n := _notes[i]
		n.z += delta
		n.y -= delta * 9.0
		n.x += sin(n.z * 4.0 + i) * delta * 6.0
		if n.z > 1.6:
			_notes.remove_at(i)
		else:
			_notes[i] = n
	queue_redraw()


func _draw() -> void:
	var playing := _on and _powered
	var bob := Vector2(0, -1) if playing and fmod(_t, 0.5) < 0.25 else Vector2.ZERO  # bass thump
	var o := POS + bob - Vector2(7, 4)
	# Antenna, body, handle, two speakers, tuning strip and power LED.
	draw_line(o + Vector2(11, 0), o + Vector2(14, -6), Color("aab4c8"), 1.0)
	draw_rect(Rect2(o + Vector2(3, -2), Vector2(8, 2)), Color("3a4258"), false, 1.0)
	draw_rect(Rect2(o, Vector2(14, 8)), Color("2a3044"))
	draw_rect(Rect2(o, Vector2(14, 8)), Color("6b7390"), false, 1.0)
	for x in [3.5, 10.5]:
		draw_circle(o + Vector2(x, 4.5), 2.2, Color("12151f"))
		draw_circle(o + Vector2(x, 4.5), 1.0 + (0.6 if playing and fmod(_t * 4.0, 1.0) < 0.5 else 0.0), Color("5a6278"))
	draw_rect(Rect2(o + Vector2(6, 2), Vector2(2, 1)), Color("ffc640") if playing else Color("4a4030"))
	draw_rect(Rect2(o + Vector2(6, 5), Vector2(2, 2)), Color("5cf07a") if playing else Color("5a2020"))
	for n in _notes:
		var a := 1.0 - n.z / 1.6
		var p := Vector2(roundf(n.x), roundf(n.y))
		draw_rect(Rect2(p, Vector2(2, 2)), Color(1.0, 0.85, 0.45, a))
		draw_rect(Rect2(p + Vector2(1, -4), Vector2(1, 4)), Color(1.0, 0.85, 0.45, a))
	# Prompt for the local player standing next to it.
	if _local_near():
		var text := "SPACE: RADIO " + ("OFF" if _on else "ON")
		if not _powered:
			text = "RADIO: NO POWER"
		var font := UiFont.font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8)).x
		var box := Rect2(POS.x - w / 2.0 - 3, POS.y - 22, w + 6, 10)
		box.position.x = minf(box.position.x, 322.0 - box.size.x)
		draw_rect(box, Color(0, 0, 0, 0.8))
		draw_rect(box, Color("ffc640"), false, 1.0)
		draw_string(font, Vector2(box.position.x + 3, box.position.y + 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color.WHITE)
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_arc(USE_POINT, REACH - 3, 0, TAU, 20, Color(1.0, 0.78, 0.25, 0.4 + 0.4 * pulse), 1.0)


func _local_near() -> bool:
	if crew == null:
		return false
	for m in crew.get_children():
		if m is CrewMember and not m.remote and in_reach(m.global_position):
			return true
	return false
