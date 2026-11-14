class_name ResourceBar
extends Control
## Animated HUD bar (0-100), drawn pixel-exact.
##   Big drop  -> fill slides down fast, a red "lost" segment lingers then drains,
##                the bar flashes and shakes 1px.
##   Gain      -> a light "incoming" segment appears at once, the fill grows into it.
##   Slow drain (small steps from the sim tick) -> just slides, no flash.
##   Below LOW -> the fill pulses as a warning.

const BIG_CHANGE := 2.0     # smaller steps count as continuous drain
const HOLD_TIME := 0.35     # how long the red "lost" segment waits before draining
const GHOST_SPEED := 60.0   # %/s the lost segment drains
const FLASH_TIME := 0.25
const SHAKE_TIME := 0.25
const LOW := 25.0

@export var color := Color.WHITE
@export var lost_color := Color("ff4a4a")

var _target := 100.0
var _fill := 100.0
var _ghost := 100.0   # end of the lost (drop) or incoming (gain) segment
var _hold := 0.0
var _flash := 0.0
var _shake := 0.0
var _time := 0.0


func set_value(value: float, instant := false) -> void:
	value = clampf(value, 0.0, 100.0)
	if instant:
		_target = value
		_fill = value
		_ghost = value
		queue_redraw()
		return
	if value < _fill - BIG_CHANGE:
		_ghost = maxf(_ghost, _fill)
		_hold = HOLD_TIME
		_flash = FLASH_TIME
		_shake = SHAKE_TIME
	_target = value


func _process(delta: float) -> void:
	_time += delta
	# Drops are fast, gains a bit slower so you can watch them fill.
	var rate := 18.0 if _target < _fill else 6.0
	_fill = lerpf(_fill, _target, 1.0 - exp(-rate * delta))
	if absf(_fill - _target) < 0.05:
		_fill = _target

	if _target > _ghost:
		_ghost = _target  # incoming segment shows the new value immediately
	elif _hold > 0.0:
		_hold -= delta
	else:
		_ghost = move_toward(_ghost, maxf(_fill, _target), GHOST_SPEED * delta)
	if _ghost < _fill:
		_ghost = _fill

	_flash = maxf(_flash - delta, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var shake_x := 0.0
	if _shake > 0.0:
		shake_x = 1.0 if int(_time * 30.0) % 2 == 0 else -1.0
	draw_set_transform(Vector2(shake_x, 0))

	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.6))
	var fill_px := roundf(w * _fill / 100.0)
	var ghost_px := roundf(w * _ghost / 100.0)

	if ghost_px > fill_px:
		var gaining := _target > _fill
		var seg_color := Color(color.lightened(0.5), 0.55) if gaining else lost_color
		draw_rect(Rect2(fill_px, 0, ghost_px - fill_px, h), seg_color)

	var fill_color := color
	if _flash > 0.0 and int(_time * 20.0) % 2 == 0:
		fill_color = Color.WHITE
	elif _target < LOW:
		fill_color = fill_color.lerp(Color("ff4a4a"), 0.5 + 0.5 * sin(_time * 8.0))
	if fill_px > 0:
		draw_rect(Rect2(0, 0, fill_px, h), fill_color)
		draw_rect(Rect2(0, 0, fill_px, 1), fill_color.lightened(0.35))  # top highlight
