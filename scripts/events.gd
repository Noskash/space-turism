extends Node
## Signal bus — the ONLY link between the sim (Person A) and the game/UI (Person B).
## Autoloaded as `Events`. Changing a signal here is a contract change: agree on it first.

## Game/UI -> sim. `role` is the crew role acting ("navigator", "engineer", "comms",
## "scientist", "team"); `action` is a plain dictionary, e.g. {type = "burn", dir = "prograde"}.
signal action_requested(role: String, action: Dictionary)

## Sim -> game/UI. Full snapshot of what the HUD and stations need to draw.
signal state_changed(state: Dictionary)

## Sim -> game/UI. A hazard started: {id, kind, role, ...}. Stations of `role` play `alarm`.
signal event_started(event: Dictionary)
signal event_ended(id: String)

## Sim -> game/UI. Mission over; `report` feeds the Report screen.
signal mission_finished(report: Dictionary)
