class_name EventGuide
extends CanvasLayer
## Walkthroughs for every cruise event (radiation storm, comet debris, faults, science windows,
## repairs, blackout, low battery, full storage).
##
## The first time an event happens:
##   1. a short dialog (Tutorial panes, the sim is paused offline) says what it is in real life,
##      who fixes it, how, and which parts help (the trade-off lesson);
##   2. then a live checklist under the banner + a bouncing arrow over the right station walk the
##      crew through it, ticking steps off from the sim state;
##   3. when the event is over, a one-line outcome ("STORM BEATEN" / "SHIP DISABLED - ...").
## Once per event (user://tutorial.cfg "seen/event_<id>"); nothing when tutorials are skipped.
## Reads the sim only through Events.state_changed, so it works the same on every co-op peer.

const ROOMS := {
	"navigator": Rect2(336, 34, 108, 168), "engineer": Rect2(30, 138, 118, 112),
	"comms": Rect2(30, 34, 118, 80), "scientist": Rect2(160, 34, 164, 80),
	"team": Rect2(160, 138, 164, 112),
	"cargo": Rect2(330, 210, 116, 44),
}
const PLACE := {
	"navigator": "BRIDGE", "engineer": "ENGINE ROOM", "comms": "COMMS",
	"scientist": "SCIENCE LAB", "team": "MISSION HUB TABLE",
}
const WHO := {
	"navigator": "NAVIGATOR", "engineer": "ENGINEER", "comms": "COMMS",
	"scientist": "SCIENTIST", "team": "ANYONE",
}
## Short, timed events: their walkthrough is never cut off. Every other walkthrough (they can run long:
## repairs, blackout, breaches...) gives way to a NEW event the crew hasn't seen yet, so a first
## encounter is never missed because an older checklist was still on screen.
const CRITICAL := ["moi", "storm_shields", "storm_safe", "debris", "conjunction"]
const ORDER := ["moi", "storm_shields", "storm_safe", "debris", "conjunction", "breach", "blackout", "solar_storm",
		"thruster_leak", "antenna_glitch", "science_window", "repair", "low_power", "data_full"]
## Codex terms each event unlocks the first time it happens (even with tutorials skipped).
const TERMS := {
	"storm_shields": ["solar_particle_event", "radiation_shielding"],
	"storm_safe": ["solar_particle_event", "safe_mode", "storm_shelter", "radiation_dose"],
	"debris": ["comet_debris"], "breach": ["hull_breach"], "blackout": ["rtg"],
	"solar_storm": ["rad_hard"], "science_window": ["downlink"], "data_full": ["downlink", "dsn"],
	"conjunction": ["solar_conjunction"], "moi": ["mars_orbit_insertion"], "low_power": ["au"],
}
const FAULTS := {
	"solar_storm": "engineer", "thruster_leak": "navigator", "antenna_glitch": "comms",
}
const RESULT_TIME := 4.0

var map: ShipMap
var local: CrewMember          # the crew member this window controls (null = none)

var _state := {}
var _guide := {}               # running walkthrough (see _build)
var _reached := 0              # steps ticked so far (never goes back, so the list doesn't flicker)
var _dialog: Tutorial
var _canvas: Node2D
var _time := 0.0
var _result := ""
var _result_good := true
var _result_left := 0.0


func _ready() -> void:
	layer = 12                 # over the HUD, under minigames (15) and dialogs (20)
	_canvas = Node2D.new()
	UiKit.setup_canvas(_canvas)
	_canvas.draw.connect(_draw_guide)
	add_child(_canvas)
	Events.state_changed.connect(_on_state)


func _on_state(state: Dictionary) -> void:
	_state = state
	for id: String in TERMS:
		if _triggered(id):
			Codex.unlock(TERMS[id])   # no-op once unlocked
	if Tutorial.is_off() or (_dialog and _dialog.is_open()):
		return
	for id: String in ORDER:
		if not _triggered(id) or Tutorial.was_seen("event_" + id):
			continue
		if _guide.get("id", "") == id:
			break
		var can_cut: bool = _guide.is_empty() or _rank(id) > _rank(_guide.id) or _rank(_guide.id) == 1
		if can_cut and not Tutorial.is_blocking():
			_start(id)
		break


## Who may cut whom: timed space weather (3) > hull breach (2, the crew can die) > the rest (1).
## Rank-1 walkthroughs also give way to each other, so a long repair never hides a new fault.
func _rank(id: String) -> int:
	return 3 if id in CRITICAL else (2 if id == "breach" else 1)


# --- triggers ------------------------------------------------------------------------------

func _triggered(id: String) -> bool:
	var cme: Dictionary = _state.get("cme", {})
	match id:
		"storm_shields":
			return cme.get("phase", "") == "warning" and cme.get("shielding", false) and not cme.get("shields", false)
		"storm_safe":
			return cme.get("phase", "") == "warning" and not cme.get("shielding", false) and not cme.get("safe", false)
		"debris":
			return _state.get("dust", {}).get("phase", "") in ["warning", "stream"]
		"blackout":
			return float(_state.get("blackout", 0.0)) > 0.0
		"repair":
			return not _state.get("offline", []).is_empty()
		"breach":
			return not _state.get("breaches", []).is_empty()
		"low_power":
			return float(_state.get("power", 100.0)) < 25.0 and float(_state.get("blackout", 0.0)) <= 0.0
		"data_full":
			return float(_state.get("data", 0.0)) > 85.0
		"conjunction":
			return _state.get("conjunction", {}).get("phase", "") == "warning"
		"moi":
			return _state.get("moi", {}).get("phase", "") == "window"
		_:
			return not _ticket(id).is_empty()


func _ticket(kind: String) -> Dictionary:
	for e: Dictionary in _state.get("events", []):
		if e.get("kind", "") == kind:
			return e
	return {}


func _ticket_by_id(id: int) -> Dictionary:
	for e: Dictionary in _state.get("events", []):
		if int(e.id) == id:
			return e
	return {}


# --- running a walkthrough -----------------------------------------------------------------

func _start(id: String) -> void:
	_guide = _build(id)
	_guide.id = id
	_guide.age = 0.0
	_reached = 0
	_result = ""
	if _dialog:
		_dialog.queue_free()
	_dialog = Tutorial.new()
	_dialog.screen_id = "event_" + id
	_dialog.panes = _guide.panes
	_dialog.hotkey = false     # H keeps reopening the cruise tutorial, not this one
	_dialog.name = "EventTutorial"
	add_child(_dialog)
	_dialog.open()


func _process(delta: float) -> void:
	_time += delta
	_result_left = maxf(_result_left - delta, 0.0)
	if not _guide.is_empty() and not (_dialog and _dialog.is_open()):
		_guide.age += delta
		var steps: Array = _guide.steps
		while _reached < steps.size() and (steps[_reached].done as Callable).call():
			_reached += 1
			if _reached < steps.size():
				Sfx.play("select", 1.4)
		if (_guide.over as Callable).call() or _guide.age > float(_guide.get("timeout", 60.0)):
			var out: Array = (_guide.outcome as Callable).call()
			_result = out[0]
			_result_good = out[1]
			_result_left = RESULT_TIME
			Sfx.play("fixed" if _result_good else "denied", 1.2)
			_guide = {}
	_canvas.queue_redraw()


# --- helpers for step checks ---------------------------------------------------------------

func _station(role: String) -> Station:
	return map.station_for_role(role) if map else null


## The local player is at (in the ring of, or docked at) the station for `role`.
func _at(role: String) -> bool:
	if local == null:
		return false
	var s := local.near_station()
	return s != null and s.role == role


func _docked(role: String) -> bool:
	return local != null and local.docked_station() != null and local.docked_station().role == role


func _offline(role: String) -> bool:
	return role in _state.get("offline", [])


## "Go to" step text that switches to "repair it first" when that station is broken.
func _go_text(role: String) -> String:
	if _offline(role):
		return "%s is OFFLINE: dock and HOLD SPACE to repair it first" % PLACE[role]
	return "%s: go to the %s" % [WHO[role], PLACE[role]]


func _step(text: Variant, role: String, done: Callable, point := Callable()) -> Dictionary:
	return {text = text, role = role, done = done, point = point}   # point() -> Vector2: arrow target


# --- the walkthroughs ------------------------------------------------------------------------
# Each: title, panes (dialog), steps [{text (String or Callable), role (arrow target), done}],
# over() -> bool, outcome() -> [text, good], optional timeout (s).

func _build(id: String) -> Dictionary:
	var s := _state
	var cme: Dictionary = s.get("cme", {})
	match id:
		"storm_shields":
			var charges := int(_ticket("shields").get("charges", 3))
			return {
				title = "RADIATION STORM",
				panes = [
					{title = "Radiation storm!", rect = _banner_rect(),
					 body = "The Sun just threw out a burst of fast particles (a solar particle event). The wave hits in %d s. Unprotected, it fries electronics: blackout and broken stations." % ceili(cme.get("time_left", 0))},
					{title = "Raise the shield", rect = ROOMS.team,
					 body = "Your ship has RADIATION SHIELDING. Anyone: run to the Mission Hub table and press SPACE. Then press SPACE while the needle is in the GREEN zone, %d times. Each charge makes it faster." % charges},
					{title = "Parts that help",
					 body = "Rad-hard computer: one fewer charge. Solar particle monitor: 7 s more warning. RTG: keeps power on even in a blackout. Real probes survive with shielding mass, rad-hard chips and safe mode (SIMPLIFIED)."},
				],
				steps = [
					_step(_go_text.bind("team"), "team", func() -> bool: return _at("team") or _shield_open() or _shields()),
					_step("Press SPACE at the table to open the shield panel", "team", func() -> bool: return _shield_open() or _shields()),
					_step("SPACE when the needle is in the GREEN zone (x%d)" % charges, "", _shields),
					_step("Shields up! Wait for the wave", "", func() -> bool: return false),
				],
				over = func() -> bool: return _state.get("cme", {}).get("phase", "") != "warning",
				outcome = func() -> Array:
					return ["STORM BEATEN - shields held, storm data recorded", true] if _shields() \
						else ["SHIP DISABLED - raise the shield before the timer runs out", false],
			}
		"storm_safe":
			return {
				title = "RADIATION STORM",
				panes = [
					{title = "Radiation storm!", rect = _banner_rect(),
					 body = "The Sun just threw out a burst of fast particles (a solar particle event). The wave hits in %d s. Unprotected, it fries electronics: blackout and broken stations." % ceili(cme.get("time_left", 0))},
					{title = "Safe mode", rect = ROOMS.engineer,
					 body = "This ship has NO radiation shielding, so the only defence is to power down. ENGINEER: dock at the Engine Room console and press SPACE. Then cut the BLINKING breaker each time (A/D move, SPACE flip) - the order changes every storm."},
					{title = "Storm shelter", rect = ROOMS.cargo,
					 body = "Safe mode protects the SHIP, not the people. EVERYONE must be inside the CARGO bay when the wave hits - its stowage walls block most of the particles (Orion crews really shelter like this). Caught outside = a big radiation dose; past 500 mSv an astronaut gets sick and works slower."},
					{title = "The trade-off",
					 body = "Safe mode protects the ship, but instruments and transmitter stay off until the storm passes - science and downlink stop. When it has passed, the ENGINEER gets a POWER UP ticket: hold SPACE once and both come back on. Want to keep working through storms? Buy Radiation shielding (heavy) in design."},
				],
				steps = [
					_step(_go_text.bind("engineer"), "engineer", func() -> bool: return _at("engineer") or _safe_open() or _safe()),
					_step("Press SPACE at the console to open the breaker panel", "engineer", func() -> bool: return _safe_open() or _safe()),
					_step("Cut the BLINKING breaker: A/D move, SPACE flip", "", _safe),
					_step("EVERYONE into the CARGO bay (storm shelter)", "", _all_sheltered,
							func() -> Vector2: return ROOMS.cargo.get_center()),
				],
				over = func() -> bool: return _state.get("cme", {}).get("phase", "") != "warning",
				outcome = func() -> Array:
					if not _safe():
						return ["SHIP DISABLED - enter safe mode before the timer runs out", false]
					if not _all_sheltered():
						return ["SHIP SAFE - but someone was caught OUTSIDE the shelter (big dose)", false]
					return ["SAFE MODE HELD + CREW SHELTERED - Engineer: POWER UP after the storm", true],
			}
		"debris":
			var start_hits := int(s.get("dust", {}).get("hits", 0))
			var wheels: bool = s.get("dust", {}).get("wheels", false)
			return {
				title = "COMET DEBRIS",
				panes = [
					{title = "Comet debris!", rect = _banner_rect(),
					 body = "The ship is crossing the trail a comet left behind along its orbit. Real trails are mostly fine dust - here it comes in chunks (SIMPLIFIED). It arrives in %d s." % ceili(s.get("dust", {}).get("time_left", 0))},
					{title = "Radar", rect = ROOMS.navigator,
					 body = "NAVIGATOR: dock at the Bridge and press E for the RADAR: the cloud closing in and your projected path. A/D = course burn: the heading turns 5 degrees, and each burn costs fuel. One or two burns usually clear it."},
					{title = "Your choice",
					 body = "Spend fuel NOW and steer clear: the debris passes you by. Or save the fuel and fly THROUGH it yourself (full screen, risky). Steering half-way leaves a thinner field. Nobody at the Bridge = the ship takes the hits."},
					{title = "Flying",
					 body = "A/D turn, W thrust, S brake. Fly off one edge and you come back on the other. Survive 6 seconds. A heavier ship is slower to speed up and turn. Every hit wears the hull and can punch a breach; thrusting costs fuel."},
					{title = "Parts that help",
					 body = "Reaction wheels: fast turning that costs no fuel%s. Star tracker: 4 s more warning, and red arrows show where rocks come from." % (" (you have them)" if wheels else "")},
				],
				steps = [
					_step(_go_text.bind("navigator"), "navigator", func() -> bool: return _docked("navigator") or _dust_phase() == "flying"),
					_step(func() -> String: return "E: radar. A/D burn clear (fuel) - or fly it: %ds" % ceili(_state.get("dust", {}).get("time_left", 0)) if _dust_phase() == "warning" else "Stay docked - here it comes!",
						"navigator", func() -> bool: return _dust_phase() == "flying"),
					_step("Fly! A/D turn - W thrust - S brake", "", func() -> bool: return false),
				],
				over = func() -> bool: return _dust_phase() == "",
				outcome = func() -> Array:
					if _state.get("last_action", "").begins_with("COURSE CHANGE"):
						return ["STEERED CLEAR - fuel spent, no risk", true]
					var hits := int(_state.get("dust", {}).get("hits", 0)) - start_hits
					if hits == 0:
						return ["CLEAN RUN - no hits!", true]
					return ["%d HIT%s - check the tickets for broken stations" % [hits, "" if hits == 1 else "S"], hits < 3],
			}
		"breach":
			var b0: Dictionary = s.get("breaches", [{}])[0]
			var hole := Vector2(float(b0.get("x", 240)), float(b0.get("y", 135)))
			return {
				title = "HULL BREACH",
				panes = [
					{title = "Hull breach!", rect = UiKit.world_rect(Rect2(hole - Vector2(18, 16), Vector2(36, 30))),
					 body = "A hit punched a hole in the hull and air is venting into space. Every open hole drains OXYGEN (top right). At 0% the crew is lost."},
					{title = "Grab a toolbox", rect = UiKit.world_rect(Rect2(HullDamage.LOCKERS[0] - Vector2(16, 14), Vector2(32, 28))),
					 body = "Toolboxes hang in RED LOCKERS in the Cargo bay and the Engine Room. Walk up and press SPACE to take one (SPACE again puts it back)."},
					{title = "Patch it", rect = UiKit.hud_rect("resources").grow(1),
					 body = "Walk to the hole and HOLD SPACE until the ring fills. The weaker the HULL, the likelier the next hit punches another hole. Heavy class and the Whipple shield make it tougher."},
				],
				steps = [
					_step("Grab a toolbox: red locker in CARGO or ENGINE ROOM", "",
						func() -> bool: return (local != null and local.has_toolbox) or _state.get("breaches", []).is_empty(),
						_nearest_locker),
					_step("Go to the hole", "", func() -> bool: return _near_breach() or _state.get("breaches", []).is_empty(), _first_breach),
					_step("HOLD SPACE until the ring fills", "", func() -> bool: return _state.get("breaches", []).is_empty(), _first_breach),
				],
				over = func() -> bool: return _state.get("breaches", []).is_empty() or _state.get("lost", "") != "",
				outcome = func() -> Array:
					return ["HULL SEALED - oxygen refilling", true] if _state.get("lost", "") == "" \
						else ["OUT OF OXYGEN", false],
				timeout = 120.0,
			}
		"blackout":
			return {
				title = "BLACKOUT",
				panes = [
					{title = "Blackout", rect = _banner_rect(),
					 body = "The radiation tripped the solar power bus: everything is off and the battery is draining. A dead ship can't steer - a stray meteoroid may hit it. Only an RTG (nuclear power) keeps making power through a blackout."},
					{title = "Recover",
					 body = "Wait for the bus to come back. Then the ENGINEER switches loads back on (A/D pick, SPACE switch), and broken stations get repaired: dock and HOLD SPACE."},
				],
				steps = [
					_step(func() -> String: return "Wait for power (%ds)" % ceili(_state.get("blackout", 0)), "", func() -> bool: return float(_state.get("blackout", 0)) <= 0.0),
					_step(_go_text.bind("engineer"), "engineer", func() -> bool: return _docked("engineer") or _loads_on()),
					_step("A/D pick a load, SPACE switches it ON", "engineer", _loads_on),
				],
				over = func() -> bool: return float(_state.get("blackout", 0)) <= 0.0 and _loads_on(),
				outcome = func() -> Array:
					return ["POWER BACK - repair any station marked X", true] if _loads_on() \
						else ["Loads are still OFF - Engineer: switch them on", false],
				timeout = 35.0,
			}
		"repair":
			var role: String = s.get("offline", [""])[0]
			return {
				title = "STATION OFFLINE",
				panes = [
					{title = "Station offline", rect = UiKit.world_rect(ROOMS.get(role, Rect2())),
					 body = "The %s is broken (a missed ticket or damage). It's useless until someone repairs it. Repairs have no timer, but every second it's down hurts." % PLACE.get(role, role)},
					{title = "Repair it",
					 body = "Walk into its ring, SPACE to dock, then HOLD SPACE until the ring fills. The Radiator part makes repairs 40% faster."},
				],
				steps = [
					_step("Go to the %s" % PLACE.get(role, role), role, func() -> bool: return _at(role) or not _offline(role)),
					_step("SPACE to dock, then HOLD SPACE to repair", role, func() -> bool: return not _offline(role)),
				],
				over = func() -> bool: return not _offline(role),
				outcome = func() -> Array: return ["%s BACK ONLINE" % PLACE.get(role, role), true],
				timeout = 90.0,
			}
		"low_power":
			return {
				title = "LOW BATTERY",
				panes = [
					{title = "Battery low", rect = UiKit.hud_rect("resources").grow(1),
					 body = "The loads use more power than the panels make, and the battery is almost empty. At zero everything trips off (brownout). Sunlight also gets weaker the farther you fly from the Sun."},
					{title = "Save power", rect = ROOMS.engineer,
					 body = "ENGINEER: at the Engine Room, A/D pick a load and SPACE to switch it OFF (the heater and instruments are hungry). In design: bigger solar, RTG or battery - each costs mass."},
				],
				steps = [
					_step(_go_text.bind("engineer"), "engineer", func() -> bool: return _docked("engineer") or _power_ok()),
					_step("Switch a load OFF (A/D pick, SPACE)", "engineer", _power_ok),
				],
				over = _power_ok,
				outcome = func() -> Array:
					return ["POWER SAVED - the battery is recovering", true] if _power_ok() \
						else ["Still draining - switch more loads off", false],
				timeout = 40.0,
			}
		"data_full":
			return {
				title = "STORAGE FULL",
				panes = [
					{title = "Storage almost full", rect = UiKit.hud_rect("resources").grow(1),
					 body = "The recorder is almost full. New science that doesn't fit is LOST, and only science that reaches Earth scores."},
					{title = "Send it home", rect = ROOMS.comms,
					 body = "COMMS: dock at Comms and HOLD SPACE while a Deep Space Network station is in view (transmitter on). Recorders store more; a high-gain dish sends faster."},
				],
				steps = [
					_step(_go_text.bind("comms"), "comms", func() -> bool: return _docked("comms") or _data_ok()),
					_step(func() -> String:
						var dsn: Dictionary = _state.get("dsn", {})
						if dsn.get("site", "") == "":
							return "Wait for a DSN station (%ds), then HOLD SPACE" % ceili(dsn.get("time_left", 0))
						return "HOLD SPACE: downlink to %s" % dsn.site, "comms", _data_ok),
				],
				over = _data_ok,
				outcome = func() -> Array:
					return ["DATA SENT HOME", true] if _data_ok() else ["Storage still full - science is being lost", false],
				timeout = 45.0,
			}
		"conjunction":
			var lost0 := float(s.get("science_lost", 0.0))
			return {
				title = "SOLAR CONJUNCTION",
				panes = [
					{title = "Solar conjunction", rect = _banner_rect(),
					 body = "The Sun is about to pass between the ship and Earth. Its radio noise drowns every signal: no downlink for a while. (Real conjunctions come every ~26 months and last about two weeks.)"},
					{title = "Empty the recorder", rect = ROOMS.comms,
					 body = "COMMS: downlink everything NOW while a DSN station is in view. ENGINEER: switching the instruments OFF stops new data piling up while nothing can be sent. A big recorder rides it out."},
				],
				steps = [
					_step(_go_text.bind("comms"), "comms", func() -> bool: return _docked("comms") or _conj_phase() != "warning"),
					_step(func() -> String: return "HOLD SPACE: empty the recorder (DATA %d%%)" % int(_state.get("data", 0)),
							"comms", func() -> bool: return float(_state.get("data", 100)) < 25.0 or _conj_phase() != "warning"),
					_step("Ride out the blackout (instruments OFF = no overflow)", "engineer",
							func() -> bool: return _conj_phase() == "done"),
				],
				over = func() -> bool: return _conj_phase() == "done",
				outcome = func() -> Array:
					var lost := float(_state.get("science_lost", 0.0)) - lost0
					return ["CONTACT BACK - no science lost", true] if lost < 1.0 \
						else ["CONTACT BACK - %d science overflowed" % int(lost), false],
				timeout = 60.0,
			}
		"moi":
			return {
				title = "MARS ORBIT INSERTION",
				panes = [
					{title = "Arriving at Mars", rect = UiKit.hud_rect("tasks").grow(1),
					 body = "Brake now or fly straight past Mars. Real spacecraft do this burn on their own: Earth is minutes away by radio, too far to help in time."},
					{title = "Hold the brake", rect = ROOMS.navigator,
					 body = "NAVIGATOR: dock at the Bridge and HOLD SPACE until the ring fills. The burn needs FUEL and at least 10% BATTERY - ENGINEER: switch loads off if power is low."},
				],
				steps = [
					_step(_go_text.bind("navigator"), "navigator", func() -> bool: return _docked("navigator") or _moi_done()),
					_step(func() -> String: return "HOLD SPACE: brake (fuel %d%%, battery %d%%)" % [int(_state.get("fuel", 0)), int(_state.get("power", 0))],
							"navigator", _moi_done),
				],
				over = _moi_done,
				outcome = func() -> Array:
					var o := str(_state.get("finished", {}).get("outcome", ""))
					return ["IN ORBIT AROUND MARS!", true] if o == "orbit" else [o.to_upper() + " - no orbit", false],
				timeout = 40.0,
			}
		"science_window":
			return _fault_guide("science_window", "scientist", "SCIENCE WINDOW", [
				{title = "Science window", rect = UiKit.hud_rect("tasks").grow(1),
				 body = "Something worth observing is happening (here: a dust storm on Mars). The window closes when the ticket's timer runs out."},
				{title = "Observe", rect = ROOMS.scientist,
				 body = "SCIENTIST: dock at the Science Lab and HOLD SPACE. The instruments must be ON (the Engineer switches them)."},
				{title = "How science scores", rect = UiKit.hud_rect("progress").grow(1),
				 body = "An observation goes into the RECORDER (DATA bar, STORED). It only scores once COMMS sends it home during a DSN pass (SENT). A full recorder can't take more: new science is LOST. So keep downlinking!"},
			], "Observation stored - now downlink it", "WINDOW MISSED - the science is lost")
		"solar_storm":
			return _fault_guide("solar_storm", "engineer", "STORM FAULT", [
				{title = "Solar storm fault", rect = UiKit.hud_rect("tasks").grow(1),
				 body = "Charged particles flipped bits in the power electronics. Fix it before the ticket's timer runs out, or the Engine Room goes OFFLINE."},
				{title = "Reset it", rect = ROOMS.engineer,
				 body = "ENGINEER: dock at the Engine Room and HOLD SPACE until the ring fills. A rad-hard computer makes these faults much rarer."},
			], "FAULT CLEARED", "MISSED - Engine Room OFFLINE, repair it")
		"thruster_leak":
			return _fault_guide("thruster_leak", "navigator", "THRUSTER LEAK", [
				{title = "Thruster leak", rect = UiKit.hud_rect("tasks").grow(1),
				 body = "A thruster valve is stuck and leaking propellant. Fix it before the ticket's timer runs out, or the Bridge goes OFFLINE."},
				{title = "Close the valve", rect = ROOMS.navigator,
				 body = "NAVIGATOR: dock at the Bridge and HOLD SPACE until the ring fills. Reaction wheels mean the thrusters fire less, so leaks are rarer."},
			], "LEAK FIXED", "MISSED - Bridge OFFLINE, repair it")
		"antenna_glitch":
			return _fault_guide("antenna_glitch", "comms", "ANTENNA GLITCH", [
				{title = "Antenna glitch", rect = UiKit.hud_rect("tasks").grow(1),
				 body = "The antenna lost its lock on Earth. Fix it before the ticket's timer runs out, or Comms goes OFFLINE and nothing gets sent home."},
				{title = "Re-point it", rect = ROOMS.comms,
				 body = "COMMS: dock at the Comms console and HOLD SPACE until the ring fills."},
			], "ANTENNA LOCKED", "MISSED - Comms OFFLINE, repair it")
	return {}


## Walkthrough for a timed ticket on one station (faults and science windows).
func _fault_guide(kind: String, role: String, title: String, panes: Array, good: String, bad: String) -> Dictionary:
	var id := int(_ticket(kind).get("id", -1))
	var last := {left = 99.0}
	var obs0 := int(_state.get("observations", 0))
	var steps := [_step(_go_text.bind(role), role, func() -> bool: return _docked(role) or _ticket_by_id(id).is_empty())]
	if kind == "science_window":
		steps.push_front(_step("Instruments must be ON (Engineer)", "engineer",
				func() -> bool: return _state.get("loads", {}).get("instruments", false) or _ticket_by_id(id).is_empty()))
	steps.append(_step("HOLD SPACE until the ring fills", role, func() -> bool: return _ticket_by_id(id).is_empty()))
	return {
		title = title, panes = panes, steps = steps,
		over = func() -> bool:
			var t := _ticket_by_id(id)
			if not t.is_empty():
				last.left = float(t.time_left)
			return t.is_empty(),
		outcome = func() -> Array:
			var missed: bool = _offline(role) if kind in FAULTS else int(_state.get("observations", 0)) == obs0
			return [bad, false] if missed else [good, true],
		timeout = 60.0,
	}


func _conj_phase() -> String:
	return str(_state.get("conjunction", {}).get("phase", ""))


func _moi_done() -> bool:
	return not _state.get("finished", {}).is_empty()


func _nearest_locker() -> Vector2:
	var from := local.global_position if local else Vector2(240, 135)
	var best: Vector2 = HullDamage.LOCKERS[0]
	for p: Vector2 in HullDamage.LOCKERS:
		if from.distance_to(p) < from.distance_to(best):
			best = p
	return best


func _first_breach() -> Vector2:
	var list: Array = _state.get("breaches", [])
	if list.is_empty():
		return Vector2(-1, -1)
	var from := local.global_position if local else Vector2(240, 135)
	var best := Vector2(list[0].x, list[0].y)
	for b: Dictionary in list:
		if from.distance_to(Vector2(b.x, b.y)) < from.distance_to(best):
			best = Vector2(b.x, b.y)
	return best


func _near_breach() -> bool:
	return local != null and HullDamage.current != null and not HullDamage.current.breach_near(local.global_position).is_empty()


func _shields() -> bool:
	return _state.get("cme", {}).get("shields", false)


func _safe() -> bool:
	return _state.get("cme", {}).get("safe", false)


## Every astronaut stands in the Cargo bay (the storm shelter).
func _all_sheltered() -> bool:
	var crew: Dictionary = _state.get("crew", {})
	for key: String in crew:
		if crew[key].get("room", "") != "cargo":
			return false
	return not crew.is_empty()


func _shield_open() -> bool:
	var st := _station("team")
	return st != null and st.minigame() is ShieldGame


func _safe_open() -> bool:
	var st := _station("engineer")
	return st != null and st.minigame() is SafeModeGame


func _dust_phase() -> String:
	return _state.get("dust", {}).get("phase", "")


func _loads_on() -> bool:
	var loads: Dictionary = _state.get("loads", {})
	return loads.get("instruments", false) or loads.get("transmitter", false)


func _power_ok() -> bool:
	return float(_state.get("power", 0.0)) >= 32.0


func _data_ok() -> bool:
	return float(_state.get("data", 100.0)) < 60.0


# --- drawing (UI kit) ------------------------------------------------------------------------

## Where the alert strip sits (under the HUD's mission progress block).
func _banner_rect() -> Rect2:
	var p := UiKit.hud_rect("progress", Rect2(140, 2, 200, 26))
	return UiKit.hud_rect("alert", Rect2(p.position.x, p.end.y + 2, p.size.x, 14)).grow(1)


## Top of the free space under the HUD's top-centre blocks.
func _below_hud() -> float:
	var y := UiKit.hud_rect("progress", Rect2(0, 0, 0, 28)).end.y
	if UiKit.hud.has("alert"):
		y = UiKit.hud_rect("alert").end.y
	return y + 2


func _draw_guide() -> void:
	var c := _canvas
	var top := _below_hud()
	UiKit.overlays.erase("guide")
	if not _guide.is_empty() and not (_dialog and _dialog.is_open()):
		var steps: Array = _guide.steps
		var i := mini(_reached, steps.size() - 1)
		var step: Dictionary = steps[i]
		var text: String = (step.text as Callable).call() if step.text is Callable else str(step.text)
		var head := "HOW TO BEAT IT: %s" % _guide.title
		var line := "%d. %s" % [i + 1, text.to_upper()]
		var dots_w := steps.size() * 7.0
		var w := maxf(UiKit.text_w(line, 8), UiKit.text_w(head, 7) + dots_w + 8) + 14.0
		var h := 6 + UiKit.line_h(7) + UiKit.line_h(8) + 2
		var box := Rect2(roundf(240.0 - w / 2.0), top, roundf(w), roundf(h))
		UiKit.panel(c, box, UiKit.PANEL_DARK, Station.ROLE_COLORS.navigator)
		UiKit.overlays.guide = box
		var head_base := box.position.y + 3 + UiKit.line_h(7) - 1
		UiKit.text(c, Vector2(box.position.x + 6, head_base), head, 7, Station.ROLE_COLORS.navigator, 0)
		# Step chips: done = green, current = blinking white.
		for k in steps.size():
			var col := UiKit.GOOD if k < _reached else (Color.WHITE if fmod(_time, 0.6) < 0.4 else UiKit.DIM) if k == i else UiKit.FAINT
			UiKit.chip(c, Rect2(box.end.x - 6 - (steps.size() - k) * 7 + 2, box.position.y + 4, 5, 5), col)
		UiKit.text(c, Vector2(box.position.x + 6, box.end.y - 4), line, 8, UiKit.TEXT)
		# Where to go: room outline + bouncing arrow over the station (map coordinates -> screen).
		c.draw_set_transform(UiKit.world_offset)
		var role: String = step.role
		var st := _station(role) if role != "" else null
		var point: Callable = step.get("point", Callable())
		if point.is_valid() and local:
			var target: Vector2 = point.call()
			if target.x >= 0.0 and target.distance_to(local.global_position) > 10.0:
				var tip2 := target + Vector2(0, -12 - 3.0 * absf(sin(_time * 5.0)))
				c.draw_colored_polygon(PackedVector2Array([tip2, tip2 + Vector2(-5, -6), tip2 + Vector2(-2, -6),
						tip2 + Vector2(-2, -12), tip2 + Vector2(2, -12), tip2 + Vector2(2, -6), tip2 + Vector2(5, -6)]),
						Color("ffc640"))
				_arrow_from_player(target)
		elif st and local and not _docked(role):
			var room: Rect2 = ROOMS.get(role, Rect2())
			var pulse := 0.4 + 0.4 * sin(_time * 6.0)
			c.draw_rect(room.grow(1), Color(1.0, 0.85, 0.3, pulse), false, 1.0)
			var tip := (st.global_position + Vector2(0, -st.radius - 20 - roundf(3.0 * absf(sin(_time * 5.0))))).round()
			var arrow := PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(-2, -6),
					tip + Vector2(-2, -12), tip + Vector2(2, -12), tip + Vector2(2, -6), tip + Vector2(5, -6)])
			var outline := PackedVector2Array()
			for p in arrow:
				outline.append(p + (p - (tip + Vector2(0, -7))).sign())  # 1 px bigger: ink outline
			c.draw_colored_polygon(outline, UiKit.INK)
			c.draw_colored_polygon(arrow, UiKit.WARN)
			_arrow_from_player(st.global_position)
		c.draw_set_transform(Vector2.ZERO)
	if _result_left > 0.0:
		# Outcome stamp: slams in, sits, fades in its last second.
		var age := RESULT_TIME - _result_left
		var col := UiKit.GOOD if _result_good else UiKit.BAD
		col.a = minf(_result_left, 1.0)
		UiKit.stamp(c, Vector2(240, top + 14), _result, col, clampf(1.0 - age / 0.18, 0.0, 1.0), 12)


## A small chevron at the local player's feet pointing toward the target station.
func _arrow_from_player(to: Vector2) -> void:
	var from := local.global_position
	if from.distance_to(to) < 40.0:
		return
	var dir := (to - from).normalized()
	var p := from + dir * 14.0 + Vector2(0, -6)
	var side := dir.orthogonal() * 3.0
	_canvas.draw_colored_polygon(PackedVector2Array([p + dir * 5.0, p - dir * 2.0 + side, p - dir * 2.0 - side]),
			Color(1.0, 0.78, 0.25, 0.6 + 0.4 * sin(_time * 8.0)))
