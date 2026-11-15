class_name AlertBanner
extends RefCounted
## Emergency alerts for the cruise HUD.
##   1. A full-width slab slides in across the middle of the screen: big icon + 2-4 words.
##   2. It holds ~1 s (players keep control), then folds up into...
##   3. ...the alert strip under the mission progress block, which keeps the full instruction and
##      a countdown, blinking, for as long as the hazard lasts.
## Built from sim state only (MOI, oxygen / breaches, meteoroid, cme, blackout, dust, conjunction),
## so every co-op peer sees the same alerts.
## show_slab() is the generic entry point for any other alert.

const SLIDE := 0.18
const HOLD := 1.0
const FOLD := 0.25
const SLAB := Rect2(0, 114, 480, 40)

## Hazard id -> slab look. Hazards not listed here only get the strip.
const SLABS := {
	"cme_warning": {icon = "radiation", words = "RADIATION STORM", color = Color("ffe14a")},
	"cme_warning_shields": {icon = "shield", words = "SHIELDS UP", color = Color("8cd8ff")},
	"cme_warning_safe": {icon = "safe", words = "SAFE MODE ON", color = Color("8cd8ff")},
	"wave": {icon = "radiation", words = "WAVE HITS!", color = Color("ff5050")},
	"wave_shields": {icon = "shield", words = "SHIELDS HOLDING", color = Color("8cffb0")},
	"wave_safe": {icon = "safe", words = "SAFE MODE HOLDS", color = Color("8cffb0")},
	"blackout": {icon = "blackout", words = "BLACKOUT", color = Color("ff5050")},
	"dust_warning": {icon = "debris_big", words = "COMET DEBRIS", color = Color("e8c890")},
	"dust_stream": {icon = "fly", words = "PILOT NEEDED", color = Color("ff8a5c")},
	"moi": {icon = "mars", words = "MARS ARRIVAL", color = Color("ff8a4c")},
	"oxygen": {icon = "alert", words = "OXYGEN LOW", color = Color("ff5050")},
	"meteor": {icon = "debris_big", words = "METEOROID!", color = Color("ff5050")},
	"breach": {icon = "wrench", words = "HULL BREACH", color = Color("ffb04a")},
	"conj_warning": {icon = "dsn", words = "SOLAR CONJUNCTION", color = Color("ffe14a")},
}

var _key := ""
var _text := ""        # strip text; "%d" = local countdown
var _left := 0.0
var _color := Color.WHITE
var _icon := ""
var _slab := {}        # {icon, words, color, t}
var _strip_rect := Rect2()
var _juice := UiJuice.new()


func update(state: Dictionary) -> void:
	var cme: Dictionary = state.get("cme", {})
	var dust: Dictionary = state.get("dust", {})
	var blackout: float = state.get("blackout", 0.0)
	var meteor_left := float(state.get("meteor", {}).get("time_left", -1.0))
	var breaches: int = state.get("breaches", []).size()
	var o2 := float(state.get("oxygen", 100.0))
	var conj: Dictionary = state.get("conjunction", {})
	var moi: Dictionary = state.get("moi", {})
	var key := ""
	_text = ""
	var shields: bool = cme.get("shields", false)
	var safe: bool = cme.get("safe", false)
	var protected := shields or safe
	var suffix := "_shields" if shields else ("_safe" if safe else "")
	if state.get("lost", "") != "" or not state.get("finished", {}).is_empty():
		pass  # the game-over panel / mission report says it
	elif moi.get("phase", "") == "window":
		_text = "MARS ARRIVAL - NAVIGATOR: HOLD THE BRAKE AT THE BRIDGE! (%ds)"
		_left = _ticket_left(state, "moi")
		_color = Color("ff8a4c")
		_icon = "mars"
		key = "moi"
	elif breaches > 0 and o2 < 40.0:
		_text = "OXYGEN %d%% - PATCH THE HULL BREACH%s NOW!" % [int(o2), "ES" if breaches > 1 else ""]
		_color = Color("ff5050")
		_icon = "alert"
		key = "oxygen"
	elif meteor_left > 0.0 and meteor_left < 2.6:
		_text = "METEOROID INCOMING - NO POWER TO DODGE!"
		_color = Color("ff5050")
		_icon = "debris"
		key = "meteor"
	elif cme.get("phase", "") == "warning" and protected:
		_text = "SHIELDS UP - RADIATION STORM IN %ds" if shields else "SAFE MODE - STORM IN %ds - EVERYONE TO CARGO!"
		_left = cme.time_left
		_color = Color("8cd8ff")
		_icon = "shield" if shields else "safe"
		key = "cme_warning" + suffix
	elif cme.get("phase", "") == "warning":
		var todo := "RAISE THE SHIELDS (MISSION HUB)" if cme.get("shielding", false) else "SAFE MODE (ENGINE ROOM), THEN ALL TO CARGO"
		_text = "RADIATION STORM IN %ds - " + todo
		_left = cme.time_left
		_color = Color("ffe14a")
		_icon = "radiation"
		key = "cme_warning"
	elif cme.get("phase", "") == "wave":
		if shields:
			_text = "RADIATION WAVE - SHIELDS HOLDING"
		elif safe:
			_text = "RADIATION WAVE - SHIP IN SAFE MODE"
		else:
			_text = "RADIATION WAVE - SHIP UNPROTECTED!"
		_color = Color("8cffb0") if protected else Color("ff5050")
		_icon = "radiation"
		key = "wave" + suffix
	elif blackout > 0.0:
		_text = "BLACKOUT - SOLAR BUS TRIPPED (%ds)"
		_left = blackout
		_color = Color("ff5050")
		_icon = "blackout"
		key = "blackout"
	elif dust.get("phase", "") == "warning":
		_text = "DEBRIS IN %ds - NAVIGATOR: STEER AROUND IT AT THE BRIDGE"
		_left = dust.time_left
		_color = Color("e8c890")
		_icon = "debris"
		key = "dust_warning"
	elif dust.get("phase", "") == "stream":
		_text = "DEBRIS! NAVIGATOR: DOCK AT THE BRIDGE TO FLY (%ds)"
		_left = dust.time_left
		_color = Color("ff8a5c")
		_icon = "debris"
		key = "dust_stream"
	elif dust.get("phase", "") == "flying":
		_text = "NAVIGATOR IS FLYING THROUGH THE DEBRIS"
		_color = Color("e8c890")
		_icon = "fly"
		key = "dust_flying"
	elif breaches > 0:
		_text = "HULL BREACH%s - GRAB A TOOLBOX, HOLD SPACE ON THE HOLE" % ("ES" if breaches > 1 else "")
		_color = Color("ffb04a")
		_icon = "wrench"
		key = "breach"
	elif conj.get("phase", "") == "warning":
		_text = "SOLAR CONJUNCTION IN %ds - COMMS: EMPTY THE RECORDER NOW"
		_left = conj.time_left
		_color = Color("ffe14a")
		_icon = "dsn"
		key = "conj_warning"
	elif conj.get("phase", "") == "active":
		_text = "SOLAR CONJUNCTION - NO RADIO CONTACT (%ds)"
		_left = conj.time_left
		_color = Color("ffb04a")
		_icon = "lost"
		key = "conj_active"
	if key != _key:
		_key = key
		if SLABS.has(key):
			var look: Dictionary = SLABS[key]
			show_slab(look.icon, look.words, look.color)
		if key != "":
			_juice.kick("strip", 0.3)


## Slide a slab across the screen (any alert; 2-4 words read best).
func show_slab(icon_name: String, words: String, color: Color) -> void:
	_slab = {icon = icon_name, words = words, color = color, t = 0.0}


func step(delta: float) -> void:
	_juice.step(delta)
	_left = maxf(_left - delta, 0.0)
	if not _slab.is_empty():
		_slab.t += delta
		if _slab.t > SLIDE + HOLD + FOLD:
			_slab = {}


func active() -> bool:
	return _text != ""


## The strip under the progress block, centred on `top_center` but kept between `left` and
## `right` (it wraps to two lines when it does not fit); returns its rect (empty = none).
func draw_strip(ci: CanvasItem, top_center: Vector2, min_w: float, left := 2.0, right := 478.0) -> Rect2:
	if _text == "":
		_strip_rect = Rect2()
		return _strip_rect
	var text := _text % ceili(_left) if "%d" in _text else _text
	var size := 7
	var max_w := right - left
	var lines := UiKit.wrap(text, size, max_w - 30)
	var text_w := 0.0
	for line in lines:
		text_w = maxf(text_w, UiKit.text_w(line, size))
	var w := clampf(maxf(min_w, text_w + 30), 0.0, max_w)
	var lh := UiKit.line_h(size)
	var h := maxf(13.0, lh * lines.size() + 5)
	var cx := clampf(top_center.x, left + w / 2.0, right - w / 2.0)
	var r := Rect2(roundf(cx - w / 2.0), top_center.y, roundf(w), roundf(h))
	_strip_rect = r
	if _slab_visible():
		return r  # the slab is still on screen; it folds into this spot
	var s := _juice.pop("strip", 0.15)
	ci.draw_set_transform(r.get_center(), 0.0, Vector2(s, s))
	var lr := Rect2(-r.size / 2.0, r.size)
	UiKit.panel(ci, lr, UiKit.PANEL_DARK, _color)
	var on := fmod(_juice.clock(), 0.6) < 0.42
	var col := _color if on else Color(_color, 0.55)
	# Icon badge sticking out of the strip's left end (fits the 16 px alert icons).
	var badge := Rect2(lr.position.x - 4, -9, 18, 18)
	UiKit.panel(ci, badge, UiKit.INK.lightened(0.08), _color)
	var tex := UiKit.icon_tex(_icon)
	var isz := tex.get_size() if tex else Vector2(8, 8)
	UiKit.icon(ci, _icon, badge.get_center() - (isz / 2.0).round(), 1, _color)
	for i in lines.size():
		UiKit.text(ci, Vector2(lr.position.x + 19, lr.position.y + 2 + lh * (i + 1) - 2), lines[i], size, col)
	ci.draw_set_transform(Vector2.ZERO)
	return r


func _slab_visible() -> bool:
	return not _slab.is_empty() and _slab.t < SLIDE + HOLD


## The slab, drawn over everything else in the HUD.
func draw_slab(ci: CanvasItem) -> void:
	if _slab.is_empty():
		return
	var t: float = _slab.t
	var color: Color = _slab.color
	var r := SLAB
	var alpha := 1.0
	if t < SLIDE:
		var k := t / SLIDE
		r.position.x = -roundf(480.0 * (1.0 - k) * (1.0 - k))  # ease out
	elif t > SLIDE + HOLD:
		# Fold up into the strip.
		var k := clampf((t - SLIDE - HOLD) / FOLD, 0.0, 1.0)
		var target := _strip_rect if _strip_rect.has_area() else Rect2(140, 30, 200, 13)
		r = Rect2(r.position.lerp(target.position, k), r.size.lerp(target.size, k))
		r = Rect2(r.position.round(), r.size.round())
		alpha = 1.0 - k * 0.6
	# Dithered edges + ink lines + body.
	UiKit.dither(ci, Rect2(r.position.x, r.position.y - 4, r.size.x, 4), Color(color, 0.8 * alpha))
	UiKit.dither(ci, Rect2(r.position.x, r.end.y, r.size.x, 4), Color(color, 0.8 * alpha))
	ci.draw_rect(Rect2(r.position.x, r.position.y - 1, r.size.x, r.size.y + 2), Color(UiKit.INK, alpha))
	ci.draw_rect(r, Color(color, alpha))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(color.lightened(0.35), alpha))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(color.darkened(0.3), alpha))
	if t > SLIDE + HOLD:
		return  # folding: no contents
	# Icon badge + words, centred.
	var words: String = _slab.words
	var size := 16
	var ww := UiKit.text_w(words, size)
	var total := 34 + 8 + ww
	var x := r.position.x + roundf(240 - total / 2.0)
	var badge := Rect2(x, r.position.y + 3, 34, 34)
	var hop := 0.0
	if t > SLIDE:
		hop = -roundf(2.0 * absf(sin((t - SLIDE) * 9.0)) * (1.0 - (t - SLIDE) / HOLD))
	badge.position.y += hop
	UiKit.panel(ci, badge, UiKit.INK.lightened(0.08), color)
	UiKit.icon(ci, _slab.icon, badge.position + Vector2(1, 1), 2, color)
	UiKit.text(ci, Vector2(x + 42, r.position.y + 20 + roundf(UiKit.ascent(size) / 2.0)), words, size,
			UiKit.ink_on(color), 0)


func _ticket_left(state: Dictionary, kind: String) -> float:
	for e: Dictionary in state.get("events", []):
		if e.get("kind", "") == kind:
			return float(e.time_left)
	return 0.0
