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
	UiKit.setup_canvas(_canvas)
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


# --- drawing (UI kit) ------------------------------------------------------------------------

func _draw_canvas() -> void:
	if not is_open():
		return
	var c := _canvas
	var pane: Dictionary = panes[_index]
	var hole: Rect2 = pane.get("rect", Rect2())
	_dim(hole)
	if hole.has_area():
		# Chunky blinking frame around the highlighted part of the screen.
		var col := UiKit.WARN if fmod(_time, 0.5) < 0.32 else Color(UiKit.WARN, 0.35)
		var h := hole.grow(1)
		c.draw_rect(Rect2(h.position.x - 1, h.position.y - 1, h.size.x + 2, 2), col)
		c.draw_rect(Rect2(h.position.x - 1, h.end.y - 1, h.size.x + 2, 2), col)
		c.draw_rect(Rect2(h.position.x - 1, h.position.y - 1, 2, h.size.y + 2), col)
		c.draw_rect(Rect2(h.end.x - 1, h.position.y - 1, 2, h.size.y + 2), col)

	var box_w := minf(BOX_W * UiFont.scale(), 440.0)
	var lines := UiKit.wrap(str(pane.get("body", "")), BODY, box_w - PAD * 2)
	var title_h := UiKit.line_h(9) + 6
	var line_h := UiKit.line_h(BODY)
	var btn_h := UiKit.keycap_size("X", 7).y + 6
	var h := title_h + 6 + lines.size() * line_h + 6 + btn_h + 6
	var box := Rect2(Vector2(roundf((480.0 - box_w) / 2.0), 0), Vector2(roundf(box_w), roundf(h)))
	# Keep the box away from the highlighted area: below it if it is high up, above otherwise.
	if hole.has_area() and hole.get_center().y < 135.0:
		box.position.y = minf(hole.end.y + 8.0, 266.0 - h)
	elif hole.has_area():
		box.position.y = maxf(hole.position.y - h - 8.0, 4.0)
	else:
		box.position.y = roundf((270.0 - h) / 2.0)
	if hole.has_area() and box.intersects(hole):
		box.position.y = 266.0 - h if hole.get_center().y < 135.0 else 4.0
	box.position.y = roundf(box.position.y)
	UiKit.frame(c, box, ACCENT)
	# Title bar.
	var x := box.position.x + PAD
	var bar := Rect2(box.position + Vector2(3, 3), Vector2(box.size.x - 6, title_h))
	c.draw_rect(bar, UiKit.PANEL)
	c.draw_rect(Rect2(bar.position.x, bar.end.y, bar.size.x, 1), UiKit.INK)
	UiKit.text(c, Vector2(x, bar.end.y - 4), str(pane.get("title", "")).to_upper(), 9, ACCENT)
	UiKit.text_r(c, box.end.x - PAD, bar.end.y - 4, "%d/%d" % [_index + 1, panes.size()], 7, UiKit.DIM, 0)
	var y := bar.end.y + 5
	for line in lines:
		y += line_h
		UiKit.text(c, Vector2(x, y - 2), line, BODY, UiKit.TEXT, 0)

	# Buttons along the bottom edge: [X] SKIP TUTORIAL ........ NEXT > [SPACE]
	var by := box.end.y - btn_h - 5
	var last := _index == panes.size() - 1
	_buttons = {
		skip = _button(Vector2(x - 2, by), "X", "SKIP TUTORIAL", 7, UiKit.DIM, false, btn_h),
	}
	var next_label := "GOT IT" if last else "NEXT >"
	var next_w := _button_width("SPACE", next_label, 8)
	_buttons.next = _button(Vector2(box.end.x - PAD - next_w + 2, by), "SPACE", next_label, 8, UiKit.WARN, true, btn_h)


func _button_width(key: String, label: String, size: int) -> float:
	return 4 + UiKit.keycap_size(key, 7).x + 4 + UiKit.text_w(label, size) + 5


## Button: key cap + label in a raised block; lights up on hover (the primary one pulses).
func _button(pos: Vector2, key: String, label: String, size: int, color: Color, primary: bool, h: float) -> Rect2:
	var r := Rect2(pos, Vector2(roundf(_button_width(key, label, size)), h))
	var id := "next" if primary else "skip"
	var hot := _hover == id or (primary and fmod(_time, 1.2) < 0.8)
	UiKit.panel(_canvas, r, UiKit.PANEL if hot else UiKit.PANEL_DARK, color if hot else UiKit.FAINT)
	var cap := UiKit.keycap(_canvas, Vector2(r.position.x + 4, r.position.y + 3), key, 7)
	UiKit.text(_canvas, Vector2(cap.end.x + 4, r.end.y - 4), label, size, color, 0)
	return r


## Darken everything except `hole`.
func _dim(hole: Rect2) -> void:
	var c := Color(0.01, 0.02, 0.06, 0.6)
	if not hole.has_area():
		_canvas.draw_rect(Rect2(0, 0, 480, 270), c)
		return
	var h := hole.grow(2)
	_canvas.draw_rect(Rect2(0, 0, 480, h.position.y), c)
	_canvas.draw_rect(Rect2(0, h.end.y, 480, 270 - h.end.y), c)
	_canvas.draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), c)
	_canvas.draw_rect(Rect2(h.end.x, h.position.y, 480 - h.end.x, h.size.y), c)
