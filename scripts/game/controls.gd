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
		"interact": [KEY_SPACE, KEY_E],
		"run": [KEY_SHIFT],  # hold while walking
		"skin": [KEY_K],  # cycle skins (until the character screen picks them)
		"tasks": [KEY_TAB],  # fold / unfold the HUD task list
		"close": [KEY_Q],  # close a station minigame (shields, safe mode)
	},
}


static func action(scheme: String, verb: String) -> StringName:
	return StringName("%s_%s" % [scheme, verb])


## Label of the first key bound to `verb` ("SPACE", "TAB", ...), for key caps in the UI.
static func key_name(scheme: String, verb: String) -> String:
	var keys: Array = SCHEMES.get(scheme, {}).get(verb, [])
	if keys.is_empty():
		return "?"
	var code := DisplayServer.keyboard_get_keycode_from_physical(keys[0])
	return OS.get_keycode_string(code if code != KEY_NONE else keys[0]).to_upper()


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
