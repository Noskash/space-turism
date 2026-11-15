extends Node
## Сетевая игра: создание комнаты, подключение к ней и список игроков.
## Подключён автозагрузкой под именем Network, поэтому живёт между сценами.
##
## Создатель комнаты — сервер (peer id 1), остальные игроки — клиенты.
## Список игроков и выбранный уровень хранит сервер и рассылает клиентам.
##
## Два способа связи, вся игра (RPC) работает одинаково поверх обоих:
## - через интернет (online = true): сервер-ретранслятор relay/server.js на Railway выдаёт
##   код комнаты из 4 букв (RelayPeer, WebSocket);
## - по локальной сети: ENet по IP-адресу и порту 7777.

## Изменился список игроков или данные комнаты.
signal room_changed
## Клиент подключился и получил данные комнаты.
signal joined_room
## Подключиться не удалось.
signal join_failed(reason: String)
## Связь с комнатой пропала (создатель её закрыл или пропала сеть).
signal room_closed(reason: String)
## Создатель комнаты начал полёт — пора загружать уровень.
signal game_started
## Сервер-ретранслятор выдал код комнаты (только создателю, игра через интернет).
signal code_received(code: String)

enum State { OFFLINE, HOSTING, CONNECTING, JOINED }

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const CONNECT_TIMEOUT := 8.0
## Части названий виртуальных сетевых адаптеров.
const VIRTUAL_ADAPTER_HINTS := ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "docker",
		"loopback", "bluetooth"]
## Подсказка, если подключиться не выходит.
const FIREWALL_HINT := "На компьютере с комнатой сеть должна быть «Частной», а игре — разрешён доступ в брандмауэре."
## Сервер-ретранслятор для игры через интернет (Railway, проект space-turism-relay).
## Переопределяется запуском с --relay=ws://127.0.0.1:8080 (локальный тест: cd relay && npm start).
const RELAY_URL := "wss://space-turism-relay-production.up.railway.app"
## Почему не вышло подключиться через ретранслятор (RelayPeer.last_error → текст).
const RELAY_ERRORS := {
	"no_room": "Комнаты с таким кодом нет. Проверь код у создателя комнаты.",
	"full": "Комната заполнена: в ней уже 4 игрока.",
	"locked": "В этой комнате полёт уже начался.",
	"busy": "Сервер занят или было слишком много попыток. Подожди минуту.",
	"unreachable": "Сервер игры через интернет не отвечает. Проверь интернет.",
	"lost": "Связь с сервером игры через интернет пропала.",
	"host_left": "Создатель закрыл комнату.",
	"expired": "Комната закрыта: она открыта больше 3 часов.",
}

## На каком адресе сервер ждёт подключений. «*» — на всех сетевых картах.
var bind_address := "*"
var state := State.OFFLINE
## Игроки комнаты: peer id → имя.
var players: Dictionary = {}
## Уровень, выбранный создателем комнаты, и его номер.
var level: LevelData
var level_number := 1
## Сообщение для следующего экрана (например, почему пропала связь).
var pending_message := ""
## Создавать комнаты через интернет (код комнаты) или по локальной сети (IP).
var online := true
## Код комнаты через интернет ("" — пока не выдан или комната по IP).
var room_code := ""
## Адрес ретранслятора (RELAY_URL или --relay=...).
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


## Создать комнату с выбранным уровнем. Возвращает OK или код ошибки.
## Через интернет код комнаты придёт позже сигналом code_received (лобби уже можно открывать).
func create_room(level_data: LevelData, number: int, port := DEFAULT_PORT) -> Error:
	leave_room()
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


## Создатель в лобби, пока никто не вошёл: переключить комнату между интернетом и локальной сетью.
func set_online(value: bool) -> Error:
	if online == value:
		return OK
	online = value
	if not is_host():
		return OK
	var error := create_room(level, level_number)
	if error != OK:   # например, порт 7777 занят — возвращаемся к интернету
		online = not value
		create_room(level, level_number)
	return error


## Подключиться к комнате по коду «KRMX» (через интернет) или по адресу «192.168.1.5[:7777]».
## Результат придёт сигналом joined_room или join_failed.
func join_room(address: String) -> Error:
	leave_room()
	if RelayPeer.looks_like_code(address):
		multiplayer.multiplayer_peer = RelayPeer.join(relay_url, address)
		state = State.CONNECTING
		_connect_timer.start()
		return OK
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


## Выйти из комнаты. Если это создатель — комната закрывается для всех.
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


## Комната через интернет (код), а не по IP.
func is_online_room() -> bool:
	return multiplayer.multiplayer_peer is RelayPeer


## Только для создателя: начать полёт у всех игроков.
func start_game() -> void:
	if not is_host():
		return
	set_room_open(false)
	_start_game.rpc()


## Только для создателя: пускать ли новых игроков.
func set_room_open(open: bool) -> void:
	if is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = not open


## Локальные IPv4-адреса этого компьютера — их создатель называет друзьям.
## Сначала адреса настоящих сетевых карт (Wi-Fi, Ethernet),
## в конце — виртуальных (VirtualBox, WSL и т. п.): через них друзья не подключатся.
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


## Разбирает «адрес» или «адрес:порт». Возвращает [адрес, порт] или пустой массив.
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
	var player_name := "Игрок %d" % _next_player_number
	_next_player_number += 1
	return player_name


# --- События сети ---

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
	# Ждём, пока сервер пришлёт данные комнаты (_receive_room).
	pass


func _on_code_received(code: String) -> void:
	room_code = code
	code_received.emit(code)
	room_changed.emit()


## Текст ошибки ретранслятора ("" — комната не через интернет или причина неизвестна).
func _relay_error() -> String:
	var peer := multiplayer.multiplayer_peer
	if peer is RelayPeer:
		return str(RELAY_ERRORS.get((peer as RelayPeer).last_error, ""))
	return ""


func _on_connection_failed() -> void:
	if state == State.CONNECTING:
		var relay := _relay_error()
		leave_room()
		join_failed.emit(relay if relay != "" else "Не удалось подключиться. Проверь адрес. " + FIREWALL_HINT)


func _on_connect_timeout() -> void:
	if state == State.CONNECTING:
		var relay := multiplayer.multiplayer_peer is RelayPeer
		leave_room()
		join_failed.emit(RELAY_ERRORS.unreachable if relay \
				else "Комната не отвечает. Проверь адрес и что вы в одной сети. " + FIREWALL_HINT)


func _on_server_disconnected() -> void:
	var relay := _relay_error()
	leave_room()
	pending_message = relay if relay != "" \
			else "Связь с комнатой пропала: создатель её закрыл или пропала сеть."
	room_closed.emit(pending_message)


# --- RPC: вызывает только сервер (authority), выполняют клиенты ---

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
