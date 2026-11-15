class_name HullDamage
extends Node2D
## Hull breaches + toolbox lockers on the ship map (sim side: fake_mission `_impact`, state.breaches).
##
## A breach is a hole in the floor/wall venting air: dark jagged hole, blinking hazard ring, dust and
## loose bits sucked into it, a hiss loop while any is open. To seal one:
##   1. grab a toolbox at a locker (Cargo or Engine Room): walk up, SPACE (SPACE again puts it back).
##      SPACE anywhere else drops it on the floor (state.toolboxes); anyone can pick it up there.
##   2. walk to the hole and HOLD SPACE until the ring fills -> {type = "patch", id} to the sim.
## CrewMember does the input (it asks `locker_in_reach` / `breach_near`); this node draws everything.
## Holes are drawn on a floor layer (under the crew, lit by ShipLighting); prompts and rings on top.

const LOCKERS := [Vector2(386, 240), Vector2(132, 226)]   # Cargo, Engine Room (use points)
const LOCKER_REACH := 13.0
const BREACH_REACH := 14.0
const PATCH_TIME := 2.5
const PICKUP_REACH := 10.0

static var current: HullDamage

var crew: Node2D                 # to find the local crew member for prompts
var breaches: Array = []         # state.breaches [{id, x, y}]
var oxygen := 100.0
var toolboxes: Array = []        # state.toolboxes [{id, x, y}] dropped on the floor
var patch_id := -1               # breach the local player is patching (set by CrewMember)
var patch_progress := 0.0
var _floor: Node2D
var _t := 0.0
var _bits: Array[Dictionary] = []   # dust and loose bits being sucked into the holes
var _rng := RandomNumberGenerator.new()


func setup(game: Node2D, map: ShipMap, crew_root: Node2D) -> void:
	crew = crew_root
	name = "HullDamage"
	z_index = 45                 # prompts + rings over the lighting, like stations
	_floor = Node2D.new()
	_floor.name = "HullFloor"
	_floor.draw.connect(_draw_floor)
	game.add_child(_floor)
	game.move_child(_floor, map.get_index() + 1)
	game.add_child(self)


func _ready() -> void:
	current = self
	_rng.randomize()
	Events.state_changed.connect(_on_state)


func _exit_tree() -> void:
	if current == self:
		current = null
	Sfx.set_loop("hiss", false)


func _on_state(state: Dictionary) -> void:
	var was := breaches.size()
	breaches = state.get("breaches", [])
	toolboxes = state.get("toolboxes", [])
	oxygen = float(state.get("oxygen", 100.0))
	if breaches.size() > was:
		Sfx.play("explode", 1.3, -4.0)
		Sfx.play("alarm")
	Sfx.set_loop("hiss", not breaches.is_empty() and state.get("lost", "") == "")


## This mission uses the hull system (breaches, toolboxes, oxygen). Off = lockers hidden and unusable
## (kept in the code for the missions that need it - data/missions.json "hull").
static func enabled() -> bool:
	return bool(Missions.sim().get("hull", true))


## The locker the point can use, or -1.
func locker_in_reach(point: Vector2) -> int:
	if not enabled():
		return -1
	for i in LOCKERS.size():
		if point.distance_to(LOCKERS[i]) <= LOCKER_REACH:
			return i
	return -1


## Closest dropped toolbox within reach ({} = none).
func toolbox_near(point: Vector2) -> Dictionary:
	for t: Dictionary in toolboxes:
		if point.distance_to(Vector2(t.x, t.y)) <= PICKUP_REACH:
			return t
	return {}


## Closest open breach within reach ({} = none).
func breach_near(point: Vector2) -> Dictionary:
	var best := {}
	var best_d := BREACH_REACH
	for b: Dictionary in breaches:
		var d := point.distance_to(Vector2(b.x, b.y))
		if d <= best_d:
			best = b
			best_d = d
	return best


func _local() -> CrewMember:
	if crew == null:
		return null
	for m in crew.get_children():
		if m is CrewMember and not m.remote:
			return m
	return null


func _process(delta: float) -> void:
	_t += delta
	# Air rushing out: bits spawn around each hole and spiral in.
	for b: Dictionary in breaches:
		if _rng.randf() < delta * 28.0:
			var a := _rng.randf() * TAU
			_bits.append({p = Vector2(b.x, b.y) + Vector2.from_angle(a) * _rng.randf_range(14, 30),
					target = Vector2(b.x, b.y), life = 1.2,
					col = [Color(0.85, 0.9, 1.0, 0.7), Color(0.7, 0.72, 0.8, 0.8), Color("c8b89a")][_rng.randi() % 3]})
	for i in range(_bits.size() - 1, -1, -1):
		var bit: Dictionary = _bits[i]
		var to: Vector2 = bit.target - bit.p
		bit.life -= delta
		if to.length() < 2.0 or bit.life <= 0.0:
			_bits.remove_at(i)
			continue
		bit.p += (to.normalized() * 55.0 + to.orthogonal().normalized() * 18.0) * delta
	queue_redraw()
	_floor.queue_redraw()


# --- drawing ------------------------------------------------------------------------------

func _draw_floor() -> void:
	if not enabled():
		return
	# Toolbox lockers: red wall cabinets.
	for i in LOCKERS.size():
		var p: Vector2 = LOCKERS[i] + Vector2(0, 6)
		var r := Rect2(p - Vector2(6, 4), Vector2(12, 8))
		_floor.draw_rect(r, Color("8c2a22"))
		_floor.draw_rect(r, Color("e0503a"), false, 1.0)
		_floor.draw_rect(Rect2(p - Vector2(3, 1), Vector2(6, 2)), Color("f2c14a"))
	# Dropped toolboxes lying on the floor.
	for t: Dictionary in toolboxes:
		var o := Vector2(t.x, t.y) + Vector2(-3, -3)
		_floor.draw_rect(Rect2(o + Vector2(1, 4), Vector2(6, 1)), Color(0, 0, 0, 0.35))
		_floor.draw_rect(Rect2(o + Vector2(1, -2), Vector2(4, 1)), Color("3a3a44"))
		_floor.draw_rect(Rect2(o, Vector2(6, 4)), Color("d8402e"))
		_floor.draw_rect(Rect2(o + Vector2(0, 1), Vector2(6, 1)), Color("8c2a22"))
		_floor.draw_rect(Rect2(o + Vector2(2, 2), Vector2(2, 1)), Color("f2c14a"))
	# Holes: jagged dark opening with stars inside and torn metal edges.
	for b: Dictionary in breaches:
		var c := Vector2(b.x, b.y)
		var pts := PackedVector2Array()
		var seed_v := int(b.id) * 37
		for k in 10:
			var a := TAU * k / 10.0
			var r := 5.5 + 2.0 * sin(seed_v + k * 2.3)
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.75))
		_floor.draw_colored_polygon(pts, Color("05060f"))
		_floor.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("9aa0b4"), 1.0)
		for k in 3:
			var sp := c + Vector2(sin(seed_v + k * 1.7) * 3.0, cos(seed_v + k * 2.9) * 2.0)
			_floor.draw_rect(Rect2(sp.round(), Vector2.ONE), Color(1, 1, 1, 0.5 + 0.5 * sin(_t * 3.0 + k)))


func _draw() -> void:
	for bit in _bits:
		draw_rect(Rect2((bit.p as Vector2).round(), Vector2.ONE), bit.col)
	var font := UiFont.font()
	for b: Dictionary in breaches:
		var c := Vector2(b.x, b.y)
		var blink := fmod(_t, 0.5) < 0.3
		draw_arc(c, 10.0, 0, TAU, 20, Color(1.0, 0.3, 0.2, 0.8 if blink else 0.3), 1.0)
		if int(b.id) == patch_id and patch_progress > 0.0:
			draw_arc(c, 10.0, -PI / 2, -PI / 2 + TAU * patch_progress, 24, Color("ffc640"), 2.0)
	# Prompts for the local player.
	var me := _local()
	if me == null:
		return
	var near := breach_near(me.global_position)
	var text := ""
	var at := Vector2.ZERO
	if not near.is_empty():
		at = Vector2(near.x, near.y) + Vector2(0, -14)
		text = "HOLD SPACE: PATCH" if me.has_toolbox else "NEED A TOOLBOX (CARGO / ENGINE RM)"
	elif not me.has_toolbox and not toolbox_near(me.global_position).is_empty():
		var t := toolbox_near(me.global_position)
		at = Vector2(t.x, t.y) + Vector2(0, -8)
		text = "SPACE: PICK UP TOOLBOX"
	elif locker_in_reach(me.global_position) >= 0:
		at = LOCKERS[locker_in_reach(me.global_position)] + Vector2(0, -12)
		text = "SPACE: PUT TOOLBOX BACK" if me.has_toolbox else "SPACE: TAKE TOOLBOX"
		draw_arc(LOCKERS[locker_in_reach(me.global_position)] + Vector2(0, 6), 9.0, 0, TAU, 20,
				Color(1, 0.6, 0.3, 0.6 + 0.4 * sin(_t * 6.0)), 1.0)
	if text != "":
		var w := UiFont.width(text, 8)
		var x := clampf(at.x - w / 2.0, 4.0, 476.0 - w)
		draw_rect(Rect2(x - 3, at.y - 8, w + 6, 10), Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8),
				Color("ffc640") if text.begins_with("NEED") else Color.WHITE)
