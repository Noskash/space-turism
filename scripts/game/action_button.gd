class_name ActionButton
extends RefCounted
## Big contextual action button (bottom-right block of the cruise HUD).
## Shows what the USE key does for the local crew member right now: DOCK at a station in reach,
## the docked station's verb (Station.action_info: REPAIR / FIX / SHIELDS / BURN / DOWNLINK...),
## RADIO next to the boombox, or a greyed USE when nothing is in reach. The key cap comes from
## the input map (Controls.key_name), so another key scheme shows its own key.
## While a hold-to-work task fills, the button's rim fills with it.

const SIZE := 38.0

var local: CrewMember
var scheme := "p1"

var _juice := UiJuice.new()
var _last := ""


func step(delta: float) -> void:
	_juice.step(delta)


func info() -> Dictionary:
	var inf := {icon = "use", verb = "USE", enabled = false, hold = false, sides = false, progress = 0.0}
	if local == null or not is_instance_valid(local):
		return inf
	var docked := local.docked_station()
	if docked:
		return docked.action_info()
	var near := local.near_station()
	if near:
		inf.merge({icon = "dock", verb = "DOCK" if near.is_free() else "IN USE", enabled = near.is_free()}, true)
		return inf
	var other: Station = local.ship_map.station_at(local.global_position) if local.ship_map else null
	if other:
		inf.merge({icon = "dock", verb = CrewRoles.tag(other.role) + " ONLY"}, true)  # another role's station
		return inf
	if ShipEva.current and ShipEva.current.airlock_in_reach(local.global_position):
		var hands_full: bool = local.has_toolbox or local.has_extinguisher
		inf.merge({icon = "spacewalk", verb = "HANDS FULL" if hands_full else "SPACEWALK", enabled = not hands_full}, true)
		return inf
	if RadioSet.in_reach(local.global_position):
		inf.merge({icon = "radio", verb = "RADIO", enabled = true}, true)
	return inf


## Draws the button with its bottom-right corner at `bottom_right`; returns the block's rect
## (button + verb label + key cap).
func draw(ci: CanvasItem, bottom_right: Vector2) -> Rect2:
	var inf := info()
	var sig := "%s|%s" % [inf.verb, inf.enabled]
	if sig != _last:
		if inf.enabled:
			_juice.kick("pop", 0.25)
		_last = sig
	var enabled: bool = inf.enabled
	var r := Rect2(bottom_right - Vector2(SIZE, SIZE + 4), Vector2(SIZE, SIZE))
	var center := r.get_center().round()
	var s := _juice.pop("pop", 0.25)
	ci.draw_set_transform(center, 0.0, Vector2(s, s))
	var local_r := Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE, SIZE)
	UiKit.panel(ci, local_r, UiKit.PANEL if enabled else UiKit.PANEL_DARK, UiKit.WARN if enabled else UiKit.FAINT)
	var tint := Color.WHITE if enabled else UiKit.FAINT
	UiKit.icon(ci, inf.icon, Vector2(-16, -17), 2, tint)
	# Hold progress: the rim lights up clockwise in chunky 3 px blocks.
	var progress: float = inf.get("progress", 0.0)
	if progress > 0.0:
		var blocks := _rim_blocks(local_r.grow(-1))
		var lit := roundi(progress * blocks.size())
		for i in lit:
			ci.draw_rect(blocks[i], UiKit.GOOD)
	ci.draw_set_transform(Vector2.ZERO)
	# Key cap(s) on the bottom edge.
	var keys: Array[String] = []
	if inf.get("sides", false):
		keys = [Controls.key_name(scheme, "left"), Controls.key_name(scheme, "right")]
	else:
		keys = [Controls.key_name(scheme, "interact")]
	var total := 0.0
	for k in keys:
		total += UiKit.keycap_size(k, 7).x + 2
	var kx := roundf(center.x - (total - 2) / 2.0)
	var cap_h := UiKit.keycap_size("A", 7).y
	for k in keys:
		var cap := UiKit.keycap(ci, Vector2(kx, r.end.y - roundf(cap_h / 2.0)), k, 7, enabled)
		kx = cap.end.x + 2
	# Verb above the button, right-aligned: "HOLD" in grey, the verb in yellow.
	var verb: String = inf.verb
	var base := r.position.y - 3
	var col := UiKit.WARN if enabled else UiKit.DIM
	UiKit.text_r(ci, r.end.x, base, verb, 8, col)
	var label_w := UiKit.text_w(verb, 8)
	if inf.get("hold", false) and enabled:
		UiKit.text_r(ci, r.end.x - label_w - 3, base, "HOLD", 7, UiKit.DIM)
		label_w += UiKit.text_w("HOLD ", 7)
	var top := base - UiKit.ascent(8) - 1
	var left := minf(r.position.x, r.end.x - label_w)
	return Rect2(left, top, r.end.x - left, r.end.y + cap_h / 2.0 - top)


## Rim blocks clockwise from the top-left corner.
static func _rim_blocks(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var step := 4.0
	var x := r.position.x
	while x < r.end.x - 3:
		out.append(Rect2(x, r.position.y, 3, 2))
		x += step
	var y := r.position.y
	while y < r.end.y - 3:
		out.append(Rect2(r.end.x - 2, y, 2, 3))
		y += step
	x = r.end.x - 3
	while x > r.position.x:
		out.append(Rect2(x, r.end.y - 2, 3, 2))
		x -= step
	y = r.end.y - 3
	while y > r.position.y:
		out.append(Rect2(r.position.x, y, 2, 3))
		y -= step
	return out
