class_name NetText
extends RefCounted
## Player names for display (lobby, crew tags, HUD, credits): Network names players "Player N";
## the kit screens show names in capitals.


## "Player 3" -> "PLAYER 3".
static func player(player_name: String) -> String:
	return player_name.to_upper()
