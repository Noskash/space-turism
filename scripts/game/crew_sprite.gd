class_name CrewSprite
extends AnimatedSprite2D
## Animated crew sprite built from a 16x16 crew sheet described in skins.json
## (8 cols x 4 rows, feet anchor 8,15). The parent node's origin is the feet.

const SKINS_DIR := "res://sprites/crew_skins/"
const MANIFEST_PATH := SKINS_DIR + "skins.json"
const FPS := {"idle": 3.0, "walk": 8.0, "work": 6.0, "alarm": 6.0}

static var _manifest := {}
static var _cache := {}  # skin name -> SpriteFrames


static func skin_names() -> Array:
	return _load_manifest().get("skins", {}).keys()


static func has_skin(skin: String) -> bool:
	return _load_manifest().get("skins", {}).has(skin)


## "up" / "down" / "left" / "right" for a facing vector.
static func dir_name(facing: Vector2) -> String:
	if absf(facing.x) > absf(facing.y):
		return "right" if facing.x > 0 else "left"
	return "down" if facing.y >= 0 else "up"


static func frames_for(skin: String) -> SpriteFrames:
	if _cache.has(skin):
		return _cache[skin]
	var manifest := _load_manifest()
	var info: Dictionary = manifest.get("skins", {}).get(skin, {})
	if info.is_empty():
		push_error("CrewSprite: unknown skin '%s'" % skin)
		return null
	var sheet: Texture2D = load(SKINS_DIR + str(info.sheet))
	var size := Vector2(manifest.frame_size[0], manifest.frame_size[1])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var animations: Dictionary = manifest.animations
	for anim: String in animations:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS.get(anim.get_slice("_", 0), 6.0))
		for cell: Array in animations[anim]:  # [row, col]
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2(cell[1], cell[0]) * size, size)
			frames.add_frame(anim, atlas)
	_cache[skin] = frames
	return frames


static func _load_manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST_PATH)
		var data: Variant = JSON.parse_string(text)
		if data is Dictionary:
			_manifest = data
		else:
			push_error("CrewSprite: cannot read %s" % MANIFEST_PATH)
	return _manifest


func set_skin(skin: String) -> void:
	sprite_frames = frames_for(skin)
	centered = false
	offset = Vector2(-8, -15)  # feet anchor -> node origin
	play(&"idle_down")


## Picks the animation: `special` ("work_up", "work_down", "alarm") wins over walk/idle.
func show_state(facing: Vector2, moving: bool, special := "", running := false) -> void:
	speed_scale = 1.6 if running and moving and special == "" else 1.0
	var anim := special
	if anim == "":
		anim = ("walk_" if moving else "idle_") + dir_name(facing)
	if animation != anim:
		play(anim)
