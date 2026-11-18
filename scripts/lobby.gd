extends Control
## Room screen (lobby): code / address for friends, the crew and the flight start.
## The host has START FLIGHT; everyone else waits for it.
## Drawn on the UI kit (UiKit + MenuKit) at 480x270 (PixelMode): mission card, room code tiles (or
## the LAN address + the ONLINE / LOCAL IP switch while alone), four role-coloured crew slots (roles as
## the flight will hand them out, CrewRoles), status line, chunky START / LEAVE buttons, keycap hints.
## Root draws the backdrop + stars (they streak in the hyperspace jump); Content draws the UI so it can fade.

@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
## Where the player goes if the room is lost.
@export_file("*.tscn") var join_scene: String = "res://scenes/join_room.tscn"

const ACCENT := Color("4fd8ff")
const HOST_COLOR := Color("ffd34a")
const ME_COLOR := Color("4fd8ff")
const CARD := Rect2(8, 42, 132, 190)
const CODE_PANEL := Rect2(148, 42, 324, 66)
const CREW_Y := 116.0
const SLOT_W := 78.0
const SLOT_H := 70.0
const START_RECT := Rect2(330, 212, 142, 24)
const LEAVE_RECT := Rect2(388, 8, 84, 20)
const MODE_RECT := Rect2(358, 84, 108, 18)
const ROLE_NAMES := {navigator = "NAVIGATOR", engineer = "ENGINEER", comms = "COMMS", scientist = "SCIENTIST", all = "ALL STATIONS"}

@onready var _content: Control = $Content
@onready var _fade: ColorRect = $Fade

var _busy := false
## 0..1: stars stretch into streaks (hyperspace jump when the flight starts).
var warp := 0.0
var _time := 0.0
var _stars: Array = []
var _juice := UiJuice.new()
var _saved_window := {}
var _notice := ""
var _notice_t := 0.0
var _focus := "start"    # keyboard focus: "start" / "mode" / "leave"
var _hot := ""           # button under the mouse
var _known_ids: Array = []
var _code_seen := ""
var _addresses := PackedStringArray()


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	UiFont.max_level = 2


func _ready() -> void:
	if not Network.is_in_room():
		# Opened without a room (e.g. the scene was run from the editor).
		get_tree().change_scene_to_file.call_deferred(menu_scene)
		return
	UiKit.setup_canvas(self)
	UiKit.setup_canvas(_content)
	_stars = MenuKit.make_stars(70, 33)
	_content.draw.connect(_draw_content)
	Network.room_changed.connect(_refresh)
	Network.room_closed.connect(_on_room_closed)
	Network.game_started.connect(_on_game_started)
	_focus = "start" if Network.is_host() else "leave"
	_refresh()
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)


func _process(delta: float) -> void:
	_time += delta
	_juice.step(delta)
	if _notice_t > 0.0:
		_notice_t -= delta
	queue_redraw()
	_content.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_cancel"):
		_leave()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_press(_focus)
			KEY_A, KEY_LEFT, KEY_W, KEY_UP:
				_move_focus(-1)
			KEY_D, KEY_RIGHT, KEY_S, KEY_DOWN, KEY_TAB:
				_move_focus(1)


func _gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseMotion:
		var hot := _button_at(get_local_mouse_position())
		if hot != "" and hot != _hot:
			_focus = hot
			Sfx.play("ui_hover")
		_hot = hot
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _button_at(get_local_mouse_position())
		if hit != "":
			_focus = hit
			_press(hit)


func _buttons() -> Array:
	var out := []
	if Network.is_host():
		out.append("start")
		if _mode_visible():
			out.append("mode")
	out.append("leave")
	return out


func _button_rect(id: String) -> Rect2:
	match id:
		"start":
			return START_RECT
		"mode":
			return MODE_RECT
	return LEAVE_RECT


func _button_at(p: Vector2) -> String:
	for id: String in _buttons():
		if _button_rect(id).has_point(p):
			return id
	return ""


func _move_focus(step: int) -> void:
	var list := _buttons()
	var i := list.find(_focus)
	_focus = list[wrapi(i + step, 0, list.size())]
	Sfx.play("ui_hover")


func _press(id: String) -> void:
	if not id in _buttons():
		return
	_juice.kick("press_" + id, 0.15)
	match id:
		"start":
			_on_start_pressed()
		"mode":
			_toggle_mode()
		"leave":
			_leave()


func _mode_visible() -> bool:
	# The mode can change only while the host is alone (otherwise everyone would drop).
	return Network.is_host() and Network.players.size() <= 1 and not OS.has_feature("web")   # no LAN in a browser


func _toggle_mode() -> void:
	if _busy or Network.players.size() > 1:
		return
	Sfx.play("toggle")
	if Network.set_online(not Network.online) != OK:
		_show_notice("Port %d is used by another program - staying online." % Network.DEFAULT_PORT)
	_refresh()


func _refresh() -> void:
	if not Network.is_in_room():
		return
	var ids := Network.players.keys()
	ids.sort()
	for id: int in ids:
		if not id in _known_ids and not _known_ids.is_empty():
			_juice.kick("slot_%d" % id, 0.45)
			Sfx.play("toggle")
	_known_ids = ids
	if Network.room_code != _code_seen:
		_code_seen = Network.room_code
		if _code_seen != "":
			_juice.kick("code", 0.6)
	if Network.is_host() and not Network.is_online_room():
		_addresses = Network.get_local_addresses()
	if not _focus in _buttons():
		_focus = _buttons()[0]


func _on_start_pressed() -> void:
	if not _busy:
		Network.start_game()


func _on_game_started() -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var title := Network.level.title
	var scene := Network.level.scene
	var has_scene := not scene.is_empty() and ResourceLoader.exists(scene)

	# Hyperspace jump: the UI fades, the stars stretch into streaks.
	var jump := create_tween().set_parallel(true)
	jump.tween_property(_content, "modulate:a", 0.0, 0.5)
	jump.tween_property(self, "warp", 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if has_scene:
		jump.chain().tween_property(_fade, "color:a", 1.0, 0.5)
		await jump.finished
		get_tree().change_scene_to_file(scene)
		return

	await jump.finished
	push_warning("Lobby: level \"%s\" has no scene - set it in the Scene field." % title)
	var back := create_tween().set_parallel(true)
	back.tween_property(self, "warp", 0.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	back.tween_property(_content, "modulate:a", 1.0, 0.5).set_delay(0.6)
	await back.finished
	_busy = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Network.set_room_open(true)
	_show_notice("The level scene for \"%s\" is not connected yet" % title)


func _on_room_closed(_reason: String) -> void:
	# The JOIN screen shows the reason (Network.pending_message).
	_busy = false
	_go_to(join_scene)


func _leave() -> void:
	if _busy:
		return
	Network.leave_room()
	_go_to(menu_scene)


func _show_notice(text: String) -> void:
	_notice = text
	_notice_t = 4.0
	Sfx.play("denied")


func _go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	MenuKit.backdrop(self, "high_right")
	MenuKit.stars(self, _stars, _time, warp)


func _draw_content() -> void:
	if not Network.is_in_room() and not _busy:
		return
	var c := _content
	var host := Network.is_host()
	var sub := "YOU ARE IN THE ROOM"
	if host:
		sub = "FRIENDS JOIN WITH THE ROOM CODE - FROM ANYWHERE" if Network.is_online_room() \
				else "FRIENDS JOIN WITH THE ADDRESS BELOW (SAME NETWORK)"
	MenuKit.title(c, Vector2(8, 6), "CREW ROOM", sub, ACCENT, "team")
	MenuKit.button(c, LEAVE_RECT, "CLOSE ROOM" if host else "LEAVE", UiKit.BAD.lightened(0.15),
			_focus == "leave", true, 8, "", _juice.k("press_leave"))
	_draw_card(c)
	if host:
		_draw_code(c)
	else:
		_draw_waiting(c)
	_draw_crew(c)
	_draw_status(c)
	var keys := [["ENTER", "START FLIGHT"], ["A/D", "CHOOSE"], ["ESC", "CLOSE ROOM"]] if host \
			else [["ESC", "LEAVE ROOM"]]
	MenuKit.key_hints(c, 240 if not host else 160, 250, keys, 6)
	# Build fingerprint (networked code only): host and friends must show the same one to play together.
	UiKit.text_r(c, 474, 266, "BUILD " + Network.build_version().to_upper(), 6, UiKit.FAINT, 0)
	if _notice != "" and _notice_t > 0.0:
		MenuKit.toast(c, 240, 244, _notice, UiKit.WARN, clampf(_notice_t * 4.0, 0.0, 1.0))


## The level / mission card on the left.
func _draw_card(c: Control) -> void:
	var level := Network.level
	if level == null:
		return
	var mission: Dictionary = Missions.mission(level.mission) if level.mission != "" else {}
	var accent: Color = Color(str(mission.accent)) if mission.has("accent") else level.accent_color
	UiKit.frame(c, CARD, accent, UiKit.PANEL)
	var head := "LEVEL %d" % Network.level_number
	var year := ""
	if level.mission == Missions.SANDBOX:
		head = "MARS · SANDBOX"
	elif not mission.is_empty():
		head = "MARS · MISSION %d" % int(mission.number)
		year = str(int(mission.year))
	var strip := Rect2(CARD.position.x + 4, CARD.position.y + 4, CARD.size.x - 8, 13)
	c.draw_rect(strip, accent.darkened(0.55))
	c.draw_rect(Rect2(strip.position.x, strip.end.y, strip.size.x, 1), UiKit.INK)
	UiKit.text(c, Vector2(strip.position.x + 3, strip.end.y - 3), head, 7, accent, 0)
	var right := strip.end.x - 3
	if level.has_missions or level.mission != "":   # difficulty (synced with the room), right of the year
		var diff := str(Missions.difficulty().get("name", ""))
		UiKit.text_r(c, right, strip.end.y - 3, diff, 7, MissionSelect.DIFF_COLORS.get(Missions.difficulty_id(), UiKit.TEXT), 0)
		right -= UiFont.width(diff, 7) + 5
	if year != "":
		UiKit.text_r(c, right, strip.end.y - 3, year, 7, UiKit.TEXT, 0)
	# Planet with a little ship on a dotted orbit.
	var center := Vector2(roundf(CARD.get_center().x), CARD.position.y + 44)
	var radius := 18
	var tex: Texture2D
	if level.has_missions or not mission.is_empty():
		tex = MenuKit.mars_tex(radius)
	else:
		var a := level.planet_color_a
		var b := level.planet_color_b
		tex = MenuKit.planet_tex(radius, [b.lightened(0.15), b, a, a.darkened(0.6)], Network.level_number, false)
	var ang := _time * 0.9
	_orbit(c, center, accent, ang, false, radius)
	c.draw_texture(tex, center - Vector2(radius, radius))
	_orbit(c, center, accent, ang, true, radius)
	var y := CARD.position.y + 82
	var title := str(mission.get("title", level.title)).to_upper()
	var size := 10
	while size > 7 and UiKit.text_w(title, size) > CARD.size.x - 10:
		size -= 1
	UiKit.text_c(c, CARD.get_center().x, y, title, size, UiKit.TEXT, 2)
	if mission.has("nasa") and level.mission != Missions.SANDBOX:
		y += 9
		var nasa := "NASA: " + str(mission.nasa)
		UiKit.text_c(c, CARD.get_center().x, y, UiKit.fit(nasa, 6, CARD.size.x - 10), 6, accent, 0)
	y += 4
	var body := str(mission.get("tagline", level.description))
	for line in UiKit.wrap(body, 6, CARD.size.x - 14).slice(0, 5):
		y += UiKit.line_h(6)
		UiKit.text(c, Vector2(CARD.position.x + 7, y), line, 6, Color("d8deee"), 0)
	# Goals (campaign) or the hazards switched on (sandbox) as chips.
	var chips: Array = []
	var chip_col := UiKit.GOOD
	var label := "GOALS"
	if level.mission == Missions.SANDBOX:
		label = "HAZARDS ON"
		chip_col = UiKit.WARN
		var opts: Dictionary = level.options if not level.options.is_empty() else Missions.offline_options
		for key: String in MissionSelect.SANDBOX_KEYS:
			if bool(opts.get(key, key != "hull")):
				chips.append([str(MissionSelect.SANDBOX_NAMES[key]).replace("CONJUNCTION", "CONJ."), MissionSelect.SANDBOX_ICONS[key]])
	else:
		for g: Dictionary in mission.get("goals", []):
			chips.append(_goal_chip(g))
	if chips.is_empty():
		return
	y = maxf(y + 6, CARD.end.y - 44)
	UiKit.text(c, Vector2(CARD.position.x + 7, y + 4), label, 5, UiKit.FAINT.lightened(0.25), 0)
	var x := CARD.position.x + 6
	y += 6
	for chip: Array in chips:
		var w := MenuKit.tag_w(chip[0], chip[1], 5)
		if x + w > CARD.end.x - 6 and x > CARD.position.x + 6:
			x = CARD.position.x + 6
			y += 11
		MenuKit.tag(c, Vector2(x, y), chip[0], chip_col, chip[1], 5)
		x += w + 2


func _goal_chip(g: Dictionary) -> Array:
	var target := int(g.get("target", 0))
	match str(g.get("kind", "")):
		"storms_recorded":
			return ["STORM x%d" % target, "power"]
		"science_sent":
			return ["SEND %d" % target, "sent"]
		"science_lost_max":
			return ["LOSE <%d" % target, "lost"]
		"orbit":
			return ["ORBIT", "mars"]
	return [str(g.get("kind", "?")).to_upper(), ""]


func _orbit(c: Control, center: Vector2, accent: Color, a: float, front: bool, radius: int) -> void:
	var rx := radius + 14.0
	var ry := 8.0
	for k in 36:
		var t := k * TAU / 36.0
		if (sin(t) > 0.0) != front:
			continue
		c.draw_rect(Rect2((center + Vector2(cos(t) * rx, sin(t) * ry)).round(), Vector2(1, 1)), Color(accent, 0.5))
	if (sin(a) > 0.0) == front:
		var p := (center + Vector2(cos(a) * rx, sin(a) * ry)).round()
		c.draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), UiKit.INK)
		c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
		c.draw_rect(Rect2(p + Vector2(-5, 0), Vector2(3, 1)), accent)
		c.draw_rect(Rect2(p + Vector2(3, 0), Vector2(3, 1)), accent)


## Host: the room code as four letter tiles (online) or the LAN address, plus the mode switch.
func _draw_code(c: Control) -> void:
	var r := CODE_PANEL
	var online := Network.is_online_room()
	UiKit.panel(c, r, UiKit.PANEL_DARK, ACCENT if online else Color("ff9a3c"))
	var hint := ""
	var text_x := r.position.x + 8
	if online:
		UiKit.text(c, Vector2(r.position.x + 8, r.position.y + 11), "ROOM CODE", 6, ACCENT, 0)
		var code := Network.room_code
		for i in 4:
			var tile := Rect2(r.position.x + 8 + i * 25, r.position.y + 16, 22, 26)
			var k := clampf(_juice.k("code") * 1.6 - i * 0.15, 0.0, 1.0)
			tile.position.y += -roundf(5.0 * sin(k * PI))
			if code == "":
				UiKit.panel(c, tile, UiKit.WELL)
				if fmod(_time * 2.0 + i * 0.25, 1.0) < 0.5:
					UiKit.text_c(c, tile.get_center().x, tile.end.y - 7, "?", 14, UiKit.FAINT, 0)
			else:
				UiKit.panel(c, tile, Color("eef1fb"))
				c.draw_rect(Rect2(tile.position.x + 1, tile.end.y - 3, tile.size.x - 2, 2), UiKit.KEY_SIDE)
				UiKit.text_c(c, tile.get_center().x, tile.end.y - 7, code.substr(i, 1), 16, UiKit.INK, 0)
		text_x = r.position.x + 8 + 4 * 25 + 6
		hint = "Getting a code from the server" + ".".repeat(1 + int(_time * 3.0) % 3) if code == "" \
				else "Friends type it in JOIN. Play goes over the internet."
		var chip := MenuKit.tag(c, Vector2(r.position.x + 8, r.end.y - 14), "ONLINE", ACCENT, "earth", 5, true)
		UiKit.text(c, Vector2(chip.end.x + 4, chip.end.y - 3), "relay server", 5, UiKit.DIM, 0)
	else:
		UiKit.text(c, Vector2(r.position.x + 8, r.position.y + 11), "ROOM ADDRESS", 6, Color("ff9a3c"), 0)
		var address := _addresses[0] if not _addresses.is_empty() else "NO NETWORK"
		UiKit.text(c, Vector2(r.position.x + 8, r.position.y + 33), address, 16, UiKit.TEXT, 3)
		text_x = r.position.x + 8 + minf(UiKit.text_w(address, 16) + 10, 150)
		if _addresses.is_empty():
			hint = "This computer is not on a network - friends can't get in."
		else:
			hint = "Friends type it in JOIN. Port %d." % Network.DEFAULT_PORT
			if _addresses.size() > 1:
				hint += " Also: " + ", ".join(_addresses.slice(1))
		var chip := MenuKit.tag(c, Vector2(r.position.x + 8, r.end.y - 14), "LOCAL IP", Color("ff9a3c"), "dsn", 5, true)
		UiKit.text(c, Vector2(chip.end.x + 4, chip.end.y - 3), "same Wi-Fi / LAN", 5, UiKit.DIM, 0)
	var hy := r.position.y + 12
	var hint_w := r.end.x - 8 - text_x
	for line in UiKit.wrap(hint, 6, hint_w).slice(0, 4 if not _mode_visible() else 3):
		UiKit.text(c, Vector2(text_x, hy), line, 6, UiKit.TEXT.darkened(0.1), 0)
		hy += UiKit.line_h(6)
	if _mode_visible():
		var label := "PLAY ON LAN (IP)" if online else "PLAY ONLINE (CODE)"
		MenuKit.button(c, MODE_RECT, label, Color("ff9a3c") if online else ACCENT, _focus == "mode", true, 6,
				"", _juice.k("press_mode"))


## Client: waiting panel instead of the code.
func _draw_waiting(c: Control) -> void:
	var r := CODE_PANEL
	UiKit.panel(c, r, UiKit.PANEL_DARK, ACCENT)
	UiKit.icon(c, "fly", Vector2(r.position.x + 10, r.position.y + 14), 2, ACCENT)
	var dots := ".".repeat(1 + int(_time * 3.0) % 3)
	UiKit.text(c, Vector2(r.position.x + 50, r.position.y + 26), "WAITING FOR THE HOST" + dots, 11, ACCENT, 2)
	UiKit.text(c, Vector2(r.position.x + 50, r.position.y + 40), "The host starts the flight for everyone.", 6, UiKit.DIM, 0)
	UiKit.text(c, Vector2(r.position.x + 50, r.position.y + 50), "Your role is set by the order you joined in.", 6, UiKit.DIM, 0)


## Four crew slots: role colour, little crewmate, player name, HOST / YOU chips. Empty = dithered.
func _draw_crew(c: Control) -> void:
	var ids := Network.players.keys()
	ids.sort()
	var roles := CrewRoles.assign(ids)
	UiKit.text(c, Vector2(CODE_PANEL.position.x + 1, CREW_Y - 2), "CREW  %d / %d" % [ids.size(), Network.MAX_PLAYERS], 7, ACCENT, 2)
	UiKit.text_r(c, CODE_PANEL.end.x - 1, CREW_Y - 2, "ROLES IN FLIGHT", 5, UiKit.FAINT.lightened(0.25), 0)
	for i in Network.MAX_PLAYERS:
		var r := Rect2(CODE_PANEL.position.x + i * (SLOT_W + 4.0), CREW_Y + 2, SLOT_W, SLOT_H)
		if i >= ids.size():
			c.draw_rect(r, UiKit.INK)
			c.draw_rect(r.grow(-1), Color(UiKit.WELL, 0.85))
			UiKit.dither(c, r.grow(-2), Color(UiKit.FAINT, 0.25))
			var plus := UiKit.FAINT.lightened(0.2) if fmod(_time + i * 0.3, 1.4) < 0.9 else UiKit.FAINT
			c.draw_rect(Rect2(r.get_center().x - 5, r.position.y + 26, 11, 3), plus)
			c.draw_rect(Rect2(r.get_center().x - 1, r.position.y + 22, 3, 11), plus)
			UiKit.text_c(c, r.get_center().x, r.end.y - 14, "FREE SLOT", 6, UiKit.FAINT.lightened(0.2), 0)
			UiKit.text_c(c, r.get_center().x, r.end.y - 6, "waiting...", 5, UiKit.FAINT, 0)
			continue
		var id: int = ids[i]
		var role: String = roles.get(id, "all")
		var parts := role.split("+")
		var col: Color = UiKit.ROLE_COLORS.team if role == "all" else UiKit.role_color(parts[0])
		var col2: Color = UiKit.role_color(parts[1]) if parts.size() > 1 else col.darkened(0.3)
		r.position.y += _juice.bounce("slot_%d" % id, 4.0)
		UiKit.panel(c, r, UiKit.PANEL, col)
		# Role band: one colour per role it covers.
		var band := Rect2(r.position.x + 2, r.position.y + 2, r.size.x - 4, 10)
		if parts.size() > 1:
			c.draw_rect(Rect2(band.position, Vector2(floorf(band.size.x / 2.0), band.size.y)), col.darkened(0.45))
			c.draw_rect(Rect2(band.position.x + floorf(band.size.x / 2.0), band.position.y, ceilf(band.size.x / 2.0), band.size.y), col2.darkened(0.45))
		else:
			c.draw_rect(band, col.darkened(0.45))
		c.draw_rect(Rect2(band.position.x, band.end.y, band.size.x, 1), UiKit.INK)
		var role_text: String = ROLE_NAMES.get(role, CrewRoles.tag(role))
		UiKit.text_c(c, band.get_center().x, band.end.y - 2, role_text, 6, UiKit.TEXT, 0)
		# Role icons in the corners of the stage.
		for k in parts.size():
			var icon_name: String = UiKit.ROLE_ICONS.get(parts[k], "team")
			UiKit.icon(c, icon_name, Vector2(r.position.x + 4 + k * 10, r.position.y + 15), 1,
					UiKit.role_color(parts[k]) if role != "all" else col)
		var bob := -1 if fmod(_time * 1.6 + i * 0.37, 1.0) < 0.5 else 0
		c.draw_rect(Rect2(r.get_center().x - 9, r.position.y + 46, 18, 2), Color(UiKit.INK, 0.6))   # shadow
		MenuKit.crewmate(c, Vector2(r.get_center().x - 12, r.position.y + 18), col, col2, 2, bob)
		var player_name := NetText.player(str(Network.players[id]))
		UiKit.text_c(c, r.get_center().x, r.position.y + 57, player_name, 7, UiKit.TEXT, 2)
		var tags: Array = []
		if id == 1:
			tags.append(["HOST", HOST_COLOR])
		if id == Network.my_id():
			tags.append(["YOU", ME_COLOR])
		var tw := 0.0
		for t: Array in tags:
			tw += MenuKit.tag_w(t[0], "", 5) + 2
		var tx := roundf(r.get_center().x - (tw - 2) / 2.0)
		for t: Array in tags:
			var tr := MenuKit.tag(c, Vector2(tx, r.end.y - 12), t[0], t[1], "", 5, true)
			tx = tr.end.x + 2


func _draw_status(c: Control) -> void:
	var host := Network.is_host()
	var text := ""
	if host:
		text = "Friends type the code in JOIN. The room closes if you leave." if Network.is_online_room() \
				else "Friends can't get in? Set the network to Private and allow the game through the firewall."
	else:
		text = "Waiting for the host to start the flight" + ".".repeat(1 + int(_time * 3.0) % 3)
	var right := START_RECT.position.x - 8 if host else CODE_PANEL.end.x
	var y := CREW_Y + SLOT_H + 14
	UiKit.icon(c, "dsn", Vector2(CODE_PANEL.position.x + 2, y - 7), 1, ACCENT)
	for line in UiKit.wrap(text, 6, right - CODE_PANEL.position.x - 14).slice(0, 3):
		UiKit.text(c, Vector2(CODE_PANEL.position.x + 13, y), line, 6, UiKit.DIM, 0)
		y += UiKit.line_h(6)
	if host:
		var ready_col := UiKit.GOOD
		var hot := _focus == "start"
		var k := 1.0 if hot and fmod(_time, 0.8) < 0.4 else 0.0
		MenuKit.button(c, Rect2(START_RECT.position + Vector2(0, -k), START_RECT.size), "START FLIGHT",
				ready_col, hot, true, 9, "fly", _juice.k("press_start"))
