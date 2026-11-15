extends Node2D
## Assembly hangar: the walk-around design phase (replaces the menu designer in the Mars flow).
##
## The crew walks around the hangar (sprites/hangar_assets) and builds ONE spacecraft:
##   - SPACE at a role shelf picks a part up (only the role that owns the shelf), F reads it.
##   - The rocket on the bay (fairing door open, the folded ship inside): SPACE opens the full-screen
##     RocketBoard. The part in your hand rides on a cell cursor: SPACE on an empty cell installs it,
##     on a taken cell swaps (the old part comes into your hand); empty hands take a part out.
##     Anyone can swap anyone's part. SPACE at its shelf puts a part back.
##   - SPACE at a class plate switches ship class AND rocket (DesignRules.CLASS_ROCKET); parts in
##     cells the new body lacks go back on the shelf. Nothing is filled in for you.
##   - The planner console (NAV) opens the launch window planner as an overlay: date, path, orbit.
##   - SPACE at the suit-up locker (left, by the crew spawn) opens CharacterSelect: pick your look.
##   - SPACE in the launch door zone = READY. All READY (ship has no errors, plan possible) -> launch pad.
##   Any change to the ship or the plan un-readies everyone.
##
## Network: designer pattern. The host owns `design`, `plan`, `ready_by` and `carried`
## (peer -> part in hand); clients send actions, the host applies them and sends the state back.
## A part is on its shelf when it is neither installed nor carried, so shelves need no state.
## Crew positions stream at 20 Hz through the host (like NetSync in the cruise).

const LAYOUT_PATH := "res://sprites/hangar_assets/hangar_layout.json"
const CONSOLE_JSON := "res://sprites/launch_planner_assets/planner.json"
const CONSOLE_SHEET := "res://sprites/launch_planner_assets/planner_sheet.png"
const CONSOLE_FEET := Vector2(400, 200)      # by the NAV rack
const PLANNER_SCRIPT := preload("res://scripts/launch/planner.gd")
const LAUNCH_SCENE := "res://scenes/launch/launch.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"
const PLAYER_SKINS := ["friend_1", "friend_2", ""]
const CREW_SEND := 1.0 / 20.0
const CONSOLE_REACH := 16.0
const CARD_W := 156.0        # F card width at NORMAL text (grows with TEXT SIZE; height fits the content)
const SIGN_PX := 6           # board text: painted into fixed boxes on the map, so it ignores TEXT SIZE

var design := DesignRules.new_design()
var plan := LaunchWindow.default_plan()
var ready_by := {}            # peer -> true
var carried := {}             # peer -> part id in hand
var roles := {}               # peer -> crew role

var _layout := {}
var _console := {}
var _saved_window := {}
var _me := 1
var _ready_peers := {}        # host: clients whose hangar has loaded
var _crew: Node2D
var _local: CrewMember
var _preview: ShipPreview
var _glow: Node2D             # socket glows over the ship
var _fx: Node2D               # carried parts, prompts, console tag (above the crew)
var _ui: Node2D               # info card + footer (screen space)
var _console_sprite: Sprite2D
var _planner: Node2D          # open planner overlay (null = closed)
var _planner_layer: CanvasLayer
var _board: RocketBoard       # open rocket board overlay (null = closed)
var _board_layer: CanvasLayer
var _wardrobe: CharacterSelect   # open suit-up locker overlay (null = closed)
var _wardrobe_layer: CanvasLayer
var _rocket_shape: CollisionShape2D   # the rocket on the bay blocks the crew (size follows the class)
var _card_target := {}        # what the F card shows ({} = closed)
var _target := {}             # what SPACE / F act on right now
var _message := ""
var _message_time := 0.0
var _send_timer := 0.0
var _launching := false
var _time := 0.0
var _card_box: StyleBoxTexture
var radio := {on = false, track = 0}   # crew boombox on the right bench (host-owned, like the design)
var _radio_audio: Radio
var _radio_set: HangarDecor
var _lighting: HangarLighting


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UiKit.setup_canvas(self)
	Controls.ensure_actions()
	DesignRules.preload_textures()
	_layout = _load_json(LAYOUT_PATH)
	_console = _load_json(CONSOLE_JSON)
	if not DesignRules.chosen.is_empty():   # back from a failed launch: keep the ship and plan
		design = DesignRules.chosen.duplicate(true)
		plan = LaunchWindow.plan_of(design)
		design.erase("plan")
	_build_scene()
	_me = Network.my_id() if Network.is_in_room() else 1
	_radio_audio = Radio.new().setup(null)
	add_child(_radio_audio)
	if _is_host():   # clients hear the host's station once its state arrives
		radio = {on = true, track = randi() % Radio.TRACKS.size()}
	_refresh_players()
	_spawn_crew()
	if Network.is_in_room():
		Network.room_changed.connect(_on_room_changed)
		Network.room_closed.connect(func(_r: String) -> void: get_tree().change_scene_to_file(JOIN_SCENE))
		multiplayer.peer_disconnected.connect(func(id: int) -> void: _ready_peers.erase(id))
		if not Network.is_host():
			_client_ready.rpc_id(1)
	_apply_state({design = design, plan = plan, ready_by = {}, carried = {}})
	PauseMenu.attach(self, "LEAVE TO MAIN MENU", "WASD WALK · SPACE USE · F INFO · J CODEX · H HELP")
	var id := Missions.current_id()
	if id != "" and not MissionBriefing.was_shown(id):
		var briefing := MissionBriefing.attach(self)
		briefing.open.call_deferred()
		briefing.closed.connect(_attach_tutorial, CONNECT_ONE_SHOT)
	else:
		_attach_tutorial()


func _attach_tutorial() -> void:
	Tutorial.attach(self, "hangar", [
		{title = "The assembly hangar", rect = Rect2(4, 18, 472, 246),
		 body = "Together you build ONE spacecraft. Walk with WASD (hold SHIFT to run). Every part costs mass, power AND budget - there is no free upgrade."},
		{title = "Suit up", rect = Rect2(62, 156, 42, 46),
		 body = "The locker by the door you came in: SPACE picks your look (flight suit and backdrop). Your astronaut - name, bio, radiation dose - comes with your crew role."},
		{title = "Your shelf", rect = Rect2(8, 2, 146, 54),
		 body = "Each crew role has a shelf. SPACE picks up a part from YOUR shelf, F reads what it does and what it costs."},
		{title = "The rocket", rect = Rect2(178, 34, 124, 130),
		 body = "Your spacecraft sits folded inside the rocket's open fairing. Carry a part here and press SPACE: the rocket board opens. Put the part in any cell - or swap one out, it lands in your hand."},
		{title = "Shared limits", rect = Rect2(158, 0, 164, 38),
		 body = "The board shows mass, power, budget, slots and the rocket. They are shared by the whole crew. Negative power is allowed - the battery will drain in flight. Too heavy for the rocket = no launch."},
		{title = "Ship + rocket", rect = Rect2(141, 170, 198, 82),
		 body = "SPACE at a plate picks the ship class AND its rocket: Light flies on Electron, Balanced on Zenit, Heavy on Proton. More slots and lift, less budget. The parts you fetch yourselves."},
		{title = "Planner console", rect = Rect2(372, 152, 56, 64),
		 body = "The Navigator plans the launch date, the path and the Mars orbit here. Everyone sees the plan on the console."},
		{title = "Launch door", rect = Rect2(404, 0, 68, 46),
		 body = "When ship and plan are set, everyone stands on the striped floor by the door and presses SPACE. Any change un-readies everyone."},
	])


func _is_host() -> bool:
	return not Network.is_in_room() or Network.is_host()


# --- scene -------------------------------------------------------------------------------

func _build_scene() -> void:
	_build_walls()
	_preview = ShipPreview.new()
	_preview.folded = true        # packed in the fairing: no wings, no boom
	add_child(_preview)
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var silo_front := Sprite2D.new()          # deck in front of the silo hole: the rocket's base sinks into the floor
	silo_front.texture = load(str(_layout.get("rocket", {}).get("front", "")))
	silo_front.centered = false
	add_child(silo_front)
	_crew = Node2D.new()
	_crew.name = "Crew"
	_crew.y_sort_enabled = true
	add_child(_crew)
	_console_sprite = Sprite2D.new()
	_console_sprite.texture = load(CONSOLE_SHEET)
	_console_sprite.centered = false
	_console_sprite.hframes = 6
	_console_sprite.vframes = 3
	_console_sprite.offset = -_arr(_console.get("anchor", [24, 43]))
	_console_sprite.position = CONSOLE_FEET
	_crew.add_child(_console_sprite)
	for d in HangarDecor.spawn(_crew):      # computers, plants, mug, radio (y-sorted with the crew)
		if d.kind == "radio":
			_radio_set = d
	var motes := HangarDecor.Motes.new()
	motes.z_index = 3
	add_child(motes)
	var overlay := Sprite2D.new()
	overlay.texture = load(str(_layout.get("overlay", {}).get("texture", "")))
	overlay.centered = false
	overlay.z_index = 4
	add_child(overlay)
	_lighting = HangarLighting.new()        # z 4 after the overlay: relights everything below the prompts
	add_child(_lighting)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Node2D.new()
	_ui.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	var card: Dictionary = _layout.get("info_card", {})
	_card_box = StyleBoxTexture.new()
	_card_box.texture = load(str(card.get("texture", "")))
	var m: Dictionary = card.get("patch_margins", {})
	_card_box.texture_margin_left = float(m.get("left", 6))
	_card_box.texture_margin_top = float(m.get("top", 14))
	_card_box.texture_margin_right = float(m.get("right", 6))
	_card_box.texture_margin_bottom = float(m.get("bottom", 6))


## Walls on ShipMap.WALL_LAYER (the crew's collision mask): outside the walkable rect,
## every obstacle from the layout, and the planner console's desk.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = ShipMap.WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	var walk := _rect((_layout.get("walkable", [{}]) as Array)[0])
	var rects: Array[Rect2] = [
		Rect2(0, 0, 480, walk.position.y), Rect2(0, walk.end.y, 480, 270 - walk.end.y),
		Rect2(0, 0, walk.position.x, 270), Rect2(walk.end.x, 0, 480 - walk.end.x, 270),
	]
	for o: Dictionary in _layout.get("obstacles", []):
		rects.append(_rect(o))
	var desk := _rect(_console.get("obstacle", {}))
	desk.position += CONSOLE_FEET - _arr(_console.get("anchor", [24, 43]))
	rects.append(desk)
	rects.append_array(HangarDecor.obstacles())
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.get_center()
		body.add_child(col)
	_rocket_shape = CollisionShape2D.new()
	_rocket_shape.shape = RectangleShape2D.new()
	body.add_child(_rocket_shape)


func _refresh_players() -> void:
	var ids: Array = Network.players.keys() if Network.is_in_room() else [1]
	roles = CrewRoles.assign(ids)


func _spawn_crew() -> void:
	var spawns: Array = _layout.get("spawns", [])
	var ids: Array = roles.keys()
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var member := CrewMember.new()
		member.name = "Crew_%d" % id if Network.is_in_room() else "P1"
		member.scheme = "p1"
		member.role = roles[id]
		member.remote = id != _me
		member.world_actions = false
		member.show_marker = Network.is_in_room() and id == _me
		if Network.is_in_room():
			member.display_name = str(Network.players.get(id, ""))
		member.skin = PLAYER_SKINS[i % 2]
		var saved: Variant = CharacterSelect.saved_skin()
		if id == _me and saved != null and (saved == "" or CrewSprite.has_skin(saved)):
			member.skin = saved   # the look picked at the suit-up locker last time (others arrive by snapshot)
		member.position = _v(spawns[i % spawns.size()]) if not spawns.is_empty() else Vector2(30, 136)
		member.set_meta("peer", id)
		_crew.add_child(member)
		if id == _me:
			_local = member


func _crew_of(peer: int) -> CrewMember:
	for m in _crew.get_children():
		if m is CrewMember and int(m.get_meta("peer", -1)) == peer:
			return m
	return null


# --- frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_message_time = maxf(_message_time - delta, 0.0)
	if _local:
		_target = _find_target(_local.global_position)
		if not _launching and not _overlay_open() and not Tutorial.is_blocking():
			_handle_input()
	if not _card_target.is_empty() and not _same_target(_card_target, _target):
		_card_target = {}
	var near_console: bool = _target.get("kind", "") == "console" or _planner != null
	var anim: Dictionary = _console.get("animations", {}).get("highlight" if near_console else "idle", {})
	_console_sprite.frame = int(anim.get("row", 0)) * 6 + int(_time * float(anim.get("fps", 4))) % int(anim.get("frames", 6))
	_send_crew(delta)
	_lighting.update(_time, _all_ready(), HangarDecor.beat(_time) if radio.get("on", false) else 0.0)
	queue_redraw()
	_glow.queue_redraw()
	_fx.queue_redraw()
	_ui.queue_redraw()


func _handle_input() -> void:
	if Input.is_action_just_pressed(Controls.action("p1", "inspect")):
		if not _card_target.is_empty() or _target.is_empty() or _target.kind == "hint":
			_card_target = {}
		else:
			_card_target = _target
			Sfx.play("ui_hover")
	if Input.is_action_just_pressed(Controls.action("p1", "interact")):
		_use(_target)


## What SPACE / F would act on for a player standing at `feet` (the local player).
func _find_target(feet: Vector2) -> Dictionary:
	var held := str(carried.get(_me, ""))
	var best := {}
	var best_d := INF
	var near_rocket := _rocket_rect().grow(float(_layout.get("rocket", {}).get("reach", 12))).has_point(feet)
	if held != "":
		if near_rocket:
			return {kind = "rocket"}
		for s: Dictionary in _layout.get("shelf_slots", []):
			if s.part_id == held and feet.distance_to(_v(s)) <= float(s.interact_radius):
				return {kind = "return", part = held}
		return {kind = "hint", part = held}
	for s: Dictionary in _layout.get("shelf_slots", []):
		var d := feet.distance_to(_v(s))
		if d <= float(s.interact_radius) and d < best_d:
			best_d = d
			best = {kind = "take", part = str(s.part_id)}
	if near_rocket and best.is_empty():
		best = {kind = "rocket"}
	for st: Dictionary in _layout.get("class_stands", []):
		var d := feet.distance_to(_v(st))
		if d <= float(st.interact_radius) and d < best_d:
			best_d = d
			best = {kind = "class", id = str(st["class"])}
	var cp := _console_use_point()
	if feet.distance_to(cp) <= CONSOLE_REACH and feet.distance_to(cp) < best_d:
		best = {kind = "console"}
	var ld := feet.distance_to(HangarDecor.LOCKER_USE)
	if ld <= HangarDecor.LOCKER_REACH and ld < best_d:
		best_d = ld
		best = {kind = "locker"}
	var rd := feet.distance_to(HangarDecor.RADIO_USE)
	if rd <= HangarDecor.RADIO_REACH and rd < best_d:
		best = {kind = "radio"}
	if _door_zone().has_point(feet):
		best = {kind = "ready"}
	return best


func _all_ready() -> bool:
	if roles.is_empty():
		return false
	for id in roles:
		if not ready_by.get(id, false):
			return false
	return true


func _same_target(a: Dictionary, b: Dictionary) -> bool:
	return a.get("kind", "") == b.get("kind", "") and a.get("part", "") == b.get("part", "") \
			and a.get("id", "") == b.get("id", "")


## SPACE: checked locally for instant feedback, then sent to the host.
func _use(t: Dictionary) -> void:
	match str(t.get("kind", "")):
		"take":
			var part := str(t.part)
			if part in design.upgrades:
				_deny("ALREADY ON THE SHIP")
			elif part in carried.values():
				_deny("SOMEONE IS CARRYING IT")
			elif not CrewRoles.has(roles.get(_me, "all"), DesignRules.part(part).get("role", "")):
				_deny("NOT YOUR SHELF - %s ONLY" % CrewRoles.tag(DesignRules.part(part).get("role", "")))
			else:
				_send({type = "take", part = part})
				Sfx.play("clank", 1.2)
		"return":
			_send({type = "return"})
			Sfx.play("clank", 0.9)
		"rocket":
			_open_board()
		"class":
			if design.ship_class != t.id:
				_send({type = "class", id = str(t.id)})
				Sfx.play("toggle")
		"console":
			_open_planner()
		"ready":
			var why := _ready_problem()
			if why != "" and not ready_by.get(_me, false):
				_deny(why)
			else:
				_send({type = "ready"})
				Sfx.play("ui_click")
		"hint":
			_deny("TAKE IT TO THE ROCKET OR PUT IT BACK ON ITS SHELF")
		"radio":
			_send({type = "radio"})
			Sfx.play("toggle")
		"locker":
			_open_wardrobe()


## Why the ship can't launch yet ("" = it can).
func _ready_problem() -> String:
	var errors: Array = DesignRules.evaluate(design).errors
	if not errors.is_empty():
		return str(errors[0])
	if not LaunchWindow.evaluate(design, plan).ok:
		return "IMPOSSIBLE LAUNCH DATE - FIX IT AT THE PLANNER"
	return ""


func _deny(text: String) -> void:
	_say(text)
	if _board:
		_board.say(text)
	Sfx.play("denied")


func _say(text: String) -> void:
	_message = text
	_message_time = 2.2


func _send(action: Dictionary) -> void:
	if _is_host():
		_host_apply(_me, action)
	else:
		_request.rpc_id(1, action)


# --- planner console ---------------------------------------------------------------------

func _open_planner() -> void:
	if _planner:
		return
	_planner_layer = CanvasLayer.new()
	_planner_layer.layer = 15
	add_child(_planner_layer)
	_planner = PLANNER_SCRIPT.new()
	_planner.embedded = true
	_planner.can_drive = CrewRoles.has(roles.get(_me, "all"), "navigator")
	_planner.show_plan(design, plan)
	_planner.request.connect(_send)
	_planner.close_requested.connect(_close_planner)
	_planner_layer.add_child(_planner)
	_card_target = {}
	_local.set_physics_process(false)     # stands at the console while the overlay is open
	_local.velocity = Vector2.ZERO
	_local._facing = Vector2.UP
	_local._animate(false, "work_up")
	Sfx.play("dock")


func _close_planner() -> void:
	if _planner_layer:
		_planner_layer.queue_free()
	_planner = null
	_planner_layer = null
	if _local:
		_local.set_physics_process(true)
	Sfx.play("undock")


func _overlay_open() -> bool:
	return _planner != null or _board != null or _wardrobe != null


## Suit-up locker: character select overlay (walking is held off by CharacterSelect itself).
func _open_wardrobe() -> void:
	if _wardrobe:
		return
	_wardrobe_layer = CanvasLayer.new()
	_wardrobe_layer.layer = 15
	add_child(_wardrobe_layer)
	_wardrobe = CharacterSelect.new()
	_wardrobe.role = str(roles.get(_me, "all"))
	_wardrobe.worn = _local.skin
	_wardrobe.crew_root = _crew
	_wardrobe.picked.connect(func(skin: String) -> void: _local.skin = skin)   # synced in the crew snapshot
	_wardrobe.close_requested.connect(_close_wardrobe)
	_wardrobe_layer.add_child(_wardrobe)
	_card_target = {}
	_local.velocity = Vector2.ZERO
	_local._facing = Vector2.UP
	_local._animate(false, "")


func _close_wardrobe() -> void:
	if _wardrobe_layer:
		_wardrobe_layer.queue_free()
	_wardrobe = null
	_wardrobe_layer = null


## The rocket board: full-screen overlay; the player stands at the rocket meanwhile.
func _open_board() -> void:
	if _board:
		return
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 15
	add_child(_board_layer)
	_board = RocketBoard.new()
	_board.rocket_name = str(_rocket_info().get("name", ""))
	_board.design = design
	_board.held = str(carried.get(_me, ""))
	_board.request.connect(_send)
	_board.close_requested.connect(_close_board)
	_board_layer.add_child(_board)
	_card_target = {}
	_local.set_physics_process(false)
	_local.velocity = Vector2.ZERO
	_local._facing = Vector2.UP
	_local._animate(false, "work_up")
	Sfx.play("dock")


func _close_board() -> void:
	if _board_layer:
		_board_layer.queue_free()
	_board = null
	_board_layer = null
	if _local:
		_local.set_physics_process(true)
	Sfx.play("undock")


# --- host logic --------------------------------------------------------------------------

func _host_apply(peer: int, action: Dictionary) -> void:
	var role: String = roles.get(peer, "")
	if role == "":
		return
	var d := design.duplicate(true)
	var p := plan.duplicate()
	var r := ready_by.duplicate()
	var c := carried.duplicate()
	var nav := CrewRoles.has(role, "navigator")
	match str(action.get("type", "")):
		"take":
			var part := str(action.get("part", ""))
			var info := DesignRules.part(part)
			if info.is_empty() or c.has(peer) or part in d.upgrades or part in c.values():
				return
			if not CrewRoles.has(role, info.get("role", "")):
				_tell(peer, "NOT YOUR SHELF")
				return
			c[peer] = part
		"return":
			c.erase(peer)
		"cell":   # rocket board: install / swap / take out (anyone, any part)
			var cell := int(action.get("cell", -1))
			var cells := DesignRules.cells_of(d)
			if cell < 0 or cell >= cells.size():
				return
			var hand := str(c.get(peer, ""))
			var there := str(cells[cell])
			if hand == "" and there == "":
				return
			if hand != "":
				var reason := DesignRules.check_put(d, cell, hand)
				if reason != "":
					_tell(peer, reason)
					return
			d = DesignRules.put(d, cell, hand)
			if there != "":
				c[peer] = there
			else:
				c.erase(peer)
		"class":
			if str(action.get("id", "")) in DesignRules.class_ids():
				d = DesignRules.set_class(d, str(action.id))   # parts that don't fit go back to the shelf
		"orbit":
			if nav:
				d = DesignRules.set_orbit(d, str(action.get("id", "")))
		"date":
			if nav:
				p.offset = clampi(int(action.get("offset", 0)), -LaunchWindow.RANGE_DAYS, LaunchWindow.RANGE_DAYS)
		"speed":
			if nav and str(action.get("speed", "")) in LaunchWindow.ORDER:
				p.speed = str(action.speed)
		"radio":   # anyone; switching on tunes to the next track; never un-readies
			var on := not bool(radio.get("on", false))
			var track := int(radio.get("track", 0))
			radio = {on = on, track = (track + 1) % Radio.TRACKS.size() if on else track}
		"ready":
			if r.get(peer, false):
				r.erase(peer)
			elif _ready_problem() == "":
				r[peer] = true
			else:
				_tell(peer, _ready_problem())
				return
	if d != design or p != plan:
		r = {}   # the ship or the plan changed: everyone has to look again
	_apply_state({design = d, plan = p, ready_by = r, carried = c})
	_broadcast()
	_check_launch()


func _tell(peer: int, text: String) -> void:
	if peer == _me:
		_deny(text)
	elif Network.is_in_room():
		_recv_say.rpc_id(peer, text)


func _broadcast() -> void:
	if not Network.is_in_room():
		return
	var state := _state()
	for id: int in _ready_peers:
		_recv_state.rpc_id(id, state)


func _state() -> Dictionary:
	return {design = design, plan = plan, ready_by = ready_by, carried = carried, radio = radio}


func _apply_state(state: Dictionary) -> void:
	design = state.get("design", design)
	plan = state.get("plan", plan)
	ready_by = state.get("ready_by", {})
	carried = state.get("carried", {})
	radio = state.get("radio", radio)
	if _radio_audio:
		_radio_audio.tune(bool(radio.get("on", false)), int(radio.get("track", 0)))
	if _radio_set:
		_radio_set.on = bool(radio.get("on", false))
	_preview.design = design
	_place_rocket()
	if _planner:
		_planner.show_plan(design, plan)
	if _board:
		_board.rocket_name = str(_rocket_info().get("name", ""))
		_board.show_state(design, str(carried.get(_me, "")))


func _check_launch() -> void:
	if _launching or not _is_host():
		return
	for id in roles:
		if not ready_by.get(id, false):
			return
	var final := LaunchWindow.apply(design, plan)
	if Network.is_in_room():
		_launch.rpc(final)
	else:
		_launch(final)


func _on_room_changed() -> void:
	_refresh_players()
	for m in _crew.get_children():
		if m is CrewMember and not roles.has(int(m.get_meta("peer", -1))):
			m.queue_free()
	if _is_host():
		var r := {}
		for id in ready_by:
			if roles.has(id):
				r[id] = true
		var c := {}
		for id in carried:   # a player who left drops their part: it goes back on the shelf
			if roles.has(id):
				c[id] = carried[id]
		_apply_state({design = design, plan = plan, ready_by = r, carried = c})
		_broadcast()
		_check_launch()


# --- network -----------------------------------------------------------------------------

func _send_crew(delta: float) -> void:
	if not Network.is_in_room() or _local == null or _launching:
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = CREW_SEND
	var snap := _local.snapshot()
	if Network.is_host():
		for id: int in _ready_peers:
			_crew_from_host.rpc_id(id, _me, snap)
	else:
		_crew_to_host.rpc_id(1, snap)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if is_inside_tree() and Network.is_host():
		var id := multiplayer.get_remote_sender_id()
		_ready_peers[id] = true
		_recv_state.rpc_id(id, _state())


@rpc("any_peer", "call_remote", "reliable")
func _request(action: Dictionary) -> void:
	if is_inside_tree() and Network.is_host():
		_host_apply(multiplayer.get_remote_sender_id(), action)


@rpc("authority", "call_remote", "reliable")
func _recv_state(state: Dictionary) -> void:
	_apply_state(state)


@rpc("authority", "call_remote", "reliable")
func _recv_say(text: String) -> void:
	_deny(text)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _crew_to_host(snap: Array) -> void:
	# A packet can still arrive while the scene is being swapped out (launch / leave):
	# the node is out of the tree then and has no `multiplayer`.
	if not is_inside_tree() or not Network.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_crew_from_host(sender, snap)
	for id: int in _ready_peers:
		if id != sender:
			_crew_from_host.rpc_id(id, sender, snap)


@rpc("authority", "call_remote", "unreliable_ordered")
func _crew_from_host(peer: int, snap: Array) -> void:
	var m := _crew_of(peer)
	if m and m.remote:
		m.apply_snapshot(snap)


@rpc("authority", "call_local", "reliable")
func _launch(final_design: Dictionary) -> void:
	if _launching:
		return
	_launching = true
	_close_planner()
	_close_board()
	_close_wardrobe()
	DesignRules.chosen = final_design.duplicate(true)
	Sfx.play("burn")
	_say("ALL READY - TO THE LAUNCH PAD")
	await get_tree().create_timer(0.9).timeout
	get_tree().change_scene_to_file(LAUNCH_SCENE)


# --- drawing: floor layer (under the ship and the crew) ----------------------------------

func _draw() -> void:
	var map := DesignRules.texture(str(_layout.get("map", "")))
	if map:
		draw_texture(map, Vector2.ZERO)
	for s: Dictionary in _layout.get("shelf_slots", []):
		var part := str(s.part_id)
		if part in design.upgrades or part in carried.values():
			continue   # the painted outline on the shelf shows the empty spot
		var tex := _part_tex(part, s)
		if tex:
			var bin := _rect(s.bin)
			draw_texture(tex, (bin.position + ((bin.size - tex.get_size()) / 2.0).floor()).floor())
	var rocket := DesignRules.texture(str(_rocket_info().get("sprite", "")))
	if rocket:
		var rr := _rocket_rect()
		draw_rect(Rect2(rr.position.x + 4, rr.end.y - 2, rr.size.x, 3), Color(0, 0, 0, 0.3))   # shadow on the mount
		draw_texture(rocket, rr.position)
		if _target.get("kind", "") == "rocket" or _board:
			var o := _opening_rect()
			draw_rect(o.grow(1), Color(UiKit.GOOD, 0.45 + 0.3 * sin(_time * 5.0)), false, 1.0)
	_draw_stands()
	_draw_board()
	_draw_door()
	HangarLighting.draw_beacon(self, _time, _all_ready())


func _draw_stands() -> void:
	for st: Dictionary in _layout.get("class_stands", []):
		var on: bool = design.ship_class == str(st["class"])
		var lamp := _v(st.lamp)
		draw_rect(Rect2(lamp - Vector2(1, 1), Vector2(2, 2)), UiKit.GOOD if on else Color("3a2030"))
		if on:
			var r := _rect(st.plinth).grow(1)
			var a := 0.55 + 0.35 * sin(_time * 4.0)
			draw_rect(r, Color(UiKit.GOOD, a), false, 1.0)


func _draw_board() -> void:
	var f: Dictionary = _layout.get("board", {}).get("fields", {})
	var ev := DesignRules.evaluate(design)
	var cls := DesignRules.class_info(design.ship_class)
	var cr := _rect(f.get("class", {}))
	_sign(Vector2(cr.end.x, cr.end.y), str(cls.get("name", "")).to_upper(), Color.WHITE, true)
	var net: float = ev.net_w
	var left: float = ev.budget - ev.cost
	var rows := {
		mass = [ev.mass / maxf(ev.mass_limit, 1.0), "%dKG" % ev.mass, Color("4fd8ff")],
		power = [clampf(ev.gen_w / maxf(ev.draw_w, 1.0) * 0.5, 0.0, 1.0), "%s%dW" % ["+" if net >= 0 else "", net],
				UiKit.GOOD if net >= 0 else UiKit.BAD],
		budget = [ev.cost / maxf(ev.budget, 1.0), "$%dM" % left, Color("ffc640")],
		slots = [float(ev.slots_used) / maxf(ev.slots, 1.0), "%d/%d" % [ev.slots_used, ev.slots], Color.WHITE],
	}
	for key: String in rows:
		var row: Array = rows[key]
		var field: Dictionary = f.get(key, {})
		var bar := _rect(field.get("bar", {}))
		var fill: float = row[0]
		var col: Color = row[2]
		if fill > 1.0 or (key == "power" and net < 0) or (key == "budget" and left < 0):
			col = UiKit.BAD
		draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * clampf(fill, 0.0, 1.0)), bar.size.y)), col)
		var vr := _rect(field.get("value", {}))
		_sign(Vector2(vr.position.x, vr.end.y), str(row[1]), col if col == UiKit.BAD else Color.WHITE)
	var rr := _rect(f.get("rocket", {}))
	var launcher: Dictionary = ev.launcher
	var rname := str(_rocket_info().get("name", "NONE"))
	var lifts: bool = not launcher.is_empty() and ev.mass <= float(launcher.capacity_kg) * DesignRules.LIFT_MARGIN
	var rw := UiFont.font().get_string_size(rname, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX).x
	_sign(Vector2(rr.get_center().x - roundf(rw / 2.0), rr.end.y), rname, Color.WHITE if lifts else UiKit.BAD)


## Board text in the map's fixed boxes (right = `pos` is the right edge).
func _sign(pos: Vector2, text: String, col: Color, right := false) -> void:
	var f := UiFont.font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX).x
	draw_string(f, Vector2(pos.x - (w if right else 0.0), pos.y).round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX, col)


func _draw_door() -> void:
	var door: Dictionary = _layout.get("launch_door", {})
	var ids: Array = roles.keys()
	ids.sort()
	var lights: Array = door.get("ready_lights", [])
	for i in lights.size():
		var p := _v(lights[i])
		var col := Color("3a1418")
		if i < ids.size():
			col = UiKit.GOOD if ready_by.get(ids[i], false) else Color("b8323a")
		draw_rect(Rect2(p - Vector2(2, 1), Vector2(4, 3)), col)
	var zone := _door_zone()
	var all_ok := _ready_problem() == ""
	if _target.get("kind", "") == "ready" or not ready_by.is_empty():
		draw_rect(zone, Color(UiKit.GOOD if all_ok else UiKit.WARN, 0.25 + 0.15 * sin(_time * 5.0)), false, 1.0)


## Free upgrade cells glow in the role colour of the part in hand.
func _draw_glow() -> void:
	var held := str(carried.get(_me, ""))
	if held == "":
		return
	var sockets: Dictionary = _layout.get("sockets", {})
	var tex := DesignRules.texture(str(sockets.get("cell_glow", "")))
	var off := _v(sockets.get("cell_glow_offset", {"x": -2, "y": -2}))
	var col := CrewRoles.color(DesignRules.part(held).get("role", ""))
	var ok := DesignRules.check_add(design, held) == ""
	col.a = (0.55 + 0.4 * sin(_time * 6.0)) if ok else 0.25
	var cells := _preview.upgrade_cells()
	var filled := DesignRules.cells_of(design)
	for i in mini(cells.size(), filled.size()):
		if tex and str(filled[i]) == "":
			_glow.draw_texture(tex, _preview.position + cells[i] + off, col)


# --- drawing: above the crew -------------------------------------------------------------

func _draw_fx() -> void:
	# carried parts, bottom-centred over each crew member's head
	var carry_off := _v(_layout.get("carry", {}).get("offset", {"x": 0, "y": -16}))
	for peer in carried:
		var m := _crew_of(int(peer))
		var tex := _part_tex(str(carried[peer]))
		if m and tex:
			var at := m.position + carry_off - Vector2(floorf(tex.get_width() / 2.0), tex.get_height())
			_fx.draw_texture(tex, at.round())
	_draw_console_screen()
	_draw_now_playing()
	if _local and not _overlay_open() and not _launching:
		_draw_prompt()


## Track title over the radio: for a few seconds after it changes, and while you stand at it.
func _draw_now_playing() -> void:
	var title := _radio_audio.now_playing() if _radio_audio else ""
	if title == "" or not _radio_audio.showing() or _target.get("kind", "") == "radio":   # at the set: the prompt names it
		return
	var label := "~ " + title.to_upper() + " ~"
	var f := UiFont.font()
	var w := ceilf(f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX).x) + 4
	var x := roundf(clampf(_radio_set.position.x - w / 2.0, 4.0, 476.0 - w))
	var r := Rect2(x, _radio_set.position.y - 32, w, 7)
	var col := Color("ff9ac8")
	_fx.draw_rect(r, Color(UiKit.INK, 0.85))
	_fx.draw_rect(r, Color(col, 0.6), false, 1.0)
	_fx.draw_string(f, Vector2(r.position.x + 2, r.end.y - 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX, col)


## The console's screen shows whether the plan works (green / amber / red edge) and a small sign above it
## (path, date, tank burn). Fixed SIGN_PX like the board, so TEXT SIZE can't push it over the crates.
func _draw_console_screen() -> void:
	var e := LaunchWindow.evaluate(design, plan)
	var col := UiKit.GOOD if e.fuel_cost <= 0.5 else (UiKit.WARN if e.ok else UiKit.BAD)
	var sr := _rect(_console.get("screen_rect", {}))
	sr.position += CONSOLE_FEET - _arr(_console.get("anchor", [24, 43]))
	_fx.draw_rect(sr.grow(1), Color(col, 0.5 + 0.3 * sin(_time * 3.0)), false, 1.0)
	var path := "STD" if str(e.path.name) == "STANDARD" else str(e.path.name)
	var label := "%s %s %d%%" % [path, str(e.date).substr(2), ceili(e.fuel_cost)]
	var f := UiFont.font()
	var w := ceilf(f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX).x) + 4
	var x := roundf(clampf(sr.get_center().x - w / 2.0, 4.0, 476.0 - w))
	var r := Rect2(x, sr.position.y - 9, w, 7)
	_fx.draw_rect(r, Color(UiKit.INK, 0.85))
	_fx.draw_rect(r, Color(col, 0.6), false, 1.0)
	_fx.draw_string(f, Vector2(r.position.x + 2, r.end.y - 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_PX, col)


## Key cap + verb over the local player's head for what SPACE would do.
func _draw_prompt() -> void:
	var verb := ""
	var ok := true
	var t := _target
	match str(t.get("kind", "")):
		"take":
			var part := str(t.part)
			if part in design.upgrades:
				verb = "ON THE SHIP"
				ok = false
			elif part in carried.values():
				verb = "IN SOMEONE'S HANDS"
				ok = false
			else:
				verb = "TAKE"
				ok = CrewRoles.has(roles.get(_me, "all"), DesignRules.part(part).get("role", ""))
				if not ok:
					verb = "NOT YOUR SHELF"
		"return": verb = "PUT BACK"
		"rocket": verb = "OPEN ROCKET BOARD"
		"class":
			ok = design.ship_class != t.id
			verb = ("SWITCH TO " + str(DesignRules.class_info(t.id).get("name", "")).to_upper()) if ok else "SELECTED"
		"console": verb = "PLAN LAUNCH"
		"locker": verb = "CHOOSE CHARACTER"
		"radio":
			var song := _radio_audio.now_playing() if _radio_audio else ""
			verb = ("RADIO OFF  ~ %s ~" % song.to_upper()) if song != "" else "RADIO ON"
		"ready":
			verb = "NOT READY" if ready_by.get(_me, false) else "READY"
			ok = ready_by.get(_me, false) or _ready_problem() == ""
		_:
			return
	var top := _local.position + Vector2(0, -32 if Network.is_in_room() else -24)
	if carried.has(_me):
		top.y -= 14
	var cap := UiKit.keycap_size("SPACE", 6)
	var vw := UiKit.text_w(verb, 6)
	var info: bool = t.kind in ["take", "return", "rocket", "class", "console", "ready"]
	var fw := UiKit.keycap_size("F", 6).x + 2 + UiKit.text_w("INFO", 6) + 6 if info else 0.0
	var total := cap.x + 2 + vw + fw
	var x := roundf(clampf(top.x - total / 2.0, 4.0, 476.0 - total))
	var y := roundf(top.y)
	UiKit.panel(_fx, Rect2(x - 3, y - cap.y, total + 6, cap.y + 4), UiKit.PANEL_DARK)   # readable over busy art
	UiKit.keycap(_fx, Vector2(x, y - cap.y + 2), "SPACE", 6, ok)
	UiKit.text(_fx, Vector2(x + cap.x + 2, y), verb, 6, Color.WHITE if ok else UiKit.DIM)
	if info:
		var fx := x + cap.x + 2 + vw + 6
		var fcap := UiKit.keycap_size("F", 6)
		UiKit.keycap(_fx, Vector2(fx, y - fcap.y + 2), "F", 6)
		UiKit.text(_fx, Vector2(fx + fcap.x + 2, y), "INFO", 6, UiKit.DIM)


# --- drawing: screen UI ------------------------------------------------------------------

func _draw_ui() -> void:
	_draw_footer()
	if not _card_target.is_empty() and not _overlay_open():
		_draw_card(_card_target)


func _draw_footer() -> void:
	var text := ""
	var col := UiKit.DIM
	if _message_time > 0.0:
		text = _message
		col = UiKit.GOOD if _launching else UiKit.WARN
	else:
		var why := _ready_problem()
		if why != "":
			text = "! " + why
			col = UiKit.BAD
		elif ready_by.size() < roles.size():
			text = "SHIP + PLAN OK - ALL TO THE LAUNCH DOOR (%d/%d)" % [ready_by.size(), roles.size()]
			col = UiKit.GOOD
	if text == "":
		return
	# between the SCI and NAV racks (x 128..382)
	text = UiKit.fit(text, 7, 244.0)
	var w := UiKit.text_w(text, 7) + 10
	var h := UiKit.line_h(7) + 4
	var r := Rect2(roundf(255 - w / 2.0), 267 - h, roundf(w), h)
	UiKit.panel(_ui, r, UiKit.PANEL_DARK, col)
	UiKit.text_c(_ui, 255, r.end.y - 4, text, 7, col, 0)


## F card next to the player: part, ship class, console or launch door.
## Rows are laid out first, so the card grows with TEXT SIZE instead of spilling out.
func _draw_card(t: Dictionary) -> void:
	var w := roundf(CARD_W * lerpf(1.0, UiFont.scale(), 0.7))
	var inner := w - 14.0
	var rows := _card_rows(t, inner)
	if rows.is_empty():
		return
	var body := rows.slice(1)
	var h := _layout_rows(body, Vector2.ZERO, false) + 6.0
	var feet := _local.position
	var pos := Vector2(clampf(feet.x - w / 2.0, 4.0, 476.0 - w),
			feet.y - 40.0 - h if feet.y > 140.0 else feet.y + 12.0)
	pos.y = clampf(pos.y, 4.0, 250.0 - h)
	var r := Rect2(pos.round(), Vector2(w, roundf(h)))
	_ui.draw_style_box(_card_box, r)
	var title: Dictionary = rows[0]
	var x := r.position.x + 7.0
	UiKit.text(_ui, Vector2(x, r.position.y + 11), UiKit.fit(str(title.text), 7, inner - 24.0), 7, Color.WHITE, 0)
	if title.has("tag"):
		UiKit.text_r(_ui, r.end.x - 7, r.position.y + 11, str(title.tag), 7, title.tag_col, 0)
	_layout_rows(body, Vector2(x, r.position.y), true)


## Places the card's body rows below the header band (from `origin` = left edge, card top);
## draws them when `draw` is true. Returns the height used, measured from the card top.
func _layout_rows(body: Array, origin: Vector2, draw: bool) -> float:
	var y := 17.0
	var icon_bottom := 0.0
	for row: Dictionary in body:
		if row.has("icon"):
			if draw:
				_ui.draw_texture(row.icon, origin + Vector2(0, y))
			icon_bottom = y + 34.0
			continue
		if row.get("clear", false):
			y = maxf(y, icon_bottom)
		y += float(row.get("gap", 0.0)) + UiKit.line_h(int(row.size))
		if draw:
			UiKit.text(_ui, origin + Vector2(float(row.get("x", 0.0)), y - 2.0), str(row.text), int(row.size), row.col, 0)
	return maxf(y, icon_bottom)


## Card content: rows[0] = title {text, tag?, tag_col?}; then {text, size, col, x?, gap?, clear?} or {icon}.
func _card_rows(t: Dictionary, inner: float) -> Array:
	var rows: Array = []
	match str(t.kind):
		"take", "return":
			var id := str(t.part)
			var p := DesignRules.part(id)
			var role := str(p.get("role", ""))
			rows.append({text = str(p.get("name", id)).to_upper(), tag = CrewRoles.tag(role), tag_col = CrewRoles.color(role)})
			var icon := DesignRules.texture(str(p.get("dir", "")) + str(p.get("icon", "")))
			if icon:
				rows.append({icon = icon})
			var pw := int(p.get("power_w", 0))
			rows.append({text = "+%d KG" % p.get("mass_kg", 0), size = 7, col = Color("4fd8ff"), x = 36.0, gap = 2.0})
			rows.append({text = "%s%d W" % ["+" if pw >= 0 else "", pw], size = 7, col = UiKit.GOOD if pw >= 0 else UiKit.BAD, x = 36.0})
			rows.append({text = "$%dM" % p.get("cost", 0), size = 7, col = Color("ffc640"), x = 36.0})
			var lines := UiKit.wrap(str(p.get("desc", "")), 6, inner)
			for i in lines.size():
				rows.append({text = lines[i], size = 6, col = UiKit.DIM, clear = i == 0, gap = 3.0 if i == 0 else 0.0})
			var status := "FITTED ON THE SHIP" if id in design.upgrades else DesignRules.check_add(design, id)
			if status == "":
				status = "FITS - CARRY IT TO THE ROCKET"
			rows.append({text = UiKit.fit(status, 6, inner), size = 6, clear = true, gap = 3.0,
					col = UiKit.GOOD if status.begins_with("F") else UiKit.BAD})
		"class":
			var cls := DesignRules.class_info(str(t.id))
			rows.append({text = "%s SHIP" % str(cls.get("name", "")).to_upper()})
			var rk := DesignRules.rocket_for(str(t.id))
			var rk_name := str(_layout.get("rocket", {}).get("types", {}).get(str(rk.get("id", "")), {}).get("name", ""))
			for line in ["UPGRADE SLOTS: %d" % cls.get("upgrade_slots", 0), "EMPTY MASS: %d KG" % cls.get("dry_mass_kg", 0),
					"MASS LIMIT: %d KG" % cls.get("mass_limit_kg", 0), "PRICE: $%dM" % cls.get("cost", 0),
					"ROCKET: %s (LIFTS %d KG, $%dM)" % [rk_name, int(float(rk.get("capacity_kg", 0)) * DesignRules.LIFT_MARGIN), int(rk.get("cost", 0))]]:
				rows.append({text = UiKit.fit(line, 6, inner), size = 6, col = UiKit.TEXT})
			_dim_rows(rows, "Switches ship AND rocket. You fetch the parts yourselves; ones that no longer fit go back on their shelves.", inner)
		"rocket":
			var ev := DesignRules.evaluate(design)
			var rk: Dictionary = ev.launcher
			var lift := int(float(rk.get("capacity_kg", 0)) * DesignRules.LIFT_MARGIN)
			rows.append({text = "%s ROCKET" % str(_rocket_info().get("name", ""))})
			for line in ["CARRIES: %s SHIP" % str(DesignRules.class_info(design.ship_class).get("name", "")).to_upper(),
					"LIFTS: %d KG (10%% MARGIN)" % lift, "SHIP NOW: %d KG" % ev.mass, "PRICE: $%dM" % int(rk.get("cost", 0))]:
				rows.append({text = UiKit.fit(line, 6, inner), size = 6, col = UiKit.TEXT if ev.mass <= lift or not line.begins_with("SHIP") else UiKit.BAD})
			_dim_rows(rows, "SPACE opens the board inside the fairing: put the part in your hand into any cell, or swap one out.", inner)
		"console":
			var e := LaunchWindow.evaluate(design, plan)
			rows.append({text = "LAUNCH WINDOW PLANNER"})
			for line in ["DATE: %s" % e.date, "PATH: %s (%d DAYS)" % [e.path.name, int(e.trip_days)],
					"SHIP BURNS: %d%% FUEL" % ceili(e.fuel_cost), "MARS BRAKE: %d%% FUEL" % ceili(e.moi),
					"ORBIT: %s" % str(Orbits.info(Orbits.id_of(design)).get("name", ""))]:
				rows.append({text = UiKit.fit(line, 6, inner), size = 6, col = UiKit.TEXT})
			rows.append({text = "NAVIGATOR: SPACE TO PLAN", size = 6, col = CrewRoles.color("navigator"), gap = 4.0})
		"ready":
			rows.append({text = "LAUNCH DOOR"})
			var problems: Array = DesignRules.evaluate(design).errors.duplicate()
			if not LaunchWindow.evaluate(design, plan).ok:
				problems.append("IMPOSSIBLE LAUNCH DATE")
			if problems.is_empty():
				rows.append({text = "SHIP AND PLAN OK", size = 6, col = UiKit.GOOD})
			for prob: String in problems:
				for line in UiKit.wrap(prob, 6, inner):
					rows.append({text = line, size = 6, col = UiKit.BAD})
			_dim_rows(rows, "Everyone presses SPACE here. Any change to the ship or the plan un-readies all.", inner)
	return rows


func _dim_rows(rows: Array, text: String, inner: float) -> void:
	var gap := 4.0
	for line in UiKit.wrap(text, 6, inner):
		rows.append({text = line, size = 6, col = UiKit.DIM, gap = gap})
		gap = 0.0


# --- helpers -----------------------------------------------------------------------------

func _part_tex(part: String, slot := {}) -> Texture2D:
	var p := DesignRules.part(part)
	var tex: Texture2D = null
	if not p.is_empty():
		tex = DesignRules.texture(str(p.dir) + str(p.get("mounted", "")))
	if tex == null and not slot.is_empty():
		tex = DesignRules.texture(str(slot.get("mounted", "")))
	return tex


## Layout info of the rocket that flies the current class (sprite, size, opening).
func _rocket_info() -> Dictionary:
	var id := str(DesignRules.rocket_for(str(design.get("ship_class", "balanced"))).get("id", "medium"))
	return _layout.get("rocket", {}).get("types", {}).get(id, {})


## The rocket sprite's rect on the map: cylinder centred on center_x, base on bottom_y.
func _rocket_rect() -> Rect2:
	var r: Dictionary = _layout.get("rocket", {})
	var i := _rocket_info()
	var w := float(i.get("w", 0))
	var h := float(i.get("h", 0))
	var x := float(r.get("center_x", 240)) - (float(i.get("cyl_x", 0)) + floorf(float(i.get("cyl_w", 0)) / 2.0))
	return Rect2(x, float(r.get("bottom_y", 160)) - h, w, h)


func _opening_rect() -> Rect2:
	var o := _rect(_rocket_info().get("opening", {}))
	o.position += _rocket_rect().position
	return o


## Moves the folded ship into the rocket's opening and sizes the rocket's collision.
func _place_rocket() -> void:
	var o := _opening_rect()
	# ShipPreview: body centre at (80, 62) of its box; the folded stack (dish + body) is centred 9 px higher.
	_preview.position = (o.get_center() - Vector2(ShipPreview.SIZE.x / 2, ShipPreview.SIZE.y / 2 - 2) + Vector2(0, 9)).floor()
	if _rocket_shape:
		var r := _rocket_rect()
		var top := maxf(r.position.y, 40.0)          # the nose may poke above the walkable floor
		(_rocket_shape.shape as RectangleShape2D).size = Vector2(r.size.x, r.end.y - top)
		_rocket_shape.position = Vector2(r.get_center().x, (top + r.end.y) / 2.0)


func _door_zone() -> Rect2:
	return _rect(_layout.get("launch_door", {}).get("zone", {}))


func _console_use_point() -> Vector2:
	var it: Dictionary = _console.get("interact", {"x": 24, "y": 51})
	return CONSOLE_FEET - _arr(_console.get("anchor", [24, 43])) + _v(it)


static func _v(d: Dictionary) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))


static func _arr(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _rect(d: Dictionary) -> Rect2:
	return Rect2(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("w", 0)), float(d.get("h", 0)))


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Hangar: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
