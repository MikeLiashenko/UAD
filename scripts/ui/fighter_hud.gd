extends Control
## Head-up display of the F-16 sortie (scripts/game/fighter.gd): speed, altitude and throttle on
## the left, stores and fuel on the right, the heading on top; the gun pipper and the aim ring in
## the middle; boxes on the threats, the lock with its launch cues and where the wreckage would
## fall; an edge arrow to a threat off the screen; PULL UP, BINGO and the patrol-area warnings.

const HUD := Color(0.45, 1.0, 0.55)
const AMBER := Color(1.0, 0.75, 0.3)
const RED := Color(1.0, 0.32, 0.26)

var game
var fg


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	visible = fg != null and fg.active and fg.state == "air"
	if visible:
		queue_redraw()


func _txt(p: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(GS.font, p, s, align, width, size, 4, Color(0, 0, 0, 0.6))
	draw_string(GS.font, p, s, align, width, size, col)


func _draw() -> void:
	var sz := size
	var c := sz * 0.5
	var cam: Camera3D = fg.cam
	var t := Time.get_ticks_msec() / 1000.0
	# --- heading on top
	var hdg := int(round(fposmod(rad_to_deg(atan2(fg.dir.x, -fg.dir.z)), 360.0)))
	_txt(Vector2(c.x - 60, 44), "%03d°" % hdg, 22, HUD, HORIZONTAL_ALIGNMENT_CENTER, 120)
	draw_line(Vector2(c.x - 90, 52), Vector2(c.x + 90, 52), Color(HUD.r, HUD.g, HUD.b, 0.4), 1.0)
	# --- the gun pipper: where the rounds go, a second of flight ahead
	var gun_p: Vector3 = fg.pos + fg.dir * 600.0
	if not cam.is_position_behind(gun_p):
		var gp := cam.unproject_position(gun_p)
		draw_arc(gp, 9.0, 0, TAU, 20, HUD, 1.8)
		draw_circle(gp, 1.8, HUD)
		draw_line(gp + Vector2(-22, 0), gp + Vector2(-12, 0), HUD, 1.8)
		draw_line(gp + Vector2(12, 0), gp + Vector2(22, 0), HUD, 1.8)
	# --- the aim ring: where the pilot steers
	var aim_p: Vector3 = cam.global_position + fg.aim * 1500.0
	if not cam.is_position_behind(aim_p):
		draw_arc(cam.unproject_position(aim_p), 15.0, 0, TAU, 28, Color(1, 1, 1, 0.8), 2.0)
	# --- threats, the lock
	var lk = fg.lock
	for e in game.enemies:
		if e.dead or cam.is_position_behind(e.position):
			continue
		var dist: float = fg.pos.distance_to(e.position)
		if dist > 3200.0:
			continue
		var sp := cam.unproject_position(e.position)
		var is_lock: bool = e == lk
		var col := RED if is_lock and fg.locked else (AMBER if is_lock else Color(HUD.r, HUD.g, HUD.b, 0.75))
		if is_lock:
			var r := 22.0 if fg.locked else 30.0 - 8.0 * clampf(fg.lock_t / fg.LOCK_TIME, 0.0, 1.0)
			draw_rect(Rect2(sp - Vector2(r, r), Vector2(r * 2, r * 2)), col, false, 2.2)
			var k := 0
			var lines := [GS.t("ЗАХВАТ") if fg.locked else GS.t("захват…"), "%s · %.1f км" % [GS.t(String(e.def.name)), dist * 0.005]]
			for kind in ([] if float(e.inbound) >= float(e.hp) else ["aim9", "aim120"]):
				var ok: bool = fg.can_hit(e, kind) and int(fg.loaded[kind]) > 0
				lines.append("%s %s" % [GS.t(String(GS.WEAPONS[kind].short)), "✔" if ok else "✖"])
			if float(e.inbound) >= float(e.hp):
				lines.append(GS.t("уже перехвачена"))
			var fall: Dictionary = game.predict_debris(e)
			lines.append(GS.t("обломки: безопасно") if bool(fall.get("safe", true)) else GS.t("обломки: НА ДОМА"))
			for ln in lines:
				var lc := col
				if String(ln).begins_with(GS.t("обломки: НА ДОМА")):
					lc = RED
				_txt(sp + Vector2(r + 8, -r + 12 + k * 16), String(ln), 13, lc)
				k += 1
		else:
			var d := PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(7, 0), sp + Vector2(0, 7), sp + Vector2(-7, 0), sp + Vector2(0, -7)])
			draw_polyline(d, col, 1.5)
			_txt(sp + Vector2(10, 4), "%s %.1f" % [GS.t(String(e.def.abbr)), dist * 0.005], 11, col)
	# the nearest (or locked) threat when it is off the screen
	var show = lk
	if show == null:
		var bd := INF
		for e in game.enemies:
			if not e.dead and GS.eff("aim9", e) > 0.0 and fg.pos.distance_to(e.position) < bd:
				bd = fg.pos.distance_to(e.position)
				show = e
	if show != null and is_instance_valid(show):
		_edge_arrow(cam, show.position, AMBER, "%.1f км" % (fg.pos.distance_to(show.position) * 0.005), sz)
	# the gun's lead point: put the pipper on it and hold the trigger
	if fg.gun_target != null and is_instance_valid(fg.gun_target) and not cam.is_position_behind(fg.gun_lead):
		var lp := cam.unproject_position(fg.gun_lead)
		draw_arc(lp, 13.0, 0, TAU, 24, RED, 2.2)
		draw_line(lp + Vector2(0, -19), lp + Vector2(0, -13), RED, 2.2)
		draw_line(lp + Vector2(0, 13), lp + Vector2(0, 19), RED, 2.2)
	_prompt(c, t)
	# --- left: speed, altitude, throttle
	var l := Vector2(40, c.y - 95)
	_txt(l, GS.t("СКОРОСТЬ"), 12, Color(HUD.r, HUD.g, HUD.b, 0.7))
	_txt(l + Vector2(0, 28), GS.t("%d км/ч") % int(fg.speed * 5.2), 24, HUD)
	_txt(l + Vector2(0, 62), GS.t("ВЫСОТА"), 12, Color(HUD.r, HUD.g, HUD.b, 0.7))
	_txt(l + Vector2(0, 90), GS.t("%d м") % int(fg.pos.y * 5.0), 24, RED if fg.pull_up else HUD)
	draw_rect(Rect2(l + Vector2(0, 108), Vector2(140, 8)), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(l + Vector2(0, 108), Vector2(140 * fg.throttle, 8)), HUD)
	_txt(l + Vector2(0, 134), GS.t("ФОРСАЖ") if fg.burner else GS.t("ТЯГА %d%%") % int(fg.throttle * 100.0), 13, AMBER if fg.burner else HUD)
	# --- right: stores and fuel
	# under the flight data: the right side belongs to the event log
	var r := Vector2(40, c.y + 85)
	var touch := DisplayServer.is_touchscreen_available()
	var dim := Color(0.5, 0.6, 0.55)
	_txt(r, "AIM-9X ×%d" % int(fg.loaded.aim9), 18, HUD if int(fg.loaded.aim9) > 0 else dim)
	_txt(r + Vector2(0, 26), "AIM-120 ×%d" % int(fg.loaded.aim120), 18, HUD if int(fg.loaded.aim120) > 0 else dim)
	_txt(r + Vector2(0, 52), "M61 %d" % int(fg.rounds), 18, HUD if int(fg.rounds) > 0 else dim)
	if not touch:
		_txt(r + Vector2(140, 0), "E", 14, AMBER)
		_txt(r + Vector2(140, 26), "Q", 14, AMBER)
		_txt(r + Vector2(140, 52), GS.t("ЛКМ"), 14, AMBER)
	var fq: float = fg.fuel / fg.FUEL
	var fc := HUD if fq > 0.2 else RED
	_txt(r + Vector2(0, 84), GS.t("ТОПЛИВО"), 12, Color(fc.r, fc.g, fc.b, 0.8))
	draw_rect(Rect2(r + Vector2(0, 92), Vector2(160, 9)), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(r + Vector2(0, 92), Vector2(160 * clampf(fq, 0.0, 1.0), 9)), fc)
	var kills := int(GS.stats.kills) - int(fg.kills_at_start)
	_txt(r + Vector2(0, 126), GS.t("Сбито за вылет: %d") % kills, 14, HUD)
	# --- warnings
	if fg.gcas:
		_txt(Vector2(c.x - 200, c.y + 130), "AUTO-GCAS", 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 400)
	if fg.pull_up and int(t * 4.0) % 2 == 0:
		_txt(Vector2(c.x - 200, c.y + 90), "PULL UP", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, 400)
	elif fq < 0.2 and int(t * 2.0) % 2 == 0:
		_txt(Vector2(c.x - 200, c.y + 90), GS.t("БИНГО — ТОПЛИВО"), 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 400)
	if fg.outside:
		_txt(Vector2(c.x - 300, 90), GS.t("ВЫ ПОКИДАЕТЕ РАЙОН ПАТРУЛИРОВАНИЯ"), 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 600)
	var hint := GS.t("мышь — куда лететь · ЛКМ — пушка · ПКМ или R — ракета · W/S — тяга · Shift — форсаж · F1 — управление · %s — на аэродром") % GS.key_label("fighter")
	if touch:
		hint = GS.t("свайп — куда лететь · ПУШКА — держать · РАКЕТА — пуск · ФОРСАЖ — держать")
	_txt(Vector2(40, sz.y - 22), hint, 13, Color(HUD.r, HUD.g, HUD.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)
	if fg.air_t < 12.0 or Input.is_key_pressed(KEY_F1):
		_controls_card(c, touch)


## What to press now, in big letters under the centre.
func _prompt(c: Vector2, t: float) -> void:
	var touch := DisplayServer.is_touchscreen_available()
	var p := Vector2(c.x - 350, c.y + 180)
	var kind: String = fg.auto_kind()
	if kind != "":
		var s := GS.t("ЦЕЛЬ ДЛЯ %s — ЖМИ «РАКЕТА»") if touch else GS.t("ЦЕЛЬ ДЛЯ %s — ЖМИ ПКМ")
		_txt(p, s % String(GS.WEAPONS[kind].short), 22, RED if int(t * 3.0) % 2 == 0 else AMBER, HORIZONTAL_ALIGNMENT_CENTER, 700)
	elif fg.gun_target != null and int(fg.rounds) > 0:
		_txt(p, GS.t("В ПРИЦЕЛЕ — ДЕРЖИ «ПУШКА»") if touch else GS.t("В ПРИЦЕЛЕ — ДЕРЖИ ЛКМ"), 22, RED, HORIZONTAL_ALIGNMENT_CENTER, 700)
	elif fg.lock == null or not is_instance_valid(fg.lock):
		_txt(p, GS.t("Разверни нос к цели — по жёлтой стрелке"), 16, Color(HUD.r, HUD.g, HUD.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 700)
	elif float(fg.lock.inbound) >= float(fg.lock.hp):
		_txt(p, GS.t("По этой цели уже летят ракеты — ищи следующую"), 18, Color(0.5, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 700)
	else:
		# a threat ahead, but too far for the missiles on the rails (or they are gone)
		var k := "aim120" if int(fg.loaded.aim120) > 0 else ("aim9" if int(fg.loaded.aim9) > 0 else "")
		var s := GS.t("Ракеты кончились — сближайся для пушки") if k == "" else GS.t("Сближайся: %s бьёт с %.1f км") % [String(GS.WEAPONS[k].short), fg.range_of(k) * 0.005]
		_txt(p, s, 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 700)


## The controls, on the screen for the first seconds of a sortie (and while F1 is held).
func _controls_card(c: Vector2, touch: bool) -> void:
	var a := clampf(12.0 - fg.air_t, 0.0, 1.0) if not Input.is_key_pressed(KEY_F1) else 1.0
	var lines: Array
	if touch:
		lines = [
			[GS.t("Свайп по экрану"), GS.t("куда лететь (белое кольцо)")],
			[GS.t("ПУШКА (держать)"), GS.t("очередь; красный круг — куда целиться")],
			[GS.t("🚀 РАКЕТА"), GS.t("пуск по цели перед носом, тип выберется сам")],
			[GS.t("ФОРСАЖ (держать)"), GS.t("быстрее, но жжёт топливо")],
			[GS.t("НА АЭРОДРОМ"), GS.t("закончить вылет")],
		]
	else:
		lines = [
			[GS.t("Мышь"), GS.t("куда лететь (белое кольцо)")],
			[GS.t("ЛКМ (держать)"), GS.t("пушка; красный круг — куда целиться")],
			[GS.t("ПКМ или R"), GS.t("ракета по цели перед носом, тип выберется сам")],
			["E / Q", GS.t("AIM-9X (до 4,5 км) / AIM-120 (до 11 км)")],
			["W / S · Shift", GS.t("тяга · форсаж (жжёт топливо)")],
			[GS.key_label("fighter"), GS.t("на аэродром")],
		]
	var w := 620.0
	var h := 50.0 + lines.size() * 28.0
	var box := Rect2(Vector2(c.x - w * 0.5, 80), Vector2(w, h))
	draw_rect(box, Color(0.02, 0.08, 0.05, 0.78 * a))
	draw_rect(box, Color(HUD.r, HUD.g, HUD.b, 0.7 * a), false, 1.5)
	_txt(box.position + Vector2(0, 30), GS.t("УПРАВЛЕНИЕ F-16"), 18, Color(AMBER.r, AMBER.g, AMBER.b, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	for i in lines.size():
		var y := box.position.y + 62 + i * 28
		_txt(Vector2(box.position.x + 20, y), String(lines[i][0]), 16, Color(AMBER.r, AMBER.g, AMBER.b, a), HORIZONTAL_ALIGNMENT_RIGHT, 190)
		_txt(Vector2(box.position.x + 225, y), String(lines[i][1]), 16, Color(1, 1, 1, a))


func _edge_arrow(cam: Camera3D, p: Vector3, col: Color, label: String, sz: Vector2) -> void:
	var c := sz * 0.5
	var sp := cam.unproject_position(p)
	if not cam.is_position_behind(p) and Rect2(Vector2(60, 60), sz - Vector2(120, 120)).has_point(sp):
		return
	var rel: Vector3 = cam.global_transform.basis.inverse() * (p - cam.global_position)
	var dir := Vector2(rel.x, -rel.y)
	if dir.length_squared() < 0.0001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := c - Vector2(90, 90)
	var edge := c + dir * minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var tip := edge + dir * 24.0
	var side := Vector2(-dir.y, dir.x) * 13.0
	draw_colored_polygon(PackedVector2Array([tip, edge - dir * 6.0 + side, edge - dir * 6.0 - side]), col)
	_txt(edge - dir * 38.0 + Vector2(-60, 5), label, 14, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
