class_name TouchControls
extends CanvasLayer
## On-screen controls for phones / tablets (web build). Created once by PixelMode.enter() and kept on the root.
## Shown on the first touch (and from the start in mobile browsers), hidden again by any keyboard / gamepad
## press - whichever the player used last wins. Everything becomes ordinary input actions
## (Input.parse_input_event), so no screen needs touch code:
##   left half      floating joystick -> p1 left/right/up/down (analog strength), pushed to the rim = run
##   USE            p1 interact (in the cruise it sits on the HUD's action button)
##   BACK           p1 leave (Q)
##   small buttons  MENU (ui_cancel), and per screen: PING (G), RADAR (E), HUD (TAB), INFO (F)
## Reading overlays: dialogs that take taps themselves (tutorial, briefing, ESC menu) hide the controls; the ones
## that only read keys (mission report, game over, Codex) get a row of key buttons instead.
## Menus are clickable already (touch is emulated as a mouse). Portrait = "rotate" hint.

const SCHEME := "p1"
const STICK_R := 24.0           # joystick throw (480x270 units)
const DEAD := 0.3               # stick share before a direction counts as pressed
const RUN_AT := 0.92            # stick share that also holds "run"
const USE_R := 21.0
const SMALL_R := 11.0
const KEY_H := 16.0             # key-button row height
const SYNTH_DEVICE := 4242      # device id on the key events we send ourselves (not a real keyboard)
const INK := Color(0.02, 0.03, 0.08, 0.7)
const FACE := Color(0.85, 0.9, 1.0, 0.16)
const FACE_ON := Color(0.85, 0.9, 1.0, 0.42)
const GAME_SCENE := "res://scenes/game/game.tscn"
## Screens with walking / stations (scene file -> layout). stick = joystick on the left half; left = USE / BACK
## sit bottom-left (the launch lever owns the bottom-right); small = extra buttons up the right edge.
const SCREENS := {
	"res://scenes/game/game.tscn": {small = ["menu", "ping", "radar", "hud"]},
	"res://scenes/design/hangar.tscn": {small = ["menu", "info"]},
	"res://scenes/launch/launch.tscn": {stick = false, left = true, use = "STAGE", small = ["menu"]},
	"res://scenes/launch/planner.tscn": {small = ["menu"]},
	"res://scenes/design/designer.tscn": {small = ["menu"]},
}
const SMALL := {
	menu = {label = "MENU", action = &"ui_cancel"},
	ping = {label = "PING", verb = "ping"},
	radar = {label = "RADAR", verb = "radar"},
	hud = {label = "HUD", verb = "tasks"},
	info = {label = "INFO", verb = "inspect"},
	redesign = {label = "REDO", verb = "right"},   # launch failed: D = back to the hangar
}

static var _instance: TouchControls

var _active := false            # a touch was seen (or a mobile browser)
var _canvas: Node2D
var _touches := {}              # touch index -> "stick" | button name
var _stick_center := Vector2.ZERO
var _stick := Vector2.ZERO      # -1..1 each axis
var _pressed := {}              # action name -> strength while we hold it
var _buttons := {}              # name -> {center, r, label} or {rect, label, key} (layout of this frame)
var _overlay: Variant = null    # null = gameplay, "dialog" = a tappable dialog is up, Array = key buttons


## Called by PixelMode.enter(): one instance for the whole game.
static func ensure(w: Window) -> void:
	if is_instance_valid(_instance) or not w.is_inside_tree():
		return
	_instance = TouchControls.new()
	_instance.name = "TouchControls"
	w.get_tree().root.add_child.call_deferred(_instance)


func _ready() -> void:
	layer = 30                   # above dialogs and minigames: the controls must stay reachable
	process_mode = Node.PROCESS_MODE_ALWAYS   # the ESC menu pauses the tree; MENU / BACK must still work
	_active = OS.has_feature("web_android") or OS.has_feature("web_ios")
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	Controls.ensure_actions()


func _scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene else ""


func _screen() -> Dictionary:
	return SCREENS.get(_scene_path(), {})


func _in_game() -> bool:
	return _active and not _screen().is_empty()


func _on_hud_button() -> bool:
	return _scene_path() == GAME_SCENE and UiKit.hud.has("action")


## What is covering the screen: null (play), "dialog" (it takes taps: hide), or [[label, keycode], ...].
func _find_overlay() -> Variant:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var dialog := Tutorial.any_open()
	for n in scene.get_children():
		if n is Codex and n.is_open():
			return [["UP", KEY_W], ["DOWN", KEY_S], ["CLOSE", KEY_Q]]   # may sit over the briefing
		if n is GameOver and n.takes_input():
			return [["AGAIN", KEY_SPACE], ["CREDITS", KEY_C], ["MENU", KEY_ESCAPE]]
		if n is MissionReport and n.takes_input():
			return [["NEXT", KEY_SPACE], ["MISSIONS", KEY_M], ["MENU", KEY_ESCAPE]]
		if (n is MissionBriefing or n is PauseMenu) and n.is_open():
			dialog = true
	return "dialog" if dialog else null


func _process(_delta: float) -> void:
	visible = _active
	var before: Variant = _overlay
	_overlay = _find_overlay() if _in_game() else null
	if (not _in_game() or _overlay != null) and not _pressed.is_empty():
		_release_all()
	if typeof(before) != typeof(_overlay):
		_touches.clear()   # a finger that went down on a control no longer owns anything
	_layout()
	_canvas.queue_redraw()


func _layout() -> void:
	_buttons.clear()
	var size := _canvas.get_viewport_rect().size
	if _overlay is Array:   # key buttons centred along the bottom edge
		var widths := []
		var total := 0.0
		for k: Array in _overlay:
			var w := UiKit.text_w(str(k[0]), 8) + 18.0
			widths.append(w)
			total += w + 6.0
		var x := (size.x - total + 6.0) / 2.0
		for i in _overlay.size():
			var k: Array = _overlay[i]
			_buttons["key%d" % i] = {rect = Rect2(x, size.y - KEY_H - 4, widths[i], KEY_H), label = k[0], key = k[1]}
			x += float(widths[i]) + 6.0
		return
	if _overlay != null:
		return
	var screen := _screen()
	var left: bool = screen.get("left", false)
	var use_c := Vector2(36, size.y - 34) if left else Vector2(size.x - 32, size.y - 34)
	if _on_hud_button():
		use_c = UiKit.hud_rect("action").get_center()   # right on the HUD's big action button
	_buttons["use"] = {center = use_c, r = USE_R, label = screen.get("use", "USE")}
	_buttons["back"] = {center = use_c + Vector2(40 if left else -40, 12), r = SMALL_R + 2, label = "BACK"}
	var small: Array = screen.get("small", []).duplicate()
	if _launch_failed():
		small.append("redesign")
	var y := use_c.y - 42
	for name: String in small:
		_buttons[name] = {center = Vector2(16 if left else size.x - 16, y), r = SMALL_R, label = SMALL[name].label}
		y -= 26


func _launch_failed() -> bool:
	var scene := get_tree().current_scene
	var flight: Variant = scene.get("flight") if scene else null
	return flight is Dictionary and str(flight.get("phase", "")) == "failed"


# --- input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# A real keyboard (or gamepad) press hides the controls; the next touch brings them back. Our own key taps
	# (_send_key) carry SYNTH_DEVICE so they don't count.
	if (event is InputEventKey and event.device != SYNTH_DEVICE) or event is InputEventJoypadButton:
		if event.is_pressed() and _active:
			_active = false
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			_active = true
		if not _in_game() or _overlay is String:
			return
		if event.pressed:
			var hit := _button_at(event.position)
			if hit != "":
				_touches[event.index] = hit
				_press_button(hit, true)
			elif _overlay == null and _screen().get("stick", true) \
					and event.position.x < _canvas.get_viewport_rect().size.x * 0.5:
				_touches[event.index] = "stick"
				_stick_center = event.position
				_set_stick(Vector2.ZERO)
		else:
			var what: String = _touches.get(event.index, "")
			_touches.erase(event.index)
			if what == "stick":
				_set_stick(Vector2.ZERO)
			elif what != "":
				_press_button(what, false)
	elif event is InputEventScreenDrag and _touches.get(event.index, "") == "stick":
		var off: Vector2 = event.position - _stick_center
		if off.length() > STICK_R:   # the base follows a finger that slides past the rim
			_stick_center = event.position - off.limit_length(STICK_R)
			off = off.limit_length(STICK_R)
		_set_stick(off / STICK_R)


func _button_at(p: Vector2) -> String:
	for name: String in _buttons:
		var b: Dictionary = _buttons[name]
		if b.has("rect"):
			if (b.rect as Rect2).grow(3).has_point(p):
				return name
		elif p.distance_to(b.center) <= float(b.r) + 4.0:
			return name
	return ""


func _press_button(name: String, on: bool) -> void:
	var b: Dictionary = _buttons.get(name, {})
	if b.has("key"):
		if on:
			_send_key(int(b.key))
		return
	match name:
		"use":
			_set_action(Controls.action(SCHEME, "interact"), on)
		"back":
			_set_action(Controls.action(SCHEME, "leave"), on)
		_:
			var info: Dictionary = SMALL.get(name, {})
			var act: StringName = info.get("action", Controls.action(SCHEME, str(info.get("verb", ""))))
			_set_action(act, on)
			if act == &"ui_cancel" and on:   # the ESC menu also listens for the key itself
				_send_key(KEY_ESCAPE)


## A key tap for screens that read raw keys (report, game over, Codex, ESC menu).
func _send_key(code: int) -> void:
	var key := InputEventKey.new()
	key.device = SYNTH_DEVICE
	key.keycode = code as Key
	key.physical_keycode = code as Key
	key.pressed = true
	Input.parse_input_event(key)
	var up: InputEventKey = key.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _set_stick(v: Vector2) -> void:
	_stick = v
	var dirs := {left = -v.x, right = v.x, up = -v.y, down = v.y}
	for d: String in dirs:
		var s: float = dirs[d]
		_set_action(Controls.action(SCHEME, d), s > DEAD, clampf(s, 0.0, 1.0))
	_set_action(Controls.action(SCHEME, "run"), v.length() >= RUN_AT)


## Press / release / re-press with a new strength (analog stick). No event when nothing changed.
func _set_action(action: StringName, on: bool, strength := 1.0) -> void:
	if not InputMap.has_action(action):
		return
	if not on and not _pressed.has(action):
		return
	if on and _pressed.has(action) and absf(float(_pressed[action]) - strength) < 0.02:
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	ev.strength = strength if on else 0.0
	Input.parse_input_event(ev)
	if on:
		_pressed[action] = strength
	else:
		_pressed.erase(action)


func _release_all() -> void:
	for action: StringName in _pressed.keys():
		_set_action(action, false)
	_touches.clear()
	_stick = Vector2.ZERO


# --- drawing --------------------------------------------------------------------------------

func _draw_controls() -> void:
	var c := _canvas
	var size := c.get_viewport_rect().size
	var win := DisplayServer.window_get_size()
	if win.y > win.x:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.05, 0.94))
		UiKit.text_c(c, size.x / 2.0, size.y / 2.0 - 6, "ROTATE YOUR PHONE", 14, UiKit.TEXT)
		UiKit.text_c(c, size.x / 2.0, size.y / 2.0 + 10, "this game plays sideways", 8, UiKit.DIM, 0)
		return
	if not _in_game() or _overlay is String:
		return
	if _overlay == null and _screen().get("stick", true):
		_draw_stick(c, size)
	for name: String in _buttons:
		var b: Dictionary = _buttons[name]
		var down := _touches.values().has(name)
		if b.has("rect"):
			var r: Rect2 = b.rect
			c.draw_rect(r.grow(1), INK)
			c.draw_rect(r, Color(UiKit.PANEL, 0.92) if not down else UiKit.PANEL.lightened(0.25))
			c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.25))
			UiKit.text_c(c, r.get_center().x, r.end.y - 5, str(b.label), 8, UiKit.TEXT, 1)
			continue
		if name == "use" and _on_hud_button():   # the HUD's action button is the face; just a ring
			c.draw_arc(b.center, float(b.r), 0.0, TAU, 40, Color(1, 1, 1, 0.5 if down else 0.18), 2.0)
			continue
		c.draw_circle(b.center, float(b.r) + 1.0, INK)
		c.draw_circle(b.center, float(b.r), FACE_ON if down else FACE)
		var sz := 9 if name == "use" else 6
		if name == "use" and str(b.label).length() > 3:
			sz = 7
		UiKit.text_c(c, b.center.x, b.center.y + sz * 0.35, str(b.label), sz, UiKit.TEXT, 1)


## Shows where the thumb is (or a faint hint where to put it).
func _draw_stick(c: Node2D, size: Vector2) -> void:
	var holding := _touches.values().has("stick")
	var base := _stick_center if holding else Vector2(52, size.y - 52)
	c.draw_arc(base, STICK_R + 6, 0.0, TAU, 40, FACE if holding else Color(FACE, 0.08), 2.0)
	var knob := base + _stick * STICK_R
	c.draw_circle(knob, 11, INK)
	c.draw_circle(knob, 10, FACE_ON if holding else FACE)
	if not holding:
		UiKit.text_c(c, base.x, base.y + 3, "MOVE", 7, Color(UiKit.TEXT, 0.5), 1)
	elif _stick.length() >= RUN_AT:
		UiKit.text_c(c, base.x, base.y - STICK_R - 10, "RUN", 7, UiKit.WARN, 1)
