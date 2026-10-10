extends MeshInstance3D
## The streak a missile leaves across the night sky: a ribbon through the points its motor passed,
## white-hot behind the nozzle, cooling to grey smoke that widens and thins out over the seconds.
## It always faces the camera and never gets thinner than a couple of pixels, so an intercept ten
## kilometres away still draws its line over the city. The ribbon lives in world space: when the
## missile is gone it stays, fades and frees itself.

const MAX_POINTS := 260

## Node whose path is traced (the ribbon ends when it is freed).
var follow: Node3D
## Seconds a point of the trail lives.
var life := 9.0
## Seconds the trail keeps the glow of the motor.
var hot_time := 1.4
## Width behind the nozzle and at the end of the trail's life, metres.
var w0 := 1.4
var w1 := 16.0
var hot := Color(3.2, 2.2, 1.2, 0.95)
var smoke := Color(0.62, 0.62, 0.66, 0.42)
## Offset of the nozzle behind the followed node, along its -Z (forward) axis.
var back := 3.0

var _p := PackedVector3Array()
var _t := PackedFloat32Array()
var _now := 0.0
var _im := ImmediateMesh.new()
var _done := false

static var _mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
global uniform float night;

void fragment() {
	// soft edges across the ribbon; the smoke is lit from below by the city at night
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float soft = smoothstep(0.0, 0.55, edge);
	vec3 c = COLOR.rgb;
	float glow = max(max(c.r, c.g), c.b);
	c = mix(c * mix(1.0, 0.42, night), c, step(1.0, glow));
	ALBEDO = c;
	ALPHA = COLOR.a * soft;
}
"""


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16000.0
	if _mat == null:
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_mat.shader = sh
	material_override = _mat


## The followed node is gone: no new points, the ribbon fades away.
func finish() -> void:
	_done = true
	follow = null


func _process(delta: float) -> void:
	_now += delta
	if not _done:
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			var pos := follow.global_position + follow.global_transform.basis.z * back
			var n := _p.size()
			if n == 0 or _p[n - 1].distance_to(pos) > 6.0:
				_p.append(pos)
				_t.append(_now)
				if _p.size() > MAX_POINTS:
					_p.remove_at(0)
					_t.remove_at(0)
		else:
			finish()
	while _t.size() > 0 and _now - _t[0] > life:
		_p.remove_at(0)
		_t.remove_at(0)
	_im.clear_surfaces()
	var n := _p.size()
	if n < 2:
		if _done:
			queue_free()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := _p[i]
		var age := _now - _t[i]
		var k := clampf(age / life, 0.0, 1.0)
		var tan := (_p[mini(i + 1, n - 1)] - _p[maxi(i - 1, 0)])
		var to_cam := cp - p
		var side := tan.cross(to_cam)
		if side.length_squared() < 0.0001:
			side = Vector3.UP
		# never thinner than a couple of pixels, however far away
		var w := maxf(lerpf(w0, w1, sqrt(k)), to_cam.length() * 0.0013)
		side = side.normalized() * w * 0.5
		var h := clampf(1.0 - age / hot_time, 0.0, 1.0)
		var c := smoke.lerp(hot, h * h)
		c.a *= (1.0 - k) * (1.0 - k)
		# the newest point tapers into the nozzle
		if i == n - 1 and not _done:
			c.a *= 0.6
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(0.0, age))
		_im.surface_add_vertex(p - side)
		_im.surface_set_uv(Vector2(1.0, age))
		_im.surface_add_vertex(p + side)
	_im.surface_end()
