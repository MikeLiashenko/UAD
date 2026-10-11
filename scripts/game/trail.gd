extends MeshInstance3D
## The streak a missile leaves across the night sky: a ribbon through the points its motor passed.
## It is both the smoke — glowing behind the nozzle, then grey, widening, curling and torn into
## puffs — and the line of light a long exposure keeps of the motor: a hair-thin arc that goes on
## glowing after the missile is gone, so a battery at work draws its fan of arcs over the city.
##
## The ribbon lives in world space and outlives what it follows. The script only adds a point
## when the head has moved on (or turned); ageing, fading, width, the curl of the smoke and the
## head sticking to the nozzle are the shader's work (Shaders.TRAIL), so a trail that just hangs
## in the sky costs nothing per frame.

const Shaders = preload("res://scripts/world/shaders.gd")

const MAX_POINTS := 300
## A new point after this much of a turn, radians — keeps a tight spiral round.
const TURN := 0.03
## A turn sharper than this between two points is rounded off, radians.
const CORNER := 0.09

## Node whose path is traced (the ribbon ends when it is freed).
var follow: Node3D
## Seconds a point of the smoke lives.
var life := 9.0
## Seconds the smoke keeps the glow of the motor behind the nozzle.
var hot_time := 1.4
## Seconds the thin line of light stays in the sky (0 = smoke only).
var glow_time := 6.0
## Width behind the nozzle and at the end of the smoke's life, metres.
var w0 := 1.4
var w1 := 16.0
var hot := Color(1.0, 0.72, 0.42, 0.95)
var hot_energy := 3.0
var smoke := Color(0.62, 0.62, 0.66, 0.42)
var glow := Color(1.0, 0.72, 0.4)
var glow_energy := 2.8
## How far the smoke curls away from the line of flight as it ages, metres.
var wobble := 14.0
## Offset of the nozzle behind the followed node, along its -Z (forward) axis.
var back := 3.0
## Shortest distance between two points of the ribbon, metres (longer by itself for a fast missile:
## the MAX_POINTS it may keep must cover its whole life).
var step := 6.0

var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _now := 0.0
var _along := 0.0
var _last := Vector3.ZERO
var _last_dir := Vector3.ZERO
var _head := Vector3.ZERO
var _speed := 0.0
var _mesh := ArrayMesh.new()
var _mat: ShaderMaterial
var _done := false
var _end := 0.0
var _curl := 1.0

static var _shader: Shader


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16000.0
	if _shader == null:
		_shader = Shader.new()
		_shader.code = Shaders.TRAIL
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	for k in ["life", "hot_time", "w0", "w1", "hot", "hot_energy", "smoke", "glow", "glow_energy", "wobble"]:
		_mat.set_shader_parameter(k, get(k))
	_mat.set_shader_parameter("glow_time", maxf(glow_time, 0.001))
	if glow_time <= 0.0:
		_mat.set_shader_parameter("glow_energy", 0.0)
	_mat.set_shader_parameter("seed", randf() * 40.0)
	material_override = _mat


## The followed node is gone: no new points, the ribbon fades away.
func finish() -> void:
	if _done:
		return
	_done = true
	follow = null
	_end = _now
	if _pos.size() >= 2:
		_fix_head()
		_upload()


func _nozzle() -> Vector3:
	return follow.global_position + follow.global_transform.basis.z * back


func _process(delta: float) -> void:
	_now += delta
	_mat.set_shader_parameter("now", _now)
	if _done:
		if _now - _end > maxf(life, glow_time) or _pos.size() < 4:
			queue_free()
		return
	if follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
		finish()
		return
	var p := _nozzle()
	if delta > 0.0:
		_speed = lerpf(_speed, _head.distance_to(p) / delta, 0.2) if _pos.size() > 0 else 0.0
	_head = p
	_mat.set_shader_parameter("head", p)
	if _pos.is_empty():
		# the first point, and the pair that rides on the nozzle
		_last = p
		_push(p, Vector3.UP, _now, 0.0)
		_push(p, Vector3.UP, _now, 1.0)
		_upload()
		return
	var d := p - _last
	var dist := d.length()
	# long enough links for the whole life of the trail to fit into the points it may keep
	var need := maxf(step, _speed * maxf(life, glow_time) / float(MAX_POINTS - 40))
	var turned := _last_dir != Vector3.ZERO and dist > step and d.angle_to(_last_dir) > TURN
	if dist < need and not turned:
		return
	_along += dist
	if need > _curl * 45.0 * 1.3:
		# the links have grown: the bends of the smoke grow with them, or they would show as zigzags
		_curl = need / 45.0
		_mat.set_shader_parameter("curl_scale", _curl)
	if _last_dir != Vector3.ZERO and d.angle_to(_last_dir) > CORNER:
		_round_corner(p)
	_last_dir = d / dist
	_last = p
	_fix_head()
	_push(p, _last_dir, _now, 1.0)
	_trim()
	_upload()


## One point of the ribbon: its two edges.
func _push(p: Vector3, dir: Vector3, born: float, riding: float) -> void:
	for side in [0.0, 1.0]:
		_pos.append(p)
		_dir.append(dir)
		_uv.append(Vector2(side, born))
		_uv2.append(Vector2(riding, _along))


## A missile turns in steps, one a frame, and at speed a step is a visible corner. The last point
## the trail kept is that corner: it is replaced by three points of the curve through it, so the
## arc reads as an arc. (Called before the head is fixed at `c`: the arrays end with the corner
## and the riding pair.)
func _round_corner(c: Vector3) -> void:
	var n := _pos.size()
	if n < 6:
		return
	var a := _pos[n - 6]
	var b := _pos[n - 4]
	var ta := _uv[n - 6].y
	var tb := _uv[n - 4].y
	var la := _uv2[n - 6].y
	var lb := _uv2[n - 4].y
	var riding := _dir[n - 1]
	# the corner and the riding pair come off …
	_pos.resize(n - 4)
	_dir.resize(n - 4)
	_uv.resize(n - 4)
	_uv2.resize(n - 4)
	# … and three points of the curve from just before the corner to just after it go in
	var p0 := a.lerp(b, 0.62)
	var p2 := b.lerp(c, 0.38)
	var times := [lerpf(ta, tb, 0.62), tb, lerpf(tb, _now, 0.38)]
	var places := [lerpf(la, lb, 0.62), lb, lerpf(lb, _along, 0.38)]
	var keep := _along
	for k in 3:
		var u := float(k) * 0.5
		var q := p0.lerp(b, u).lerp(b.lerp(p2, u), u)
		var tan := (b - p0) * (1.0 - u) + (p2 - b) * u
		_along = float(places[k])
		_push(q, tan.normalized() if tan.length() > 0.001 else riding, float(times[k]), 0.0)
	_along = keep
	_push(c, riding, _now, 1.0)


## The pair that rode on the nozzle stays where the nozzle is now.
func _fix_head() -> void:
	var n := _pos.size()
	var dir := (_head - _pos[n - 4]).normalized() if n >= 4 else Vector3.UP
	if dir == Vector3.ZERO:
		dir = _dir[n - 1]
	for i in [n - 2, n - 1]:
		_pos[i] = _head
		_dir[i] = dir
		_uv[i] = Vector2(_uv[i].x, _now)
		_uv2[i] = Vector2(0.0, _along)
	if n >= 4 and n < 6:
		# the very first point had no direction yet
		_dir[0] = dir
		_dir[1] = dir


## Points too old to show, and the oldest ones past the limit, leave the ribbon.
func _trim() -> void:
	var keep := maxf(life, glow_time)
	var drop := 0
	while _pos.size() - drop > 4 and (_now - _uv[drop].y > keep or _pos.size() - drop > MAX_POINTS * 2):
		drop += 2
	if drop > 0:
		_pos = _pos.slice(drop)
		_dir = _dir.slice(drop)
		_uv = _uv.slice(drop)
		_uv2 = _uv2.slice(drop)


func _upload() -> void:
	_mesh.clear_surfaces()
	if _pos.size() < 4:
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _pos
	arr[Mesh.ARRAY_NORMAL] = _dir
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_TEX_UV2] = _uv2
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr)
