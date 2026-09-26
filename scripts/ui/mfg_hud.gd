extends Control
## Overlay of the mobile fire group (scripts/game/mobile_group.gd): the radio call with the drone
## to catch and an arrow to the beacon, speed, the truck's state, barrel heat; at the gun a
## crosshair and boxes on the threats in the searchlight's reach.

const NEON := Color(0.35, 1.0, 0.65)
const AMBER := Color(1.0, 0.75, 0.3)
const RED := Color(1.0, 0.32, 0.26)

var game
var mg


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	visible = mg != null and mg.active
	if visible:
		queue_redraw()


func _txt(p: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, p, s, align, width, size, 5, Color(0, 0, 0, 0.75))
	draw_string(GS.font, p, s, align, width, size, col)


func _bar(at: Vector2, w: float, v: float, col: Color, title: String) -> void:
	draw_rect(Rect2(at, Vector2(w, 10)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(at, Vector2(w * clampf(v, 0.0, 1.0), 10)), col)
	draw_rect(Rect2(at, Vector2(w, 10)), Color(col.r, col.g, col.b, 0.8), false, 1.5)
	_txt(at + Vector2(0, -5), title, 12, col)


func _draw() -> void:
	var sz := size
	var c := sz * 0.5
	var cam: Camera3D = mg.cam
	# --- the radio call, top centre
	var tip = mg.tip
	if tip != null and is_instance_valid(tip) and not tip.dead:
		var d: float = Vector2(tip.position.x - mg.pos.x, tip.position.z - mg.pos.z).length()
		var line := GS.t("📻 РАДИО: %s · %.1f км · выс. %d м · пролёт через %d с") % [GS.t(String(tip.def.name)), d * 0.005, int(tip.position.y * 5.0), int(mg.tip_eta)]
		if mg.tip_eta < 1.0 and mg.pos.distance_to(mg.tip_point) > 40.0:
			line = GS.t("📻 РАДИО: %s · %.1f км · уходит — ищите следующую цель") % [GS.t(String(tip.def.name)), d * 0.005]
		_txt(Vector2(c.x - 500, 118), line, 17, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 1000)
		if mg.seat == "drive":
			var to_beacon: float = mg.pos.distance_to(mg.tip_point)
			var hint := GS.t("Жми к маяку: %d м") % int(to_beacon) if to_beacon > 25.0 else GS.t("На месте! К ПУЛЕМЁТУ — Пробел")
			_txt(Vector2(c.x - 500, 142), hint, 15, NEON if to_beacon <= 25.0 else Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 1000)
			_edge_arrow(cam, mg.tip_point + Vector3(0, 3, 0), AMBER, "%d м" % int(to_beacon), sz)
		else:
			_edge_arrow(cam, tip.position, RED, "%.1f км" % (cam.global_position.distance_to(tip.position) * 0.005), sz)
	else:
		_txt(Vector2(c.x - 500, 118), GS.t("📻 РАДИО: на вашем участке тихо — ждите целей"), 16, Color(0.6, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 1000)
	# --- at the gun: crosshair and the threats in reach
	if mg.seat == "gun":
		var col := RED if mg.overheated else NEON
		draw_arc(c, 16.0, 0, TAU, 32, col, 1.5)
		for q in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + q * 22.0, c + q * 40.0, col, 2.0)
		draw_circle(c, 2.0, col)
		for e in game.enemies:
			if e.dead or cam.is_position_behind(e.position):
				continue
			var dist: float = cam.global_position.distance_to(e.position)
			if dist > 900.0:
				continue
			var sp := cam.unproject_position(e.position)
			var r := clampf(700.0 / maxf(dist, 20.0), 8.0, 60.0)
			var in_reach := dist < float(GS.WEAPONS.mg.range)
			var ec := RED if in_reach else AMBER
			draw_rect(Rect2(sp - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), ec, false, 1.5)
			_txt(sp + Vector2(r + 5, 4), "%s · %d м" % [GS.t(String(e.def.abbr)), int(dist * 5.0)], 12, ec)
		if mg.overheated:
			_txt(Vector2(c.x - 200, c.y + 70), GS.t("СТВОЛ ПЕРЕГРЕТ"), 22, RED, HORIZONTAL_ALIGNMENT_CENTER, 400)
	# --- the truck, bottom left
	var top := Vector2(26, sz.y - 200)
	_txt(top, GS.t("МОГ · ПИКАП С ДШК"), 20, NEON)
	_txt(top + Vector2(0, 26), GS.t("%s · %d км/ч") % [GS.t("ЗА РУЛЁМ") if mg.seat == "drive" else GS.t("ЗА ПУЛЕМЁТОМ"), int(absf(mg.speed) * 3.6)], 15, Color(0.8, 1.0, 0.9))
	var hc: Color = NEON if mg.hp > 50.0 else (AMBER if mg.hp > 25.0 else RED)
	_bar(top + Vector2(0, 56), 170, mg.hp / 100.0, hc, GS.t("ПИКАП %d%%") % int(mg.hp))
	var heat_col: Color = RED if mg.overheated else (AMBER if mg.heat > 0.6 else Color(0.4, 0.85, 1.0))
	_bar(top + Vector2(0, 92), 170, mg.heat, heat_col, GS.t("НАГРЕВ СТВОЛА"))
	var auto_on: bool = int(game.auto_fire) >= 1
	_txt(top + Vector2(0, 128), GS.t("Экипаж стреляет сам [%s]: %s") % [GS.key_label("auto"), GS.t("ДА") if auto_on else GS.t("НЕТ")], 13, NEON if auto_on else Color(0.6, 0.75, 0.7))
	# --- hints, bottom
	var hint := GS.t("W/S — газ/тормоз · A/D — руль · мышь — осмотреться · Пробел — к пулемёту · %s — выйти из машины") % GS.key_label("mfg")
	if mg.seat == "gun":
		hint = GS.t("мышь — прицел · ЛКМ — огонь очередями · ПКМ — зум · Пробел — за руль · %s — выйти из машины") % GS.key_label("mfg")
	if DisplayServer.is_touchscreen_available():
		hint = GS.t("левая половина — руль и газ · правая — обзор · кнопки — пулемёт и огонь")
	_txt(Vector2(40, sz.y - 22), hint, 13, Color(0.75, 1.0, 0.88, 0.85), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)


## An arrow on the screen edge towards `p` when it is off screen, a marker on it when it is not.
func _edge_arrow(cam: Camera3D, p: Vector3, col: Color, label: String, sz: Vector2) -> void:
	var c := sz * 0.5
	var sp := cam.unproject_position(p)
	var inside := not cam.is_position_behind(p) and Rect2(Vector2(60, 60), sz - Vector2(120, 120)).has_point(sp)
	if inside:
		draw_arc(sp, 14.0, 0, TAU, 20, col, 2.0)
		_txt(sp + Vector2(-60, -20), label, 13, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
		return
	var rel: Vector3 = cam.global_transform.basis.inverse() * (p - cam.global_position)
	var dir := Vector2(rel.x, -rel.y)
	if dir.length_squared() < 0.0001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := c - Vector2(80, 80)
	var edge := c + dir * minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var tip := edge + dir * 24.0
	var side := Vector2(-dir.y, dir.x) * 13.0
	draw_colored_polygon(PackedVector2Array([tip, edge - dir * 6.0 + side, edge - dir * 6.0 - side]), col)
	_txt(edge - dir * 36.0 + Vector2(-60, 5), label, 14, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
