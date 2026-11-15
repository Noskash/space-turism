class_name ShipEva
extends Node2D
## Spacewalks (EVA), the inside half: the airlock hatch in the Bridge floor, plus everyone who is
## outside, drawn as a small suited figure "on the roof" with a tether back to the hatch.
## SPACE on the hatch with empty hands (CrewMember) -> start_eva() -> EvaView, full screen, local player only.
##
## Sim side (fake_mission "Spacewalks"): outside faults (solar wing jammed / dish jammed / radiator
## leaking) are tickets kind "eva", role "team", no timer; they hurt until fixed: {type = "eva_fix", id}.
## A crew member outside has `eva = true` (CrewMember, synced) and the host reports their room as "eva"
## (radiation storm dose x1.5, no shelter). SIMPLIFIED, real basis in fake_mission EVA_FAULTS.

const HATCH := Vector2(424, 190)     # Bridge floor, by the nose (free floor in ship_layout.json)
const REACH := 11.0
const OUT := Vector2(412, 196)       # where a spacewalker reappears inside

static var current: ShipEva

var crew: Node2D
var faults: Array = []               # open "eva" tickets
var state := {}
var _t := 0.0
var _view: EvaView


func setup(game: Node2D, crew_root: Node2D) -> ShipEva:
	crew = crew_root
	name = "ShipEva"
	z_index = 45                     # over the ship lighting, like the stations and the radio
	game.add_child(self)
	return self


func _ready() -> void:
	current = self
	Events.state_changed.connect(_on_state)


func _exit_tree() -> void:
	if current == self:
		current = null


func _on_state(s: Dictionary) -> void:
	state = s
	faults = s.get("events", []).filter(func(e: Dictionary) -> bool: return e.get("kind", "") == "eva")


func airlock_in_reach(point: Vector2) -> bool:
	return point.distance_to(HATCH) <= REACH


func is_outside() -> bool:
	return _view != null and is_instance_valid(_view)


## Suit up and go out (local player). EvaView hides the crew member and moves it around on the hull.
func start_eva(member: CrewMember) -> void:
	if is_outside() or not state.get("finished", {}).is_empty() or state.get("lost", "") != "":
		return
	_view = EvaView.new()
	_view.member = member
	_view.ship = self
	get_parent().add_child(_view)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _outside_crew() -> Array:
	var out := []
	if crew:
		for m in crew.get_children():
			if m is CrewMember and m.eva:
				out.append(m)
	return out


func _draw() -> void:
	var outside := _outside_crew()
	_draw_hatch(not outside.is_empty())
	for m: CrewMember in outside:
		_draw_walker(m)


## Round floor hatch: hazard-striped ring, dark lid with a wheel, a lamp (amber blinking = a job is
## waiting outside, green = someone is out).
func _draw_hatch(someone_out: bool) -> void:
	var c := HATCH
	for i in 16:   # hazard ring, 16 chunky segments
		var a := TAU * i / 16.0
		var p := (c + Vector2(cos(a), sin(a) * 0.75) * 7.0).round()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("ffd84a") if i % 2 == 0 else Color("1a1c26"))
	draw_rect(Rect2(c - Vector2(5, 3), Vector2(10, 6)), Color("3a4258"))
	draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)).grow_individual(0, -1, 0, -1), Color("4d5573"))
	draw_rect(Rect2(c - Vector2(3, 0), Vector2(6, 1)), Color("8d96ad"))   # wheel
	draw_rect(Rect2(c - Vector2(0, 2), Vector2(1, 4)), Color("8d96ad"))
	var lamp := Color("2a2f3e")
	if someone_out:
		lamp = UiKit.GOOD
	elif not faults.is_empty() and fmod(_t, 0.8) < 0.45:
		lamp = UiKit.WARN
	draw_rect(Rect2(c + Vector2(7, -7), Vector2(2, 2)), lamp)
	if not faults.is_empty() and not someone_out and fmod(_t, 1.6) < 1.0:   # helmet sign: a job outside
		UiKit.icon(self, "eva", c + Vector2(-4, -17), 1, Color.WHITE)


## A crew member on the hull, drawn over the map (they are above the ceiling): dithered shadow,
## tiny white suit with a gold visor and the role colour on the arm, dotted tether to the hatch.
func _draw_walker(m: CrewMember) -> void:
	var p := m.position.round()
	var dist := p.distance_to(HATCH)
	var steps := maxi(int(dist / 3.0), 1)
	var mid := (p + HATCH) / 2.0 + Vector2(0, minf(dist * 0.12, 10.0) + sin(_t * 2.0) * 1.5)
	for i in steps + 1:   # tether: dotted quadratic curve
		if i % 2 == 1:
			continue
		var k := float(i) / steps
		var q := HATCH.lerp(mid, k).lerp(mid.lerp(p, k), k)
		draw_rect(Rect2(q.round(), Vector2.ONE), Color(0.92, 0.89, 0.78, 0.8))
	var bob := -1.0 if fmod(_t * 2.0 + m.get_instance_id() % 7, 2.0) < 1.0 else 0.0
	for x in 6:   # shadow under them
		if x % 2 == 0:
			draw_rect(Rect2(p + Vector2(x - 3, 3), Vector2(1, 1)), Color(0, 0, 0, 0.6))
	var o := p + Vector2(-3, -9 + bob)
	draw_rect(Rect2(o + Vector2(-1, -1), Vector2(8, 11)), UiKit.INK)
	draw_rect(Rect2(o + Vector2(0, 3), Vector2(6, 6)), Color("e8ecf4"))          # body
	draw_rect(Rect2(o, Vector2(6, 4)), Color("f4f6fb"))                          # helmet
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(4, 2)), Color("ffc640"))          # visor
	draw_rect(Rect2(o + Vector2(0, 5), Vector2(1, 2)), m.role_color())           # arm stripes
	draw_rect(Rect2(o + Vector2(5, 5), Vector2(1, 2)), m.role_color())
	UiKit.text_c(self, p.x, p.y - 12 + bob, "EVA", 5, UiKit.TEXT, 1)
