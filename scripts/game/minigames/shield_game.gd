class_name ShieldGame
extends CanvasLayer
## Raise the radiation shields (Mission Hub holo-table, any crew member). Timing minigame:
## a needle sweeps the capacitor gauge, press SPACE while it is in the green zone to charge one
## capacitor. Miss = short lockout. Charge them all before the wave hits (rad-hard CPU: one fewer).
## Each charge makes the needle faster and the zone smaller. Emits `finished({ok})`.
## SIMPLIFIED: real probes protect electronics with shielding mass + safe modes, not force fields.

signal finished(result: Dictionary)

const GAUGE := Rect2(110, 150, 260, 14)
const ARM_TIME := 0.25          # ignore the SPACE press that opened the game
const LOCKOUT := 0.4

var charges_needed := 3
var deadline := 15.0            # seconds until the wave (from the ticket)

var _canvas: Node2D
var _t := 0.0
var _needle := 0.0              # 0..1 across the gauge
var _dir := 1.0
var _speed := 0.9               # gauge widths per second
var _zone := Vector2(0.55, 0.72)
var _charged := 0
var _lock := 0.0
var _flash := 0.0               # >0 green flash, <0 red flash
var _done := false
var _outro := 0.0
var _aborted := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 15
	_rng.randomize()
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_game)
	add_child(_canvas)
	_new_zone()
	Tutorial.hold(true)
	Sfx.play("page")


func _exit_tree() -> void:
	Tutorial.hold(false)


## The wave arrived (or the ticket vanished) while charging.
func abort() -> void:
	if not _done:
		_aborted = true
		finished.emit({ok = false})
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	deadline -= delta
	_lock = maxf(_lock - delta, 0.0)
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	if _done:
		_outro += delta
		if _outro > 0.8:
			finished.emit({ok = true})
			queue_free()
		_canvas.queue_redraw()
		return
	_needle += _dir * _speed * delta
	if _needle >= 1.0 or _needle <= 0.0:
		_needle = clampf(_needle, 0.0, 1.0)
		_dir = -_dir
	if _t > ARM_TIME and _lock <= 0.0 and Input.is_action_just_pressed(Controls.action("p1", "interact")):
		if _needle >= _zone.x and _needle <= _zone.y:
			_charged += 1
			_flash = 1.0
			Sfx.play("fixed", 0.9 + _charged * 0.15)
			if _charged >= charges_needed:
				_done = true
				Sfx.play("orbit")
			else:
				_speed += 0.35
				_new_zone()
		else:
			_lock = LOCKOUT
			_flash = -1.0
			Sfx.play("denied")
	_canvas.queue_redraw()


func _new_zone() -> void:
	var w := clampf(0.2 - _charged * 0.035, 0.1, 0.2)
	var a := _rng.randf_range(0.08, 0.92 - w)
	if absf(a + w / 2.0 - _needle) < 0.2:  # not right under the needle
		a = fposmod(a + 0.4, 0.92 - w)
	_zone = Vector2(a, a + w)


func _draw_game() -> void:
	var c := _canvas
	var font := UiFont.font()
	c.draw_rect(Rect2(-8, -8, 496, 286), Color(0.0, 0.02, 0.05, 0.82))
	var panel := Rect2(90, 40, 300, 180)
	c.draw_rect(panel, Color("0e1424"))
	c.draw_rect(panel, Color("4fd8ff"), false, 1.0)
	var title := "RAISE THE SHIELDS"
	c.draw_string(font, Vector2(240 - UiFont.width(title, 14) / 2.0, 60), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("4fd8ff"))
	var wave := "RADIATION WAVE IN %.1fs" % maxf(deadline, 0.0)
	c.draw_string(font, Vector2(240 - UiFont.width(wave, 8) / 2.0, 72), wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color("ffe14a") if fmod(_t, 0.5) < 0.35 or deadline > 4.0 else Color("ff5050"))

	# The ship with its shield bubble filling up charge by charge.
	var center := Vector2(240, 108)
	c.draw_rect(Rect2(center - Vector2(16, 6), Vector2(32, 12)), Color("8a93aa"))
	c.draw_rect(Rect2(center + Vector2(16, -3), Vector2(6, 6)), Color("8a93aa"))
	c.draw_rect(Rect2(center - Vector2(28, 2), Vector2(12, 4)), Color("2c5aa8"))
	c.draw_rect(Rect2(center + Vector2(-6, -14), Vector2(12, 4)), Color("2c5aa8"))
	var k := float(_charged) / charges_needed
	if k > 0.0:
		var pulse := 0.6 + 0.4 * sin(_t * 8.0)
		var pts := PackedVector2Array()
		var seg := 40
		for i in seg + 1:
			var a := -PI / 2.0 + TAU * k * i / seg
			pts.append(center + Vector2(cos(a) * 44.0, sin(a) * 26.0))
		c.draw_polyline(pts, Color(0.4, 0.85, 1.0, 0.5 + 0.4 * pulse), 2.0)
		if _done:
			c.draw_circle(center, 1.0, Color.WHITE)
			for r in 3:
				c.draw_arc(center, 30.0 + r * 4 + fmod(_t * 30.0, 4.0), 0, TAU, 32, Color(0.5, 0.9, 1.0, 0.25), 1.0)

	# Capacitors.
	var cap_w := 18.0
	var start_x := 240.0 - charges_needed * (cap_w + 4) / 2.0
	for i in charges_needed:
		var r := Rect2(start_x + i * (cap_w + 4), 132, cap_w, 8)
		c.draw_rect(r, Color("4fd8ff") if i < _charged else Color("1d2a4a"))
		c.draw_rect(r, Color("4fd8ff"), false, 1.0)

	# Gauge, zone, needle.
	var flash_col := Color(0.36, 0.94, 0.48, _flash) if _flash > 0.0 else Color(1, 0.3, 0.3, -_flash)
	c.draw_rect(GAUGE.grow(2), flash_col if _flash != 0.0 else Color("1d2a4a"))
	c.draw_rect(GAUGE, Color("0a0e1a"))
	var zone := Rect2(GAUGE.position.x + GAUGE.size.x * _zone.x, GAUGE.position.y, GAUGE.size.x * (_zone.y - _zone.x), GAUGE.size.y)
	c.draw_rect(zone, Color(0.36, 0.94, 0.48, 0.55 + 0.2 * sin(_t * 10.0)))
	var nx := GAUGE.position.x + GAUGE.size.x * _needle
	c.draw_rect(Rect2(nx - 1, GAUGE.position.y - 4, 3, GAUGE.size.y + 8), Color("ff5050") if _lock > 0.0 else Color.WHITE)

	var hint := "PRESS SPACE IN THE GREEN ZONE" if not _done else "SHIELDS UP!"
	c.draw_string(font, Vector2(240 - UiFont.width(hint, 10) / 2.0, 190), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color("5cf07a") if _done else Color.WHITE)
	var sub := "CAPACITORS %d / %d · SIMPLIFIED" % [_charged, charges_needed]
	c.draw_string(font, Vector2(240 - UiFont.width(sub, 7) / 2.0, 204), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("6b7390"))
