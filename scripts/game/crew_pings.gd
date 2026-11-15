class_name CrewPings
extends Node2D
## Crew call-outs on the ship map (G key, CrewMember._ping -> {type = "ping"} -> state.pings).
## Each ping is a speech bubble where it was made ("HELP!", "NEED ENGINEER", "FIRE HERE!", "ON IT!")
## in the colour of who is needed, with a ring pulsing on the floor and a chirp. Read from sim state,
## so every co-op peer sees the same pings; each one shows for SHOW s from when this peer first saw it.

const SHOW := 3.0
const TINTS := {fire = Color("ff7a2a"), breach = Color("ff5050")}

var _shown: Array[Dictionary] = []   # {id, p, text, col, age}
var _seen := {}                      # ping ids already shown
var _juice := UiJuice.new()


func setup(game: Node2D) -> void:
	name = "CrewPings"
	z_index = 46                     # over the lighting, stations (45) and flames
	game.add_child(self)


func _ready() -> void:
	Events.state_changed.connect(_on_state)


func _on_state(state: Dictionary) -> void:
	for p: Dictionary in state.get("pings", []):
		var id := int(p.id)
		if _seen.has(id):
			continue
		_seen[id] = true
		var role := str(p.get("role", ""))
		var col: Color = TINTS.get(role, UiKit.role_color(role))
		# One bubble per player: a newer ping from the same person replaces theirs.
		_shown = _shown.filter(func(s: Dictionary) -> bool: return s.from != str(p.get("from", "")))
		_shown.append({id = id, from = str(p.get("from", "")), p = Vector2(p.x, p.y), text = str(p.text),
				col = col, age = 0.0})
		_juice.kick("ping_%d" % id, 0.35)
		Sfx.play("ping", 1.0 if role not in TINTS else 0.8)


func _process(delta: float) -> void:
	_juice.step(delta)
	for s in _shown:
		s.age += delta
	_shown = _shown.filter(func(s: Dictionary) -> bool: return s.age < SHOW)
	queue_redraw()


func _draw() -> void:
	for s: Dictionary in _shown:
		var at: Vector2 = (s.p as Vector2).round()
		var col: Color = s.col
		var fade := clampf((SHOW - float(s.age)) / 0.4, 0.0, 1.0)
		# Floor ring pulsing out (two rings, whole-pixel radii).
		for k in 2:
			var t := fmod(float(s.age) * 1.4 + k * 0.5, 1.0)
			draw_arc(at + Vector2(0, -1), roundf(4.0 + 12.0 * t), 0, TAU, 20, Color(col, (1.0 - t) * 0.8 * fade), 1.0)
		# Bubble: pops up from the ping spot, bobs a little.
		var label := str(s.text)
		var w := roundf(UiKit.text_w(label, 7) + 16)
		var h := maxf(12.0, UiKit.line_h(7) + 4)
		var lift := roundf(10.0 * (1.0 - _juice.k("ping_%d" % s.id)))
		var bob := roundf(sin(float(s.age) * 5.0))
		var r := Rect2(roundf(at.x - w / 2.0), at.y - 30.0 + lift + bob, w, h)
		r.position.x = clampf(r.position.x, 2.0, 478.0 - w)
		if fade < 1.0 and fmod(float(s.age), 0.16) < 0.08:
			continue   # blinks out at the end
		UiKit.panel(self, r, UiKit.PANEL_DARK, col)
		# Tail down to the ping spot.
		var tx := clampf(at.x, r.position.x + 4, r.end.x - 5)
		draw_rect(Rect2(tx - 1, r.end.y, 3, 2), UiKit.INK)
		draw_rect(Rect2(tx, r.end.y, 1, 3), col)
		UiKit.icon(self, "ping", Vector2(r.position.x + 3, r.position.y + roundf((h - 8) / 2.0)), 1, col)
		UiKit.text(self, Vector2(r.position.x + 13, r.end.y - 3), label, 7, col, 0)
