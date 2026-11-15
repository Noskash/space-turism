class_name RadarScreen
extends Node2D
## Bridge radar (think Barotrauma sonar): E opens / closes it while the local player is docked at the
## Bridge (closes on undock), so it never covers the station while someone holds SPACE to fix things.
## Forward is up, the ship sits at the bottom. A comet debris cloud appears ahead as blips that light
## up when the sweep passes, closing in as its countdown runs. The dotted line is the projected path.
## A/D at the Bridge = course burn (fuel): the heading changes a few degrees and the cloud slides
## sideways on the screen. Clear of it = it passes by. Inside = you fly through it (DodgeGame).
## Reads state.dust (cloud_y, cloud_w, course, time_left, duration). SIMPLIFIED distances.

const PANEL := Rect2(222, 38, 108, 132)
const CENTER := Vector2(276, 96)
const R := 46.0
const SCALE := 40.0               # px per lateral unit (state.dust course / cloud_y)
const SHIP_W := 0.12              # same as fake_mission
const DEG_PER_UNIT := 20.0

var map: ShipMap
var local: CrewMember
var _dust := {}
var _t := 0.0
var _sweep := 0.0
var _left := 0.0                  # debris countdown, run down locally between states
var _open := false


func _ready() -> void:
	name = "RadarScreen"
	z_index = 46
	Events.state_changed.connect(func(s: Dictionary) -> void:
		_dust = s.get("dust", {})
		_left = float(_dust.get("time_left", 0.0)))


func _docked() -> bool:
	return local != null and local.docked_station() != null and local.docked_station().role == "navigator"


func _shown() -> bool:
	return _open and _docked() and not Tutorial.is_blocking()


func _process(delta: float) -> void:
	_t += delta
	_left = maxf(_left - delta, 0.0)
	if not _docked():
		_open = false
	elif not Tutorial.is_blocking() and Input.is_action_just_pressed(Controls.action("p1", "radar")):
		_open = not _open
		Sfx.play("toggle" if _open else "undock", 1.3)
	var before := _sweep
	_sweep = fmod(_sweep + delta * 3.2, TAU)
	if _shown() and _warning():
		# Ping when the sweep crosses the cloud's bearing.
		var bearing := (_cloud_pos() - CENTER).angle()
		if _crossed(before, _sweep, bearing):
			Sfx.play("select", 2.2, -10.0)
	visible = _shown()
	queue_redraw()


func _warning() -> bool:
	return _dust.get("phase", "") == "warning"


func _crossed(a: float, b: float, x: float) -> bool:
	x = fposmod(x, TAU)
	return (a <= x and x < b) if b >= a else (x >= a or x < b)


## Cloud centre on the screen: relative to our heading, closer as the countdown runs out.
func _cloud_pos() -> Vector2:
	var ship := CENTER + Vector2(0, R * 0.72)
	var dur := maxf(float(_dust.get("duration", 12.0)), 0.1)
	var dist := lerpf(R * 0.12, R * 1.55, clampf(_left / dur, 0.0, 1.0))   # on the scope from the first second
	var lateral := (float(_dust.get("cloud_y", 0.0)) - float(_dust.get("course", 0.0))) * SCALE
	return ship + Vector2(lateral, -dist)


func _draw() -> void:
	var font := UiFont.font()
	draw_rect(PANEL, Color(0.0, 0.05, 0.03, 0.92))
	draw_rect(PANEL, Color("4fd8ff"), false, 1.0)
	draw_string(font, PANEL.position + Vector2(5, 9), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("4fd8ff"))
	# Scope: rings, cross, sweep with a fading trail.
	var green := Color(0.3, 1.0, 0.55)
	draw_circle(CENTER, R, Color(0.0, 0.12, 0.06))
	for k in 3:
		draw_arc(CENTER, R * (k + 1) / 3.0, 0, TAU, 40, Color(green, 0.25), 1.0)
	draw_line(CENTER - Vector2(R, 0), CENTER + Vector2(R, 0), Color(green, 0.15))
	draw_line(CENTER - Vector2(0, R), CENTER + Vector2(0, R), Color(green, 0.15))
	for k in 10:
		var a := _sweep - k * 0.06
		draw_line(CENTER, CENTER + Vector2.from_angle(a) * R, Color(green, 0.5 * (1.0 - k / 10.0)), 1.0)
	var ship := CENTER + Vector2(0, R * 0.72)
	var status := "NO CONTACTS"
	var status_col := Color(green, 0.7)
	if _warning():
		var cloud := _cloud_pos()
		var half := float(_dust.get("cloud_w", 0.42)) * SCALE
		var d := absf(float(_dust.get("course", 0.0)) - float(_dust.get("cloud_y", 0.0)))
		var w := float(_dust.get("cloud_w", 0.42))
		var clear := d >= w + SHIP_W
		var edge := not clear and d > w * 0.4
		# Cloud extent: a faint band so you see exactly where it sits across your path.
		for y in range(int(cloud.y) - 8, int(cloud.y) + 9, 2):
			for x in range(int(cloud.x - half), int(cloud.x + half) + 1, 3):
				var q := Vector2(x, y)
				if q.distance_to(CENTER) <= R - 1.0:
					draw_rect(Rect2(q, Vector2.ONE), Color(1.0, 0.55, 0.3, 0.25))
		# Projected corridor: the ship's width, straight ahead (red where it runs into the cloud).
		var corridor := SHIP_W * SCALE
		for y in range(int(ship.y) - 6, int(CENTER.y - R), -4):
			for side in [-corridor, corridor]:
				var p := Vector2(ship.x + side, y)
				if p.distance_to(CENTER) > R:
					continue
				var inside: bool = absf(p.x - cloud.x) < half and absf(p.y - cloud.y) < 9.0
				draw_rect(Rect2(p, Vector2(1, 2)), Color("ff5050") if inside or not clear and y < cloud.y + 9 and y > cloud.y - 9 else Color(green, 0.8))
		# Blips (fixed pattern per cloud), lit by the sweep.
		var bearing := (cloud - CENTER).angle()
		var lit := 1.0 - clampf(fposmod(_sweep - bearing, TAU) / 2.5, 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(_dust.get("cloud_y", 0.0)) * 1000.0) + 7
		for i in 26:
			var off := Vector2(rng.randf_range(-half, half), rng.randf_range(-7.0, 7.0))
			var p := cloud + off
			if p.distance_to(CENTER) <= R - 1.0:
				draw_rect(Rect2(p.round(), Vector2(2, 1) if i % 3 else Vector2(1, 1)),
						Color(1.0, 0.75, 0.4, 0.25 + 0.75 * lit))
		if clear:
			status = "CLEAR OF THE DEBRIS"
			status_col = Color("5cf07a")
		elif edge:
			status = "EDGE OF THE FIELD"
			status_col = Color("ffc640")
		else:
			status = "HEADING INTO IT"
			status_col = Color("ff5050") if fmod(_t, 0.5) < 0.35 else Color(1, 0.3, 0.3, 0.5)
		var info := "DEBRIS %ds   HDG %+d°" % [ceili(_left), roundi(float(_dust.get("course", 0.0)) * DEG_PER_UNIT)]
		draw_string(font, Vector2(PANEL.position.x + 5, PANEL.end.y - 24), info, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color.WHITE)
		draw_string(font, Vector2(PANEL.position.x + 5, PANEL.end.y - 5), "A/D: BURN 5° (FUEL) · E: CLOSE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("9aa4b8"))
	elif _dust.get("phase", "") in ["stream", "flying"]:
		status = "IN THE FIELD"
		status_col = Color("ff8a5c")
	# Our ship.
	draw_colored_polygon(PackedVector2Array([ship + Vector2(0, -5), ship + Vector2(-3, 3), ship + Vector2(3, 3)]), Color.WHITE)
	draw_string(font, Vector2(PANEL.position.x + 5, PANEL.end.y - 14), status, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), status_col)
