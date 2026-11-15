class_name TicketStrip
extends Control
## Row of ticket chips (Overcooked "orders"): role colour, station tag, countdown bar.
## Repairs (no timer) blink red with "FIX". Drawn right-to-left from the control's right edge.

const CHIP := Vector2(26, 11)
const GAP := 3.0
const TAGS := {"navigator": "NAV", "engineer": "PWR", "comms": "COM", "scientist": "SCI", "team": "PLAN"}
const ALERT_COLOR := Color("ff4040")
const FONT_SIZE := 8

var events: Array = []
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var font := UiFont.font()
	var x := size.x
	for event: Dictionary in events:
		x -= CHIP.x
		var rect := Rect2(Vector2(x, 0), CHIP)
		var c: Color = Station.ROLE_COLORS.get(event.role, Color.WHITE)
		var repair: bool = event.repair
		var urgent: bool = repair or (event.time_left >= 0.0 and event.time_left < 4.0)
		var border := ALERT_COLOR if repair else c
		if urgent and fmod(_time, 0.4) < 0.2:
			border = Color.WHITE
		draw_rect(rect, Color(0, 0, 0, 0.8))
		draw_rect(rect, border, false, 1.0)
		var tag: String = "FIX" if repair else TAGS.get(event.role, "?")
		var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x
		draw_string(font, Vector2(roundf(x + (CHIP.x - w) / 2.0), 8), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE), ALERT_COLOR if repair else c)
		if not repair and event.duration > 0.0:
			var left := clampf(event.time_left / event.duration, 0.0, 1.0)
			draw_rect(Rect2(x + 1, CHIP.y - 2, roundf((CHIP.x - 2) * left), 1), c)
		x -= GAP
