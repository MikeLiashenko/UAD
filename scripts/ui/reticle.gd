extends Control
## Gunner sight overlay for the base view: crosshair, heading tape, elevation ladder, zoom,
## target brackets / lock-on, lead indicator (systems with a fire-control computer),
## debris-fall forecast, hit markers and a kill banner.

const Bullet = preload("res://scripts/game/bullet.gd")

var game
var bv
var _t := 0.0
var _hit_t := 0.0
var _kill_t := 0.0
var _kill_text := ""
var _kill_color := Color.WHITE

const NEON := Color(0.3, 1.0, 0.6)
const RED := Color(1.0, 0.25, 0.2)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func hit() -> void:
	_hit_t = 0.14


func kill(text: String, color := Color(0.3, 1.0, 0.5)) -> void:
	_kill_t = 1.8
	_kill_text = text
	_kill_color = color


func _process(delta: float) -> void:
	_t += delta
	_hit_t = maxf(0.0, _hit_t - delta)
	_kill_t = maxf(0.0, _kill_t - delta)
	visible = bv != null and bv.active
	if visible:
		queue_redraw()


func _txt(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, pos, s, align, width, size, 4, Color(0, 0, 0, 0.7))
	draw_string(GS.font, pos, s, align, width, size, col)


func _brackets(c: Vector2, r: float, col: Color, w := 2.0) -> void:
	var k := r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * r, sy * r)
			draw_line(p, p - Vector2(sx * k, 0), col, w)
			draw_line(p, p - Vector2(0, sy * k), col, w)


func _draw() -> void:
	if bv == null or not bv.active:
		return
	var w = bv.weapon()
	if w == null:
		return
	var cam: Camera3D = bv.cam
	var sz := size
	var c := sz * 0.5
	var kind := String(w.def.kind)
	var col := NEON
	# --- crosshair
	if kind == "gun":
		draw_arc(c, 16.0, 0, TAU, 32, Color(col.r, col.g, col.b, 0.8), 1.5)
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			var d := Vector2.from_angle(a)
			draw_line(c + d * 20.0, c + d * 44.0, col, 2.0)
		draw_circle(c, 2.0, col)
		# stadiametric marks for manual lead (pickup has no fire-control computer)
		for i in range(1, 4):
			draw_line(c + Vector2(-6, 30 + i * 18), c + Vector2(6, 30 + i * 18), Color(col.r, col.g, col.b, 0.6), 1.5)
			draw_line(c + Vector2(30 + i * 18, -6), c + Vector2(30 + i * 18, 6), Color(col.r, col.g, col.b, 0.6), 1.5)
	else:
		draw_arc(c, 90.0, 0, TAU, 64, Color(col.r, col.g, col.b, 0.35), 1.5)
		for a in 12:
			var d := Vector2.from_angle(TAU * a / 12.0)
			draw_line(c + d * 86.0, c + d * 96.0, Color(col.r, col.g, col.b, 0.6), 2.0)
		draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), col, 1.5)
		draw_line(c + Vector2(0, -10), c + Vector2(0, 10), col, 1.5)
	# --- heading tape
	var dir: Vector3 = bv.aim_dir()
	var hdg := fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	var tape_y := 70.0
	var span := 50.0
	var px_per_deg := 9.0
	draw_line(Vector2(c.x - span * px_per_deg, tape_y + 14), Vector2(c.x + span * px_per_deg, tape_y + 14), Color(col.r, col.g, col.b, 0.4), 1.0)
	var start := int(floor(hdg - span))
	for d in range(start, start + int(span * 2) + 1):
		var x := c.x + (float(d) - hdg) * px_per_deg
		var dm := posmod(d, 360)
		if dm % 5 == 0:
			var tall := dm % 10 == 0
			draw_line(Vector2(x, tape_y + 14), Vector2(x, tape_y + (2 if tall else 8)), Color(col.r, col.g, col.b, 0.7), 1.5)
			if tall:
				var lbl := str(dm)
				match dm:
					0:
						lbl = GS.t("С")
					90:
						lbl = GS.t("В")
					180:
						lbl = GS.t("Ю")
					270:
						lbl = GS.t("З")
				_txt(Vector2(x - 20, tape_y - 4), lbl, 13, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x, tape_y + 16), Vector2(c.x - 7, tape_y + 28), Vector2(c.x + 7, tape_y + 28)]), col)
	_txt(Vector2(c.x - 40, tape_y + 46), "%03d°" % int(hdg), 16, col, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# --- elevation ladder
	var elev := rad_to_deg(bv.pitch)
	var lx := c.x + 300.0
	for e in range(-10, 91, 5):
		var y := c.y - (float(e) - elev) * 6.0
		if y < 120 or y > sz.y - 160:
			continue
		var big := e % 10 == 0
		draw_line(Vector2(lx, y), Vector2(lx + (22 if big else 12), y), Color(col.r, col.g, col.b, 0.6), 1.5)
		if big:
			_txt(Vector2(lx + 26, y + 5), "%d°" % e, 12, col)
	draw_colored_polygon(PackedVector2Array([Vector2(lx - 4, c.y), Vector2(lx - 16, c.y - 7), Vector2(lx - 16, c.y + 7)]), col)
	_txt(Vector2(c.x - 360, c.y + 5), "×%.1f" % (70.0 / bv.fov), 18, col)
	# --- targets
	var fcs: bool = bool(w.def.fcs)
	for e in game.enemies:
		if e.dead or cam.is_position_behind(e.position):
			continue
		var sp := cam.unproject_position(e.position)
		var is_cand: bool = e == bv.candidate
		if GS.settings.markers:
			var mc: Color = e.def.color
			draw_arc(sp, 6.0, 0, TAU, 12, mc, 1.5)
			_txt(sp + Vector2(10, -6), GS.t("%s %.1f км") % [GS.t(String(e.def.abbr)), cam.global_position.distance_to(e.position) * 0.005], 12, mc)
		if is_cand:
			var locked_ready: bool = bv.lock == e and bv.lock_ready
			var bc := RED if locked_ready else Color(1, 1, 1, 0.9)
			var r := 22.0
			if kind != "gun" and bv.lock == e and not bv.lock_ready:
				r = lerpf(60.0, 22.0, clampf(bv.lock_t / 0.7, 0.0, 1.0))
				bc = Color(1.0, 0.8, 0.3)
			_brackets(sp, r, bc, 2.0)
			if locked_ready and int(_t * 6.0) % 2 == 0:
				var go: String = GS.t("ЗАХВАТ · ЛКМ — ПУСК ДРОНА") if kind == "drone" else GS.t("ЗАХВАТ · ПУСК ЛКМ")
				_txt(sp + Vector2(-60, -r - 10), go, 14, RED, HORIZONTAL_ALIGNMENT_CENTER, 120)
			if kind == "gun" and fcs:
				var lp: Vector3 = Bullet.lead(w.muzzle.global_position, e.position, e.vel, float(w.def.speed))
				if not cam.is_position_behind(lp):
					var ls := cam.unproject_position(lp)
					draw_line(sp, ls, Color(1.0, 0.85, 0.3, 0.5), 1.0)
					draw_arc(ls, 7.0, 0, TAU, 16, Color(1.0, 0.85, 0.3), 2.0)
					draw_circle(ls, 1.5, Color(1.0, 0.85, 0.3))
	# --- info panel under the crosshair
	var info_y := c.y + 112.0
	var ammo := "∞" if kind == "gun" else "×%d" % int(GS.ammo.get(w.id, 0))
	var reload := ""
	if kind != "gun" and w.cooldown > 0.0:
		reload = GS.t(" · ПЕРЕЗАРЯДКА")
	_txt(Vector2(c.x - 250, info_y), GS.t("%s  %s  · дальность %.1f км%s") % [GS.t(String(w.def.short)), ammo, w.effective_range() * 0.005, reload], 16, col, HORIZONTAL_ALIGNMENT_CENTER, 500)
	if not fcs:
		_txt(Vector2(c.x - 250, info_y + 20), GS.t("без СУО — берите упреждение по меткам прицела"), 12, Color(col.r, col.g, col.b, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 500)
	elif kind == "drone":
		var air := GS.t("в воздухе: %d") % game.drones.size()
		_txt(Vector2(c.x - 250, info_y + 20), GS.t("[C] — пульт FPV · %s · дрон без цели сам вернётся на базу") % air, 12, Color(col.r, col.g, col.b, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 500)
	var cand = bv.candidate
	if cand != null and is_instance_valid(cand) and not cand.dead:
		var info: Dictionary = game.predict_debris(cand)
		var dist := cam.global_position.distance_to(cand.position)
		_txt(Vector2(c.x - 250, info_y + 42), GS.t("%s · Д %.1f км · В %d м · %d%%") % [GS.t(String(cand.def.name)), dist * 0.005, int(cand.position.y * 5.0), int(100.0 * cand.hp / cand.max_hp)], 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 500)
		_txt(Vector2(c.x - 250, info_y + 64), GS.t("Обломки: ") + String(info.text), 16, info.color, HORIZONTAL_ALIGNMENT_CENTER, 500)
		if not w.can_engage(cand):
			_txt(Vector2(c.x - 250, info_y + 86), GS.t("%s НЕ ПОРАЖАЕТ ЭТУ ЦЕЛЬ") % GS.t(String(w.def.short)), 15, RED, HORIZONTAL_ALIGNMENT_CENTER, 500)
		elif not w.in_range(cand):
			_txt(Vector2(c.x - 250, info_y + 86), GS.t("ВНЕ ЗОНЫ ПОРАЖЕНИЯ"), 15, Color(1.0, 0.7, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 500)
	# --- hit marker & kill banner
	if _hit_t > 0.0:
		var hc := Color(1, 1, 1, _hit_t / 0.14)
		for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + s * 8.0, c + s * 18.0, hc, 2.5)
	if _kill_t > 0.0:
		var a := clampf(_kill_t / 0.6, 0.0, 1.0)
		var kc := Color(_kill_color.r, _kill_color.g, _kill_color.b, a)
		var lines := _kill_text.split("\n")
		for i in lines.size():
			_txt(Vector2(c.x - 300, c.y - 90 + i * 34), lines[i], 30 if i == 0 else 22, kc, HORIZONTAL_ALIGNMENT_CENTER, 600)
	_txt(Vector2(c.x - 400, 150), GS.t("ЛКМ — огонь/пуск · ПКМ/колесо — зум · %s — ночной прицел · %s — вид сверху · 1-9 или %s/%s — ПВО · %s — дрон · Alt — курсор") % [GS.key_label("night"), GS.key_label("view"), GS.key_label("weapon_prev"), GS.key_label("weapon_next"), GS.key_label("fpv")], 12, Color(col.r, col.g, col.b, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 800)
