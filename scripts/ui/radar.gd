extends Control
## Classic round air-defense radar scope, centered on the player's base.
## Blips are refreshed when the rotating sweep passes over a target and then fade out.

const RANGE_WORLD := 1500.0
const SWEEP_PERIOD := 2.4

var game
var _sweep := 0.0
var _blips := {}


func _ready() -> void:
	custom_minimum_size = Vector2(250, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var prev := _sweep
	_sweep = fmod(_sweep + delta * TAU / SWEEP_PERIOD, TAU)
	var base: Vector3 = GS.base_pos
	var alive := {}
	for e in game.enemies:
		var rel := Vector2(e.position.x - base.x, e.position.z - base.z)
		var id: int = e.get_instance_id()
		alive[id] = true
		var a := fposmod(rel.angle(), TAU)
		var crossed := (a > prev and a <= _sweep) if _sweep >= prev else (a > prev or a <= _sweep)
		# ballistic threats are tracked continuously by the fire-control radar
		if crossed or e.type == "ballistic" or not _blips.has(id):
			_blips[id] = {"pos": rel, "age": 0.0, "type": e.type, "variant": e.variant, "locked": game.locked == e}
	for id in _blips.keys():
		var b: Dictionary = _blips[id]
		b.age = float(b.age) + delta
		if not alive.has(id) and float(b.age) > 1.5:
			_blips.erase(id)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var neon := Color(0.2, 1.0, 0.55)
	draw_circle(c, r + 3.0, Color(0.0, 0.0, 0.0, 0.75))
	draw_circle(c, r, Color(0.0, 0.09, 0.05, 0.92))
	# rivers and the coast for orientation
	for line in game.map.radar_lines:
		var river := PackedVector2Array()
		for p in line:
			var v: Vector2 = (p - Vector2(GS.base_pos.x, GS.base_pos.z)) / RANGE_WORLD * r
			if v.length() < r:
				river.append(c + v)
			elif river.size() > 1:
				draw_polyline(river, Color(0.25, 0.6, 1.0, 0.35), 3.0)
				river = PackedVector2Array()
			else:
				river = PackedVector2Array()
		if river.size() > 1:
			draw_polyline(river, Color(0.25, 0.6, 1.0, 0.35), 3.0)
	# range rings (500 m step in world units) and crosshair
	for k in [0.25, 0.5, 0.75, 1.0]:
		draw_arc(c, r * k, 0, TAU, 64, Color(neon.r, neon.g, neon.b, 0.22), 1.0)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(neon.r, neon.g, neon.b, 0.15), 1.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(neon.r, neon.g, neon.b, 0.15), 1.0)
	# weapon range of the selected system
	var w = game.weapons.get(game.selected_weapon)
	if w != null:
		var wr: float = minf(w.effective_range() / RANGE_WORLD, 1.0) * r
		draw_arc(c, wr, 0, TAU, 64, Color(1.0, 0.8, 0.3, 0.45), 1.5)
	# sweep wedge with a fading tail
	var steps := 28
	var tail := 0.9
	for i in steps:
		var a0 := _sweep - tail * float(i) / steps
		var a1 := _sweep - tail * float(i + 1) / steps
		var alpha := 0.35 * (1.0 - float(i) / steps)
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r]), Color(neon.r, neon.g, neon.b, alpha))
	draw_line(c, c + Vector2.from_angle(_sweep) * r, Color(0.6, 1.0, 0.8, 0.9), 2.0)
	# camera view direction
	var yaw: float = game.rig.yaw
	var look := Vector2(-sin(yaw), -cos(yaw))
	draw_line(c, c + look * r * 0.22, Color(1, 1, 1, 0.5), 1.5)
	# blips
	for id in _blips:
		var b: Dictionary = _blips[id]
		var v: Vector2 = b.pos / RANGE_WORLD * r
		if v.length() > r - 3.0:
			v = v.normalized() * (r - 3.0)
		var fade := clampf(1.0 - float(b.age) / SWEEP_PERIOD, 0.15, 1.0)
		var col: Color = GS.ENEMIES[String(b.get("variant", b.type))].color
		col.a = fade
		var p := c + v
		match String(b.type):
			"ballistic":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 4), p + Vector2(-5, 4)]), col)
			"cruise":
				draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), col)
			"scout":
				draw_arc(p, 4.0, 0, TAU, 12, col, 2.0)
			_:
				draw_circle(p, 3.2, col)
		if b.locked:
			draw_arc(p, 9.0, 0, TAU, 16, Color(1, 0.3, 0.3, 0.9), 1.5)
	# own interceptor drones: tracked continuously over the data link
	for d in game.drones:
		if not is_instance_valid(d):
			continue
		var v: Vector2 = Vector2(d.position.x - GS.base_pos.x, d.position.z - GS.base_pos.z) / RANGE_WORLD * r
		if v.length() > r - 3.0:
			v = v.normalized() * (r - 3.0)
		var p := c + v
		var dc := Color(0.4, 1.0, 0.85, 0.95 if d.fpv else 0.7)
		var a: float = atan2(d.vel.z, d.vel.x)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2.from_angle(a) * 6.0,
			p + Vector2.from_angle(a + 2.5) * 4.0,
			p + Vector2.from_angle(a - 2.5) * 4.0]), dc)
		if d.fpv:
			draw_arc(p, 9.0, 0, TAU, 16, Color(0.4, 1.0, 0.85, 0.9), 1.5)
	# friends' bases in a multiplayer session: a diamond in their colour with their initial
	for code in Net.others():
		var pl: Dictionary = Net.players[code]
		if not bool(pl.has_base):
			continue
		var bv: Vector2 = Vector2(pl.base.x - GS.base_pos.x, pl.base.z - GS.base_pos.z) / RANGE_WORLD * r
		var edge := bv.length() > r - 6.0
		if edge:
			bv = bv.normalized() * (r - 6.0)
		var bp := c + bv
		var pc: Color = pl.color
		pc.a = 0.6 if edge else 0.95
		draw_colored_polygon(PackedVector2Array([bp + Vector2(0, -6), bp + Vector2(6, 0), bp + Vector2(0, 6), bp + Vector2(-6, 0)]), pc)
		draw_string(GS.font, bp + Vector2(8, 5), String(pl.nick).substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, pc)
	# base marker and bezel
	draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, 0.9))
	draw_arc(c, r, 0, TAU, 96, Color(neon.r, neon.g, neon.b, 0.9), 2.5)
	var f: Font = GS.font
	draw_string(f, c + Vector2(-5, -r + 16), GS.t("С"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(neon.r, neon.g, neon.b, 0.9))
	draw_string(f, c + Vector2(-r + 6, r - 4), GS.t("%.1f км") % (RANGE_WORLD * 0.005), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(neon.r, neon.g, neon.b, 0.7))
