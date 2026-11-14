extends Node2D
## Mission scene root: ship map + crew + HUD + sim.
##
## Pixel-perfect mode is switched on only while this scene is alive: the window renders a
## 480x270 viewport scaled by whole numbers with Nearest filtering. The menus keep their own
## (canvas_items) settings, so nothing in project.godot had to change.

const BASE_SIZE := Vector2i(480, 270)
const MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _map: ShipMap = $ShipMap
@onready var _crew: Node2D = $Crew
@onready var _mission: Node = $Mission

var _saved_window := {}


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
	var w := get_window()
	w.content_scale_size = _saved_window.size
	w.content_scale_mode = _saved_window.mode
	w.content_scale_aspect = _saved_window.aspect
	w.content_scale_stretch = _saved_window.stretch


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # inherited by map, stations, crew
	Controls.ensure_actions()
	_spawn_crew()
	_mission.start({})


func _process(delta: float) -> void:
	_mission.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if Network.is_in_room():
			Network.leave_room()
		get_tree().change_scene_to_file(MENU_SCENE)


## Single player for now: one astronaut who can use every station.
func _spawn_crew() -> void:
	var member := CrewMember.new()
	member.name = "P1"
	member.scheme = "p1"
	member.role = "all"
	member.ship_map = _map
	member.position = _map.spawn_point(0)
	_crew.add_child(member)
