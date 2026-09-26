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
	visible = fv != null and fv.active and ((fv.drone != null and is_instance_valid(fv.drone)) or fv.lost_t > 0.0)
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


## The drone is gone: the receiver shows snow, "NO SIGNAL" and how it ended.
func _no_signal() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.03, 0.82))
	for i in 900:
		var g := _rng.randf_range(0.2, 0.9)
		draw_rect(Rect2(_rng.randf() * sz.x, _rng.randf() * sz.y, _rng.randf_range(2.0, 7.0), 2.0), Color(g, g, g, 0.55))
	_static(0.0)
	var c := sz * 0.5
	_txt(Vector2(c.x - 300, c.y + 10), GS.t("НЕТ СИГНАЛА"), 40, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 600)
	if _kill_t > 0.0:
		_txt(Vector2(c.x - 300, c.y - 60), _kill_text.split("\n")[0], 32, _kill_color, HORIZONTAL_ALIGNMENT_CENTER, 600)


func _draw() -> void:
	if fv == null or not fv.active:
		return
	var d = fv.drone
	if d == null or not is_instance_valid(d):
		if fv.lost_t > 0.0:
			_no_signal()
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
	# --- pitch of the flight path, next to the reticle (the horizon leaves the picture in a climb)
	var pitch := rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
	_txt(c + Vector2(44, 5), ("▲ %d°" if pitch >= 0.0 else "▼ %d°") % int(absf(pitch)), 13, Color(col.r, col.g, col.b, 0.8))
	# --- where the pilot steers: the drone turns until this ring sits in the reticle
	var aim_p: Vector3 = cam.global_position + fv.aim * 1000.0
	if not cam.is_position_behind(aim_p):
		var ap := cam.unproject_position(aim_p)
		draw_arc(ap, 13.0, 0, TAU, 24, Color(1, 1, 1, 0.85), 2.0)
		draw_circle(ap, 2.0, Color(1, 1, 1, 0.85))
	# --- the lock: lead diamond on the feed, or an arrow on the edge towards it
	var lk = d.target
	if lk != null and is_instance_valid(lk) and not lk.dead:
		var lead: Vector3 = fv.lead
		if lead != Vector3.INF and not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead)
			if Rect2(Vector2.ZERO, sz).has_point(lp):
				var dm := PackedVector2Array([lp + Vector2(0, -11), lp + Vector2(11, 0), lp + Vector2(0, 11), lp + Vector2(-11, 0), lp + Vector2(0, -11)])
				draw_polyline(dm, RED, 2.0)
		var tp := cam.unproject_position(lk.position)
		var inside := not cam.is_position_behind(lk.position) and Rect2(Vector2(40, 40), sz - Vector2(80, 80)).has_point(tp)
		if not inside:
			# direction to the threat in the picture's own plane
			var rel: Vector3 = cam.global_transform.basis.inverse() * (lk.position - cam.global_position)
			var dir2 := Vector2(rel.x, -rel.y)
			if dir2.length_squared() < 0.0001:
				dir2 = Vector2(0, 1)
			dir2 = dir2.normalized()
			# where the ray from the centre leaves a frame 70 px inside the screen
			var half := c - Vector2(70, 70)
			var edge := c + dir2 * minf(half.x / maxf(absf(dir2.x), 0.0001), half.y / maxf(absf(dir2.y), 0.0001))
			var tip := edge + dir2 * 22.0
			var side := Vector2(-dir2.y, dir2.x) * 12.0
			draw_colored_polygon(PackedVector2Array([tip, edge - dir2 * 6.0 + side, edge - dir2 * 6.0 - side]), RED)
			var ldist: float = cam.global_position.distance_to(lk.position)
			_txt(edge - dir2 * 34.0 + Vector2(-60, 5), GS.t("%s · %d м") % [GS.t(String(lk.def.abbr)), int(ldist * 5.0)], 13, RED, HORIZONTAL_ALIGNMENT_CENTER, 120)
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
			_txt(sp + Vector2(r + 6, 16), GS.t("сближение %d км/ч · %d%%") % [int(closing), int(100.0 * e.hp / e.max_hp)], 12, Color(ec.r, ec.g, ec.b, 0.85))
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
	var hint := GS.t("мышь — куда лететь (кольцо) · W/S — тяга · A/D, стрелки — поворот · Shift/ЛКМ — разгон · %s — следующий дрон · %s — на базу · %s — ночная камера · %s — пульт выкл · Alt — курсор") % [GS.key_label("fpv_next"), GS.key_label("fpv_home"), GS.key_label("night"), GS.key_label("fpv")]
	if DisplayServer.is_touchscreen_available():
		hint = GS.t("свайп — куда лететь (кольцо) · ромб — точка встречи с целью · «РАЗГОН» — ускорение · «СЛЕД.» — другой дрон · «НАЗАД» — выйти")
	_txt(Vector2(40, sz.y - 26), hint, 13, Color(col.r, col.g, col.b, 0.75), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)
	_static(q)
