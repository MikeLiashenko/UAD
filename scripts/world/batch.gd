extends RefCounted
## Chunked MultiMesh builder. Instances are kept as raw MultiMesh buffers (20 floats each: a 3×4
## transform, a colour, custom data) grouped into square chunks, so the renderer can cull parts of
## the city and whole chunks can be produced on worker threads and handed over ready-made
## (adopt). Supports per-instance updates and hiding. References to instances are
## Vector2i(chunk key, index).

const STRIDE := 20

var mesh: Mesh
var material: Material
var shadows := false
## Side of a chunk, metres.
var chunk := 1000.0
## For shaders that move or grow vertices (sprites, traffic) the automatic AABB is too small.
var aabb_margin := 0.0
var aabb_height := 300.0
## Chunks further than this from the camera are not drawn (0 = no limit).
var range_end := 0.0

var _buf := {}
var mms := {}
var nodes := {}
var _parent: Node3D
var _visible := true


func _init(m: Mesh, mat: Material, chunk_size := 1000.0) -> void:
	mesh = m
	material = mat
	chunk = chunk_size


func key_at(x: float, z: float) -> int:
	return (int(floor(z / chunk)) + 512) * 1024 + int(floor(x / chunk)) + 512


## South-west corner of a chunk.
func chunk_origin(k: int) -> Vector2:
	return Vector2(float(k % 1024 - 512) * chunk, float(k / 1024 - 512) * chunk)


## Appends one instance to a raw buffer (usable from worker threads on their own buffers).
static func push(buf: PackedFloat32Array, xf: Transform3D, col: Color, cd: Color) -> void:
	var b := xf.basis
	var o := xf.origin
	buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		col.r, col.g, col.b, col.a, cd.r, cd.g, cd.b, cd.a]))


## A MultiMesh over a ready buffer.
static func make_multimesh(m: Mesh, buf: PackedFloat32Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = buf.size() / STRIDE
	if mm.instance_count > 0:
		mm.buffer = buf
	return mm


func add(xf: Transform3D, col := Color.WHITE, cd := Color(0, 0, 0, 0)) -> Vector2i:
	var k := key_at(xf.origin.x, xf.origin.z)
	if not _buf.has(k):
		_buf[k] = PackedFloat32Array()
	var b: PackedFloat32Array = _buf[k]
	var i := b.size() / STRIDE
	push(b, xf, col, cd)
	_buf[k] = b
	if mms.has(k):
		_rebuild(k) # added after build(): the chunk is made again (rare: runtime props)
	return Vector2i(k, i)


## Takes a whole run of instances for chunk `k` (made elsewhere, e.g. on a worker thread).
## Returns the index of its first instance in the chunk.
func adopt(k: int, buf: PackedFloat32Array) -> int:
	if buf.is_empty():
		return 0
	if not _buf.has(k):
		_buf[k] = buf
		return 0
	var b: PackedFloat32Array = _buf[k]
	var base := b.size() / STRIDE
	b.append_array(buf)
	_buf[k] = b
	return base


func count() -> int:
	var n := 0
	for k in _buf:
		n += (_buf[k] as PackedFloat32Array).size() / STRIDE
	return n


func build(parent: Node3D) -> void:
	_parent = parent
	for k in _buf:
		_rebuild(k)


func _rebuild(k: int) -> void:
	var b: PackedFloat32Array = _buf[k]
	var mm := make_multimesh(mesh, b)
	mms[k] = mm
	var mmi: MultiMeshInstance3D = nodes.get(k)
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var o := chunk_origin(k)
		if aabb_margin > 0.0:
			mmi.custom_aabb = AABB(Vector3(o.x - aabb_margin, -20.0, o.y - aabb_margin), Vector3(chunk + aabb_margin * 2.0, aabb_height, chunk + aabb_margin * 2.0))
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = chunk * 0.5
		mmi.visible = _visible
		_parent.add_child(mmi)
		nodes[k] = mmi
	mmi.multimesh = mm


static func _xf_at(b: PackedFloat32Array, o: int) -> Transform3D:
	return Transform3D(Basis(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]), Vector3(b[o + 2], b[o + 6], b[o + 10])),
		Vector3(b[o + 3], b[o + 7], b[o + 11]))


func get_xform(ref: Vector2i) -> Transform3D:
	return _xf_at(_buf[ref.x], ref.y * STRIDE)


func get_custom(ref: Vector2i) -> Color:
	var b: PackedFloat32Array = _buf[ref.x]
	var o := ref.y * STRIDE + 16
	return Color(b[o], b[o + 1], b[o + 2], b[o + 3])


func get_color(ref: Vector2i) -> Color:
	var b: PackedFloat32Array = _buf[ref.x]
	var o := ref.y * STRIDE + 12
	return Color(b[o], b[o + 1], b[o + 2], b[o + 3])


func set_custom(ref: Vector2i, cd: Color) -> void:
	var b: PackedFloat32Array = _buf[ref.x]
	var o := ref.y * STRIDE + 16
	b[o] = cd.r
	b[o + 1] = cd.g
	b[o + 2] = cd.b
	b[o + 3] = cd.a
	_buf[ref.x] = b
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_custom_data(ref.y, cd)


## Moves one instance (a collapsing building shrinks its box); the stored transform follows,
## so hide/unhide and later edits keep working from the new shape.
func set_xform(ref: Vector2i, xf: Transform3D) -> void:
	var b: PackedFloat32Array = _buf[ref.x]
	var o := ref.y * STRIDE
	var bs := xf.basis
	b[o] = bs.x.x
	b[o + 1] = bs.y.x
	b[o + 2] = bs.z.x
	b[o + 3] = xf.origin.x
	b[o + 4] = bs.x.y
	b[o + 5] = bs.y.y
	b[o + 6] = bs.z.y
	b[o + 7] = xf.origin.y
	b[o + 8] = bs.x.z
	b[o + 9] = bs.y.z
	b[o + 10] = bs.z.z
	b[o + 11] = xf.origin.z
	_buf[ref.x] = b
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, xf)


func hide(ref: Vector2i) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))


func unhide(ref: Vector2i) -> void:
	if mms.has(ref.x):
		(mms[ref.x] as MultiMesh).set_instance_transform(ref.y, get_xform(ref))


## All instance refs whose origin lies within `r` (horizontal) of `c`.
func refs_near(c: Vector3, r: float) -> Array:
	var out := []
	for cz in range(int(floor((c.z - r) / chunk)), int(floor((c.z + r) / chunk)) + 1):
		for cx in range(int(floor((c.x - r) / chunk)), int(floor((c.x + r) / chunk)) + 1):
			var k := (cz + 512) * 1024 + cx + 512
			if not _buf.has(k):
				continue
			var b: PackedFloat32Array = _buf[k]
			var n := b.size() / STRIDE
			for i in n:
				var o := i * STRIDE
				var dx := b[o + 3] - c.x
				var dz := b[o + 11] - c.z
				if dx * dx + dz * dz < r * r:
					out.append(Vector2i(k, i))
	return out


func set_visible(v: bool) -> void:
	_visible = v
	for k in nodes:
		(nodes[k] as Node3D).visible = v


func set_range(end: float) -> void:
	range_end = end
	for k in nodes:
		var n: MultiMeshInstance3D = nodes[k]
		n.visibility_range_end = end
		n.visibility_range_end_margin = chunk * 0.5 if end > 0.0 else 0.0
