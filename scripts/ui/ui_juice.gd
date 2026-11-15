class_name UiJuice
extends RefCounted
## "Juice" timers for immediate-mode UI. kick() a key when something changes (always from a
## sim state diff, so every co-op peer sees the same thing), call step(delta) once a frame,
## and read k(key) in _draw(): 1.0 right after the kick, falling to 0.0 at the end.
##
##   pop    numbers / icons scale up and settle      flash  white blink for a few frames
##   shake  +-1 px horizontal jitter                  bounce whole-pixel hop up
## All offsets are whole pixels so nothing leaves the 480x270 grid.

var _t := {}   # key -> [time_left, duration]
var _clock := 0.0


func kick(key: String, duration := 0.3) -> void:
	_t[key] = [duration, duration]


func step(delta: float) -> void:
	_clock += delta
	for key: String in _t.keys():
		_t[key][0] -= delta
		if _t[key][0] <= 0.0:
			_t.erase(key)


## 1 -> 0 over the kick's duration (0 when idle).
func k(key: String) -> float:
	if not _t.has(key):
		return 0.0
	return clampf(_t[key][0] / _t[key][1], 0.0, 1.0)


func active(key: String) -> bool:
	return _t.has(key)


## Scale for a pop: 1 + amount at the kick, easing back to 1.
func pop(key: String, amount := 0.4) -> float:
	var v := k(key)
	return 1.0 + amount * v * v


## Alternating frames while active.
func flash(key: String) -> bool:
	return active(key) and int(_clock * 30.0) % 2 == 0


## +-1 px while active.
func shake(key: String) -> Vector2:
	if not active(key):
		return Vector2.ZERO
	return Vector2(1 if int(_clock * 30.0) % 2 == 0 else -1, 0)


## Whole-pixel hop: up `height` px and back.
func bounce(key: String, height := 3.0) -> float:
	var v := k(key)
	if v <= 0.0:
		return 0.0
	return -roundf(height * sin(v * PI))


## Seconds since this juice object started (for blinking).
func clock() -> float:
	return _clock


func blink(period := 0.5, on := 0.6) -> bool:
	return fmod(_clock, period) < period * on
