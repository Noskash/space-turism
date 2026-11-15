class_name CrewRoles
extends RefCounted
## Who covers which stations, by number of players (CLAUDE.md "Crew roles").
## Same order on every peer: peer ids sorted, host (1) first.

const SPLITS := {
	1: ["all"],
	2: ["navigator+engineer", "comms+scientist"],
	3: ["navigator", "engineer", "comms+scientist"],
	4: ["navigator", "engineer", "comms", "scientist"],
}
const TAGS := {"navigator": "NAV", "engineer": "PWR", "comms": "COM", "scientist": "SCI", "all": "ALL"}


## peer id -> role string ("navigator+engineer", "all", ...).
static func assign(peer_ids: Array) -> Dictionary:
	var ids := peer_ids.duplicate()
	ids.sort()
	var roles: Array = SPLITS.get(ids.size(), SPLITS[4])
	var out := {}
	for i in ids.size():
		out[ids[i]] = roles[mini(i, roles.size() - 1)]
	return out


static func has(role: String, station_role: String) -> bool:
	return role == "all" or station_role in role.split("+")


static func tag(role: String) -> String:
	var tags := PackedStringArray()
	for r in role.split("+"):
		tags.append(TAGS.get(r, r.to_upper()))
	return "+".join(tags)


static func color(role: String) -> Color:
	return Station.ROLE_COLORS.get(role.split("+")[0], Color("e8e8e8"))
