class_name ResourceBar
extends RefCounted
## One animated resource row for the HUD's resource block: icon + segmented bar + number.
## Feed it the sim value with set_value(), step() it every frame, draw() it in the HUD's _draw.
##   Big drop  -> fill slides down fast, red "lost" segments linger then drain, the bar flashes
##                and shakes 1 px, the number pops red, the icon jolts.
##   Gain      -> light "incoming" segments appear at once, the fill grows into them, the number
##                pops and the icon hops.
##   Slow drain (small steps from the sim tick) -> just slides, no flash.
##   Warning   -> below `low` (or above `high` for storage) the bar and icon pulse red.

const BIG_CHANGE := 2.0     # smaller steps count as continuous drain
const HOLD_TIME := 0.35     # how long the red "lost" segments wait before draining
const GHOST_SPEED := 60.0   # %/s the lost segments drain
const SEGMENTS := 10
const SEG_W := 4

var key := ""
var icon := ""
var color := Color.WHITE
var low := 25.0             # warn below this...
var high := 101.0           # ...or above this (storage filling up)

var _target := 100.0
var _fill := 100.0
var _ghost := 100.0
var _hold := 0.0
var _juice := UiJuice.new()
var _started := false


func _init(p_key: String, p_icon: String, p_color: Color) -> void:
	key = p_key
	icon = p_icon
	color = p_color


func set_value(value: float) -> void:
	value = clampf(value, 0.0, 100.0)
	if not _started:  # no animation on spawn
		_started = true
		_target = value
		_fill = value
		_ghost = value
		return
	if value < _fill - BIG_CHANGE:
		_ghost = maxf(_ghost, _fill)
		_hold = HOLD_TIME
		_juice.kick("flash", 0.2)
		_juice.kick("shake", 0.25)
		_juice.kick("drop", 0.35)
	elif value > _target + BIG_CHANGE:
		_juice.kick("gain", 0.35)
	if int(value) != int(_target):
		_juice.kick("pop", 0.18)
	_target = value


func value() -> float:
	return _target


func warning() -> bool:
	return _target < low or _target > high


func step(delta: float) -> void:
	_juice.step(delta)
	var rate := 18.0 if _target < _fill else 6.0
	_fill = lerpf(_fill, _target, 1.0 - exp(-rate * delta))
	if absf(_fill - _target) < 0.05:
		_fill = _target
	if _target > _ghost:
		_ghost = _target
	elif _hold > 0.0:
		_hold -= delta
	else:
		_ghost = move_toward(_ghost, maxf(_fill, _target), GHOST_SPEED * delta)
	_ghost = maxf(_ghost, _fill)


## Row height at the current text size.
static func row_height() -> float:
	return maxf(8.0, roundf(UiKit.ascent(8)) + 1.0)


## Row width at the current text size.
static func row_width() -> float:
	return 8 + 3 + UiKit.seg_bar_width(SEGMENTS, SEG_W) + 3 + UiKit.text_w("100", 8)


func draw(ci: CanvasItem, at: Vector2) -> void:
	var h := row_height()
	var warn := warning()
	var blink := warn and _juice.blink(0.5)
	# Icon: hops on a gain, jolts on a drop, blinks red while in warning.
	var icon_y := at.y + roundf((h - 8) / 2.0) + _juice.bounce("gain", 2.0) + (1.0 if _juice.active("drop") else 0.0)
	UiKit.icon(ci, icon, Vector2(at.x, icon_y), 1, UiKit.BAD if blink else color)
	# Bar.
	var bw := UiKit.seg_bar_width(SEGMENTS, SEG_W)
	var bar := Rect2(at + Vector2(11, roundf((h - 6) / 2.0)) + _juice.shake("shake"), Vector2(bw, 6))
	var fill_col := color
	if warn:
		fill_col = color.lerp(UiKit.BAD, 0.5 + 0.5 * sin(_juice.clock() * 8.0))
	var gaining := _target > _fill + 0.5
	var ghost_col := Color(color.lightened(0.55), 0.8) if gaining else UiKit.BAD
	UiKit.seg_bar(ci, bar, _fill / 100.0, fill_col, SEGMENTS, _ghost / 100.0, ghost_col, _juice.flash("flash"))
	# Number: pops on change, red on a drop, green on a gain.
	var num := str(int(roundf(_target)))
	var num_col := UiKit.TEXT
	if _juice.active("drop"):
		num_col = UiKit.BAD
	elif _juice.active("gain"):
		num_col = UiKit.GOOD
	elif warn:
		num_col = UiKit.BAD if blink else UiKit.TEXT
	var s := _juice.pop("pop", 0.35)
	var nx := at.x + 11 + bw + 3
	var base := at.y + h - 1
	if s > 1.01:
		ci.draw_set_transform(Vector2(nx, base), 0.0, Vector2(s, s))
		UiKit.text(ci, Vector2.ZERO, num, 8, num_col)
		ci.draw_set_transform(Vector2.ZERO)
	else:
		UiKit.text(ci, Vector2(nx, base), num, 8, num_col)
