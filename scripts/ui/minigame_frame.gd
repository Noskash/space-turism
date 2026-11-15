class_name MinigameFrame
extends RefCounted
## One look for every station minigame (they are CanvasLayers on layer 15):
##   dim backdrop, a big frame with a thick outline in the station's colour, a title bar
##   (16 px icon + title), a "Q CLOSE" key cap (closable games), the deadline bar, a footer
##   hint + note, and a rubber stamp ("DONE", "FAILED") when the game ends.
## Usage: frame.draw(canvas, ...) at the top of the game's _draw, content in content_rect(),
## frame.stamp("DONE", colour) when it ends, frame.step(delta) every frame, frame.draw_stamp()
## last. Full-screen games (DodgeGame) use draw_bar() / draw_footer() / draw_stamp() only.

const RECT := Rect2(70, 28, 340, 214)
const TITLE_H := 20.0

var title := ""
var icon := ""
var color := Color.WHITE
## Shows the Q key cap; the game itself handles the key (Controls "close").
var closable := true

var _stamp := ""
var _stamp_color := Color.WHITE
var _stamp_t := -1.0
var _t := 0.0


func _init(p_title: String, p_icon: String, p_color: Color, p_closable := true) -> void:
	title = p_title
	icon = p_icon
	color = p_color
	closable = p_closable


func step(delta: float) -> void:
	_t += delta
	if _stamp_t >= 0.0:
		_stamp_t += delta


## Slams a stamp over the frame (once).
func stamp(text: String, col: Color) -> void:
	if _stamp_t < 0.0:
		_stamp = text
		_stamp_color = col
		_stamp_t = 0.0
		Sfx.play("dock", 0.7)


## Area for the game's own content (below the title and deadline bars).
func content_rect(offset := Vector2.ZERO) -> Rect2:
	return Rect2(RECT.position + offset + Vector2(6, TITLE_H + 24), RECT.size - Vector2(12, TITLE_H + 24 + 34))


## Backdrop + frame + title bar + deadline. `deadline_text` like "RADIATION WAVE IN %.1fs"
## (formatted with `left`). `offset` shakes the whole frame.
func draw(ci: CanvasItem, left: float, total: float, deadline_text: String, offset := Vector2.ZERO) -> void:
	ci.draw_rect(Rect2(-8, -8, 496, 286), Color(0.01, 0.015, 0.04, 0.84))
	var r := Rect2(RECT.position + offset.round(), RECT.size)
	UiKit.frame(ci, r, color)
	# Title bar.
	var bar := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, TITLE_H))
	ci.draw_rect(bar, UiKit.PANEL)
	ci.draw_rect(Rect2(bar.position.x, bar.end.y, bar.size.x, 1), UiKit.INK)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1)), color.darkened(0.2))
	UiKit.icon(ci, icon, bar.position + Vector2(3, 2), 1, color)
	UiKit.text(ci, Vector2(bar.position.x + 23, bar.end.y - 5), title, 12, color, 2)
	if closable:
		var cap := UiKit.keycap_size("Q", 7)
		var label_w := UiKit.text_w("CLOSE", 6)
		var x := bar.end.x - 4 - label_w - 3 - cap.x
		UiKit.keycap(ci, Vector2(x, bar.position.y + roundf((TITLE_H - cap.y) / 2.0)), "Q", 7)
		UiKit.text(ci, Vector2(x + cap.x + 3, bar.end.y - 6), "CLOSE", 6, UiKit.DIM, 0)
	# Deadline: text + 20-segment bar that blinks red near the end.
	if total > 0.0:
		var y := bar.end.y + 4
		var urgent := left < 4.0
		var on := fmod(_t, 0.5) < 0.35 or not urgent
		var text := deadline_text % maxf(left, 0.0)
		var col := (UiKit.WARN if not urgent else UiKit.BAD) if on else Color(UiKit.BAD, 0.5)
		UiKit.text_c(ci, r.get_center().x, y + 9, text, 8, col)
		var sw := UiKit.seg_bar_width(20, 7)
		UiKit.seg_bar(ci, Rect2(roundf(r.get_center().x - sw / 2.0), y + 12, sw, 6),
				clampf(left / total, 0.0, 1.0), col if urgent else UiKit.WARN, 20)


## Footer: big hint line + small note, centred near the frame's bottom.
func draw_footer(ci: CanvasItem, hint: String, hint_col: Color, note: String, offset := Vector2.ZERO) -> void:
	var r := Rect2(RECT.position + offset.round(), RECT.size)
	UiKit.text_c(ci, r.get_center().x, r.end.y - 20, hint, 9, hint_col)
	UiKit.text_c(ci, r.get_center().x, r.end.y - 8, note, 6, UiKit.DIM, 0)


## Thin top bar for full-screen games: icon + title left, `right_text` right, a time bar.
func draw_bar(ci: CanvasItem, left: float, total: float, right_text: String, right_col: Color) -> void:
	var r := Rect2(2, 2, 476, TITLE_H)
	UiKit.panel(ci, r, UiKit.PANEL, color)
	UiKit.icon(ci, icon, r.position + Vector2(3, 2), 1, color)
	UiKit.text(ci, Vector2(r.position.x + 23, r.end.y - 5), title, 10, color)
	UiKit.text_r(ci, r.end.x - 6, r.end.y - 6, right_text, 9, right_col)
	if total > 0.0:
		var sw := UiKit.seg_bar_width(20, 6)
		UiKit.seg_bar(ci, Rect2(roundf(240 - sw / 2.0), r.position.y + 7, sw, 7), clampf(left / total, 0.0, 1.0),
				color if left > 2.0 else UiKit.BAD, 20)


func draw_stamp(ci: CanvasItem, center := Vector2(240, 135)) -> void:
	if _stamp_t < 0.0:
		return
	UiKit.stamp(ci, center, _stamp, _stamp_color, clampf(1.0 - _stamp_t / 0.18, 0.0, 1.0), 20)
