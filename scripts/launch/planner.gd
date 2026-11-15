extends Node2D
## Launch window planner (phase 2): between the designer and the launch pad. SIMPLIFIED physics
## (LaunchWindow). The crew picks the launch DATE and the PATH (STANDARD / FAST); the screen shows
## where Earth and Mars are, the transfer path, where Mars will be on arrival, and what the choice
## costs in departure delta-v, the ship's own fuel and the Mars brake burn.
##
## Controls: Navigator (or whoever holds NAV) moves the date with A/D (hold) or by clicking the
## date chart, W/S switches the path. SPACE = READY for everyone. Any change un-readies all.
## Network: same pattern as the designer - the host owns the plan, clients send requests.
##
## EMBEDDED (the hangar's planner console): the hangar owns design + plan and passes them in with
## show_plan(); changes go out through the `request` signal, SPACE cycles the Mars orbit, Q closes.
## No READY here - the crew readies up at the hangar's launch door.

signal request(action: Dictionary)
signal close_requested

const LAUNCH_SCENE := "res://scenes/launch/launch.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"

const FONT_SIZE := 8
const BG := Color("0b0d1a")
const PANEL := Color("151a2e")
const LINE := Color("2c3454")
const DIM := Color("6b7390")
const GOOD := Color("5cf07a")
const WARN := Color("ffc640")
const BAD := Color("ff5050")
const CYAN := Color("48e2ec")
const CYAN_D := Color("1c6e84")
const EARTH := Color("407ede")
const MARS := Color("d4623c")
const SUN := Color("ffd654")

const ORBIT_C := Vector2(131, 108)     # Sun on screen
const R_EARTH := 44.0
const R_MARS := 67.0                   # 1.52 x Earth's
const CHART := Rect2(14, 214, 452, 30)
const REPEAT_FIRST := 0.32
const REPEAT := 0.05

## Overlay inside the hangar (see header). Set before adding the node.
var embedded := false
## Embedded: may the local player change the plan (holds NAV)?
var can_drive := true

var design := {}
var plan := LaunchWindow.default_plan()
var ready_by := {}
var roles := {}

var _saved_window := {}
var _font: Font
var _me := 1
var _ready_peers := {}
var _time := 0.0
var _message := ""
var _message_time := 0.0
var _going := false
var _hold := 0.0                 # key repeat timer for the date
var _dragging := false
# Explanation text at the bottom of the numbers panel scrolls when it does not fit (bigger TEXT SIZE,
# long orbit texts): mouse wheel over the panel, otherwise it steps down a line at a time by itself.
const NUMBERS := Rect2(262, 16, 212, 186)
const SCROLL_PAUSE := 2.5        # s at the top / bottom before auto-scroll moves on
const SCROLL_STEP := 1.3         # s per line while auto-scrolling
const SCROLL_IDLE := 6.0         # s after a wheel scroll before auto-scroll takes over again
var _desc_text := ""             # what is shown; a new text starts at the top
var _desc_over := 0              # lines that do not fit (0 = no scrolling)
var _desc_line := 0              # first visible line
var _desc_wait := SCROLL_PAUSE   # auto-scroll countdown to the next step
var _desc_idle := SCROLL_IDLE    # time since the last wheel scroll
var _stars: Array[Vector3] = []


func _enter_tree() -> void:
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE here (as in the designer)
	if not embedded:
		_saved_window = PixelMode.enter(get_window())


func _exit_tree() -> void:
	UiFont.max_level = 2
	if not embedded:
		PixelMode.exit(get_window(), _saved_window)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Controls.ensure_actions()
	_font = UiFont.font()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 60:
		_stars.append(Vector3(rng.randi_range(0, 479), rng.randi_range(0, 269), rng.randf() * TAU))
	if embedded:
		return
	design = DesignRules.chosen.duplicate(true) if not DesignRules.chosen.is_empty() else DesignRules.new_design()
	plan = LaunchWindow.plan_of(design)
	_me = Network.my_id() if Network.is_in_room() else 1
	_refresh_players()
	if Network.is_in_room():
		Network.room_changed.connect(_on_room_changed)
		Network.room_closed.connect(func(_r: String) -> void: get_tree().change_scene_to_file(JOIN_SCENE))
		multiplayer.peer_disconnected.connect(func(id: int) -> void: _ready_peers.erase(id))
		if not Network.is_host():
			_client_ready.rpc_id(1)
		else:
			_host_hello.rpc()
	PauseMenu.attach(self, "LEAVE TO MAIN MENU")
	Tutorial.attach(self, "planner", [
		{title = "Plan the launch window", rect = Rect2(6, 16, 250, 186),
		 body = "Earth and Mars both circle the Sun. You must launch when Mars is the right angle AHEAD of Earth (about 44 degrees), so that Mars arrives at the meeting point together with you. Aim where Mars WILL be, not where it is."},
		{title = "Launch date", rect = Rect2(6, 204, 468, 44),
		 body = "The Navigator moves the date (A/D or click the chart). Earth gains on Mars every day, so the right angle only comes back every ~26 months. Off the window, the ship must burn its own fuel to catch Mars."},
		{title = "Path", rect = Rect2(262, 16, 212, 186),
		 body = "STANDARD is the cheapest half-orbit. FAST reaches Mars sooner (W/S) but needs a bigger push and arrives faster, so the Mars brake burn costs more fuel. Fuel you burn here is fuel you don't have at Mars."},
		{title = "Ready", rect = Rect2(4, 250, 472, 18),
		 body = "Everyone presses SPACE when happy with the plan. Then: the launch pad."},
	])


## Embedded: the hangar pushes its (host-owned) design and plan.
func show_plan(new_design: Dictionary, new_plan: Dictionary) -> void:
	design = new_design
	plan = new_plan


func _is_host() -> bool:
	return not Network.is_in_room() or Network.is_host()


func _refresh_players() -> void:
	var ids: Array = Network.players.keys() if Network.is_in_room() else [1]
	roles = CrewRoles.assign(ids)
	for id in ready_by.keys():
		if not roles.has(id):
			ready_by.erase(id)


func _can_drive(peer: int) -> bool:
	if embedded:
		return can_drive
	return CrewRoles.has(roles.get(peer, "all"), "navigator")


# --- input -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_message_time = maxf(_message_time - delta, 0.0)
	_auto_scroll(delta)
	if not _going and not Tutorial.is_blocking():
		_handle_keys(delta)
	queue_redraw()


func _handle_keys(delta: float) -> void:
	if embedded and _pressed("leave"):
		close_requested.emit()
		return
	if embedded and _pressed("interact"):
		if _drive_check():
			_send({type = "orbit", id = Orbits.next_id(Orbits.id_of(design))})
			Sfx.play("toggle")
	elif _pressed("interact"):
		_send({type = "ready"})
		Sfx.play("ui_click")
	if _pressed("up") or _pressed("down"):
		if _drive_check():
			var i := LaunchWindow.ORDER.find(plan.speed)
			_send({type = "speed", speed = LaunchWindow.ORDER[wrapi(i + (1 if _pressed("down") else -1), 0, 2)]})
			Sfx.play("toggle")
	var dir := 0
	if Input.is_action_pressed(Controls.action("p1", "left")):
		dir -= 1
	if Input.is_action_pressed(Controls.action("p1", "right")):
		dir += 1
	if dir == 0:
		_hold = 0.0
		return
	if _pressed("left") or _pressed("right"):
		if not _drive_check():
			return
		_hold = REPEAT_FIRST
		_step_date(dir)
	elif _can_drive(_me):
		_hold -= delta
		if _hold <= 0.0:
			_hold = REPEAT
			_step_date(dir)


func _input(event: InputEvent) -> void:
	if _going or Tutorial.is_blocking():
		return
	if event is InputEventMouseButton and event.pressed and NUMBERS.has_point(get_local_mouse_position()) 			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_desc_line = clampi(_desc_line + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, _desc_over)
		_desc_idle = 0.0
		_desc_wait = SCROLL_PAUSE
		return
	var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if click and not event.pressed:
		_dragging = false
		return
	if click and event.pressed and CHART.grow(4).has_point(get_local_mouse_position()):
		if _drive_check():
			_dragging = true
			_date_from_mouse()
	elif event is InputEventMouseMotion and _dragging:
		_date_from_mouse()


func _date_from_mouse() -> void:
	var t := clampf((get_local_mouse_position().x - CHART.position.x) / CHART.size.x, 0.0, 1.0)
	var offset := snappedi(roundi(lerpf(-LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS, t)), LaunchWindow.DAY_STEP)
	if offset != int(plan.offset):
		_send({type = "date", offset = offset})
		Sfx.play("ui_hover")


func _step_date(dir: int) -> void:
	var offset := clampi(int(plan.offset) + dir * LaunchWindow.DAY_STEP, -LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS)
	if offset != int(plan.offset):
		_send({type = "date", offset = offset})
		Sfx.play("ui_hover")


func _drive_check() -> bool:
	if _can_drive(_me):
		return true
	_say("ONLY THE NAVIGATOR CHANGES THE PLAN")
	Sfx.play("denied")
	return false


func _pressed(verb: String) -> bool:
	return Input.is_action_just_pressed(Controls.action("p1", verb))


func _say(text: String) -> void:
	_message = text
	_message_time = 2.0


func _send(action: Dictionary) -> void:
	if embedded:
		request.emit(action)
	elif _is_host():
		_host_apply(_me, action)
	else:
		_request.rpc_id(1, action)


# --- host logic --------------------------------------------------------------------------

func _host_apply(peer: int, action: Dictionary) -> void:
	var new_plan := plan.duplicate()
	var new_ready := ready_by.duplicate()
	match str(action.get("type", "")):
		"date":
			if _can_drive(peer):
				new_plan.offset = clampi(int(action.get("offset", 0)), -LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS)
		"speed":
			if _can_drive(peer) and str(action.get("speed", "")) in LaunchWindow.ORDER:
				new_plan.speed = str(action.speed)
		"ready":
			if new_ready.get(peer, false):
				new_ready.erase(peer)
			elif LaunchWindow.evaluate(design, plan).ok:
				new_ready[peer] = true
			elif peer == _me:
				_say("IMPOSSIBLE DATE - PICK ONE CLOSER TO THE WINDOW")
				Sfx.play("denied")
	if new_plan != plan:
		new_ready = {}
	plan = new_plan
	ready_by = new_ready
	if Network.is_in_room():
		for id: int in _ready_peers:
			_recv_plan.rpc_id(id, plan, ready_by)
	_check_go()


func _check_go() -> void:
	if _going or not _is_host():
		return
	for id in roles:
		if not ready_by.get(id, false):
			return
	var final := LaunchWindow.apply(design, plan)
	if Network.is_in_room():
		_go.rpc(final)
	else:
		_go(final)


func _on_room_changed() -> void:
	_refresh_players()
	if _is_host():
		_check_go()


# --- network -----------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if Network.is_host():
		var id := multiplayer.get_remote_sender_id()
		_ready_peers[id] = true
		_recv_plan.rpc_id(id, plan, ready_by)


## The host's planner just loaded: a client that got here first lost its _client_ready (sent while the host
## was still switching scenes), so it says it again.
@rpc("authority", "call_remote", "reliable")
func _host_hello() -> void:
	if is_inside_tree() and not Network.is_host():
		_client_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request(action: Dictionary) -> void:
	if Network.is_host():
		_host_apply(multiplayer.get_remote_sender_id(), action)


@rpc("authority", "call_remote", "reliable")
func _recv_plan(new_plan: Dictionary, new_ready: Dictionary) -> void:
	plan = new_plan
	ready_by = new_ready


@rpc("authority", "call_local", "reliable")
func _go(final_design: Dictionary) -> void:
	if _going:
		return
	_going = true
	DesignRules.chosen = final_design.duplicate(true)
	Sfx.play("burn")
	_say("PLAN LOCKED - TO THE LAUNCH PAD")
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file(LAUNCH_SCENE)


# --- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG)
	for s in _stars:
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(0.8, 0.85, 1.0, 0.2 + 0.35 * maxf(sin(_time * 1.3 + s.z), 0.0)))
	var e := LaunchWindow.evaluate(design, plan)
	_text(Vector2(8, 11), "LAUNCH WINDOW PLANNER" if embedded else "PLAN THE LAUNCH WINDOW", Color.WHITE)
	_text_right(Vector2(472, 11), "SIMPLIFIED PHYSICS   H: HELP", DIM)
	_panel(Rect2(6, 16, 250, 186))
	_draw_orbits(e)
	_draw_numbers(NUMBERS, e)
	_draw_chart(Rect2(6, 204, 468, 44), e)
	_draw_footer()


func _pos(r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return ORBIT_C + Vector2(cos(a), -sin(a)) * r


func _cost_color(e: Dictionary) -> Color:
	if not e.ok:
		return BAD
	if e.fuel_cost > 0.5:
		return WARN
	return CYAN


func _draw_orbits(e: Dictionary) -> void:
	draw_arc(ORBIT_C, R_EARTH, 0, TAU, 72, EARTH.darkened(0.45), 1.0)
	_dotted_ring(R_MARS, MARS.darkened(0.4))
	draw_circle(ORBIT_C, 4, SUN)
	draw_circle(ORBIT_C, 6, Color(SUN, 0.18))
	var earth := _pos(R_EARTH, 180.0)
	var mars_now := _pos(R_MARS, 180.0 - float(e.lead))
	# the launch angle wedge: Sun -> Earth and Sun -> Mars on launch day
	draw_line(ORBIT_C, earth, Color(CYAN_D, 0.6), 1.0)
	draw_line(ORBIT_C, mars_now, Color(CYAN_D, 0.6), 1.0)
	draw_arc(ORBIT_C, 16, deg_to_rad(-180.0), deg_to_rad(-180.0 + float(e.lead)), 16, CYAN_D, 1.0)
	_text(ORBIT_C + Vector2(-34, -12), "%d°" % roundi(e.lead), CYAN)
	# transfer path: from Earth to where it meets Mars' orbit, coloured by what it costs
	var col := _cost_color(e)
	var sweep := float(e.path.sweep)
	var prev := earth
	var n := 48
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := _path_point(t, sweep)
		if i % 3 != 0:
			draw_line(prev, p, col, 1.0)
		prev = p
	var ship := _path_point(fmod(_time * 0.22, 1.0), sweep)
	draw_rect(Rect2(ship.round() - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
	# where Mars will be when the ship arrives
	var path_end := _pos(R_MARS, float(e.path_end))
	var mars_then := _pos(R_MARS, float(e.arrival_mars))
	if absf(float(e.miss_deg)) > 3.0:
		_dotted_line(path_end, mars_then, Color(col, 0.8))
	draw_arc(mars_then, 5, 0, TAU, 16, MARS if fmod(_time, 0.8) < 0.5 else MARS.darkened(0.3), 1.0)
	draw_circle(earth, 3, EARTH)
	draw_circle(mars_now, 3, MARS)
	_text(earth + Vector2(-30, 14), "EARTH", EARTH.lightened(0.3))
	_text(earth + Vector2(-34, 22), "LAUNCH DAY", DIM)
	_label_out(mars_now, "MARS NOW", MARS.lightened(0.2))
	_label_out(mars_then, "MARS ON ARRIVAL", MARS.lightened(0.2))


## Label placed just outside Mars' orbit, away from the Sun, so it never sits on the rings.
func _label_out(at: Vector2, text: String, col: Color) -> void:
	var dir := (at - ORBIT_C).normalized()
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x
	var p := at + dir * 9.0
	p.x -= w * (0.5 - 0.5 * dir.x)          # right side: text starts at the point; left side: ends there
	p.y += 3.0 + 4.0 * dir.y
	var free_x := p.x
	p.x = clampf(p.x, 10.0, 252.0 - w)
	if absf(p.x - free_x) > 6.0:   # no room beside it (panel edge): put the label under the point
		p = Vector2(clampf(at.x - w / 2.0, 10.0, 252.0 - w), at.y + 8.0 + UiKit.ascent(FONT_SIZE))
	p.y = clampf(p.y, 26.0, 198.0)
	_text(p, text, col)


func _path_point(t: float, sweep: float) -> Vector2:
	var r := R_EARTH + (R_MARS - R_EARTH) * (1.0 - cos(PI * t)) * 0.5
	return _pos(r, 180.0 - sweep * t)


func _dotted_ring(r: float, col: Color) -> void:
	for i in 64:
		if i % 2 == 0:
			var a := TAU * i / 64.0
			draw_arc(ORBIT_C, r, a, a + TAU / 64.0, 2, col, 1.0)


func _dotted_line(a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(int(a.distance_to(b) / 3.0), 1)
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 1.0)


func _draw_numbers(r: Rect2, e: Dictionary) -> void:
	_panel(r)
	var x := r.position.x + 6
	var y := r.position.y + 12
	var w := r.size.x - 12
	_text(Vector2(x, y), "LAUNCH DATE", DIM)
	_text_right(Vector2(x + w, y), str(e.date), Color.WHITE)
	y += _step(9)
	var days := int(e.offset) - LaunchWindow.best_offset(e.speed)
	var off_text := "ON THE BEST DAY" if days == 0 else "%d DAYS %s THE BEST DAY" % [absi(days), "AFTER" if days > 0 else "BEFORE"]
	_text(Vector2(x, y), off_text, GOOD if absi(days) <= 6 else DIM)
	y += _step(13)
	_text(Vector2(x, y), "PATH", DIM)
	var px := x + 40
	for id: String in LaunchWindow.ORDER:
		var p: Dictionary = LaunchWindow.PATHS[id]
		var on: bool = id == e.speed
		var label := "%s %dD" % [p.name, int(p.trip)]
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x + 6
		var chip := Rect2(px, y - _step(8), lw, _step(11))
		draw_rect(chip, Color(CYAN, 0.18) if on else Color(0, 0, 0, 0))
		draw_rect(chip, CYAN if on else LINE, false, 1.0)
		_text(Vector2(px + 3, y), label, Color.WHITE if on else DIM)
		px += lw + 4
	y += _step(14)
	_text(Vector2(x, y), "MARS AHEAD OF EARTH", DIM)
	_text_right(Vector2(x + w, y), "%d° (NEED %d°)" % [roundi(e.lead), roundi(e.ideal_lead)],
			GOOD if absf(float(e.lead_error)) < 3.0 else WARN)
	y += _step(13)
	_text(Vector2(x, y), "DEPARTURE PUSH", DIM)
	_text_right(Vector2(x + w, y), "%.1f KM/S" % float(e.dv), Color.WHITE)
	y += _step(9)
	_text(Vector2(x, y), "ROCKET GIVES", DIM)
	_text_right(Vector2(x + w, y), "%.1f KM/S" % float(e.rocket_dv), Color.WHITE)
	y += _step(9)
	_text(Vector2(x, y), "SHIP'S TANK BURNS", DIM)
	_text_right(Vector2(x + w, y), "%d%% FUEL" % ceili(e.fuel_cost), GOOD if e.fuel_cost <= 0.5 else (BAD if not e.ok else WARN))
	y += _step(9)
	_text(Vector2(x, y), "MARS BRAKE NEEDS", DIM)
	_text_right(Vector2(x + w, y), "%d%% FUEL%s" % [ceili(e.moi), "" if e.moi_mult <= 1.0 else " (x%.1f)" % e.moi_mult], Color.WHITE)
	y += _step(9)
	var left := 100.0 - float(e.fuel_cost)
	_text(Vector2(x, y), "TANK AFTER DEPARTURE", DIM)
	_text_right(Vector2(x + w, y), "~%d%%" % maxi(roundi(left), 0), GOOD if left >= float(e.moi) + 15.0 else (WARN if left >= float(e.moi) else BAD))
	y += _step(6)
	_bar(Rect2(x, y, w, 4), left / 100.0, float(e.moi) / 100.0)
	y += _step(14)
	y = _wrapped(Vector2(x, y), str(e.verdict), w, _cost_color(e) if e.ok and e.fuel_cost > 0.5 else (GOOD if e.ok else BAD)) - _step(9)
	y += _step(10)
	if embedded:   # the console also picks the Mars orbit (it sets the brake burn above)
		var o := Orbits.info(Orbits.id_of(design))
		_text(Vector2(x, y), "MARS ORBIT", DIM)
		_text_right(Vector2(x + w, y), "%s  [SPACE]" % str(o.get("name", "")), CYAN)
		y += _step(10)
		_scrolled(Vector2(x, y), str(o.get("desc", "")), w, DIM, r.end.y - 3)
		return
	_scrolled(Vector2(x, y), str(e.path.desc) + " Launch tank assumed full; the climb to orbit uses some (launch pad).",
			w, DIM, r.end.y - 3)


## Fuel bar: what is left after departure, with a marker at what the Mars brake needs.
func _bar(r: Rect2, fill: float, need: float) -> void:
	draw_rect(r, LINE)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(fill, 0.0, 1.0)), r.size.y)),
			GOOD if fill >= need else BAD)
	var mx := r.position.x + roundf(r.size.x * clampf(need, 0.0, 1.0))
	draw_rect(Rect2(mx, r.position.y - 2, 1, r.size.y + 4), Color.WHITE)


## Fuel cost over the whole date range for the current path: the "window" is the dip.
func _draw_chart(r: Rect2, e: Dictionary) -> void:
	_panel(r)
	draw_rect(CHART, Color(0, 0, 0, 0.25))
	var n := int(CHART.size.x)
	var prev := Vector2.ZERO
	for i in n + 1:
		var t := float(i) / n
		var off := roundi(lerpf(-LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS, t))
		var c: float = LaunchWindow.evaluate(design, {offset = off, speed = e.speed}).fuel_cost
		var x := CHART.position.x + i
		if c <= 0.5:
			draw_rect(Rect2(x, CHART.position.y, 1, CHART.size.y), Color(GOOD, 0.12))
		elif c >= 100.0:
			draw_rect(Rect2(x, CHART.position.y, 1, CHART.size.y), Color(BAD, 0.08))
		var p := Vector2(x, CHART.end.y - 1 - (CHART.size.y - 2) * clampf(c / 100.0, 0.0, 1.0))
		if i > 0:
			draw_line(prev, p, Color(WARN, 0.85), 1.0)
		prev = p
	var best := LaunchWindow.best_offset(e.speed)
	var bx := CHART.position.x + CHART.size.x * inverse_lerp(-LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS, best)
	_text(Vector2(bx - 10, CHART.position.y + 8), "BEST", GOOD)
	var mx := CHART.position.x + CHART.size.x * inverse_lerp(-LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS, int(e.offset))
	draw_rect(Rect2(roundf(mx), CHART.position.y - 2, 1, CHART.size.y + 4), Color.WHITE)
	draw_rect(Rect2(roundf(mx) - 2, CHART.position.y - 4, 5, 3), Color.WHITE)
	_text(Vector2(r.position.x + 6, r.position.y + 8), "FUEL THE SHIP MUST BURN, BY LAUNCH DATE", DIM)
	_text_right(Vector2(r.end.x - 6, r.position.y + 8), "NEXT WINDOW: %s (+26 MONTHS)" %
			LaunchWindow.date_text(LaunchWindow.SYNODIC_DAYS).substr(0, 7), DIM)
	_text(Vector2(CHART.position.x, r.end.y - 1), "-%d D" % LaunchWindow.RANGE_DAYS, DIM)
	_text_right(Vector2(CHART.end.x, r.end.y - 1), "+%d D" % LaunchWindow.RANGE_DAYS, DIM)


func _draw_footer() -> void:
	if embedded:
		var keys := "A/D DATE  W/S PATH  SPACE ORBIT  Q CLOSE" if can_drive else "ONLY THE NAVIGATOR CHANGES THE PLAN   Q CLOSE"
		_text_right(Vector2(472, 262), keys, CYAN if can_drive else DIM)
		var room := 464.0 - UiKit.text_w(keys, FONT_SIZE) - 12.0
		_text(Vector2(8, 262), UiKit.fit("READY UP AT THE LAUNCH DOOR WHEN THE PLAN IS SET", FONT_SIZE, room), DIM)
		_draw_message()
		return
	var ids := roles.keys()
	ids.sort()
	var x := 8.0
	for i in ids.size():
		var id: int = ids[i]
		var ok: bool = ready_by.get(id, false)
		var text := "P%d %s %s" % [i + 1, CrewRoles.tag(roles[id]), "READY" if ok else "NOT READY"]
		_text(Vector2(x, 262), text, GOOD if ok else CrewRoles.color(roles[id]))
		x += _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x + 12
	var hint := "A/D DATE  W/S PATH  SPACE READY" if _can_drive(_me) else "NAVIGATOR PLANS  SPACE READY"
	if x + UiKit.text_w(hint, FONT_SIZE) < 470.0:
		_text_right(Vector2(472, 262), hint, DIM)
	_draw_message()


func _draw_message() -> void:
	if _message_time > 0.0:
		var w := _font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x
		var h := UiKit.line_h(FONT_SIZE) + 4
		draw_rect(Rect2(240 - w / 2 - 6, 128 - h + 4, w + 12, h), Color(0, 0, 0, 0.8))
		_text(Vector2(240 - w / 2, 128), _message, WARN)


func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, LINE, false, 1.0)


func _text(pos: Vector2, text: String, color: Color) -> void:
	draw_string(_font, pos.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE), color)


func _text_right(pos: Vector2, text: String, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x
	_text(Vector2(pos.x - w, pos.y), text, color)


## Word-wrapped text; lines below `max_y` (baseline) are dropped. Returns the y below the last line.
func _wrapped(pos: Vector2, text: String, width: float, color: Color, max_y := INF) -> float:
	var y := pos.y
	for line in UiKit.wrap(text, FONT_SIZE, width):
		if y > max_y:
			break
		if line != "":
			_text(Vector2(pos.x, y), line, color)
			y += _step(9)
	return y


## Like _wrapped, but scrolls (from _desc_line) when the text is taller than the space down to `max_y`,
## with a thin scrollbar on the right edge of the panel.
func _scrolled(pos: Vector2, text: String, width: float, color: Color, max_y: float) -> void:
	var lines := PackedStringArray()
	for l in UiKit.wrap(text, FONT_SIZE, width - 4):
		if l != "":
			lines.append(l)
	if text != _desc_text:
		_desc_text = text
		_desc_line = 0
		_desc_wait = SCROLL_PAUSE
	var step := _step(9)
	var fit := maxi(int(floorf((max_y - pos.y) / step)) + 1, 1)
	_desc_over = maxi(lines.size() - fit, 0)
	_desc_line = clampi(_desc_line, 0, _desc_over)
	var y := pos.y
	for i in range(_desc_line, mini(_desc_line + fit, lines.size())):
		_text(Vector2(pos.x, y), lines[i], color)
		y += step
	if _desc_over > 0:
		var top := pos.y - step + 3
		var track := Rect2(NUMBERS.end.x - 4, top, 2, max_y + 3 - top)
		draw_rect(track, Color(LINE, 0.6))
		var h := maxf(roundf(track.size.y * float(fit) / float(lines.size())), 4.0)
		var at := roundf((track.size.y - h) * float(_desc_line) / float(_desc_over))
		draw_rect(Rect2(track.position.x, track.position.y + at, 2, h), CYAN)


## Steps the explanation down a line at a time, pauses at the bottom, then jumps back to the top.
func _auto_scroll(delta: float) -> void:
	_desc_idle += delta
	if _desc_over <= 0 or _desc_idle < SCROLL_IDLE:
		return
	_desc_wait -= delta
	if _desc_wait > 0.0:
		return
	if _desc_line >= _desc_over:
		_desc_line = 0
		_desc_wait = SCROLL_PAUSE
	else:
		_desc_line += 1
		_desc_wait = SCROLL_PAUSE if _desc_line >= _desc_over else SCROLL_STEP


## A vertical gap that grows a bit with TEXT SIZE (not fully, so the panels still fit).
func _step(n: float) -> float:
	return roundf(n * lerpf(1.0, UiFont.scale(), 0.85))
