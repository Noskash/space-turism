extends Node2D
## Mission scene root: ship map + crew + HUD + sim.
##
## Pixel-perfect mode is switched on only while this scene is alive: the window renders a
## 480x270 viewport scaled by whole numbers with Nearest filtering. The menus keep their own
## (canvas_items) settings, so nothing in project.godot had to change.

const BASE_SIZE := Vector2i(480, 270)
const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join_room.tscn"
## Who covers which stations, by number of players (CLAUDE.md "Crew roles").
const ROLE_SPLITS := {
	1: ["all"],
	2: ["navigator+engineer", "comms+scientist"],
	3: ["navigator", "engineer", "comms+scientist"],
	4: ["navigator", "engineer", "comms", "scientist"],
}
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


func _enter_tree() -> void:
	var w := get_window()
	_saved_window = {
		size = w.content_scale_size,
		mode = w.content_scale_mode,
		aspect = w.content_scale_aspect,
		stretch = w.content_scale_stretch,
	}
	w.content_scale_size = BASE_SIZE
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER


func _exit_tree() -> void:
	Sfx.set_loop("hum", false)
	var w := get_window()
	w.content_scale_size = _saved_window.size
	w.content_scale_mode = _saved_window.mode
	w.content_scale_aspect = _saved_window.aspect
	w.content_scale_stretch = _saved_window.stretch


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # inherited by map, stations, crew
	Controls.ensure_actions()
	_net = NetSync.new()
	_net.name = "NetSync"
	add_child(_net)
	_net.crew_received.connect(_on_crew_received)
	_spawn_crew()
	Vfx.new().setup(self, _map, _crew)
	if _net.active:
		Network.room_changed.connect(_on_room_changed)
		Network.room_closed.connect(_on_room_closed)
	Sfx.set_loop("hum", true)
	if _net.is_authority():
		_mission.start({})  # clients get the host's state through NetSync


func _process(delta: float) -> void:
	if _net.is_authority():
		_mission.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if Network.is_in_room():
			Network.leave_room()  # host leaving closes the room for everyone
		get_tree().change_scene_to_file(MENU_SCENE)


## Offline: one crew member who can use every station.
## Co-op: one per player in the room (same order on every peer), roles split per ROLE_SPLITS.
func _spawn_crew() -> void:
	if not _net.active:
		_local = _add_crew("P1", "all", 0, false)
		_net.local_crew = _local
		return
	var ids := Network.players.keys()
	ids.sort()
	var roles: Array = ROLE_SPLITS.get(ids.size(), ROLE_SPLITS[4])
	for i in ids.size():
		var id: int = ids[i]
		var is_me := id == Network.my_id()
		var member := _add_crew("Crew_%d" % id, roles[mini(i, roles.size() - 1)], i, not is_me)
		member.show_marker = is_me
		if is_me:
			_local = member
	_net.local_crew = _local
	if _local:
		_hud.show_role(_role_tag(_local.role))


func _add_crew(node_name: String, role: String, index: int, is_remote: bool) -> CrewMember:
	var member := CrewMember.new()
	member.name = node_name
	member.scheme = "p1"
	member.role = role
	member.remote = is_remote
	member.skin = PLAYER_SKINS[index % 2]
	member.ship_map = _map
	member.position = _map.spawn_point(index)
	_crew.add_child(member)
	member.skin_changed.connect(_update_companion.bind(member))
	_update_companion(member.skin, member)
	return member


func _physics_process(_delta: float) -> void:
	if _local and Input.is_action_just_pressed(Controls.action("p1", "skin")):
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


static func _role_tag(role: String) -> String:
	var tags := PackedStringArray()
	for r in role.split("+"):
		tags.append(TicketStrip.TAGS.get(r, r.to_upper()))
	return "+".join(tags)
