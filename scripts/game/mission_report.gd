class_name MissionReport
extends CanvasLayer
## End of a campaign mission (state.finished from the sim: orbit / flyby / miss).
## Page 1 RESULT: outcome, stars, goal checklist and WHY it went that way (from state.stats).
## Page 2 WHAT NASA ACTUALLY DID (+ the Mars Climate Orbiter card after a miss or flyby).
## Keys: SPACE next page. Last page: SPACE = fly this mission again (redesign), M = pick another
## mission, ESC = main menu. In co-op the host decides for everyone (RPC), others can only leave.
## Every peer builds it from the synced state, saves best stars and unlocks Codex terms.

const DESIGNER_SCENE := "res://scenes/design/hangar.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const DELAY := 2.2            # let the arrival message / brake burn play first

var _state := {}
var _shown := false
var _t := 0.0
var _page := 0
var _canvas: Node2D
var _why: Array[String] = []
var _new_best := false
var _best := 0


func _ready() -> void:
	name = "MissionReport"
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_report)
	add_child(_canvas)
	visible = false
	Events.state_changed.connect(func(s: Dictionary) -> void:
		if not _shown and not s.get("finished", {}).is_empty():
			_show(s))


func _show(state: Dictionary) -> void:
	_state = state.duplicate(true)
	_shown = true
	_why = _reasons()
	Missions.save_stars(Missions.current_id(), int(_state.finished.get("stars", 0)))
	var points := int(_state.finished.get("score", 0))
	_new_best = Missions.save_score(Missions.current_id(), points)
	_best = Missions.best_score(Missions.current_id())
	Sfx.play("fixed" if _state.finished.outcome == "orbit" else "denied")


func _exit_tree() -> void:
	if visible:
		Tutorial.hold(false)


func _process(delta: float) -> void:
	if not _shown:
		return
	var before := _t
	_t += delta
	if before < DELAY and _t >= DELAY:
		visible = true
		Tutorial.hold(true)
		Sfx.set_loop("engine", false)
		Sfx.play("page")
		var terms := ["mars_orbit_insertion", "polar_orbit", "elliptical_orbit"]
		if Missions.current_id() == "mro" or Orbits.id_of(_state.get("design", {})) == "aerobrake":
			terms.append("aerobraking")
		Codex.unlock(terms)
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or _t < DELAY + 0.6 or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var last := _page >= _pages() - 1
	match event.physical_keycode:
		KEY_SPACE, KEY_ENTER:
			if not last:
				_page += 1
				Sfx.play("page")
			elif _decides():
				if Network.is_in_room():
					_go.rpc("again")
				else:
					_go("again")
		KEY_M:
			if last and _decides():
				_go("other")   # leaves the room (co-op: the host closes it for everyone)
		KEY_ESCAPE:
			_go("menu")
	get_viewport().set_input_as_handled()


func _decides() -> bool:
	return not Network.is_in_room() or Network.is_host()


@rpc("authority", "call_local", "reliable")
func _go(where: String) -> void:
	match where:
		"again":
			get_tree().change_scene_to_file(DESIGNER_SCENE)
		"other":
			if Network.is_in_room():
				Network.leave_room()
			get_tree().change_scene_to_file(MissionSelect.SCENE)
		_:
			if Network.is_in_room():
				Network.leave_room()
			get_tree().change_scene_to_file(MENU_SCENE)


## RESULT · ORBIT (science from Mars orbit; only after a brake burn into orbit) · CREW (radiation dose
## per astronaut; only when the sim had a crew) · NASA (always last).
func _page_list() -> Array[String]:
	var out: Array[String] = ["result"]
	if str(_state.get("finished", {}).get("outcome", "")) == "orbit":
		out.append("orbit")
	if _has_crew():
		out.append("crew")
	out.append("nasa")
	return out


func _pages() -> int:
	return _page_list().size()


func _has_crew() -> bool:
	return not _state.get("crew", {}).is_empty()


# --- why it went that way ------------------------------------------------------------------

func _reasons() -> Array[String]:
	var out: Array[String] = []
	var f: Dictionary = _state.finished
	var st: Dictionary = _state.get("stats", {})
	var design: Dictionary = _state.get("design", {})
	var need := ceili(Orbits.moi_fuel(design))
	var orbit_name := str(Orbits.info(Orbits.id_of(design)).get("short", "")).to_lower()
	match str(f.outcome):
		"orbit":
			out.append("Brake burn done (%s orbit) - %d%% fuel was left to keep it." % [orbit_name, int(f.get("fuel", 0))])
		"flyby":
			var cheap := ceili(Orbits.moi_fuel(DesignRules.set_orbit(design, "elliptical")))
			var hint := "" if Orbits.id_of(design) == "elliptical" else " A high elliptical orbit needs only %d%%." % cheap
			out.append("Only %d%% fuel at Mars, the %s orbit needed %d%%: a FLYBY.%s Fuel is mass - a bigger tank costs mass too." % [
					int(st.get("fuel_at_moi", 0)), orbit_name, need, hint])
		_:
			out.append("Nobody held the brake in time - the ship flew past Mars.")
	var plan: Dictionary = design.get("plan", {})   # launch window planner
	if float(plan.get("fuel_cost", 0.0)) > 0.5:
		out.append("Launching on %s, off the best window, burned %d%% of the ship's own fuel to catch Mars." % [
				str(plan.get("date", "")), ceili(float(plan.fuel_cost))])
	if str(plan.get("speed", "")) == "fast":
		out.append("FAST path: Mars in %d days instead of 259, but the brake burn needed x%.1f fuel." % [
				int(plan.get("trip_days", 180)), float(plan.get("moi_mult", 1.4))])
	if int(st.get("leaks", 0)) > 0:
		out.append("Debris punctured a fuel line on day %d - the leak cost %d%% fuel before it was sealed." % [
				int(st.get("leak_day", 0)), int(st.get("leak_fuel", 0))])
	if int(st.get("caught_outside", 0)) > 0:
		out.append("Astronauts were caught outside the shelter %d time(s) as a storm hit - big radiation doses." % int(st.caught_outside))
	match str(st.get("big_storm", "")):
		"hit":
			out.append("The Halloween storm hit an unprotected ship - just like MARIE in 2003.")
		"shields":
			out.append("Shields held through the Halloween storm - MARIE had no such luck.")
	for g: Dictionary in Missions.current().get("goals", []):
		if g.kind == "storms_recorded" and int(_state.get("storms_recorded", 0)) < int(g.target):
			if int(st.get("safe_modes", 0)) > 0:
				out.append("Safe mode kept you safe %d time(s), but it switches the instruments off: no reading." % int(st.safe_modes))
			else:
				out.append("Storm readings need the instruments ON as the wave hits.")
	var lost := int(_state.get("science_lost", 0))
	if lost >= 10:
		out.append("%d science was lost to a full recorder - downlink more often, or a bigger recorder / dish." % lost)
	if int(st.get("disabled", 0)) > 0:
		out.append("The ship was disabled by radiation %d time(s)." % int(st.disabled))
	if int(st.get("breaches", 0)) > 0:
		out.append("%d hull breach(es) opened by debris." % int(st.breaches))
	if int(st.get("knockouts", 0)) >= 3:
		out.append("Stations went OFFLINE %d times - missed tickets cost repair time." % int(st.knockouts))
	if out.size() < 3:
		out.append("Every part costs mass, power and budget - there is no single best design.")
	return out.slice(0, 5)


# --- drawing --------------------------------------------------------------------------------

func _draw_report() -> void:
	if not visible:
		return
	var c := _canvas
	var m := Missions.current()
	var accent := Color(str(m.get("accent", "4fd8ff")))
	var k := clampf((_t - DELAY) / 0.5, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.02, 0.05, 0.85 * k))
	var box := Rect2(36, 16, 408, 238)
	c.draw_rect(box.grow(2), Color(0, 0, 0, 0.6 * k))
	c.draw_rect(box, Color(0.055, 0.07, 0.14, k))
	c.draw_rect(box, Color(accent, k), false, 1.0)
	match _page_list()[clampi(_page, 0, _pages() - 1)]:
		"result": _draw_result(box, accent, k)
		"orbit": _draw_orbit(box, accent, k)
		"crew": _draw_crew(box, accent, k)
		_: _draw_nasa(box, accent, k)
	var last := _page >= _pages() - 1
	var keys := "SPACE: NEXT"
	if last:
		keys = "SPACE: FLY AGAIN   M: OTHER MISSION   ESC: MAIN MENU" if _decides() else "WAITING FOR THE HOST...   ESC: LEAVE"
	var col := Color("ffc640") if fmod(_t, 1.2) < 0.85 else Color("9a8040")
	_text(keys, Vector2(240 - UiFont.width(keys, 8) / 2.0, box.end.y - 8), 8, Color(col, k))


func _draw_result(box: Rect2, accent: Color, k: float) -> void:
	var m := Missions.current()
	var f: Dictionary = _state.finished
	var x := box.position.x + 12
	var header := "MISSION %d REPORT  ·  %s" % [int(m.get("number", 0)), str(m.get("title", ""))]
	if Missions.current_id() == Missions.SANDBOX:
		header = "SANDBOX REPORT  ·  FREE PLAY"
	_text(header, Vector2(x, box.position.y + 13), 8, Color(accent, k))
	var head: String = {orbit = "ORBIT ACHIEVED", flyby = "FLYBY - NO ORBIT", miss = "MISSED MARS"}.get(str(f.outcome), "")
	var head_col := Color("8cffb0") if f.outcome == "orbit" else (Color("ffc640") if f.outcome == "flyby" else Color("ff5050"))
	_text(head, Vector2(240 - UiFont.width(head, 18) / 2.0, box.position.y + 36), 18, Color(head_col, k))
	var stars := int(f.get("stars", 0))
	var sandbox: bool = Missions.current().get("goals", []).is_empty()
	if sandbox:
		var tag := "SANDBOX - NO STARS"
		_text(tag, Vector2(240 - UiFont.width(tag, 7) / 2.0, box.position.y + 55), 7, Color(0.6, 0.65, 0.8, k))
	else:
		for i in 3:
			var reveal := clampf((_t - DELAY - 0.4 - i * 0.35) / 0.2, 0.0, 1.0)
			_star(Vector2(240 - 26 + i * 26, box.position.y + 52), i < stars and reveal > 0.0, 8.0 * (0.6 + 0.4 * reveal), k)
	# Score: stars + BONUS DATA (science sent beyond the SENT goal), right of the stars.
	if _t > DELAY + 1.4:
		var points := "SCORE %d" % int(f.get("score", 0))
		var right := box.end.x - 12
		_text(points, Vector2(right - UiFont.width(points, 11), box.position.y + 52), 11, Color("ffd34a") * Color(1, 1, 1, k))
		var parts := ("STARS %d + DATA SENT %d + HEALTHY CREW %d + ORBIT %d" if sandbox else "STARS %d + BONUS DATA %d + HEALTHY CREW %d + ORBIT %d") % [stars * Missions.STAR_POINTS,
				int(f.get("bonus", 0)) * Missions.BONUS_POINTS, int(f.get("healthy", 0)) * Missions.HEALTHY_POINTS,
				int(f.get("orbit_science", 0)) * Orbits.ORBIT_POINTS]
		_text(parts, Vector2(right - UiFont.width(parts, 6), box.position.y + 61), 6, Color(0.6, 0.65, 0.8, k))
		var best := "NEW BEST!" if _new_best else "BEST %d" % _best
		var best_col := Color("8cffb0") if _new_best and fmod(_t, 0.6) < 0.4 else Color(0.6, 0.65, 0.8)
		_text(best, Vector2(x, box.position.y + 52), 9, Color(best_col, k))
	var y := box.position.y + 74
	if sandbox:   # which hazards were on: the thing to compare between sandbox flights
		_text("HAZARDS FLOWN", Vector2(x, y), 7, Color(0.55, 0.6, 0.75, k))
		y += 11
		var o := Missions.sandbox_options()
		var parts_on := PackedStringArray()
		for key: String in ["storms", "debris", "hull", "conjunction"]:
			var on := bool(o.get(key, key != "hull"))
			parts_on.append("%s %s" % [MissionSelect.SANDBOX_NAMES[key], "ON" if on else "OFF"])
		_text("  ·  ".join(parts_on), Vector2(x, y), 8, Color(1, 1, 1, k))
		y += 11
	else:
		_text("GOALS", Vector2(x, y), 7, Color(0.55, 0.6, 0.75, k))
		y += 11
	for g: Dictionary in Missions.goals(_state):
		_text("[x]" if g.done else "[ ]", Vector2(x, y), 8, Color(Color("8cffb0") if g.done else Color("ff6a5a"), k))
		_text("%s  -  %s" % [g.text, g.short], Vector2(x + 20, y), 8, Color(1, 1, 1, k))
		y += 11
	y += 6
	_text("WHY IT WENT THIS WAY", Vector2(x, y), 7, Color(0.55, 0.6, 0.75, k))
	y += 11
	for reason in _why:
		for line in MissionSelect._wrap("- " + reason, box.size.x - 24, 8):
			_text(line, Vector2(x, y), 8, Color(0.85, 0.88, 0.95, k))
			y += 10
	var tally := "SENT %d · LOST %d · STORMS RECORDED %d · DAY %d" % [int(_state.get("science_sent", 0)),
			int(_state.get("science_lost", 0)), int(_state.get("storms_recorded", 0)), int(f.get("day", 0))]
	_text(tally, Vector2(x, box.end.y - 22), 7, Color(0.5, 0.56, 0.7, k))


func _draw_nasa(box: Rect2, accent: Color, k: float) -> void:
	var m := Missions.current()
	var x := box.position.x + 12
	var w := box.size.x - 24
	var y := box.position.y + 16
	var cards: Array = [m.get("nasa_card", {})]
	if str(_state.finished.outcome) != "orbit":
		cards.append(Missions.failure_card())
	for card: Dictionary in cards:
		_text(str(card.get("title", "")), Vector2(x, y), 10, Color(accent, k))
		y += 14
		for line in MissionSelect._wrap(str(card.get("body", "")), w, 8):
			_text(line, Vector2(x, y), 8, Color(0.9, 0.92, 0.98, k))
			y += 10
		y += 10
	_text("LESSON: " + str(m.get("lesson", "")), Vector2(x, minf(y, box.end.y - 30)), 8, Color(Color("8cffb0"), k))


## After the brake burn: what the chosen orbit achieved over the ship's lifetime (Orbits.result).
## Lifetime bar (aerobraking wait + science years out of MAX_YEARS), the two rates per Mars year
## (observed vs what the radio can send - the smaller one is the bottleneck), total, why.
func _draw_orbit(box: Rect2, accent: Color, k: float) -> void:
	var r := Orbits.result(_state)
	var o := Orbits.info(str(r.orbit))
	var x := box.position.x + 12
	var w := box.size.x - 24
	var y := box.position.y + 18
	_text("IN MARS ORBIT  ·  %s" % str(o.get("name", "")), Vector2(x, y), 10, Color(accent, k))
	_text("SIMPLIFIED", Vector2(box.end.x - 12 - UiFont.width("SIMPLIFIED", 6), y), 6, Color(0.5, 0.56, 0.7, k))
	y += 10
	_text(str(o.get("shape", "")), Vector2(x, y), 7, Color(0.6, 0.65, 0.8, k))
	y += 16
	# Lifetime bar: grey = aerobraking wait, gold = science, dark = fuel ran out before MAX_YEARS.
	var bar := Rect2(x + 70, y - 7, w - 150, 8)
	var per_year := bar.size.x / Orbits.MAX_YEARS
	_text("LIFETIME", Vector2(x, y), 8, Color(1, 1, 1, k))
	_canvas.draw_rect(bar, Color(1, 1, 1, 0.1 * k))
	var wait := minf(float(r.delay), float(r.fuel_years))
	_canvas.draw_rect(Rect2(bar.position, Vector2(per_year * wait, bar.size.y)), Color(0.55, 0.6, 0.75, 0.8 * k))
	_canvas.draw_rect(Rect2(bar.position + Vector2(per_year * wait, 0), Vector2(per_year * float(r.years), bar.size.y)),
			Color(Color("ffd34a"), k))
	for i in range(1, int(Orbits.MAX_YEARS)):
		_canvas.draw_rect(Rect2(bar.position.x + per_year * i, bar.position.y - 1, 1, bar.size.y + 2), Color(0, 0, 0, 0.6 * k))
	_text("%.1f YRS SCIENCE" % float(r.years), Vector2(bar.end.x + 6, y), 8, Color(Color("ffd34a"), k))
	y += 16
	# Observed vs sent per Mars year: the smaller bar is the bottleneck.
	var top := maxf(maxf(float(r.observed_year), float(r.cap_year)), 1.0)
	for row: Array in [["OBSERVED / YR", float(r.observed_year), r.bottleneck == "instruments"],
			["RADIO CAN SEND / YR", float(r.cap_year), r.bottleneck == "downlink"]]:
		var rb := Rect2(x + 110, y - 7, w - 190, 8)
		_text(str(row[0]), Vector2(x, y), 8, Color(1, 1, 1, k))
		_canvas.draw_rect(rb, Color(1, 1, 1, 0.1 * k))
		var col := Color("ff6a5a") if row[2] else Color("4fd8ff")
		_canvas.draw_rect(Rect2(rb.position, Vector2(rb.size.x * float(row[1]) / top, rb.size.y)), Color(col, k))
		_text("%d%s" % [int(row[1]), "  BOTTLENECK" if row[2] else ""], Vector2(rb.end.x + 6, y), 7, Color(col, k))
		y += 13
	y += 4
	var total := "+%d SCIENCE SENT HOME FROM ORBIT  (+%d POINTS)" % [int(r.sent), int(r.sent) * Orbits.ORBIT_POINTS]
	_text(total, Vector2(240 - UiFont.width(total, 10) / 2.0, y + 2), 10, Color(Color("8cffb0"), k))
	y += 18
	for reason: String in r.lines:
		for line in MissionSelect._wrap("- " + reason, w, 8):
			if y > box.end.y - 30:
				break
			_text(line, Vector2(x, y), 8, Color(0.85, 0.88, 0.95, k))
			y += 10
	_text(str(o.get("real", "")), Vector2(x, box.end.y - 22), 7, Color(0.5, 0.56, 0.7, k))


## Each astronaut's dose against NASA's 600 mSv career limit, with the real numbers behind it.
func _draw_crew(box: Rect2, accent: Color, k: float) -> void:
	var x := box.position.x + 12
	var w := box.size.x - 24
	var y := box.position.y + 18
	_text("CREW RADIATION DOSE", Vector2(x, y), 10, Color(accent, k))
	y += 16
	var crew: Dictionary = _state.crew
	var keys := crew.keys()
	keys.sort()
	var limit := Astronauts.dose("nasa_limit")
	var bar_w := 110.0
	for key: String in keys:
		var a: Dictionary = crew[key]
		var info := Astronauts.info(a.astronaut)
		var sick := bool(a.get("sick", false))
		_text("%s  (%s)" % [info.name, info.role], Vector2(x, y), 8, Color(Color(str(info.color)), k))
		var bar := Rect2(x + 190, y - 6, bar_w, 6)
		_canvas.draw_rect(bar, Color(1, 1, 1, 0.12 * k))
		_canvas.draw_rect(Rect2(bar.position, Vector2(bar_w * clampf(float(a.dose) / limit, 0.0, 1.0), 6)),
				Color(Color("ff5050") if sick else Color("ffd34a"), k))
		_canvas.draw_rect(Rect2(bar.position.x + bar_w * Astronauts.dose("sick_at") / limit, bar.position.y - 1, 1, 8), Color(1, 1, 1, 0.6 * k))
		var tag := "%d mSv%s" % [int(a.dose), "  SICK" if sick else ""]
		_text(tag, Vector2(bar.end.x + 6, y), 7, Color(Color("ff6a5a") if sick else Color(0.85, 0.88, 0.95), k))
		y += 14
	y += 4
	var healthy := Missions.healthy_crew(_state)
	_text("HEALTHY CREW: %d / %d  (+%d points each)" % [healthy, keys.size(), Missions.HEALTHY_POINTS], Vector2(x, y), 8,
			Color(Color("8cffb0"), k))
	y += 16
	for line in MissionSelect._wrap(str(Astronauts.data().get("dose_facts", "")) + " (SIMPLIFIED: real cruises are longer, real doses lower per storm.)", w, 8):
		_text(line, Vector2(x, y), 8, Color(0.8, 0.84, 0.92, k))
		y += 10


func _star(c: Vector2, full: bool, r: float, k: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var ang := -PI / 2 + i * PI / 5
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	if full:
		_canvas.draw_colored_polygon(pts, Color(1.0, 0.83, 0.29, k))
	pts.append(pts[0])
	_canvas.draw_polyline(pts, Color(1.0, 0.83, 0.29, k) if full else Color(0.4, 0.45, 0.6, k), 1.0)


func _text(text: String, at: Vector2, size: int, col: Color) -> void:
	_canvas.draw_string(UiFont.font(), at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), col)
