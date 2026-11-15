class_name HangarLighting
extends ColorRect
## Full-map lighting pass for the assembly hangar (shaders/hangar_light.gdshader).
## Add it to the hangar AFTER the gantry overlay at z 4 (lights everything below), under the prompts (z 5).
## update() is called every frame with what the room is doing: lamps flicker, the silo glows, screens
## shimmer, the radio pulses with the beat, the door beacon spins (green + fast once everyone is READY).

const SHADER := preload("res://shaders/hangar_light.gdshader")
const LAMP := Color(1.0, 0.86, 0.66)
const BEACON_AMBER := Color(1.0, 0.62, 0.15)
const BEACON_GREEN := Color(0.35, 1.0, 0.5)

## Fixed lights: [x, y, radius, strength, colour, flicker]. flicker: 0 none, 1 lamp, 2 fire, 3 screen.
const LIGHTS := [
	[82, 112, 100, 0.42, LAMP, 1],                 # ceiling lamps
	[398, 112, 100, 0.42, LAMP, 1],
	[240, 222, 120, 0.42, LAMP, 1],
	[58, 188, 72, 0.24, LAMP, 1],
	[240, 142, 90, 0.55, Color(1.0, 0.5, 0.22), 2],   # launch silo
	[238, 26, 80, 0.36, Color(0.35, 0.8, 1.0), 3],    # status board
	[80, 50, 80, 0.30, Color("ff9a3c"), 0],       # role shelves (UiKit.ROLE_COLORS)
	[364, 50, 66, 0.30, Color("5cf07a"), 0],
	[68, 232, 70, 0.32, Color("b77bff"), 0],
	[428, 232, 60, 0.30, Color("4fd8ff"), 0],
	[24, 59, 34, 0.5, Color("5cf07a"), 3],       # computer screens (HangarDecor)
	[454, 77, 34, 0.5, Color("4fd8ff"), 3],
	[400, 174, 36, 0.36, Color("4fd8ff"), 3],     # planner console
	[82, 158, 30, 0.30, Color("ffd8a0"), 3],      # suit-up locker mirror lamp (HangarDecor)
]
const RADIO_LIGHT := [375, 92, 36]

var _mat := ShaderMaterial.new()


func _init() -> void:
	name = "Lighting"
	size = Vector2(480, 270)
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4
	_mat.shader = SHADER
	material = _mat


## t = scene time, all_ready = every player stands READY, beat = 0..1 radio pulse (0 = off).
func update(t: float, all_ready: bool, beat: float) -> void:
	var pos := PackedVector4Array()
	var cols := PackedVector4Array()
	for i in LIGHTS.size():
		var l: Array = LIGHTS[i]
		var s: float = l[3]
		match int(l[5]):
			1: s *= 0.94 + 0.06 * sin(t * 1.7 + i * 2.3)
			2: s *= 0.82 + 0.12 * sin(t * 7.0) * sin(t * 3.1 + 1.0) + 0.06 * sin(t * 13.0)
			3: s *= 0.9 + 0.1 * (1.0 if fmod(t * 3.0 + i * 0.37, 1.0) < 0.85 else 0.0)
		var c: Color = l[4]
		pos.append(Vector4(l[0], l[1], l[2], s))
		cols.append(Vector4(c.r, c.g, c.b, 1.0))
	if beat > 0.0:
		pos.append(Vector4(RADIO_LIGHT[0], RADIO_LIGHT[1], RADIO_LIGHT[2], 0.16 + 0.4 * beat))
		cols.append(Vector4(1.0, 0.55, 0.75, 1.0))
	_mat.set_shader_parameter("lights", pos)
	_mat.set_shader_parameter("light_colors", cols)
	_mat.set_shader_parameter("light_count", pos.size())
	_mat.set_shader_parameter("time", t)
	var bc := BEACON_GREEN if all_ready else BEACON_AMBER
	_mat.set_shader_parameter("beacon_angle", t * (5.0 if all_ready else 1.8))
	_mat.set_shader_parameter("beacon_color", Vector4(bc.r, bc.g, bc.b, 0.42 if all_ready else 0.28))


## Beacon dome over the launch door (drawn by the hangar under the lighting, so it gets lit too).
static func draw_beacon(ci: CanvasItem, t: float, all_ready: bool) -> void:
	var c := BEACON_GREEN if all_ready else BEACON_AMBER
	var flash := fmod(t * (5.0 if all_ready else 1.8) / TAU, 1.0) < 0.5
	ci.draw_rect(Rect2(462, 0, 9, 6), UiKit.INK)
	ci.draw_rect(Rect2(463, 1, 7, 4), c.darkened(0.15) if flash else c.darkened(0.45))
	ci.draw_rect(Rect2(464, 1, 2, 1), Color(1, 1, 1, 0.8))
