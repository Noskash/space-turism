class_name SafeModeGame
extends CanvasLayer
## Put the ship in SAFE MODE before a radiation storm (Engine Room console, Engineer) - the defence of
## a ship WITHOUT radiation shielding. Power-down sequence: a row of breakers, the next one to cut
## blinks; A/D move the cursor, SPACE flips the breaker under it. Wrong breaker = short lockout.
## Order is random every storm. Rad-hard CPU: one breaker fewer. Emits `finished({ok})`.
## Real basis: probes ride out storms by switching non-essential loads off (safe mode). SIMPLIFIED.

signal finished(result: Dictionary)

const NAMES := ["SCIENCE", "TRANSMIT", "HEATER", "PAYLOAD", "AUX BUS"]
const ARM_TIME := 0.25          # ignore the SPACE press that opened the game
const LOCKOUT := 0.5
const BREAKER := Vector2(34, 54)

var breakers_needed := 4
var deadline := 9.0             # seconds until the wave (from the ticket)

var _canvas: Node2D
var _t := 0.0
var _names: Array = []          # breakers on the panel, left to right
var _order: Array = []          # indices into _names, the cut sequence
var _off: Array = []            # bool per breaker
var _next := 0                  # position in _order
var _cursor := 0
var _lock := 0.0
var _flash := 0.0               # >0 green, <0 red
var _shake := 0.0
var _done := false
var _outro := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 15
	_rng.randomize()
	var count := clampi(breakers_needed, 2, NAMES.size())
	_names = NAMES.slice(0, count)
	_off.resize(count)
	_off.fill(false)
	for i in count:
		_order.append(i)
	_order.shuffle()
	_cursor = count / 2
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_game)
	add_child(_canvas)
	Tutorial.hold(true)
	Sfx.play("page")


func _exit_tree() -> void:
	Tutorial.hold(false)


## The wave arrived (or the ticket vanished) while powering down.
func abort() -> void:
	if not _done:
		finished.emit({ok = false})
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	deadline -= delta
	_lock = maxf(_lock - delta, 0.0)
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	if _done:
		_outro += delta
		if _outro > 0.8:
			finished.emit({ok = true})
			queue_free()
		_canvas.queue_redraw()
		return
	if _t > ARM_TIME:
		if Input.is_action_just_pressed(Controls.action("p1", "left")):
			_cursor = wrapi(_cursor - 1, 0, _names.size())
			Sfx.play("select")
		if Input.is_action_just_pressed(Controls.action("p1", "right")):
			_cursor = wrapi(_cursor + 1, 0, _names.size())
			Sfx.play("select")
		if _lock <= 0.0 and Input.is_action_just_pressed(Controls.action("p1", "interact")):
			_flip()
	_canvas.queue_redraw()


func _flip() -> void:
	if _off[_cursor]:
		return
	if _cursor == _order[_next]:
		_off[_cursor] = true
		_next += 1
		_flash = 1.0
		Sfx.play("toggle", 0.8 + _next * 0.12)
		if _next >= _order.size():
			_done = true
			Sfx.play("brownout", 1.4)
	else:
		_lock = LOCKOUT
		_flash = -1.0
		_shake = 1.0
		Sfx.play("denied")


func _draw_game() -> void:
	var c := _canvas
	var font := UiFont.font()
	c.draw_rect(Rect2(-8, -8, 496, 286), Color(0.02, 0.01, 0.0, 0.82))
	var off := Vector2(sin(_t * 70.0) * 2.0 * _shake, 0)
	var panel := Rect2(Vector2(80, 40) + off, Vector2(320, 186))
	c.draw_rect(panel, Color("1a1410"))
	c.draw_rect(panel, Color("ff9a3c"), false, 1.0)
	_centered("ENTER SAFE MODE", 240 + off.x, 60, 14, Color("ff9a3c"))
	var wave := "RADIATION WAVE IN %.1fs" % maxf(deadline, 0.0)
	_centered(wave, 240 + off.x, 72, 8,
			Color("ffe14a") if fmod(_t, 0.5) < 0.35 or deadline > 4.0 else Color("ff5050"))

	# Breaker row.
	var n := _names.size()
	var gap := 14.0
	var x0 := 240.0 - (n * BREAKER.x + (n - 1) * gap) / 2.0 + off.x
	var y0 := 92.0
	var target: int = _order[_next] if not _done else -1
	for i in n:
		var r := Rect2(x0 + i * (BREAKER.x + gap), y0, BREAKER.x, BREAKER.y)
		var is_off: bool = _off[i]
		var blink := i == target and fmod(_t, 0.4) < 0.25
		c.draw_rect(r, Color("2a221c"))
		c.draw_rect(r, Color("ffc640") if blink else Color("5a4a3a"), false, 1.0)
		# Status lamp: green = live, dark = cut, yellow = cut me next.
		var lamp := r.position + Vector2(BREAKER.x / 2.0, 8)
		c.draw_circle(lamp, 3.0, Color("2c2c2c") if is_off else (Color("ffc640") if blink else Color("5cf07a")))
		# Switch slot + lever (up = on, down = off).
		var slot := Rect2(r.position + Vector2(BREAKER.x / 2.0 - 4, 16), Vector2(8, 24))
		c.draw_rect(slot, Color("0d0a08"))
		var lever_y := slot.end.y - 9 if is_off else slot.position.y + 1
		c.draw_rect(Rect2(slot.position.x - 2, lever_y, 12, 8), Color("8a93aa") if is_off else Color("e8ecf8"))
		_centered(_names[i], r.get_center().x, r.end.y - 4, 7, Color("6b7390") if is_off else Color("e8ecf8"))
		# Order hint: the step number above each breaker once it is cut.
		if is_off:
			_centered("%d" % (_order.find(i) + 1), r.get_center().x, r.position.y - 3, 7, Color("5cf07a"))
		if i == _cursor and not _done:
			var col := Color("ff5050") if _lock > 0.0 else Color.WHITE
			c.draw_rect(r.grow(3), col, false, 1.0)
			var tip := Vector2(r.get_center().x, r.end.y + 6)
			c.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 5), tip + Vector2(4, 5)]), col)

	if _flash != 0.0:
		var fc := Color(0.36, 0.94, 0.48, _flash * 0.25) if _flash > 0.0 else Color(1, 0.3, 0.3, -_flash * 0.25)
		c.draw_rect(panel, fc)
	var hint := "SAFE MODE ON - SHIP POWERED DOWN" if _done else (
			"WRONG BREAKER!" if _lock > 0.0 else "CUT THE BLINKING BREAKER: A/D MOVE · SPACE FLIP")
	_centered(hint, 240 + off.x, 182, 9, Color("5cf07a") if _done else (Color("ff5050") if _lock > 0.0 else Color.WHITE))
	_centered("BREAKERS %d / %d · SIMPLIFIED" % [_next, n], 240 + off.x, 198, 7, Color("6b7390"))


func _centered(text: String, cx: float, y: float, size: int, col: Color) -> void:
	_canvas.draw_string(UiFont.font(), Vector2(roundf(cx - UiFont.width(text, size) / 2.0), y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
