extends Node
## FAKE MISSION — stand-in for Person A's Mission.gd so the ship map, stations and HUD
## can be built and tested now. Same public API as the contract in CLAUDE.md:
##   start(design), tick(dt), predict_path() -> PackedVector2Array
## When the real Mission.gd lands, swap the script on the "Mission" node and delete this file.

const DAYS_PER_SECOND := 2.9  # ~259-day cruise in ~90 s

var state := {}
var _emit_timer := 0.0


func start(design: Dictionary) -> void:
	state = {
		day = 0.0,
		power = 100.0,
		fuel = 100.0,
		data = 0.0,
		last_action = "",
		design = design,
	}
	if not Events.action_requested.is_connected(_on_action):
		Events.action_requested.connect(_on_action)
	Events.state_changed.emit(state)


func tick(dt: float) -> void:
	if state.is_empty():
		return
	state.day += dt * DAYS_PER_SECOND
	state.power = maxf(state.power - dt * 1.5, 0.0)   # loads drain the battery
	state.data = minf(state.data + dt * 0.8, 100.0)   # instruments fill storage
	_emit_timer -= dt
	if _emit_timer <= 0.0:
		_emit_timer = 0.25
		Events.state_changed.emit(state)


func predict_path() -> PackedVector2Array:
	return PackedVector2Array()


func _on_action(role: String, action: Dictionary) -> void:
	match role:
		"navigator":
			state.fuel = maxf(state.fuel - 5.0, 0.0)
			state.power = maxf(state.power - 3.0, 0.0)
			state.last_action = "NAV: correction burn"
		"engineer":
			state.power = minf(state.power + 15.0, 100.0)
			state.last_action = "PWR: loads rebalanced"
		"comms":
			state.data = maxf(state.data - 25.0, 0.0)
			state.last_action = "COM: downlink to DSN"
		"scientist":
			state.data = minf(state.data + 15.0, 100.0)
			state.power = maxf(state.power - 5.0, 0.0)
			state.last_action = "SCI: observation taken"
		_:
			state.last_action = "%s: %s" % [role.to_upper(), action.get("type", "?")]
	Events.state_changed.emit(state)
