class_name RelayPeer
extends MultiplayerPeerExtension
## Online co-op transport: a MultiplayerPeer that talks to the room relay (relay/server.js) over one
## WebSocket instead of connecting players directly (Railway has no UDP, home routers block ENet).
## Every RPC in the game works unchanged on top of it: the relay gives the host peer id 1 and the
## clients 2, 3, ...; clients only ever send to the host and Godot's server relay (SceneMultiplayer)
## carries client <-> client traffic, exactly like with ENet.
##
## Network uses it: RelayPeer.host(url) / RelayPeer.join(url, code), then multiplayer_peer = it.
## The relay is TCP, so every transfer mode arrives reliable and ordered.

## The host got its room code from the relay.
signal code_received(code: String)

const MAX_PACKET := (1 << 20) - 4
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"   # no I / O, same as the relay
const CODE_LENGTH := 4
const CONNECT_TIMEOUT_MS := 8000

## Room code (host: from the relay; client: what was typed).
var code := ""
## Why the connection ended ("" = closed by us). Relay reasons: no_room, full, locked, busy,
## host_left, expired, bad; plus unreachable / lost from here.
var last_error := ""

var _ws := WebSocketPeer.new()
var _is_host := false
var _id := 0
var _status := MultiplayerPeer.CONNECTION_CONNECTING
var _was_open := false
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false
var _incoming: Array = []    # [from, PackedByteArray]
var _outgoing: Array = []    # packets put before the room existed (host only)
var _peers: Array[int] = []
var _started_ms := 0


## Create a room on the relay; the code arrives with code_received.
static func host(url: String) -> RelayPeer:
	var peer := RelayPeer.new()
	peer._is_host = true
	peer._id = 1
	# The host counts as connected at once (no peers yet): the game can open the lobby while the
	# relay answers. If the relay is unreachable, the status drops to DISCONNECTED -> Network
	# gets server_disconnected and shows last_error.
	peer._status = MultiplayerPeer.CONNECTION_CONNECTED
	peer._open(url)
	return peer


## Join the room `room_code`; connected_to_server fires once the relay lets us in.
static func join(url: String, room_code: String) -> RelayPeer:
	var peer := RelayPeer.new()
	peer.code = room_code.strip_edges().to_upper()
	peer._open(url)
	return peer


## A room code is 4 letters without I / O, e.g. "KRMX" (case does not matter).
static func looks_like_code(text: String) -> bool:
	var t := text.strip_edges().to_upper()
	if t.length() != CODE_LENGTH:
		return false
	for c in t:
		if not CODE_LETTERS.contains(c):
			return false
	return true


func _open(url: String) -> void:
	_started_ms = Time.get_ticks_msec()
	_ws.inbound_buffer_size = 1 << 22
	_ws.outbound_buffer_size = 1 << 22
	_ws.max_queued_packets = 8192
	if _ws.connect_to_url(url) != OK:
		_fail("unreachable")


func _fail(reason: String) -> void:
	if last_error == "":
		last_error = reason
	_ws.close()
	_drop_all()


func _drop_all() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_incoming.clear()
	_outgoing.clear()
	_peers.clear()


func _send_control(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


# --- MultiplayerPeerExtension ---

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var ready := _ws.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_send_control({op = "host"} if _is_host else {op = "join", code = code})
	# Read what arrived even if the socket is closing: the relay sends {op:"error"} right before it
	# closes (host left, room full ...).
	while _ws.get_available_packet_count() > 0:
		var data := _ws.get_packet()
		if _ws.was_string_packet():
			_on_control(data.get_string_from_utf8())
		elif data.size() >= 4 and _status == MultiplayerPeer.CONNECTION_CONNECTED:
			_incoming.append([data.decode_s32(0), data.slice(4)])
		if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
	if code == "" or not _is_host and _id == 0:
		# No answer from the relay (a refused connection can hang for a long time on Windows).
		if Time.get_ticks_msec() - _started_ms > CONNECT_TIMEOUT_MS:
			_fail("unreachable")
			return
	if ready == WebSocketPeer.STATE_CLOSED:
		var reason := _ws.get_close_reason()   # the relay also puts the reason in the close frame
		_fail(reason if reason != "" else ("lost" if _was_open else "unreachable"))


func _on_control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match str(msg.get("op", "")):
		"hosted":
			code = str(msg.get("code", ""))
			for packet: PackedByteArray in _outgoing:
				_ws.send(packet)
			_outgoing.clear()
			if _refusing:
				_send_control({op = "lock", on = true})
			code_received.emit(code)
		"joined":
			_id = int(msg.get("id", 0))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			_peers.append(1)
			peer_connected.emit(1)          # SceneMultiplayer -> connected_to_server
		"peer_joined":
			var id := int(msg.get("id", 0))
			if _refusing:
				_send_control({op = "kick", id = id})
			elif id > 1 and not _peers.has(id):
				_peers.append(id)
				peer_connected.emit(id)
		"peer_left":
			var id := int(msg.get("id", 0))
			if _peers.has(id):
				_peers.erase(id)
				peer_disconnected.emit(id)
		"error":
			_fail(str(msg.get("reason", "bad")))


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET:
		return ERR_OUT_OF_MEMORY
	var packet := PackedByteArray()
	packet.resize(4)
	packet.encode_s32(0, _target if _is_host else 1)
	packet.append_array(buffer)
	if _is_host and code == "":
		_outgoing.append(packet)    # relay has not answered yet
		return OK
	return _ws.send(packet)


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()[1]


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_peer() -> int:
	return int(_incoming[0][0]) if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return 0


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _is_host


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	_send_control({op = "lock", on = enable})


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_host:
		_send_control({op = "kick", id = peer})


func _close() -> void:
	_ws.close()
	_drop_all()
