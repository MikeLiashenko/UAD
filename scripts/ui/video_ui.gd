extends Control
## The overlay of the morning compilation: the replay of scripts/game/reel.gd framed as what it
## pretends to be — a vertical phone video. A status bar, the channel, the handle of whoever
## filmed this one, the caption typing itself out, likes ticking up, comments floating past, and
## the grain and vignette of a phone camera at two in the morning.
##
## Everything is drawn: there are no textures in this project. The reel tells the overlay which
## shot is on screen, so a dashcam clip gets its timestamp bar and an onboard camera gets its
## telemetry.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal closed
## The viewer asked for this cut to be written to a file.
signal record_requested

## What the badge in the corner calls each shot.
const STYLE_NAME := {
	"balcony": "С БАЛКОНА",
	"street": "С УЛИЦЫ",
	"pass": "ПРЯМО НАД НАМИ",
	"dash": "ВИДЕОРЕГИСТРАТОР",
	"window": "ИЗ ОКНА",
	"onboard": "КАМЕРА ПЕРЕХВАТЧИКА",
}
## What the city writes under the clips.
const COMMENTS := [
	"аж стёкла зазвенели", "красиво сработали", "это над нашим домом", "слава ПВО",
	"опять всю ночь не спим", "слышала два хлопка", "спасибо ребятам", "снимал с балкона",
	"жёстко по звуку", "дочка проснулась, но всё ок", "спокойной ночи всем", "работают наши",
]

var game
var reel
## Set while the cut is being written to a file (scripts/game/video_export.gd).
var recorder
var _save_btn: Button
## Likes shown for the clip on screen, counting up while it plays.
var _likes := 0.0
var _t := 0.0
## Heart pulse after a like: 1 right after, fading to 0.
var _pulse := 0.0
## Comment bubbles drifting up the frame, and the hearts a tap throws out.
var _bubbles: Array = []
var _hearts: Array = []
var _next_bubble := 0.9
var _rng := RandomNumberGenerator.new()
## Separate stream for the sensor noise: it is reseeded every frame and must not disturb the
## random order comments and hearts come out in.
var _noise := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 1337
	var close_btn := Button.new()
	close_btn.text = GS.t("✕ ЗАКРЫТЬ [%s]") % GS.key_label("pause")
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -190
	close_btn.offset_right = -16
	close_btn.offset_top = 16
	close_btn.offset_bottom = 50
	close_btn.pressed.connect(func() -> void: closed.emit())
	add_child(close_btn)
	var skip_btn := Button.new()
	skip_btn.text = GS.t("СЛЕДУЮЩИЙ ▶ [%s]") % GS.key_label("fpv_next")
	skip_btn.add_theme_font_size_override("font_size", 15)
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.anchor_left = 1.0
	skip_btn.anchor_right = 1.0
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -230
	skip_btn.offset_right = -16
	skip_btn.offset_top = -54
	skip_btn.offset_bottom = -16
	skip_btn.pressed.connect(func() -> void: reel.skip())
	add_child(skip_btn)
	_save_btn = Button.new()
	_save_btn.text = GS.t("⤓ СОХРАНИТЬ ВИДЕО")
	_save_btn.add_theme_font_size_override("font_size", 15)
	_save_btn.focus_mode = Control.FOCUS_NONE
	_save_btn.anchor_top = 1.0
	_save_btn.anchor_bottom = 1.0
	_save_btn.offset_left = 16
	_save_btn.offset_right = 250
	_save_btn.offset_top = -54
	_save_btn.offset_bottom = -16
	_save_btn.pressed.connect(func() -> void: record_requested.emit())
	add_child(_save_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# a tap on the frame is a like, same as anywhere else
		_like_at((event as InputEventMouseButton).position)
		return
	if not (event is InputEventKey) or not event.pressed or (event as InputEventKey).echo:
		return
	var kc: int = (event as InputEventKey).keycode
	if kc == KEY_ESCAPE or kc == KEY_ENTER or GS.action_of(kc) in ["pause", "feed", "view"]:
		get_viewport().set_input_as_handled()
		closed.emit()
	elif kc == KEY_SPACE or kc == KEY_RIGHT or GS.action_of(kc) == "fpv_next":
		get_viewport().set_input_as_handled()
		reel.skip()


func _like_at(pos: Vector2) -> void:
	_likes += 1.0
	_pulse = 1.0
	for i in 5:
		_hearts.append({
			"p": pos + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-10, 10)),
			"v": Vector2(_rng.randf_range(-42, 42), _rng.randf_range(-190, -120)),
			"t": 0.0,
			"s": _rng.randf_range(0.7, 1.25),
		})


func on_clip(_i: int) -> void:
	_likes = 0.0
	_bubbles.clear()
	_next_bubble = 0.6


func _process(delta: float) -> void:
	_t += delta
	if _save_btn != null:
		_save_btn.visible = recorder == null or not is_instance_valid(recorder) or not recorder.recording
	_pulse = maxf(_pulse - delta * 2.2, 0.0)
	if reel != null and reel.playing and reel.phase == "clip":
		var c: Dictionary = reel.current()
		var target := float(c.get("likes", 0))
		var before := _likes
		_likes = move_toward(_likes, target, target * delta * 0.7 + 40.0 * delta)
		if int(before / 250.0) != int(_likes / 250.0):
			_pulse = 1.0
		_next_bubble -= delta
		if _next_bubble <= 0.0:
			_next_bubble = _rng.randf_range(0.7, 1.4)
			_bubbles.append({
				"who": String(GS.video_authors()[_rng.randi() % GS.video_authors().size()]),
				"text": GS.t(String(COMMENTS[_rng.randi() % COMMENTS.size()])),
				"t": 0.0,
			})
	var i := 0
	while i < _bubbles.size():
		_bubbles[i]["t"] = float(_bubbles[i]["t"]) + delta
		if float(_bubbles[i]["t"]) > 3.4:
			_bubbles.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _hearts.size():
		var h: Dictionary = _hearts[i]
		h["t"] = float(h["t"]) + delta
		h["p"] = (h["p"] as Vector2) + (h["v"] as Vector2) * delta
		h["v"] = (h["v"] as Vector2) + Vector2(0, 150.0 * delta)
		if float(h["t"]) > 1.3:
			_hearts.remove_at(i)
		else:
			i += 1
	queue_redraw()


# --- Little drawing helpers ------------------------------------------------------------------
func _fmt_count(n: float) -> String:
	if n >= 1000000.0:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000.0:
		return "%.1fk" % (n / 1000.0)
	return "%d" % int(n)


func _txt(pos: Vector2, s: String, size_px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, pos, s, align, width, size_px, 5, Color(0, 0, 0, 0.75))
	draw_string(GS.font, pos, s, align, width, size_px, col)


func _pill(r: Rect2, col: Color, radius := 8) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)


func _heart(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-s * 0.42, -s * 0.2), s * 0.5, col)
	draw_circle(c + Vector2(s * 0.42, -s * 0.2), s * 0.5, col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 0.9, 0.0), c + Vector2(s * 0.9, 0.0), c + Vector2(0.0, s * 1.05)]), col)


# --- Frame -----------------------------------------------------------------------------------
## The vertical phone frame inside the window — also what the recorder crops to.
func frame_rect() -> Rect2:
	var sz := size
	var vw: float = minf(sz.y * 0.5625, sz.x)
	return Rect2((sz.x - vw) * 0.5, 0.0, vw, sz.y)


func _draw() -> void:
	if reel == null:
		return
	var sz := size
	var f := frame_rect()
	# the sides of the screen are curtained off: what is left is the phone
	draw_rect(Rect2(0, 0, f.position.x, sz.y), Color(0, 0.012, 0.01, 0.95))
	draw_rect(Rect2(f.end.x, 0, sz.x - f.end.x, sz.y), Color(0, 0.012, 0.01, 0.95))
	_grain(f)
	_vignette(f)
	match String(reel.phase):
		"intro":
			_draw_intro(f)
		"outro":
			_draw_outro(f)
		_:
			_draw_clip(f)
	_draw_hearts()
	_bezel(f)
	if reel.flash > 0.01:
		draw_rect(f, Color(1, 1, 1, reel.flash * 0.75))
	_rec_badge(f)


## Written outside the phone frame on purpose: what the recorder saves must not show it.
func _rec_badge(f: Rect2) -> void:
	if recorder == null or not is_instance_valid(recorder) or not recorder.recording:
		return
	var x: float = f.position.x * 0.5 - 70.0
	var y: float = size.y * 0.5
	if int(_t * 2.0) % 2 == 0:
		draw_circle(Vector2(x + 8, y - 6), 7.0, Color(1.0, 0.25, 0.2))
	_txt(Vector2(x + 24, y), GS.t("ЗАПИСЬ %d%%") % int(recorder.progress * 100.0), 17, Color(1.0, 0.45, 0.4))
	_txt(Vector2(x, y + 26), GS.t("не закрывайте окно"), 13, Color(0.7, 0.9, 0.85))
	draw_rect(Rect2(x, y + 40, 140, 5), Color(1, 1, 1, 0.2))
	draw_rect(Rect2(x, y + 40, 140.0 * recorder.progress, 5), Color(1.0, 0.45, 0.4))


## Sensor noise: a phone camera at night is never clean.
func _grain(f: Rect2) -> void:
	_noise.seed = int(_t * 30.0)
	for i in 150:
		var at := Vector2(f.position.x + _noise.randf() * f.size.x, _noise.randf() * f.size.y)
		draw_rect(Rect2(at, Vector2(2, 2)), Color(1, 1, 1, _noise.randf_range(0.015, 0.05)))
	# a couple of scan bands rolling down the frame
	var y: float = fmod(_t * 90.0, f.size.y + 200.0) - 100.0
	draw_rect(Rect2(f.position.x, y, f.size.x, 60.0), Color(0.6, 1.0, 0.85, 0.018))


func _vignette(f: Rect2) -> void:
	for i in 18:
		var k := float(i) / 18.0
		var a: float = 0.07 * (1.0 - k)
		var h: float = 9.0
		draw_rect(Rect2(f.position.x, float(i) * h, f.size.x, h), Color(0, 0, 0, a))
		draw_rect(Rect2(f.position.x, f.size.y - float(i + 1) * h, f.size.x, h), Color(0, 0, 0, a))
		draw_rect(Rect2(f.position.x + float(i) * 6.0, 0, 6.0, f.size.y), Color(0, 0, 0, a * 0.8))
		draw_rect(Rect2(f.end.x - float(i + 1) * 6.0, 0, 6.0, f.size.y), Color(0, 0, 0, a * 0.8))


## The rounded body of the phone over the picture.
func _bezel(f: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(12)
	sb.border_color = Color(0, 0.02, 0.02, 1.0)
	sb.set_corner_radius_all(38)
	draw_style_box(sb, f.grow(6.0))
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.bg_color = Color(0, 0, 0, 0)
	line.set_border_width_all(2)
	line.border_color = Color(0.35, 1.0, 0.65, 0.35)
	line.set_corner_radius_all(32)
	draw_style_box(line, f.grow(-4.0))


## Signal, wifi, battery and the time the clip was filmed — the strip across the top.
func _status_bar(f: Rect2, clock: String) -> void:
	_txt(Vector2(f.position.x + 26, 30), clock, 16, Color(1, 1, 1, 0.92))
	var x: float = f.end.x - 96.0
	for i in 4:
		var h: float = 4.0 + float(i) * 3.0
		draw_rect(Rect2(x + float(i) * 6.0, 26.0 - h, 4.0, h), Color(1, 1, 1, 0.85 if i < 3 else 0.35))
	x = f.end.x - 62.0
	for i in 3:
		var rr: float = 4.0 + float(i) * 5.0
		draw_arc(Vector2(x, 28), rr, PI * 1.25, PI * 1.75, 10, Color(1, 1, 1, 0.8), 2.0)
	var bat := Rect2(f.end.x - 46.0, 16.0, 26.0, 13.0)
	draw_rect(bat, Color(1, 1, 1, 0.6), false, 1.5)
	draw_rect(Rect2(bat.position + Vector2(2, 2), Vector2(9, 9)), Color(1.0, 0.55, 0.3))
	draw_rect(Rect2(bat.end.x, 19.0, 2.5, 7.0), Color(1, 1, 1, 0.6))


## One segment per clip, the current one filling up.
func _progress(f: Rect2) -> void:
	var n: int = reel.clips.size()
	if n <= 0:
		return
	var seg: float = (f.size.x - 48.0 - 4.0 * float(n - 1)) / float(n)
	for i in n:
		var r := Rect2(f.position.x + 24.0 + float(i) * (seg + 4.0), 44.0, seg, 3.0)
		_pill(r, Color(1, 1, 1, 0.22), 2)
		var k := 0.0
		if String(reel.phase) == "outro" or i < reel.index:
			k = 1.0
		elif String(reel.phase) == "clip" and i == reel.index:
			k = reel.clip_k()
		if k > 0.0:
			_pill(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), Color(1, 1, 1, 0.95), 2)


## Avatar, handle and the subscribe pill of the channel that cut the compilation.
func _channel(f: Rect2, day: int) -> void:
	var neon := Color(0.35, 1.0, 0.65)
	var c := Vector2(f.position.x + 40, 78)
	draw_circle(c, 17.0, Color(0.05, 0.16, 0.13))
	draw_arc(c, 17.0, 0.0, TAU, 28, neon, 2.0)
	_txt(c + Vector2(-9, 7), "К", 19, neon)
	_txt(Vector2(f.position.x + 66, 74), GS.video_channel(), 17, Color(1, 1, 1))
	_txt(Vector2(f.position.x + 66, 94), GS.t("НАРЕЗКА НОЧИ %d") % day, 14, Color(0.72, 0.95, 0.88))
	var pill := Rect2(f.end.x - 132, 62, 106, 30)
	_pill(pill, Color(1.0, 0.25, 0.3, 0.92), 8)
	_txt(Vector2(pill.position.x, 83), GS.t("ПОДПИСКА"), 14, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, pill.size.x)
	if int(_t * 2.0) % 2 == 0:
		draw_circle(Vector2(f.position.x + 30, 118), 5.0, Color(1.0, 0.25, 0.2))
		_txt(Vector2(f.position.x + 40, 124), GS.t("ЭФИР"), 14, Color(1.0, 0.35, 0.3))


## Likes, comments, shares and views down the right edge.
func _rail(f: Rect2, c: Dictionary) -> void:
	var x: float = f.end.x - 52.0
	var y: float = f.size.y - 300.0
	var s: float = 15.0 + _pulse * 4.0
	_heart(Vector2(x, y), s, Color(1.0, 0.24, 0.34).lerp(Color(1, 1, 1), _pulse * 0.4))
	_txt(Vector2(x - 34, y + 34), _fmt_count(_likes), 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 68)
	var cy: float = y + 74.0
	_pill(Rect2(x - 15, cy - 12, 30, 22), Color(1, 1, 1, 0.9), 7)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 8, cy + 9), Vector2(x + 2, cy + 9), Vector2(x - 6, cy + 17)]), Color(1, 1, 1, 0.9))
	_txt(Vector2(x - 34, cy + 40), _fmt_count(float(c.get("comments", 0))), 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 68)
	var sy: float = y + 150.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 14, sy - 10), Vector2(x + 16, sy + 2), Vector2(x - 14, sy + 14),
		Vector2(x - 14, sy + 5), Vector2(x - 3, sy + 2), Vector2(x - 14, sy - 1)]), Color(1, 1, 1, 0.9))
	_txt(Vector2(x - 34, sy + 38), GS.t("ПОДЕЛИТЬСЯ"), 12, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 68)
	var vy: float = y + 226.0
	draw_arc(Vector2(x, vy), 12.0, 0.0, TAU, 20, Color(1, 1, 1, 0.85), 2.0)
	draw_circle(Vector2(x, vy), 5.0, Color(1, 1, 1, 0.85))
	_txt(Vector2(x - 34, vy + 34), _fmt_count(float(reel.video.get("views", 0))), 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 68)


## Comments floating up the left side while the clip runs.
func _comments(f: Rect2) -> void:
	for b in _bubbles:
		var k: float = float(b["t"]) / 3.4
		var a: float = clampf(minf(k * 6.0, (1.0 - k) * 3.0), 0.0, 1.0)
		var y: float = f.size.y - 190.0 - k * 104.0
		_txt(Vector2(f.position.x + 22, y), String(b["who"]), 13, Color(0.55, 0.95, 0.8, a))
		_txt(Vector2(f.position.x + 22, y + 17), String(b["text"]), 15, Color(1, 1, 1, a * 0.92))


func _draw_hearts() -> void:
	for h in _hearts:
		var k: float = float(h["t"]) / 1.3
		_heart(h["p"] as Vector2, 13.0 * float(h["s"]), Color(1.0, 0.3, 0.4, clampf(1.6 - k * 1.8, 0.0, 1.0)))


## Extras that belong to one kind of shot: a dashcam stamp, a window sill, gun telemetry.
func _style_overlay(f: Rect2, st: String) -> void:
	match st:
		"dash":
			draw_rect(Rect2(f.position.x, f.size.y - 210.0, f.size.x, 26.0), Color(0, 0, 0, 0.55))
			_txt(Vector2(f.position.x + 20, f.size.y - 191.0), GS.ctext("rec"), 14, Color(1, 1, 1, 0.75))
		"window":
			# the frame of the window the phone is leaning against
			draw_rect(Rect2(f.position.x, 0, 30.0, f.size.y), Color(0, 0.01, 0.01, 0.82))
			draw_rect(Rect2(f.end.x - 30.0, 0, 30.0, f.size.y), Color(0, 0.01, 0.01, 0.82))
			draw_rect(Rect2(f.position.x, f.size.y - 150.0, f.size.x, 18.0), Color(0, 0.01, 0.01, 0.7))
		"onboard":
			var c := Vector2(f.get_center().x, f.size.y * 0.47)
			var col := Color(0.4, 1.0, 0.6, 0.55)
			for i in 4:
				var a: float = float(i) * PI * 0.5 + PI * 0.25
				draw_line(c + Vector2(cos(a), sin(a)) * 26.0, c + Vector2(cos(a), sin(a)) * 46.0, col, 1.5)
			draw_arc(c, 26.0, 0.0, TAU, 32, col, 1.5)
			_txt(c + Vector2(34, -30), GS.t("ЗАХВАТ"), 13, Color(0.45, 1.0, 0.65, 0.8))
			_txt(Vector2(f.position.x + 26, f.size.y * 0.47), "ALT %d" % int(maxf(reel.cam.global_position.y, 0.0)), 13, col)


func _draw_clip(f: Rect2) -> void:
	var c: Dictionary = reel.current()
	var day: int = int(reel.video.get("day", 0))
	var n: int = reel.clips.size()
	var neon := Color(0.35, 1.0, 0.65)
	var secs: int = int(c.get("t", 0))
	_status_bar(f, "0%d:%02d" % [2 + secs / 60, secs % 60])
	_progress(f)
	_channel(f, day)
	_style_overlay(f, String(reel.style()))
	_rail(f, c)
	_comments(f)
	# --- who filmed it and what happened
	var y: float = f.size.y - 148.0
	var author := String(c.get("author", "@kyiv"))
	_txt(Vector2(f.position.x + 22, y), author, 21, Color(1, 1, 1))
	var w: float = GS.font.get_string_size(author, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	draw_circle(Vector2(f.position.x + 32 + w, y - 7), 8.0, Color(0.25, 0.65, 1.0))
	_txt(Vector2(f.position.x + 27 + w, y - 2), "✓", 12, Color(1, 1, 1))
	# the caption types itself out, the way a fresh post reads
	var cap := String(c.get("caption", ""))
	var shown: int = int(clampf(reel.t * 26.0, 0.0, float(cap.length())))
	_txt(Vector2(f.position.x + 22, y + 26), cap.substr(0, shown), 16, Color(0.88, 1.0, 0.94))
	_txt(Vector2(f.position.x + 22, y + 50), GS.t("%s · клип %d из %d") % [GS.t(String(c.get("district", ""))), reel.index + 1, n], 14, Color(0.7, 0.9, 0.85))
	# --- the soundtrack line every one of these videos has
	_txt(Vector2(f.position.x + 22, y + 74), GS.t("♪ оригинальный звук · %s") % author, 13, Color(0.75, 0.95, 0.9, 0.8 + 0.2 * sin(_t * 3.0)))
	# --- what brought it down, and how it was filmed
	var by := String(c.get("by", ""))
	if by != "" and GS.WEAPONS.has(by):
		_txt(Vector2(f.end.x - 22, f.size.y - 128.0), GS.t(String(GS.WEAPONS[by].short)), 18, neon, HORIZONTAL_ALIGNMENT_RIGHT)
	if bool(c.get("manual", false)):
		_txt(Vector2(f.end.x - 22, f.size.y - 106.0), GS.t("РУЧНОЙ ПЕРЕХВАТ"), 13, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	var badge := GS.t(String(STYLE_NAME.get(String(reel.style()), "С БАЛКОНА")))
	_txt(Vector2(f.position.x + 22, 152), badge, 13, Color(0.6, 0.9, 0.85, 0.85))
	if reel.slow > 0.05:
		var a: float = clampf(reel.slow * 1.4, 0.0, 1.0)
		_txt(Vector2(f.get_center().x, 152), GS.t("ЗАМЕДЛЕНИЕ ×3"), 15, Color(1.0, 0.85, 0.35, a), HORIZONTAL_ALIGNMENT_CENTER)


## The title card the compilation opens with.
func _draw_intro(f: Rect2) -> void:
	var k: float = reel.clip_k()
	var a: float = clampf(minf(k * 5.0, (1.0 - k) * 4.0), 0.0, 1.0)
	var day: int = int(reel.video.get("day", 0))
	var neon := Color(0.35, 1.0, 0.65, a)
	draw_rect(f, Color(0, 0.01, 0.01, 0.45 * a))
	var cx: float = f.get_center().x
	var cy: float = f.size.y * 0.42
	draw_circle(Vector2(cx, cy - 86), 30.0, Color(0.05, 0.16, 0.13, a))
	draw_arc(Vector2(cx, cy - 86), 30.0, 0.0, TAU, 36, neon, 2.5)
	_txt(Vector2(cx - 15, cy - 76), "К", 30, neon)
	_txt(Vector2(cx, cy - 20), GS.video_channel(), 20, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(cx, cy + 26), GS.t("НАРЕЗКА НОЧИ"), 40, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(cx, cy + 66), GS.t("ДЕНЬ %d") % day, 26, neon, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(cx, cy + 112), GS.t("%d роликов · 0:%02d") % [reel.clips.size(), int(reel.nominal_len())], 16, Color(0.75, 0.95, 0.9, a), HORIZONTAL_ALIGNMENT_CENTER)
	_status_bar(f, "02:00")


## The sign-off: what the night added up to.
func _draw_outro(f: Rect2) -> void:
	var k: float = reel.clip_k()
	var a: float = clampf(minf(k * 5.0, (1.0 - k) * 4.0), 0.0, 1.0)
	var neon := Color(0.35, 1.0, 0.65, a)
	draw_rect(f, Color(0, 0.01, 0.01, 0.5 * a))
	var cx: float = f.get_center().x
	var cy: float = f.size.y * 0.34
	_txt(Vector2(cx, cy), GS.t("ВСЕМ СПОКОЙНОЙ НОЧИ"), 26, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
	var rows := [
		[GS.t("роликов"), "%d" % reel.clips.size()],
		[GS.t("лайков"), _fmt_count(float(reel.video.get("likes", 0)))],
		[GS.t("просмотров"), _fmt_count(float(reel.video.get("views", 0)))],
	]
	var y: float = cy + 52.0
	for r in rows:
		_txt(Vector2(f.position.x + 54, y), String(r[0]), 17, Color(0.75, 0.95, 0.9, a))
		_txt(Vector2(f.end.x - 54, y), String(r[1]), 21, neon, HORIZONTAL_ALIGNMENT_RIGHT)
		draw_rect(Rect2(f.position.x + 54, y + 10, f.size.x - 108, 1), Color(0.35, 1.0, 0.65, 0.18 * a))
		y += 46.0
	_txt(Vector2(cx, y + 34), GS.t("ЗАВТРА В ЭТО ЖЕ ВРЕМЯ"), 16, Color(0.8, 0.95, 0.9, a), HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(cx, f.size.y - 120.0), GS.video_channel(), 18, neon, HORIZONTAL_ALIGNMENT_CENTER)
	_progress(f)
	_status_bar(f, "02:30")
