class_name Radio
extends Node
## Ship radio audio: CC0 jazz from OpenGameArt (music/CREDITS.md). The radio is an object on the
## map (RadioSet, Mission Hub bench): crew switch it on/off with SPACE, the sim keeps
## state.radio = {on, track}, so every co-op peer hears the same thing. Tracks play one after another.
## Runs on ship power: a blackout silences it; a radiation wave fills it with static.
## Music plays on its own "Music" bus (volume in the ESC menu, saved in user://settings.cfg).

const TRACKS := [
	{file = "res://music/drunken_saloon.mp3", title = "Drunken Saloon", artist = "iamoneabe"},
	{file = "res://music/jazz_improv.mp3", title = "Jazz Improvisation", artist = "Alex McCulloch"},
	{file = "res://music/jazz_n_brass.mp3", title = "Jazz n' Brass", artist = "Emma_MA"},
	{file = "res://music/jazz.mp3", title = "Jazz", artist = "umplix"},
	{file = "res://music/jazzcrashed.ogg", title = "Jazzcrashed", artist = "tozan"},
]
const BUS := "Music"
const LEVELS_DB := [-6.0, -11.0, -18.0, -80.0]
const LEVEL_NAMES := ["100%", "70%", "40%", "OFF"]

var _player: AudioStreamPlayer
var _index := -1               # track playing, -1 = off
var _on := false               # state.radio.on
var _state_track := -1         # last state.radio.track seen (local auto-advance may differ)
var _label: Label
var _powered := true
var _static := false
var _show := 0.0               # seconds the full title stays on screen


## Creates the Music bus once and applies the saved level (0..3).
static func apply_volume(level := -1) -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if level < 0:
		var cfg := ConfigFile.new()
		cfg.load("user://settings.cfg")
		level = int(cfg.get_value("audio", "music", 0))
	var bus := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_volume_db(bus, LEVELS_DB[clampi(level, 0, 3)])
	AudioServer.set_bus_mute(bus, level >= 3)


func setup(label: Label) -> Radio:
	_label = label
	name = "Radio"
	return self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # watches the pause itself: freezes with the game
	apply_volume()
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.finished.connect(func() -> void: _play(wrapi(_index + 1, 0, TRACKS.size())))
	add_child(_player)
	Events.state_changed.connect(_on_state)


func _exit_tree() -> void:
	Sfx.set_loop("static", false)


func _process(delta: float) -> void:
	_show = maxf(_show - delta, 0.0)
	_player.stream_paused = get_tree().paused
	_player.volume_db = lerpf(_player.volume_db, -14.0 if _static else 0.0, minf(delta * 4.0, 1.0))
	_update_label()


func _play(index: int) -> void:
	_index = index
	_show = 4.0
	if index < 0:
		_player.stop()
		return
	var stream: AudioStream = load(TRACKS[index].file)
	if stream == null:
		push_warning("Radio: missing " + TRACKS[index].file)
		return
	_player.stream = stream
	if _powered:
		_player.play()


## Outside the cruise (the assembly hangar has no sim): drive the radio directly.
func tune(on: bool, track: int) -> void:
	_on_state({radio = {on = on, track = track}})


## Title of the track playing ("" = off).
func now_playing() -> String:
	return "" if _index < 0 else str(TRACKS[_index].title)


## True for a few seconds after a track starts (show its title).
func showing() -> bool:
	return _show > 0.0


func _on_state(state: Dictionary) -> void:
	var radio: Dictionary = state.get("radio", {})
	var on: bool = radio.get("on", false)
	var track: int = int(radio.get("track", 0)) % TRACKS.size()
	if on != _on or (on and track != _state_track):
		_on = on
		_state_track = track
		_play(track if on else -1)
	var powered: bool = float(state.get("blackout", 0.0)) <= 0.0
	if powered != _powered:
		_powered = powered
		if _index >= 0:
			if powered:
				_player.play()
			else:
				_player.stop()
				Sfx.play("fizzle")
	var storm: bool = state.get("cme", {}).get("phase", "") == "wave"
	if storm != _static:
		_static = storm
		Sfx.set_loop("static", storm and _powered and _index >= 0)


func _update_label() -> void:
	if _label == null:
		return
	if _index < 0:
		_label.text = "RADIO OFF" if _show > 0.0 else ""
	elif not _powered:
		_label.text = "RADIO  -- NO POWER --"
	elif _show > 0.0:
		var t: Dictionary = TRACKS[_index]
		_label.text = "RADIO  %s - %s" % [t.title, t.artist]
	else:
		_label.text = "RADIO  " + str(TRACKS[_index].title)
