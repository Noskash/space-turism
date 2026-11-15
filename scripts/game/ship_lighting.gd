class_name ShipLighting
extends Node2D
## Lighting for the cruise: where we are on the route decides where the Sun is and how bright.
##
## SIMPLIFIED: route progress p = day / 259 (Hohmann cruise). Sun distance follows the transfer
## ellipse, r = 1.0 AU at Earth -> 1.52 AU at Mars, so sunlight = 1/r^2 (100% -> 43%).
## The Sun's direction on screen sweeps from the ship's left/behind to upper-right as the route
## curves around it (exaggerated so you can see it). Earthshine fades behind, Mars glow grows.
##
## Layers: shadows (between map and crew: walls, props and crew cast shadows away from the Sun),
## then two full-screen shaders over everything: light_shade (multiply) and light_glow (add).
## Low battery -> red emergency lighting; solar storm -> shimmer from the Sun's side.

const CRUISE_DAYS := 259.0   # sandbox; a campaign mission sends its own state.cruise_days


## Share of the transfer flown (0 = Earth, 1 = Mars), from the sim state.
static func progress_of(state: Dictionary) -> float:
	var days := float(state.get("cruise_days", 0.0))
	return float(state.get("day", 0.0)) / (days if days > 0.0 else CRUISE_DAYS)
const TRANSFER_A := 1.26          # AU, semi-major axis of the Earth -> Mars transfer
const TRANSFER_E := 0.206
const SUN_ANGLE_START := deg_to_rad(165.0)   # screen angle (y down): left, slightly below
const SUN_ANGLE_END := deg_to_rad(300.0)     # up-right
const CENTER := Vector2(240, 135)
const WALL_HEIGHT := 14.0
const PROP_HEIGHT := {"rack": 12.0, "comms-console": 6.0}
const SCREEN := Rect2(-12, -40, 504, 322)   # map coords; reaches above the map for the HUD band (UiKit.world_offset)

var progress := 0.0               # 0 at Earth .. 1 at Mars
var sun_dir := Vector2.LEFT       # towards the Sun, screen space
var sun_power := 1.0
var sun_au := 1.0

var _map: ShipMap
var _crew: Node2D
var _shadows: Node2D
var _shade: Node2D
var _glow: Node2D
var _shade_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _state := {}
var _t := 0.0
var _emergency := 0.0
var _storm := 0.0
var _blackout := 0.0
var _wave_t := -1.0          # radiation wave front, 0..1 across the ship (-1 = none)
var _static_shadows: Array[PackedVector2Array] = []
var _shadow_vec_cached := Vector2.INF
var _rng := RandomNumberGenerator.new()


func setup(game: Node2D, map: ShipMap, crew: Node2D) -> ShipLighting:
	_map = map
	_crew = crew
	name = "Lighting"
	_shadows = Node2D.new()
	_shadows.name = "Shadows"
	_shadows.draw.connect(_draw_shadows)
	game.add_child(_shadows)
	game.move_child(_shadows, map.get_index() + 1)

	_shade_mat = ShaderMaterial.new()
	_shade_mat.shader = load("res://shaders/light_shade.gdshader")
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = load("res://shaders/light_glow.gdshader")
	_shade = _full_screen(_shade_mat, 40)
	_glow = _full_screen(_glow_mat, 41)
	game.add_child(self)
	add_child(_shade)
	add_child(_glow)
	_set_progress(0.0)
	return self


func _full_screen(mat: ShaderMaterial, z: int) -> Node2D:
	var n := Node2D.new()
	n.material = mat
	n.z_index = z
	n.draw.connect(func() -> void: n.draw_rect(SCREEN, Color.WHITE))
	return n


func _ready() -> void:
	_rng.randomize()
	Events.state_changed.connect(func(s: Dictionary) -> void: _state = s)


func _set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	var theta := PI * progress
	sun_au = TRANSFER_A * (1.0 - TRANSFER_E * TRANSFER_E) / (1.0 + TRANSFER_E * cos(theta))
	sun_power = 1.0 / (sun_au * sun_au)
	sun_dir = Vector2.from_angle(lerp_angle(SUN_ANGLE_START, SUN_ANGLE_END, smoothstep(0.0, 1.0, progress)))


func _process(delta: float) -> void:
	_t += delta
	_set_progress(progress_of(_state))
	var power: float = _state.get("power", 100.0)
	_emergency = move_toward(_emergency, clampf((22.0 - power) / 14.0, 0.0, 1.0) * 0.55, delta)
	var storming := false
	for e: Dictionary in _state.get("events", []):
		if e.get("kind", "") == "solar_storm":
			storming = true
	_storm = move_toward(_storm, 1.0 if storming else 0.0, delta * 0.8)

	var warm := Color(1.0, 0.92, 0.75).lerp(Color(0.95, 0.9, 0.86), progress)
	_shade_mat.set_shader_parameter("sun_dir", sun_dir)
	_shade_mat.set_shader_parameter("sun_power", sun_power)
	_shade_mat.set_shader_parameter("ambient", Vector3(1.0, 1.0, 1.0).lerp(Vector3(0.94, 0.95, 1.04), progress))
	var cme: Dictionary = _state.get("cme", {})
	var blackout := 1.0 if float(_state.get("blackout", 0.0)) > 0.0 else 0.0
	_blackout = move_toward(_blackout, blackout, delta * (3.0 if blackout > 0.0 else 0.7))
	_wave_t = 1.0 - clampf(float(cme.get("time_left", 0.0)) / 6.0, 0.0, 1.0) if cme.get("phase", "") == "wave" else -1.0
	if cme.get("phase", "") == "warning":
		_emergency = maxf(_emergency, 0.25 + 0.15 * sin(_t * 8.0))
	_shade_mat.set_shader_parameter("emergency", maxf(_emergency, _blackout * 0.8))
	_shade_mat.set_shader_parameter("blackout", _blackout)
	_glow_mat.set_shader_parameter("wave", _wave_t)
	_glow_mat.set_shader_parameter("sun_dir", sun_dir)
	_shade_mat.set_shader_parameter("time", _t)
	_glow_mat.set_shader_parameter("sun_pos", CENTER + sun_dir * Vector2(330, 230))
	_glow_mat.set_shader_parameter("sun_power", sun_power)
	_glow_mat.set_shader_parameter("sun_color", Vector3(warm.r, warm.g, warm.b))
	_glow_mat.set_shader_parameter("earth_power", pow(1.0 - progress, 2.0))
	_glow_mat.set_shader_parameter("mars_power", smoothstep(0.35, 1.0, progress))
	_glow_mat.set_shader_parameter("storm", _storm)
	_glow_mat.set_shader_parameter("time", _t)
	_update_station_lights()
	_shadows.queue_redraw()


## Each station glows in its role colour; a pending ticket makes it pulse, offline flickers.
func _update_station_lights() -> void:
	var pos: Array[Vector4] = []
	var cols: Array[Vector4] = []
	var pending := {}
	for e: Dictionary in _state.get("events", []):
		pending[e.get("role", "")] = true
	var offline: Array = _state.get("offline", [])
	for st: Station in _map.stations:
		if pos.size() >= 8:
			break
		var c: Color = Station.ROLE_COLORS.get(st.role, Color.WHITE)
		var strength := 0.05 * (1.0 - _blackout)
		var radius := 26.0
		if st.role in offline:
			c = Color(1.0, 0.45, 0.2)
			strength = 0.12 if _rng.randf() < 0.3 else 0.0
		elif pending.has(st.role) and _blackout < 0.5:
			strength = 0.10 + 0.08 * sin(_t * 6.0)
			radius = 40.0
		pos.append(Vector4(st.position.x, st.position.y - 6.0, radius, strength))
		cols.append(Vector4(c.r, c.g, c.b, 1.0))
	while pos.size() < 8:
		pos.append(Vector4.ZERO)
		cols.append(Vector4.ZERO)
	_glow_mat.set_shader_parameter("light_count", _map.stations.size())
	_glow_mat.set_shader_parameter("lights", pos)
	_glow_mat.set_shader_parameter("light_colors", cols)


# --- shadows -------------------------------------------------------------------------------

## Shadow per unit of height: away from the Sun, foreshortened (3/4 view); longer when the
## light is weaker (as if lower), fainter too.
func _shadow_vec() -> Vector2:
	var away := -sun_dir
	return Vector2(away.x, away.y * 0.6) * lerpf(0.75, 1.1, 1.0 - sun_power)


func _draw_shadows() -> void:
	var v := _shadow_vec()
	if v.distance_to(_shadow_vec_cached) > 0.02:
		_shadow_vec_cached = v
		_build_static_shadows(v)
	var alpha := 0.42 * lerpf(0.6, 1.0, sun_power)
	var col := Color(0.02, 0.03, 0.08, alpha)
	for poly in _static_shadows:
		_shadows.draw_colored_polygon(poly, col)
	if _crew:
		for member in _crew.get_children():
			if member is Node2D and member.visible:
				_crew_shadow(member, v, alpha)


## Walls cast a strip into each room on the Sun's side; props cast a shadow off their far side.
func _build_static_shadows(v: Vector2) -> void:
	_static_shadows.clear()
	var layout: Dictionary = _map.layout
	for room: Dictionary in layout.get("rooms", []):
		var r := Rect2(room.x, room.y, room.w, room.h)
		# room minus itself shifted away from the Sun = the strip along the sunward walls (no holes)
		_static_shadows.append_array(Geometry2D.clip_polygons(_rect_poly(r), _rect_poly(Rect2(r.position + v * WALL_HEIGHT, r.size))))
	for ob: Dictionary in layout.get("obstacles", []):
		var r := Rect2(ob.x, ob.y, ob.w, ob.h)
		var h: float = PROP_HEIGHT.get(ob.get("kind", ""), 8.0)
		var pts := _rect_poly(r)
		pts.append_array(_rect_poly(Rect2(r.position + v * h, r.size)))
		var hull := Geometry2D.convex_hull(pts)
		_static_shadows.append_array(Geometry2D.clip_polygons(hull, _rect_poly(r)))


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Contact blob + the current animation frame as a black silhouette, sheared away from the Sun.
func _crew_shadow(member: Node2D, v: Vector2, alpha: float) -> void:
	var feet := member.position
	_shadows.draw_set_transform(feet + Vector2(0, -0.5), 0.0, Vector2(1.0, 0.45))
	_shadows.draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.28))
	_shadows.draw_set_transform_matrix(Transform2D.IDENTITY)
	var sprite: AnimatedSprite2D = null
	for child in member.get_children():
		if child is AnimatedSprite2D:
			sprite = child
			break
	if sprite == null or sprite.sprite_frames == null or not sprite.visible:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var size := tex.get_size()
	var rect := Rect2(sprite.offset - (size / 2.0 if sprite.centered else Vector2.ZERO), size)
	var dst := rect
	if sprite.flip_h:  # negative width mirrors the texture
		dst = Rect2(rect.position.x + size.x, rect.position.y, -size.x, size.y)
	var origin := member.position + sprite.position
	var foot_y := rect.end.y - 1.0
	var d := v * 1.1
	# (x, y) -> (x + d.x * (foot_y - y), foot_y + d.y * (foot_y - y)): flat on the floor.
	var xf := Transform2D(Vector2(1, 0), Vector2(-d.x, -d.y), Vector2(d.x * foot_y, foot_y * (1.0 + d.y)))
	_shadows.draw_set_transform_matrix(Transform2D(0.0, origin) * xf)
	_shadows.draw_texture_rect(tex, dst, false, Color(0, 0, 0.05, alpha * 1.4))
	_shadows.draw_set_transform_matrix(Transform2D.IDENTITY)
