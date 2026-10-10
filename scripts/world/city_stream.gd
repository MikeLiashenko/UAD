extends Node3D
## The detail stream: the small things of the streets exist only around the camera. Every 500 m
## tile has two sets made on worker threads by CityGen.tile_decor — "mid" (the glow of the street
## lamps, sparse trees, traffic; out to a few kilometres) and "near" (everything: lamp posts,
## parked cars, balconies, fences, people, every tree). The radii and the amount depend on the
## graphics level (CityMap.QUALITY). On Max / UltraMax (Forward+) the nearest street lamps are real
## lights with shadows.

const CityGen = preload("res://scripts/world/city_gen.gd")
const Batch = preload("res://scripts/world/batch.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Shaders = preload("res://scripts/world/shaders.gd")
const Fx = preload("res://scripts/core/fx.gd")

const TILE := 500.0
## Tiles made at once on the worker threads, and tiles put on the scene per frame.
const MAX_TASKS := 10
const MAX_APPLY := 3

var map
## Loaded sets: tile → Node3D.
var _near := {}
var _mid := {}
## Running tasks: key (tile * 2 + near) → task id.
var _tasks := {}
var _results: Array = []
var _mutex := Mutex.new()
## Tiles whose near set must be made again (a house collapsed, a base was placed): tile → when.
var _dirty := {}
var _ver := 0
var _t := 0.0
var _scan := 0.0
var _wanted_missing := 0
var _off := false

var _mesh := {}
var _mat := {}
## Lamps of the loaded near sets (x, y, z, r, g, b, and the direction to the road dx, dz) by
## tile, and the pool of real lights.
var _lamps := {}
var _pool: Array = []
var _lights_t := 0.0
var _real_on := false
## Energy of a real street lamp: about the brightness of the painted pool under it.
const LAMP_ENERGY := 210.0


func _ready() -> void:
	_off = DisplayServer.get_name() == "headless"
	if _off:
		set_process(false)
		return
	_setup_assets()


func _setup_assets() -> void:
	var hi: bool = map.quality >= 3
	_mesh = {
		"lamp": Fx.quad(), "tlight": Fx.quad(),
		"pole": Meshes.lamp_post_mesh(),
		"tree": Meshes.deciduous_mesh(3 if hi else (2 if map.quality >= 2 else 1)), "pine": Meshes.conifer_mesh(3 if hi else (2 if map.quality >= 2 else 1)),
		"tree_lo": Meshes.deciduous_mesh(0), "pine_lo": Meshes.conifer_mesh(0),
		"car": Meshes.car_mesh(3 if hi else (2 if map.quality >= 2 else 1)), "tcar": Meshes.car_mesh(3 if hi else 1),
		"box": Fx.cube(Vector3.ONE), "bbox": Fx.cube(Vector3.ONE), "neon": Fx.cube(Vector3.ONE),
		"cyl": map.b_cyl.mesh, "ppl": Meshes.person_mesh(),
	}
	_mat = {
		"lamp": map.lights_mat, "tlight": map.traffic_mat,
		"pole": Fx.vcolor(), "tree": Shaders.shared("tree", Shaders.TREE), "pine": Shaders.shared("tree", Shaders.TREE),
		"car": Shaders.shared("car", Shaders.CAR), "tcar": map.b_cars.material,
		"box": Fx.vcolor(), "bbox": map.build_mat, "neon": map.neon_mat,
		"cyl": Fx.vcolor(), "ppl": map.b_people.material,
	}


func _exit_tree() -> void:
	# the tasks read the map: let them finish before it goes
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


## True while the surroundings of the camera are still being made (the screenshot tool waits).
func busy() -> bool:
	return not _off and (not _tasks.is_empty() or not _results.is_empty() or _wanted_missing > 0 or not _dirty.is_empty())


func set_blackouts(_arr: PackedVector4Array) -> void:
	pass # the materials are the map's own


func set_night(n: float) -> void:
	for l in _pool:
		(l as Light3D).visible = n > 0.45


## The graphics level changed: everything is made again with the new radii and meshes.
func apply_quality() -> void:
	if _off:
		return
	_ver += 1
	for d in [_near, _mid]:
		for t in d:
			(d[t] as Node).queue_free()
		d.clear()
	_lamps.clear()
	_dirty.clear()
	for l in _pool:
		(l as Node).queue_free()
	_pool.clear()
	_setup_assets()
	_scan = 0.0


## Something changed on the ground around a point: the near sets there are made again.
func refresh_at(x: float, z: float, r := 0.0) -> void:
	if _off:
		return
	var tn: int = map.tn
	var half: float = map.half
	for tz in range(int(floor((z - r + half) / TILE)), int(floor((z + r + half) / TILE)) + 1):
		for tx in range(int(floor((x - r + half) / TILE)), int(floor((x + r + half) / TILE)) + 1):
			if tx >= 0 and tz >= 0 and tx < tn and tz < tn:
				var t := tz * tn + tx
				if _near.has(t) or _tasks.has(t * 2 + 1):
					_dirty[t] = _t + 0.6


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


## Distance from the camera to a tile (to its square on the ground).
func _tile_dist(t: int, cp: Vector3) -> float:
	var tn: int = map.tn
	var x0: float = -map.half + (t % tn) * TILE
	var z0: float = -map.half + (t / tn) * TILE
	var dx := maxf(maxf(x0 - cp.x, cp.x - x0 - TILE), 0.0)
	var dz := maxf(maxf(z0 - cp.z, cp.z - z0 - TILE), 0.0)
	return sqrt(dx * dx + dz * dz + cp.y * cp.y * 0.5)


func _process(delta: float) -> void:
	_t += delta
	_apply_results()
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.2
		_update_wanted()
	_lights_t -= delta
	if _lights_t <= 0.0:
		_lights_t = 0.25
		_update_lights()


func _update_wanted() -> void:
	var cam := _camera()
	if cam == null:
		return
	var cp := cam.global_position
	var qd: Dictionary = map.quality_def()
	var near_r: float = qd.near
	var mid_r: float = qd.mid
	var tn: int = map.tn
	var half: float = map.half
	var ctx := int(floor((cp.x + half) / TILE))
	var ctz := int(floor((cp.z + half) / TILE))
	var span := int(ceil(mid_r / TILE)) + 1
	var want: Array = []
	var keep_near := {}
	var keep_mid := {}
	for tz in range(maxi(0, ctz - span), mini(tn - 1, ctz + span) + 1):
		for tx in range(maxi(0, ctx - span), mini(tn - 1, ctx + span) + 1):
			var t := tz * tn + tx
			var d := _tile_dist(t, cp)
			if d < mid_r * 1.2:
				keep_mid[t] = true
			if d < near_r * 1.25 + 60.0:
				keep_near[t] = true
			if d < mid_r and not _mid.has(t) and not _tasks.has(t * 2):
				want.append([d + 400.0, t, false])
			if d < near_r and not _near.has(t) and not _tasks.has(t * 2 + 1):
				want.append([d, t, true])
	# drop what the camera has left behind
	for t in _near.keys():
		if not keep_near.has(t):
			(_near[t] as Node).queue_free()
			_near.erase(t)
			_lamps.erase(t)
			if _mid.has(t):
				(_mid[t] as Node3D).visible = true
	for t in _mid.keys():
		if not keep_mid.has(t):
			(_mid[t] as Node).queue_free()
			_mid.erase(t)
	# houses that changed: their tile again, once things have settled
	for t in _dirty.keys():
		if _t >= float(_dirty[t]) and not _tasks.has(int(t) * 2 + 1):
			_dirty.erase(t)
			if keep_near.has(t):
				want.append([0.0, t, true])
	_wanted_missing = want.size()
	if want.is_empty():
		return
	want.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var dense: float = qd.dense
	for w in want:
		if _tasks.size() >= MAX_TASKS:
			break
		var t: int = w[1]
		var near: bool = w[2]
		var ver := _ver
		_tasks[t * 2 + (1 if near else 0)] = WorkerThreadPool.add_task(func() -> void:
			var dec := CityGen.tile_decor(map, t, near, dense)
			_mutex.lock()
			_results.append([t, near, ver, dec])
			_mutex.unlock(), false, "UAD detail")


func _apply_results() -> void:
	if _results.is_empty():
		return
	var done := 0
	while done < MAX_APPLY:
		_mutex.lock()
		var r = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if r == null:
			break
		var t: int = r[0]
		var near: bool = r[1]
		var key := t * 2 + (1 if near else 0)
		if _tasks.has(key):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
		if int(r[2]) != _ver:
			continue
		var node := _build_set(t, r[3], near)
		var d := _near if near else _mid
		if d.has(t):
			(d[t] as Node).queue_free()
		d[t] = node
		add_child(node)
		if near:
			_lamps[t] = (r[3] as CityGen.Decor).lights
			if _mid.has(t):
				(_mid[t] as Node3D).visible = false
		elif _near.has(t):
			node.visible = false
		done += 1


func _build_set(t: int, dec: CityGen.Decor, near: bool) -> Node3D:
	var root := Node3D.new()
	var tn: int = map.tn
	var x0: float = -map.half + (t % tn) * TILE
	var z0: float = -map.half + (t / tn) * TILE
	var life: bool = map.quality_def().life
	var shadows: bool = near and map.quality >= 2
	var sets := [
		["lamp", dec.lamp, 0], ["pole", dec.pole, 1], ["tree" if near else "tree_lo", dec.tree, 1], ["pine" if near else "pine_lo", dec.pine, 1],
		["car", dec.car, 1], ["box", dec.box, 1], ["bbox", dec.bbox, 1], ["neon", dec.neon, 0], ["cyl", dec.cyl, 1],
		["tlight", dec.tlight, 2], ["tcar", dec.tcar, 2], ["ppl", dec.ppl, 2],
	]
	for s in sets:
		var buf: PackedFloat32Array = s[1]
		if buf.is_empty():
			continue
		var kind := int(s[2])
		if kind == 2 and not life:
			continue
		var id := String(s[0])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = Batch.make_multimesh(_mesh[id], buf)
		mmi.material_override = _mat[id.trim_suffix("_lo")]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and kind == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind != 1:
			# sprites grow and traffic moves in the vertex shader: the automatic box would be too small
			var m := 60.0 if kind == 0 else 260.0
			mmi.custom_aabb = AABB(Vector3(x0 - m, -10.0, z0 - m), Vector3(TILE + m * 2.0, 420.0, TILE + m * 2.0))
		root.add_child(mmi)
	return root


## Forward+: the street lamps nearest to the camera become real lights.
func _update_lights() -> void:
	if _off or not map.forward or map.quality < 3:
		if _real_on:
			_real_on = false
			RenderingServer.global_shader_parameter_set("lamp_real", Vector4(0, 0, -1, -1))
		return
	_real_on = true
	var cam := _camera()
	if cam == null:
		return
	var want := 56 if map.quality >= 4 else 28
	var shadowed := 10 if map.quality >= 4 else 4
	while _pool.size() < want:
		var l := SpotLight3D.new()
		# a street luminaire: a wide cone straight down, falling off with the square of the distance
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.spot_angle = 64.0
		l.spot_angle_attenuation = 1.5
		l.spot_range = 36.0
		l.spot_attenuation = 2.0
		l.light_energy = LAMP_ENERGY
		l.light_specular = 1.0
		l.light_size = 0.35
		l.light_volumetric_fog_energy = 2.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = 300.0
		l.distance_fade_length = 60.0
		l.shadow_bias = 0.06
		l.shadow_blur = 1.6
		l.visible = false
		add_child(l)
		_pool.append(l)
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var cand: Array = []
	for t in _lamps:
		var a: PackedFloat32Array = _lamps[t]
		for i in a.size() / 8:
			var o := i * 8
			var p := Vector3(a[o], a[o + 1], a[o + 2])
			var to := p - cp
			var d := to.length()
			if d > 340.0:
				continue
			# what is behind the camera matters less
			if d > 30.0 and to.dot(fwd) < 0.0:
				d *= 2.2
			cand.append([d, p, Color(a[o + 3], a[o + 4], a[o + 5]), Vector3(a[o + 6], 0.0, a[o + 7])])
	cand.sort_custom(func(x, y) -> bool: return float(x[0]) < float(y[0]))
	var night_on: bool = map.night > 0.45
	# the painted pools of light on the ground give way to the real lamps as far as these reach
	var reach := 300.0 if cand.size() <= want else float(cand[want - 1][0])
	if night_on and not cand.is_empty():
		RenderingServer.global_shader_parameter_set("lamp_real", Vector4(cp.x, cp.z, reach * 0.7, reach * 0.95))
	else:
		RenderingServer.global_shader_parameter_set("lamp_real", Vector4(0, 0, -1, -1))
	for i in _pool.size():
		var l: SpotLight3D = _pool[i]
		if i < cand.size() and night_on:
			var lp: Vector3 = cand[i][1]
			# the luminaire throws its light forward over the road, not back at the houses
			var aim: Vector3 = (cand[i][3] as Vector3) * 0.36 + Vector3.DOWN
			l.look_at_from_position(lp, lp + aim, cand[i][3] as Vector3)
			l.light_color = cand[i][2]
			l.shadow_enabled = i < shadowed
			l.visible = true
		else:
			l.visible = false
