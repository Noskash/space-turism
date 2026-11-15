extends Node2D
## Design phase: the crew builds one spacecraft together, then launches into the cruise.
##
## Every player has a cursor (WASD + SPACE). The SHIP column (class + READY) is shared; the
## NAV / PWR / COM / SCI columns are only reachable by players holding that role, so each crew
## member shops for their own station - but slots, mass, power and budget are one shared pool.
## Launch when every player is READY and the design has no errors; any change un-readies all.
##
## Network: the host owns the design. Clients send requests, the host applies them and sends the
## design back; cursors are relayed through the host (same pattern as NetSync in the game).
## Offline (no room) everything is applied locally.

const LAUNCH_SCENE := "res://scenes/launch/planner.tscn"   # launch window planner, then the pad
const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"

const COLUMNS := [
	{id = "ship", title = "SHIP"},
	{id = "navigator", title = "NAV"},
	{id = "engineer", title = "PWR"},
	{id = "comms", title = "COM"},
	{id = "scientist", title = "SCI"},
]
const SHORT_NAMES := {
	"solar_large": "Large solar", "rtg": "RTG", "battery_large": "Big battery",
	"radiator": "Radiator", "computer_radhard": "Rad-hard CPU", "antenna_high": "High-gain dish",
	"recorder_small": "Small recorder", "recorder_large": "Large recorder",
	"relay_radio": "Relay radio", "tank_large": "Large tank", "star_tracker": "Star tracker",
	"reaction_wheels": "React. wheels", "camera_hires": "Hi-res camera",
	"spectrometer": "Spectrometer", "radar_sounder": "Radar sounder",
	"thermal_imager": "Thermal imager", "magnetometer": "Magnetometer",
	"rad_shielding": "Rad shielding", "particle_monitor": "Particle mon.",
	"whipple_shield": "Whipple shield",
}
const CLASS_HINTS := {
	"light": "Cheap and light. Few slots. Suits the FAST path.",
	"balanced": "Middle of everything. Suits the STANDARD path.",
	"heavy": "Many slots, little money left. Suits VENUS flyby.",
}

const FONT_SIZE := 8
const BG := Color("0b0d1a")
const PANEL := Color("151a2e")
const LINE := Color("2c3454")
const DIM := Color("6b7390")
const GOOD := Color("5cf07a")
const BAD := Color("ff5050")
const CATALOG_Y := 152
const COL_W := 94
const ROW_H := 12
const CURSOR_SEND := 0.1

var design := DesignRules.new_design() if DesignRules.chosen.is_empty() else DesignRules.chosen.duplicate(true)
var ready_by := {}             # peer id -> true
var cursors := {}           # peer id -> Vector2i(col, row)
var roles := {}             # peer id -> role string

var _saved_window := {}
var _preview: ShipPreview
var _font: Font
var _me := 1
var _ready_peers := {}      # host: clients whose designer scene is loaded
var _send_timer := 0.0
var _message := ""
var _message_time := 0.0
var _launching := false
var _time := 0.0
var _stars: Array[Vector3] = []


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())
	UiFont.max_level = 1  # dense grid: TEXT SIZE stops at LARGE here


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	UiFont.max_level = 2


func _ready() -> void:
	UiKit.setup_canvas(self)
	Controls.ensure_actions()
	_font = UiFont.font()
	_preview = ShipPreview.new()
	_preview.position = Vector2(8, 18)
	add_child(_preview)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 50:
		_stars.append(Vector3(rng.randi_range(0, 479), rng.randi_range(0, 269), rng.randf() * TAU))

	_me = Network.my_id() if Network.is_in_room() else 1
	_refresh_players()
	cursors[_me] = Vector2i(0, 1)  # starts on "Balanced"
	if Network.is_in_room():
		Network.room_changed.connect(_on_room_changed)
		Network.room_closed.connect(func(_r: String) -> void: get_tree().change_scene_to_file(JOIN_SCENE))
		multiplayer.peer_disconnected.connect(func(id: int) -> void: _ready_peers.erase(id))
		if not Network.is_host():
			_client_ready.rpc_id(1)
	_apply_design(design, {})
	PauseMenu.attach(self, "LEAVE TO MAIN MENU", "WASD MOVE · SPACE PICK · J CODEX · H HELP")
	# Campaign mission: the briefing comes first (once per mission), then the designer tutorial.
	var id := Missions.current_id()
	if id != "" and not MissionBriefing.was_shown(id):
		var briefing := MissionBriefing.attach(self)
		briefing.open.call_deferred()
		briefing.closed.connect(_attach_tutorial, CONNECT_ONE_SHOT)
	else:
		_attach_tutorial()


func _attach_tutorial() -> void:
	Tutorial.attach(self, "designer", [
		{title = "Build your spacecraft", rect = Rect2(6, 16, 164, 132),
		 body = "Together you design ONE ship. Every part costs mass, power AND budget - there is no free upgrade."},
		{title = "Your column", rect = Rect2(4, 152, 470, 96),
		 body = "WASD moves your cursor, SPACE adds or removes a part. You can only shop in your crew role's column (NAV / PWR / COM / SCI); SHIP is shared."},
		{title = "Shared limits", rect = Rect2(174, 16, 128, 132),
		 body = "Mass, power, budget and slots are shared by the whole crew. A heavier ship needs a bigger, pricier rocket. Negative power is allowed - the battery will drain in flight."},
		{title = "Part card", rect = Rect2(306, 16, 168, 132),
		 body = "Shows what the part under your cursor does and what it costs. Fixing one problem usually creates another."},
		{title = "Mars orbit", rect = Rect2(4, CATALOG_Y + 13 + 3 * ROW_H, COL_W - 3, ROW_H),
		 body = "Pick where the ship will orbit Mars. A low orbit sees more but needs a big brake burn; a high oval one is cheap to reach and talks to Earth longer. The report shows what each orbit achieved."},
		{title = "Ready", rect = Rect2(4, 152, 92, 96),
		 body = "When everyone is READY and the ship has no errors, you go to the launch pad. Any change un-readies everyone."},
	])


func _is_host() -> bool:
	return not Network.is_in_room() or Network.is_host()


func _refresh_players() -> void:
	var ids: Array = Network.players.keys() if Network.is_in_room() else [1]
	roles = CrewRoles.assign(ids)
	for id in cursors.keys():
		if not roles.has(id):
			cursors.erase(id)
	for id in ready_by.keys():
		if not roles.has(id):
			ready_by.erase(id)


# --- input -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_message_time = maxf(_message_time - delta, 0.0)
	if not _launching and not Tutorial.is_blocking():
		_handle_input()
	_send_cursor(delta)
	_preview.highlight = _item_at(cursors.get(_me, Vector2i.ZERO))
	queue_redraw()


func _handle_input() -> void:
	var c: Vector2i = cursors.get(_me, Vector2i.ZERO)
	var moved := c
	if _pressed("up"):
		moved.y -= 1
	if _pressed("down"):
		moved.y += 1
	if _pressed("left") or _pressed("right"):
		moved.x = _next_column(c.x, -1 if _pressed("left") else 1)
	moved.y = clampi(moved.y, 0, _column_items(moved.x).size() - 1)
	if moved != c:
		cursors[_me] = moved
		Sfx.play("ui_hover")
	if _pressed("interact"):
		_use(_item_at(moved))


func _pressed(verb: String) -> bool:
	return Input.is_action_just_pressed(Controls.action("p1", verb))


func _next_column(from: int, step: int) -> int:
	var col := from
	for i in COLUMNS.size():
		col = wrapi(col + step, 0, COLUMNS.size())
		if _can_use_column(_me, col):
			return col
	return from


func _can_use_column(peer: int, col: int) -> bool:
	return col == 0 or CrewRoles.has(roles.get(peer, "all"), COLUMNS[col].id)


func _column_items(col: int) -> Array:
	if col == 0:
		return ["class:light", "class:balanced", "class:heavy", "orbit", "ready"]
	return DesignRules.upgrades_for_role(COLUMNS[col].id)


func _item_at(c: Vector2i) -> String:
	var items := _column_items(c.x)
	return items[c.y] if c.y >= 0 and c.y < items.size() else ""


## SPACE on an item: checked locally first for instant feedback, then sent to the host.
func _use(item: String) -> void:
	if item == "":
		return
	var action := {}
	if item == "ready":
		var errors: Array = DesignRules.evaluate(design).errors
		if errors and not ready_by.get(_me, false):
			_say(errors[0])
			Sfx.play("denied")
			return
		action = {type = "ready"}
		Sfx.play("ui_click")
	elif item.begins_with("class:"):
		action = {type = "class", id = item.trim_prefix("class:")}
		Sfx.play("toggle")
	elif item == "orbit":
		action = {type = "orbit", id = Orbits.next_id(Orbits.id_of(design))}
		Sfx.play("toggle")
	else:
		var reason := DesignRules.check_add(design, item)
		if reason != "":
			_say(reason)
			Sfx.play("denied")
			return
		action = {type = "toggle", part = item}
		Sfx.play("toggle")
	if _is_host():
		_host_apply(_me, action)
	else:
		_request.rpc_id(1, action)


func _say(text: String) -> void:
	_message = text
	_message_time = 2.0


# --- host logic ------------------------------------------------------------------------

func _host_apply(peer: int, action: Dictionary) -> void:
	var new_design := design
	var new_ready := ready_by.duplicate()
	match action.get("type", ""):
		"toggle":
			var part := str(action.get("part", ""))
			var col := COLUMNS.map(func(c: Dictionary) -> String: return c.id).find(DesignRules.part(part).get("role", ""))
			if col > 0 and _can_use_column(peer, col):
				new_design = DesignRules.toggle(design, part)
		"class":
			if str(action.get("id", "")) in DesignRules.class_ids():
				new_design = DesignRules.set_class(design, action.id)
		"orbit":
			new_design = DesignRules.set_orbit(design, str(action.get("id", "")))
		"ready":
			if new_ready.get(peer, false):
				new_ready.erase(peer)
			elif DesignRules.evaluate(design).errors.is_empty():
				new_ready[peer] = true
	if new_design != design:
		new_ready = {}  # the ship changed: everyone has to look again
	_apply_design(new_design, new_ready)
	if Network.is_in_room():
		for id: int in _ready_peers:
			_recv_design.rpc_id(id, design, ready_by)
	_check_launch()


func _check_launch() -> void:
	if _launching or not _is_host():
		return
	for id in roles:
		if not ready_by.get(id, false):
			return
	if Network.is_in_room():
		_launch.rpc(design)
	else:
		_launch(design)


func _apply_design(new_design: Dictionary, new_ready: Dictionary) -> void:
	design = new_design
	ready_by = new_ready
	_preview.design = design


func _on_room_changed() -> void:
	_refresh_players()
	if _is_host():
		_check_launch()


# --- network ---------------------------------------------------------------------------

func _send_cursor(delta: float) -> void:
	if not Network.is_in_room():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = CURSOR_SEND
	var c: Vector2i = cursors.get(_me, Vector2i.ZERO)
	if Network.is_host():
		for id: int in _ready_peers:
			_cursor_from_host.rpc_id(id, 1, c)
	else:
		_cursor_to_host.rpc_id(1, c)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if Network.is_host():
		var id := multiplayer.get_remote_sender_id()
		_ready_peers[id] = true
		_recv_design.rpc_id(id, design, ready_by)


@rpc("any_peer", "call_remote", "reliable")
func _request(action: Dictionary) -> void:
	if Network.is_host():
		_host_apply(multiplayer.get_remote_sender_id(), action)


@rpc("authority", "call_remote", "reliable")
func _recv_design(new_design: Dictionary, new_ready: Dictionary) -> void:
	_apply_design(new_design, new_ready)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _cursor_to_host(c: Vector2i) -> void:
	if not Network.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	cursors[sender] = c
	for id: int in _ready_peers:
		if id != sender:
			_cursor_from_host.rpc_id(id, sender, c)


@rpc("authority", "call_remote", "unreliable_ordered")
func _cursor_from_host(peer: int, c: Vector2i) -> void:
	if peer != _me:
		cursors[peer] = c


@rpc("authority", "call_local", "reliable")
func _launch(final_design: Dictionary) -> void:
	if _launching:
		return
	_launching = true
	DesignRules.chosen = final_design.duplicate(true)
	Sfx.play("burn")
	_say("ALL READY - LAUNCHING")
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file(LAUNCH_SCENE)


# --- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG)
	for s in _stars:
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(0.8, 0.85, 1.0, 0.25 + 0.4 * maxf(sin(_time * 1.3 + s.z), 0.0)))
	var title := "DESIGN YOUR SPACECRAFT"
	UiKit.text(self, Vector2(8, 12), title, 9, Color.WHITE, 2)
	var level_title := (Network.level.title if Network.is_in_room() and Network.level else "MARS").to_upper()
	_text_right(Vector2(472, 11), "MISSION: " + level_title + "   H: HELP", DIM)

	_panel(Rect2(6, 16, 164, 132))
	var ev := DesignRules.evaluate(design)
	_draw_stats(Rect2(174, 16, 128, 132), ev)
	_draw_detail(Rect2(306, 16, 168, 132))
	_draw_catalog(ev)
	_draw_footer(ev)


func _draw_stats(r: Rect2, ev: Dictionary) -> void:
	_panel(r)
	var x := r.position.x + 5
	var y := r.position.y + 11
	var w := r.size.x - 10
	var cls := DesignRules.class_info(design.ship_class)
	_text(Vector2(x, y), "SHIP: %s" % str(cls.get("name", "")).to_upper(), Color.WHITE)
	y += 14
	_text(Vector2(x, y), "MASS %d / %d KG" % [ev.mass, ev.mass_limit], DIM)
	_bar(Rect2(x, y + 3, w, 4), ev.mass / maxf(ev.mass_limit, 1.0), Color("4fd8ff"))
	y += 16
	var net: float = ev.net_w
	_text(Vector2(x, y), "POWER %s%d W" % ["+" if net >= 0 else "", net], GOOD if net >= 0 else BAD)
	y += 9
	_text(Vector2(x, y), "MAKES %d  USES %d" % [ev.gen_w, ev.draw_w], DIM)
	y += 14
	var left: float = ev.budget - ev.cost
	_text(Vector2(x, y), "BUDGET $%dM LEFT" % left, Color.WHITE if left >= 0 else BAD)
	_bar(Rect2(x, y + 3, w, 4), ev.cost / maxf(ev.budget, 1.0), Color("ffc640"))
	y += 16
	_text(Vector2(x, y), "SLOTS %d / %d" % [ev.slots_used, ev.slots], Color.WHITE)
	for i in ev.slots:
		UiKit.chip(self, Rect2(x + 64 + i * 7, y - 7, 6, 6), Color.WHITE if i < ev.slots_used else UiKit.WELL)
	y += 14
	var launcher: Dictionary = ev.launcher
	if launcher.is_empty():
		_text(Vector2(x, y), "ROCKET: NONE CAN LIFT", BAD)
	else:
		_text(Vector2(x, y), "ROCKET: %s" % str(launcher.name).to_upper(), Color.WHITE)
		y += 9
		var usable := float(launcher.capacity_kg) * DesignRules.LIFT_MARGIN
		_text(Vector2(x, y), "MARGIN %d%%  $%dM" % [roundi((1.0 - ev.mass / float(launcher.capacity_kg)) * 100.0), launcher.cost],
				Color("ffc640") if ev.mass > usable * 0.95 else DIM)
	if Missions.current_id() != "":   # campaign: the cruise ends with the Mars brake burn
		y += 11
		_text(Vector2(x, y), "MARS BRAKE: %d%% FUEL" % ceili(Orbits.moi_fuel(design)), Color("4fd8ff"))


## Details of whatever the local cursor is on.
func _draw_detail(r: Rect2) -> void:
	_panel(r)
	var x := r.position.x + 5
	var y := r.position.y + 11
	var item := _item_at(cursors.get(_me, Vector2i.ZERO))
	var width := r.size.x - 10
	if item.begins_with("class:"):
		var id := item.trim_prefix("class:")
		var cls := DesignRules.class_info(id)
		_text(Vector2(x, y), "%s SHIP" % str(cls.get("name", "")).to_upper(), Color.WHITE)
		y += 13
		for line in ["UPGRADE SLOTS: %d" % cls.get("upgrade_slots", 0),
				"EMPTY MASS: %d KG" % cls.get("dry_mass_kg", 0),
				"MASS LIMIT: %d KG" % cls.get("mass_limit_kg", 0),
				"PRICE: $%dM" % cls.get("cost", 0)]:
			_text(Vector2(x, y), line, DIM)
			y += 10
		y = _wrapped(Vector2(x, y + 4), CLASS_HINTS.get(id, ""), width, Color.WHITE)
		var status := "SELECTED" if design.ship_class == id else "SPACE: SWITCH"
		_text(Vector2(x, r.end.y - 6), status, GOOD if design.ship_class == id else DIM)
	elif item == "orbit":
		_draw_orbit_detail(r)
	elif item == "ready":
		_text(Vector2(x, y), "READY TO LAUNCH?", Color.WHITE)
		y = _wrapped(Vector2(x, y + 13), "Launch when every crew member is READY. Any change to the ship un-readies everyone.", width, DIM)
		var errors: Array = DesignRules.evaluate(design).errors
		for e: String in errors:
			y = _wrapped(Vector2(x, y + 4), e, width, BAD)
	elif item != "":
		var p := DesignRules.part(item)
		var icon := DesignRules.texture(p.dir + p.get("icon", ""))
		if icon:
			draw_texture(icon, Vector2(x, y - 6))
		var name_y := _wrapped(Vector2(x + 36, y), str(p.get("name", item)), width - 36, Color.WHITE)
		_text(Vector2(x + 36, maxf(name_y, y + 10) + 1), CrewRoles.tag(p.get("role", "")),
				CrewRoles.color(p.get("role", "")))
		y += 32
		var w := int(p.get("power_w", 0))
		_text(Vector2(x, y), "+%d KG" % p.get("mass_kg", 0), Color("4fd8ff"))
		_text(Vector2(x + 50, y), "%s%d W" % ["+" if w >= 0 else "", w], GOOD if w >= 0 else BAD)
		_text(Vector2(x + 104, y), "$%dM" % p.get("cost", 0), Color("ffc640"))
		y = _wrapped(Vector2(x, y + 12), str(p.get("desc", "")), width, DIM)
		var status := ""
		var col := DIM
		if item in design.upgrades:
			status = "FITTED - SPACE: REMOVE"
			col = GOOD
		else:
			status = DesignRules.check_add(design, item)
			col = BAD
			if status == "":
				status = "SPACE: ADD"
				col = Color.WHITE
		if not _can_use_column(_me, cursors.get(_me, Vector2i.ZERO).x):
			status = "NOT YOUR STATION"
			col = DIM
		_text(Vector2(x, r.end.y - 6), status, col)


## The Mars orbit card: what the brake costs THIS design, what the orbit gives, the trade-off.
func _draw_orbit_detail(r: Rect2) -> void:
	var x := r.position.x + 5
	var y := r.position.y + 11
	var width := r.size.x - 10
	var id := Orbits.id_of(design)
	var o := Orbits.info(id)
	_text(Vector2(x, y), "MARS ORBIT: %s" % str(o.get("name", "")), Color.WHITE)
	y += 10
	_text(Vector2(x, y), str(o.get("shape", "")), DIM)
	y += 12
	_text(Vector2(x, y), "BRAKE AT MARS: %d%% OF THE TANK" % ceili(Orbits.moi_fuel(design)), Color("4fd8ff"))
	y += 10
	_text(Vector2(x, y), "SCIENCE x%s  EARTH CONTACT x%s" % [str(o.get("science_mult", 1)), str(o.get("contact_mult", 1))], DIM)
	y += 10
	var delay := Orbits.delay_years(design)
	var life := "DRAG %d%% FUEL / MARS YEAR" % int(o.get("drag", 0))
	if delay > 0.0:
		life += "  WAIT %d MO" % roundi(delay * Orbits.MONTHS_PER_YEAR)
	_text(Vector2(x, y), life, DIM)
	if Orbits.favoured(id):
		y += 10
		_text(Vector2(x, y), "SUITS THIS MISSION: +%d%% SCIENCE" % roundi((Orbits.FAVOURED - 1.0) * 100.0), GOOD)
	_wrapped(Vector2(x, y + 12), str(o.get("desc", "")), width, DIM)
	_text(Vector2(x, r.end.y - 6), "SPACE: NEXT ORBIT (SIMPLIFIED)", Color.WHITE)


func _draw_catalog(ev: Dictionary) -> void:
	for col in COLUMNS.size():
		var x := 4 + col * COL_W
		var r := Rect2(x, CATALOG_Y, COL_W - 3, 90)
		var role_id: String = COLUMNS[col].id
		var mine := _can_use_column(_me, col)
		var accent := Color.WHITE if col == 0 else CrewRoles.color(role_id)
		_panel(r, accent if mine else LINE)
		_text(Vector2(x + 4, CATALOG_Y + 9), COLUMNS[col].title, accent if mine else DIM)
		var items := _column_items(col)
		for row in items.size():
			var item: String = items[row]
			var y := CATALOG_Y + 21 + row * ROW_H
			_draw_item(item, Vector2(x + 4, y), mine, accent)
	# Cursors on top: remote first, local last.
	var order := cursors.keys()
	order.erase(_me)
	order.append(_me)
	var stack := {}
	for peer in order:
		if not cursors.has(peer):
			continue
		var c: Vector2i = cursors[peer]
		var inset: int = stack.get(c, 0)
		stack[c] = inset + 1
		var rect := Rect2(4 + c.x * COL_W + 1 + inset, CATALOG_Y + 13 + c.y * ROW_H + inset,
				COL_W - 5 - inset * 2, ROW_H - inset * 2)
		var color := CrewRoles.color(roles.get(peer, "all"))
		if peer == _me:
			# Your cursor: chunky 2 px frame that nudges in and out.
			var g := rect.grow(1.0 if fmod(_time, 0.5) < 0.25 else 0.0)
			_frame_rect(g, Color.WHITE, 2)
		else:
			_frame_rect(rect, color, 1)
			var tag := "P%d" % (_player_index(peer) + 1)
			var tw := UiKit.text_w(tag, 6) + 4
			var tr := Rect2(rect.end.x - tw, rect.position.y - 3, tw, 8)
			UiKit.chip(self, tr, color)
			UiKit.text(self, Vector2(tr.position.x + 2, tr.end.y - 1), tag, 6, UiKit.INK, 0)


func _draw_item(item: String, at: Vector2, usable: bool, accent: Color) -> void:
	var on := false
	var label := ""
	var possible := true
	if item.begins_with("class:"):
		var id := item.trim_prefix("class:")
		on = design.ship_class == id
		label = str(DesignRules.class_info(id).get("name", id))
	elif item == "orbit":
		on = true
		label = "Orbit: " + str(Orbits.info(Orbits.id_of(design)).get("short", ""))
	elif item == "ready":
		on = ready_by.get(_me, false)
		label = "READY" if not on else "READY!"
		possible = DesignRules.evaluate(design).errors.is_empty() or on
	else:
		on = item in design.upgrades
		label = SHORT_NAMES.get(item, item)
		possible = on or DesignRules.check_add(design, item) == ""
	var box := Rect2(at + Vector2(0, -6), Vector2(6, 6))
	if on:
		UiKit.chip(self, box, accent)
	else:
		UiKit.chip(self, box, UiKit.WELL)
		draw_rect(Rect2(box.position + Vector2(1, 1), Vector2(4, 1)), Color(accent if usable else DIM, 0.6))
	var color := Color.WHITE if usable and possible else DIM
	if item == "ready" and on:
		color = GOOD
	_text(at + Vector2(9, 0), UiKit.fit(label, FONT_SIZE, COL_W - 20), color)


func _draw_footer(ev: Dictionary) -> void:
	var y := 253
	if _message_time > 0.0:
		_text(Vector2(8, y), _message, BAD if not _launching else GOOD)
	elif not ev.errors.is_empty():
		_text(Vector2(8, y), "! " + str(ev.errors[0]), BAD)
	else:
		_text(Vector2(8, y), "SHIP OK - EVERYONE PRESS READY", GOOD)
	# One chip per player: role colour, green when READY.
	var ids := roles.keys()
	ids.sort()
	var x := 6.0
	var h := maxf(11.0, UiKit.line_h(7) + 3)
	for i in ids.size():
		var id: int = ids[i]
		var ready: bool = ready_by.get(id, false)
		var text := "P%d %s %s" % [i + 1, CrewRoles.tag(roles[id]), "READY" if ready else "NOT READY"]
		var col := CrewRoles.color(roles[id])
		var w := UiKit.text_w(text, 7) + 10
		var r := Rect2(x, 268 - h, roundf(w), h)
		UiKit.panel(self, r, Color("123320") if ready else UiKit.PANEL, GOOD if ready else col)
		UiKit.chip(self, Rect2(r.position.x + 2, r.position.y + 2, 3, h - 4), GOOD if ready else col)
		UiKit.text(self, Vector2(r.position.x + 7, r.end.y - 3), text, 7, GOOD if ready else Color.WHITE, 0)
		if id == _me:  # small arrow over your own chip
			var cx := roundf(r.get_center().x)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 2, r.position.y - 4), Vector2(cx + 3, r.position.y - 4),
					Vector2(cx + 0.5, r.position.y - 1)]), Color.WHITE)
		x = r.end.x + 4
	# Controls as key caps, bottom right.
	var keys := [["WASD", "MOVE"], ["SPACE", "PICK"], ["ESC", "MENU"]]
	var kx := 474.0
	for j in range(keys.size() - 1, -1, -1):
		var label: String = keys[j][1]
		var lw := UiKit.text_w(label, 6)
		UiKit.text(self, Vector2(kx - lw, 266), label, 6, DIM, 0)
		var cap := UiKit.keycap_size(keys[j][0], 6)
		UiKit.keycap(self, Vector2(kx - lw - 2 - cap.x, 266 - cap.y + 2), keys[j][0], 6)
		kx -= lw + 2 + cap.x + 6


func _player_index(peer: int) -> int:
	var ids := roles.keys()
	ids.sort()
	return ids.find(peer)


# --- tiny drawing helpers (UI kit) -----------------------------------------------------

func _panel(r: Rect2, border := LINE) -> void:
	UiKit.panel(self, r, PANEL, border if border != LINE else Color(0, 0, 0, 0))


## Segmented bar; over 100% the whole bar turns red.
func _bar(r: Rect2, fill: float, color: Color) -> void:
	var over := fill > 1.0
	var segs := maxi(int(r.size.x / 6.0), 4)
	UiKit.seg_bar(self, Rect2(r.position.x, r.position.y - 1, r.size.x, 6), clampf(fill, 0.0, 1.0),
			BAD if over else color, segs)


func _frame_rect(r: Rect2, col: Color, width: int) -> void:
	r = Rect2(r.position.round(), r.size.round())
	draw_rect(Rect2(r.position, Vector2(r.size.x, width)), col)
	draw_rect(Rect2(r.position.x, r.end.y - width, r.size.x, width), col)
	draw_rect(Rect2(r.position, Vector2(width, r.size.y)), col)
	draw_rect(Rect2(r.end.x - width, r.position.y, width, r.size.y), col)


func _text(pos: Vector2, text: String, color: Color) -> void:
	UiKit.text(self, pos, text, FONT_SIZE, color, 0)


func _text_right(pos: Vector2, text: String, color: Color) -> void:
	UiKit.text_r(self, pos.x, pos.y, text, FONT_SIZE, color, 0)


## Word-wrapped text; returns the y below the last line.
func _wrapped(pos: Vector2, text: String, width: float, color: Color) -> float:
	var y := pos.y
	var lh := maxf(9.0, UiKit.line_h(FONT_SIZE) - 1)
	for line in UiKit.wrap(text, FONT_SIZE, width):
		if line != "":
			_text(Vector2(pos.x, y), line, color)
			y += lh
	return y
