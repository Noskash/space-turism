class_name RocketBoard
extends Node2D
## Full-screen rocket board (hangar overlay, opened at the rocket on the bay): the spacecraft's body
## seen flat and big, like a circuit board. The part in the player's hand rides on a cell cursor
## (WASD or mouse). SPACE / click on a cell:
##   part in hand -> empty cell = install, taken cell = swap (the old part comes into your hand);
##   empty hand  -> taken cell = take it out.
## Q closes; your hand keeps what it holds. Anyone can swap anyone's part (Overcooked chaos).
## The hangar owns the state (host-authoritative): this only shows it and asks for
## {type = "cell", cell = i}; the hangar calls show_state() whenever the state changes.

signal request(action: Dictionary)
signal close_requested

const AREA := Rect2(12, 30, 300, 224)     # the body is drawn here, integer-scaled
const SIDE := Rect2(318, 30, 150, 224)    # hand / cell / totals panel
const MAX_BODY := 212.0
const PCB := Color("0c1d17")
const TRACE := Color("163a2a")
const ACCENT := Color("48e2ec")

var design := {}
var held := ""                # part in the local player's hand ("" = empty)
var rocket_name := ""

var _cursor := 0
var _preview: ShipPreview
var _top: Node2D
var _scale := 3
var _time := 0.0
var _message := ""
var _message_time := 0.0


func _enter_tree() -> void:
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE (like the planner)


func _exit_tree() -> void:
	UiFont.max_level = 2


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview = ShipPreview.new()
	_preview.bare = true
	add_child(_preview)
	_top = Node2D.new()
	_top.draw.connect(_draw_top)
	add_child(_top)
	show_state(design, held)


func show_state(new_design: Dictionary, new_held: String) -> void:
	design = new_design
	held = new_held
	if _preview == null:
		return
	_preview.design = design
	_layout()


func say(text: String) -> void:
	_message = text
	_message_time = 2.2


## Integer scale + position so the body fills AREA; keeps the cursor on a real cell.
func _layout() -> void:
	var cls := DesignRules.class_info(design.get("ship_class", "balanced"))
	var body := DesignRules.texture(DesignRules.BASE_DIR + str(cls.get("body", "")))
	if body == null:
		return
	var size := Vector2(body.get_size())
	_scale = clampi(int(floorf(minf(MAX_BODY / size.y, (AREA.size.x - 12.0) / size.x))), 1, 6)
	_preview.scale = Vector2(_scale, _scale)
	_preview.position = (AREA.get_center() - (_preview.body_origin() + size / 2.0) * _scale).round()
	_cursor = clampi(_cursor, 0, maxi(_cells().size() - 1, 0))


func _cells() -> Array:
	return DesignRules.cells_of(design)


func _cell_rect(i: int) -> Rect2:
	var corners := _preview.upgrade_cells()
	if i < 0 or i >= corners.size():
		return Rect2()
	return Rect2(_preview.position + corners[i] * _scale, Vector2(ShipPreview.CELL, ShipPreview.CELL) * _scale)


# --- input -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_message_time = maxf(_message_time - delta, 0.0)
	if not Tutorial.is_blocking():
		if _pressed("leave"):
			close_requested.emit()
			return
		for pair: Array in [["left", Vector2.LEFT], ["right", Vector2.RIGHT], ["up", Vector2.UP], ["down", Vector2.DOWN]]:
			if _pressed(pair[0]):
				_move(pair[1])
		if _pressed("interact"):
			_act()
	queue_redraw()
	_top.queue_redraw()


func _input(event: InputEvent) -> void:
	if Tutorial.is_blocking():
		return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		var at := _cell_at(get_local_mouse_position())
		if at >= 0 and at != _cursor:
			_cursor = at
			Sfx.play("ui_hover")
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and at >= 0:
			_act()
			get_viewport().set_input_as_handled()


func _pressed(verb: String) -> bool:
	return Input.is_action_just_pressed(Controls.action("p1", verb))


func _cell_at(p: Vector2) -> int:
	for i in _cells().size():
		if _cell_rect(i).has_point(p):
			return i
	return -1


## Jump to the nearest cell that lies in direction `dir` from the current one.
func _move(dir: Vector2) -> void:
	var from := _cell_rect(_cursor).get_center()
	var best := -1
	var best_score := INF
	for i in _cells().size():
		var d := _cell_rect(i).get_center() - from
		if i == _cursor or d.length() < 1.0:
			continue
		var dot := d.normalized().dot(dir)
		if dot < 0.5:
			continue
		var score := d.length() * (2.0 - dot)
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		_cursor = best
		Sfx.play("ui_hover")


## What SPACE does on the current cell: [verb, ok].
func _verdict() -> Array:
	var cells := _cells()
	if cells.is_empty():
		return ["NO CELLS", false]
	var here := str(cells[_cursor])
	if held == "":
		return ["TAKE OUT", true] if here != "" else ["EMPTY - BRING A PART", false]
	var why := DesignRules.check_put(design, _cursor, held)
	if why != "":
		return [why, false]
	return ["SWAP" if here != "" else "INSTALL", true]


func _act() -> void:
	var v := _verdict()
	if not v[1]:
		say(str(v[0]))
		Sfx.play("denied")
		return
	request.emit({type = "cell", cell = _cursor})
	Sfx.play("toggle" if held != "" else "clank", 1.1)


# --- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(-8, -8, 496, 286), Color(0.01, 0.015, 0.04, 0.9))
	UiKit.frame(self, Rect2(4, 4, 472, 262), ACCENT)
	var bar := Rect2(7, 7, 466, 20)
	draw_rect(bar, UiKit.PANEL)
	draw_rect(Rect2(bar.position.x, bar.end.y, bar.size.x, 1), UiKit.INK)
	UiKit.icon(self, "ship", bar.position + Vector2(3, 2), 1, ACCENT)
	var cls := str(DesignRules.class_info(design.get("ship_class", "")).get("name", "")).to_upper()
	var cap := UiKit.keycap_size("Q", 7)
	var close_w := cap.x + 3 + UiKit.text_w("CLOSE", 6)
	UiKit.text(self, Vector2(bar.position.x + 23, bar.end.y - 5),
			UiKit.fit("ROCKET BOARD  -  %s SHIP ON %s" % [cls, rocket_name], 10, bar.size.x - 40 - close_w), 10, ACCENT)
	var kx := bar.end.x - 4 - close_w
	UiKit.keycap(self, Vector2(kx, bar.position.y + roundf((bar.size.y - cap.y) / 2.0)), "Q", 7)
	UiKit.text(self, Vector2(kx + cap.x + 3, bar.end.y - 6), "CLOSE", 6, UiKit.DIM, 0)
	# The board: dark green PCB with traces and pads behind the body.
	draw_rect(AREA, PCB)
	for x in range(int(AREA.position.x) + 6, int(AREA.end.x), 12):
		draw_rect(Rect2(x, AREA.position.y, 1, AREA.size.y), TRACE)
	for y in range(int(AREA.position.y) + 6, int(AREA.end.y), 12):
		draw_rect(Rect2(AREA.position.x, y, AREA.size.x, 1), TRACE)
	for x in range(int(AREA.position.x) + 6, int(AREA.end.x), 24):
		for y in range(int(AREA.position.y) + 6, int(AREA.end.y), 24):
			draw_rect(Rect2(x - 1, y - 1, 3, 3), Color("2a5a40"))
	draw_rect(AREA, UiKit.INK, false, 1.0)
	UiKit.panel(self, SIDE)


func _draw_top() -> void:
	var cells := _cells()
	var c := _top
	var held_ok := held != "" and DesignRules.check_put(design, _cursor, held) == ""
	for i in cells.size():
		var r := _cell_rect(i)
		var id := str(cells[i])
		if id == "":
			c.draw_rect(r.grow(-1), Color(0.03, 0.04, 0.08, 0.92))
			var col := UiKit.FAINT
			if held != "":
				col = CrewRoles.color(str(DesignRules.part(held).get("role", "")))
				col.a = 0.45 + 0.4 * sin(_time * 6.0) if DesignRules.check_put(design, i, held) == "" else 0.25
			c.draw_rect(r.grow(-1), col, false, 1.0)
			continue
		var role := str(DesignRules.part(id).get("role", ""))
		c.draw_rect(r.grow(-1), Color(CrewRoles.color(role).darkened(0.75), 0.95))
		c.draw_rect(r.grow(-1), CrewRoles.color(role), false, 2.0)
		_draw_icon(c, id, r.get_center(), r.size.x - 4.0, Color.WHITE)
	if cells.is_empty():
		return
	# Cursor + the part in hand riding on it.
	var cr := _cell_rect(_cursor)
	var blink := fmod(_time, 0.5) < 0.32
	c.draw_rect(cr.grow(2), (UiKit.GOOD if held_ok or (held == "" and str(cells[_cursor]) != "") else Color.WHITE)
			if blink else Color(1, 1, 1, 0.35), false, 2.0)
	if held != "":
		var at := cr.get_center() + Vector2(10, 10 + roundf(2.0 * sin(_time * 5.0)))
		c.draw_rect(Rect2(at - Vector2(17, 13), Vector2(36, 32)), Color(0, 0, 0, 0.35))   # drop shadow
		_draw_icon(c, held, at - Vector2(2, 2), 34.0, Color.WHITE)
	_draw_side(c, cells)
	if _message_time > 0.0:
		var w := UiKit.text_w(_message, 8) + 12
		var h := UiKit.line_h(8) + 6
		var mr := Rect2(roundf(AREA.get_center().x - w / 2.0), AREA.end.y - h - 6, roundf(w), h)
		UiKit.panel(c, mr, UiKit.PANEL_DARK, UiKit.WARN)
		UiKit.text_c(c, mr.get_center().x, mr.end.y - 5, _message, 8, UiKit.WARN, 0)


## A part's 32 px icon, centred at `center`, shown only if it fits `room` (else its small mounted sprite).
func _draw_icon(c: CanvasItem, id: String, center: Vector2, room: float, mod: Color) -> void:
	var p := DesignRules.part(id)
	var tex := DesignRules.texture(str(p.get("dir", "")) + str(p.get("icon", "")))
	if tex == null or tex.get_width() > room:
		tex = DesignRules.texture(str(p.get("dir", "")) + str(p.get("mounted", "")))
	if tex:
		c.draw_texture(tex, (center - tex.get_size() / 2.0).round(), mod)


func _draw_side(c: CanvasItem, cells: Array) -> void:
	var x := SIDE.position.x + 6
	var w := SIDE.size.x - 12
	var y := SIDE.position.y + 12
	UiKit.text(c, Vector2(x, y), "IN YOUR HAND", 6, UiKit.DIM, 0)
	y += 4
	if held == "":
		y += UiKit.line_h(7)
		UiKit.text(c, Vector2(x, y), "EMPTY", 7, UiKit.FAINT, 0)
		y += 6
	else:
		y = _part_block(c, held, x, y, w)
	y += 6
	UiKit.text(c, Vector2(x, y), "THIS CELL", 6, UiKit.DIM, 0)
	var here := str(cells[_cursor])
	y += UiKit.line_h(7)
	if here == "":
		UiKit.text(c, Vector2(x, y), "EMPTY", 7, UiKit.FAINT, 0)
	else:
		var role := str(DesignRules.part(here).get("role", ""))
		UiKit.text(c, Vector2(x, y), UiKit.fit(str(DesignRules.part(here).get("name", here)).to_upper(), 7, w - 26), 7, Color.WHITE, 0)
		UiKit.text_r(c, x + w, y, CrewRoles.tag(role), 7, CrewRoles.color(role), 0)
	y += UiKit.line_h(8) + 2
	var v := _verdict()
	var scap := UiKit.keycap_size("SPACE", 6)
	UiKit.keycap(c, Vector2(x, y - scap.y + 2), "SPACE", 6, v[1])
	for line in UiKit.wrap(str(v[0]), 7, w - scap.x - 4).slice(0, 2):
		UiKit.text(c, Vector2(x + scap.x + 4, y), line, 7, UiKit.GOOD if v[1] else UiKit.BAD, 0)
		y += UiKit.line_h(7)
	# Shared totals (same numbers as the wall board).
	var ev := DesignRules.evaluate(design)
	var lift := float(ev.launcher.get("capacity_kg", 0)) * DesignRules.LIFT_MARGIN
	var rows := [
		["MASS", "%d/%d KG" % [ev.mass, ev.mass_limit], ev.mass <= ev.mass_limit],
		["POWER", "%s%d W" % ["+" if ev.net_w >= 0 else "", ev.net_w], ev.net_w >= 0],
		["BUDGET", "$%dM LEFT" % int(ev.budget - ev.cost), ev.cost <= ev.budget],
		["SLOTS", "%d/%d" % [ev.slots_used, ev.slots], true],
		["LIFT", "%d KG MAX" % lift, ev.mass <= lift],
	]
	var lh := UiKit.line_h(6) + 1
	var ty := maxf(y + 4, SIDE.end.y - 22 - lh * rows.size())
	for row: Array in rows:
		ty += lh
		UiKit.text(c, Vector2(x, ty), row[0], 6, UiKit.DIM, 0)
		UiKit.text_r(c, x + w, ty, row[1], 6, Color.WHITE if row[2] else UiKit.BAD, 0)
	UiKit.text(c, Vector2(x, SIDE.end.y - 12), UiKit.fit("WASD / MOUSE  MOVE", 6, w), 6, UiKit.DIM, 0)
	UiKit.text(c, Vector2(x, SIDE.end.y - 4), UiKit.fit("SPACE / CLICK  PUT, TAKE", 6, w), 6, UiKit.DIM, 0)


## Icon + name + KG / W / $ of a part; returns the y below it.
func _part_block(c: CanvasItem, id: String, x: float, y: float, w: float) -> float:
	var p := DesignRules.part(id)
	var role := str(p.get("role", ""))
	var icon := DesignRules.texture(str(p.get("dir", "")) + str(p.get("icon", "")))
	if icon:
		c.draw_texture(icon, Vector2(x, y + 2))
	var tx := x + 36
	var lh := UiKit.line_h(6)
	var ty := y + lh + 1
	for line in UiKit.wrap(str(p.get("name", id)).to_upper(), 7, w - 36).slice(0, 2):
		UiKit.text(c, Vector2(tx, ty), line, 7, Color.WHITE, 0)
		ty += UiKit.line_h(7)
	UiKit.text(c, Vector2(tx, ty), CrewRoles.tag(role), 6, CrewRoles.color(role), 0)
	ty += lh
	var pw := int(p.get("power_w", 0))
	UiKit.text(c, Vector2(tx, ty), "%dKG %s%dW $%dM" % [int(p.get("mass_kg", 0)), "+" if pw >= 0 else "", pw, int(p.get("cost", 0))],
			6, UiKit.TEXT, 0)
	return maxf(ty, y + 36) + 2
