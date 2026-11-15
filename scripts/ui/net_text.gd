class_name NetText
extends RefCounted
## English text for the kit menus (join / lobby). The UI font (Share Tech Mono) has no Cyrillic, and
## Network (scripts/network.gd) still hands out Russian messages and player names, so this maps the
## known ones to English for display only. Network itself is untouched; unknown text passes through.

const MESSAGES := {
	"no_room": "No room with that code. Check the code with the room's host.",
	"full": "The room is full: 4 players are already in.",
	"locked": "This room's flight has already started.",
	"busy": "The server is busy or there were too many tries. Wait a minute.",
	"unreachable": "The online server does not answer. Check your internet.",
	"lost": "Lost the connection to the online server.",
	"host_left": "The host closed the room.",
	"expired": "Room closed: it was open for more than 3 hours.",
}
const FIREWALL_EN := "On the host's computer the network must be Private and the game allowed through the firewall."


## Network message (join_failed reason, pending_message) -> English.
static func message(text: String) -> String:
	if text == "":
		return ""
	for key: String in Network.RELAY_ERRORS:
		if text == str(Network.RELAY_ERRORS[key]):
			return MESSAGES.get(key, text)
	var out := text.replace(Network.FIREWALL_HINT, FIREWALL_EN)
	if out.begins_with("Не удалось подключиться"):
		return "Could not connect. Check the address. " + FIREWALL_EN
	if out.begins_with("Комната не отвечает"):
		return "The room does not answer. Check the address and that you are on the same network. " + FIREWALL_EN
	if out.begins_with("Связь с комнатой пропала"):
		return "Lost the room: the host closed it or the network dropped."
	return out


## "Игрок 3" -> "PLAYER 3".
static func player(player_name: String) -> String:
	if player_name.begins_with("Игрок"):
		return "PLAYER" + player_name.trim_prefix("Игрок")
	return player_name.to_upper()
