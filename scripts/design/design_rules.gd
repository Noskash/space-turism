class_name DesignRules
extends RefCounted
## Spacecraft design rules: parts, classes, launchers, totals and limits, plus the numbers the
## cruise sim derives from a design. Pure data + static functions, no nodes.
##
## A design is a plain dictionary (goes over the network unchanged):
##   {ship_class = "balanced", upgrades = ["rtg", "camera_hires"]}
## Numbers live in res://data/design_stats.json; art and slot layouts come from the asset JSONs.

const STATS_PATH := "res://data/design_stats.json"
const BASE_DIR := "res://sprites/base_kit_assets/"
const UPGRADE_DIR := "res://sprites/upgrade_kit_assets/"
const ROLES := ["navigator", "engineer", "comms", "scientist"]

## The design the crew launched with (set by the designer, read by the game scene).
static var chosen := {}

static var _data := {}
static var _textures := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var stats: Dictionary = _load_json(STATS_PATH)
		var base: Dictionary = _load_json(BASE_DIR + "parts_base.json")
		var ups: Dictionary = _load_json(UPGRADE_DIR + "parts_upgrades.json")
		var classes := {}
		for c: Dictionary in base.get("classes", []):
			var info: Dictionary = c.duplicate(true)
			info.merge(stats.classes.get(c.id, {}))
			classes[c.id] = info
		var parts := {}
		var order: Array[String] = []
		for p: Dictionary in base.get("parts", []):
			var part: Dictionary = p.duplicate(true)
			part.dir = BASE_DIR
			parts[p.id] = part
		for p: Dictionary in ups.get("parts", []):
			var part: Dictionary = p.duplicate(true)
			part.dir = UPGRADE_DIR
			part.merge(stats.parts.get(p.id, {}), true)
			parts[p.id] = part
			order.append(p.id)
		_data = {stats = stats, classes = classes, parts = parts, upgrade_order = order,
				frames = ups.get("frames", {})}
	return _data


static func class_ids() -> Array:
	return ["light", "balanced", "heavy"]


static func class_info(id: String) -> Dictionary:
	return data().classes.get(id, {})


static func part(id: String) -> Dictionary:
	return data().parts.get(id, {})


static func upgrades_for_role(role: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in data().upgrade_order:
		if part(id).role == role:
			out.append(id)
	return out


static func new_design(ship_class := "balanced") -> Dictionary:
	return {ship_class = ship_class, upgrades = []}


## Totals and problems for the HUD / ready check.
static func evaluate(design: Dictionary) -> Dictionary:
	var stats: Dictionary = data().stats
	var cls := class_info(design.get("ship_class", "balanced"))
	var mass := float(cls.get("dry_mass_kg", 0))
	var cost := float(cls.get("cost", 0))
	var gen := float(stats.base.solar_w)
	var draw := -float(stats.base.base_w + stats.base.instruments_w + stats.base.transmitter_w)
	for id: String in design.get("upgrades", []):
		var p := part(id)
		mass += float(p.get("mass_kg", 0))
		cost += float(p.get("cost", 0))
		var w := float(p.get("power_w", 0))
		if w >= 0.0:
			gen += w
		else:
			draw -= w
	var launcher := launcher_for(mass)
	if not launcher.is_empty():
		cost += float(launcher.cost)
	var result := {
		mass = mass, mass_limit = float(cls.get("mass_limit_kg", 0)),
		cost = cost, budget = float(stats.total_budget),
		gen_w = gen, draw_w = draw, net_w = gen - draw,
		slots_used = design.get("upgrades", []).size(), slots = int(cls.get("upgrade_slots", 0)),
		launcher = launcher, errors = [],
	}
	if result.slots_used > result.slots:
		result.errors.append("TOO MANY UPGRADES FOR THIS SHIP")
	if mass > result.mass_limit:
		result.errors.append("TOO HEAVY FOR A %s SHIP" % str(cls.get("name", "")).to_upper())
	if launcher.is_empty():
		result.errors.append("NO ROCKET CAN LIFT %d KG" % mass)
	if cost > result.budget:
		result.errors.append("OVER BUDGET")
	return result


## Real missions keep a lift margin: a rocket only takes payloads up to this share of its
## capacity (above it the launch mini-game cannot reach orbit).
const LIFT_MARGIN := 0.9


## Cheapest launcher that can lift `mass` with margin, or {} if none can.
static func launcher_for(mass: float) -> Dictionary:
	for l: Dictionary in data().stats.launchers:
		if mass <= float(l.capacity_kg) * LIFT_MARGIN:
			return l
	return {}


## Why `part_id` cannot be added right now ("" = it can).
static func check_add(design: Dictionary, part_id: String) -> String:
	if part_id in design.get("upgrades", []):
		return ""
	var trial := design.duplicate(true)
	trial.upgrades.append(part_id)
	var after := evaluate(trial)
	if after.slots_used > after.slots:
		return "NO FREE SLOT"
	if after.mass > after.mass_limit:
		return "TOO HEAVY (+%d KG)" % int(after.mass - after.mass_limit)
	if after.launcher.is_empty():
		return "NO ROCKET CAN LIFT IT"
	if after.cost > after.budget:
		return "OVER BUDGET ($%dM SHORT)" % int(after.cost - after.budget)
	return ""


## Add or remove an upgrade; returns the new design (unchanged if it cannot be added).
static func toggle(design: Dictionary, part_id: String) -> Dictionary:
	var out := design.duplicate(true)
	if part_id in out.upgrades:
		out.upgrades.erase(part_id)
	elif check_add(design, part_id) == "":
		out.upgrades.append(part_id)
	return out


## Switch ship class; upgrades that no longer fit (slots) are dropped from the end.
static func set_class(design: Dictionary, ship_class: String) -> Dictionary:
	var out := design.duplicate(true)
	out.ship_class = ship_class
	var slots := int(class_info(ship_class).get("upgrade_slots", 0))
	while out.upgrades.size() > slots:
		out.upgrades.pop_back()
	return out


## Numbers the cruise sim runs on. Defaults = the bare base kit.
static func mission_params(design: Dictionary) -> Dictionary:
	var b: Dictionary = data().stats.base
	var p := {
		solar_w = float(b.solar_w), battery_wh = float(b.battery_wh),
		base_w = -float(b.base_w), instruments_w = -float(b.instruments_w),
		transmitter_w = -float(b.transmitter_w), heater_w = -float(b.heater_w),
		storage = float(b.storage), data_rate = float(b.data_rate),
		downlink_rate = float(b.downlink_rate), science = float(b.science),
		dsn_pass = float(b.dsn_pass), burn_fuel = float(b.burn_fuel),
		repair_work = float(b.repair_work), storm_weight = 1.0, leak_weight = 1.0,
		instrument_count = 0,
		# Space-weather events (fake_mission): which parts help.
		storm_proof_w = 0.0,   # power that survives a radiation storm tripping the solar bus (RTG)
		cme_tasks = 0,         # +/- shield charges before a radiation storm (rad-hard CPU: -1)
		shields = false,       # radiation shielding: can raise the shield (else only safe mode)
		cme_warning = 0.0,     # extra seconds of radiation storm warning (particle monitor)
		dust_warning = 0.0,    # extra seconds of comet-dust warning (star tracker)
		steer_free = false,    # dodge without thrusters (reaction wheels)
	}
	for id: String in design.get("upgrades", []):
		var part_data := part(id)
		var w := float(part_data.get("power_w", 0))
		match part_data.get("load", "base"):
			"gen": p.solar_w += w
			"instruments":
				p.instruments_w -= w
				p.instrument_count += 1
			"transmitter": p.transmitter_w -= w
			_: p.base_w -= w
		var fx: Dictionary = part_data.get("effects", {})
		p.battery_wh += float(fx.get("battery_wh", 0))
		p.storage += float(fx.get("storage", 0))
		p.data_rate += float(fx.get("data_rate", 0))
		p.science += float(fx.get("science", 0))
		p.dsn_pass += float(fx.get("dsn_pass", 0))
		p.downlink_rate *= float(fx.get("downlink_mult", 1))
		p.burn_fuel *= float(fx.get("burn_mult", 1))
		p.repair_work *= float(fx.get("repair_mult", 1))
		p.storm_weight *= float(fx.get("storm_mult", 1))
		p.leak_weight *= float(fx.get("leak_mult", 1))
		p.storm_proof_w += float(fx.get("storm_proof_w", 0))
		p.cme_tasks += int(fx.get("cme_tasks", 0))
		p.shields = p.shields or bool(fx.get("shields", 0))
		p.cme_warning += float(fx.get("cme_warning", 0))
		p.dust_warning += float(fx.get("dust_warning", 0))
		p.steer_free = p.steer_free or bool(fx.get("steer_free", 0))
	return p


## Cached texture. Call preload_textures() before drawing: a texture loaded for the first time
## inside _draw() renders as a white box on this renderer.
static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## Loads every body, part, icon and frame texture the designer can draw.
static func preload_textures() -> void:
	for c: Dictionary in data().classes.values():
		texture(BASE_DIR + c.get("body", ""))
	for p: Dictionary in data().parts.values():
		texture(p.dir + p.get("mounted", ""))
		texture(p.dir + p.get("icon", ""))
	for f: Dictionary in data().frames.values():
		for rel: String in f.values():
			texture(UPGRADE_DIR + rel)


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DesignRules: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
