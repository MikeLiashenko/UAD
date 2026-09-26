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
			for kind in ["aim9", "aim120"]:
				var ok: bool = dist <= fg.range_of(kind) and int(fg.loaded[kind]) > 0
				lines.append("%s %s" % [GS.t(String(GS.WEAPONS[kind].short)), "✔" if ok else "✖"])
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
	_txt(r, "AIM-9X ×%d" % int(fg.loaded.aim9), 18, HUD if int(fg.loaded.aim9) > 0 else Color(0.5, 0.6, 0.55))
	_txt(r + Vector2(0, 26), "AIM-120 ×%d" % int(fg.loaded.aim120), 18, HUD if int(fg.loaded.aim120) > 0 else Color(0.5, 0.6, 0.55))
	_txt(r + Vector2(0, 52), "M61 %d" % int(fg.rounds), 18, HUD if int(fg.rounds) > 0 else Color(0.5, 0.6, 0.55))
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
	var hint := GS.t("мышь — куда лететь · W/S — тяга · Shift — форсаж · ЛКМ — пушка · ПКМ/E — AIM-9X · Q — AIM-120 · %s — на аэродром") % GS.key_label("fighter")
	if DisplayServer.is_touchscreen_available():
		hint = GS.t("свайп — куда лететь · кнопки — пушка, ракеты, форсаж")
	_txt(Vector2(40, sz.y - 22), hint, 13, Color(HUD.r, HUD.g, HUD.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 80.0)


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
