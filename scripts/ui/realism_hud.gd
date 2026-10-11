extends Control
## Everything a MaxRealism session puts on the screen (scripts/game/realism.gd): the radio
## traffic, a wrist compass on foot, the prompt of the seat in reach, and the consoles — the
## operator's scope of a radar-guided system and the board of the command post. No threat is
## ever marked in the 3D picture.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

const INK := Color(0.9, 0.93, 0.88)
const DIM := Color(0.62, 0.68, 0.62)
const PHOSPHOR := Color(0.45, 1.0, 0.55)
const AMBER := Color(1.0, 0.78, 0.35)
const CASE := Color(0.07, 0.085, 0.075, 1.0)

var game
var rl
var _use_btn: Button
var _lock_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if DisplayServer.is_touchscreen_available():
		_use_btn = _touch_btn(GS.t("МЕСТО"), -330, func() -> void: rl.use())
		_lock_btn = _touch_btn(GS.t("ЗАХВАТ"), -490, func() -> void: rl.lock())


## A round button over the fire button of the game HUD, for touch screens.
func _touch_btn(text: String, left: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", UiKit.sbox(Color(0.1, 0.12, 0.1, 0.75), DIM, 2, 60, 6))
	b.add_theme_stylebox_override("pressed", UiKit.sbox(Color(0.25, 0.3, 0.25, 0.9), INK, 2, 60, 6))
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = left
	b.offset_right = left + 120.0
	b.offset_top = -270
	b.offset_bottom = -150
	b.pressed.connect(cb)
	add_child(b)
	return b


func _process(_delta: float) -> void:
	if _use_btn != null:
		_use_btn.visible = game.view != "walk" or not rl.near.is_empty()
		_lock_btn.visible = rl.scope_on()
	queue_redraw()


func _txt(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, pos, s, align, width, size, 4, Color(0, 0, 0, 0.75 * col.a))
	draw_string(GS.font, pos, s, align, width, size, col)


## A paragraph wrapped to `width`; returns its height.
func _para(pos: Vector2, s: String, size: int, col: Color, width: float) -> float:
	draw_multiline_string_outline(GS.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, 4, Color(0, 0, 0, 0.75 * col.a))
	draw_multiline_string(GS.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, col)
	return GS.font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size).y


func _draw() -> void:
	var sz := size
	if game.view == "post":
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.035, 0.045, 0.04, 0.97))
	# the instructor's card first: the radio traffic goes under it
	_draw_radio(sz, _draw_training(sz) if rl.training != null else 0.0)
	match String(game.view):
		"post":
			_draw_post(sz)
		"base":
			if rl.scope_on():
				_draw_console(sz)
			else:
				_draw_seat_hint(sz)
		"walk":
			_draw_compass(sz, fposmod(-rad_to_deg(float(game.walker.yaw)), 360.0))
			_draw_prompt(sz)
	if rl.note_t > 0.0:
		_txt(Vector2(sz.x * 0.5 - 500, sz.y * 0.5 + 120), rl.note, 17, Color(AMBER.r, AMBER.g, AMBER.b, clampf(rl.note_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, 1000)


# --- On foot ----------------------------------------------------------------------------------
## A plain compass tape: the radio gives bearings, so the player has to know where north is.
func _draw_compass(sz: Vector2, hdg: float) -> void:
	var c := Vector2(sz.x * 0.5, 34.0)
	var span := 40.0
	var px := 7.0
	var col := Color(INK.r, INK.g, INK.b, 0.9)
	draw_rect(Rect2(Vector2(c.x - span * px - 14.0, 4.0), Vector2(span * px * 2.0 + 28.0, 66.0)), Color(0, 0, 0, 0.32))
	var start := int(floor(hdg - span))
	for d in range(start, start + int(span * 2.0) + 1):
		var dm := posmod(d, 360)
		if dm % 5 != 0:
			continue
		var x := c.x + (float(d) - hdg) * px
		var tall := dm % 15 == 0
		draw_line(Vector2(x, c.y), Vector2(x, c.y - (9.0 if tall else 4.0)), col, 1.5)
		if dm % 45 == 0:
			var names := [GS.t("С"), GS.t("СВ"), GS.t("В"), GS.t("ЮВ"), GS.t("Ю"), GS.t("ЮЗ"), GS.t("З"), GS.t("СЗ")]
			_txt(Vector2(x - 20, c.y - 13), String(names[dm / 45]), 13, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 3), c + Vector2(-5, 11), c + Vector2(5, 11)]), col)
	_txt(Vector2(c.x - 40, c.y + 28), "%03d°" % (int(hdg) % 360), 14, col, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _draw_prompt(sz: Vector2) -> void:
	if rl.near.is_empty():
		return
	var verb := GS.t("занять место")
	match String(rl.near.kind):
		"post":
			verb = GS.t("к пульту")
		"truck":
			verb = GS.t("сесть за руль")
	_txt(Vector2(sz.x * 0.5 - 400, sz.y * 0.5 + 86), "%s — %s: %s" % [GS.key_label("use"), verb, String(rl.near.name)], 18, INK, HORIZONTAL_ALIGNMENT_CENTER, 800)


## At a gun or an infrared launcher the sight is drawn by the reticle; here only the keys.
func _draw_seat_hint(sz: Vector2) -> void:
	var w = game.base_view.weapon()
	if w == null:
		return
	var fire := GS.t("ЛКМ — огонь") if String(w.def.kind) == "gun" else GS.t("держите цель в кольце до ровного тона · ЛКМ — пуск")
	_txt(Vector2(40, sz.y - 22), GS.t("%s · ПКМ / колесо — кратность · %s — ночной прицел · %s — встать") % [fire, GS.key_label("night"), GS.key_label("use")], 13, Color(DIM.r, DIM.g, DIM.b, 0.85), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)


## Radio traffic at the top of the screen, the newest call first: beside the scope at an
## operator's console, in the left column elsewhere, and under the instructor's card (`below`).
func _draw_radio(sz: Vector2, below: float) -> void:
	var x := 24.0
	var y := 40.0
	var w := minf(520.0, sz.x * 0.4)
	match String(game.view):
		"post":
			w = sz.x * 0.5 - _post_radius(sz) - 70.0
		"base":
			if rl.scope_on():
				x = _console_radius(sz) * 2.0 + 96.0
				w = minf(520.0, sz.x - x - 24.0)
			else:
				y = 134.0 # under the heading tape of the sight
				w = minf(360.0, sz.x * 0.26)
	if below > 0.0:
		y = maxf(y, below + 14.0)
	for i in range(rl.radio_log.size() - 1, -1, -1):
		var r: Dictionary = rl.radio_log[i]
		var col: Color = r.color
		col.a = clampf((16.0 - float(r.age)) / 2.0, 0.0, 1.0)
		y += _para(Vector2(x, y), "📻 " + String(r.text), 15, col, w) + 6.0


func _console_radius(sz: Vector2) -> float:
	return clampf(sz.y * 0.22, 130.0, 260.0)


func _post_radius(sz: Vector2) -> float:
	return clampf(minf(sz.y * 0.36, sz.x * 0.22), 150.0, 400.0)


# --- The scope --------------------------------------------------------------------------------
func _scope(c: Vector2, r: float, with_gate: bool) -> void:
	var scale: float = rl.scope_scale
	draw_circle(c, r + 10.0, Color(0.03, 0.035, 0.03, 0.98))
	draw_circle(c, r, Color(0.01, 0.055, 0.03, 1.0))
	var grid := Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.2)
	for k in [0.25, 0.5, 0.75, 1.0]:
		draw_arc(c, r * k, 0, TAU, 72, grid, 1.0)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * r * 0.06, c + d * r, Color(grid.r, grid.g, grid.b, 0.12), 1.0)
		_txt(c + d * (r + 24.0) + Vector2(-20, 5), "%03d" % (i * 30), 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# how far the system on this console reaches
	var w = rl.weapon()
	if w != null:
		var wr: float = float(w.effective_range()) / scale * r
		if wr <= r:
			draw_arc(c, wr, 0, TAU, 72, Color(AMBER.r, AMBER.g, AMBER.b, 0.35), 1.0)
	# the sweep and its afterglow
	var steps := 24
	var tail := 0.7
	for i in steps:
		var a0: float = rl.sweep - tail * float(i) / steps
		var a1: float = rl.sweep - tail * float(i + 1) / steps
		var alpha := 0.2 * (1.0 - float(i) / steps)
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(sin(a0), -cos(a0)) * r, c + Vector2(sin(a1), -cos(a1)) * r]), Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, alpha))
	draw_line(c, c + Vector2(sin(rl.sweep), -cos(rl.sweep)) * r, Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.7), 1.5)
	# echoes: all alike, the radar does not know what they are
	var period: float = rl.SWEEP_POST if game.view == "post" else rl.SWEEP_SAM
	for id in rl.blips:
		var b: Dictionary = rl.blips[id]
		var v: Vector2 = b.pos / scale * r
		if v.length() > r - 2.0:
			continue
		var fade := clampf(1.0 - float(b.age) / (period * 1.6), 0.0, 1.0)
		draw_circle(c + v, 3.4, Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.25 + 0.75 * fade))
		draw_circle(c + v, 1.6, Color(0.9, 1.0, 0.9, fade))
	for m in rl.missiles:
		var mv: Vector2 = Vector2(m.position.x - GS.base_pos.x, m.position.z - GS.base_pos.z) / scale * r
		if mv.length() < r - 2.0:
			draw_rect(Rect2(c + mv - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1.0, 0.95, 0.7, 0.9))
	if with_gate:
		var az: float = rl.scope_az
		var d := Vector2(sin(az), -cos(az))
		var gr: float = clampf(rl.scope_rng / scale, 0.0, 1.0) * r
		var tracking: bool = rl.track != null
		var gc := AMBER if tracking else Color(INK.r, INK.g, INK.b, 0.8)
		draw_line(c, c + d * r, Color(gc.r, gc.g, gc.b, 0.45), 1.0)
		var half: float = rl.GATE_AZ if gr > 30.0 else 0.6
		var depth := maxf(6.0, gr * rl.GATE_RNG + 300.0 / scale * r)
		for rr in [gr - depth, gr + depth]:
			if rr > 2.0 and rr < r:
				draw_arc(c, rr, az - PI * 0.5 - half, az - PI * 0.5 + half, 12, gc, 2.0 if tracking else 1.5)
	draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(INK.r, INK.g, INK.b, 0.8))
	draw_arc(c, r, 0, TAU, 96, Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.55), 2.0)


## Label and value on one line of a console's readout.
func _row(at: Vector2, label: String, value: String, col := INK, w := 300.0) -> void:
	_txt(at, label, 14, DIM)
	_txt(at, value, 16, col, HORIZONTAL_ALIGNMENT_RIGHT, w)


## The readout of the cursor, or of the tracked blip: what a radar can tell about an echo.
func _readout(at: Vector2, w: float) -> float:
	var y := at.y
	var td: Dictionary = rl.track_data()
	_row(Vector2(at.x, y), GS.t("АЗИМУТ"), "%03d°" % (int(rad_to_deg(float(td.get("az", rl.scope_az)))) % 360), INK, w)
	y += 24.0
	_row(Vector2(at.x, y), GS.t("ДАЛЬНОСТЬ"), GS.t("%.1f км") % (float(td.get("rng", rl.scope_rng)) * 0.001), INK, w)
	y += 24.0
	if td.is_empty():
		_row(Vector2(at.x, y), GS.t("СОПРОВОЖДЕНИЕ"), GS.t("НЕТ"), DIM, w)
		return y + 24.0
	_row(Vector2(at.x, y), GS.t("ВЫСОТА"), GS.t("%d м") % (int(float(td.alt) / 10.0) * 10), INK, w)
	y += 24.0
	_row(Vector2(at.x, y), GS.t("СКОРОСТЬ"), GS.t("%d км/ч") % (int(float(td.kmh) / 10.0) * 10), INK, w)
	y += 24.0
	var move := GS.t("ПРИБЛИЖАЕТСЯ") if bool(td.closing) else GS.t("УДАЛЯЕТСЯ")
	if float(td.vy) < -60.0:
		move += GS.t(" · ПИКИРУЕТ")
	_row(Vector2(at.x, y), GS.t("ДВИЖЕНИЕ"), move, AMBER if bool(td.closing) else INK, w)
	return y + 24.0


## The operator's place of a system with its own radar: the scope on the left, the window of the
## cabin (the 3D picture) everywhere else.
func _draw_console(sz: Vector2) -> void:
	var w = rl.weapon()
	if w == null:
		return
	var r := _console_radius(sz)
	var pw := r * 2.0 + 60.0
	var panel := Rect2(Vector2(16, sz.y - (r * 2.0 + 326.0)), Vector2(pw, r * 2.0 + 310.0))
	draw_rect(panel, CASE)
	draw_rect(panel, Color(DIM.r, DIM.g, DIM.b, 0.5), false, 1.5)
	var c := panel.position + Vector2(pw * 0.5, r + 62.0)
	_scope(c, r, true)
	var x := panel.position.x + 22.0
	var rw := pw - 44.0
	var y := c.y + r + 44.0
	_txt(Vector2(x, y), GS.t(String(w.def.name)), 17, INK)
	_txt(Vector2(x, y), GS.t("ШКАЛА %d км") % int(rl.scope_scale * 0.001), 14, DIM, HORIZONTAL_ALIGNMENT_RIGHT, rw)
	y += 28.0
	y = _readout(Vector2(x, y), rw)
	var is_drone: bool = String(w.def.kind) == "drone"
	var td: Dictionary = rl.track_data()
	if not td.is_empty():
		var ok: bool = w.can_engage(rl.track) and w.in_range(rl.track)
		_row(Vector2(x, y), GS.t("ЗОНА ПОРАЖЕНИЯ"), GS.t("В ЗОНЕ") if ok else GS.t("ВНЕ ЗОНЫ"), PHOSPHOR if ok else AMBER, rw)
		y += 24.0
	var left := int(GS.ammo.get(w.id, 0))
	_row(Vector2(x, y), GS.t("ДРОНОВ") if is_drone else GS.t("РАКЕТ"), "%d" % left, INK if left > 0 else AMBER, rw)
	if rl.salvo > 0:
		_txt(Vector2(x + rw * 0.4, y), GS.t("пущено: %d") % rl.salvo, 14, AMBER)
	if rl.console_t > 0.0:
		_txt(Vector2(panel.position.x, panel.position.y + 24.0), rl.console_msg, 16, Color(AMBER.r, AMBER.g, AMBER.b, clampf(rl.console_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, pw)
	var hint := GS.t("мышь ↔ азимут · мышь ↕ дальность · ПКМ — захват / сброс · ЛКМ — пуск · колесо — шкала · %s — встать") % GS.key_label("use")
	if DisplayServer.is_touchscreen_available():
		hint = GS.t("ведите пальцем: ↔ азимут, ↕ дальность · ЗАХВАТ · ОГОНЬ — пуск")
	_txt(Vector2(panel.end.x + 20.0, sz.y - 22), hint, 13, Color(DIM.r, DIM.g, DIM.b, 0.85), HORIZONTAL_ALIGNMENT_LEFT, sz.x - panel.end.x - 40.0)


## The command post: the surveillance scope and the state board. The whole screen is the console.
func _draw_post(sz: Vector2) -> void:
	var r := _post_radius(sz)
	var c := Vector2(sz.x * 0.5, sz.y * 0.5 + 10.0)
	_scope(c, r, true)
	if rl.console_t > 0.0:
		_txt(Vector2(c.x - r, c.y - r - 46.0), rl.console_msg, 16, Color(AMBER.r, AMBER.g, AMBER.b, clampf(rl.console_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	var x := c.x + r + 60.0
	var w := minf(380.0, sz.x - x - 30.0)
	var y := c.y - r + 6.0
	_txt(Vector2(x, y), GS.t("КОМАНДНЫЙ ПУНКТ"), 22, INK)
	y += 28.0
	var d = game.director
	var clock := ""
	if d != null and not GS.training:
		var secs := int(d.time_left())
		clock = GS.t("ДЕНЬ %d · %s · %d:%02d") % [GS.day, d.phase_name(), secs / 60, secs % 60]
		if d.is_night() and d.time_left() <= 0.0:
			clock = GS.t("ДЕНЬ %d · НОЧЬ · в небе ещё есть цели") % GS.day
	_txt(Vector2(x, y), GS.world_name if clock == "" else "%s · %s" % [GS.world_name, clock], 14, DIM)
	y += 36.0
	_txt(Vector2(x, y), GS.t("ОБЗОРНЫЙ РАДАР · ШКАЛА %d км") % int(rl.scope_scale * 0.001), 14, DIM)
	y += 26.0
	y = _readout(Vector2(x, y), w) + 14.0
	_row(Vector2(x, y), GS.t("БЮДЖЕТ"), GS.fmt_money(GS.money), INK if GS.money >= 0 else AMBER, w)
	y += 24.0
	_row(Vector2(x, y), GS.t("ГОРОД"), "%d%%" % int(GS.city), INK if GS.city > 40.0 else AMBER, w)
	y += 24.0
	_row(Vector2(x, y), GS.t("ПОЗИЦИЯ"), "%d%%" % int(GS.base_hp), INK if GS.base_hp > 40.0 else AMBER, w)
	y += 24.0
	var found := GS.t("РАСКРЫТА — ЖДИТЕ УДАР") if GS.base_found else GS.t("не обнаружена")
	_row(Vector2(x, y), GS.t("МАСКИРОВКА"), found, AMBER if GS.base_found else INK, w)
	y += 24.0
	_row(Vector2(x, y), GS.t("РАСЧЁТЫ [%s]") % GS.key_label("auto"), GS.t("ОГОНЬ ПО ГОТОВНОСТИ") if rl.crews_free() else GS.t("НЕ СТРЕЛЯТЬ"), INK if rl.crews_free() else AMBER, w)
	y += 38.0
	_txt(Vector2(x, y), GS.t("НА ПОЗИЦИИ"), 14, DIM)
	y += 22.0
	for id in game.owned_weapons():
		var def: Dictionary = GS.WEAPONS[id]
		var kind := String(def.kind)
		var left := GS.t("боекомплект") if kind == "gun" else "%d" % int(GS.ammo.get(id, 0))
		_row(Vector2(x, y), GS.t(String(def.short)), left, DIM if kind == "gun" else (INK if int(GS.ammo.get(id, 0)) > 0 else AMBER), w)
		y += 21.0
		if y > sz.y - 90.0:
			break
	var keys := GS.t("%s — снабжение · %s — удары по точкам пуска · %s — лента города · %s — приказ расчётам · %s — встать") % [GS.key_label("shop"), GS.key_label("strikes"), GS.key_label("feed"), GS.key_label("auto"), GS.key_label("use")]
	_txt(Vector2(40, sz.y - 44), keys, 14, INK, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)
	_txt(Vector2(40, sz.y - 22), GS.t("мышь ↔ азимут · мышь ↕ дальность · ПКМ — взять отметку на сопровождение · колесо — шкала"), 13, Color(DIM.r, DIM.g, DIM.b, 0.85), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)


# --- Training ---------------------------------------------------------------------------------
## The instructor's card: what to do now. Lessons are scripts/game/training.gd.
## Returns the bottom edge of the card (0 when there is none).
func _draw_training(sz: Vector2) -> float:
	var t = rl.training
	var lines: PackedStringArray = t.card()
	if lines.is_empty():
		return 0.0
	var w := minf(760.0, sz.x - 60.0)
	var at := Vector2(sz.x * 0.5 - w * 0.5, 84.0 if game.view == "walk" else 20.0)
	if game.view == "post":
		# the scope has the middle of the screen: the card takes the left column
		w = sz.x * 0.5 - _post_radius(sz) - 70.0
		at = Vector2(24.0, 20.0)
	elif game.view == "base" and rl.scope_on():
		at.x = _console_radius(sz) * 2.0 + 96.0
		w = minf(w, sz.x - at.x - 24.0)
	var h := 40.0
	for i in lines.size():
		h += GS.font.get_multiline_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, w - 36.0, 17 if i == 0 else 15).y + 4.0
	var low: bool = game.view == "base" and not rl.scope_on()
	if low:
		at.y = sz.y - h - 44.0 # at a sight the sky is where the targets are: the card goes down
	draw_rect(Rect2(at, Vector2(w, h)), Color(0.04, 0.05, 0.045, 0.86))
	draw_rect(Rect2(at, Vector2(4, h)), AMBER)
	_txt(at + Vector2(18, 22), GS.t("ИНСТРУКТОР · урок %d из %d") % [t.step + 1, t.total()], 13, AMBER)
	var y := at.y + 46.0
	for i in lines.size():
		y += _para(Vector2(at.x + 18.0, y), lines[i], 17 if i == 0 else 15, INK if i == 0 else Color(INK.r, INK.g, INK.b, 0.85), w - 36.0) + 4.0
	return 0.0 if low else at.y + h
