extends Node
## Sound effects. Autoloaded as `Sfx`, so it lives across scenes.
##
##   Sfx.play("fixed")                 one-shot (a small pool of players, so sounds overlap)
##   Sfx.play("step", 1.1, -8.0)       pitch scale, extra volume in dB
##   Sfx.set_loop("hum", true)         start / stop a looping sound
##
## Every Button anywhere in the game gets hover + click sounds automatically (hooked when it
## enters the tree), so menu scenes need no sound code. The WAVs in res://sounds are generated
## by sounds/gen_sounds.py.

const DIR := "res://sounds/"
const POOL_SIZE := 10
## Base volume per sound (dB); anything not listed plays at 0 dB.
const VOLUME := {
	"ui_hover": -10.0, "ui_click": -4.0, "step": -14.0, "work_tick": -8.0, "select": -6.0,
	"toast": -10.0, "hum": -12.0, "downlink": -6.0, "burn": -3.0, "alarm": -5.0,
	"engine": -14.0, "static": -12.0, "siren": -4.0, "lever": -6.0, "countdown": -4.0, "rocket": -2.0,
	"klaxon": -6.0, "fire": -8.0, "spray": -9.0, "ping": -4.0, "perfect": -6.0,
}
## Hover sounds are ignored right after a scene builds its UI (menus grab focus on _ready).
const HOVER_QUIET_MS := 200

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}  # name -> AudioStreamPlayer
var _last_node_added := 0
var _last_hover: BaseButton
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	get_tree().node_added.connect(_on_node_added)
	# Saved volume (set in the ESC menu, PauseMenu): 0 = 100% ... 3 = off.
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var level := int(cfg.get_value("audio", "volume", 0))
	AudioServer.set_bus_volume_db(0, [0.0, -6.0, -14.0, -80.0][clampi(level, 0, 3)])
	AudioServer.set_bus_mute(0, level >= 3)


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = VOLUME.get(sound, 0.0) + volume_db
	player.play()


func set_loop(sound: String, on: bool) -> void:
	var player: AudioStreamPlayer = _loops.get(sound)
	if on and player == null:
		var stream := _stream(sound)
		if stream == null:
			return
		stream = stream.duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player = AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = VOLUME.get(sound, 0.0)
		add_child(player)
		player.play()
		_loops[sound] = player
	elif not on and player != null:
		player.queue_free()
		_loops.erase(sound)


## Live volume (dB on top of the base) and pitch of a running loop, e.g. rocket roar vs throttle.
func tune_loop(sound: String, volume_db: float, pitch := 1.0) -> void:
	var player: AudioStreamPlayer = _loops.get(sound)
	if player:
		player.volume_db = VOLUME.get(sound, 0.0) + volume_db
		player.pitch_scale = maxf(pitch, 0.05)


## Freeze / resume every loop (the pause menu pauses the whole game).
func pause_loops(on: bool) -> void:
	for player: AudioStreamPlayer in _loops.values():
		player.stream_paused = on


func is_looping(sound: String) -> bool:
	return _loops.has(sound)


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + sound + ".wav"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
		if _streams[sound] == null:
			push_warning("Sfx: no sound %s" % path)
	return _streams[sound]


# --- automatic UI sounds -------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	_last_node_added = Time.get_ticks_msec()
	if node is BaseButton:
		node.mouse_entered.connect(_on_button_hover.bind(node))
		node.focus_entered.connect(_on_button_hover.bind(node))
		node.pressed.connect(_on_button_pressed.bind(node))


func _on_button_hover(button: BaseButton) -> void:
	var now := Time.get_ticks_msec()
	if button.disabled or now - _last_node_added < HOVER_QUIET_MS:
		return
	if button == _last_hover and now - _last_hover_ms < 150:
		return  # mouse_entered + focus_entered for the same hover
	_last_hover = button
	_last_hover_ms = now
	play("ui_hover")


func _on_button_pressed(_button: BaseButton) -> void:
	play("ui_click")
