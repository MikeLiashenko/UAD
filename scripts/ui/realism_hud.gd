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
## Touch screens: the buttons of the seat the player is in ({id, text} with a centre and a radius,
## or with a rect) and the fingers resting on them (touch index -> id). A Button control hears
## only the first finger on the screen — it lives on the emulated mouse — so with a thumb on the
## stick nothing else could be pressed; these are hit-tested for every finger (see _input).
var _btns: Array = []
var _held := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if rl.touch:
		var live: bool = not get_tree().paused and not game.game_over
		_btns = _layout(size) if live else []
		if not live:
			_release_all()
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
	if rl.touch:
		_draw_touch(sz)


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
	var what := "%s: %s" % [verb, String(rl.near.name)]
	if not rl.touch:
		what = "%s — %s" % [GS.key_label("use"), what]
	_txt(Vector2(sz.x * 0.5 - 400, sz.y * 0.5 + 86), what, 18, INK, HORIZONTAL_ALIGNMENT_CENTER, 800)


## At a gun or an infrared launcher the sight is drawn by the reticle; here only the keys.
func _draw_seat_hint(sz: Vector2) -> void:
	var w = game.base_view.weapon()
	if w == null or rl.touch:
		return # on a touch screen the buttons say it all
	var fire := GS.t("ЛКМ — огонь") if String(w.def.kind) == "gun" else GS.t("держите цель в кольце до ровного тона · ЛКМ — пуск")
	_txt(Vector2(40, sz.y - 22), GS.t("%s · ПКМ / колесо — кратность · %s — ночной прицел · %s — встать") % [fire, GS.key_label("night"), GS.key_label("use")], 13, Color(DIM.r, DIM.g, DIM.b, 0.85), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)


## Radio traffic at the top of the screen, the newest call first: beside the scope at an
## operator's console, in the left column elsewhere, and under the instructor's card (`below`).
func _draw_radio(sz: Vector2, below: float) -> void:
	var x := 24.0
	var y := 40.0
	var w := minf(520.0, sz.x * 0.4)
	match String(game.view):
		"walk":
			y = 86.0 # under the compass
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
	if rl.touch:
		hint = GS.t("ведите пальцем по экрану: ↔ азимут, ↕ дальность")
	_txt(Vector2(panel.end.x + 20.0, sz.y - 22), hint, 13, Color(DIM.r, DIM.g, DIM.b, 0.85), HORIZONTAL_ALIGNMENT_LEFT, sz.x - panel.end.x - 40.0)


## The command post: the surveillance scope and the state board. The whole screen is the console.
func _draw_post(sz: Vector2) -> void:
	var r := _post_radius(sz)
	var c := Vector2(sz.x * 0.5, sz.y * 0.5 + (-14.0 if rl.touch else 10.0))
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
	_row(Vector2(x, y), GS.t("РАСЧЁТЫ") if rl.touch else GS.t("РАСЧЁТЫ [%s]") % GS.key_label("auto"), GS.t("ОГОНЬ ПО ГОТОВНОСТИ") if rl.crews_free() else GS.t("НЕ СТРЕЛЯТЬ"), INK if rl.crews_free() else AMBER, w)
	if not GS.training:
		y += 24.0
		var left := int(ceil(game.shelter_left()))
		var people := GS.t("НЕ ОБЪЯВЛЕНА")
		if game.alarm:
			people = GS.t("ЛЮДИ В УКРЫТИЯХ") if left <= 0 else GS.t("В УКРЫТИЯХ ЧЕРЕЗ %d с") % left
		_row(Vector2(x, y), GS.t("ТРЕВОГА") if rl.touch else GS.t("ТРЕВОГА [%s]") % GS.key_label("alarm"), people, (INK if left <= 0 else AMBER) if game.alarm else DIM, w)
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
	if rl.touch:
		return # the row of buttons along the bottom stands for the keys
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
	var low: bool = game.view == "base" and not rl.scope_on()
	if low and rl.touch:
		# the bottom right corner belongs to the buttons
		at.x = 24.0
		w = minf(w, sz.x - 24.0 - 340.0)
	var h := 40.0
	for i in lines.size():
		h += GS.font.get_multiline_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, w - 36.0, 17 if i == 0 else 15).y + 4.0
	if low:
		at.y = sz.y - h - 44.0 # at a sight the sky is where the targets are: the card goes down
	draw_rect(Rect2(at, Vector2(w, h)), Color(0.04, 0.05, 0.045, 0.86))
	draw_rect(Rect2(at, Vector2(4, h)), AMBER)
	_txt(at + Vector2(18, 22), GS.t("ИНСТРУКТОР · урок %d из %d") % [t.step + 1, t.total()], 13, AMBER)
	var y := at.y + 46.0
	for i in lines.size():
		y += _para(Vector2(at.x + 18.0, y), lines[i], 17 if i == 0 else 15, INK if i == 0 else Color(INK.r, INK.g, INK.b, 0.85), w - 36.0) + 4.0
	return 0.0 if low else at.y + h


# --- Touch screens --------------------------------------------------------------------------------
## The buttons of the seat the player is in: round ones in the bottom right corner (the left half
## of the screen is the stick), a row along the bottom at the command post, the pause on top.
func _layout(sz: Vector2) -> Array:
	var out := [{"id": "pause", "c": Vector2(sz.x - 46.0, 46.0), "r": 28.0, "text": "❚❚"}]
	if not GS.training:
		# the air-raid alarm is called over the radio: the button is there in every seat and on foot
		out.append({"id": "alarm", "rect": Rect2(sz.x - 228.0, 20.0, 136.0, 52.0), "text": GS.t("ОТБОЙ") if game.alarm else GS.t("ТРЕВОГА"), "hot": true, "lit": game.alarm})
	match String(game.view):
		"walk":
			if not rl.near.is_empty():
				out.append({"id": "use", "c": sz + Vector2(-130, -150), "r": 62.0, "text": GS.t("МЕСТО")})
		"base":
			var w = game.base_view.weapon()
			var gun: bool = w != null and String(w.def.kind) == "gun"
			out.append({"id": "fire", "c": sz + Vector2(-112, -128), "r": 70.0, "text": GS.t("ОГОНЬ") if gun else GS.t("ПУСК"), "hot": true})
			out.append({"id": "use", "c": sz + Vector2(-262, -64), "r": 44.0, "text": GS.t("ВСТАТЬ")})
			out.append({"id": "zoom_in", "c": sz + Vector2(-60, -262), "r": 36.0, "text": "+"})
			out.append({"id": "zoom_out", "c": sz + Vector2(-146, -262), "r": 36.0, "text": "−"})
			if rl.scope_on():
				out.append({"id": "lock", "c": sz + Vector2(-258, -176), "r": 56.0, "text": GS.t("ЗАХВАТ")})
			else:
				out.append({"id": "nv", "c": sz + Vector2(-250, -172), "r": 44.0, "text": GS.t("НОЧЬ")})
		"mfg":
			var driving: bool = game.mfg.seat == "drive"
			out.append({"id": "fire", "c": sz + Vector2(-112, -128), "r": 70.0, "text": GS.t("ОГОНЬ"), "hot": true})
			out.append({"id": "seat", "c": sz + Vector2(-258, -176), "r": 56.0, "text": GS.t("ПУЛЕМЁТ") if driving else GS.t("РУЛЬ")})
			out.append({"id": "use", "c": sz + Vector2(-262, -64), "r": 44.0, "text": GS.t("ВЫЙТИ")})
		"post":
			var row := [["shop", GS.t("СНАБЖЕНИЕ"), 150.0], ["crew", GS.t("РАСЧЁТЫ"), 126.0], ["lock", GS.t("ЗАХВАТ"), 124.0],
				["zoom_out", "−", 62.0], ["zoom_in", "+", 62.0], ["use", GS.t("ВСТАТЬ"), 120.0]]
			if not GS.training:
				row.insert(1, ["strikes", GS.t("УДАРЫ"), 110.0])
				row.insert(2, ["feed", GS.t("ЛЕНТА"), 110.0])
			var total := 10.0 * (row.size() - 1)
			for b in row:
				total += float(b[2])
			var x := (sz.x - total) * 0.5
			for b in row:
				out.append({"id": String(b[0]), "rect": Rect2(x, sz.y - 62.0, float(b[2]), 50.0), "text": String(b[1])})
				x += float(b[2]) + 10.0
	return out


## The button under a finger ("" when it is on none); a little generous around the edge.
func _hit(p: Vector2) -> String:
	for b in _btns:
		if b.has("rect"):
			var rc: Rect2 = b.rect
			if rc.grow(6.0).has_point(p):
				return String(b.id)
		elif p.distance_to(b.c) <= float(b.r) * 1.15:
			return String(b.id)
	return ""


## Fingers are taken before the game sees them: one that lands on a button belongs to the button
## until it is lifted, and never turns the head or moves the stick.
func _input(event: InputEvent) -> void:
	if not rl.touch:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			var id := _hit(st.position)
			if id == "":
				return
			_held[st.index] = id
			get_viewport().set_input_as_handled()
			_press(id, true)
		elif _held.has(st.index):
			var was := String(_held[st.index])
			_held.erase(st.index)
			get_viewport().set_input_as_handled()
			_press(was, false)
	elif event is InputEventScreenDrag and _held.has((event as InputEventScreenDrag).index):
		get_viewport().set_input_as_handled()


func _press(id: String, on: bool) -> void:
	if id == "fire":
		game.set_trigger(on) # held for a gun, one launch a press for everything else
		return
	if not on:
		return
	SFX.play("click", -10.0)
	match id:
		"use":
			rl.use()
		"pause":
			game.hud.toggle_pause()
		"lock":
			rl.lock()
		"zoom_in":
			if rl.scope_on():
				rl.step_scale(-1)
			else:
				game.base_view.zoom(0.6)
		"zoom_out":
			if rl.scope_on():
				rl.step_scale(1)
			else:
				game.base_view.zoom(1.67)
		"nv":
			game.base_view.nv = not game.base_view.nv
		"seat":
			game.mfg.switch_seat()
		"shop":
			game.hud.open_shop()
		"strikes":
			game.hud.open_strikes()
		"feed":
			game.hud.open_feed()
		"crew":
			rl.crew_order()
		"alarm":
			game.toggle_alarm()


## A window opened or the game ended with fingers still down.
func _release_all() -> void:
	if _held.values().has("fire"):
		game.set_trigger(false)
	_held.clear()


func _draw_touch(sz: Vector2) -> void:
	# the stick: where the thumb is, or a faint ring where it is expected
	var origin := Vector2(150.0, sz.y - 170.0)
	var vec := Vector2.ZERO
	var shown := false
	var on := false
	if game.view == "walk":
		shown = true
		on = int(game.walker._move_touch) >= 0
		if on:
			origin = game.walker._move_origin
			vec = game.walker._move_vec
	elif game.view == "mfg" and game.mfg.seat == "drive":
		shown = true
		on = int(game.mfg._touch_move) >= 0
		if on:
			origin = game.mfg._touch_origin
			vec = game.mfg._touch_vec
	if shown and not get_tree().paused:
		draw_arc(origin, 90.0, 0, TAU, 48, Color(INK.r, INK.g, INK.b, 0.55 if on else 0.2), 2.0)
		draw_circle(origin + Vector2(vec.x, -vec.y) * 90.0, 30.0, Color(INK.r, INK.g, INK.b, 0.4 if on else 0.12))
	var held := _held.values()
	for b in _btns:
		var down: bool = held.has(b.id)
		var edge: Color = Color(0.92, 0.45, 0.35) if b.get("hot", false) else DIM
		if down:
			edge = INK
		var fill := Color(0.22, 0.26, 0.22, 0.8) if down else Color(0.05, 0.065, 0.055, 0.5)
		if b.get("lit", false) and not down:
			fill = Color(0.6, 0.1, 0.07, 0.55 + 0.25 * absf(sin(Time.get_ticks_msec() * 0.003)))
		var text := String(b.text)
		if b.has("rect"):
			var rc: Rect2 = b.rect
			draw_rect(rc, fill)
			draw_rect(rc, edge, false, 2.0)
			_txt(Vector2(rc.position.x, rc.get_center().y + (9.0 if text.length() <= 2 else 5.0)), text, 26 if text.length() <= 2 else 15, INK, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
		else:
			var c: Vector2 = b.c
			var r: float = b.r
			draw_circle(c, r, fill)
			draw_arc(c, r, 0, TAU, 40, edge, 2.0)
			var fs := 28 if text.length() <= 2 else (17 if r >= 54.0 else 13)
			_txt(Vector2(c.x - r, c.y + fs * 0.36), text, fs, INK, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
