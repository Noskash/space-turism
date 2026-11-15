class_name HangarDecor
extends Node2D
## Hand-drawn, animated pixel props for the assembly hangar: two computer desks (scrolling flight
## software / telemetry graph), potted plants (a fern, pink and yellow flowers that sway), a steaming
## coffee mug and the crew boombox (the hangar radio; speakers thump and notes float up while it plays).
## Each prop is its own node in the y-sorted crew layer, origin = its feet (bottom centre), so the crew
## walks in front of / behind it. Floor props are walls too (obstacles()).
## Motes (inner class) = dust drifting through the skylight shafts of HangarLighting.

const INK := Color("06070f")
const SHADOW := Color(0, 0, 0, 0.28)

const ITEMS := [
	{kind = "computer", x = 26, y = 80, variant = "code"},
	{kind = "computer", x = 456, y = 98, variant = "graph"},
	{kind = "fern", x = 16, y = 119},
	{kind = "flower", x = 133, y = 219, variant = "pink"},
	{kind = "flower", x = 356, y = 217, variant = "yellow"},
	{kind = "mug", x = 131, y = 99},
	{kind = "radio", x = 375, y = 100},
]
## Collision per kind, relative to the feet. Bench props (mug, radio) sit on a bench that is already a wall.
const BLOCK := {
	computer = Rect2(-15, -8, 30, 8),
	fern = Rect2(-5, -5, 10, 5),
	flower = Rect2(-4, -4, 8, 4),
}
const RADIO_USE := Vector2(397, 101)   # stand at the bench's right end (the prompt then clears the set)
const RADIO_REACH := 14.0

var kind := ""
var variant := ""
var on := false                        # radio: playing
var _t := 0.0
var _phase := 0.0
var _notes: Array[Vector4] = []        # x, y, age, colour index


## Creates every prop under `parent` (the y-sorted crew node). Returns them.
static func spawn(parent: Node) -> Array[HangarDecor]:
	var out: Array[HangarDecor] = []
	for it: Dictionary in ITEMS:
		var d := HangarDecor.new()
		d.kind = it.kind
		d.variant = str(it.get("variant", ""))
		d.position = Vector2(it.x, it.y)
		d.name = "Decor_" + d.kind
		d._phase = float(it.x) * 0.13
		parent.add_child(d)
		out.append(d)
	return out


static func obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for it: Dictionary in ITEMS:
		if BLOCK.has(it.kind):
			var r: Rect2 = BLOCK[it.kind]
			out.append(Rect2(r.position + Vector2(it.x, it.y), r.size))
	return out


## 0..1 bass thump while the radio plays (~120 BPM), shared by the speakers and the light.
static func beat(t: float) -> float:
	return pow(maxf(sin(t * TAU * 2.0), 0.0), 6.0)


func _process(delta: float) -> void:
	_t += delta
	if kind == "radio":
		if on and fmod(_t, 0.55) < delta:
			_notes.append(Vector4(randf_range(-6, 6), -16, 0.0, randi() % 3))
		for i in range(_notes.size() - 1, -1, -1):
			var n := _notes[i]
			n.z += delta
			n.y -= delta * 11.0
			n.x += sin(n.z * 4.0 + i) * delta * 7.0
			if n.z > 1.8:
				_notes.remove_at(i)
			else:
				_notes[i] = n
	queue_redraw()


func _draw() -> void:
	match kind:
		"computer": _draw_computer()
		"fern": _draw_fern()
		"flower": _draw_flower()
		"mug": _draw_mug()
		"radio": _draw_radio()


func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func _dot(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.round(), Vector2.ONE), c)


# --- computer desk -----------------------------------------------------------------------

func _draw_computer() -> void:
	_r(-15, -1, 31, 2, SHADOW)
	# legs + desk top
	_r(-15, -10, 3, 10, INK)
	_r(12, -10, 3, 10, INK)
	_r(-14, -9, 1, 9, Color("3a4258"))
	_r(13, -9, 1, 9, Color("3a4258"))
	_r(-16, -14, 32, 5, INK)
	_r(-15, -13, 30, 2, Color("7a84a0"))
	_r(-15, -11, 30, 1, Color("4a5470"))
	# tower PC
	_r(7, -24, 8, 11, INK)
	_r(8, -23, 6, 9, Color("5a6480"))
	_r(13, -23, 1, 9, Color("454e68"))
	_r(9, -21, 3, 1, Color("2a3044"))
	_r(9, -19, 3, 1, Color("2a3044"))
	var led := fmod(_t * 1.3 + _phase, 1.0) < 0.6
	_r(9, -16, 1, 1, Color("5cf07a") if led else Color("1e4028"))
	_r(11, -16, 1, 1, Color("ffc640") if fmod(_t * 7.0, 1.0) < 0.3 else Color("40381e"))
	# keyboard
	_r(-11, -13, 12, 2, INK)
	_r(-10, -13, 10, 1, Color("b4bcd0"))
	for k in 5:
		_r(-10 + k * 2, -12, 1, 1, Color("6a7490"))
	# monitor
	var green := variant == "code"
	var fg := Color("5cf07a") if green else Color("4fd8ff")
	_r(-12, -29, 17, 14, INK)
	_r(-11, -28, 15, 12, Color("6a7490"))
	_r(-11, -17, 15, 1, Color("4a5470"))
	_r(-10, -27, 13, 9, Color("08140f") if green else Color("06101c"))
	_r(-4, -15, 3, 2, INK)
	if green:
		# flight software scrolling past
		var step := int(_t * 2.5)
		for row in 4:
			var h := hash(step + row) % 9
			_r(-9 + (h % 2), -26 + row * 2, 2 + h, 1, Color(fg, 0.55 + 0.45 * float(row == 3)))
		if fmod(_t, 0.8) < 0.4:
			_r(-9 + 2 + hash(step + 3) % 9 + 1, -20, 1, 1, Color.WHITE)
	else:
		# telemetry: a dim grid line and a moving trace
		_r(-10, -22, 13, 1, Color(fg, 0.25))
		for x in 13:
			var y := -22.0 + roundf(sin((x + _t * 7.0) * 0.55) * 2.0 + sin((x - _t * 3.0) * 1.3))
			_r(-10 + x, y, 1, 1, Color(fg, 0.5 + 0.5 * float(x == 12)))
	_r(-10, -27, 2, 1, Color(1, 1, 1, 0.35))   # glass glare


# --- plants ------------------------------------------------------------------------------

func _pot(w: int) -> void:
	var hw := int(w / 2.0)
	_r(-hw - 1, 0, w + 2, 1, SHADOW)
	_r(-hw - 1, -9, w + 2, 4, INK)
	_r(-hw, -6, w, 6, INK)
	_r(-hw, -8, w, 2, Color("e07a4a"))
	_r(-hw, -8, w, 1, Color("f09a62"))
	_r(-hw + 1, -6, w - 2, 5, Color("a54c2c"))
	_r(hw - 3, -6, 2, 5, Color("7e3820"))
	_r(-hw + 1, -9, w - 2, 1, Color("3a2418"))


## Pixel line from a to b (whole pixels).
func _stem(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		_dot(a.lerp(b, float(i) / maxf(n, 1)), c)


func _draw_fern() -> void:
	var dark := Color("2a7044")
	var mid := Color("3aa05a")
	var light := Color("6cd88a")
	for i in 7:
		var ang := lerpf(-2.55, -0.6, i / 6.0) + sin(_t * 1.2 + _phase + i * 0.9) * 0.07
		var length := 13.0 - absf(i - 3.0) * 1.2
		var dir := Vector2(cos(ang), sin(ang))
		for s in int(length):
			var f := s / length
			var p := Vector2(0, -9) + dir * s + Vector2(0, f * f * 6.0)   # fronds arch over
			_dot(p + Vector2(1, 1), dark)
			_dot(p, mid if i % 2 == 0 else light)
			if s > 2 and s % 2 == 0:
				var side := Vector2(-dir.y, dir.x)
				_dot(p + side, light)
				_dot(p - side, mid)
	_pot(10)


func _draw_flower() -> void:
	var petal := Color("ff7ab0") if variant == "pink" else Color("ffd84a")
	var petal_dark := Color("d04880") if variant == "pink" else Color("d8a020")
	var heart := Color("ffe46a") if variant == "pink" else Color("8a4a20")
	var stem := Color("3aa05a")
	var tips := [Vector2(-4, -16), Vector2(0, -20), Vector2(4, -15)]
	for i in 3:
		var sway := roundf(sin(_t * 1.6 + _phase + i * 1.7) * 1.2)
		var base := Vector2(i - 1, -9)
		var tip: Vector2 = tips[i] + Vector2(sway, 0)
		_stem(base, tip, stem)
		var mid := base.lerp(tip, 0.5).round()
		_r(mid.x + (1 if i != 0 else -2), mid.y, 2, 1, Color("6cd88a"))
		# bloom: plus-shaped petals with a darker underside and a bright heart
		_r(tip.x - 2, tip.y - 1, 5, 3, INK)
		_r(tip.x - 1, tip.y - 2, 3, 5, INK)
		_r(tip.x - 1, tip.y - 1, 3, 3, petal)
		_r(tip.x - 1, tip.y + 1, 3, 1, petal_dark)
		_dot(tip, heart)
	_pot(8)


# --- bench props -------------------------------------------------------------------------

func _draw_mug() -> void:
	_r(-3, -6, 7, 6, INK)
	_r(4, -5, 2, 3, INK)
	_r(-2, -5, 5, 4, Color("e8e8f0"))
	_r(2, -5, 1, 4, Color("b8bccc"))
	_r(-2, -5, 5, 1, Color("5a3420"))
	_r(-1, -3, 2, 1, Color("4fd8ff"))   # NASA-blue stripe
	for k in 3:
		var ph := fmod(_t * 0.7 + k / 3.0, 1.0)
		var p := Vector2(roundf(sin(ph * 6.0 + k * 2.0) * 1.5), -7.0 - ph * 11.0)
		_dot(p, Color(1, 1, 1, (1.0 - ph) * 0.55))


func _draw_radio() -> void:
	var b := beat(_t) if on else 0.0
	var o := Vector2(0, -1 if b > 0.5 else 0)
	_r(-12, -1, 24, 2, SHADOW)
	# antenna + handle
	_stem(o + Vector2(7, -13), o + Vector2(11, -21), Color("aab4c8"))
	_dot(o + Vector2(11, -22), Color("ffc640") if on else Color("6b7390"))
	_r(o.x - 6, o.y - 16, 12, 1, INK)
	_r(o.x - 6, o.y - 16, 1, 4, INK)
	_r(o.x + 5, o.y - 16, 1, 4, INK)
	# body
	_r(o.x - 12, o.y - 13, 24, 13, INK)
	_r(o.x - 11, o.y - 12, 22, 11, Color("c8484a"))
	_r(o.x - 11, o.y - 12, 22, 1, Color("ec7a76"))
	_r(o.x - 11, o.y - 2, 22, 1, Color("86283a"))
	# speakers
	for cx in [-6, 6]:
		var c := o + Vector2(cx, -6)
		_r(c.x - 3, c.y - 3, 7, 7, INK)
		_r(c.x - 2, c.y - 2, 5, 5, Color("3a3a48"))
		var cone := 1 if b > 0.4 else 0
		_r(c.x - 1 - cone, c.y - 1 - cone, 3 + cone * 2, 3 + cone * 2, Color("6a6a7c"))
		_dot(c, Color("c8c8d8"))
	# cassette window with turning reels
	_r(o.x - 2, o.y - 10, 5, 4, INK)
	_r(o.x - 1, o.y - 9, 3, 2, Color("d8d0c0"))
	if on:
		_dot(o + Vector2(-1 + int(_t * 6.0) % 3, -9 + int(_t * 6.0) % 2), Color("5a4a3a"))
	# tuning strip + power LED
	_r(o.x - 9, o.y - 12, 3, 1, Color("ffc640") if on else Color("4a4030"))
	_dot(o + Vector2(9, -11), Color("5cf07a") if on else Color("5a2020"))
	# notes
	var cols := [Color("ff7ab0"), Color("ffd84a"), Color("4fd8ff")]
	for n in _notes:
		var a := 1.0 - n.z / 1.8
		var c: Color = cols[int(n.w)]
		c.a = a
		var p := Vector2(roundf(n.x), roundf(n.y))
		_r(p.x, p.y, 2, 2, c)
		_r(p.x + 1, p.y - 4, 1, 4, c)
		_r(p.x + 2, p.y - 4, 1, 1, c)


## Dust drifting through the skylight shafts: bright inside a shaft, barely visible outside.
class Motes extends Node2D:
	var _p: Array[Vector3] = []   # x, y, phase
	var _t := 0.0

	func _ready() -> void:
		name = "Motes"
		for i in 46:
			_p.append(Vector3(randf_range(150, 380), randf_range(30, 230), randf() * TAU))

	func _process(delta: float) -> void:
		_t += delta
		for i in _p.size():
			var m := _p[i]
			m.x += (-1.2 + sin(_t * 0.6 + m.z) * 1.5) * delta
			m.y += (2.0 + cos(_t * 0.5 + m.z) * 1.2) * delta
			if m.y > 235.0 or m.x < 140.0:
				m = Vector3(randf_range(220, 390), 30.0, m.z)
			_p[i] = m
		queue_redraw()

	func _draw() -> void:
		for m in _p:
			var u := m.x + m.y * 0.55
			var lit := maxf(maxf(_band(u, 292.0, 13.0), 0.6 * _band(u, 318.0, 6.0)), 0.85 * _band(u, 352.0, 10.0))
			var a := (0.08 + 0.7 * lit) * (0.7 + 0.3 * sin(_t * 2.0 + m.z)) * clampf(1.0 - m.y / 240.0, 0.0, 1.0)
			draw_rect(Rect2(Vector2(m.x, m.y).round(), Vector2.ONE), Color(0.92, 0.95, 1.0, a))

	static func _band(u: float, centre: float, half_w: float) -> float:
		return 1.0 - smoothstep(half_w * 0.4, half_w, absf(u - centre))
