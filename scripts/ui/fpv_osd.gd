extends Control
## Video overlay of the FPV console: the picture the drone's nose camera sends back.
## Artificial horizon, centre reticle, target box with range and closing speed, battery and
## link gauges, throttle, and the analogue break-up (scan lines, static, rolling bar) that
## gets worse as the drone flies away from the base. See scripts/game/fpv_view.gd.

const NEON := Color(0.35, 1.0, 0.65)
const AMBER := Color(1.0, 0.8, 0.3)
const RED := Color(1.0, 0.3, 0.25)

var game
## The FPV console (scripts/game/fpv_view.gd) this overlay belongs to.
var fv

var _t := 0.0
var _kill_t := 0.0
var _kill_text := ""
var _kill_color := NEON
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()


func kill(text: String, color := NEON) -> void:
	_kill_t = 1.8
	_kill_text = text
	_kill_color = color


func _process(delta: float) -> void:
	_t += delta
	_kill_t = maxf(0.0, _kill_t - delta)
	visible = fv != null and fv.active and fv.drone != null and is_instance_valid(fv.drone)
	if visible:
		queue_redraw()


func _txt(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, pos, s, align, width, size, 4, Color(0, 0, 0, 0.7))
	draw_string(GS.font, pos, s, align, width, size, col)


func _gauge(at: Vector2, w: float, h: float, value: float, col: Color, title: String) -> void:
	draw_rect(Rect2(at, Vector2(w, h)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(at, Vector2(w * clampf(value, 0.0, 1.0), h)), col)
	draw_rect(Rect2(at, Vector2(w, h)), Color(col.r, col.g, col.b, 0.8), false, 1.5)
	_txt(at + Vector2(0, -5), title, 12, Color(col.r, col.g, col.b, 0.9))


## Signal strength as four bars in the corner of the feed, like a real video receiver.
func _bars(at: Vector2, q: float) -> void:
	for i in 4:
		var lit: bool = q > float(i) * 0.25
		var h := 5.0 + i * 5.0
		var col := NEON if q > 0.35 else (AMBER if q > 0.15 else RED)
		var r := Rect2(at + Vector2(i * 8.0, 20.0 - h), Vector2(6.0, h))
		if lit:
			draw_rect(r, col)
		else:
			draw_rect(r, Color(col.r, col.g, col.b, 0.35), false, 1.0)


## Analogue break-up: scan lines everywhere, then torn rows and a rolling bar as the link
## degrades. Kept light enough that the picture stays flyable right up to the link limit.
func _static(q: float) -> void:
	var sz := size
	var noise := clampf(1.0 - q, 0.0, 1.0)
	for y in range(0, int(sz.y), 4):
		draw_rect(Rect2(0, y, sz.x, 1), Color(0, 0, 0, 0.07 + 0.05 * noise))
	if noise <= 0.05:
		return
	var rows := int(noise * noise * 22.0)
	for i in rows:
		var y := _rng.randf() * sz.y
		var w := _rng.randf_range(0.04, 0.3) * sz.x
		var x := _rng.randf() * (sz.x - w)
		draw_rect(Rect2(x, y, w, _rng.randf_range(1.0, 2.0 + 3.0 * noise)), Color(0.8, 1.0, 0.9, 0.04 + 0.1 * noise))
	var bar := fposmod(_t * (60.0 + 120.0 * noise), sz.y + 120.0) - 60.0
	draw_rect(Rect2(0, bar, sz.x, 14.0 * noise + 3.0), Color(0.7, 1.0, 0.85, 0.03 + 0.06 * noise))


func _draw() -> void:
	if fv == null or not fv.active:
		return
	var d = fv.drone
	if d == null or not is_instance_valid(d):
		return
	var cam: Camera3D = fv.cam
	var sz := size
	var c := sz * 0.5
	var q: float = fv.signal_q
	var col := NEON if q > 0.35 else AMBER
	# --- artificial horizon: two far points at eye height, so roll and pitch come for free
	var b := cam.global_transform.basis
	var f := -b.z
	var flat := Vector3(f.x, 0.0, f.z)
	if flat.length_squared() > 0.001:
		flat = flat.normalized()
		var right := Vector3(-flat.z, 0.0, flat.x)
		var p1: Vector3 = cam.global_position + flat * 4000.0 - right * 4000.0
		var p2: Vector3 = cam.global_position + flat * 4000.0 + right * 4000.0
		if not cam.is_position_behind(p1) and not cam.is_position_behind(p2):
			var s1 := cam.unproject_position(p1)
			var s2 := cam.unproject_position(p2)
			draw_line(s1, s2, Color(col.r, col.g, col.b, 0.35), 1.5)
	# --- centre reticle of a racing quad: a dot with wings
	draw_line(c + Vector2(-34, 0), c + Vector2(-12, 0), col, 2.0)
	draw_line(c + Vector2(12, 0), c + Vector2(34, 0), col, 2.0)
	draw_line(c + Vector2(0, -26), c + Vector2(0, -12), Color(col.r, col.g, col.b, 0.7), 1.5)
	draw_arc(c, 7.0, 0, TAU, 16, col, 1.5)
	draw_circle(c, 1.5, col)
	# --- threats in the feed
	var tracked = fv.feed_target()
	for e in game.enemies:
		if e.dead or cam.is_position_behind(e.position):
			continue
		var sp := cam.unproject_position(e.position)
		var dist: float = cam.global_position.distance_to(e.position)
		var locked: bool = e == d.target
		var ec: Color = RED if locked else Color(e.def.color.r, e.def.color.g, e.def.color.b, 0.8)
		var r := clampf(900.0 / maxf(dist, 20.0), 9.0, 90.0)
		var k := r * 0.4
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p := sp + Vector2(sx * r, sy * r)
				draw_line(p, p - Vector2(sx * k, 0), ec, 2.0)
				draw_line(p, p - Vector2(0, sy * k), ec, 2.0)
		if e == tracked or locked:
			var closing: float = (d.vel - e.vel).dot((e.position - d.position).normalized())
			_txt(sp + Vector2(r + 6, -2), GS.t("%s · %d м") % [GS.t(String(e.def.abbr)), int(dist * 5.0)], 13, ec)
			_txt(sp + Vector2(r + 6, 16), GS.t("сближение %d м/с · %d%%") % [int(closing * 5.0), int(100.0 * e.hp / e.max_hp)], 12, Color(ec.r, ec.g, ec.b, 0.85))
			if locked:
				_txt(sp + Vector2(-60, -r - 10), GS.t("ЦЕЛЬ"), 14, RED, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# --- telemetry, bottom left (clear of the status panel and the event log)
	var top := Vector2(26, sz.y - 190)
	_txt(top, GS.t("FPV · ДРОН #%d") % int(d.serial), 20, col)
	_txt(top + Vector2(0, 24), GS.t("РЕЖИМ: %s") % d.state_text(), 14, Color(col.r, col.g, col.b, 0.9))
	var batt: float = d.charge()
	var bcol := NEON if batt > 0.35 else (AMBER if batt > 0.18 else RED)
	if batt < 0.18 and int(_t * 4.0) % 2 == 0:
		bcol = Color(1, 1, 1)
	_gauge(top + Vector2(0, 44), 150, 10, batt, bcol, GS.t("АККУМУЛЯТОР %d%%") % int(batt * 100.0))
	_gauge(top + Vector2(0, 84), 150, 10, clampf(d.in_throttle / 1.35, 0.0, 1.0), Color(0.4, 0.85, 1.0), GS.t("ТЯГА %d%%") % int(d.in_throttle * 100.0))
	# ground speed on the console is the airframe number a pilot expects (max ~175 km/h)
	_txt(top + Vector2(0, 124), GS.t("V %d км/ч · H %d м") % [int(d.speed), int(d.position.y * 5.0)], 15, col)
	var to_base: float = d.position.distance_to(GS.base_pos)
	_txt(top + Vector2(0, 146), GS.t("до базы %.1f км · в воздухе %d") % [to_base * 0.005, game.drones.size()], 14, Color(col.r, col.g, col.b, 0.85))
	# --- link, bottom right
	var br := Vector2(sz.x - 210, sz.y - 150)
	_bars(br, q)
	_txt(br + Vector2(44, 18), GS.t("СИГНАЛ %d%%") % int(q * 100.0), 14, NEON if q > 0.35 else (AMBER if q > 0.15 else RED))
	if q < 0.3 and int(_t * 2.0) % 2 == 0:
		_txt(br + Vector2(0, 46), GS.t("СЛАБЫЙ СИГНАЛ — ВЕРНИТЕСЬ БЛИЖЕ"), 14, RED)
	if int(_t * 1.5) % 2 == 0:
		draw_circle(br + Vector2(-18, 14), 6.0, RED)
		_txt(br + Vector2(-8, 20), "REC", 14, RED)
	# --- kill banner and hints
	if _kill_t > 0.0:
		var a := clampf(_kill_t / 0.6, 0.0, 1.0)
		var kc := Color(_kill_color.r, _kill_color.g, _kill_color.b, a)
		var lines := _kill_text.split("\n")
		for i in lines.size():
			_txt(Vector2(c.x - 300, c.y - 90 + i * 34), lines[i], 32 if i == 0 else 22, kc, HORIZONTAL_ALIGNMENT_CENTER, 600)
	var hint := GS.t("мышь — управление · W/S — тяга · Shift/ЛКМ — разгон · %s — следующий дрон · %s — на базу · %s — ночная камера · %s — пульт выкл · Alt — курсор") % [GS.key_label("fpv_next"), GS.key_label("fpv_home"), GS.key_label("night"), GS.key_label("fpv")]
	if DisplayServer.is_touchscreen_available():
		hint = GS.t("свайп — управление · «РАЗГОН» — ускорение · «СЛЕД.» — другой дрон · «НАЗАД» — выйти с пульта")
	_txt(Vector2(c.x - 450, sz.y - 26), hint, 13, Color(col.r, col.g, col.b, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 900)
	_static(q)
