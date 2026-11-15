class_name PlanBoard
extends CanvasLayer
## FLIGHT PLAN on the Mission Hub holo-table (Station role "team", SPACE with no storm ticket).
## A timeline Earth -> Mars with what is coming (state.forecast: real named comet trails and asteroids,
## the cold zone, the solar conjunction; built by fake_mission with Forecast.make). Pick one (A/D or click),
## SPACE = plan / cancel ({type = "plan", id} -> state.plan). Planned items are handled by stored commands
## when the ship gets there; unplanned ones just happen. Anyone can plan; the board stays open while the
## mission runs (it is not paused). Q closes.

const LEAD_DAYS := 6.0           # same as fake_mission PLAN_LEAD: closer than this = too late
const COLOR := Color("b48cff")   # holo-table violet (team)
const TL := Rect2(98, 78, 284, 0)   # timeline: Earth at x, Mars at end.x, line at y
const ARM_TIME := 0.2

var state := {}                  # latest sim state (the Station keeps it fresh)
var send: Callable               # Station._send: Events.action_requested("team", action)

var _canvas: Node2D
var _frame := MinigameFrame.new("FLIGHT PLAN", "holo", COLOR)
var _sel := -1                   # index into state.forecast
var _t := 0.0
var _hits := []                  # [Rect2, index] icon click areas
var _button := Rect2()


func _ready() -> void:
	layer = 15
	_canvas = Node2D.new()
	UiKit.setup_canvas(_canvas)
	_canvas.draw.connect(_draw_board)
	add_child(_canvas)
	Tutorial.hold(true)
	Sfx.play("page")
	var list := _items()
	for i in list.size():   # first thing still ahead that can be planned
		if not list[i].done and _ahead(list[i]) >= LEAD_DAYS:
			_sel = i
			break
	if _sel < 0:
		_sel = maxi(list.size() - 1, 0)


func _exit_tree() -> void:
	Tutorial.hold(false)
	Codex.unlock(["flight_plan", "near_earth_asteroid", "comet_debris"])   # on close: its toast won't cover the board


func _items() -> Array:
	return state.get("forecast", [])


func _ahead(item: Dictionary) -> float:
	return float(item.day) - float(state.get("day", 0.0))


func _planned(item: Dictionary) -> bool:
	return state.get("plan", {}).has(str(item.id))


func _process(delta: float) -> void:
	_t += delta
	_frame.step(delta)
	if not state.get("finished", {}).is_empty() or str(state.get("lost", "")) != "":
		queue_free()
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(Controls.action("p1", "leave")):
		get_viewport().set_input_as_handled()
		Sfx.play("undock")
		queue_free()
		return
	var list := _items()
	if list.is_empty():
		return
	if event.is_action_pressed(Controls.action("p1", "left")) or event.is_action_pressed(Controls.action("p1", "right")):
		get_viewport().set_input_as_handled()
		_sel = wrapi(_sel + (1 if event.is_action_pressed(Controls.action("p1", "right")) else -1), 0, list.size())
		Sfx.play("select")
	elif event.is_action_pressed(Controls.action("p1", "interact")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _t > ARM_TIME:
			_toggle()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = _canvas.get_global_transform_with_canvas().affine_inverse() * event.position
		for h: Array in _hits:
			if (h[0] as Rect2).has_point(p):
				_sel = int(h[1])
				Sfx.play("select")
				get_viewport().set_input_as_handled()
				return
		if _button.has_point(p):
			get_viewport().set_input_as_handled()
			_toggle()


func _toggle() -> void:
	var list := _items()
	if _sel < 0 or _sel >= list.size():
		return
	var item: Dictionary = list[_sel]
	if not _planned(item) and (item.done or _ahead(item) < LEAD_DAYS):
		Sfx.play("denied")
		return
	Sfx.play("toggle" if _planned(item) else "fixed")
	send.call({type = "plan", id = int(item.id)})


# --- drawing --------------------------------------------------------------------------------

func _draw_board() -> void:
	var c := _canvas
	_frame.draw(c, 0.0, 0.0, "")
	var list := _items()
	var days := maxf(float(state.get("cruise_days", 0.0)), 1.0)
	var day := float(state.get("day", 0.0))
	_hits.clear()
	# Timeline: Earth -> Mars, the part already flown filled in, NOW marker.
	var y := TL.position.y
	UiKit.icon(c, "earth", Vector2(TL.position.x - 14, y - 4))
	UiKit.icon(c, "mars", Vector2(TL.end.x + 6, y - 4))
	c.draw_rect(Rect2(TL.position.x - 1, y - 2, TL.size.x + 2, 5), UiKit.INK)
	c.draw_rect(Rect2(TL.position.x, y - 1, TL.size.x, 3), UiKit.WELL)
	var now_x := roundf(TL.position.x + TL.size.x * clampf(day / days, 0.0, 1.0))
	c.draw_rect(Rect2(TL.position.x, y - 1, now_x - TL.position.x, 3), COLOR.darkened(0.35))
	for k in 5:   # quarter ticks
		var tx := roundf(TL.position.x + TL.size.x * k / 4.0)
		c.draw_rect(Rect2(tx, y + 3, 1, 2), UiKit.FAINT)
	UiKit.text_c(c, TL.position.x, y + 12, "DAY 0", 6, UiKit.FAINT, 0)
	UiKit.text_c(c, TL.end.x, y + 12, "DAY %d" % int(days), 6, UiKit.FAINT, 0)
	# Items: icon in a chip above (or below, when crowded) the line.
	var last_x := -100.0
	var up := true
	for i in list.size():
		var item: Dictionary = list[i]
		var x := roundf(TL.position.x + TL.size.x * clampf(float(item.day) / days, 0.0, 1.0))
		up = not up if x - last_x < 14.0 else true
		last_x = x
		var info: Dictionary = Forecast.KIND_INFO[item.kind]
		var col: Color = UiKit.ROLE_COLORS.get(info.role, COLOR)
		var box := Rect2(x - 6, (y - 20) if up else (y + 15), 12, 12)
		var sel := i == _sel
		var planned := _planned(item)
		c.draw_rect(Rect2(x, box.end.y if up else y + 3, 1, (y - 2 - box.end.y) if up else (box.position.y - y - 3)),
				col if not item.done else UiKit.FAINT)
		if sel:
			var b := 1.0 if fmod(_t, 0.6) < 0.3 else 0.0
			c.draw_rect(box.grow(3 + b), Color(col, 0.35))
		UiKit.chip(c, box, col.darkened(0.55) if item.done else (col if planned else UiKit.PANEL))
		UiKit.icon(c, info.icon, box.position + Vector2(2, 2), 1,
				UiKit.INK if planned and not item.done else (UiKit.FAINT if item.done else col))
		if planned:   # tick badge
			c.draw_rect(Rect2(box.end.x - 3, box.position.y - 2, 5, 5), UiKit.INK)
			c.draw_rect(Rect2(box.end.x - 2, box.position.y - 1, 3, 3), UiKit.GOOD)
		elif item.done and str(item.get("result", "")) == "missed":
			c.draw_rect(Rect2(box.end.x - 3, box.position.y - 2, 5, 5), UiKit.INK)
			c.draw_rect(Rect2(box.end.x - 2, box.position.y - 1, 3, 3), UiKit.BAD)
		_hits.append([box.grow(3), i])
	# The ship (NOW).
	var bob := -1.0 if fmod(_t, 0.8) < 0.4 else 0.0
	c.draw_rect(Rect2(now_x - 3, y - 3 + bob, 7, 7), UiKit.INK)
	c.draw_rect(Rect2(now_x - 2, y - 2 + bob, 5, 5), Color.WHITE)
	UiKit.text_c(c, now_x, y + 12, "NOW", 6, UiKit.TEXT, 1)
	_draw_info(c, list)
	var key := Controls.key_name("p1", "interact")
	_frame.draw_footer(c, "A/D PICK  ·  %s PLAN / CANCEL" % key, UiKit.TEXT,
			"PLANS ARE STORED COMMANDS: THEY RUN WHEN THE SHIP GETS THERE · SIMPLIFIED")


func _draw_info(c: CanvasItem, list: Array) -> void:
	var r := Rect2(80, 104, 320, 110)
	UiKit.panel(c, r, UiKit.PANEL_DARK)
	_button = Rect2()
	if list.is_empty() or _sel < 0 or _sel >= list.size():
		UiKit.text_c(c, r.get_center().x, r.get_center().y, "Nothing on the forecast.", 8, UiKit.DIM)
		return
	var item: Dictionary = list[_sel]
	var info: Dictionary = Forecast.KIND_INFO[item.kind]
	var col: Color = UiKit.ROLE_COLORS.get(info.role, COLOR)
	var x := r.position.x + 6
	var tr := MenuKit.tag(c, Vector2(x, r.position.y + 5), info.label, col, info.icon, 6, true)
	var ahead := _ahead(item)
	var when := ("DAY %d · IN %d DAYS" % [int(item.day), ceili(ahead)]) if ahead > 0.0 else ("DAY %d" % int(item.day))
	UiKit.text(c, Vector2(tr.end.x + 5, r.position.y + 12), when, 6, UiKit.DIM, 0)
	UiKit.text(c, Vector2(x, r.position.y + 27), UiKit.fit(str(item.name), 10, r.size.x - 12), 10, UiKit.TEXT)
	var yy := r.position.y + 37
	for line in UiKit.wrap(str(item.fact), 6, r.size.x - 12).slice(0, 2):
		UiKit.text(c, Vector2(x, yy), line, 6, UiKit.DIM, 0)
		yy += 8
	# What a plan does / what happens without one.
	var planned := _planned(item)
	yy += 2
	for line in UiKit.wrap(info.plan, 6, r.size.x - 12).slice(0, 2):
		UiKit.text(c, Vector2(x, yy), line, 6, UiKit.GOOD if planned else UiKit.TEXT, 0)
		yy += 8
	if not planned:
		for line in UiKit.wrap(info.skip, 6, r.size.x - 12).slice(0, 2):
			UiKit.text(c, Vector2(x, yy), line, 6, UiKit.WARN, 0)
			yy += 8
	# Status + button (bottom right).
	var status := ""
	var status_col := UiKit.DIM
	var can := false
	if item.done:
		match str(item.get("result", "")):
			"planned": status = "DONE - THE PLAN WORKED"; status_col = UiKit.GOOD
			"failed": status = "PLAN FAILED"; status_col = UiKit.BAD
			"missed": status = "MISSED - NOT PLANNED"; status_col = UiKit.BAD
			_: status = "PASSED"
	elif planned:
		var by := str(state.get("plan", {}).get(str(item.id), ""))
		status = "PLANNED" + ((" BY " + CrewCredits.player_name(by)) if by != "" else "")
		status_col = UiKit.GOOD
		can = true
	elif ahead < LEAD_DAYS:
		status = "TOO LATE - COMMANDS NEED TIME TO UPLOAD"
		status_col = UiKit.WARN
	else:
		status = "NOT PLANNED"
		can = true
	UiKit.text(c, Vector2(x, r.end.y - 5), status, 7, status_col, 1)
	if can:
		var label := "CANCEL" if planned else "PLAN IT"
		var w := UiKit.text_w(label, 8) + 14
		_button = Rect2(r.end.x - w - 6, r.end.y - 17, w, 13)
		UiKit.chip(c, _button, UiKit.PANEL if planned else COLOR)
		UiKit.text_c(c, _button.get_center().x, _button.end.y - 3, label, 8,
				UiKit.TEXT if planned else UiKit.ink_on(COLOR), 0)
