class_name Forecast
extends RefCounted
## What the crew can see coming on the flight, for the FLIGHT PLAN at the Mission Hub holo-table (PlanBoard).
## Real named comets and asteroids, the cold zone, solar conjunction. The sim (fake_mission) builds the list at
## start (state.forecast) and acts on it when the ship reaches each day; the crew plans ahead (state.plan).
## Solar storms are NOT here on purpose: they can't be forecast weeks ahead (only minutes to hours).
## SIMPLIFIED: real close passes of comet trails / asteroids are rare; here the distances are made small.

## Comets whose dust trails cross the inner solar system. Facts checked against NASA/JPL pages (2026-11).
const COMETS := [
	{name = "2P/Encke", fact = "Around the Sun every 3.3 years - the shortest of any big comet. Its dust makes Earth's Taurid meteors."},
	{name = "1P/Halley", fact = "Back every ~76 years. Its dust gives Earth two meteor showers a year: the Orionids and Eta Aquariids."},
	{name = "109P/Swift-Tuttle", fact = "Parent of the Perseid meteors every August. Its icy core is about 26 km across."},
	{name = "55P/Tempel-Tuttle", fact = "Parent of the Leonids. When Earth crossed its dense trails (1966, 1999-2002) the sky had meteor storms."},
	{name = "21P/Giacobini-Zinner", fact = "In 1985 NASA's ICE probe flew right through its tail - the first spacecraft to visit a comet."},
	{name = "C/2013 A1 Siding Spring", fact = "Passed ~140,000 km from Mars in Oct 2014. MRO, Odyssey and MAVEN hid behind Mars from its dust."},
]
## Near-Earth asteroids whose orbits reach the Earth-Mars space.
const ASTEROIDS := [
	{name = "433 Eros", fact = "First asteroid a spacecraft orbited: NEAR Shoemaker in 2000, which then landed on it in 2001."},
	{name = "1036 Ganymed", fact = "The biggest near-Earth asteroid, about 35 km across. Its orbit swings out past Mars."},
	{name = "101955 Bennu", fact = "OSIRIS-REx grabbed a sample of it in 2020 and dropped it off at Earth in 2023."},
	{name = "162173 Ryugu", fact = "Japan's Hayabusa2 brought pieces of it home in 2020."},
	{name = "25143 Itokawa", fact = "Peanut-shaped. Hayabusa brought the first asteroid dust ever back to Earth from it in 2010."},
	{name = "3200 Phaethon", fact = "A 'rock comet': sheds the dust of the Geminid meteors and swings closer to the Sun than Mercury."},
	{name = "4179 Toutatis", fact = "China's Chang'e 2 flew past it in 2012, just a few km away, and photographed it."},
]
## Per kind: who acts, what planning it does, what it costs (the trade-off), icon.
const KIND_INFO := {
	comet = {role = "navigator", icon = "comet", label = "COMET TRAIL",
		plan = "PLANNED BURN: steer clear of the trail before it arrives (small fuel cost, no debris).",
		skip = "Unplanned: debris on the radar with only seconds to react - emergency burns or fly through it."},
	asteroid = {role = "scientist", icon = "asteroid", label = "ASTEROID FLYBY",
		plan = "POINT THE CAMERA: a flyby window opens for the Scientist - 2x science (costs power + storage).",
		skip = "Unplanned: it flies past and nobody is looking. Real flybys are planned months ahead."},
	cold = {role = "engineer", icon = "fuel", label = "COLD ZONE",
		plan = "THERMOSTAT: from here the heater switches itself on when the tanks get cold, off when warm (it still draws power).",
		skip = "Unplanned: the fuel lines cool down until the Engineer gets a FREEZING ticket."},
	conjunction = {role = "comms", icon = "dsn", label = "SOLAR CONJUNCTION",
		plan = "EXTRA DSN TIME booked: a station stays in view for the whole warning, empty the recorder.",
		skip = "Unplanned: the usual DSN passes come and go while the warning counts down."},
}


## The forecast for a flight of `days`: comet crossings at `comet_days`, 2 asteroid flybys, the cold zone
## (`cold_day` < 0 = none), the conjunction warning (`conj_day` < 0 = none). Sorted by day.
static func make(rng: RandomNumberGenerator, days: float, comet_days: Array, cold_day: float, conj_day: float) -> Array:
	var out := []
	var comets := COMETS.duplicate()
	comets.shuffle()
	for i in comet_days.size():
		var c: Dictionary = comets[i % comets.size()]
		out.append({kind = "comet", name = c.name, fact = c.fact, day = float(comet_days[i])})
	var rocks := ASTEROIDS.duplicate()
	rocks.shuffle()
	var slots := [rng.randf_range(0.22, 0.42), rng.randf_range(0.55, 0.8)]
	for i in 2:
		var a: Dictionary = rocks[i]
		var day: float = days * slots[i]
		for o: Dictionary in out:   # keep a few days from a comet crossing
			if absf(float(o.day) - day) < days * 0.06:
				day += days * 0.08
		out.append({kind = "asteroid", name = a.name, fact = a.fact, day = minf(day, days * 0.86)})
	if cold_day >= 0.0:
		out.append({kind = "cold", name = "Cold zone (~1.25 AU)", day = cold_day,
				fact = "Sunlight is weaker out here: without a heater the fuel lines cool towards freezing (hydrazine freezes near 2 C)."})
	if conj_day >= 0.0:
		out.append({kind = "conjunction", name = "Sun between ship and Earth", day = conj_day,
				fact = "Teams book extra Deep Space Network time before a conjunction to empty the recorder first."})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.day) < float(y.day))
	for i in out.size():
		out[i].id = i + 1
		out[i].role = KIND_INFO[out[i].kind].role
		out[i].done = false
	return out
