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
	},
}


static func action(scheme: String, verb: String) -> StringName:
	return StringName("%s_%s" % [scheme, verb])


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
