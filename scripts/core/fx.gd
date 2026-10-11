extends RefCounted
## Shared procedural materials + one-shot visual effects (explosions, splashes, fires, glares).

const Shaders = preload("res://scripts/world/shaders.gd")
const Sparks = preload("res://scripts/game/sparks.gd")

## No floating captions ("+$1 300", "ПРОМАХ") over the effects: for pictures of the sky.
static var quiet := false

static var _mats := {}
static var _meshes := {}
static var _glare_shader: Shader
static var _paint_shader: Shader


static func glow(c: Color, energy := 2.5) -> StandardMaterial3D:
	var key := "g%s_%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func solid(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "s%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


## Paint of a vehicle or an airframe (Shaders.PAINT): the given colour, from Ultra up with
## camouflage (`camo` 0 = none), plate seams, wear and mud.
static func paint(c: Color, rough := 0.8, metal := 0.1, camo := 0.6) -> ShaderMaterial:
	var key := "p%s_%.2f_%.2f_%.2f" % [c.to_html(), rough, metal, camo]
	if _mats.has(key):
		return _mats[key]
	if _paint_shader == null:
		_paint_shader = Shader.new()
		_paint_shader.code = Shaders.PAINT
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	m.set_shader_parameter("base", c)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("camo", camo)
	_mats[key] = m
	return m


static func vcolor() -> StandardMaterial3D:
	## Uses per-vertex / per-instance colour (combined meshes, MultiMesh props).
	if _mats.has("vcolor"):
		return _mats["vcolor"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	_mats["vcolor"] = m
	return m


## Painted metal that takes its colour from the vertices / instances (parked cars).
static func solid_vcolor_metal() -> StandardMaterial3D:
	if _mats.has("vmetal"):
		return _mats["vmetal"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	m.metallic = 0.45
	_mats["vmetal"] = m
	return m


static func ghost(c: Color, energy := 1.5) -> StandardMaterial3D:
	## Additive translucent glow (beams, rings).
	var key := "t%s_%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
	_mats[key] = m
	return m


## Smoke particles: soft-edged puffs coloured by the particle, dark at night unless lit (Shaders.PUFF).
static func smoke_mat() -> ShaderMaterial:
	if _mats.has("smoke"):
		return _mats["smoke"]
	var m := Shaders.material(Shaders.PUFF.replace("BLEND", "blend_mix"))
	m.set_shader_parameter("tint", Color(0.55, 0.55, 0.6, 0.5))
	_mats["smoke"] = m
	return m


## Additive, particle-coloured: glowing exhaust / flame particles with the same soft edge.
static func fire_mat() -> ShaderMaterial:
	if _mats.has("fire"):
		return _mats["fire"]
	var m := Shaders.material(Shaders.PUFF.replace("BLEND", "blend_add"))
	m.set_shader_parameter("tint", Color(3.0, 3.0, 3.0, 1.0))
	_mats["fire"] = m
	return m


static func sphere(radius := 1.0, seg := 10) -> SphereMesh:
	var key := "sp%.2f_%d" % [radius, seg]
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 3)
	_meshes[key] = s
	return s


static func cube(size := Vector3.ONE) -> BoxMesh:
	var key := "bx%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = size
	_meshes[key] = b
	return b


static func quad() -> QuadMesh:
	if _meshes.has("quad"):
		return _meshes["quad"]
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_meshes["quad"] = q
	return q


static func ring_mesh(radius: float, thickness: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius
	t.rings = 64
	t.ring_segments = 4
	return t


# --- Glare sprites ------------------------------------------------------------------------
## `rays` = the star a lens draws around a point light, `core` 0 = a soft halo without a centre.
static func glare_material(c: Color, energy: float, base_size: float, dist_k: float, day_vis := 0.25, flicker := 0.0, unique := false, rays := 0.0, core := 1.0) -> ShaderMaterial:
	var key := "gl%s_%.2f_%.2f_%.4f_%.2f_%.2f_%.2f_%.2f" % [c.to_html(), energy, base_size, dist_k, day_vis, flicker, rays, core]
	if not unique and _mats.has(key):
		return _mats[key]
	if _glare_shader == null:
		_glare_shader = Shader.new()
		_glare_shader.code = Shaders.GLARE
	var m := ShaderMaterial.new()
	m.shader = _glare_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("base_size", base_size)
	m.set_shader_parameter("dist_k", dist_k)
	m.set_shader_parameter("day_vis", day_vis)
	m.set_shader_parameter("flicker", flicker)
	m.set_shader_parameter("rays", rays)
	m.set_shader_parameter("core", core)
	if not unique:
		_mats[key] = m
	return m


## A light blob that stays visible at any distance (engine plume, flash). `dist_k` sets its
## minimum on-screen size: world size = max(base_size, distance * dist_k).
static func glare(c: Color, energy := 2.0, base_size := 2.0, dist_k := 0.004, day_vis := 0.25, flicker := 0.0, rays := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = glare_material(c, energy, base_size, dist_k, day_vis, flicker, false, rays)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	return mi


# --- Effects ---------------------------------------------------------------------------------
static func _sparks(root: Node3D, color: Color, amount: int, vel: float, life: float, grav := -30.0, streak := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.22, 2.8, 0.22) if streak else Vector3(0.6, 0.6, 0.6)
	m.material = glow(color, 5.0)
	p.mesh = m
	p.amount = maxi(amount, 1)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vel * 0.35
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.4
	p.particle_flag_align_y = streak
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = sc
	p.emitting = true
	root.add_child(p)
	return p


static func _smoke(root: Node3D, amount: int, size: float, life: float, rise := 6.0, lit := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = sphere(1.0, 6)
	p.material_override = smoke_mat()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.8
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = sc
	var grad := Gradient.new()
	if lit:
		# the cloud of a burst hangs there lit orange — by its own fire, then by the city below
		grad.set_color(0, Color(1.0, 0.66, 0.3, 0.8))
		grad.add_point(0.1, Color(0.8, 0.47, 0.24, 0.7))
		grad.add_point(0.4, Color(0.42, 0.31, 0.27, 0.5))
	else:
		grad.set_color(0, Color(0.35, 0.3, 0.3, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.16, 0.16, 0.18, 0.0))
	p.color_ramp = grad
	p.emitting = true
	root.add_child(p)
	return p


## How much of the spark rain a graphics level draws.
static func detail() -> float:
	return [0.45, 0.7, 1.0, 1.0, 1.0][clampi(int(GS.settings.quality), 0, 4)]


## The nearest of the spark counts there are ready-made bursts for.
static func _spark_count(n: float) -> int:
	var best := 12
	for c in [12, 20, 32, 48, 72, 100]:
		if absf(float(c) - n) < absf(float(best) - n):
			best = c
	return best


## Air burst, the way a camera sees it at night: a blinding point with the star of the lens around
## it, the haze of half the sky lit up for a moment, splinters, a willow of embers that arcs over
## and rains down, and a cloud that hangs there glowing. `big` = warhead / ballistic intercept:
## brighter flash, heavier ember rain.
static func explosion(parent: Node, pos: Vector3, size := 1.0, color := Color(1.0, 0.55, 0.15), big := false) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var s := size * (1.4 if big else 1.0)
	var many := detail() * clampf(s, 0.6, 2.2)
	# the light of a big one does not grow with it for ever: a warhead on the ground must not
	# turn the night into a sunrise
	var g := minf(s, 1.0 + (s - 1.0) * 0.35) if s > 1.0 else s
	# light that illuminates the city below
	var light := OmniLight3D.new()
	light.light_color = color.lerp(Color(1, 0.9, 0.7), 0.4)
	light.light_energy = 14.0 * s
	light.omni_range = 170.0 * s
	light.omni_attenuation = 1.2
	root.add_child(light)
	# the flash, seen from any distance, with its star
	var flash := MeshInstance3D.new()
	flash.mesh = quad()
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.extra_cull_margin = 600.0
	var fm := glare_material(Color(1.0, 0.86, 0.62), 3.2, 70.0 * g, 0.11 * g, 0.6, 0.0, true, 1.6)
	flash.material_override = fm
	root.add_child(flash)
	# the haze around the burst lights up (a puff the size of a drone leaving its rail lights nothing)
	var hazy := 1.0 if s >= 0.4 else 0.0
	var halo := MeshInstance3D.new()
	halo.mesh = quad()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.extra_cull_margin = 1500.0
	var hm := glare_material(color.lerp(Color(1.0, 0.6, 0.3), 0.6), 1.9 * hazy, (700.0 if big else 560.0) * g, 0.0, 0.2, 0.0, true, 0.0, 0.0)
	halo.material_override = hm
	root.add_child(halo)
	# and the cloud of the burst goes on glowing from inside for a few seconds
	var cloud := MeshInstance3D.new()
	cloud.mesh = quad()
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.extra_cull_margin = 400.0
	var cm := glare_material(Color(1.0, 0.5, 0.2), 1.5 * hazy, 110.0 * g, 0.0, 0.3, 0.6, true, 0.0, 0.0)
	cloud.material_override = cm
	root.add_child(cloud)
	# fireball: hot white core + orange shell
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.albedo_color = Color(4.0, 3.4, 2.4, 1.0)
	var core := MeshInstance3D.new()
	core.mesh = sphere(1.0, 14)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var shell_mat := core_mat.duplicate() as StandardMaterial3D
	shell_mat.albedo_color = Color(2.6, 1.0, 0.25, 0.9)
	var shell := MeshInstance3D.new()
	shell.mesh = sphere(1.0, 14)
	shell.material_override = shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	# shock ring + pressure shell
	var ring_mat := core_mat.duplicate() as StandardMaterial3D
	ring_mat.albedo_color = Color(1.4, 1.1, 0.9, 0.6)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh(1.0, 0.12)
	ring.material_override = ring_mat
	ring.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# fragments: splinters that are gone in a second, then the embers arcing over and raining down
	Sparks.burst(root, pos, _spark_count(40.0 * many), 170.0 * s, 1.1, 16.0, 2.0, 0.08, 0.5, Color(1.0, 0.95, 0.8), Color(1.0, 0.62, 0.25), 4.0)
	Sparks.burst(root, pos, _spark_count((56.0 if big else 26.0) * many), 78.0 * s, 4.6 if big else 3.6, 12.0, 0.62, 0.5, 0.75,
		Color(1.0, 0.86, 0.55), color.lerp(Color(1.0, 0.4, 0.08), 0.6), 3.2, 0.2)
	_smoke(root, 18, 5.0 + 6.5 * s, 11.0, 5.0 + 4.0 * s, true)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE * 7.0 * s, 0.22).from(Vector3.ONE * 1.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(core_mat, "albedo_color", Color(1.2, 0.5, 0.1, 0.0), 0.35)
	tw.tween_property(shell, "scale", Vector3.ONE * 14.0 * s, 0.6).from(Vector3.ONE * 3.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell_mat, "albedo_color", Color(0.4, 0.08, 0.0, 0.0), 0.9)
	tw.tween_property(ring, "scale", Vector3(40, 40, 40) * s, 0.7).from(Vector3.ONE * 2.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "albedo_color", Color(0, 0, 0, 0), 0.7)
	tw.tween_property(light, "light_energy", 0.0, 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# the point stays burning for a second after the flash itself
	tw.tween_property(fm, "shader_parameter/energy", 0.0, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(fm, "shader_parameter/rays", 0.0, 0.7)
	tw.tween_property(hm, "shader_parameter/energy", 0.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cm, "shader_parameter/energy", 0.0, 4.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(root.queue_free).set_delay(11.0)


## A missile leaves its launcher: the motor lights the smoke and the yard around it, and for a
## moment the launch is the brightest thing in the city.
static func launch_flash(parent: Node, pos: Vector3, size := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var flash := MeshInstance3D.new()
	flash.mesh = quad()
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.extra_cull_margin = 300.0
	var fm := glare_material(Color(1.0, 0.86, 0.62), 3.0, 9.0 * size, 0.03 * size, 0.5, 0.0, true, 0.4)
	flash.material_override = fm
	root.add_child(flash)
	var halo := MeshInstance3D.new()
	halo.mesh = quad()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.extra_cull_margin = 600.0
	var hm := glare_material(Color(1.0, 0.66, 0.36), 0.3, 150.0 * size, 0.0, 0.15, 0.0, true, 0.0, 0.0)
	halo.material_override = hm
	root.add_child(halo)
	Sparks.burst(root, pos, 12, 26.0 * size, 1.3, 14.0, 1.6, 0.14, 0.45, Color(1.0, 0.9, 0.7), Color(1.0, 0.5, 0.15), 2.6, 0.6)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fm, "shader_parameter/energy", 0.0, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(hm, "shader_parameter/energy", 0.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(root.queue_free).set_delay(0.5)


static func splash(parent: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, 0.5, pos.z)
	var p := _sparks(root, Color(0.6, 0.85, 1.0), 24, 22.0, 1.2, -40.0)
	p.spread = 25.0
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh(1.0, 0.25)
	ring.material_override = ghost(Color(0.5, 0.8, 1.0, 0.8), 1.2)
	root.add_child(ring)
	var tw := root.create_tween()
	tw.tween_property(ring, "scale", Vector3(9, 1, 9), 1.2).from(Vector3(1, 1, 1))
	tw.tween_callback(root.queue_free).set_delay(0.6)


static func ground_hit(parent: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	_sparks(root, Color(1.0, 0.5, 0.1), 12, 16.0, 0.9)
	_smoke(root, 5, 2.5, 2.5, 3.0)
	var tw := root.create_tween()
	tw.tween_callback(root.queue_free).set_delay(3.0)


## Engine exhaust: short-lived additive particles in world space (a glowing plume / trail).
static func exhaust(color: Color, amount := 30, life := 0.35, size := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = sphere(1.0, 6)
	p.material_override = fire_mat()
	p.local_coords = false
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.BACK
	p.spread = 6.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.3 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	g.add_point(0.25, Color(color.r, color.g, color.b, 0.8))
	g.set_color(g.get_point_count() - 1, Color(color.r * 0.5, color.g * 0.2, 0.0, 0.0))
	p.color_ramp = g
	return p


static func float_text(parent: Node, pos: Vector3, text: String, color: Color) -> void:
	if quiet:
		return
	var l := Label3D.new()
	l.text = text
	l.font = GS.font
	l.font_size = 34
	l.outline_size = 8
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.pixel_size = 0.0011
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 8, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 45, 0), 2.4)
	tw.tween_property(l, "modulate:a", 0.0, 2.4).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 2.4).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)
