class_name PixelMode
extends RefCounted
## Window settings for gameplay scenes: a 480x270 canvas scaled by whole numbers, Nearest
## filtering (set on the scene root) so pixel art stays sharp. canvas_items mode (not viewport)
## so text renders at full screen resolution (UiFont). Menus keep project.godot's settings,
## so call enter() in _enter_tree and exit() in _exit_tree.

const BASE_SIZE := Vector2i(480, 270)


static func enter(w: Window) -> Dictionary:
	var saved := {
		size = w.content_scale_size,
		mode = w.content_scale_mode,
		aspect = w.content_scale_aspect,
		stretch = w.content_scale_stretch,
	}
	w.content_scale_size = BASE_SIZE
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	return saved


static func exit(w: Window, saved: Dictionary) -> void:
	if saved.is_empty():
		return
	w.content_scale_size = saved.size
	w.content_scale_mode = saved.mode
	w.content_scale_aspect = saved.aspect
	w.content_scale_stretch = saved.stretch
