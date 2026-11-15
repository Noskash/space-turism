class_name TaskList
extends RefCounted
## Task list (top-right block of the cruise HUD; replaces the old ticket strip).
## One row per sim event (ticket, repair, comet debris) in the order they appeared, coloured by
## role: role stripe + icon, title, countdown segments (repairs blink FIX instead).
## Rows of the local player's roles are bright, other crew's rows dimmer. A finished row gets a
## green strike-through + tick and stays LINGER s; a missed one (station knocked offline, science
## window ran out) a red one. TAB folds the list to its header with one chip per task (a third press hides
## the whole top HUD, see hud.gd).
## Reads only state dictionaries (Events.state_changed), so every co-op peer sees the same list.

const LINGER := 1.6
const MAX_ROWS := 6
const TITLE_SIZE := 7
const URGENT := 4.0

var collapsed := false
## Local player's role string ("navigator+engineer", "all", "" = sees everything as own).
var mine := "all"

var _rows: Array[Dictionary] = []  # {id, role, title, kind, repair, time_left, duration, status, left, grade}
var _prev_offline: Array = []
var _juice := UiJuice.new()
var _first := true
var _streak := 0                    # state.grades.streak: tickets done in time in a row (header "xN")
var _grade_of := {}                 # ticket id -> "perfect" | "good" | "late" (state.grade_log)
const GRADE_WORDS := {perfect = ["PERFECT", UiKit.WARN], good = ["GOOD", UiKit.GOOD], late = ["LATE", Color("ff9a3c")]}


func update(state: Dictionary) -> void:
	var events: Array = state.get("events", [])
	var offline: Array = state.get("offline", [])
	for g: Dictionary in state.get("grade_log", []):
		_grade_of[int(g.id)] = str(g.grade)
	var streak := int(state.get("grades", {}).get("streak", 0))
	if streak > _streak and not _first:
		_juice.kick("streak", 0.35)
	_streak = streak
	var now := {}
	for e: Dictionary in events:
		now[int(e.id)] = e
	for row in _rows:
		if row.status == "open" and not now.has(row.id):
			var knocked: bool = row.role in offline and row.role not in _prev_offline
			var ran_out: bool = not row.repair and row.time_left >= 0.0 and row.time_left < 0.4
			row.status = "missed" if knocked or ran_out else "done"
			row.left = LINGER
			_juice.kick("end_%d" % row.id, 0.3)
	for e: Dictionary in events:
		var id := int(e.id)
		var row := _find(id)
		if row.is_empty():
			row = {id = id, status = "open", left = 0.0}
			_rows.append(row)
			if not _first:
				_juice.kick("new_%d" % id, 0.35)
		row.role = str(e.get("role", ""))
		row.title = str(e.get("title", ""))
		row.kind = str(e.get("kind", ""))
		row.repair = bool(e.get("repair", false))
		row.time_left = float(e.get("time_left", -1.0))
		row.duration = float(e.get("duration", -1.0))
	_prev_offline = offline.duplicate()
	_first = false


func step(delta: float) -> void:
	_juice.step(delta)
	for row in _rows:
		if row.status == "open":
			if row.time_left > 0.0:
				row.time_left = maxf(row.time_left - delta, 0.0)  # count down between sim states
		else:
			row.left -= delta
	_rows = _rows.filter(func(r: Dictionary) -> bool: return r.status == "open" or r.left > 0.0)


func open_count() -> int:
	return _rows.filter(func(r: Dictionary) -> bool: return r.status == "open").size()


## Any open task close to running out (the hidden-HUD tab blinks).
func has_urgent() -> bool:
	for row in _rows:
		if row.status == "open" and _urgent(row):
			return true
	return false


func toggle() -> void:
	collapsed = not collapsed
	Sfx.play("select")


func _find(id: int) -> Dictionary:
	for row in _rows:
		if row.id == id:
			return row
	return {}


func _mine(role: String) -> bool:
	return mine == "" or role == "team" or CrewRoles.has(mine, role)


# --- drawing ---------------------------------------------------------------------------------

func width() -> float:
	return clampf(26 + UiKit.text_w("Solar storm fault", TITLE_SIZE) + 22, 112, 160)


func _row_h() -> float:
	return maxf(9.0, UiKit.line_h(TITLE_SIZE) + 1)


## Draws the block with its top-right corner at `top_right`; returns its rect.
func draw(ci: CanvasItem, top_right: Vector2) -> Rect2:
	var w := width()
	var rh := _row_h()
	var head_h := maxf(11.0, UiKit.line_h(7) + 3)
	var shown := _rows.slice(0, MAX_ROWS)
	var extra := _rows.size() - shown.size()
	var body_rows := 0 if collapsed else maxi(shown.size(), 1) + (1 if extra > 0 else 0)
	var h := 3 + head_h + body_rows * rh + (3 if body_rows > 0 else 1)
	var r := Rect2(top_right.x - w, top_right.y, w, h)
	UiKit.panel(ci, r)
	_draw_header(ci, r, head_h)
	if collapsed:
		return r
	var y := r.position.y + 2 + head_h
	if shown.is_empty():
		UiKit.icon(ci, "check", Vector2(r.position.x + 7, y + roundf((rh - 8) / 2.0)), 1, UiKit.GOOD)
		UiKit.text(ci, Vector2(r.position.x + 18, y + rh - 2), "ALL CLEAR", TITLE_SIZE, Color(UiKit.GOOD, 0.8))
		return r
	for row: Dictionary in shown:
		_draw_row(ci, Rect2(r.position.x + 2, y, w - 4, rh), row)
		y += rh
	if extra > 0:
		UiKit.text(ci, Vector2(r.position.x + 18, y + rh - 2), "+%d MORE" % extra, TITLE_SIZE, UiKit.DIM)
	return r


func _draw_header(ci: CanvasItem, r: Rect2, head_h: float) -> void:
	var x := r.position.x + 5
	var base := r.position.y + 2 + head_h - 3
	UiKit.text(ci, Vector2(x, base), "TASKS", 7, UiKit.DIM)
	x += UiKit.text_w("TASKS ", 7)
	var n := open_count()
	var count_col := UiKit.WARN if n > 0 else UiKit.FAINT
	UiKit.text(ci, Vector2(x, base), str(n), 7, count_col)
	x += UiKit.text_w(str(n) + " ", 7)
	var cap := UiKit.keycap_size("TAB", 6)
	UiKit.keycap(ci, Vector2(r.end.x - cap.x - 4, r.position.y + roundf((head_h - cap.y) / 2.0) + 2), "TAB", 6)
	if _streak >= 2 and not collapsed:   # tickets done in time in a row
		var label := "x%d" % _streak
		var hop := _juice.bounce("streak", 2.0)
		var sx := r.end.x - cap.x - 8 - UiKit.text_w(label, 7)
		UiKit.text(ci, Vector2(roundf(sx), base + hop), label, 7, Color.WHITE if _juice.flash("streak") else UiKit.WARN)
	if collapsed:
		# One chip per open task.
		for row: Dictionary in _rows:
			if row.status != "open" or x > r.end.x - cap.x - 12:
				continue
			var col: Color = UiKit.BAD if row.repair else UiKit.role_color(row.role)
			if _urgent(row) and _juice.blink(0.4):
				col = Color.WHITE
			UiKit.chip(ci, Rect2(x, r.position.y + 4, 4, head_h - 4), col)
			x += 6


func _draw_row(ci: CanvasItem, rr: Rect2, row: Dictionary) -> void:
	var role_col: Color = UiKit.role_color(row.role)
	var slide := roundf(24.0 * _juice.k("new_%d" % row.id))
	rr.position.x += slide
	if _juice.flash("new_%d" % row.id):
		ci.draw_rect(rr, Color(role_col, 0.35))
	var open: bool = row.status == "open"
	var urgent := open and _urgent(row)
	# Role stripe.
	var stripe := UiKit.BAD if row.repair and open else role_col
	if urgent and not _juice.blink(0.4):
		stripe = Color.WHITE
	ci.draw_rect(Rect2(rr.position.x + 1, rr.position.y + 1, 2, rr.size.y - 2), stripe if open else Color(stripe, 0.4))
	# Icon.
	var icon_name: String = UiKit.ROLE_ICONS.get(row.role, "alert")
	var icon_col := role_col
	if row.repair:
		icon_name = "wrench"
		icon_col = UiKit.BAD
	elif row.kind == "dust":
		icon_name = "debris"
	elif row.kind == "fire":
		icon_name = "fire"
		icon_col = Color.WHITE   # the fire icon keeps its own colours
	elif row.kind == "eva":
		icon_name = "eva"
		icon_col = Color.WHITE   # spacesuit helmet, own colours
	if row.status == "done":
		icon_name = "check"
		icon_col = UiKit.GOOD
	elif row.status == "missed":
		icon_name = "lost"
		icon_col = UiKit.BAD
	var hop := _juice.bounce("end_%d" % row.id, 2.0)
	UiKit.icon(ci, icon_name, Vector2(rr.position.x + 5, rr.position.y + roundf((rr.size.y - 8) / 2.0) + hop), 1, icon_col)
	# Timer on the right: 4 segments, or a blinking FIX for repairs.
	var timer_w := maxf(17.0, UiKit.text_w("FIX", TITLE_SIZE) + 1) if row.repair and open else 17.0
	var tx := rr.end.x - timer_w - 2
	if row.status == "done" and _grade_of.has(row.id):   # how well it went
		var word: Array = GRADE_WORDS.get(_grade_of[row.id], ["", UiKit.DIM])
		timer_w = UiKit.text_w(word[0], 6) + 2
		tx = rr.end.x - timer_w - 2
		UiKit.text_r(ci, rr.end.x - 3, rr.end.y - 2, word[0], 6, word[1])
	elif open and row.repair:
		if _juice.blink(0.6):
			UiKit.text_r(ci, rr.end.x - 3, rr.end.y - 2, "FIX", TITLE_SIZE, UiKit.BAD)
	elif open and row.duration > 0.0 and row.time_left >= 0.0:
		var frac: float = clampf(row.time_left / row.duration, 0.0, 1.0)
		var bar_col := Color.WHITE if urgent and _juice.blink(0.3) else role_col
		UiKit.seg_bar(ci, Rect2(tx, rr.position.y + roundf((rr.size.y - 6) / 2.0), timer_w, 6), frac, bar_col, 4)
	# Title, struck through when finished.
	var tx0 := rr.position.x + 16
	var max_w := tx - tx0 - 3
	var title := UiKit.fit(str(row.title), TITLE_SIZE, max_w)
	var title_col := UiKit.TEXT if _mine(row.role) else UiKit.DIM
	if not open:
		title_col = UiKit.FAINT.lightened(0.3)
	UiKit.text(ci, Vector2(tx0, rr.end.y - 2), title, TITLE_SIZE, title_col)
	if not open:
		var line_col := UiKit.GOOD if row.status == "done" else UiKit.BAD
		var tw := UiKit.text_w(title, TITLE_SIZE)
		var grow := clampf(1.0 - _juice.k("end_%d" % row.id), 0.0, 1.0)  # the line swipes across
		ci.draw_rect(Rect2(tx0 - 1, roundf(rr.position.y + rr.size.y / 2.0), roundf((tw + 2) * grow), 1), line_col)


func _urgent(row: Dictionary) -> bool:
	return row.repair or (row.time_left >= 0.0 and row.duration > 0.0 and row.time_left < URGENT)
