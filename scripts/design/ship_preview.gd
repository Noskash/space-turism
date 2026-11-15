class_name ShipPreview
extends Node2D
## Draws a design (class body + base kit + upgrades) in a 160x128 box at the node's origin,
## placed exactly like sprites/upgrade_kit_assets/draw_upgrades.py assemble_loadout().

const SIZE := Vector2i(160, 128)
const CELL := 12
const PLATE := Color(56 / 255.0, 60 / 255.0, 82 / 255.0)  # "metalD" behind cell parts

var design := {}:
	set(value):
		design = value
		queue_redraw()
## Upgrade to blink on the ship (the part under the local cursor), "" = none.
var highlight := ""

var _time := 0.0


func _ready() -> void:
	DesignRules.preload_textures()


func _process(delta: float) -> void:
	_time += delta
	if highlight != "":
		queue_redraw()


func _draw() -> void:
	var cls := DesignRules.class_info(design.get("ship_class", "balanced"))
	var body := _tex(DesignRules.BASE_DIR + cls.get("body", ""))
	if body == null:
		return
	var upgrades: Array = design.get("upgrades", [])
	var bw := int(body.get_width())
	var bh := int(body.get_height())
	var ox := (SIZE.x - bw) / 2
	var oy := (SIZE.y - bh) / 2 - 2

	var wing := _mounted("solar_large" if "solar_large" in upgrades else "solar_small")
	if wing:
		var wy := oy + bh / 2 - int(wing.get_height()) / 2
		_draw_flipped(wing, Vector2(ox - wing.get_width(), wy))
		draw_texture(wing, Vector2(ox + bw, wy))
	if "magnetometer" in upgrades:
		draw_texture(_mounted("magnetometer"), Vector2(ox + bw - 3, oy + bh - 3))
	draw_texture(body, Vector2(ox, oy))
	var top := _mounted("antenna_high" if "antenna_high" in upgrades else "antenna_low")
	if top:
		draw_texture(top, Vector2(ox + bw / 2 - int(top.get_width()) / 2, oy - top.get_height() + 2))
	var engine := _mounted("engine_main")
	if engine:
		draw_texture(engine, Vector2(ox + bw / 2 - int(engine.get_width()) / 2, oy + bh - 1))
	var thr := _mounted("thrusters_basic")
	if thr:
		for p in [Vector2(ox - 1, oy - 1), Vector2(ox + bw - 3, oy - 1),
				Vector2(ox - 1, oy + bh - 3), Vector2(ox + bw - 3, oy + bh - 3)]:
			draw_texture(thr, p)

	var slots: Array[Dictionary] = []
	for cell: Dictionary in cls.get("cells", []):
		if cell.use == "upgrade_slot":
			slots.append(cell)
		else:
			_draw_centered(_mounted(cell.use), Vector2(ox + cell.x, oy + cell.y))

	for i in mini(upgrades.size(), slots.size()):
		var id: String = upgrades[i]
		var p := DesignRules.part(id)
		var at := Vector2(ox + slots[i].x, oy + slots[i].y)
		var frames: Dictionary = DesignRules.data().frames.get(p.get("role", ""), {})
		if p.get("mount", "") == "cell":
			draw_rect(Rect2(at + Vector2.ONE, Vector2(CELL - 2, CELL - 2)), PLATE)
			_draw_centered(_mounted(id), at)
			_draw_frame(frames.get("slot", ""), at)
		else:
			_draw_frame(frames.get("linked", ""), at)
		if id == highlight and fmod(_time, 0.5) < 0.3:
			draw_rect(Rect2(at - Vector2.ONE, Vector2(CELL + 2, CELL + 2)), Color.WHITE, false, 1.0)


## Top-left corners (local) of the class's upgrade cells, in the order upgrades fill them.
## The hangar uses them to light free cells and to find the installed part next to a player.
func upgrade_cells() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cls := DesignRules.class_info(design.get("ship_class", "balanced"))
	var body := _tex(DesignRules.BASE_DIR + cls.get("body", ""))
	if body == null:
		return out
	var ox := (SIZE.x - int(body.get_width())) / 2
	var oy := (SIZE.y - int(body.get_height())) / 2 - 2
	for cell: Dictionary in cls.get("cells", []):
		if cell.use == "upgrade_slot":
			out.append(Vector2(ox + cell.x, oy + cell.y))
	return out


func _mounted(id: String) -> Texture2D:
	var p := DesignRules.part(id)
	if p.is_empty():
		return null
	return _tex(p.dir + p.get("mounted", ""))


func _tex(path: String) -> Texture2D:
	return DesignRules.texture(path)


func _draw_centered(tex: Texture2D, cell_pos: Vector2) -> void:
	if tex:
		draw_texture(tex, cell_pos + Vector2((CELL - int(tex.get_width())) / 2, (CELL - int(tex.get_height())) / 2))


func _draw_frame(rel: String, at: Vector2) -> void:
	var tex := _tex(DesignRules.UPGRADE_DIR + rel) if rel != "" else null
	if tex:
		draw_texture(tex, at)


func _draw_flipped(tex: Texture2D, at: Vector2) -> void:
	draw_set_transform(at + Vector2(tex.get_width(), 0), 0.0, Vector2(-1, 1))
	draw_texture(tex, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO)
