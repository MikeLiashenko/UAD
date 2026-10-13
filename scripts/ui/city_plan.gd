extends Control
## A drawn city (CustomCity data) as a flat plan, north up: water, woods, districts, roads,
## railways and objects. The city editor draws on it, the attack screen of a server aims on it,
## the server card shows it small. The plan is moved with the right mouse button or two fingers
## and scaled with the wheel or a pinch (`movable`); a tap or a left drag goes to whoever listens.

const CustomCity = preload("res://scripts/world/custom_city.gd")

## A tap (left click or one finger, without dragging) at a point of the city, metres.
signal tapped(world: Vector2)
## A left drag: phase 0 = picked up at `world`, 1 = moved to it, 2 = let go there.
signal dragged(world: Vector2, phase: int)

const FIELD := Color(0.13, 0.19, 0.12)
const WATER := Color(0.12, 0.33, 0.62)
const FOREST := Color(0.07, 0.3, 0.13)
const ROAD := Color(0.86, 0.84, 0.7)
const RAIL := Color(0.75, 0.6, 0.5)

var data := {}
## Metres of the city at the middle of the control, and pixels per metre.
var center := Vector2.ZERO
var zoom := 0.03
var movable := true
## Names of districts and objects are drawn.
var names := true
## Drawn over the plan by its owner: called with this control (use at() and the draw_* calls).
var overlay := Callable()

var _left := false
var _moved := false
var _press := Vector2.ZERO
var _pan := false
var _touches := {}
var _pinch := 0.0
var _fitted := false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void:
		if not _fitted:
			fit())


func set_data(d: Dictionary) -> void:
	data = d
	_fitted = false
	fit()
	queue_redraw()


func half() -> float:
	return float(data.get("size", 7000.0))


## The whole square in view.
func fit() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	_fitted = true
	center = Vector2.ZERO
	zoom = minf(size.x, size.y) / (half() * 2.08)
	queue_redraw()


## City metres → pixels of this control.
func at(world: Vector2) -> Vector2:
	return size * 0.5 + (world - center) * zoom


func world_at(screen: Vector2) -> Vector2:
	return center + (screen - size * 0.5) / maxf(zoom, 0.00001)


func zoom_by(f: float, about := Vector2.INF) -> void:
	if about == Vector2.INF:
		about = size * 0.5
	var w := world_at(about)
	var fit_zoom := minf(size.x, size.y) / (half() * 2.08)
	zoom = clampf(zoom * f, fit_zoom * 0.7, 0.6)
	center = w - (about - size * 0.5) / zoom
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	var h := half()
	center = center.clamp(Vector2(-h, -h), Vector2(h, h))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if movable and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15, mb.position)
		elif movable and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = mb.pressed and movable
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left = true
				_moved = false
				_press = mb.position
			elif _left:
				_left = false
				if _touches.size() >= 2:
					return
				if _moved:
					dragged.emit(world_at(mb.position), 2)
				else:
					tapped.emit(world_at(mb.position))
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan:
			center -= mm.relative / zoom
			_clamp_center()
			queue_redraw()
		elif _left and _touches.size() < 2:
			if not _moved and mm.position.distance_to(_press) > 8.0:
				_moved = true
				dragged.emit(world_at(_press), 0)
			if _moved:
				dragged.emit(world_at(mm.position), 1)
	elif event is InputEventMagnifyGesture and movable:
		zoom_by((event as InputEventMagnifyGesture).factor)


## Two fingers move and pinch the plan (the first one alone is the emulated mouse above).
func _input(event: InputEvent) -> void:
	if not movable or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := st.position - global_position
		if st.pressed:
			if Rect2(Vector2.ZERO, size).has_point(local):
				_touches[st.index] = local
		else:
			_touches.erase(st.index)
		_pinch = 0.0
		if _touches.size() >= 2 and _left:
			# the second finger came down: this is not a tap and not a drag of an item any more
			if _moved:
				dragged.emit(world_at(_press), 2)
			_left = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		_touches[sd.index] = sd.position - global_position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[1]
			var d := a.distance_to(b)
			center -= sd.relative * 0.5 / zoom
			if _pinch > 0.0 and d > 1.0:
				zoom_by(d / _pinch, (a + b) * 0.5)
			_pinch = d
			_clamp_center()
			queue_redraw()


# --- Drawing -------------------------------------------------------------------------------------
func _ellipse(e: Array, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rot := deg_to_rad(float(e[4]) if e.size() > 4 else 0.0)
	var c := Vector2(float(e[0]), float(e[1]))
	for i in n:
		var a := TAU * i / n
		pts.append(at(c + Vector2(cos(a) * float(e[2]), sin(a) * float(e[3])).rotated(rot)))
	return pts


## A line through control points [x, z(, half width)], smoothed the way the game builds it:
## [pixels of this control, half widths in metres].
func _curve(pts: Array) -> Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		for p in pts:
			out.append(at(Vector2(float(p[0]), float(p[1]))))
		return [out, PackedFloat32Array()]
	var s: Array = CustomCity.smooth(pts, maxf(6.0 / maxf(zoom, 0.00001), 40.0))
	for q in (s[0] as PackedVector2Array):
		out.append(at(q))
	return [out, s[1]]


func text(p: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := 240.0) -> void:
	var q := p - Vector2(width * 0.5, 0) if align == HORIZONTAL_ALIGNMENT_CENTER else p
	draw_string_outline(GS.font, q, s, align, width, sz, 4, Color(0, 0, 0, 0.8))
	draw_string(GS.font, q, s, align, width, sz, col)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.05))
	var h := half()
	var sq := Rect2(at(Vector2(-h, -h)), Vector2.ONE * h * 2.0 * zoom)
	draw_rect(sq, FIELD)
	# a kilometre grid, every fifth line stronger
	var km := 1000.0
	var n := int(h / km)
	if km * zoom >= 6.0:
		for i in range(-n, n + 1):
			var col := Color(0.4, 1.0, 0.7, 0.13 if i % 5 == 0 else 0.05)
			draw_line(at(Vector2(i * km, -h)), at(Vector2(i * km, h)), col, 1.0)
			draw_line(at(Vector2(-h, i * km)), at(Vector2(h, i * km)), col, 1.0)
	for f in data.get("forests", []):
		draw_colored_polygon(_ellipse(f), FOREST)
	for d in data.get("districts", []):
		var spec := CustomCity.district_spec(String(d[4]))
		var c: Color = spec[3]
		var p := at(Vector2(float(d[1]), float(d[2])))
		var r := float(d[5]) * 1.15 * zoom
		draw_circle(p, r, Color(c.r, c.g, c.b, 0.32))
		draw_arc(p, r, 0, TAU, 40, Color(c.r, c.g, c.b, 0.7), 1.2)
		# the street grid's direction
		var ga := deg_to_rad(float(d[3]))
		for k: float in [-0.5, 0.0, 0.5]:
			var off := Vector2(-sin(ga), cos(ga)) * r * k
			var along := Vector2(cos(ga), sin(ga)) * r * sqrt(1.0 - k * k) * 0.9
			draw_line(p + off - along, p + off + along, Color(c.r, c.g, c.b, 0.28), 1.0)
	for l in data.get("lakes", []):
		draw_colored_polygon(_ellipse(l), WATER)
	for r in data.get("rivers", []):
		var cv := _curve(r.p)
		var pl: PackedVector2Array = cv[0]
		var ws: PackedFloat32Array = cv[1]
		for i in pl.size() - 1:
			var w := maxf((ws[i] + ws[i + 1]) * zoom, 2.0)
			draw_line(pl[i], pl[i + 1], WATER, w)
			draw_circle(pl[i + 1], w * 0.5, WATER)
		if not pl.is_empty() and not ws.is_empty():
			draw_circle(pl[0], maxf(ws[0] * zoom, 1.0), WATER)
	for r in data.get("rails", []):
		var pl: PackedVector2Array = _curve(r.p)[0]
		if pl.size() >= 2:
			draw_polyline(pl, Color(0.1, 0.1, 0.1, 0.9), 4.0)
			draw_polyline(pl, RAIL, 1.5)
	for r in data.get("roads", []):
		var pl: PackedVector2Array = _curve(r.p)[0]
		if pl.size() >= 2:
			draw_polyline(pl, Color(0.1, 0.1, 0.1, 0.9), maxf(24.0 * zoom, 4.5))
			draw_polyline(pl, ROAD, maxf(18.0 * zoom, 2.2))
	draw_rect(sq, Color(0.4, 1.0, 0.7, 0.5), false, 1.5)
	for o in data.get("objects", []):
		var p := at(Vector2(float(o.x), float(o.z)))
		draw_object(p, String(o.k), Color(1.0, 0.55, 0.4))
		if names:
			var oname := String(o.n) if String(o.n) != "" else GS.t(CustomCity.object_name(String(o.k)))
			text(p + Vector2(0, 24), oname, 11, Color(1.0, 0.75, 0.6))
	if names:
		for d in data.get("districts", []):
			text(at(Vector2(float(d[1]), float(d[2]))) + Vector2(0, 4), String(d[0]), 12, Color(0.9, 1.0, 0.95, 0.9))
	if overlay.is_valid():
		overlay.call(self)


## The sign of an object kind, the same in the palette, on the plan and on the attack screen.
func draw_object(p: Vector2, kind: String, col: Color) -> void:
	draw_circle(p, 11.0, Color(0, 0, 0, 0.6))
	draw_arc(p, 11.0, 0, TAU, 20, col, 1.5)
	match kind:
		"tpp":
			draw_colored_polygon(PackedVector2Array([p + Vector2(1, -8), p + Vector2(-4, 1), p + Vector2(0, 1), p + Vector2(-2, 8), p + Vector2(5, -2), p + Vector2(1, -2)]), col)
		"plant":
			draw_rect(Rect2(p + Vector2(-7, 0), Vector2(14, 6)), col)
			draw_rect(Rect2(p + Vector2(2, -7), Vector2(3, 8)), col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(-3, -4), p + Vector2(-3, 0)]), col)
		"oil":
			draw_circle(p + Vector2(-3, 1), 4.0, col)
			draw_circle(p + Vector2(4, -2), 3.0, col)
		"rail":
			draw_line(p + Vector2(-7, -3), p + Vector2(7, -3), col, 2.0)
			draw_line(p + Vector2(-7, 3), p + Vector2(7, 3), col, 2.0)
			for k in [-5.0, 0.0, 5.0]:
				draw_line(p + Vector2(k, -5), p + Vector2(k, 5), col, 1.5)
		"airport":
			draw_line(p + Vector2(0, -8), p + Vector2(0, 8), col, 2.5)
			draw_line(p + Vector2(-8, -1), p + Vector2(8, -1), col, 2.5)
			draw_line(p + Vector2(-4, 6), p + Vector2(4, 6), col, 2.0)
		"port":
			draw_arc(p + Vector2(0, 1), 5.0, 0.2, PI - 0.2, 10, col, 2.0)
			draw_line(p + Vector2(0, -7), p + Vector2(0, 6), col, 2.0)
			draw_line(p + Vector2(-3, -4), p + Vector2(3, -4), col, 2.0)
		"tv":
			draw_line(p + Vector2(0, -8), p + Vector2(-4, 7), col, 1.6)
			draw_line(p + Vector2(0, -8), p + Vector2(4, 7), col, 1.6)
			draw_line(p + Vector2(-2, 0), p + Vector2(2, 0), col, 1.6)
		"stadium":
			draw_arc(p, 6.0, 0, TAU, 16, col, 2.5)
		"tower":
			draw_rect(Rect2(p + Vector2(-3, -8), Vector2(6, 16)), col)
		_:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -3), p + Vector2(0, -8), p + Vector2(8, -3)]), col)
			for k in [-5.0, 0.0, 5.0]:
				draw_line(p + Vector2(k, -2), p + Vector2(k, 6), col, 2.0)
			draw_line(p + Vector2(-8, 7), p + Vector2(8, 7), col, 2.0)
