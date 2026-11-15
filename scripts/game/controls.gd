class_name Controls
extends RefCounted
## Keyboard schemes for local players. Actions are registered in code (not in project.godot)
## so the input map never causes merge conflicts.
##
## Physical keycodes are used so the keys stay in the same place on any layout
## (a Russian layout still moves with the WASD keys).

const SCHEMES := {
	"p1": {
		"left": [KEY_A, KEY_LEFT],
		"right": [KEY_D, KEY_RIGHT],
		"up": [KEY_W, KEY_UP],
		"down": [KEY_S, KEY_DOWN],
		"interact": [KEY_SPACE],
		"leave": [KEY_Q],  # leave a station / close a minigame or dialog (A/D are station choices)
		"radar": [KEY_E],  # Bridge radar on/off while docked there
		"run": [KEY_SHIFT],  # hold while walking
		"skin": [KEY_K],  # cycle skins (until the character screen picks them)
		"tasks": [KEY_TAB],  # cruise HUD: fold the task list -> hide the whole top -> show it again
		"inspect": [KEY_F],  # hangar: read the part / stand / console in reach
		"ping": [KEY_G],  # cruise: call out to the crew ("HELP!", "NEED ENGINEER", "FIRE HERE!")
	},
}


static func action(scheme: String, verb: String) -> StringName:
	return StringName("%s_%s" % [scheme, verb])


static var _key_names := {}   # "scheme/verb" -> label (UI asks every frame)


## Label of the first key bound to `verb` ("SPACE", "TAB", ...), for key caps in the UI.
static func key_name(scheme: String, verb: String) -> String:
	var id := scheme + "/" + verb
	if not _key_names.has(id):
		var keys: Array = SCHEMES.get(scheme, {}).get(verb, [])
		if keys.is_empty():
			return "?"
		var code := KEY_NONE
		if DisplayServer.get_name() != "headless":  # (headless: no keyboard layout)
			code = DisplayServer.keyboard_get_keycode_from_physical(keys[0])
		_key_names[id] = OS.get_keycode_string(code if code != KEY_NONE else keys[0]).to_upper()
	return _key_names[id]


## Safe to call more than once.
static func ensure_actions() -> void:
	for scheme: String in SCHEMES:
		var verbs: Dictionary = SCHEMES[scheme]
		for verb: String in verbs:
			var name := action(scheme, verb)
			if InputMap.has_action(name):
				continue
			InputMap.add_action(name)
			for key: Key in verbs[verb]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(name, event)
