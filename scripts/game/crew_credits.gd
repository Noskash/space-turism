class_name CrewCredits
extends RefCounted
## End-credits dashboard: who did what on this flight, ranked. Built from state.team (the sim's per-crew
## tallies, fake_mission `_credit`) + state.crew (astronauts). MissionReport shows it as its last page.
## MERIT ranks the crew for fun and to show teamwork; it is NOT part of the mission score (hard rule 4).

## Merit per deed.
const MERIT := {tickets = 10.0, perfect = 5.0, good = 2.0, repairs = 6.0, fires = 8.0, patches = 8.0, eva = 15.0,
		burns = 2.0, dodges = 10.0, switches = 1.0, storms = 6.0, moi = 20.0, science = 4.0, sent = 0.5, pings = 0.5, plans = 6.0}
## Awards, in priority order: [stat, title]. Each goes to the crew member with the most of it.
const AWARDS := [["moi", "MARS BRAKER"], ["eva", "SPACEWALKER"], ["fires", "FIREFIGHTER"], ["patches", "HULL WELDER"],
		["repairs", "FIXER"], ["plans", "MISSION PLANNER"], ["sent", "DATA COURIER"], ["dodges", "ACE PILOT"], ["storms", "STORM CHASER"],
		["science", "SCIENCE HUNTER"], ["perfect", "PERFECTIONIST"], ["burns", "HELMSMAN"], ["switches", "SWITCH FLIPPER"],
		["walked", "MARATHONER"], ["pings", "LOUDEST VOICE"]]
## Stat chips: [stat, label, icon]. Shown when > 0, in this order, as many as fit.
const STATS := [["tickets", "TASKS", "check"], ["perfect", "PERFECT", "check"], ["repairs", "REPAIRS", "wrench"],
		["fires", "FIRES OUT", "fire"], ["patches", "HOLES", "wrench"], ["eva", "EVA JOBS", "eva"],
		["sent", "SENT", "sent"], ["science", "SCIENCE", "sci"], ["burns", "BURNS", "nav"],
		["dodges", "DODGES", "debris"], ["plans", "PLANS", "plan"], ["switches", "SWITCHES", "pwr"], ["walked", "WALKED", ""]]
const MEDALS := [Color("ffd34a"), Color("cfd6e6"), Color("d8894a"), Color("6a7390")]
const PX_PER_M := 10.0           # ~16 px crew sprite = a 1.6 m astronaut


static func merit(t: Dictionary) -> float:
	var m := 0.0
	for k: String in MERIT:
		m += float(t.get(k, 0.0)) * float(MERIT[k])
	return m


## Rows sorted by merit: {key, name, astronaut, role, color, t (tallies), merit, awards [titles], rank}.
static func rows(state: Dictionary) -> Array:
	var team: Dictionary = state.get("team", {})
	var crew: Dictionary = state.get("crew", {})
	var keys := {}
	for k in crew:
		keys[k] = true
	for k in team:
		keys[k] = true
	var out := []
	for key: String in keys:
		var a: Dictionary = crew.get(key, {})
		var info := Astronauts.info(str(a.get("astronaut", ""))) if a.has("astronaut") else {}
		var t: Dictionary = team.get(key, {})
		out.append({key = key, name = player_name(key), astronaut = str(info.get("name", "")),
				role = str(info.get("role", "")), color = Color(str(info.get("color", "d8f4ff"))),
				t = t, merit = merit(t), awards = [], dose = float(a.get("dose", 0.0))})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.merit > y.merit if x.merit != y.merit else str(x.key) < str(y.key))
	for i in out.size():
		out[i].rank = i + 1
	if out.size() > 1 and float(out[0].merit) > 0.0:
		out[0].awards.append("MVP")
	for aw: Array in AWARDS:
		var best: Dictionary = {}
		for r: Dictionary in out:
			var v := float(r.t.get(aw[0], 0.0))
			if v > 0.0 and (best.is_empty() or v > float(best.t.get(aw[0], 0.0))):
				best = r
		if not best.is_empty() and best.awards.size() < 3:
			best.awards.append(aw[1])
	return out


## Display name for a crew key ("P1" = "YOU", "Crew_<peer>" = the player's name).
static func player_name(key: String) -> String:
	if key.begins_with("Crew_"):
		var id := key.trim_prefix("Crew_").to_int()
		var n := str(Network.players.get(id, ""))
		if n != "":
			return NetText.player(n).to_upper()
		return "PLAYER %d" % id
	return "YOU"


static func _stat_text(stat: String, v: float) -> String:
	match stat:
		"walked": return "%d m" % roundi(v / PX_PER_M)
		"sent": return "%d" % roundi(v)
	return "%d" % roundi(v)


## Draws the dashboard inside `box`. `t` = seconds since the page opened (rows slide in one by one).
static func draw(ci: CanvasItem, box: Rect2, state: Dictionary, t: float, accent: Color) -> void:
	var list := rows(state)
	var x := box.position.x + 10
	var w := box.size.x - 20
	UiKit.text(ci, Vector2(x, box.position.y + 16), "CREW CREDITS", 11, accent)
	UiKit.text_r(ci, box.end.x - 10, box.position.y + 15, "who did what  ·  ranking, not score", 6, UiKit.DIM, 0)
	if list.is_empty():
		UiKit.text_c(ci, box.get_center().x, box.get_center().y, "No crew on board.", 8, UiKit.DIM)
		return
	var top := box.position.y + 24
	var bottom := box.end.y - 30
	var row_h := floorf(minf(48.0, (bottom - top) / float(list.size()) - 3.0))
	var top_merit := maxf(float(list[0].merit), 1.0)
	for i in list.size():
		var r: Dictionary = list[i]
		var appear := clampf((t - 0.25 * i) / 0.35, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var slide := roundf((1.0 - appear) * (1.0 - appear) * 60.0)
		var rr := Rect2(x + slide, top + i * (row_h + 3.0), w, row_h)
		_draw_row(ci, rr, r, top_merit, t - 0.25 * i)
	# Footer: what the whole crew did together.
	var total := {}
	for r: Dictionary in list:
		for k: String in r.t:
			total[k] = float(total.get(k, 0.0)) + float(r.t[k])
	var foot := "TOGETHER: %d tasks · %d perfect · %d fires out · %d spacewalk jobs · %d m walked" % [
			roundi(total.get("tickets", 0.0)), roundi(total.get("perfect", 0.0)), roundi(total.get("fires", 0.0)),
			roundi(total.get("eva", 0.0)), roundi(float(total.get("walked", 0.0)) / PX_PER_M)]
	if t > 0.25 * list.size() + 0.3:
		UiKit.text_c(ci, box.get_center().x, box.end.y - 20, UiKit.fit(foot, 6, w), 6, UiKit.TEXT, 1)


static func _draw_row(ci: CanvasItem, r: Rect2, row: Dictionary, top_merit: float, t: float) -> void:
	var col: Color = row.color
	var rank: int = row.rank
	UiKit.panel(ci, r, UiKit.PANEL, col)
	# Rank medal.
	var medal: Color = MEDALS[mini(rank - 1, MEDALS.size() - 1)]
	var mr := Rect2(r.position.x + 4, r.position.y + 4, 18, 14)
	UiKit.chip(ci, mr, medal)
	UiKit.text_c(ci, mr.get_center().x, mr.end.y - 3, "#%d" % rank, 7, UiKit.ink_on(medal), 0)
	# Crewmate in the role colour (rank 1 hops).
	var hop := -1 if rank == 1 and fmod(t, 0.8) < 0.4 else 0
	var cm_scale := 2 if r.size.y >= 34.0 else 1
	MenuKit.crewmate(ci, Vector2(r.position.x + 5, r.position.y + (21 if cm_scale == 2 else 20)), col, col.darkened(0.45), cm_scale, hop)
	# Name, astronaut, awards.
	var nx := r.position.x + 34
	UiKit.text(ci, Vector2(nx, r.position.y + 11), str(row.name), 9, UiKit.TEXT)
	var sub := ("%s · %s" % [row.astronaut, row.role]) if row.astronaut != "" else ""
	var nw := UiKit.text_w(str(row.name), 9)
	UiKit.text(ci, Vector2(nx + nw + 6, r.position.y + 10), sub, 6, col, 0)
	var ax := nx
	for aw: String in row.awards:
		var gold := aw == "MVP"
		var tr := MenuKit.tag(ci, Vector2(ax, r.position.y + 14), aw, MEDALS[0] if gold else col, "", 6, gold)
		ax = tr.end.x + 3
	# Merit bar (right).
	var bar_w := 74.0
	var bx := r.end.x - bar_w - 6
	UiKit.text_r(ci, r.end.x - 6, r.position.y + 10, "MERIT %d" % roundi(row.merit), 7, MEDALS[0] if rank == 1 else UiKit.DIM)
	var grow := clampf(t / 0.6, 0.0, 1.0)
	UiKit.seg_bar(ci, Rect2(bx, r.position.y + 14, bar_w, 6), float(row.merit) / top_merit * grow, col, 10)
	# Stat chips along the bottom of the row.
	var sy := r.end.y - 12 if r.size.y >= 34.0 else r.position.y + 14
	var sx := ax + 4 if r.size.y < 34.0 else nx
	for st: Array in STATS:
		var v := float(row.t.get(st[0], 0.0))
		if v < 0.5:
			continue
		var label := "%s %s" % [st[1], _stat_text(st[0], v)]
		var cw := MenuKit.tag_w(label, st[2], 6)
		if sx + cw > r.end.x - 4:
			break
		MenuKit.tag(ci, Vector2(sx, sy), label, UiKit.TEXT.darkened(0.15), st[2], 6)
		sx += cw + 3
	if row.t.is_empty():
		UiKit.text(ci, Vector2(nx, r.end.y - 4), "on board for the ride", 6, UiKit.FAINT, 0)
