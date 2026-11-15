class_name ShipFire
extends Node2D
## Fires on the ship map + extinguisher racks (sim side: fake_mission `_start_fire` / `_tick_fire`,
## state.fires [{id, room, x, y}], state.bus_heat).
##
## SIMPLIFIED, real basis: fire is one of the most feared emergencies on a spacecraft (Mir, 1997);
## crews keep portable extinguishers at hand. Here a fire starts when the power bus overheats (loads
## drawing more than the panels make) or a hit sparks it. Each flame grows in its room, spreads through
## the doors, makes the room's station TOO HOT to use and eats cabin air. To put it out:
##   1. take an extinguisher from a rack (Mission Hub / Bridge): SPACE (SPACE again puts it back).
##      You carry ONE thing: toolbox OR extinguisher. SPACE anywhere else drops it on the floor.
##   2. walk up to a flame and HOLD SPACE until the ring fills -> {type = "douse", id}.
## CrewMember does the input (it asks `rack_in_reach` / `flame_near` / `extinguisher_near`); this node draws.

const RACKS := [Vector2(205, 150), Vector2(398, 50)]   # use points: Mission Hub, Bridge (rack on the wall above)
const RACK_REACH := 13.0
const FLAME_REACH := 16.0
const PICKUP_REACH := 10.0
const DOUSE_TIME := 1.0
const FLAME := [Color("fff3a0"), Color("ffc640"), Color("ff7a2a"), Color("d8301e")]
const EXT_RED := Color("e0402e")
const EXT_DARK := Color("8c2a22")

static var current: ShipFire

var crew: Node2D
var flames: Array = []           # state.fires
var dropped: Array = []          # extinguishers on the floor (state.toolboxes, kind "extinguisher")
var heat := 0.0                  # state.bus_heat
var douse_id := -1               # flame the local player is spraying (set by CrewMember)
var douse_progress := 0.0
var _t := 0.0
var _parts: Array[Dictionary] = []   # embers, smoke, foam
var _rng := RandomNumberGenerator.new()
var _known := {}                 # flame ids seen (pop-in + sound for new ones)


func setup(game: Node2D, crew_root: Node2D) -> void:
	crew = crew_root
	name = "ShipFire"
	z_index = 45                 # flames glow over the ship lighting, like the station panels
	game.add_child(self)


func _ready() -> void:
	current = self
	_rng.randomize()
	Events.state_changed.connect(_on_state)


func _exit_tree() -> void:
	if current == self:
		current = null
	Sfx.set_loop("fire", false)
	Sfx.set_loop("spray", false)


func _on_state(state: Dictionary) -> void:
	flames = state.get("fires", [])
	dropped = state.get("toolboxes", []).filter(
			func(t: Dictionary) -> bool: return t.get("kind", "toolbox") == "extinguisher")
	heat = float(state.get("bus_heat", 0.0))
	var now := {}
	for f: Dictionary in flames:
		now[int(f.id)] = true
		if not _known.has(int(f.id)):
			Sfx.play("ignite", _rng.randf_range(0.9, 1.1))
			for i in 10:
				_ember(Vector2(f.x, f.y), 1.5)
	for id: int in _known:
		if not now.has(id):
			Sfx.play("fizzle", 1.3)   # a flame went out
	_known = now
	Sfx.set_loop("fire", not flames.is_empty() and state.get("lost", "") == "")


## The rack the point can use, or -1.
func rack_in_reach(point: Vector2) -> int:
	for i in RACKS.size():
		if point.distance_to(RACKS[i]) <= RACK_REACH:
			return i
	return -1


## Closest flame within reach ({} = none).
func flame_near(point: Vector2, reach := FLAME_REACH) -> Dictionary:
	var best := {}
	var best_d := reach
	for f: Dictionary in flames:
		var d := point.distance_to(Vector2(f.x, f.y))
		if d <= best_d:
			best = f
			best_d = d
	return best


## Closest extinguisher lying on the floor within reach ({} = none).
func extinguisher_near(point: Vector2) -> Dictionary:
	for t: Dictionary in dropped:
		if point.distance_to(Vector2(t.x, t.y)) <= PICKUP_REACH:
			return t
	return {}


func _local() -> CrewMember:
	if crew == null:
		return null
	for m in crew.get_children():
		if m is CrewMember and not m.remote:
			return m
	return null


func _process(delta: float) -> void:
	_t += delta
	for f: Dictionary in flames:
		var at := Vector2(f.x, f.y)
		if _rng.randf() < delta * 14.0:
			_ember(at, 1.0)
		if _rng.randf() < delta * 5.0:
			_parts.append({p = at + Vector2(_rng.randf_range(-3, 3), -9), v = Vector2(_rng.randf_range(-4, 4), -12),
					life = 1.4, max = 1.4, col = Color("4a4e5c"), size = 2})
	# Foam from everyone spraying (remote crew too: CrewMember.spraying is synced).
	var any_spray := false
	if crew:
		for m in crew.get_children():
			if m is CrewMember and m.spraying:
				any_spray = true
				var dir: Vector2 = m.facing_dir()
				var from: Vector2 = m.position + Vector2(dir.x * 5.0, -6.0)
				for i in 2:
					_parts.append({p = from, v = dir.rotated(_rng.randf_range(-0.35, 0.35)) * _rng.randf_range(50, 80),
							life = 0.35, max = 0.35, col = [Color.WHITE, Color("d8f0ff")][i], size = 1, drag = 3.0})
	Sfx.set_loop("spray", any_spray)
	for i in range(_parts.size() - 1, -1, -1):
		var p: Dictionary = _parts[i]
		p.life -= delta
		if p.life <= 0.0:
			_parts.remove_at(i)
			continue
		p.v *= maxf(1.0 - float(p.get("drag", 0.8)) * delta, 0.0)
		p.p += p.v * delta
	queue_redraw()


func _ember(at: Vector2, speed: float) -> void:
	_parts.append({p = at + Vector2(_rng.randf_range(-3, 3), -4),
			v = Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-30, -14)) * speed,
			life = _rng.randf_range(0.4, 0.8), max = 0.8, col = FLAME[_rng.randi() % 3], size = 1})


# --- drawing ------------------------------------------------------------------------------

func _draw() -> void:
	for i in RACKS.size():
		_draw_extinguisher(RACKS[i] + Vector2(0, -9), true)
	for t: Dictionary in dropped:
		_draw_extinguisher(Vector2(t.x, t.y), false)
	for f: Dictionary in flames:
		_draw_flame(Vector2(f.x, f.y), int(f.id))
		if int(f.id) == douse_id and douse_progress > 0.0:
			draw_arc(Vector2(f.x, f.y) + Vector2(0, -4), 10.0, -PI / 2, -PI / 2 + TAU * douse_progress, 24, Color("d8f0ff"), 2.0)
	for p in _parts:
		var col: Color = p.col
		col.a *= clampf(p.life / p.max * 1.5, 0.0, 1.0)
		var s := int(p.get("size", 1))
		draw_rect(Rect2((p.p as Vector2).round(), Vector2(s, s)), col)
	_draw_prompt()


## A pixel flame: a hot core and tongues that flicker (whole pixels, no smoothing).
func _draw_flame(at: Vector2, id: int) -> void:
	var base := at.round()
	draw_rect(Rect2(base + Vector2(-5, 0), Vector2(10, 2)), Color(0.1, 0.05, 0.02, 0.5))   # scorch
	for k in 5:
		var x := -4 + k * 2
		var h := 4.0 + 4.0 * absf(sin(_t * (9.0 + k) + id * 1.7 + k * 1.3)) + (3.0 if k == 2 else 0.0)
		var hh := int(h)
		draw_rect(Rect2(base + Vector2(x, -hh), Vector2(2, hh)), FLAME[3])
		draw_rect(Rect2(base + Vector2(x, -hh + 2), Vector2(2, maxi(hh - 2, 0))), FLAME[2])
		if k in [1, 2, 3]:
			draw_rect(Rect2(base + Vector2(x, -hh + 4), Vector2(2, maxi(hh - 4, 0))), FLAME[1])
	draw_rect(Rect2(base + Vector2(-1, -3), Vector2(2, 3)), FLAME[0])


func _draw_extinguisher(at: Vector2, on_wall: bool) -> void:
	var o := at.round() + Vector2(-2, -6)
	if on_wall:
		draw_rect(Rect2(o + Vector2(-2, 2), Vector2(8, 6)), Color("3a3f52"))   # bracket
	else:
		draw_rect(Rect2(o + Vector2(0, 7), Vector2(5, 1)), Color(0, 0, 0, 0.35))   # floor shadow
	draw_rect(Rect2(o + Vector2(1, -2), Vector2(2, 2)), Color("2a2a30"))      # valve
	draw_rect(Rect2(o + Vector2(3, -2), Vector2(2, 1)), Color("2a2a30"))      # nozzle
	draw_rect(Rect2(o, Vector2(4, 7)), EXT_RED)
	draw_rect(Rect2(o + Vector2(3, 0), Vector2(1, 7)), EXT_DARK)
	draw_rect(Rect2(o + Vector2(1, 2), Vector2(2, 2)), Color("f2f2f2"))       # label


## One line for the local player: what SPACE does about fire right here.
func _draw_prompt() -> void:
	var me := _local()
	if me == null or me.docked_station() != null:
		return
	var near := flame_near(me.global_position)
	var text := ""
	var at := Vector2.ZERO
	var warn := false
	if not near.is_empty():
		at = Vector2(near.x, near.y) + Vector2(0, -16)
		if me.has_extinguisher:
			text = "HOLD SPACE: PUT IT OUT"
		else:
			text = "NEED AN EXTINGUISHER (HUB / BRIDGE)"
			warn = true
	elif not me.has_extinguisher and not me.has_toolbox and not extinguisher_near(me.global_position).is_empty():
		var t := extinguisher_near(me.global_position)
		at = Vector2(t.x, t.y) + Vector2(0, -10)
		text = "SPACE: PICK UP EXTINGUISHER"
	elif rack_in_reach(me.global_position) >= 0:
		var rack: Vector2 = RACKS[rack_in_reach(me.global_position)]
		at = rack + Vector2(0, -20)
		if me.has_toolbox:
			text = "HANDS FULL - DROP THE TOOLBOX"
			warn = true
		else:
			text = "SPACE: PUT IT BACK" if me.has_extinguisher else "SPACE: TAKE EXTINGUISHER"
		draw_arc(rack + Vector2(0, -9), 8.0, 0, TAU, 20, Color(1, 0.5, 0.3, 0.6 + 0.4 * sin(_t * 6.0)), 1.0)
	if text == "":
		return
	var w := UiFont.width(text, 8)
	var x := clampf(at.x - w / 2.0, 4.0, 476.0 - w)
	UiKit.panel(self, Rect2(roundf(x - 3), roundf(at.y - 9), roundf(w + 6), 12), UiKit.PANEL_DARK,
			UiKit.WARN if warn else Color("ff7a2a"))
	UiKit.text(self, Vector2(roundf(x), roundf(at.y)), text, 8, UiKit.WARN if warn else UiKit.TEXT, 0)
