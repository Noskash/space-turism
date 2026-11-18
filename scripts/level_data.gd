class_name LevelData
extends Resource
## A level's description for the level select screen.

## Name, e.g. "Moon".
@export var title: String = ""
## Short route description (2-3 lines on the card).
@export_multiline var description: String = ""
## The level scene loaded after the hyperspace jump.
@export_file("*.tscn") var scene: String = ""
## Colour of the card's frame and text.
@export var accent_color: Color = Color(0.35, 0.85, 1.0)
## Mars campaign: the card opens the mission picker (MissionSelect) instead of creating a room.
@export var has_missions: bool = false
## False = the card shows "UNDER DEVELOPMENT - NOT AVAILABLE YET" and can't be picked.
@export var available: bool = true
## Mission id from data/missions.json, set by the mission picker ("" = none). Synced with the room.
@export var mission: String = ""
## Sandbox hazard switches {storms, debris, hull, conjunction} (Missions.sim). Synced with the room.
@export var options: Dictionary = {}
## "easy" / "medium" / "hard" (missions.json "difficulty"), set by the mission picker. Synced with the room.
@export var difficulty: String = "medium"

@export_group("Planet on the card")
@export var planet_color_a: Color = Color(0.3, 0.3, 0.32)
@export var planet_color_b: Color = Color(0.8, 0.8, 0.78)
@export var atmosphere_color: Color = Color(0.35, 0.75, 1.0)
## Bands and clouds instead of a rocky, cratered surface.
@export var gas_giant: bool = false
## Rings around the planet.
@export var rings: bool = false


## Data to send over the network (whole resources are not sent).
func to_dict() -> Dictionary:
	return {
		"title": title,
		"description": description,
		"scene": scene,
		"accent_color": accent_color,
		"planet_color_a": planet_color_a,
		"planet_color_b": planet_color_b,
		"atmosphere_color": atmosphere_color,
		"gas_giant": gas_giant,
		"rings": rings,
		"has_missions": has_missions,
		"available": available,
		"mission": mission,
		"options": options,
		"difficulty": difficulty,
	}


static func from_dict(data: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.title = str(data.get("title", ""))
	level.description = str(data.get("description", ""))
	level.scene = str(data.get("scene", ""))
	level.accent_color = data.get("accent_color", level.accent_color)
	level.planet_color_a = data.get("planet_color_a", level.planet_color_a)
	level.planet_color_b = data.get("planet_color_b", level.planet_color_b)
	level.atmosphere_color = data.get("atmosphere_color", level.atmosphere_color)
	level.gas_giant = bool(data.get("gas_giant", false))
	level.rings = bool(data.get("rings", false))
	level.has_missions = bool(data.get("has_missions", false))
	level.available = bool(data.get("available", true))
	level.mission = str(data.get("mission", ""))
	var opts: Variant = data.get("options", {})
	level.options = opts if opts is Dictionary else {}
	level.difficulty = str(data.get("difficulty", "medium"))
	return level
