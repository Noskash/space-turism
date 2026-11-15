class_name Astronauts
extends RefCounted
## The named crew (data/astronauts.json): one fictional astronaut per role, "commander" when flying
## solo. A player's crew role decides who they are ("navigator+engineer" -> the navigator).
## Also the radiation dose numbers (mSv, SIMPLIFIED from Curiosity's RAD and NASA's 600 mSv limit).

const PATH := "res://data/astronauts.json"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {astronauts = {}, dose = {}}
	return _data


## Astronaut id for a crew role string ("all" -> commander, "comms+scientist" -> comms).
static func id_for_role(role: String) -> String:
	if role == "all" or role == "":
		return "commander"
	return role.split("+")[0]


static func info(id: String) -> Dictionary:
	return data().astronauts.get(id, {name = id.capitalize(), role = "", color = "e8e8e8", bio = ""})


## Dose setting by key (per_day, storm_outside, storm_big_outside, storm_sheltered, sick_at, ...).
static func dose(key: String) -> float:
	var defaults := {per_day = 1.8, storm_outside = 150.0, storm_big_outside = 250.0, storm_sheltered = 10.0,
			sick_at = 500.0, nasa_limit = 600.0, sick_slowdown = 0.75}
	return float(data().get("dose", {}).get(key, defaults.get(key, 0.0)))


## Surname for tight HUD rows ("Dr. Lena Sato" -> "SATO").
static func short_name(id: String) -> String:
	var parts := str(info(id).name).split(" ")
	return parts[parts.size() - 1].to_upper()
