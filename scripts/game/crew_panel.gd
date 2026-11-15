class_name CrewPanel
extends CanvasLayer
## Bottom-left HUD block: one row per astronaut (data/astronauts.json) with their radiation dose.
## Bar = dose against NASA's 600 mSv career limit, tick = radiation sickness threshold.
## During a storm warning without shields each row says whether that astronaut is in the Cargo shelter.
## Reads only Events.state_changed (state.crew from the sim), so every co-op peer shows the same.

const ROW := 9.0
const BAR_W := 34.0
const BOTTOM := 240.0      # just above the radio / status line

var _canvas: Node2D
var _state := {}
var _time := 0.0


func _ready() -> void:
	layer = 2   # over the HUD (1), under the event guide (12) and minigames (15)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_panel)
	add_child(_canvas)
	Events.state_changed.connect(func(s: Dictionary) -> void: _state = s)


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()


func _draw_panel() -> void:
	var crew: Dictionary = _state.get("crew", {})
	if crew.is_empty():
		return
	var font := UiFont.font()
	var cme: Dictionary = _state.get("cme", {})
	var shelter_call: bool = cme.get("phase", "") == "warning" and not cme.get("shielding", false)
	var row_h := maxf(ROW, UiFont.px(7) + 2.0)
	var keys := crew.keys()
	keys.sort()
	var name_w := 0.0
	for key: String in keys:
		name_w = maxf(name_w, UiFont.width(Astronauts.short_name(crew[key].astronaut), 7))
	var w := name_w + BAR_W + UiFont.width("600", 6) + UiFont.width("OUTSIDE", 6) + 22
	var top := BOTTOM - row_h * keys.size() - 2
	_canvas.draw_rect(Rect2(28, top - 9, w, row_h * keys.size() + 11), Color(0, 0, 0, 0.55))
	_canvas.draw_string(font, Vector2(31, top - 2), "CREW DOSE mSv", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6),
			Color(0.6, 0.65, 0.8, 0.9))
	var limit := Astronauts.dose("nasa_limit")
	var sick_at := Astronauts.dose("sick_at")
	for i in keys.size():
		var a: Dictionary = crew[keys[i]]
		var info := Astronauts.info(a.astronaut)
		var y := top + i * row_h
		var base := y + row_h - 2
		var col := Color(str(info.get("color", "e8e8e8")))
		var sick := bool(a.get("sick", false))
		var x := 31.0
		_canvas.draw_string(font, Vector2(x, base), Astronauts.short_name(a.astronaut), HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiFont.px(7), Color("ff6a5a") if sick else col)
		x += name_w + 4
		var bar := Rect2(x, y + row_h / 2.0 - 2, BAR_W, 4)
		_canvas.draw_rect(bar, Color(1, 1, 1, 0.12))
		var k := clampf(float(a.dose) / limit, 0.0, 1.0)
		_canvas.draw_rect(Rect2(bar.position, Vector2(BAR_W * k, 4)), Color("ff5050") if sick else Color("ffd34a"))
		_canvas.draw_rect(Rect2(bar.position.x + BAR_W * sick_at / limit, bar.position.y - 1, 1, 6), Color(1, 1, 1, 0.6))
		x += BAR_W + 3
		_canvas.draw_string(font, Vector2(x, base), "%d" % int(a.dose), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6),
				Color("ff6a5a") if sick else Color(0.8, 0.84, 0.92))
		x += UiFont.width("600", 6) + 4
		if shelter_call:   # no shields: everyone must be in the Cargo bay when the wave hits
			var inside: bool = a.get("room", "") == "cargo"
			if inside or fmod(_time, 0.5) < 0.3:
				_canvas.draw_string(font, Vector2(x, base), "SHELTER" if inside else "OUTSIDE", HORIZONTAL_ALIGNMENT_LEFT, -1,
						UiFont.px(6), Color("5cf07a") if inside else Color("ff5050"))
		elif sick:
			_canvas.draw_string(font, Vector2(x, base), "SICK", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6), Color("ff6a5a"))
