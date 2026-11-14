class_name NetSync
extends Node
## Network co-op for the game scene (rooms themselves live in the Network autoload).
##
## Host = authority. It alone runs the Mission; clients forward their station actions to it,
## and it sends state + ticket events back. Every peer owns its own crew member and streams a
## small snapshot of it; the host relays snapshots, so nothing is sent to a peer whose game
## scene has not finished loading (which would spam "node not found" errors).
##
##   client --_submit_action--> host        Events.action_requested on the host
##   host   --_recv_state-----> clients     Events.state_changed on the clients
##   host   --_recv_event_*---> clients     Events.event_started / event_ended
##   peer   --_crew_to_host---> host --_crew_from_host--> other peers
##
## Offline (no room) this node does nothing and the scene plays as single player.
## Must sit at the same path on every peer: /root/Game/NetSync.

signal crew_received(peer_id: int, snapshot: Array)

const CREW_SEND_INTERVAL := 1.0 / 20.0

var active := false
var local_crew: CrewMember

var _ready_peers := {}         # host: peer id -> true once its game scene is loaded
var _host_ready := false       # client: the host has started sending us state
var _send_timer := 0.0


func _ready() -> void:
	active = Network.is_in_room()
	if not active:
		return
	if Network.is_host():
		Events.state_changed.connect(_on_host_state)
		Events.event_started.connect(_on_host_event_started)
		Events.event_ended.connect(_on_host_event_ended)
		multiplayer.peer_disconnected.connect(func(id: int) -> void: _ready_peers.erase(id))
	else:
		Events.action_requested.connect(_on_client_action)
		_client_ready.rpc_id(1)


func is_authority() -> bool:
	return not active or Network.is_host()


func _process(delta: float) -> void:
	if not active or not Network.is_in_room() or local_crew == null:
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = CREW_SEND_INTERVAL
	var snapshot := local_crew.snapshot()
	if Network.is_host():
		for id: int in _ready_peers:
			_crew_from_host.rpc_id(id, 1, snapshot)
	elif _host_ready:
		_crew_to_host.rpc_id(1, snapshot)


# --- host side -------------------------------------------------------------------------

func _on_host_state(state: Dictionary) -> void:
	for id: int in _ready_peers:
		_recv_state.rpc_id(id, state)


func _on_host_event_started(event: Dictionary) -> void:
	for id: int in _ready_peers:
		_recv_event_started.rpc_id(id, event)


func _on_host_event_ended(id_text: String) -> void:
	for id: int in _ready_peers:
		_recv_event_ended.rpc_id(id, id_text)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if Network.is_host():
		_ready_peers[multiplayer.get_remote_sender_id()] = true


@rpc("any_peer", "call_remote", "reliable")
func _submit_action(role: String, action: Dictionary) -> void:
	if Network.is_host():
		Events.action_requested.emit(role, action)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _crew_to_host(snapshot: Array) -> void:
	if not Network.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	crew_received.emit(sender, snapshot)
	for id: int in _ready_peers:
		if id != sender:
			_crew_from_host.rpc_id(id, sender, snapshot)


# --- client side -----------------------------------------------------------------------

func _on_client_action(role: String, action: Dictionary) -> void:
	if Network.is_in_room():
		_submit_action.rpc_id(1, role, action)


@rpc("authority", "call_remote", "reliable")
func _recv_state(state: Dictionary) -> void:
	_host_ready = true
	Events.state_changed.emit(state)


@rpc("authority", "call_remote", "reliable")
func _recv_event_started(event: Dictionary) -> void:
	Events.event_started.emit(event)


@rpc("authority", "call_remote", "reliable")
func _recv_event_ended(id_text: String) -> void:
	Events.event_ended.emit(id_text)


@rpc("authority", "call_remote", "unreliable_ordered")
func _crew_from_host(peer_id: int, snapshot: Array) -> void:
	crew_received.emit(peer_id, snapshot)
