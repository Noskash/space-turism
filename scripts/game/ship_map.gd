class_name ShipMap
extends Node2D
## The ship interior: map sprite, wall collision and stations, all built from ship_layout.json.
##
## Collision: everything that is not inside a room or a door is a wall, and every obstacle
## (racks, consoles, holo-table...) is solid. The map is rasterised into CELL-sized cells and
## blocked cells are merged into as few rectangles as possible for the StaticBody2D.

const LAYOUT_PATH := "res://sprites/lab_assets/ship_layout.json"
const MAP_TEXTURE_PATH := "res://sprites/lab_assets/maps/ship_480x270_nocrew.png"
const CELL := 2
const WALL_LAYER := 1

## Where crew appear: around the coffee corner of the Mission Hub.
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(190, 200), Vector2(200, 230), Vector2(290, 200), Vector2(285, 230),
]

## Draw wall rectangles on top of the map (toggle in the inspector to check collision).
@export var debug_draw_walls := false

var layout: Dictionary = {}
var stations: Array[Station] = []
var _wall_rects: Array[Rect2] = []


func _ready() -> void:
	layout = _load_layout()
	if layout.is_empty():
		return
	var sprite := Sprite2D.new()
	sprite.name = "Map"
	sprite.texture = load(MAP_TEXTURE_PATH)
	sprite.centered = false
	sprite.show_behind_parent = true  # so debug_draw_walls shows on top of the map
	add_child(sprite)
	_build_walls()
	_build_stations()


func spawn_point(index: int) -> Vector2:
	return SPAWN_POINTS[index % SPAWN_POINTS.size()]


## Closest station whose interact radius contains `point`, or null.
func station_at(point: Vector2) -> Station:
	var best: Station = null
	var best_distance := INF
	for station in stations:
		var d := point.distance_to(station.global_position)
		if station.can_reach(point) and d < best_distance:
			best = station
			best_distance = d
	return best


func station_for_role(role: String) -> Station:
	for station in stations:
		if station.role == role:
			return station
	return null


func _load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_error("ShipMap: cannot open %s" % LAYOUT_PATH)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is not Dictionary:
		push_error("ShipMap: %s is not a JSON object" % LAYOUT_PATH)
		return {}
	return data


func _build_stations() -> void:
	for data: Dictionary in layout.get("stations", []):
		var station := Station.new()
		station.setup(data)
		add_child(station)
		stations.append(station)


func _build_walls() -> void:
	var cols := int(layout.base_size[0]) / CELL
	var rows := int(layout.base_size[1]) / CELL

	# 1 = blocked. Start fully blocked, carve out rooms and doors, then add obstacles back.
	var grid: Array[PackedByteArray] = []
	for y in rows:
		var row := PackedByteArray()
		row.resize(cols)
		row.fill(1)
		grid.append(row)
	for key in ["rooms", "doors"]:
		for r: Dictionary in layout.get(key, []):
			_paint(grid, _rect(r), 0)
	for r: Dictionary in layout.get("obstacles", []):
		_paint(grid, _rect(r), 1)

	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	for cell_rect in _merge_blocked(grid, cols, rows):
		var rect := Rect2(cell_rect.position * CELL, cell_rect.size * CELL)
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = rect.get_center()
		body.add_child(collider)
		_wall_rects.append(rect)
	queue_redraw()


## Sets every cell whose centre lies inside `rect`.
func _paint(grid: Array[PackedByteArray], rect: Rect2, value: int) -> void:
	var cols := grid[0].size()
	var x0 := clampi(floori(rect.position.x / CELL), 0, cols)
	var x1 := clampi(ceili(rect.end.x / CELL), 0, cols)
	var y0 := clampi(floori(rect.position.y / CELL), 0, grid.size())
	var y1 := clampi(ceili(rect.end.y / CELL), 0, grid.size())
	for y in range(y0, y1):
		for x in range(x0, x1):
			if rect.has_point(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)):
				grid[y][x] = value


## Horizontal runs of blocked cells, stacked downwards while the run below has the same span.
func _merge_blocked(grid: Array[PackedByteArray], cols: int, rows: int) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var open := {}  # Vector2i(x_start, x_end) -> index in rects still growing downwards
	for y in rows:
		var still_open := {}
		var x := 0
		while x < cols:
			if grid[y][x] == 0:
				x += 1
				continue
			var start := x
			while x < cols and grid[y][x] == 1:
				x += 1
			var span := Vector2i(start, x)
			if open.has(span):
				var i: int = open[span]
				var grown := rects[i]
				grown.size.y += 1
				rects[i] = grown
				still_open[span] = i
			else:
				rects.append(Rect2i(start, y, x - start, 1))
				still_open[span] = rects.size() - 1
		open = still_open
	return rects


static func _rect(d: Dictionary) -> Rect2:
	return Rect2(float(d.x), float(d.y), float(d.w), float(d.h))


func _draw() -> void:
	if not debug_draw_walls:
		return
	for rect in _wall_rects:
		draw_rect(rect, Color(1, 0, 0, 0.35))
