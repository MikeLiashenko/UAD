extends RefCounted
## Chunked MultiMesh builder. Instances are grouped into 400×400 spatial chunks so the renderer
## can frustum-cull parts of the city. Supports per-instance custom-data updates and hiding.
## References to instances are Vector2i(chunk_key, index).

const CHUNK := 400.0
const ORIGIN := -1400.0
const N := 7

var mesh: Mesh
var material: Material
var use_colors := false
var use_custom := false
var shadows := false
## For shaders that move or grow vertices (sprites, traffic) the automatic AABB is too small.
var aabb_margin := 0.0
var aabb_height := 300.0

var _xf := {}
var _col := {}
var _cd := {}
var mms := {}
var nodes: Array = []


func _init(m: Mesh, mat: Material, colors := false, custom := false) -> void:
	mesh = m
	material = mat
	use_colors = colors
	use_custom = custom


static func key_of(p: Vector3) -> int:
	var cx := clampi(int(floor((p.x - ORIGIN) / CHUNK)), 0, N - 1)
	var cz := clampi(int(floor((p.z - ORIGIN) / CHUNK)), 0, N - 1)
	return cz * N + cx


func add(xf: Transform3D, col := Color.WHITE, cd := Color(0, 0, 0, 0)) -> Vector2i:
	var k := key_of(xf.origin)
	if not _xf.has(k):
		_xf[k] = []
		_col[k] = []
		_cd[k] = []
	var arr: Array = _xf[k]
	arr.append(xf)
	(_col[k] as Array).append(col)
	(_cd[k] as Array).append(cd)
	return Vector2i(k, arr.size() - 1)


func count() -> int:
	var n := 0
	for k in _xf:
		n += (_xf[k] as Array).size()
	return n


func build(parent: Node3D) -> void:
	for k in _xf:
		var xs: Array = _xf[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = use_colors
		mm.use_custom_data = use_custom
		mm.mesh = mesh
		mm.instance_count = xs.size()
		var cs: Array = _col[k]
		var ds: Array = _cd[k]
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			if use_colors:
				mm.set_instance_color(i, cs[i])
			if use_custom:
				mm.set_instance_custom_data(i, ds[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if aabb_margin > 0.0:
			var cx := float(k % N) * CHUNK + ORIGIN
			var cz := float(k / N) * CHUNK + ORIGIN
			mmi.custom_aabb = AABB(Vector3(cx - aabb_margin, -20.0, cz - aabb_margin), Vector3(CHUNK + aabb_margin * 2.0, aabb_height, CHUNK + aabb_margin * 2.0))
		parent.add_child(mmi)
		mms[k] = mm
		nodes.append(mmi)


func set_custom(ref: Vector2i, cd: Color) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_custom_data(ref.y, cd)
	(_cd[ref.x] as Array)[ref.y] = cd


## Moves one instance (a collapsing building shrinks its box); the stored transform follows,
## so hide/unhide and later edits keep working from the new shape.
func set_xform(ref: Vector2i, xf: Transform3D) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, xf)
	(_xf[ref.x] as Array)[ref.y] = xf


func get_custom(ref: Vector2i) -> Color:
	return (_cd[ref.x] as Array)[ref.y]


func get_xform(ref: Vector2i) -> Transform3D:
	return (_xf[ref.x] as Array)[ref.y]


func hide(ref: Vector2i) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))


func unhide(ref: Vector2i) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, get_xform(ref))


## All instance refs whose origin lies within `r` (horizontal) of `c`.
func refs_near(c: Vector3, r: float) -> Array:
	var out := []
	for k in _xf:
		var cx := float(k % N) * CHUNK + ORIGIN
		var cz := float(k / N) * CHUNK + ORIGIN
		if c.x + r < cx or c.x - r > cx + CHUNK or c.z + r < cz or c.z - r > cz + CHUNK:
			continue
		var xs: Array = _xf[k]
		for i in xs.size():
			var o: Vector3 = (xs[i] as Transform3D).origin
			if Vector2(o.x - c.x, o.z - c.z).length() < r:
				out.append(Vector2i(k, i))
	return out


func set_visible(v: bool) -> void:
	for n in nodes:
		(n as Node3D).visible = v
