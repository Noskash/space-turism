extends Node
## Network play: creating a room, joining it, and the player list.
## An autoload named Network, so it lives across scenes.
##
## The room's host is the server (peer id 1); the other players are clients.
## The server keeps the player list and the chosen level and sends them to clients.
##
## Two transports; the whole game (RPC) works the same over both:
## - online (online = true): the relay server relay/server.js on Railway hands out
##   a 4-letter room code (RelayPeer, WebSocket);
## - local network: ENet by IP address and port 7777.

## The player list or the room data changed.
signal room_changed
## A client connected and received the room data.
signal joined_room
## Joining failed.
signal join_failed(reason: String)
## Lost the room (the host closed it or the network dropped).
signal room_closed(reason: String)
## The host started the flight: time to load the level.
signal game_started
## The relay server issued the room code (host only, online play).
signal code_received(code: String)

enum State { OFFLINE, HOSTING, CONNECTING, JOINED }

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const CONNECT_TIMEOUT := 8.0
## Name fragments of virtual network adapters.
const VIRTUAL_ADAPTER_HINTS := ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "docker",
		"loopback", "bluetooth"]
## Hint shown when joining does not work.
const FIREWALL_HINT := "On the host's computer the network must be Private and the game allowed through the firewall."
## Relay server for online play (Railway, project space-turism-relay).
## Override with --relay=ws://127.0.0.1:8080 on the command line (local test: cd relay && npm start).
const RELAY_URL := "wss://space-turism-relay-production.up.railway.app"
## Why joining through the relay failed (RelayPeer.last_error -> text).
const RELAY_ERRORS := {
	"no_room": "No room with that code. Check the code with the room's host.",
	"full": "The room is full: 4 players are already in.",
	"locked": "This room's flight has already started.",
	"busy": "The server is busy or there were too many tries. Wait a minute.",
	"unreachable": "The online server does not answer. Check your internet.",
	"lost": "Lost the connection to the online server.",
	"host_left": "The host closed the room.",
	"expired": "Room closed: it was open for more than 3 hours.",
}

## Address the server listens on. "*" = every network card.
var bind_address := "*"
var state := State.OFFLINE
## Players in the room: peer id -> name.
var players: Dictionary = {}
## The level the host picked, and its number.
var level: LevelData
var level_number := 1
## Message for the next screen (e.g. why the connection was lost).
var pending_message := ""
## Create rooms online (room code) or on the local network (IP).
var online := true
## Online room code ("" = not issued yet, or an IP room).
var room_code := ""
## Relay address (RELAY_URL or --relay=...).
var relay_url := RELAY_URL

var _next_player_number := 1
var _connect_timer: Timer


func _ready() -> void:
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = CONNECT_TIMEOUT
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			relay_url = arg.trim_prefix("--relay=")


func is_host() -> bool:
	return state == State.HOSTING


func is_in_room() -> bool:
	return state == State.HOSTING or state == State.JOINED


func my_id() -> int:
	return multiplayer.get_unique_id()


## Create a room with the chosen level. Returns OK or an error code.
## Online, the room code arrives later via code_received (the lobby can open already).
func create_room(level_data: LevelData, number: int, port := DEFAULT_PORT) -> Error:
	leave_room()
	if OS.has_feature("web"):
		online = true   # browsers have no ENet / UDP: always the WebSocket relay
	if online:
		var relay := RelayPeer.host(relay_url)
		relay.code_received.connect(_on_code_received)
		multiplayer.multiplayer_peer = relay
	else:
		var peer := ENetMultiplayerPeer.new()
		peer.set_bind_ip(bind_address)
		var error := peer.create_server(port, MAX_PLAYERS - 1)
		if error != OK:
			return error
		multiplayer.multiplayer_peer = peer
	state = State.HOSTING
	level = level_data
	level_number = number
	_next_player_number = 1
	players = {1: _take_player_name()}
	room_changed.emit()
	return OK


## Host in the lobby while nobody has joined: switch the room between online and local network.
func set_online(value: bool) -> Error:
	if online == value:
		return OK
	if OS.has_feature("web") and not value:
		return ERR_UNAVAILABLE   # no LAN (ENet) in a browser
	online = value
	if not is_host():
		return OK
	var error := create_room(level, level_number)
	if error != OK:   # e.g. port 7777 is taken: back to online
		online = not value
		create_room(level, level_number)
	return error


## Join a room by code "KRMX" (online) or by address "192.168.1.5[:7777]".
## The result arrives as joined_room or join_failed.
func join_room(address: String) -> Error:
	leave_room()
	if RelayPeer.looks_like_code(address):
		multiplayer.multiplayer_peer = RelayPeer.join(relay_url, address)
		state = State.CONNECTING
		_connect_timer.start()
		return OK
	if OS.has_feature("web"):
		return ERR_UNAVAILABLE   # browsers can only join by room code (relay)
	var parsed := parse_address(address)
	if parsed.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(parsed[0], parsed[1])
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	state = State.CONNECTING
	_connect_timer.start()
	return OK


## Leave the room. If this is the host, the room closes for everyone.
func leave_room() -> void:
	_connect_timer.stop()
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer or peer is RelayPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	state = State.OFFLINE
	players = {}
	level = null
	room_code = ""


## An online room (code), not an IP room.
func is_online_room() -> bool:
	return multiplayer.multiplayer_peer is RelayPeer


## Host only: start the flight for every player.
func start_game() -> void:
	if not is_host():
		return
	set_room_open(false)
	_start_game.rpc()


## Host only: whether new players may join.
func set_room_open(open: bool) -> void:
	if is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = not open


## This computer's local IPv4 addresses - the host tells them to friends.
## Real network cards first (Wi-Fi, Ethernet),
## virtual ones last (VirtualBox, WSL, ...): friends can't join through those.
func get_local_addresses() -> PackedStringArray:
	var real := PackedStringArray()
	var virtual := PackedStringArray()
	for adapter in IP.get_local_interfaces():
		var adapter_name := (str(adapter.get("friendly", "")) + " " + str(adapter.get("name", ""))).to_lower()
		var is_virtual := VIRTUAL_ADAPTER_HINTS.any(
				func(hint: String) -> bool: return adapter_name.contains(hint))
		for address: String in adapter.get("addresses", []):
			if address.count(".") != 3 or address.begins_with("127.") or address.begins_with("169.254."):
				continue
			if is_virtual:
				virtual.append(address)
			else:
				real.append(address)
	return real + virtual


## Parses "address" or "address:port". Returns [address, port] or an empty array.
static func parse_address(text: String) -> Array:
	var address := text.strip_edges()
	var port := DEFAULT_PORT
	if address.count(":") == 1:
		var parts := address.split(":")
		if not parts[1].is_valid_int():
			return []
		address = parts[0]
		port = parts[1].to_int()
	if address.is_empty() or port < 1 or port > 65535:
		return []
	return [address, port]


func _take_player_name() -> String:
	var player_name := "Player %d" % _next_player_number
	_next_player_number += 1
	return player_name


# --- Network events ---

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	players[id] = _take_player_name()
	var room_info := level.to_dict()
	room_info["number"] = level_number
	_receive_room.rpc_id(id, room_info)
	_receive_players.rpc(players)
	room_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	players.erase(id)
	_receive_players.rpc(players)
	room_changed.emit()


func _on_connected_to_server() -> void:
	# Wait for the server to send the room data (_receive_room).
	pass


func _on_code_received(code: String) -> void:
	room_code = code
	code_received.emit(code)
	room_changed.emit()


## Relay error text ("" = not an online room, or the reason is unknown).
func _relay_error() -> String:
	var peer := multiplayer.multiplayer_peer
	if peer is RelayPeer:
		return str(RELAY_ERRORS.get((peer as RelayPeer).last_error, ""))
	return ""


func _on_connection_failed() -> void:
	if state == State.CONNECTING:
		var relay := _relay_error()
		leave_room()
		join_failed.emit(relay if relay != "" else "Could not connect. Check the address. " + FIREWALL_HINT)


func _on_connect_timeout() -> void:
	if state == State.CONNECTING:
		var relay := multiplayer.multiplayer_peer is RelayPeer
		leave_room()
		join_failed.emit(RELAY_ERRORS.unreachable if relay \
				else "The room does not answer. Check the address and that you are on the same network. " + FIREWALL_HINT)


func _on_server_disconnected() -> void:
	var relay := _relay_error()
	leave_room()
	pending_message = relay if relay != "" \
			else "Lost the room: the host closed it or the network dropped."
	room_closed.emit(pending_message)


# --- RPC: called by the server (authority) only, run on clients ---

@rpc("authority", "call_remote", "reliable")
func _receive_room(room_info: Dictionary) -> void:
	level = LevelData.from_dict(room_info)
	level_number = int(room_info.get("number", 1))
	if state == State.CONNECTING:
		state = State.JOINED
		_connect_timer.stop()
		joined_room.emit()
	room_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_players(list: Dictionary) -> void:
	players = list
	room_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	game_started.emit()
