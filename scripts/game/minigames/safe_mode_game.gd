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
var _frame := MinigameFrame.new("ENTER SAFE MODE", "safe", Color("ff9a3c"))
var _total := 0.0              # deadline when the game opened (for the bar)


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
	_total = deadline
	_canvas = Node2D.new()
	UiKit.setup_canvas(_canvas)
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
	_frame.step(delta)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	if _done:
		_outro += delta
		if _outro > 0.8:
			finished.emit({ok = true})
			queue_free()
		_canvas.queue_redraw()
		return
	if _t > ARM_TIME and Input.is_action_just_pressed(Controls.action("p1", "close")):
		Sfx.play("undock")
		abort()  # closed: the ticket stays, anyone can open it again
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
			_frame.stamp("SAFE MODE", UiKit.GOOD)
			Sfx.play("brownout", 1.4)
	else:
		_lock = LOCKOUT
		_flash = -1.0
		_shake = 1.0
		Sfx.play("denied")


func _draw_game() -> void:
	var c := _canvas
	var off := Vector2(roundf(sin(_t * 70.0) * 2.0 * _shake), 0)
	_frame.draw(c, deadline, _total, "RADIATION WAVE IN %.1fs", off)

	# Breaker row.
	var n := _names.size()
	var gap := 14.0
	var x0 := roundf(240.0 - (n * BREAKER.x + (n - 1) * gap) / 2.0 + off.x)
	var y0 := 98.0
	var target: int = _order[_next] if not _done else -1
	for i in n:
		var r := Rect2(x0 + i * (BREAKER.x + gap), y0, BREAKER.x, BREAKER.y)
		var is_off: bool = _off[i]
		var blink := i == target and fmod(_t, 0.4) < 0.25
		UiKit.panel(c, r, Color("2a221c"), UiKit.WARN if blink else Color("5a4a3a"))
		# Status lamp: green = live, dark = cut, yellow = cut me next.
		var lamp := Rect2(r.position + Vector2(BREAKER.x / 2.0 - 3, 5), Vector2(6, 6))
		UiKit.chip(c, lamp, Color("2c2c2c") if is_off else (UiKit.WARN if blink else UiKit.GOOD))
		# Switch slot + lever (up = on, down = off).
		var slot := Rect2(r.position + Vector2(BREAKER.x / 2.0 - 4, 16), Vector2(8, 24))
		c.draw_rect(slot.grow(1), UiKit.INK)
		c.draw_rect(slot, Color("0d0a08"))
		var lever_y := slot.end.y - 9 if is_off else slot.position.y + 1
		UiKit.chip(c, Rect2(slot.position.x - 2, lever_y, 12, 8), Color("8a93aa") if is_off else Color("e8ecf8"))
		UiKit.text_c(c, r.get_center().x, r.end.y - 4, _names[i], 6, UiKit.DIM if is_off else UiKit.TEXT, 0)
		# Order hint: the step number above each breaker once it is cut.
		if is_off:
			UiKit.text_c(c, r.get_center().x, r.position.y - 3, "%d" % (_order.find(i) + 1), 7, UiKit.GOOD)
		if i == _cursor and not _done:
			var col := UiKit.BAD if _lock > 0.0 else Color.WHITE
			var g := r.grow(3)
			for e in [Rect2(g.position, Vector2(g.size.x, 2)), Rect2(g.position.x, g.end.y - 2, g.size.x, 2),
					Rect2(g.position, Vector2(2, g.size.y)), Rect2(g.end.x - 2, g.position.y, 2, g.size.y)]:
				c.draw_rect(e, col)
			var tip := Vector2(roundf(r.get_center().x), r.end.y + 7)
			c.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 5), tip + Vector2(4, 5)]), col)

	if _flash != 0.0:
		var fc := Color(0.36, 0.94, 0.48, _flash * 0.25) if _flash > 0.0 else Color(1, 0.3, 0.3, -_flash * 0.25)
		c.draw_rect(MinigameFrame.RECT.grow(-3), fc)
	var hint := "SAFE MODE ON - SHIP POWERED DOWN" if _done else (
			"WRONG BREAKER!" if _lock > 0.0 else "CUT THE BLINKING BREAKER: A/D MOVE · %s FLIP" % Controls.key_name("p1", "interact"))
	_frame.draw_footer(c, hint, UiKit.GOOD if _done else (UiKit.BAD if _lock > 0.0 else UiKit.TEXT),
			"BREAKERS %d / %d · SIMPLIFIED" % [_next, n], off)
	_frame.draw_stamp(c, Vector2(240, 125))
