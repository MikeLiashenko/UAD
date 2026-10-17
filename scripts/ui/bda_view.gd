extends Control
## "Objective control": the footage of our strikes as the staff gets it — a white-hot thermal
## picture from a drone or a satellite above the target, a few seconds for each strike that has
## just landed (scripts/game/strikes.gd, at dusk; a hunt the moment it hits). The target is drawn
## by its kind — an airfield with bombers, ships at anchor, launchers under the trees, a plant —
## from the site's id, so the same target always looks the same; then the warhead arrives: a hit
## blooms on the target and burns on, a miss bursts beside it or the site's air defence takes it
## down in the air. Nothing here takes a click or a finger: it only plays and goes.

const Strikes = preload("res://scripts/game/strikes.gd")

## Seconds of footage per strike, and how many strikes of one dusk get their footage.
const CLIP := 3.6
const MAX_CLIPS := 4

var _queue: Array = []
var _cur := {}
var _t := 0.0
var _more := 0
## The picture of the current target: [kind, Rect2 or Vector2, angle] in 0..1 frame space.
var _shapes: Array = []
var _trees: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


## Plays the footage of these results ({site, name, w, hit, …}); more than MAX_CLIPS at once are
## summed up in the caption of the last one.
func play(results: Array) -> void:
	for r in results:
		if _queue.size() + (0 if _cur.is_empty() else 1) < MAX_CLIPS:
			_queue.append(r)
		else:
			_more += 1
	if _cur.is_empty():
		_next()


func playing() -> bool:
	return not _cur.is_empty()


func _next() -> void:
	if _queue.is_empty():
		_cur = {}
		_more = 0
		visible = false
		return
	_cur = _queue.pop_front()
	_t = 0.0
	visible = true
	_build_scene(String(_cur.site))


func _process(delta: float) -> void:
	if _cur.is_empty():
		return
	# real seconds: the footage plays the same on a fast clock
	_t += delta / maxf(Engine.time_scale, 0.001)
	if _t >= CLIP:
		_next()
	queue_redraw()


## Lays out the target: what stands there and where, the same every time for one site.
func _build_scene(id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	_shapes.clear()
	_trees = PackedVector2Array()
	var icon := String(Strikes.KINDS.get(id, {}).get("icon", "missile"))
	match icon:
		"plane":
			# a runway across the frame, the bombers on their stands beside it
			_shapes.append(["strip", Rect2(0.05, 0.42, 0.9, 0.09), 0.0])
			_shapes.append(["strip", Rect2(0.2, 0.6, 0.6, 0.05), 0.0])
			for i in 5:
				_shapes.append(["plane", Vector2(0.22 + i * 0.13, 0.69 + rng.randf_range(-0.02, 0.02)), 0.0])
			_shapes.append(["block", Rect2(0.12, 0.18, 0.16, 0.1), 0.0])
		"ship":
			# water: no trees; the ships at anchor
			_shapes.append(["water", Rect2(0, 0, 1, 1), 0.0])
			for i in 3:
				_shapes.append(["ship", Vector2(0.3 + i * 0.2, 0.45 + rng.randf_range(-0.12, 0.12)), rng.randf_range(-0.4, 0.4)])
		"factory":
			for i in 4:
				_shapes.append(["block", Rect2(0.18 + (i % 2) * 0.32, 0.25 + (i / 2) * 0.28, rng.randf_range(0.18, 0.26), rng.randf_range(0.12, 0.18)), 0.0])
			for i in 3:
				_shapes.append(["tank", Vector2(0.76 + rng.randf_range(-0.03, 0.03), 0.3 + i * 0.16), 0.0])
		_:
			# launchers under the trees at the edge of a field
			for i in 4:
				_shapes.append(["truck", Vector2(0.32 + i * 0.12 + rng.randf_range(-0.02, 0.02), 0.5 + rng.randf_range(-0.08, 0.08)), rng.randf_range(-0.5, 0.5)])
	if icon != "ship":
		for i in 70:
			var p := Vector2(rng.randf(), rng.randf())
			if icon == "plane" and p.y > 0.38 and p.y < 0.82:
				continue
			_trees.append(p)


func _draw() -> void:
	if _cur.is_empty():
		return
	var sz := size
	var hit := bool(_cur.get("hit", false))
	var fade := clampf(_t / 0.25, 0.0, 1.0) * clampf((CLIP - _t) / 0.3, 0.0, 1.0)
	var a := fade
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.03, 0.92 * a))
	# the camera creeps in on the target
	var zoom := 1.0 + 0.12 * clampf(_t / CLIP, 0.0, 1.0)
	var frame := Rect2(Vector2(6, 6), sz - Vector2(12, 12))
	var c := frame.get_center()
	var to_px := func(p: Vector2) -> Vector2: return c + (p - Vector2(0.5, 0.5)) * frame.size * zoom
	var grain := RandomNumberGenerator.new()
	grain.seed = int(_t * 24.0) * 7919
	# ground or water: grey, cooler than anything men have put there
	var ground := Color(0.24, 0.25, 0.24, a)
	draw_rect(frame, ground)
	for i in 160:
		var gp := frame.position + Vector2(grain.randf(), grain.randf()) * frame.size
		draw_rect(Rect2(gp, Vector2(2, 2)), Color(0.4, 0.4, 0.4, 0.18 * a))
	for t in _trees:
		var tp: Vector2 = to_px.call(t)
		if frame.has_point(tp):
			draw_circle(tp, 4.0 * zoom, Color(0.17, 0.18, 0.17, a))
	var impact := 1.15
	var after := _t - impact
	for s in _shapes:
		_shape(s, to_px, zoom, a, hit and after > 0.0)
	# the warhead: a white-hot point falling in from the corner
	var aim: Vector2 = to_px.call(Vector2(0.5, 0.5))
	var miss_at: Vector2 = to_px.call(Vector2(0.5 + 0.28, 0.5 - 0.22))
	var downed := not hit and int(hash(String(_cur.site) + String(_cur.w))) % 2 == 0
	if after < 0.0:
		var k := clampf(_t / impact, 0.0, 1.0)
		var from: Vector2 = frame.position + Vector2(frame.size.x * 0.95, frame.size.y * 0.05)
		var dst := aim if hit else (from.lerp(miss_at, 0.75) if downed else miss_at)
		var head := from.lerp(dst, k * k)
		draw_line(from.lerp(dst, maxf(k * k - 0.18, 0.0)), head, Color(1, 1, 1, 0.35 * a), 2.0)
		draw_circle(head, 3.0, Color(1, 1, 1, a))
	else:
		var at := aim if hit else (frame.position + Vector2(frame.size.x * 0.95, frame.size.y * 0.05)).lerp(miss_at, 0.75) if downed else miss_at
		var bloom := clampf(after / 0.35, 0.0, 1.0)
		var cool := clampf((after - 0.3) / 1.6, 0.0, 1.0)
		var big := 36.0 if hit else 20.0
		draw_circle(at, big * (0.4 + bloom) * zoom, Color(1, 1, 1, (1.0 - cool * 0.75) * a))
		draw_circle(at, big * 1.7 * bloom * zoom, Color(0.85, 0.85, 0.85, 0.35 * (1.0 - cool) * a))
		if hit:
			# what was there burns on: hot spots over the target, a plume drifting off
			var fire := RandomNumberGenerator.new()
			fire.seed = hash(String(_cur.site))
			for i in 7:
				var fp: Vector2 = at + Vector2(fire.randf_range(-60, 60), fire.randf_range(-36, 36)) * zoom
				var flick := 0.75 + 0.25 * sin(_t * 17.0 + i)
				draw_circle(fp, fire.randf_range(5, 11) * zoom * flick * minf(bloom * 2.0, 1.0), Color(1, 1, 1, 0.85 * a))
			for i in 6:
				var sp: Vector2 = at + Vector2(i * 14.0 + after * 26.0, -i * 9.0 - after * 18.0) * zoom
				draw_circle(sp, (14.0 + i * 5.0) * zoom * cool, Color(0.62, 0.62, 0.62, 0.22 * a))
	# the camera's own marks
	var hud := Color(0.85, 1.0, 0.9, 0.9 * a)
	draw_line(aim + Vector2(-26, 0), aim + Vector2(-9, 0), hud, 1.5)
	draw_line(aim + Vector2(9, 0), aim + Vector2(26, 0), hud, 1.5)
	draw_line(aim + Vector2(0, -26), aim + Vector2(0, -9), hud, 1.5)
	draw_line(aim + Vector2(0, 9), aim + Vector2(0, 26), hud, 1.5)
	for q in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var corner: Vector2 = frame.position + q * frame.size + (Vector2(1, 1) - q * 2.0) * 8.0
		var dx := 16.0 if q.x == 0 else -16.0
		var dy := 16.0 if q.y == 0 else -16.0
		draw_line(corner, corner + Vector2(dx, 0), hud, 2.0)
		draw_line(corner, corner + Vector2(0, dy), hud, 2.0)
	# scan lines
	for y in range(int(frame.position.y), int(frame.end.y), 3):
		draw_line(Vector2(frame.position.x, y), Vector2(frame.end.x, y), Color(0, 0, 0, 0.12 * a), 1.0)
	var f := GS.font
	_txt(f, frame.position + Vector2(12, 20), GS.t("ОБЪЕКТИВНЫЙ КОНТРОЛЬ"), 12, hud)
	_txt(f, Vector2(frame.end.x - 74, frame.position.y + 20), "WHT +%04.1f" % _t, 11, hud)
	var what := "%s → %s" % [GS.t(String(Strikes.WEAPONS.get(String(_cur.w), {}).get("short", ""))), GS.t(String(Strikes.KINDS.get(String(_cur.site), {}).get("short", _cur.get("name", ""))))]
	_txt(f, frame.position + Vector2(12, 38), what, 13, hud, HORIZONTAL_ALIGNMENT_LEFT, frame.size.x - 24)
	if after > 0.25:
		var verdict := GS.t("ПОРАЖЕНИЕ") if hit else (GS.t("СБИТ ПВО ПРОТИВНИКА") if downed else GS.t("ПРОМАХ"))
		var vc := Color(0.55, 1.0, 0.6, a) if hit else Color(1.0, 0.65, 0.35, a)
		_txt(f, Vector2(frame.position.x, frame.end.y - 14), verdict, 20, vc, HORIZONTAL_ALIGNMENT_CENTER, frame.size.x)
	if _more > 0 and _queue.is_empty():
		_txt(f, Vector2(frame.end.x - 150, frame.end.y - 40), GS.t("и ещё ударов: %d") % _more, 12, hud, HORIZONTAL_ALIGNMENT_RIGHT, 140)
	draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(0.4, 1.0, 0.75, 0.55 * a), false, 2.0)


## One thing on the ground, hot (white) where engines, fuel or men are; a struck one glows.
func _shape(s: Array, to_px: Callable, zoom: float, a: float, struck: bool) -> void:
	var hot := Color(0.92, 0.92, 0.9, a) if not struck else Color(1, 1, 1, a)
	var warm := Color(0.55, 0.56, 0.55, a)
	match String(s[0]):
		"water":
			var r: Rect2 = s[1]
			var p0: Vector2 = to_px.call(r.position)
			var p1: Vector2 = to_px.call(r.end)
			draw_rect(Rect2(p0, p1 - p0), Color(0.1, 0.11, 0.12, a))
		"strip", "block":
			var r: Rect2 = s[1]
			var p0: Vector2 = to_px.call(r.position)
			var p1: Vector2 = to_px.call(r.end)
			draw_rect(Rect2(p0, p1 - p0), warm if String(s[0]) == "strip" else Color(0.62, 0.62, 0.6, a))
		"plane":
			var p: Vector2 = to_px.call(s[1])
			var k := 10.0 * zoom
			draw_line(p + Vector2(0, -k), p + Vector2(0, k), hot, 3.0)
			draw_line(p + Vector2(-k, -k * 0.1), p + Vector2(k, -k * 0.1), hot, 3.0)
			draw_line(p + Vector2(-k * 0.4, k * 0.8), p + Vector2(k * 0.4, k * 0.8), hot, 2.0)
		"ship":
			var p: Vector2 = to_px.call(s[1])
			var ang := float(s[2])
			var d := Vector2(cos(ang), sin(ang)) * 26.0 * zoom
			var n := Vector2(-d.y, d.x).normalized() * 6.0 * zoom
			draw_colored_polygon(PackedVector2Array([p - d + n, p + d * 0.8 + n, p + d, p + d * 0.8 - n, p - d - n]), Color(0.7, 0.7, 0.68, a))
			draw_circle(p - d * 0.2, 4.0 * zoom, hot)
		"tank":
			draw_circle(to_px.call(s[1]), 13.0 * zoom, Color(0.66, 0.66, 0.64, a))
			draw_circle(to_px.call(s[1]), 6.0 * zoom, warm)
		"truck":
			var p: Vector2 = to_px.call(s[1])
			var ang := float(s[2])
			var d := Vector2(cos(ang), sin(ang)) * 14.0 * zoom
			var n := Vector2(-d.y, d.x).normalized() * 4.0 * zoom
			draw_colored_polygon(PackedVector2Array([p - d + n, p + d + n, p + d - n, p - d - n]), Color(0.68, 0.68, 0.66, a))
			draw_circle(p + d * 0.75, 3.5 * zoom, hot)


func _txt(f: Font, p: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(f, p, s, align, width, sz, 4, Color(0, 0, 0, 0.75 * col.a))
	draw_string(f, p, s, align, width, sz, col)
