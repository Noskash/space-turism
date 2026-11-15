extends CanvasLayer
## Mission HUD - UI kit "corner blocks" layout (CLAUDE.md "UI kit"):
##   top-left      resources: icon + segmented bar + number (POWER / FUEL / DATA, then HULL / O2 on
##                 missions with the hull system)                                  ResourceBar
##   top-centre    mission progress Earth -> Mars with day + AU, DSN pass, science stored / sent /
##                 lost, mission goals (campaign); under it the alert strip, then sim toasts  AlertBanner
##   top-right     task list                                                        TaskList
##   TAB cycles the whole top: open -> task list folded -> top HUD hidden (a small TAB tab with the
##   open task count stays in the corner; alerts and toasts still show) -> open
##   bottom-right  big action button with the key to press                         ActionButton
##   bottom-left   you (name + role colour), radio, controls hint for the first 30 s
##                 (the crew dose panel, CrewPanel, sits above it)
## Emergencies first slide a slab across the screen (AlertBanner). Reads only
## Events.state_changed. Block rects go to UiKit.hud so stations and the event guide keep out.

const HINT_TIME := 30.0
const HINT_KEYS := [["WASD", "MOVE"], ["SHIFT", "RUN"], ["SPACE", "USE"], ["Q", "LEAVE"], ["TAB", "HUD"],
		["J", "CODEX"], ["K", "SKIN"], ["H", "HELP"], ["ESC", "MENU"]]
const INFO_SIZE := 7

var radio_label: Label       # Radio writes the track text here; the HUD draws it
var local: CrewMember:       # set by Game
	set(value):
		local = value
		_button.local = value
		_tasks.mine = value.role if value else "all"

var _canvas: Node2D
var _bars: Array[ResourceBar] = []
var _tasks := TaskList.new()
var _top_hidden := false     # TAB, third press: resources, progress, goals and tasks out of the way
var _button := ActionButton.new()
var _alert := AlertBanner.new()
var _juice := UiJuice.new()
var _state := {}
var _day := 0.0
var _progress := 0.0         # share of the transfer flown (ShipLighting.progress_of)
var _au := 1.0
var _life := true            # hull + O2 bars (missions with the hull system)
var _goals: Array = []       # Missions.goals(state): {short, done, ...}
var _goals_rect := Rect2()    # goal rows inside the progress block (UiKit.hud.goals)
var _toast := ""
var _toast_left := 0.0
var _last_seq := -1
var _time := 0.0
var _role_text := ""
var _player_name := ""


func _ready() -> void:
	_canvas = Node2D.new()
	UiKit.setup_canvas(_canvas)
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	radio_label = Label.new()
	radio_label.visible = false
	add_child(radio_label)
	_bars = [
		ResourceBar.new("power", "power", UiKit.RESOURCE_COLORS.power),
		ResourceBar.new("fuel", "fuel", UiKit.RESOURCE_COLORS.fuel),
		ResourceBar.new("data", "data", UiKit.RESOURCE_COLORS.data),
		ResourceBar.new("hull", "hull", UiKit.RESOURCE_COLORS.hull),
		ResourceBar.new("oxygen", "o2", UiKit.RESOURCE_COLORS.o2),
	]
	_bars[2].low = -1.0   # storage: empty is fine...
	_bars[2].high = 85.0  # ...full is the problem
	_bars[3].low = 40.0   # hull: breaches get likelier
	_bars[4].low = 35.0   # cabin oxygen
	_life = bool(Missions.sim().get("hull", true))
	Events.state_changed.connect(_on_state_changed)
	_layout_rects()


func _exit_tree() -> void:
	UiKit.hud = {}
	UiKit.overlays = {}


## Role tag (e.g. "NAV+PWR"; "" offline) and player name for the "you" block.
func show_role(role_text: String, player_name := "") -> void:
	_role_text = role_text
	_player_name = player_name


func _on_state_changed(state: Dictionary) -> void:
	var prev := _state
	_state = state
	# Sun distance on the transfer ellipse (same model as ShipLighting): sunlight falls as 1/r^2.
	_day = state.get("day", 0.0)
	_progress = clampf(ShipLighting.progress_of(state), 0.0, 1.0)
	_au = ShipLighting.TRANSFER_A * (1.0 - ShipLighting.TRANSFER_E ** 2) \
			/ (1.0 + ShipLighting.TRANSFER_E * cos(PI * _progress))
	_life = bool(Missions.sim().get("hull", true))
	for bar in _bars:
		bar.set_value(float(state.get(bar.key, 100.0 if bar.key in ["hull", "oxygen"] else 0.0)))
	# Fuel tank temperature (frozen propellant): shown once it gets cold.
	var tank := float(state.get("tank_temp", 20.0))
	_bars[1].badge = "FROZEN %dC" % roundi(tank) if state.get("fuel_frozen", false) \
			else ("COLD %dC" % roundi(tank) if tank < 10.0 else "")
	_bars[1].badge_col = Color("bfefff") if state.get("fuel_frozen", false) else Color("8cd8ff")
	var done_before := _goals_done()
	_goals = Missions.goals(state)
	_tasks.update(state)
	_alert.update(state)
	if not prev.is_empty():
		if _goals_done() > done_before:
			_juice.kick("goals", 0.4)
			Sfx.play("fixed", 1.3)
		if prev.get("dsn", {}).get("site", "") == "" and state.get("dsn", {}).get("site", "") != "":
			_juice.kick("dsn", 0.4)
		if float(state.get("science_sent", 0)) > float(prev.get("science_sent", 0)):
			_juice.kick("sent", 0.35)
		if float(state.get("science_lost", 0)) > float(prev.get("science_lost", 0)):
			_juice.kick("lost", 0.35)
	var seq: int = state.get("action_seq", 0)
	if seq != _last_seq and _last_seq != -1 and state.get("last_action", "") != "":
		_toast = str(state.last_action)
		_toast_left = 2.2
		_juice.kick("toast", 0.25)
		Sfx.play("toast")
	_last_seq = seq


func _goals_done() -> int:
	var n := 0
	for g: Dictionary in _goals:
		n += 1 if g.get("done", false) else 0
	return n


## Rows shown in the resource block: hull + O2 only on missions with the hull system.
func _shown_bars() -> Array[ResourceBar]:
	return _bars if _life else _bars.slice(0, 3)


func _process(delta: float) -> void:
	_time += delta
	_juice.step(delta)
	for bar in _bars:
		bar.step(delta)
	_tasks.step(delta)
	_alert.step(delta)
	_button.step(delta)
	_toast_left = maxf(_toast_left - delta, 0.0)
	if not Tutorial.is_blocking() and Input.is_action_just_pressed(Controls.action("p1", "tasks")):
		_cycle_top()
	_canvas.queue_redraw()


## TAB: open -> task list folded -> whole top hidden -> open.
func _cycle_top() -> void:
	if _top_hidden:
		_top_hidden = false
		_tasks.collapsed = false
		Sfx.play("select")
	elif _tasks.collapsed:
		_top_hidden = true
		Sfx.play("select")
	else:
		_tasks.toggle()


# --- drawing ---------------------------------------------------------------------------------

func _draw_hud() -> void:
	var c := _canvas
	var rects := {}
	if _top_hidden:
		_goals_rect = Rect2()
		rects.tasks = _draw_top_tab(c)
		var strip_top := _alert.draw_strip(c, Vector2(240, 2), 200, 8, rects.tasks.position.x - 4)
		var ty := 2.0
		if strip_top.has_area():
			rects.alert = strip_top
			ty = strip_top.end.y + 2
		if UiKit.overlays.has("guide"):
			ty = maxf(ty, UiKit.overlays.guide.end.y + 2)
		_draw_toast(c, Vector2(240, ty))
		rects.you = _draw_you(c)
		rects.action = _button.draw(c, Vector2(478, 268))
		_alert.draw_slab(c)
		UiKit.hud = rects
		return
	rects.resources = _draw_resources(c)
	rects.tasks = _tasks.draw(c, Vector2(478, 2))
	_goals_rect = Rect2()
	rects.progress = _draw_progress(c, rects.resources.end.x + 4, rects.tasks.position.x - 4)
	if _goals_rect.has_area():
		rects.goals = _goals_rect
	var y: float = rects.progress.end.y + 2
	# The strip may only be as wide as the gap between the side blocks at its height.
	var left: float = rects.resources.end.x + 8 if y < rects.resources.end.y else 8.0
	var right: float = rects.tasks.position.x - 4 if y < rects.tasks.end.y else 476.0
	var strip := _alert.draw_strip(c, Vector2(rects.progress.get_center().x, y), rects.progress.size.x, left, right)
	if strip.has_area():
		rects.alert = strip
		y = strip.end.y + 2
	if UiKit.overlays.has("guide"):  # event walkthrough checklist (EventGuide) sits here
		y = maxf(y, UiKit.overlays.guide.end.y + 2)
	_draw_toast(c, Vector2(rects.progress.get_center().x, y))
	rects.you = _draw_you(c)
	rects.action = _button.draw(c, Vector2(478, 268))
	_alert.draw_slab(c)
	UiKit.hud = rects


## Hidden top HUD: a small tab in the top-right corner (key cap + open tasks, one chip each).
func _draw_top_tab(c: CanvasItem) -> Rect2:
	var key := Controls.key_name("p1", "tasks")
	var cap := UiKit.keycap_size(key, 6)
	var n := _tasks.open_count()
	var label := str(n) if n > 0 else "HUD"
	var h := cap.y + 6
	var w := cap.x + 6 + UiKit.text_w(label, 7) + 6
	var r := Rect2(478 - w, 2, w, h)
	UiKit.panel(c, r)
	UiKit.keycap(c, r.position + Vector2(3, 3), key, 6)
	var col := UiKit.WARN if n > 0 else UiKit.FAINT
	if n > 0 and _tasks.has_urgent() and fmod(_time, 0.5) < 0.25:
		col = Color.WHITE
	UiKit.text(c, Vector2(r.position.x + cap.x + 6, r.end.y - 4), label, 7, col)
	return r


## Rects before the first frame (the cruise tutorial points at them right away).
func _layout_rects() -> void:
	var n := _shown_bars().size()
	var res := Rect2(2, 2, ResourceBar.row_width() + 8, n * ResourceBar.row_height() + (n - 1) + 8)
	var tw := _tasks.width()
	var row_h := maxf(9.0, UiKit.line_h(INFO_SIZE))
	var progress := Rect2(140, 2, 200, 26)
	UiKit.hud = {
		resources = res,
		tasks = Rect2(478 - tw, 2, tw, 40),
		action = Rect2(478 - ActionButton.SIZE, 268 - ActionButton.SIZE - 16, ActionButton.SIZE, ActionButton.SIZE + 16),
		you = Rect2(2, 254, 90, 14),
	}
	if not Missions.current().get("goals", []).is_empty():
		UiKit.hud.goals = Rect2(progress.position.x + 3, progress.end.y - 1, progress.size.x - 6, row_h + 2)
		progress.size.y += row_h + 2
	UiKit.hud.progress = progress


func _draw_resources(c: CanvasItem) -> Rect2:
	var bars := _shown_bars()
	var row_h := ResourceBar.row_height()
	var r := Rect2(2, 2, ResourceBar.row_width() + 8, bars.size() * row_h + (bars.size() - 1) + 8)
	UiKit.panel(c, r)
	for i in bars.size():
		bars[i].draw(c, Vector2(r.position.x + 4, r.position.y + 4 + i * (row_h + 1)))
	return r


## Earth -> ship -> Mars track, then day / AU and DSN / stored / sent / lost (two rows if it gets
## wide), then the mission goals (campaign missions; wrap onto more rows when needed).
func _draw_progress(c: CanvasItem, left_limit: float, right_limit: float) -> Rect2:
	var size := INFO_SIZE
	var row_h := maxf(9.0, UiKit.line_h(size))
	var day_txt := "DAY %d" % int(_day)
	var au_txt := " %.2f AU" % _au
	var dsn: Dictionary = _state.get("dsn", {})
	var site: String = dsn.get("site", "")
	var dsn_txt := "%s %ds" % [site, ceili(float(dsn.get("time_left", 0)))] if site != "" else "--"
	var stored_txt := str(int(_state.get("science_stored", 0)))
	var sent_txt := str(int(_state.get("science_sent", 0)))
	var lost_txt := str(int(_state.get("science_lost", 0)))
	var w_left := UiKit.text_w(day_txt + au_txt, size)
	var w_right := 10 + UiKit.text_w(dsn_txt, size) + 6 + 10 + UiKit.text_w(stored_txt, size) + 6 \
			+ 10 + UiKit.text_w(sent_txt, size) + 6 + 10 + UiKit.text_w(lost_txt, size)
	var avail := right_limit - left_limit
	var one_row := w_left + 12 + w_right + 12 <= avail
	var w := maxf(196.0, (w_left + 12 + w_right if one_row else maxf(w_left, w_right)) + 12)
	var goal_rows := _goal_rows(avail - 10, size)
	for row: Array in goal_rows:
		w = maxf(w, row[-1].end + 10)
	w = clampf(w, 0, avail)
	var center := clampf(240.0, left_limit + w / 2.0, right_limit - w / 2.0)
	var h := 4 + 8 + 3 + row_h * (1 if one_row else 2) + 3
	if not goal_rows.is_empty():
		h += 2 + row_h * goal_rows.size()
	var r := Rect2(roundf(center - w / 2.0), 2, roundf(w), roundf(h))
	UiKit.panel(c, r)
	# Track.
	var ty := r.position.y + 4
	UiKit.icon(c, "earth", Vector2(r.position.x + 4, ty))
	UiKit.icon(c, "mars", Vector2(r.end.x - 12, ty))
	var x0 := r.position.x + 15
	var x1 := r.end.x - 15
	var sx := roundf(lerpf(x0, x1, _progress))
	var line_y := ty + 3
	for x in range(int(x0), int(x1), 2):
		c.draw_rect(Rect2(x, line_y, 1, 2), UiKit.FAINT)
	c.draw_rect(Rect2(x0, line_y, sx - x0, 2), UiKit.ROLE_COLORS.navigator)
	for q in [0.25, 0.5, 0.75]:
		c.draw_rect(Rect2(roundf(lerpf(x0, x1, q)), line_y - 1, 1, 4), UiKit.DIM)
	UiKit.icon(c, "ship", Vector2(sx - 4, ty))
	# Info.
	var base := ty + 8 + 3 + row_h - 2
	UiKit.text(c, Vector2(r.position.x + 5, base), day_txt, size, UiKit.TEXT)
	UiKit.text(c, Vector2(r.position.x + 5 + UiKit.text_w(day_txt, size), base), au_txt, size, UiKit.DIM)
	if not one_row:
		base += row_h
	var x := r.end.x - 5 - w_right if one_row else r.position.x + 5
	var icon_y := base - 7
	var dsn_col := UiKit.GOOD if site != "" else UiKit.FAINT
	UiKit.icon(c, "dsn", Vector2(x, icon_y + _juice.bounce("dsn", 3.0)), 1, dsn_col)
	UiKit.text(c, Vector2(x + 10, base), dsn_txt, size, UiKit.TEXT if site != "" else UiKit.DIM)
	x += 10 + UiKit.text_w(dsn_txt, size) + 6
	# Stored on board (not scored until it is sent home).
	UiKit.icon(c, "data", Vector2(x, icon_y), 1, UiKit.RESOURCE_COLORS.data)
	UiKit.text(c, Vector2(x + 10, base), stored_txt, size, UiKit.TEXT)
	x += 10 + UiKit.text_w(stored_txt, size) + 6
	UiKit.icon(c, "sent", Vector2(x, icon_y + _juice.bounce("sent", 3.0)), 1, UiKit.GOOD)
	var sent_col := UiKit.GOOD if _juice.active("sent") else UiKit.TEXT
	UiKit.text(c, Vector2(x + 10, base), sent_txt, size, sent_col)
	x += 10 + UiKit.text_w(sent_txt, size) + 6
	var lost_n := int(_state.get("science_lost", 0))
	UiKit.icon(c, "lost", Vector2(x, icon_y + _juice.bounce("lost", 3.0)), 1, UiKit.BAD if lost_n > 0 else UiKit.FAINT)
	UiKit.text(c, Vector2(x + 10, base), lost_txt, size, UiKit.BAD if _juice.active("lost") else UiKit.DIM)
	# Goals: "GOALS [x] STORMS 1/3  [ ] SENT 12/30 ...", green when met.
	if not goal_rows.is_empty():
		var gy := base + 2
		c.draw_rect(Rect2(r.position.x + 3, base + 3, r.size.x - 6, 1), UiKit.INK)
		var all_done := _goals_done() == _goals.size()
		var hop := _juice.bounce("goals", 2.0)
		for i in goal_rows.size():
			gy += row_h
			if i == 0:
				UiKit.text(c, Vector2(r.position.x + 5, gy), "GOALS", size, UiKit.GOOD if all_done else UiKit.DIM)
			for item: Dictionary in goal_rows[i]:
				var g: Dictionary = item.goal
				var done: bool = g.get("done", false)
				var gx: float = r.position.x + 5 + item.start
				var box := Rect2(gx, gy - 7 + (hop if done else 0.0), 7, 7)
				c.draw_rect(box, UiKit.INK)
				c.draw_rect(box.grow(-1), UiKit.GOOD if done else UiKit.PANEL_DARK)
				if done:
					c.draw_rect(Rect2(box.position + Vector2(2, 3), Vector2(1, 2)), UiKit.INK)
					c.draw_rect(Rect2(box.position + Vector2(3, 4), Vector2(1, 1)), UiKit.INK)
					c.draw_rect(Rect2(box.position + Vector2(4, 2), Vector2(1, 2)), UiKit.INK)
				UiKit.text(c, Vector2(gx + 10, gy), str(g.get("short", "")), size, UiKit.GOOD if done else UiKit.TEXT)
		_goals_rect = Rect2(r.position.x + 3, base + 3, r.size.x - 6, gy - base)
	return r


## Goals laid out in rows no wider than `max_w`; each row = [{goal, start, end}] (x from the text
## start, the first row after the "GOALS" label, later rows at the same indent).
func _goal_rows(max_w: float, size: int) -> Array:
	var rows := []
	if _goals.is_empty():
		return rows
	var indent := UiKit.text_w("GOALS", size) + 6
	var row := []
	var x := indent
	for g: Dictionary in _goals:
		var item_w := 10 + UiKit.text_w(str(g.get("short", "")), size)
		if not row.is_empty() and x + item_w > max_w:
			rows.append(row)
			row = []
			x = indent
		row.append({goal = g, start = x, end = x + item_w})
		x += item_w + 8
	rows.append(row)
	return rows


func _draw_toast(c: CanvasItem, top_center: Vector2) -> void:
	if _toast_left <= 0.0 or _toast == "":
		return
	var size := 7
	var w := UiKit.text_w(_toast, size) + 10
	var h := maxf(12.0, UiKit.line_h(size) + 4)
	var s := _juice.pop("toast", 0.3)
	var squash := clampf(_toast_left / 0.2, 0.0, 1.0)  # folds away in the last 0.2 s
	var r := Rect2(roundf(top_center.x - w / 2.0), top_center.y, roundf(w), h)
	c.draw_set_transform(r.get_center(), 0.0, Vector2(s, s * squash))
	var lr := Rect2(-r.size / 2.0, r.size)
	UiKit.panel(c, lr, UiKit.PANEL_DARK, UiKit.DIM)
	UiKit.text(c, Vector2(lr.position.x + 5, lr.end.y - 3), _toast, size, UiKit.TEXT, 0)
	c.draw_set_transform(Vector2.ZERO)


## Bottom-left: role colour + who you are, the radio, and the controls for the first 30 s.
func _draw_you(c: CanvasItem) -> Rect2:
	var size := 7
	var role := local.role if local else "all"
	var col := UiKit.role_color(role) if role != "all" else UiKit.TEXT
	var who := _player_name if _player_name != "" else "YOU"
	var tag := _role_text if _role_text != "" else "ALL STATIONS"
	var h := maxf(12.0, UiKit.line_h(size) + 4)
	var w := 9 + UiKit.text_w(who, size) + 5 + UiKit.text_w(tag, size) + 6
	var r := Rect2(2, 268 - h, roundf(w), h)
	UiKit.panel(c, r, UiKit.PANEL, col)
	UiKit.chip(c, Rect2(r.position.x + 3, r.position.y + 3, 4, h - 6), col)
	var base := r.end.y - 3
	UiKit.text(c, Vector2(r.position.x + 9, base), who, size, UiKit.TEXT)
	UiKit.text(c, Vector2(r.position.x + 9 + UiKit.text_w(who + " ", size), base), tag, size, col)
	# Radio, right of the block.
	if radio_label and radio_label.text != "":
		var x := r.end.x + 4
		UiKit.icon(c, "note", Vector2(x, base - 7), 1, Color(1, 0.85, 0.55))
		UiKit.text(c, Vector2(x + 10, base), radio_label.text, 6, Color(1, 0.85, 0.55, 0.9))
	# Controls hint: slides down out of view after HINT_TIME.
	var drop := clampf((_time - HINT_TIME) / 0.4, 0.0, 1.0)
	if drop < 1.0:
		var x := 2.0
		var cap_h := UiKit.keycap_size("A", 6).y
		var y := r.position.y - cap_h - 2 + roundf(drop * 40.0)
		for pair: Array in HINT_KEYS:
			var cap := UiKit.keycap(c, Vector2(x, y), pair[0], 6)
			UiKit.text(c, Vector2(cap.end.x + 2, cap.end.y - 2), pair[1], 6, UiKit.DIM)
			x = cap.end.x + 2 + UiKit.text_w(pair[1], 6) + 5
	return r
