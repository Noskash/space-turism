extends CanvasLayer
## Mission HUD - UI kit "corner blocks" layout (CLAUDE.md "UI kit"):
##   top-left      resources: icon + segmented bar + number (POWER / FUEL / DATA)   ResourceBar
##   top-centre    mission progress Earth -> Mars with day + AU, DSN pass, science sent / lost;
##                 under it the alert strip, then sim toasts                       AlertBanner
##   top-right     task list, TAB folds it                                          TaskList
##   bottom-right  big action button with the key to press                         ActionButton
##   bottom-left   you (name + role colour), radio, controls hint for the first 30 s
## Emergencies first slide a slab across the screen (AlertBanner). Reads only
## Events.state_changed. Block rects go to UiKit.hud so stations and the event guide keep out.

const HINT_TIME := 30.0
const HINT_KEYS := [["WASD", "MOVE"], ["SHIFT", "RUN"], ["SPACE", "USE"], ["TAB", "TASKS"],
		["K", "SKIN"], ["H", "HELP"], ["ESC", "MENU"]]

var radio_label: Label       # Radio writes the track text here; the HUD draws it
var local: CrewMember:       # set by Game
	set(value):
		local = value
		_button.local = value
		_tasks.mine = value.role if value else "all"

var _canvas: Node2D
var _bars: Array[ResourceBar] = []
var _tasks := TaskList.new()
var _button := ActionButton.new()
var _alert := AlertBanner.new()
var _juice := UiJuice.new()
var _state := {}
var _day := 0.0
var _au := 1.0
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
	]
	_bars[2].low = -1.0   # storage: empty is fine...
	_bars[2].high = 85.0  # ...full is the problem
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
	_au = ShipLighting.TRANSFER_A * (1.0 - ShipLighting.TRANSFER_E ** 2) \
			/ (1.0 + ShipLighting.TRANSFER_E * cos(PI * clampf(_day / ShipLighting.CRUISE_DAYS, 0.0, 1.0)))
	for bar in _bars:
		bar.set_value(float(state.get(bar.key, 0)))
	_tasks.update(state)
	_alert.update(state)
	if not prev.is_empty():
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
		_tasks.toggle()
	_canvas.queue_redraw()


# --- drawing ---------------------------------------------------------------------------------

func _draw_hud() -> void:
	var c := _canvas
	var rects := {}
	rects.resources = _draw_resources(c)
	rects.tasks = _tasks.draw(c, Vector2(478, 2))
	rects.progress = _draw_progress(c, rects.resources.end.x + 4, rects.tasks.position.x - 4)
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


## Rects before the first frame (the cruise tutorial points at them right away).
func _layout_rects() -> void:
	var res_h := 3 * ResourceBar.row_height() + 2 + 8
	var res := Rect2(2, 2, ResourceBar.row_width() + 8, res_h)
	var tw := _tasks.width()
	UiKit.hud = {
		resources = res,
		tasks = Rect2(478 - tw, 2, tw, 40),
		progress = Rect2(140, 2, 200, 26),
		action = Rect2(478 - ActionButton.SIZE, 268 - ActionButton.SIZE - 16, ActionButton.SIZE, ActionButton.SIZE + 16),
		you = Rect2(2, 254, 90, 14),
	}


func _draw_resources(c: CanvasItem) -> Rect2:
	var row_h := ResourceBar.row_height()
	var r := Rect2(2, 2, ResourceBar.row_width() + 8, 3 * row_h + 2 + 8)
	UiKit.panel(c, r)
	for i in _bars.size():
		_bars[i].draw(c, Vector2(r.position.x + 4, r.position.y + 4 + i * (row_h + 1)))
	return r


## Earth -> ship -> Mars track, then day / AU and DSN / sent / lost (two rows if it gets wide).
func _draw_progress(c: CanvasItem, left_limit: float, right_limit: float) -> Rect2:
	var size := 7
	var row_h := maxf(9.0, UiKit.line_h(size))
	var day_txt := "DAY %d" % int(_day)
	var au_txt := " %.2f AU" % _au
	var dsn: Dictionary = _state.get("dsn", {})
	var site: String = dsn.get("site", "")
	var dsn_txt := "%s %ds" % [site, ceili(float(dsn.get("time_left", 0)))] if site != "" else "--"
	var sent_txt := str(int(_state.get("science_sent", 0)))
	var lost_txt := str(int(_state.get("science_lost", 0)))
	var w_left := UiKit.text_w(day_txt + au_txt, size)
	var w_right := 10 + UiKit.text_w(dsn_txt, size) + 6 + 10 + UiKit.text_w(sent_txt, size) + 6 + 10 + UiKit.text_w(lost_txt, size)
	var avail := right_limit - left_limit
	var one_row := w_left + 12 + w_right + 12 <= avail
	var w := clampf(maxf(196.0, (w_left + 12 + w_right if one_row else maxf(w_left, w_right)) + 12), 0, avail)
	var center := clampf(240.0, left_limit + w / 2.0, right_limit - w / 2.0)
	var h := 4 + 8 + 3 + row_h * (1 if one_row else 2) + 3
	var r := Rect2(roundf(center - w / 2.0), 2, roundf(w), roundf(h))
	UiKit.panel(c, r)
	# Track.
	var ty := r.position.y + 4
	UiKit.icon(c, "earth", Vector2(r.position.x + 4, ty))
	UiKit.icon(c, "mars", Vector2(r.end.x - 12, ty))
	var x0 := r.position.x + 15
	var x1 := r.end.x - 15
	var k := clampf(_day / ShipLighting.CRUISE_DAYS, 0.0, 1.0)
	var sx := roundf(lerpf(x0, x1, k))
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
	UiKit.icon(c, "sent", Vector2(x, icon_y + _juice.bounce("sent", 3.0)), 1, UiKit.GOOD)
	var sent_col := UiKit.GOOD if _juice.active("sent") else UiKit.TEXT
	UiKit.text(c, Vector2(x + 10, base), sent_txt, size, sent_col)
	x += 10 + UiKit.text_w(sent_txt, size) + 6
	var lost_n := int(_state.get("science_lost", 0))
	UiKit.icon(c, "lost", Vector2(x, icon_y + _juice.bounce("lost", 3.0)), 1, UiKit.BAD if lost_n > 0 else UiKit.FAINT)
	UiKit.text(c, Vector2(x + 10, base), lost_txt, size, UiKit.BAD if _juice.active("lost") else UiKit.DIM)
	return r


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
