extends Node2D
## Mission scene root: ship map + crew + HUD + sim. Pixel mode (PixelMode) only while alive.
## The mission starts with the design the crew launched (DesignRules.chosen; {} = base kit).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"

## Skins the local player cycles through with K ("" = placeholder astronaut).
const PLAYER_SKINS := ["friend_1", "friend_2", ""]

@onready var _map: ShipMap = $ShipMap
@onready var _crew: Node2D = $Crew
@onready var _mission: Node = $Mission
@onready var _hud: CanvasLayer = $HUD

var _saved_window := {}
var _net: NetSync
var _local: CrewMember          # the crew member this window controls
var _companions := {}           # CrewMember -> Companion
var _tutorial: Tutorial
var _guide: EventGuide


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())


func _exit_tree() -> void:
	Sfx.set_loop("hum", false)
	Sfx.set_loop("engine", false)
	PixelMode.exit(get_window(), _saved_window)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # inherited by map, stations, crew
	Controls.ensure_actions()
	_net = NetSync.new()
	_net.name = "NetSync"
	add_child(_net)
	_net.crew_received.connect(_on_crew_received)
	_spawn_crew()
	_hud.local = _local
	Vfx.new().setup(self, _map, _crew)
	ShipLighting.new().setup(self, _map, _crew)
	add_child(Radio.new().setup(_hud.radio_label))
	var radio_set := RadioSet.new()
	radio_set.crew = _crew
	add_child(radio_set)
	if _net.active:
		Network.room_changed.connect(_on_room_changed)
		Network.room_closed.connect(_on_room_closed)
	Sfx.set_loop("hum", true)
	Sfx.set_loop("engine", true)
	if _net.is_authority():
		_mission.crew_size = maxi(Network.players.size(), 1) if _net.active else 1
		_mission.start(DesignRules.chosen)  # clients get the host's state through NetSync
	PauseMenu.attach(self, "ABANDON MISSION", "WASD MOVE · SHIFT RUN · SPACE USE · TAB TASKS · K SKIN · H HELP")
	_guide = EventGuide.new()
	_guide.name = "EventGuide"
	_guide.map = _map
	_guide.local = _local
	add_child(_guide)
	_tutorial = Tutorial.attach(self, "cruise", [
		{title = "Fly the mission", rect = UiKit.hud_rect("tasks").grow(1),
		 body = "Problems pop up as tasks, top right, each with a countdown in its role's colour. Run to that station before the timer runs out. SHIFT = run, TAB folds the list."},
		{title = "Ship and mission", rect = UiKit.hud_rect("resources").merge(UiKit.hud_rect("progress")).grow(1),
		 body = "Top left: POWER, FUEL and DATA storage. Top centre: the trip from Earth to Mars, the Deep Space Network pass, science sent home and science lost."},
		{title = "Action button", rect = UiKit.hud_rect("action").grow(1),
		 body = "Bottom right shows what SPACE does right now: DOCK at a station, REPAIR, FIX, DOWNLINK... Grey = nothing to do here."},
		{title = "Stations", rect = Rect2(336, 34, 108, 168),
		 body = "Walk into a station's ring and press SPACE to dock. A/D pick an option, HOLD SPACE to work, W/S leave. BRIDGE (NAV): course-correction burns cost fuel and power."},
		{title = "Engine room", rect = Rect2(30, 138, 118, 112),
		 body = "PWR: switch loads (instruments, transmitter, heater) on and off and reset storm faults. The battery drains whenever loads use more power than you make."},
		{title = "Comms", rect = Rect2(30, 34, 118, 80),
		 body = "COM: HOLD SPACE to send data home - only while a Deep Space Network station is in view and the transmitter is on. Full storage = lost science."},
		{title = "Science lab", rect = Rect2(160, 34, 164, 80),
		 body = "SCI: when a science window opens, HOLD SPACE to observe. Instruments must be on - they eat power and fill storage."},
		{title = "Events", rect = Rect2(UiKit.hud_rect("progress").position.x, UiKit.hud_rect("progress").end.y + 2, UiKit.hud_rect("progress").size.x, 14),
		 body = "Radiation storms, comet debris, faults, science windows... Big ones slide a banner across the screen, then stay here with a countdown. The first time each one happens, a walkthrough shows you how to beat it."},
		{title = "Missed tickets",
		 body = "A missed ticket knocks its station OFFLINE until someone docks and holds a repair. Score = science that reached Earth. H shows this again."},
	])


func _process(delta: float) -> void:
	if _net.is_authority() and not Tutorial.any_open():  # cruise tutorial or an event walkthrough
		_mission.tick(delta)


## Offline: one crew member who can use every station.
## Co-op: one per player in the room (same order on every peer), roles split by CrewRoles.
func _spawn_crew() -> void:
	if not _net.active:
		_local = _add_crew("P1", "all", 0, false)
		_net.local_crew = _local
		return
	var ids := Network.players.keys()
	ids.sort()
	var roles := CrewRoles.assign(ids)
	for i in ids.size():
		var id: int = ids[i]
		var is_me := id == Network.my_id()
		var member := _add_crew("Crew_%d" % id, roles[id], i, not is_me)
		member.show_marker = is_me
		if is_me:
			_local = member
	_net.local_crew = _local
	if _local:
		_hud.show_role(CrewRoles.tag(_local.role), str(Network.players.get(Network.my_id(), "")))


func _add_crew(node_name: String, role: String, index: int, is_remote: bool) -> CrewMember:
	var member := CrewMember.new()
	member.name = node_name
	member.scheme = "p1"
	member.role = role
	member.remote = is_remote
	if _net.active:  # name tag in co-op (role-coloured)
		member.display_name = str(Network.players.get(node_name.trim_prefix("Crew_").to_int(), ""))
	member.skin = PLAYER_SKINS[index % 2]
	member.ship_map = _map
	member.position = _map.spawn_point(index)
	_crew.add_child(member)
	member.skin_changed.connect(_update_companion.bind(member))
	_update_companion(member.skin, member)
	return member


func _physics_process(_delta: float) -> void:
	if _local and not Tutorial.is_blocking() and Input.is_action_just_pressed(Controls.action("p1", "skin")):
		var i := PLAYER_SKINS.find(_local.skin)
		_local.skin = PLAYER_SKINS[(i + 1) % PLAYER_SKINS.size()]


## friend_1 always walks around with his companion (one per friend_1 on the map).
func _update_companion(skin: String, member: CrewMember) -> void:
	var wanted := skin == "friend_1"
	var companion: Companion = _companions.get(member)
	if wanted and companion == null:
		companion = Companion.new()
		companion.setup(member, "friend_1_girl")
		companion.name = "Companion_" + member.name
		_crew.add_child(companion)
		_companions[member] = companion
	elif not wanted and companion != null:
		companion.queue_free()
		_companions.erase(member)


# --- co-op -----------------------------------------------------------------------------

func _on_crew_received(peer_id: int, snapshot: Array) -> void:
	var member := _crew.get_node_or_null("Crew_%d" % peer_id) as CrewMember
	if member and member.remote:
		member.apply_snapshot(snapshot)


## A player left: remove their crew member (their stations stay unmanned).
func _on_room_changed() -> void:
	for member in _crew.get_children():
		if member is CrewMember and member.remote 				and not Network.players.has(member.name.trim_prefix("Crew_").to_int()):
			_update_companion("", member)
			member.queue_free()


## The host closed the room: the Join screen shows Network.pending_message.
func _on_room_closed(_reason: String) -> void:
	get_tree().change_scene_to_file(JOIN_SCENE)
