class_name Tutorial
extends CanvasLayer
## Short dialog-box tutorial for one screen: a few panes, each can highlight a rect (480x270 units).
## Every pane has [SKIP TUTORIAL] (turns the tutorial off on every screen) and [NEXT]/[GOT IT].
## Keys: SPACE/ENTER next · X skip all · ESC close · H reopens this screen's tutorial later. Mouse works too.
## Seen/skipped state lives in user://tutorial.cfg, so it only shows once per screen.
##
## While a pane is open (and for a moment after), `Tutorial.is_blocking()` is true: scenes ignore
## gameplay input, so the SPACE that closes the dialog doesn't also press something in the game.

signal closed

const CFG := "user://tutorial.cfg"
const BOX_W := 300.0
const PAD := 8.0
const ACCENT := Color("4fd8ff")
const BODY := 8
const RELEASE_MS := 180

static var _open_count := 0
static var _holds := 0        # other overlays (PauseMenu) that block gameplay input
static var _release_at := 0

var screen_id := ""
var hotkey := true      # H reopens it (off for event walkthroughs: H is the screen's tutorial)
var panes: Array = []   # [{title, body, rect = Rect2 (optional)}]
var _index := -1
var _canvas: Node2D
var _time := 0.0
var _buttons := {}      # "skip"/"next" -> Rect2 of the drawn button
var _hover := ""


## Adds the tutorial to `scene` and opens it if this screen hasn't been seen and it isn't turned off.
static func attach(scene: Node, id: String, pane_list: Array) -> Tutorial:
	var t := Tutorial.new()
	t.screen_id = id
	t.panes = pane_list
	t.name = "Tutorial"
	scene.add_child(t)
	if not is_off() and not _cfg().get_value("seen", id, false):
		t.open.call_deferred()
	return t


static func is_blocking() -> bool:
	return _open_count > 0 or _holds > 0 or Time.get_ticks_msec() < _release_at


static func any_open() -> bool:
	return _open_count > 0


## For other overlays: hold(true) while open, hold(false) when closed.
static func hold(on: bool) -> void:
	_holds = maxi(_holds + (1 if on else -1), 0)
	if not on:
		_release_at = Time.get_ticks_msec() + RELEASE_MS


static func was_seen(id: String) -> bool:
	return _cfg().get_value("seen", id, false)


static func is_off() -> bool:
	return _cfg().get_value("tutorial", "off", false)


## For a "show tutorials again" option.
static func reset() -> void:
	var cfg := ConfigFile.new()
	cfg.save(CFG)


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	return cfg


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	visible = false


func _exit_tree() -> void:
	if is_open():
		_open_count = maxi(_open_count - 1, 0)


func is_open() -> bool:
	return _index >= 0


func open() -> void:
	if is_open() or panes.is_empty():
		return
	_index = 0
	_open_count += 1
	visible = true
	Sfx.play("page")


func _close(skip_all: bool) -> void:
	if not is_open():
		return
	var cfg := _cfg()
	cfg.set_value("seen", screen_id, true)
	if skip_all:
		cfg.set_value("tutorial", "off", true)
	cfg.save(CFG)
	_index = -1
	_open_count = maxi(_open_count - 1, 0)
	_release_at = Time.get_ticks_msec() + RELEASE_MS
	visible = false
	Sfx.play("undock" if skip_all else "ui_click")
	closed.emit()


func _next() -> void:
	if _index >= panes.size() - 1:
		_close(false)
	else:
		_index += 1
		Sfx.play("page")


func _process(delta: float) -> void:
	_time += delta
	if is_open():
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open():
		if hotkey and _holds == 0 and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
			open()
			get_viewport().set_input_as_handled()
		return
	# Everything goes to the dialog while it is open.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E:
				_next()
			KEY_X:
				_close(true)
			KEY_ESCAPE, KEY_Q:
				_close(false)
	elif event is InputEventMouseMotion:
		_hover = _button_at(_canvas.get_local_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		match _button_at(_canvas.get_local_mouse_position()):
			"next":
				_next()
			"skip":
				_close(true)
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _button_at(p: Vector2) -> String:
	for id: String in _buttons:
		if (_buttons[id] as Rect2).has_point(p):
			return id
	return ""


# --- drawing ------------------------------------------------------------------------------

func _draw_canvas() -> void:
	if not is_open():
		return
	var pane: Dictionary = panes[_index]
	var hole: Rect2 = pane.get("rect", Rect2())
	_dim(hole)
	if hole.has_area():
		var blink := 0.55 + 0.45 * sin(_time * 6.0)
		_canvas.draw_rect(hole.grow(1), Color(ACCENT, blink), false, 1.0)

	var font := UiFont.font()
	var lines := _wrap(str(pane.get("body", "")), BOX_W - PAD * 2)
	var h := 26.0 + lines.size() * 10.0 + 22.0
	var box := Rect2(Vector2((480.0 - BOX_W) / 2.0, 0), Vector2(BOX_W, h))
	# Keep the box away from the highlighted area: below it if it is high up, above otherwise.
	if hole.has_area() and hole.get_center().y < 135.0:
		box.position.y = minf(hole.end.y + 8.0, 262.0 - h)
	elif hole.has_area():
		box.position.y = maxf(hole.position.y - h - 8.0, 8.0)
	else:
		box.position.y = (270.0 - h) / 2.0
	if hole.has_area() and box.intersects(hole):
		box.position.y = 262.0 - h if hole.get_center().y < 135.0 else 8.0
	_canvas.draw_rect(box.grow(2), Color(0, 0, 0, 0.6))
	_canvas.draw_rect(box, Color("10142a"))
	_canvas.draw_rect(box, ACCENT, false, 1.0)
	_canvas.draw_rect(Rect2(box.position, Vector2(box.size.x, 14)), Color("1d2a4a"))

	var x := box.position.x + PAD
	var y := box.position.y + 10.0
	_canvas.draw_string(font, Vector2(x, y), str(pane.get("title", "")).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9), ACCENT)
	var page := "%d/%d" % [_index + 1, panes.size()]
	_canvas.draw_string(font, Vector2(box.end.x - PAD - UiFont.width(page, 7), y), page,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b7390"))
	y += 15.0
	for line in lines:
		_canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(BODY), Color("e8ecf8"))
		y += 10.0

	# Buttons along the bottom edge.
	var by := box.end.y - 16.0
	var skip_text := "SKIP TUTORIAL [X]"
	var next_text := ("GOT IT" if _index == panes.size() - 1 else "NEXT >") + " [SPACE]"
	_buttons = {
		skip = Rect2(x - 2, by, UiFont.width(skip_text, 7) + 8, 12),
		next = Rect2(box.end.x - PAD - UiFont.width(next_text, 8) - 6, by, UiFont.width(next_text, 8) + 8, 12),
	}
	_button("skip", skip_text, 7, Color("9aa4b8"))
	_button("next", next_text, 8, Color("ffc640"))


func _button(id: String, text: String, size: int, color: Color) -> void:
	var r: Rect2 = _buttons[id]
	var hot := _hover == id or (id == "next" and fmod(_time, 1.2) < 0.8)
	_canvas.draw_rect(r, Color(color, 0.18 if hot else 0.08))
	_canvas.draw_rect(r, Color(color, 0.9 if hot else 0.5), false, 1.0)
	_canvas.draw_string(UiFont.font(), r.position + Vector2(4, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), color)


## Darken everything except `hole`.
func _dim(hole: Rect2) -> void:
	var c := Color(0, 0, 0, 0.55)
	if not hole.has_area():
		_canvas.draw_rect(Rect2(0, 0, 480, 270), c)
		return
	var h := hole.grow(2)
	_canvas.draw_rect(Rect2(0, 0, 480, h.position.y), c)
	_canvas.draw_rect(Rect2(0, h.end.y, 480, 270 - h.end.y), c)
	_canvas.draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), c)
	_canvas.draw_rect(Rect2(h.end.x, h.position.y, 480 - h.end.x, h.size.y), c)


func _wrap(text: String, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var test := word if line == "" else line + " " + word
			if UiFont.width(test, BODY) > max_w and line != "":
				out.append(line)
				line = word
			else:
				line = test
		out.append(line)
	return out
