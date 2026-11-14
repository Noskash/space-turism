class_name Companion
extends Node2D
## A non-player character that walks behind a leader, JRPG-style: it replays the leader's
## path a fixed distance behind, so it never needs its own collision or pathfinding.

const FOLLOW_DISTANCE := 12.0  # px behind the leader, along the path

var leader: Node2D
var _trail := PackedVector2Array()
var _sprite: CrewSprite
var _facing := Vector2.DOWN


func setup(leader_node: Node2D, skin: String) -> void:
	leader = leader_node
	name = "Companion"
	var start := leader.global_position + Vector2(-FOLLOW_DISTANCE, 0)
	position = start
	_trail = PackedVector2Array([start, leader.global_position])
	_sprite = CrewSprite.new()
	_sprite.set_skin(skin)
	add_child(_sprite)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(leader) or _sprite == null:
		return
	var lead := leader.global_position
	if _trail[_trail.size() - 1].distance_to(lead) > 0.5:
		_trail.append(lead)

	# Walk back along the trail until FOLLOW_DISTANCE is used up; drop older points.
	var target := _trail[0]
	var remaining := FOLLOW_DISTANCE
	for i in range(_trail.size() - 1, 0, -1):
		var segment := _trail[i].distance_to(_trail[i - 1])
		if segment >= remaining:
			target = _trail[i].move_toward(_trail[i - 1], remaining)
			_trail = _trail.slice(i - 1)
			break
		remaining -= segment

	var step := target - global_position
	var moving := step.length() > 0.05
	global_position = target
	# Walking: face the way we move. Standing: look at the leader.
	_facing = step if moving else lead - global_position
	if _facing == Vector2.ZERO:
		_facing = Vector2.DOWN
	_sprite.show_state(_facing, moving)
