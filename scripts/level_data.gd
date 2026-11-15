class_name LevelData
extends Resource
## Описание уровня для экрана выбора уровня.

## Название, например «Луна».
@export var title: String = ""
## Короткое описание маршрута (2–3 строки на карточке).
@export_multiline var description: String = ""
## Сцена уровня, которая загрузится после прыжка в гиперпространство.
@export_file("*.tscn") var scene: String = ""
## Цвет рамки и надписей карточки.
@export var accent_color: Color = Color(0.35, 0.85, 1.0)
## Mars campaign: the card opens the mission picker (MissionSelect) instead of creating a room.
@export var has_missions: bool = false
## False = the card shows "UNDER DEVELOPMENT - NOT AVAILABLE YET" and can't be picked.
@export var available: bool = true
## Mission id from data/missions.json, set by the mission picker ("" = none). Synced with the room.
@export var mission: String = ""
## Sandbox hazard switches {storms, debris, hull, conjunction} (Missions.sim). Synced with the room.
@export var options: Dictionary = {}

@export_group("Планета на карточке")
@export var planet_color_a: Color = Color(0.3, 0.3, 0.32)
@export var planet_color_b: Color = Color(0.8, 0.8, 0.78)
@export var atmosphere_color: Color = Color(0.35, 0.75, 1.0)
## Полосы и облака вместо каменистой поверхности с кратерами.
@export var gas_giant: bool = false
## Кольца вокруг планеты.
@export var rings: bool = false


## Данные для отправки по сети (ресурсы целиком по сети не передаются).
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
	return level
