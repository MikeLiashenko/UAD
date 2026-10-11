extends MeshInstance3D
## A burst of sparks: burning fragments thrown out of an explosion, each drawing its own thin
## streak — fast splinters that are gone in a second, or heavy embers that arc over and rain down
## like the willow of a firework. The paths are worked out by the shader (Shaders.SPARKS) from the
## second of the burst; the node only counts that second and frees itself at the end.

const Shaders = preload("res://scripts/world/shaders.gd")

## Segments of one spark's streak.
const SEGMENTS := 6
## Ready-made bursts per spark count: every explosion takes one of them.
const VARIANTS := 5

var life := 3.0
var _t := 0.0
var _mat: ShaderMaterial

static var _shader: Shader
static var _meshes := {}


## `count` sparks flying out at up to `speed` m/s for up to `life` seconds. `up` > 0 throws them
## upwards rather than evenly around; `streak` = the length of a streak in seconds of flight.
static func burst(parent: Node, pos: Vector3, count: int, speed: float, life_s: float, gravity := 12.0, drag := 1.0,
		streak := 0.3, size := 0.8, head := Color(1.0, 0.9, 0.7), tail := Color(1.0, 0.45, 0.1), energy := 3.0, up := 0.0) -> MeshInstance3D:
	var s := new()
	s.life = life_s
	s.mesh = _mesh_for(count, up)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = Shaders.SPARKS
	s._mat = ShaderMaterial.new()
	s._mat.shader = _shader
	s._mat.set_shader_parameter("speed", speed)
	s._mat.set_shader_parameter("gravity", gravity)
	s._mat.set_shader_parameter("drag", maxf(drag, 0.05))
	s._mat.set_shader_parameter("life", life_s)
	s._mat.set_shader_parameter("streak", streak)
	s._mat.set_shader_parameter("size", size)
	s._mat.set_shader_parameter("head_color", head)
	s._mat.set_shader_parameter("tail_color", tail)
	s._mat.set_shader_parameter("energy", energy)
	s.material_override = s._mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the sparks fly far from the node: it must not be culled with them still on the screen
	s.extra_cull_margin = speed * life_s + 200.0
	parent.add_child(s)
	s.global_position = pos
	s.rotation = Vector3(0.0, randf() * TAU, 0.0)
	return s


func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("t", _t)
	if _t >= life:
		queue_free()


static func _mesh_for(count: int, up: float) -> ArrayMesh:
	var key := "%d_%d" % [count, int(up * 10.0)]
	if not _meshes.has(key):
		_meshes[key] = []
	var all: Array = _meshes[key]
	if all.size() < VARIANTS:
		# one more is made each time until there are enough: no hitch at the first big explosion
		all.append(_build(count, up))
		return all[all.size() - 1]
	return all[randi() % all.size()]


static func _build(count: int, up: float) -> ArrayMesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in count:
		# a direction evenly over the sphere, then tipped upwards by `up`
		var z := randf_range(-1.0, 1.0)
		var a := randf() * TAU
		var r := sqrt(maxf(1.0 - z * z, 0.0))
		var dir := (Vector3(r * cos(a), z, r * sin(a)) + Vector3(0, up, 0)).normalized()
		var vel := dir * randf_range(0.3, 1.0)
		var mine := Vector2(randf_range(0.55, 1.0), randf())
		var base := pos.size()
		for j in SEGMENTS + 1:
			for side in [0.0, 1.0]:
				pos.append(vel)
				uv.append(Vector2(side, float(j) / float(SEGMENTS)))
				uv2.append(mine)
		for j in SEGMENTS:
			var q := base + j * 2
			idx.append_array(PackedInt32Array([q, q + 1, q + 2, q + 1, q + 3, q + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# the vertices hold velocities, not places: the real extent is the cull margin's business
	m.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return m
