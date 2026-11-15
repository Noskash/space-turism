class_name GameOver
extends CanvasLayer
## "MISSION LOST" when the sim sets state.lost (e.g. oxygen ran out). First the ship blows up
## (Vfx chain of explosions, DOOM s), then this layer grabs the last frame and breaks it into
## shards tumbling away into space, then the panel. Blocks gameplay input
## (Tutorial.hold). Offline: SPACE = redesign the ship, ESC = main menu. Co-op: ESC leaves the room.
## Reads state.lost from Events.state_changed, so every co-op peer shows it.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const DESIGNER_SCENE := "res://scenes/design/hangar.tscn"

var _reason := ""
var _canvas: Node2D
var _t := 0.0
const DOOM := 2.6               # = Vfx.DOOM_TIME: the explosions play before the ship breaks up
var _shards: Array[Dictionary] = []   # {pts (local), uv, c (centre), v, rot, spin}
var _shot: Texture2D
var _stars: Array[Vector3] = []


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_panel)
	add_child(_canvas)
	visible = false
	Events.state_changed.connect(func(s: Dictionary) -> void:
		if _reason == "" and s.get("lost", "") != "":
			_show(str(s.lost)))


func _show(reason: String) -> void:
	_reason = reason
	visible = true
	Tutorial.hold(true)
	Sfx.set_loop("hiss", false)
	Sfx.set_loop("engine", false)
	Sfx.play("brownout", 0.6)


func _exit_tree() -> void:
	if _reason != "":
		Tutorial.hold(false)


func _process(delta: float) -> void:
	if _reason == "":
		return
	var before := _t
	_t += delta
	if before < DOOM and _t >= DOOM:
		_break_up()
	for s in _shards:
		s.c += s.v * delta
		s.rot += s.spin * delta
	_canvas.queue_redraw()


## Grab the exploding ship from the screen and cut it into jagged shards flying apart.
func _break_up() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	_shot = ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 90:
		_stars.append(Vector3(rng.randf() * 480.0, rng.randf() * 270.0, rng.randf()))
	var cols := 5
	var rows := 3
	var grid := []   # jittered lattice points
	for y in rows + 1:
		var row := []
		for x in cols + 1:
			var p := Vector2(480.0 * x / cols, 270.0 * y / rows)
			if x > 0 and x < cols:
				p.x += rng.randf_range(-30, 30)
			if y > 0 and y < rows:
				p.y += rng.randf_range(-25, 25)
			row.append(p)
		grid.append(row)
	for y in rows:
		for x in cols:
			var quad: Array = [grid[y][x], grid[y][x + 1], grid[y + 1][x + 1], grid[y + 1][x]]
			var mid: Vector2 = (quad[0] + quad[2]) / 2.0 + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			for k in 4:   # each cell -> 4 triangles around a jittered middle = jagged shards
				var tri: Array = [quad[k], quad[(k + 1) % 4], mid]
				var c: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
				var pts := PackedVector2Array()
				var uv := PackedVector2Array()
				for q: Vector2 in tri:
					pts.append(q - c)
					uv.append(q / Vector2(480, 270))
				var out := (c - Vector2(240, 135)).normalized()
				_shards.append({pts = pts, uv = uv, c = c, rot = 0.0,
						v = out * rng.randf_range(25, 70) + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)),
						spin = rng.randf_range(-1.2, 1.2)})


func _input(event: InputEvent) -> void:
	if _reason == "" or _t < DOOM + 1.5 or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE, KEY_ENTER:
			if not Network.is_in_room():
				get_tree().change_scene_to_file(DESIGNER_SCENE)
		KEY_ESCAPE:
			if Network.is_in_room():
				Network.leave_room()
			get_tree().change_scene_to_file(MENU_SCENE)
	get_viewport().set_input_as_handled()


func _draw_panel() -> void:
	var c := _canvas
	if _t < DOOM:
		return   # the ship is still exploding underneath
	# Space with the wreck drifting apart.
	c.draw_rect(Rect2(-8, -8, 496, 286), Color("03040a"))
	for st in _stars:
		c.draw_rect(Rect2(Vector2(st.x, st.y), Vector2.ONE), Color(0.8, 0.85, 1.0, 0.3 + 0.5 * st.z))
	var burn := clampf(1.0 - (_t - DOOM) / 2.0, 0.0, 1.0)
	for s in _shards:
		c.draw_set_transform(s.c, s.rot)
		c.draw_colored_polygon(s.pts, Color(1, 1, 1).lerp(Color(1.0, 0.6, 0.3), burn * 0.5), s.uv, _shot)
		var edge: PackedVector2Array = s.pts.duplicate()
		edge.append(s.pts[0])
		c.draw_polyline(edge, Color(1.0, 0.55, 0.2, 0.9 * burn), 1.0)
	c.draw_set_transform(Vector2.ZERO)
	if _t < DOOM + 0.25:   # the final flash fading out
		c.draw_rect(Rect2(-8, -8, 496, 286), Color(1, 0.95, 0.85, 1.0 - (_t - DOOM) / 0.25))
	var k := clampf((_t - DOOM - 0.9) / 0.8, 0.0, 1.0)
	if k <= 0.0:
		return
	c.draw_rect(Rect2(0, 0, 480, 270), Color(0.05, 0.0, 0.0, 0.75 * k))
	var box := Rect2(90, 80, 300, 110)
	c.draw_rect(box, Color(0.06, 0.03, 0.05, k))
	c.draw_rect(box, Color(1.0, 0.3, 0.3, k), false, 1.0)
	_centered("MISSION LOST", 112, 18, Color(1.0, 0.35, 0.3, k))
	var lines := _reason.split(" - ")
	for i in lines.size():
		_centered(lines[i].strip_edges().to_upper(), 132 + i * 11, 9, Color(1, 1, 1, k))
	_centered("A tougher hull (Heavy class, Whipple shield) means fewer breaches.", 160, 7, Color(0.6, 0.65, 0.75, k))
	var keys := "ESC: LEAVE" if Network.is_in_room() else "SPACE: REDESIGN THE SHIP     ESC: MAIN MENU"
	if _t > DOOM + 1.5:
		_centered(keys, 180, 8, Color("ffc640") if fmod(_t, 1.2) < 0.8 else Color("9a8040"))


func _centered(text: String, y: float, size: int, col: Color) -> void:
	_canvas.draw_string(UiFont.font(), Vector2(roundf(240 - UiFont.width(text, size) / 2.0), y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), col)
