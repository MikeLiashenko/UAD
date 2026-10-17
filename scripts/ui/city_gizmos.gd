extends Node3D
## The drawing of the city editor laid over the 3D city (scripts/ui/city_editor.gd): the rings of
## the districts, the lines of rivers, roads and railways with their points, the outlines of
## lakes and woods, the marks of the objects, the line being drawn and what is selected. The
## built city under it may be a step behind the drawing — a district just placed is a ring on an
## empty field until the city is built again — so the marks are always what the data says.
##
## Everything is flat ribbons a little above the ground, drawn over the buildings (no depth
## test) and as wide as a few pixels at the camera's distance: update() rebuilds them when the
## drawing changes or the camera has come closer or gone further by a quarter.

const CustomCity = preload("res://scripts/world/custom_city.gd")

const Y := 3.0
const WATER := Color(0.35, 0.7, 1.0, 0.9)
const FOREST := Color(0.3, 0.95, 0.45, 0.85)
const ROAD := Color(1.0, 0.95, 0.75, 0.9)
const RAIL := Color(0.95, 0.7, 0.5, 0.9)
const OBJECT := Color(1.0, 0.55, 0.4, 0.95)
const DRAFT := Color(1.0, 0.9, 0.4, 1.0)
const WHITE := Color(1, 1, 1, 1)
## What is selected.
const SEL := Color(1.0, 0.92, 0.2, 1.0)
## Names of objects, rivers and roads show from closer than this (the districts' always).
const NAMES_FROM := 9000.0

var _mesh: MeshInstance3D
var _labels: Node3D
var _v := PackedVector3Array()
var _c := PackedColorArray()
## Width of a thin line, metres (a couple of pixels at the camera's distance).
var _w := 10.0
var _sig := ""
var _built_w := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 1 # under the names
	_mesh.material_override = m
	# the marks are flat and huge: never culled by a box that is a step behind
	_mesh.extra_cull_margin = 16000.0
	add_child(_mesh)
	_labels = Node3D.new()
	add_child(_labels)


## Shows the drawing: `sel` and `draft` as the editor has them, `dist` the camera's distance to
## what it looks at, `pulse` 0..1 for the selected mark. Cheap when nothing has changed.
func update(data: Dictionary, sel: Dictionary, draft: Array, dist: float, version: int) -> void:
	var w := maxf(dist * 0.0032, 1.5)
	for l in _labels.get_children():
		if l.has_meta("minor"):
			(l as Label3D).visible = dist < NAMES_FROM
	var sig := "%d|%s|%d" % [version, str(sel), draft.size()]
	if sig == _sig and absf(w - _built_w) < _built_w * 0.25:
		return
	var relabel := sig != _sig
	_sig = sig
	_built_w = w
	_w = w
	_v = PackedVector3Array()
	_c = PackedColorArray()
	_build(data, sel, draft)
	if _v.is_empty():
		_mesh.mesh = null
	else:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = _v
		a[Mesh.ARRAY_COLOR] = _c
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		_mesh.mesh = am
	if relabel:
		_build_labels(data)


func vertex_count() -> int:
	return _v.size()


func label_count() -> int:
	return _labels.get_child_count()


# --- Ribbons -----------------------------------------------------------------------------------
func _quad(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	var p0 := Vector3(a.x - n.x, Y, a.y - n.y)
	var p1 := Vector3(a.x + n.x, Y, a.y + n.y)
	var p2 := Vector3(b.x + n.x, Y, b.y + n.y)
	var p3 := Vector3(b.x - n.x, Y, b.y - n.y)
	_v.append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))
	_c.append_array(PackedColorArray([col, col, col, col, col, col]))


func _polyline(pts: PackedVector2Array, width: float, col: Color, closed := false) -> void:
	for i in pts.size() - 1:
		_quad(pts[i], pts[i + 1], width, col)
	if closed and pts.size() > 2:
		_quad(pts[pts.size() - 1], pts[0], width, col)


func _circle(c: Vector2, r: float, width: float, col: Color, seg := 40) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		pts.append(c + Vector2.from_angle(TAU * i / seg) * r)
	_polyline(pts, width, col, true)


## A filled square mark (a point of a line) of side `s`.
func _dot(c: Vector2, s: float, col: Color) -> void:
	_quad(c - Vector2(s * 0.5, 0), c + Vector2(s * 0.5, 0), s, col)


func _ellipse(e: Array, seg := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rot := deg_to_rad(float(e[4]) if e.size() > 4 else 0.0)
	var c := Vector2(float(e[0]), float(e[1]))
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * float(e[2]), sin(a) * float(e[3])).rotated(rot))
	return pts


## A line through control points, smoothed the way the generator lays it.
func _curve(ctrl: Array) -> PackedVector2Array:
	if ctrl.size() < 2:
		return PackedVector2Array()
	return CustomCity.smooth(ctrl, maxf(_w * 6.0, 60.0))[0]


func _build(data: Dictionary, sel: Dictionary, draft: Array) -> void:
	var w := _w
	var st := String(sel.get("type", ""))
	var si := int(sel.get("i", -1))
	for i in (data.get("forests", []) as Array).size():
		var on := st == "forest" and si == i
		_polyline(_ellipse(data.forests[i]), w * (2.2 if on else 1.0), SEL if on else FOREST, true)
	for i in (data.get("lakes", []) as Array).size():
		var on := st == "lake" and si == i
		_polyline(_ellipse(data.lakes[i]), w * (2.2 if on else 1.0), SEL if on else WATER, true)
	for i in (data.get("districts", []) as Array).size():
		var d: Array = data.districts[i]
		var on := st == "district" and si == i
		var kc: Color = CustomCity.district_spec(String(d[4]))[3]
		var c := Vector2(float(d[1]), float(d[2]))
		var r := float(d[5]) * 1.15
		_circle(c, r, w * (2.4 if on else 1.3), SEL if on else Color(kc.r, kc.g, kc.b, 0.9), 48)
		# which way its streets run: two ticks on the ring (the middle is left to the name)
		var ga := deg_to_rad(float(d[3]))
		var along := Vector2(cos(ga), sin(ga))
		for sg in [-1.0, 1.0]:
			_quad(c + along * r * 0.72 * sg, c + along * r * sg, w * (2.0 if on else 1.2), SEL if on else Color(kc.r, kc.g, kc.b, 0.9))
	for spec in [["rivers", "river", WATER], ["rails", "rail", RAIL], ["roads", "road", ROAD]]:
		var list: Array = data.get(spec[0], [])
		for i in list.size():
			var on := st == String(spec[1]) and si == i
			var pts: Array = list[i].p
			_polyline(_curve(pts), w * (2.4 if on else 1.4), SEL if on else spec[2])
			if on:
				# the points it is drawn through: the selected one bigger
				for k in pts.size():
					var mark := k == int(sel.get("pt", -1))
					_dot(Vector2(float(pts[k][0]), float(pts[k][1])), w * (7.0 if mark else 4.5), WHITE if mark else SEL)
	for i in (data.get("objects", []) as Array).size():
		var o: Dictionary = data.objects[i]
		var on := st == "object" and si == i
		var c := Vector2(float(o.x), float(o.z))
		_circle(c, w * 6.0, w * (2.4 if on else 1.5), SEL if on else OBJECT, 20)
		_dot(c, w * 3.0, SEL if on else OBJECT)
		if on:
			# the ground it keeps free of houses, and which way it faces
			_circle(c, CustomCity.object_radius(String(o.k)), w, Color(1, 1, 1, 0.6), 40)
			var a := deg_to_rad(float(o.r))
			_quad(c, c + Vector2(sin(a), -cos(a)) * w * 16.0, w * 1.6, WHITE)
	if not draft.is_empty():
		var pl := PackedVector2Array()
		for p in draft:
			pl.append(Vector2(float(p[0]), float(p[1])))
		_polyline(pl, w * 2.0, DRAFT)
		for q in pl:
			_dot(q, w * 5.0, DRAFT)
		_circle(pl[pl.size() - 1], w * 6.0, w * 1.4, WHITE, 16)


# --- Names -------------------------------------------------------------------------------------
func _build_labels(data: Dictionary) -> void:
	for l in _labels.get_children():
		l.queue_free()
	for d in data.get("districts", []):
		_label(String(d[0]), Vector3(float(d[1]), 40.0, float(d[2])), Color(0.92, 1.0, 0.95), 24, false)
	for o in data.get("objects", []):
		var oname := String(o.n) if String(o.n) != "" else GS.t(CustomCity.object_name(String(o.k)))
		_label("◎ " + oname, Vector3(float(o.x), 120.0, float(o.z)), Color(1.0, 0.75, 0.6), 19, true)
	for r in data.get("rivers", []) + data.get("roads", []):
		if String(r.n) != "" and (r.p as Array).size() >= 2:
			var mid: Array = r.p[(r.p as Array).size() / 2]
			_label(String(r.n), Vector3(float(mid[0]), 30.0, float(mid[1])), Color(0.75, 0.9, 1.0), 18, true)


func _label(text: String, pos: Vector3, col: Color, size: int, minor: bool) -> void:
	var l := Label3D.new()
	if minor:
		l.set_meta("minor", true)
	l.text = text
	l.font = GS.font
	l.font_size = size
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.render_priority = 6
	l.outline_render_priority = 5
	l.pixel_size = 0.0011
	l.position = pos
	_labels.add_child(l)
