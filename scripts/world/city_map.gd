extends Node3D
## A city at its real size, built from a CityDef (scripts/world/cities/<id>.gd): the water (rivers,
## lakes, the sea, islands) as an exact distance function, zones and districts, avenues and
## railways with their bridges, and the registry of every building footprint so falling debris can
## hit any roof. The square ±half (25–35 km across) is cut into 500 m tiles: the buildings of every
## tile are generated on worker threads when the map loads (CityGen), the small things of a street —
## lamps, trees, parked cars, balconies — only around the camera (CityStream). Unique landmarks come
## from the city file (with the Landmarks toolkit), moving life from Life.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Shaders = preload("res://scripts/world/shaders.gd")
const Batch = preload("res://scripts/world/batch.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const CityStream = preload("res://scripts/world/city_stream.gd")
const Landmarks = preload("res://scripts/world/landmarks.gd")
const Life = preload("res://scripts/world/life.gd")
const Cities = preload("res://scripts/world/cities.gd")

## GS.Zone as plain constants: the generator compares zones on many threads, and reaching the enum
## through the autoload every time would make them wait for each other.
const Z_FIELD := 0
const Z_FOREST := 1
const Z_WATER := 2
const Z_CITY := 3
const Z_SAND := 4

## Side of a tile: the unit of generation, of the building chunks and of the detail streaming.
const TILE := 500.0
## Cell of the footprint lookup grid.
const FCELL := 50.0
## Cell of the water / road lookup hashes.
const HCELL := 250.0
## The water distance is exact up to this far from the shore; beyond it is just "far".
const W_REACH := 320.0
const FAR := 1000.0
## Same for the distance to avenues and railways.
const RD_REACH := 60.0
## Rivers are followed this far beyond the edge of the map.
const EDGE := 1000.0

var city_id := "kyiv"
var city
## Half of the playable square (from the city), metres.
var half := 15000.0
## Tiles per side.
var tn := 60
## Zone raster: side in cells and metres per cell (a picture for the ground and quick lookups;
## the generator asks classify() itself).
var zn := 1024
var zres := 30.0
var zones := PackedByteArray()
var urb := PackedByteArray()
var targets: Array = []
## Polylines drawn on the radar (rivers, the coast).
var radar_lines: Array = []
var night := 1.0
var fog_scale := 1.0
var env: Environment
var rng := RandomNumberGenerator.new()
## 0 low … 4 ultramax (see apply_quality).
var quality := 2
## True when the Forward+ renderer runs (Max / UltraMax on a computer).
var forward := false

# --- Water: shapes in a spatial hash ---------------------------------------------------------------
## 8 floats per shape. Capsule: 0, ax, az, abx, abz, 1/|ab|², wa, wb − wa. Ellipse: 1, cx, cz, rx,
## rz, cos, sin, min(rx, rz).
var _wsh := PackedFloat32Array()
var _wc_start := PackedInt32Array()
var _wc_items := PackedInt32Array()
var _ic_start := PackedInt32Array()
var _ic_items := PackedInt32Array()
var _hn := 0
var _hhalf := 0.0
# --- Avenues and railways: capsules of constant width: ax, az, abx, abz, 1/|ab|², w ---------------------
var _rsh := PackedFloat32Array()
var _rc_start := PackedInt32Array()
var _rc_items := PackedInt32Array()
## Bridges actually built: {"a", "b", "deck", "style", "fp", "name"}.
var built_bridges: Array = []
## Railway tracks for the trains: {"pts": PackedVector3Array, "len": PackedFloat32Array, "trains", "cars"}.
var tracks: Array = []
## Boat lanes in the water: PackedVector2Array each.
var lanes: Array = []

# --- Districts ---------------------------------------------------------------------------------------
## Flat district data for the lookups (see _gen_districts) and the candidate districts of every
## tile (those that can be the nearest for some point of it).
var _df := PackedFloat32Array()
var _dp := PackedFloat32Array()
var _dc_start := PackedInt32Array()
var _dc_items := PackedInt32Array()
## Zone-only ellipses (islands, parks) and woods, 8 floats each.
var _za := PackedFloat32Array()
var _fa := PackedFloat32Array()
var _beach := 0.0
var _park_thr := 0.45
## The city has its own zone rule (CityDef.zone_hook) for land this close to water.
var _hook_reach := 0.0
## The two zone noises sampled into grids (lookups from many threads must not call into objects),
## and the sea shore as a table (CityDef.coast).
var _ng := PackedFloat32Array()
var _ngn := 0
var _ng2 := PackedFloat32Array()
var _ng2n := 0
var _coast := PackedFloat32Array()
var _coast_z0 := 0.0
var _coast_step := 20.0
var city_seed := 0
## Street profile of every district (CityGen.PROFILES).
var d_kind: Array = []

# --- Footprints: everything debris can land on ----------------------------------------
var fp_center := PackedVector3Array()   # x, roof height, z
var fp_half := PackedVector2Array()
var fp_rot := PackedFloat32Array()
var fp_kind := PackedByteArray()
var fp_damaged := PackedByteArray()
## x = box height, y = pitched-roof height (0 = none) — what a collapsed building is rebuilt from.
var fp_box := PackedVector2Array()
## How much of the building has come down, 0..CRUSH_MAX.
var fp_crush := PackedFloat32Array()
var fp_hidden := PackedByteArray()
## Facade style (see Shaders.BUILDING), wall colour and the seed of the windows.
var fp_style := PackedByteArray()
var fp_col := PackedColorArray()
var fp_seed := PackedFloat32Array()
## The building's box in b_build (chunk key, index; −1 = an invisible footprint) and its roof in b_roof.
var fp_bk := PackedInt32Array()
var fp_bi := PackedInt32Array()
var fp_rk := PackedInt32Array()
var fp_ri := PackedInt32Array()
## Pieces glued to the box right after it in b_build (machine rooms, turrets, crowns): how many,
## and which of them sit on the roof (bit mask) and go when the top floors go.
var fp_att := PackedByteArray()
var fp_att_roof := PackedByteArray()
var fp_name := {}
## Footprint lookup: for every FCELL cell the run [start, start + count) in _fp_items.
var _fp_start := PackedInt32Array()
var _fp_items := PackedInt32Array()
var _fp_dirty := true
## Footprints registered after the grid was built (few): checked one by one.
var _fp_late := PackedInt32Array()
var _fn := 0
var hmax := PackedFloat32Array()
## Footprints of the road bridges (the fire crews drive over them).
var road_bridge_fp: Array = []
## First footprint and count of every tile's generated buildings, and the tile's blocks
## (8 floats each: district, type, x0, x1, z0, z1 in the district's frame, i, j).
var tile_fp0 := PackedInt32Array()
var tile_fpn := PackedInt32Array()
var tile_blocks: Array = []
## Lamps of the avenues by tile (x, y, z, yaw each), for the poles of the detail stream.
var road_lamps := {}

# --- Instanced geometry -------------------------------------------------------------------------
var b_build: Batch
var b_roof: Batch
var b_lights: Batch
var b_traffic: Batch
var b_props: Batch
var b_cyl: Batch
var b_cars: Batch
var b_people: Batch
var b_detail: Batch
var b_neon: Batch
var neon_mat: ShaderMaterial
## How many more smoking chimneys the city may light (particles are not free).
var smoke_budget := 40
## The detail stream around the camera.
var stream: CityStream

const BILLBOARD := [Color(1.0, 0.35, 0.5), Color(0.35, 0.8, 1.0), Color(1.0, 0.85, 0.35), Color(0.6, 1.0, 0.5), Color(0.95, 0.95, 1.0)]
const CAR_PAINT := [Color(0.9, 0.9, 0.9), Color(0.08, 0.08, 0.09), Color(0.6, 0.62, 0.65), Color(0.6, 0.08, 0.06), Color(0.1, 0.22, 0.5), Color(0.35, 0.36, 0.38), Color(0.85, 0.75, 0.3), Color(0.15, 0.35, 0.2)]
const CLOTHES := [Color(0.15, 0.15, 0.2), Color(0.5, 0.1, 0.1), Color(0.2, 0.3, 0.55), Color(0.75, 0.7, 0.6), Color(0.3, 0.45, 0.3), Color(0.9, 0.9, 0.9), Color(0.55, 0.35, 0.2), Color(0.95, 0.8, 0.2)]

var build_mat: ShaderMaterial
var lights_mat: ShaderMaterial
var traffic_mat: ShaderMaterial
var road_mat: ShaderMaterial
var blackouts: Array = []

var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
## Circles kept free of generated houses (x, z, r) and their lookup grid.
var _rv := PackedVector3Array()
var _rv_start := PackedInt32Array()
var _rv_items := PackedInt32Array()
var _rv_dirty := true
## Circles cleared for the players' bases (x, z, r): nothing of the detail stream stands there.
var cleared := PackedVector3Array()
var _sky_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _outer_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _labels: Node3D
var _hidden: Array = []
var _hidden_fp: Array = []
var _tile_out: Array = []
var gen_ms := 0


func _ready() -> void:
	build()
	GS.state_changed.connect(_on_settings)


func _on_settings() -> void:
	apply_quality(int(GS.settings.quality))


func build() -> void:
	var t0 := Time.get_ticks_msec()
	_prof_t = Time.get_ticks_usec()
	city = Cities.get_def(city_id)
	city_id = city.id
	half = float(city.half)
	tn = int(ceil(half * 2.0 / TILE))
	# a phone gets a coarser picture of the zones; the generator does not depend on it
	zn = 1024 if OS.has_feature("pc") else 512
	zres = half * 2.0 / zn
	_fn = int(ceil(half * 2.0 / FCELL))
	forward = RenderingServer.get_current_rendering_method() == "forward_plus"
	rng.seed = city.seed
	_noise.seed = city.noise_seed
	_noise.frequency = 0.0007
	_noise.fractal_octaves = 3
	_noise2.seed = city.noise2_seed
	_noise2.frequency = 0.0035
	hmax.resize(_fn * _fn)
	_setup_env()
	_make_batches()
	_step("setup")
	_gen_water_hash()
	_gen_route_hash()
	_gen_districts()
	_gen_noise()
	_step("hashes")
	_gen_zones()
	_step("zones")
	_gen_ground()
	_gen_water_mesh()
	city.build_outer(self)
	_step("ground+water mesh")
	Landmarks.begin(self)
	city.build_landmarks(self)
	_step("landmarks")
	_gen_routes()
	Landmarks.finish()
	_step("roads+rails")
	_freeze_reserved()
	_gen_tiles()
	_step("tiles")
	_build_fp_index()
	_step("index")
	_gen_power_lines()
	for b in [b_build, b_roof, b_lights, b_traffic, b_props, b_cyl, b_cars, b_people, b_detail, b_neon]:
		(b as Batch).build(self)
	var life := Life.new()
	life.map = self
	add_child(life)
	stream = CityStream.new()
	stream.map = self
	add_child(stream)
	_gen_labels()
	_step("batches+life")
	_update_blackouts()
	apply_quality(int(GS.settings.quality))
	set_night(1.0)
	gen_ms = Time.get_ticks_msec() - t0
	print("UAD: %s (%d×%d km) generated in %d ms: %d buildings, %d roofs, %d lights, %d cars, %d bridges, %d districts" % [
		city.id, int(half / 500.0), int(half / 500.0), gen_ms, fp_box.size(), b_roof.count(), b_lights.count(), b_cars.count(), built_bridges.size(), city.districts.size()])


## How many worker threads the generation uses. A release build takes them all; a debug build takes
## a global lock on every script call (the engine checks for freed objects), so more than eight
## threads only queue on it.
func _threads() -> int:
	return 8 if OS.is_debug_build() else -1


var _prof_t := 0
var _prof := OS.get_cmdline_user_args().has("--genprof")


## Generation profile (run with -- --genprof).
func _step(what: String) -> void:
	if _prof:
		var now := Time.get_ticks_usec()
		print("UAD GEN %-18s %6.1f ms" % [what, (now - _prof_t) / 1000.0])
		_prof_t = now


func _make_batches() -> void:
	build_mat = Shaders.material(Shaders.BUILDING)
	lights_mat = Shaders.material(Shaders.LIGHTS)
	traffic_mat = Shaders.material(Shaders.TRAFFIC)
	road_mat = Shaders.material(Shaders.ROAD)
	b_build = Batch.new(Fx.cube(Vector3.ONE), build_mat, TILE)
	b_build.shadows = true
	var prism := PrismMesh.new()
	prism.size = Vector3.ONE
	b_roof = Batch.new(prism, build_mat, TILE)
	b_roof.shadows = true
	b_lights = Batch.new(Fx.quad(), lights_mat, 1000.0)
	b_lights.aabb_margin = 80.0
	b_lights.aabb_height = 600.0
	b_traffic = Batch.new(Fx.quad(), traffic_mat, 1000.0)
	b_traffic.aabb_margin = 700.0
	b_props = Batch.new(Fx.cube(Vector3.ONE), Fx.vcolor(), 1000.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 14
	cyl.rings = 1
	b_cyl = Batch.new(cyl, Fx.vcolor(), 1000.0)
	b_cyl.shadows = true
	b_cars = Batch.new(Meshes.car_mesh(1), Shaders.material(Shaders.CAR_BODY), 1000.0)
	b_cars.aabb_margin = 700.0
	b_cars.aabb_height = 60.0
	b_people = Batch.new(Meshes.person_mesh(), Shaders.material(Shaders.PEOPLE), 1000.0)
	b_people.aabb_margin = 700.0
	b_people.aabb_height = 60.0
	b_detail = Batch.new(Fx.cube(Vector3.ONE), Fx.vcolor(), 1000.0)
	neon_mat = Shaders.material(Shaders.NEON)
	b_neon = Batch.new(Fx.cube(Vector3.ONE), neon_mat, 1000.0)


# --- Water ------------------------------------------------------------------------------------------
## Every river is a chain of capsules; lakes and islands are ellipses; the sea is the city's own
## function. The shapes go into a spatial hash and the distance is computed exactly from the few
## shapes around the point. Everything the lookups touch is a flat packed array: the generator
## asks from two dozen threads at once, and containers that count their references would make
## them wait for each other.
func _hash_cell(x: float, z: float) -> int:
	var ix := int(floor((x + _hhalf) / HCELL))
	var iz := int(floor((z + _hhalf) / HCELL))
	if ix < 0 or iz < 0 or ix >= _hn or iz >= _hn:
		return -1
	return iz * _hn + ix


func _hash_add(cells: Array, i: int, x0: float, z0: float, x1: float, z1: float) -> void:
	var cx0 := maxi(0, int(floor((x0 + _hhalf) / HCELL)))
	var cx1 := mini(_hn - 1, int(floor((x1 + _hhalf) / HCELL)))
	var cz0 := maxi(0, int(floor((z0 + _hhalf) / HCELL)))
	var cz1 := mini(_hn - 1, int(floor((z1 + _hhalf) / HCELL)))
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := cz * _hn + cx
			if cells[k] == null:
				cells[k] = PackedInt32Array()
			var l: PackedInt32Array = cells[k]
			l.append(i)
			cells[k] = l


## Per-cell lists → one run of items with the start of every cell: [starts, items].
func _csr(cells: Array) -> Array:
	var start := PackedInt32Array()
	start.resize(cells.size() + 1)
	var items := PackedInt32Array()
	for k in cells.size():
		start[k] = items.size()
		if cells[k] != null:
			items.append_array(cells[k])
	start[cells.size()] = items.size()
	return [start, items]


var _has_sea := false


func _gen_water_hash() -> void:
	_has_sea = bool(city.has_sea)
	_hook_reach = float(city.hook_reach)
	_coast = city.coast
	_coast_z0 = float(city.coast_z0)
	_coast_step = float(city.coast_step)
	_has_sea = _has_sea and _coast.size() >= 3
	_hhalf = half + EDGE
	_hn = int(ceil(_hhalf * 2.0 / HCELL))
	var wcells: Array = []
	var icells: Array = []
	wcells.resize(_hn * _hn)
	icells.resize(_hn * _hn)
	for r in city.rivers:
		var pts: PackedVector2Array = r.pts
		var ws: PackedFloat32Array = r.w
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.0001)
			var si := _wsh.size() / 8
			_wsh.append_array(PackedFloat32Array([0.0, a.x, a.y, ab.x, ab.y, 1.0 / l2, ws[i], ws[i + 1] - ws[i]]))
			var rr := maxf(ws[i], ws[i + 1]) + W_REACH
			_hash_add(wcells, si, minf(a.x, b.x) - rr, minf(a.y, b.y) - rr, maxf(a.x, b.x) + rr, maxf(a.y, b.y) + rr)
		if float(ws[0]) >= 25.0:
			radar_lines.append(pts)
	for c in city.radar_coast():
		radar_lines.append(c)
	for l in city.lakes:
		var si := _wsh.size() / 8
		_wsh.append_array(_ellipse_shape(l))
		var rr := maxf(float(l[2]), float(l[3])) + W_REACH
		_hash_add(wcells, si, float(l[0]) - rr, float(l[1]) - rr, float(l[0]) + rr, float(l[1]) + rr)
	for isl in city.islands:
		var si := _wsh.size() / 8
		_wsh.append_array(_ellipse_shape(isl))
		var rr := maxf(float(isl[2]), float(isl[3])) + W_REACH
		_hash_add(icells, si, float(isl[0]) - rr, float(isl[1]) - rr, float(isl[0]) + rr, float(isl[1]) + rr)
	var w := _csr(wcells)
	_wc_start = w[0]
	_wc_items = w[1]
	var ic := _csr(icells)
	_ic_start = ic[0]
	_ic_items = ic[1]


func _ellipse_shape(e: Array) -> PackedFloat32Array:
	var rot := deg_to_rad(float(e[4]) if e.size() > 4 else 0.0)
	return PackedFloat32Array([1.0, float(e[0]), float(e[1]), float(e[2]), float(e[3]), cos(rot), sin(rot), minf(float(e[2]), float(e[3]))])


## Signed distance to the sea shore (negative = at sea).
func sea_dist(x: float, z: float) -> float:
	var f := clampf((z - _coast_z0) / _coast_step, 1.0, _coast.size() - 2.001)
	var i := int(f)
	var slope := (_coast[i + 1] - _coast[i - 1]) / (2.0 * _coast_step)
	return (lerpf(_coast[i], _coast[i + 1], f - i) - x) / sqrt(1.0 + slope * slope)


## Signed distance to water (negative = in the water), exact within W_REACH of a shore.
func water_dist(x: float, z: float) -> float:
	var g := FAR
	var k := -1
	var ix := int(floor((x + _hhalf) / HCELL))
	var iz := int(floor((z + _hhalf) / HCELL))
	if ix >= 0 and iz >= 0 and ix < _hn and iz < _hn:
		k = iz * _hn + ix
		for q in range(_wc_start[k], _wc_start[k + 1]):
			var o: int = _wc_items[q] * 8
			var d: float
			if _wsh[o] < 0.5:
				var ax := _wsh[o + 1]
				var az := _wsh[o + 2]
				var abx := _wsh[o + 3]
				var abz := _wsh[o + 4]
				var t := clampf(((x - ax) * abx + (z - az) * abz) * _wsh[o + 5], 0.0, 1.0)
				var dx := ax + abx * t - x
				var dz := az + abz * t - z
				d = sqrt(dx * dx + dz * dz) - (_wsh[o + 6] + _wsh[o + 7] * t)
			else:
				var ex := x - _wsh[o + 1]
				var ez := z - _wsh[o + 2]
				var u := (ex * _wsh[o + 5] + ez * _wsh[o + 6]) / _wsh[o + 3]
				var v := (-ex * _wsh[o + 6] + ez * _wsh[o + 5]) / _wsh[o + 4]
				d = (sqrt(u * u + v * v) - 1.0) * _wsh[o + 7]
			if d < g:
				g = d
	if _has_sea:
		var sd := sea_dist(x, z)
		if sd < g:
			g = sd
	if k >= 0 and g < FAR * 0.5:
		for q in range(_ic_start[k], _ic_start[k + 1]):
			var o: int = _ic_items[q] * 8
			var ex := x - _wsh[o + 1]
			var ez := z - _wsh[o + 2]
			var u := (ex * _wsh[o + 5] + ez * _wsh[o + 6]) / _wsh[o + 3]
			var v := (-ex * _wsh[o + 6] + ez * _wsh[o + 5]) / _wsh[o + 4]
			var d := (sqrt(u * u + v * v) - 1.0) * _wsh[o + 7]
			if -d > g:
				g = -d
	return g


## True where a hash cell has water shapes around it (or the sea is near): only there the shore
## can run.
func _cell_has_water(k: int, cx: float, cz: float) -> bool:
	if _wc_start[k + 1] > _wc_start[k]:
		return true
	return _has_sea and sea_dist(cx, cz) < HCELL * 1.5


## The water surface: marching squares along the shores, whole quads over open water. Rows of hash
## cells are meshed on worker threads.
const W_COARSE := 62.5
const W_FINE := 12.5


func _gen_water_mesh() -> void:
	_water_mat = Shaders.material(Shaders.WATER)
	var rows: Array = []
	rows.resize(_hn)
	var gid := WorkerThreadPool.add_group_task(func(iz: int) -> void: rows[iz] = _water_row(iz), _hn, _threads(), true, "UAD water")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	# one mesh per band of rows, so far water is culled
	var band := 8
	for b0 in range(0, _hn, band):
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		for iz in range(b0, mini(b0 + band, _hn)):
			var r = rows[iz]
			if r != null:
				verts.append_array(r[0])
				cols.append_array(r[1])
		if verts.is_empty():
			continue
		var norms := PackedVector3Array()
		norms.resize(verts.size())
		norms.fill(Vector3.UP)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var mi := Meshes.part(self, am, _water_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One row of hash cells: [vertices, colours] (the colour is how far from the bank the vertex is).
func _water_row(iz: int) -> Array:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var y := 0.35
	var sub := int(HCELL / W_COARSE)
	var fine := int(W_COARSE / W_FINE)
	var z0 := -_hhalf + iz * HCELL
	var cv := PackedFloat32Array()
	cv.resize((sub + 1) * (sub + 1))
	var fv := PackedFloat32Array()
	fv.resize((fine + 1) * (fine + 1))
	for ix in _hn:
		var x0 := -_hhalf + ix * HCELL
		if not _cell_has_water(iz * _hn + ix, x0 + HCELL * 0.5, z0 + HCELL * 0.5):
			continue
		# coarse lattice of the cell
		var shallowest := -INF
		for j in sub + 1:
			for i in sub + 1:
				var wd := water_dist(x0 + i * W_COARSE, z0 + j * W_COARSE)
				cv[j * (sub + 1) + i] = wd
				shallowest = maxf(shallowest, wd)
		if shallowest < -90.0:
			# open water all over the cell (the sea, the middle of a wide river): one quad
			_quad(verts, cols, x0, x0 + HCELL, z0, z0 + HCELL, y, -90.0, -90.0, -90.0, -90.0)
			continue
		for j in sub:
			for i in sub:
				var a := cv[j * (sub + 1) + i]
				var b := cv[j * (sub + 1) + i + 1]
				var c := cv[(j + 1) * (sub + 1) + i + 1]
				var d := cv[(j + 1) * (sub + 1) + i]
				var mx := maxf(maxf(a, b), maxf(c, d))
				var mn := minf(minf(a, b), minf(c, d))
				var sx := x0 + i * W_COARSE
				var sz := z0 + j * W_COARSE
				if mx < -W_COARSE * 0.75:
					_quad(verts, cols, sx, sx + W_COARSE, sz, sz + W_COARSE, y, a, b, c, d)
				elif mn < W_COARSE * 0.75:
					# the shore runs through here: a fine lattice and marching squares
					for fj in fine + 1:
						for fi in fine + 1:
							fv[fj * (fine + 1) + fi] = water_dist(sx + fi * W_FINE, sz + fj * W_FINE)
					for fj in fine:
						for fi in fine:
							var o := fj * (fine + 1) + fi
							_cell(verts, cols, sx + fi * W_FINE, sz + fj * W_FINE, W_FINE, y, fv[o], fv[o + 1], fv[o + fine + 2], fv[o + fine + 1])
	return [verts, cols]


static func _shore(d: float) -> Color:
	var s := clampf(-d / 60.0, 0.0, 1.0)
	return Color(s, s, s, 1.0)


## Open-water quads overlap their neighbours a little: quads and the finer shore cells meet in
## T-junctions, which would otherwise show as hairline cracks.
func _quad(verts: PackedVector3Array, cols: PackedColorArray, x0: float, x1: float, z0: float, z1: float, y: float, v0: float, v1: float, v2: float, v3: float) -> void:
	x0 -= 0.3
	x1 += 0.3
	z0 -= 0.3
	z1 += 0.3
	verts.append_array(PackedVector3Array([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]))
	cols.append_array(PackedColorArray([_shore(v0), _shore(v1), _shore(v2), _shore(v0), _shore(v2), _shore(v3)]))


func _cell(verts: PackedVector3Array, cols: PackedColorArray, x0: float, z0: float, s: float, y: float, v0: float, v1: float, v2: float, v3: float) -> void:
	if v0 >= 0.0 and v1 >= 0.0 and v2 >= 0.0 and v3 >= 0.0:
		return
	var v := PackedFloat32Array([v0, v1, v2, v3])
	var p := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + s, z0), Vector2(x0 + s, z0 + s), Vector2(x0, z0 + s)])
	var poly := PackedVector2Array()
	var pd := PackedFloat32Array()
	for k in 4:
		var k2 := (k + 1) % 4
		var a := v[k]
		var b := v[k2]
		if a < 0.0:
			poly.append(p[k])
			pd.append(a)
		if (a < 0.0) != (b < 0.0):
			poly.append(p[k].lerp(p[k2], a / (a - b)))
			pd.append(0.0)
	for k in range(1, poly.size() - 1):
		var q0 := poly[0]
		var q1 := poly[k]
		var q2 := poly[k + 1]
		verts.append(Vector3(q0.x, y, q0.y))
		verts.append(Vector3(q1.x, y, q1.y))
		verts.append(Vector3(q2.x, y, q2.y))
		cols.append(_shore(pd[0]))
		cols.append(_shore(pd[k]))
		cols.append(_shore(pd[k + 1]))


func is_sea(x: float, z: float) -> bool:
	return _has_sea and sea_dist(x, z) < 0.0


# --- Districts ---------------------------------------------------------------------------------------------
## The districts as flat numbers (_df: x, z, cos, sin, block, radius, park, kind id; _dp: street
## half width, avenue half width, avenue period, setback, LED, grid angle) and, for every tile, the
## districts that can be the nearest one somewhere in it.
## The radii in the city files are those of the dense core of a district; grown by this, the
## neighbours meet along their Voronoi border and the city is one piece, as it is.
const DISTRICT_GROW := 1.22


func _gen_districts() -> void:
	var ds: Array = city.districts
	d_kind.clear()
	_df.clear()
	_dp.clear()
	for d in ds:
		var pr := CityGen.profile(String(d[5]))
		d_kind.append(pr)
		var rot := deg_to_rad(float(d[3]))
		_df.append_array(PackedFloat32Array([float(d[1]), float(d[2]), cos(rot), sin(rot), float(d[4]), float(d[6]) * DISTRICT_GROW, float(pr.park), float(CityGen.kind_id(String(d[5])))]))
		_dp.append_array(PackedFloat32Array([float(pr.w), float(pr.aw), float(pr.ap), float(pr.set), float(pr.led), rot, 0.0, 0.0]))
	var cand: Array = []
	cand.resize(tn * tn)
	var reach := TILE * 1.45
	for tz in tn:
		for tx in tn:
			var cx := -half + (tx + 0.5) * TILE
			var cz := -half + (tz + 0.5) * TILE
			var best := INF
			var dist := PackedFloat32Array()
			dist.resize(ds.size())
			for i in ds.size():
				var dd := Vector2(cx - _df[i * 8], cz - _df[i * 8 + 1]).length()
				dist[i] = dd
				best = minf(best, dd)
			var c := PackedInt32Array()
			for i in ds.size():
				if dist[i] <= best + reach:
					c.append(i)
			cand[tz * tn + tx] = c
	var cs := _csr(cand)
	_dc_start = cs[0]
	_dc_items = cs[1]
	# zone areas and woods as flat ellipses: x, z, rx, rz, cos, sin, zone / wobble, 0
	_za.clear()
	for e in city.islands + city.parks:
		var rot := deg_to_rad(float(e[4]) if (e as Array).size() > 4 else 0.0)
		_za.append_array(PackedFloat32Array([float(e[0]), float(e[1]), float(e[2]), float(e[3]), cos(rot), sin(rot), float(e[5]) if (e as Array).size() > 5 else float(Z_FOREST), 0.0]))
	_fa.clear()
	for e in city.forests:
		var rot := deg_to_rad(float(e[4]))
		_fa.append_array(PackedFloat32Array([float(e[0]), float(e[1]), float(e[2]), float(e[3]), cos(rot), sin(rot), float(e[5]), 0.0]))
	_beach = float(city.beach_width)
	_park_thr = float(city.park_threshold)
	city_seed = int(city.seed)


func tile_at(x: float, z: float) -> int:
	var tx := clampi(int(floor((x + half) / TILE)), 0, tn - 1)
	var tz := clampi(int(floor((z + half) / TILE)), 0, tn - 1)
	return tz * tn + tx


## Index of the nearest district seed.
func nearest_district(x: float, z: float) -> int:
	var t := clampi(int(floor((z + half) / TILE)), 0, tn - 1) * tn + clampi(int(floor((x + half) / TILE)), 0, tn - 1)
	var best := 0
	var bd := INF
	for q in range(_dc_start[t], _dc_start[t + 1]):
		var i := _dc_items[q]
		var dx := x - _df[i * 8]
		var dz := z - _df[i * 8 + 1]
		var dd := dx * dx + dz * dz
		if dd < bd:
			bd = dd
			best = i
	return best


# --- Zones ----------------------------------------------------------------------------------------------
## Zone of a point and how built-up it is (0 open country, 1 suburb, 2 city), packed as
## zone + urban * 16. This is the exact rule; zone_at() / urban_at() read its raster.
func classify_full(x: float, z: float) -> int:
	var wd := water_dist(x, z)
	if wd < 0.0:
		return Z_WATER
	var n := noise_at(x, z)
	var zone := -1
	if wd < _hook_reach:
		zone = city.zone_hook(self, x, z, wd, n)
	if zone < 0:
		var o := 0
		while o < _za.size():
			var dx := x - _za[o]
			var dz := z - _za[o + 1]
			var u := (dx * _za[o + 4] + dz * _za[o + 5]) / _za[o + 2]
			var v := (-dx * _za[o + 5] + dz * _za[o + 4]) / _za[o + 3]
			if u * u + v * v < 1.0:
				var iz := int(_za[o + 6])
				zone = Z_SAND if iz == Z_FOREST and wd < 30.0 else iz
				break
			o += 8
	if zone < 0 and _beach > 0.0 and wd < _beach:
		zone = Z_SAND
	if zone < 0:
		var o := 0
		while o < _fa.size():
			var k := 1.0 + n * _fa[o + 6]
			var dx := x - _fa[o]
			var dz := z - _fa[o + 1]
			var u := (dx * _fa[o + 4] + dz * _fa[o + 5]) / (_fa[o + 2] * k)
			var v := (-dx * _fa[o + 5] + dz * _fa[o + 4]) / (_fa[o + 3] * k)
			if u * u + v * v < 1.0:
				zone = Z_FOREST
				break
			o += 8
	if zone >= 0:
		return zone
	# the district: built-up inside its radius, a belt of private houses just beyond it
	var di := nearest_district(x, z) * 8
	var ddx := x - _df[di]
	var ddz := z - _df[di + 1]
	var dd := sqrt(ddx * ddx + ddz * ddz)
	var r := _df[di + 5] * (1.0 + n * 0.2)
	if dd < r:
		var pk := _df[di + 6]
		if pk < 1.0 and _grid(_ng2, _ng2n, NG2_RES, x, z) > _park_thr + pk:
			return Z_FOREST # a small park in the city
		return Z_CITY + 32
	if dd < r * 1.12 + 320.0 and n > -0.35:
		return Z_FIELD + 16
	if noise_at(x * 0.6 + 4000.0, z * 0.6) > 0.22:
		return Z_FOREST
	return Z_FIELD


func classify(x: float, z: float) -> int:
	return classify_full(x, z) & 15


## Cell of the two noise grids, metres.
const NG_RES := 60.0
const NG2_RES := 40.0


## Samples both zone noises over the map (and a margin) into grids.
func _gen_noise() -> void:
	_ngn = int(ceil(_hhalf * 2.0 / NG_RES)) + 2
	_ng.resize(_ngn * _ngn)
	for iz in _ngn:
		var z := -_hhalf + iz * NG_RES
		for ix in _ngn:
			_ng[iz * _ngn + ix] = _noise.get_noise_2d(-_hhalf + ix * NG_RES, z)
	_ng2n = int(ceil(_hhalf * 2.0 / NG2_RES)) + 2
	_ng2.resize(_ng2n * _ng2n)
	for iz in _ng2n:
		var z := -_hhalf + iz * NG2_RES
		for ix in _ng2n:
			_ng2[iz * _ng2n + ix] = _noise2.get_noise_2d(-_hhalf + ix * NG2_RES, z)


func _grid(g: PackedFloat32Array, n: int, res: float, x: float, z: float) -> float:
	var fx := clampf((x + _hhalf) / res, 0.0, n - 1.001)
	var fz := clampf((z + _hhalf) / res, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(g[i], g[i + 1], tx), lerpf(g[i + n], g[i + n + 1], tx), tz)


## The slow zone noise (the wobble of forest and city edges), −1..1.
func noise_at(x: float, z: float) -> float:
	return _grid(_ng, _ngn, NG_RES, x, z)


func zone_at(x: float, z: float) -> int:
	var ix := int((x + half) / zres)
	var iz := int((z + half) / zres)
	if ix < 0 or iz < 0 or ix >= zn or iz >= zn:
		return Z_WATER if is_sea(x, z) else Z_FIELD
	# the raster is coarse: near water the point itself is asked
	var zv := zones[iz * zn + ix]
	var hk := _hash_cell(x, z)
	if zv == Z_WATER or _has_sea or (hk >= 0 and _wc_start[hk + 1] > _wc_start[hk]):
		if water_dist(x, z) < 0.0:
			return Z_WATER
		if zv == Z_WATER:
			return classify(x, z)
	return zv


func urban_at(x: float, z: float) -> int:
	var ix := int((x + half) / zres)
	var iz := int((z + half) / zres)
	if ix < 0 or iz < 0 or ix >= zn or iz >= zn:
		return 0
	return urb[iz * zn + ix]


## Base location type for a map point, or -1 when the base can't be placed there.
func location_at(x: float, z: float) -> int:
	if absf(x) > half - 400.0 or absf(z) > half - 400.0:
		return -1
	var zn2 := classify(x, z)
	var wd := water_dist(x, z)
	if zn2 == Z_WATER or wd < 20.0:
		return -1
	if is_reserved(x, z, 45.0) or road_dist(x, z) < 22.0:
		return -1
	if wd < 260.0:
		return GS.Loc.RIVER
	if zn2 == Z_FOREST:
		var city_hits := 0
		for i in 16:
			var a := TAU * i / 16.0
			if zone_at(x + cos(a) * 350.0, z + sin(a) * 350.0) == Z_CITY:
				city_hits += 1
		return GS.Loc.CITY if city_hits >= 6 else GS.Loc.FOREST
	if zn2 == Z_CITY:
		return GS.Loc.CITY
	return GS.Loc.FIELD


## Keeps a circle free of generated houses and trees (landmarks, bridge heads, squares).
func reserve(x: float, z: float, r: float) -> void:
	_rv.append(Vector3(x, z, r))
	_rv_dirty = true


## The lookup grid over the reserved circles (made again when circles were added since).
func _freeze_reserved() -> void:
	var cells: Array = []
	cells.resize(_hn * _hn)
	for i in _rv.size():
		var rv := _rv[i]
		var reach := rv.z + RES_QUERY
		_hash_add(cells, i, rv.x - reach, rv.y - reach, rv.x + reach, rv.y + reach)
	var cs := _csr(cells)
	_rv_start = cs[0]
	_rv_items = cs[1]
	_rv_dirty = false


## Largest radius is_reserved() may be asked with through the grid.
const RES_QUERY := 70.0


func is_reserved(x: float, z: float, r: float) -> bool:
	if _rv_dirty or r > RES_QUERY:
		# while the landmarks are still being placed (one thread), or a wide query: every circle
		for i in _rv.size():
			var rv := _rv[i]
			var dx := x - rv.x
			var dz := z - rv.y
			var rr := rv.z + r
			if dx * dx + dz * dz < rr * rr:
				return true
		return false
	var k := _hash_cell(x, z)
	if k < 0:
		return false
	for q in range(_rv_start[k], _rv_start[k + 1]):
		var rv := _rv[_rv_items[q]]
		var dx := x - rv.x
		var dz := z - rv.y
		var rr := rv.z + r
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


## True inside a circle cleared for a base.
func is_cleared(x: float, z: float, margin := 0.0) -> bool:
	for i in cleared.size():
		var c := cleared[i]
		var dx := x - c.x
		var dz := z - c.y
		var rr := c.z + margin
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


# --- Avenues & railways ---------------------------------------------------------------------------------
func _gen_route_hash() -> void:
	var rcells: Array = []
	rcells.resize(_hn * _hn)
	var list := []
	for r in city.roads:
		list.append([r.pts, float(r.w) + 1.5])
	for r in city.rails:
		list.append([r.pts, 5.0])
	for item in list:
		var pts: PackedVector2Array = item[0]
		var w: float = item[1]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var si := _rsh.size() / 6
			_rsh.append_array(PackedFloat32Array([a.x, a.y, ab.x, ab.y, 1.0 / maxf(ab.length_squared(), 0.0001), w]))
			var rr := w + RD_REACH
			_hash_add(rcells, si, minf(a.x, b.x) - rr, minf(a.y, b.y) - rr, maxf(a.x, b.x) + rr, maxf(a.y, b.y) + rr)
	var cs := _csr(rcells)
	_rc_start = cs[0]
	_rc_items = cs[1]


## Distance to the edge of the nearest avenue or railway (negative = on it).
func road_dist(x: float, z: float) -> float:
	var ix := int(floor((x + _hhalf) / HCELL))
	var iz := int(floor((z + _hhalf) / HCELL))
	if ix < 0 or iz < 0 or ix >= _hn or iz >= _hn:
		return RD_REACH
	var k := iz * _hn + ix
	var g := RD_REACH
	for q in range(_rc_start[k], _rc_start[k + 1]):
		var o: int = _rc_items[q] * 6
		var ax := _rsh[o]
		var az := _rsh[o + 1]
		var abx := _rsh[o + 2]
		var abz := _rsh[o + 3]
		var t := clampf(((x - ax) * abx + (z - az) * abz) * _rsh[o + 4], 0.0, 1.0)
		var dx := ax + abx * t - x
		var dz := az + abz * t - z
		var d := sqrt(dx * dx + dz * dz) - _rsh[o + 5]
		if d < g:
			g = d
	return g


## A polyline with its running length, so a point at s metres is found by a binary search.
class Line:
	var pts: PackedVector2Array
	var lens := PackedFloat32Array()
	var total := 0.0

	func _init(p: PackedVector2Array) -> void:
		pts = p
		lens.resize(p.size())
		var acc := 0.0
		for i in p.size():
			if i > 0:
				acc += p[i - 1].distance_to(p[i])
			lens[i] = acc
		total = acc

	func at(s: float) -> Vector2:
		var i := clampi(lens.bsearch(s) - 1, 0, pts.size() - 2)
		var l := lens[i + 1] - lens[i]
		return pts[i].lerp(pts[i + 1], clampf((s - lens[i]) / maxf(l, 0.001), 0.0, 1.0))

	func dir(s: float) -> Vector2:
		var i := clampi(lens.bsearch(s) - 1, 0, pts.size() - 2)
		return (pts[i + 1] - pts[i]).normalized()


## Water crossings along a line as [from_s, to_s] including the approach on each bank.
## Crossings with little land between them (a narrow island) become one bridge.
const APPROACH := 60.0
## Water narrower than this is crossed by a low bridge.
const LOW_SPAN := 75.0


func _crossings(ln: Line) -> Array:
	var out := []
	var s := 0.0
	var wet := false
	var start := 0.0
	var step := 6.0
	while s <= ln.total:
		var p := ln.at(s)
		var w := water_dist(p.x, p.y) < 0.0
		if w and not wet:
			start = s
		elif not w and wet and s - start >= 10.0:
			# a small river: a low bridge with short approaches
			var low := s - start < LOW_SPAN
			var ap := 14.0 if low else APPROACH
			var s0 := maxf(start - ap, 0.0)
			var s1 := minf(s + ap, ln.total)
			var join := 60.0 if low else 260.0
			if not out.is_empty() and s0 - float(out[out.size() - 1][1]) < join:
				out[out.size() - 1][1] = s1
				out[out.size() - 1][2] = low and bool(out[out.size() - 1][2]) and s1 - float(out[out.size() - 1][0]) < LOW_SPAN * 2.0
			else:
				out.append([s0, s1, low])
		wet = w
		s += step
	return out


func _gen_routes() -> void:
	var st := {"v": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray()}
	for r in city.roads:
		_build_road(r, st)
	for r in city.rails:
		_build_rail(r, st)
	for b in city.bridges:
		var bd: Dictionary = Landmarks.bridge(self, b.a, b.b, String(b.style), String(b.name), bool(b.get("target", false)))
		built_bridges.append(bd)
		if String(b.style) != "rail" and String(b.style) != "pedestrian":
			road_bridge_fp.append(int(bd.fp))
	var verts: PackedVector3Array = st.v
	if verts.is_empty():
		return
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_TEX_UV] = st.uv
	a[Mesh.ARRAY_COLOR] = st.c
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := Meshes.part(self, am, road_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A ribbon of width 2·w along a line from s0 to s1 (clockwise from above, as the ground). UV: x
## across in metres from the axis, y along in metres. The colour tells the shader what it is:
## r = 1 a highway, 0 a rail bed; g = half width / 32; b = raised (ramps, embankments).
func _ribbon(st: Dictionary, ln: Line, s0: float, s1: float, w: float, y0: float, y1: float, kind: float) -> void:
	var v: PackedVector3Array = st.v
	var uv: PackedVector2Array = st.uv
	var c: PackedColorArray = st.c
	var n := maxi(1, int(ceil((s1 - s0) / 24.0)))
	var col := Color(kind, w / 32.0, 0.0, 1.0)
	var pl := Vector2.ZERO
	var pr := Vector2.ZERO
	var py := 0.0
	var ps := 0.0
	for i in n + 1:
		var s := lerpf(s0, s1, float(i) / n)
		var p := ln.at(s)
		var d := ln.dir(s)
		var side := Vector2(-d.y, d.x) * w
		var l := p - side
		var r := p + side
		var y := lerpf(y0, y1, float(i) / n)
		if i > 0:
			# clockwise seen from above whatever the direction
			var q := [Vector3(pl.x, py, pl.y), Vector3(pr.x, py, pr.y), Vector3(r.x, y, r.y), Vector3(l.x, y, l.y)]
			var t := [Vector2(-w, ps), Vector2(w, ps), Vector2(w, s), Vector2(-w, s)]
			var cross := (pr - pl).x * (r - pl).y - (pr - pl).y * (r - pl).x
			var order := [0, 1, 2, 0, 2, 3] if cross > 0.0 else [0, 3, 2, 0, 2, 1]
			for k in order:
				v.append(q[k])
				uv.append(t[k])
				c.append(col)
		pl = l
		pr = r
		py = y
		ps = s
	st.v = v
	st.uv = uv
	st.c = c


func _build_road(r: Dictionary, st: Dictionary) -> void:
	var ln := Line.new(r.pts)
	var w: float = r.w
	var specs: Array = r.get("bridges", [])
	# one bridge per water crossing, the land runs between them get the asphalt
	var land := []
	var at := 0.0
	var cr := _crossings(ln)
	for k in cr.size():
		var spec: Dictionary = specs[k] if k < specs.size() else {}
		var bd: Dictionary = Landmarks.bridge(self, ln.at(cr[k][0]), ln.at(cr[k][1]), String(spec.get("style", "girder")), String(spec.get("name", "мост")), bool(spec.get("target", false)), w, bool(cr[k][2]))
		built_bridges.append(bd)
		road_bridge_fp.append(int(bd.fp))
		land.append([at, float(cr[k][0])])
		at = float(cr[k][1])
	land.append([at, ln.total])
	for run in land:
		var s0: float = run[0]
		var s1: float = run[1]
		if s1 - s0 < 8.0:
			continue
		_ribbon(st, ln, s0, s1, w, 0.14, 0.14, 1.0)
		# lamps on both kerbs, staggered; the poles come with the detail stream
		var s := s0 + 14.0
		var k := 0
		while s < s1 - 6.0:
			var p := ln.at(s)
			var d := ln.dir(s)
			var side := Vector2(-d.y, d.x)
			var sg := 1.0 if k % 2 == 0 else -1.0
			var q := p + side * sg * (w + 1.6)
			if absf(q.x) < half and absf(q.y) < half:
				add_light(Vector3(q.x, 10.5, q.y), Color(0.9, 0.93, 1.0), false, 1.3, 0.0021)
				var tk := tile_at(q.x, q.y)
				if not road_lamps.has(tk):
					road_lamps[tk] = PackedFloat32Array()
				var rl: PackedFloat32Array = road_lamps[tk]
				rl.append_array(PackedFloat32Array([q.x, 10.5, q.y, atan2(-side.x * sg, -side.y * sg)]))
				road_lamps[tk] = rl
			s += 21.0
			k += 1
		# traffic and pedestrians in runs of a few hundred metres
		var a := s0
		while s1 - a >= 80.0:
			var b := minf(a + 420.0, s1)
			if s1 - b < 80.0:
				b = s1
			var pa := ln.at(a)
			var pb := ln.at(b)
			# a bent run would cut the corner: shorten it until it follows the road
			var mid := ln.at((a + b) * 0.5)
			var tries := 0
			while tries < 4 and ((pa + pb) * 0.5).distance_to(mid) > w * 0.5 and b - a > 100.0:
				b = a + (b - a) * 0.6
				pb = ln.at(b)
				mid = ln.at((a + b) * 0.5)
				tries += 1
			if absf(pa.x) < half and absf(pa.y) < half:
				add_traffic(pa, pb, 1.1, 0.0, w)
				add_people(pa, pb, w + 3.0)
			a = b
		# lit billboards along the highway, on alternating sides
		var bs := s0 + 300.0
		var side_k := 1.0
		while bs < s1 - 100.0:
			var bp := ln.at(bs)
			var bd := ln.dir(bs)
			var nrm := Vector2(-bd.y, bd.x) * side_k
			var q: Vector2 = bp + nrm * (w + 9.0)
			if absf(q.x) < half - 50.0 and absf(q.y) < half - 50.0 and water_dist(q.x, q.y) > 8.0 and not is_reserved(q.x, q.y, 6.0):
				var yaw := atan2(bd.x, bd.y) + PI * 0.5
				add_detail(Vector3(q.x, 6.0, q.y), Vector3(0.6, 12.0, 0.6), 0.0, Color(0.3, 0.3, 0.32))
				add_neon(Vector3(q.x, 14.0, q.y), Vector3(12.0, 5.0, 0.4), -yaw, BILLBOARD[rng.randi() % BILLBOARD.size()])
				add_footprint(q, Vector2(6.0, 0.6), -yaw, 16.6, 2, "рекламный щит")
				reserve(q.x, q.y, 7.0)
			side_k = -side_k
			bs += rng.randf_range(500.0, 900.0)


func _build_rail(r: Dictionary, st: Dictionary) -> void:
	var ln := Line.new(r.pts)
	var spans := _crossings(ln)
	var spec: Dictionary = r.get("bridge", {})
	var decks := PackedFloat32Array()
	var ramps := PackedFloat32Array()
	for sp in spans:
		var bd: Dictionary = Landmarks.bridge(self, ln.at(sp[0]), ln.at(sp[1]), "rail", String(spec.get("name", "железнодорожный мост")), bool(spec.get("target", false)), 12.0, bool(sp[2]))
		built_bridges.append(bd)
		decks.append(float(bd.deck))
		ramps.append(90.0 if bool(sp[2]) else 260.0)
	# height profile: the rail deck on the bridges, long ramps down to the ground
	var track := PackedVector3Array()
	var lens := PackedFloat32Array()
	var s := 0.0
	var prev_s := 0.0
	var prev_y := 0.0
	var first := true
	while true:
		var p := ln.at(s)
		var y := 0.0
		var on_bridge := false
		for k in spans.size():
			var sp: Array = spans[k]
			var d := 0.0
			if s < float(sp[0]):
				d = float(sp[0]) - s
			elif s > float(sp[1]):
				d = s - float(sp[1])
			else:
				on_bridge = true
			y = maxf(y, decks[k] * clampf(1.0 - d / ramps[k], 0.0, 1.0))
		if not first and not on_bridge:
			var yy := maxf(prev_y, y)
			if yy > 0.4:
				# embankment under the ramp
				var a := ln.at(prev_s)
				var mid := (a + p) * 0.5
				add_solid(Vector3(mid.x, yy * 0.5 - 0.1, mid.y), Vector3(8.0, yy, a.distance_to(p) + 0.6), atan2(p.x - a.x, p.y - a.y), Color(0.3, 0.28, 0.26))
			_ribbon(st, ln, prev_s, s, 3.2, 0.1 + prev_y, 0.1 + y, 0.0)
		track.append(Vector3(p.x, y, p.y))
		lens.append(s)
		prev_s = s
		prev_y = y
		first = false
		if s >= ln.total:
			break
		s = minf(s + 24.0, ln.total)
	tracks.append({"pts": track, "len": lens, "trains": int(r.get("trains", 1)), "cars": int(r.get("cars", 7))})


# --- Footprints ----------------------------------------------------------------------------------
func _register(c: Vector2, hs: Vector2, rot: float, h: float, kind: int, fname: String) -> int:
	var i := fp_center.size()
	fp_center.append(Vector3(c.x, h, c.y))
	fp_half.append(hs)
	fp_rot.append(rot)
	fp_kind.append(kind)
	fp_damaged.append(0)
	fp_box.append(Vector2.ZERO)
	fp_crush.append(0.0)
	fp_hidden.append(0)
	fp_style.append(6)
	fp_col.append(Color(0.5, 0.5, 0.5))
	fp_seed.append(0.0)
	fp_bk.append(-1)
	fp_bi.append(-1)
	fp_rk.append(-1)
	fp_ri.append(-1)
	fp_att.append(0)
	fp_att_roof.append(0)
	if fname != "":
		fp_name[i] = fname
	if not _fp_dirty:
		# registered after the lookup grid was built (pylons, things placed at run time)
		_fp_late.append(i)
		var k := clampi(int(floor((c.y + half) / FCELL)), 0, _fn - 1) * _fn + clampi(int(floor((c.x + half) / FCELL)), 0, _fn - 1)
		hmax[k] = maxf(hmax[k], h)
	return i


## Builds the lookup grid over all footprints (two passes: count, then fill).
func _build_fp_index() -> void:
	var cells := _fn * _fn
	var counts := PackedInt32Array()
	counts.resize(cells + 1)
	hmax.fill(0.0)
	var n := fp_center.size()
	var ranges := PackedInt32Array()
	ranges.resize(n * 4)
	for i in n:
		var c := fp_center[i]
		var r := fp_half[i].length()
		var x0 := clampi(int(floor((c.x - r + half) / FCELL)), 0, _fn - 1)
		var x1 := clampi(int(floor((c.x + r + half) / FCELL)), 0, _fn - 1)
		var z0 := clampi(int(floor((c.z - r + half) / FCELL)), 0, _fn - 1)
		var z1 := clampi(int(floor((c.z + r + half) / FCELL)), 0, _fn - 1)
		ranges[i * 4] = x0
		ranges[i * 4 + 1] = x1
		ranges[i * 4 + 2] = z0
		ranges[i * 4 + 3] = z1
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var k := iz * _fn + ix
				counts[k] += 1
				if c.y > hmax[k]:
					hmax[k] = c.y
	_fp_start.resize(cells + 1)
	var acc := 0
	for k in cells:
		_fp_start[k] = acc
		acc += counts[k]
		counts[k] = 0
	_fp_start[cells] = acc
	_fp_items.resize(acc)
	for i in n:
		for iz in range(ranges[i * 4 + 2], ranges[i * 4 + 3] + 1):
			for ix in range(ranges[i * 4], ranges[i * 4 + 1] + 1):
				var k := iz * _fn + ix
				_fp_items[_fp_start[k] + counts[k]] = i
				counts[k] += 1
	_fp_late.clear()
	_fp_dirty = false


## A visible building (unit cube scaled + rotated) with an optional pitched roof.
func add_building(c: Vector2, hs: Vector2, rot: float, h: float, style: int, col: Color, kind := 0, roof_h := 0.0, roof_col := Color(0.45, 0.2, 0.15), fname := "") -> int:
	var seed := rng.randf()
	var basis := Basis(Vector3.UP, -rot) * Basis.from_scale(Vector3(hs.x * 2.0, h, hs.y * 2.0))
	var ref := b_build.add(Transform3D(basis, Vector3(c.x, h * 0.5, c.y)), col, Color(0.0, seed, style / 10.0, 0.0))
	var i := _register(c, hs, rot, h + roof_h * 0.6, kind, fname)
	fp_box[i] = Vector2(h, roof_h)
	fp_style[i] = style
	fp_col[i] = col
	fp_seed[i] = seed
	fp_bk[i] = ref.x
	fp_bi[i] = ref.y
	if roof_h > 0.0:
		var rb: Basis
		if hs.x > hs.y:
			rb = Basis(Vector3.UP, -rot + PI * 0.5) * Basis.from_scale(Vector3(hs.y * 2.0, roof_h, hs.x * 2.0))
		else:
			rb = Basis(Vector3.UP, -rot) * Basis.from_scale(Vector3(hs.x * 2.0, roof_h, hs.y * 2.0))
		var roof := b_roof.add(Transform3D(rb, Vector3(c.x, h + roof_h * 0.5, c.y)), roof_col, Color(0.0, rng.randf(), 0.7, 0.0))
		fp_rk[i] = roof.x
		fp_ri[i] = roof.y
	return i


## Invisible footprint for individually modelled landmarks.
func add_footprint(c: Vector2, hs: Vector2, rot: float, h: float, kind := 2, fname := "") -> int:
	return _register(c, hs, rot, h, kind, fname)


## Decorative box using the building shader (no collision), e.g. rooftop machine rooms.
func add_prop_box(center: Vector3, size: Vector3, rot: float, col: Color, style := 6) -> Vector2i:
	var basis := Basis(Vector3.UP, -rot) * Basis.from_scale(size)
	return b_build.add(Transform3D(basis, center), col, Color(0.0, rng.randf(), style / 10.0, 0.0))


func add_solid(center: Vector3, size: Vector3, rot: float, col: Color) -> void:
	b_props.add(Transform3D(Basis(Vector3.UP, -rot) * Basis.from_scale(size), center), col)


func add_cyl(base: Vector3, r: float, h: float, col: Color) -> Vector2i:
	return b_cyl.add(Transform3D(Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), base + Vector3(0, h * 0.5, 0)), col)


## A small unlit prop box (pylons, sign posts …).
func add_detail(center: Vector3, size: Vector3, rot: float, col: Color) -> Vector2i:
	return b_detail.add(Transform3D(Basis(Vector3.UP, -rot) * Basis.from_scale(size), center), col)


## A glowing sign / shop front / neon strip.
func add_neon(center: Vector3, size: Vector3, rot: float, col: Color) -> Vector2i:
	return b_neon.add(Transform3D(Basis(Vector3.UP, -rot) * Basis.from_scale(size), center), col)


## Smoke rising from a chimney top (a limited number per city).
func add_smoke(top: Vector3, dark := true) -> void:
	if smoke_budget <= 0:
		return
	smoke_budget -= 1
	var sm := CPUParticles3D.new()
	sm.mesh = Fx.sphere(1.0, 6)
	sm.material_override = Fx.smoke_mat()
	sm.amount = 18
	sm.lifetime = 14.0
	sm.direction = Vector3.UP
	sm.spread = 10.0
	sm.initial_velocity_min = 4.0
	sm.initial_velocity_max = 7.0
	sm.gravity = Vector3(2.2, 0.6, 0.8)
	sm.scale_amount_min = 5.0
	sm.scale_amount_max = 13.0
	var g := Gradient.new()
	g.set_color(0, Color(0.45, 0.43, 0.42, 0.45) if dark else Color(0.8, 0.8, 0.82, 0.35))
	g.set_color(1, Color(0.4, 0.4, 0.42, 0.0))
	sm.color_ramp = g
	sm.position = top
	sm.visibility_range_end = 6000.0
	add_child(sm)


func add_light(pos: Vector3, col: Color, blink := false, base := 1.0, k := 0.0025) -> void:
	b_lights.add(Transform3D(Basis(), pos), col, Color(rng.randf(), 1.0 if blink else 0.0, base, k))


## Two opposite streams of car lights between a and b (`w` = half width of the carriageway).
func add_traffic(a: Vector2, b: Vector2, density := 1.0, y := 0.0, w := 7.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 40.0:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var lanes_n := 1 if w < 8.0 else (2 if w < 13.0 else 3)
	for lane in lanes_n * 2:
		var fwd := lane % 2 == 0
		var from := a if fwd else b
		var to_dir := dir if fwd else -dir
		var off := side * ((1.9 + (lane / 2) * 3.4) * (1.0 if fwd else -1.0))
		var basis := Basis.looking_at(Vector3(to_dir.x, 0, to_dir.y), Vector3.UP)
		var col := Color(1.0, 0.93, 0.78) if fwd else Color(1.0, 0.12, 0.07)
		var n := maxi(1, int(length / 85.0 * density))
		for i in n:
			var o := from + off
			var xf := Transform3D(basis, Vector3(o.x, y, o.y))
			var cd := Color(rng.randf_range(12.0, 19.0), length, rng.randf(), 0.0)
			b_traffic.add(xf, col, cd)
			b_cars.add(xf, CAR_PAINT[rng.randi() % CAR_PAINT.size()], cd)


## Pedestrians walking both ways along the sidewalks of a street segment.
func add_people(a: Vector2, b: Vector2, sidewalk: float, y := 0.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 30.0:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	for s in [-1.0, 1.0]:
		var n := int(length / 60.0)
		for i in n:
			var fwd := rng.randf() < 0.5
			var start: Vector2 = a if fwd else b
			var from: Vector2 = start + side * float(s) * (sidewalk + rng.randf_range(-0.8, 0.8))
			var to_dir: Vector2 = dir if fwd else -dir
			var basis := Basis.looking_at(Vector3(to_dir.x, 0, to_dir.y), Vector3.UP)
			var cd := Color(rng.randf_range(1.1, 1.8), length, rng.randf(), rng.randf())
			b_people.add(Transform3D(basis, Vector3(from.x, y, from.y)), CLOTHES[rng.randi() % CLOTHES.size()], cd)


## Bridge decks are walkable surfaces for the pedestrian view.
func is_deck(i: int) -> bool:
	return String(fp_name.get(i, "")).to_lower().contains("мост")


func building_at(x: float, z: float) -> int:
	if _fp_dirty:
		_build_fp_index()
	var ix := int(floor((x + half) / FCELL))
	var iz := int(floor((z + half) / FCELL))
	if ix < 0 or iz < 0 or ix >= _fn or iz >= _fn:
		return -1
	var k := iz * _fn + ix
	var best := -1
	var best_h := -1.0
	var q0 := _fp_start[k]
	var q1 := _fp_start[k + 1]
	for q in range(q0, q1 + _fp_late.size()):
		var i := _fp_items[q] if q < q1 else _fp_late[q - q1]
		if fp_hidden[i] == 1:
			continue
		var c := fp_center[i]
		var dx := x - c.x
		var dz := z - c.z
		var hs := fp_half[i]
		if absf(dx) > hs.x + hs.y or absf(dz) > hs.x + hs.y:
			continue
		var ca := cos(fp_rot[i])
		var sa := sin(fp_rot[i])
		var lx := dx * ca + dz * sa
		var lz := -dx * sa + dz * ca
		if absf(lx) <= hs.x and absf(lz) <= hs.y and c.y > best_h:
			best = i
			best_h = c.y
	return best


func ground_height(x: float, z: float) -> float:
	var bi := building_at(x, z)
	return fp_center[bi].y if bi >= 0 else 0.0


## Highest roof in the 3×3 cells around a point (for terrain-following flight).
func ceiling(x: float, z: float) -> float:
	var ix := int(floor((x + half) / FCELL))
	var iz := int(floor((z + half) / FCELL))
	var m := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx := ix + dx
			var cz := iz + dz
			if cx >= 0 and cz >= 0 and cx < _fn and cz < _fn:
				m = maxf(m, hmax[cz * _fn + cx])
	return m


## Road bridge decks: the only way across the water for anything that drives.
func bridge_points() -> Array:
	var out := []
	for i in road_bridge_fp:
		out.append(fp_center[int(i)])
	return out


func is_bridge(i: int) -> bool:
	return i >= 0 and String(fp_name.get(i, "")).to_lower().contains("мост")


## Name of the district a point falls in — used by the highlight reel captions.
func district_name(x: float, z: float) -> String:
	return String(city.districts[nearest_district(x, z)][0])


func building_kind(i: int) -> int:
	return fp_kind[i]


func building_name(i: int) -> String:
	return GS.t(String(fp_name.get(i, GS.KIND_NAME[fp_kind[i]])))


# --- Tiles: the generated buildings ------------------------------------------------------------------------
func _gen_tiles() -> void:
	var n := tn * tn
	_tile_out.resize(n)
	tile_fp0.resize(n)
	tile_fpn.resize(n)
	tile_blocks.resize(n)
	var gid := WorkerThreadPool.add_group_task(func(t: int) -> void: _tile_out[t] = CityGen.tile_buildings(self, t), n, _threads(), true, "UAD tiles")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for t in n:
		var o: CityGen.TileOut = _tile_out[t]
		tile_fp0[t] = fp_center.size()
		tile_fpn[t] = 0
		if o == null:
			continue
		tile_blocks[t] = o.blocks
		var cnt := o.centers.size()
		if cnt == 0 and o.churches.is_empty():
			continue
		var tx := t % tn
		var tz := t / tn
		var key := b_build.key_at(-half + (tx + 0.5) * TILE, -half + (tz + 0.5) * TILE)
		var base := fp_center.size()
		var bb := b_build.adopt(key, o.build_buf)
		var rb := b_roof.adopt(key, o.roof_buf)
		fp_center.append_array(o.centers)
		fp_half.append_array(o.halfs)
		fp_rot.append_array(o.rots)
		fp_kind.append_array(o.kinds)
		fp_box.append_array(o.boxes)
		fp_style.append_array(o.styles)
		fp_col.append_array(o.cols)
		fp_seed.append_array(o.seeds)
		fp_att.append_array(o.atts)
		fp_att_roof.append_array(o.att_roofs)
		var zeros := PackedByteArray()
		zeros.resize(cnt)
		fp_damaged.append_array(zeros)
		fp_hidden.append_array(zeros)
		var zf := PackedFloat32Array()
		zf.resize(cnt)
		fp_crush.append_array(zf)
		for i in cnt:
			var bi := o.build_i[i]
			fp_bk.append(key if bi >= 0 else -1)
			fp_bi.append(bb + bi if bi >= 0 else -1)
			var ri := o.roof_i[i]
			fp_rk.append(key if ri >= 0 else -1)
			fp_ri.append(rb + ri if ri >= 0 else -1)
		for li in o.names:
			fp_name[base + int(li)] = o.names[li]
		tile_fpn[t] = cnt
		# far-visible extras of the tile: warning lights, chimneys, container stacks
		var lb := o.lights_buf
		for i in lb.size() / Batch.STRIDE:
			var q := i * Batch.STRIDE
			b_lights.add(Transform3D(Basis(), Vector3(lb[q + 3], lb[q + 7], lb[q + 11])), Color(lb[q + 12], lb[q + 13], lb[q + 14]), Color(lb[q + 16], lb[q + 17], lb[q + 18], lb[q + 19]))
		for pair in [[o.cyl_buf, b_cyl], [o.prop_buf, b_props]]:
			var buf: PackedFloat32Array = pair[0]
			for i in buf.size() / Batch.STRIDE:
				var q := i * Batch.STRIDE
				(pair[1] as Batch).add(Batch._xf_at(buf, q), Color(buf[q + 12], buf[q + 13], buf[q + 14]))
		for ch in o.churches:
			Landmarks.small_church(self, ch[0], ch[1], rng, false)
		for sp in o.smokes:
			add_smoke(sp)
	_tile_out.clear()
	_fp_dirty = true


func damage_building(i: int) -> bool:
	if fp_damaged[i] == 1:
		return false
	fp_damaged[i] = 1
	_show_damage(i, 1.0)
	return true


func _show_damage(i: int, v: float) -> void:
	if fp_bk[i] >= 0:
		var ref := Vector2i(fp_bk[i], fp_bi[i])
		var cd := b_build.get_custom(ref)
		b_build.set_custom(ref, Color(v, cd.g, cd.b, cd.a))
	if fp_rk[i] >= 0:
		var roof := Vector2i(fp_rk[i], fp_ri[i])
		var rc := b_roof.get_custom(roof)
		b_roof.set_custom(roof, Color(v, rc.g, rc.b, rc.a))


## A building never comes down completely: the lower floors and the walls stay standing.
const CRUSH_MAX := 0.55


## Takes `amount` (0..1 of the original height) off a building: the upper floors collapse,
## a pitched roof is gone with them. Returns how many metres came down (0 = nothing moved).
func crush_building(i: int, amount: float) -> float:
	if i < 0 or i >= fp_crush.size() or fp_box[i].x <= 0.0 or fp_bk[i] < 0:
		return 0.0
	var before: float = fp_crush[i]
	var after: float = minf(CRUSH_MAX, before + amount)
	if after - before < 0.01:
		return 0.0
	fp_crush[i] = after
	_apply_crush(i)
	return fp_box[i].x * (after - before)


## Rebuilds part of a collapsed building (the repair crews work gradually).
## Returns true once it stands at its full height again.
func repair_building(i: int, amount := 1.0) -> bool:
	if i < 0 or i >= fp_crush.size():
		return true
	if fp_crush[i] > 0.0:
		fp_crush[i] = maxf(0.0, fp_crush[i] - amount)
		_apply_crush(i)
	if fp_crush[i] > 0.0:
		return false
	undamage_building(i)
	return true


## Scale the box down to the height that is left and drop the roof cap with it.
func _apply_crush(i: int) -> void:
	if fp_bk[i] < 0:
		return
	var ref := Vector2i(fp_bk[i], fp_bi[i])
	var c: Vector3 = fp_center[i]
	var hs: Vector2 = fp_half[i]
	var box: Vector2 = fp_box[i]
	var crush: float = fp_crush[i]
	var h: float = box.x * (1.0 - crush)
	var basis := Basis(Vector3.UP, -fp_rot[i]) * Basis.from_scale(Vector3(hs.x * 2.0, h, hs.y * 2.0))
	b_build.set_xform(ref, Transform3D(basis, Vector3(c.x, h * 0.5, c.z)))
	if fp_rk[i] >= 0:
		var roof := Vector2i(fp_rk[i], fp_ri[i])
		if crush > 0.01:
			b_roof.hide(roof)
		else:
			b_roof.unhide(roof)
	# the pieces glued to the box follow it in the batch
	for a in int(fp_att[i]):
		var ar := Vector2i(ref.x, ref.y + 1 + a)
		if int(fp_att_roof[i]) & (1 << a):
			if crush > 0.01:
				b_build.hide(ar)
			else:
				b_build.unhide(ar)
		else:
			# a wall piece standing on the ground keeps its foot and loses its top with the floors
			var xf := b_build.get_xform(ar)
			var sc := xf.basis.get_scale()
			var foot := xf.origin.y - sc.y * 0.5
			var nh := maxf(0.2, minf(sc.y, h - foot))
			var nb := xf.basis.orthonormalized() * Basis.from_scale(Vector3(sc.x, nh, sc.z))
			if b_build.mms.has(ar.x):
				(b_build.mms[ar.x] as MultiMesh).set_instance_transform(ar.y, Transform3D(nb, Vector3(xf.origin.x, foot + nh * 0.5, xf.origin.z)))
	fp_center[i] = Vector3(c.x, h + (0.0 if crush > 0.01 else box.y * 0.6), c.z)
	if stream != null:
		stream.refresh_at(c.x, c.z)


func crush_of(i: int) -> float:
	return fp_crush[i] if i >= 0 and i < fp_crush.size() else 0.0


## Soot and boarded-up windows go away when the building is repaired.
func undamage_building(i: int) -> void:
	if i < 0 or i >= fp_damaged.size() or fp_damaged[i] == 0:
		return
	fp_damaged[i] = 0
	_show_damage(i, 0.0)


func damaged_list() -> Array:
	var out := []
	for i in fp_damaged.size():
		if fp_damaged[i] == 1:
			out.append(i)
	return out


## Collapsed buildings for the save file: [index, percent] pairs.
func crushed_list() -> Array:
	var out := []
	for i in fp_crush.size():
		if fp_crush[i] > 0.0:
			out.append([i, int(round(fp_crush[i] * 100.0))])
	return out


func apply_crush_list(list: Array) -> void:
	for v in list:
		if v is Array and (v as Array).size() == 2:
			var i := int(v[0])
			if i >= 0 and i < fp_crush.size() and fp_box[i].x > 0.0 and fp_bk[i] >= 0:
				fp_crush[i] = clampf(float(v[1]) * 0.01, 0.0, CRUSH_MAX)
				_apply_crush(i)


## Multiplayer guest: makes the buildings exactly what the host has — sooty roofs `damaged`
## (indices) and collapsed floors `crushed` ([index, percent]). Returns [index, height lost] for
## the buildings that came down further since the last state (the game shows them collapse).
func sync_damage(damaged: Array, crushed: Array) -> Array:
	var want_d := {}
	for v in damaged:
		want_d[int(v)] = true
	for i in damaged_list():
		if not want_d.has(i):
			undamage_building(i)
	for i in want_d:
		if i >= 0 and i < fp_damaged.size():
			damage_building(i)
	var want_c := {}
	for v in crushed:
		if v is Array and (v as Array).size() == 2:
			want_c[int(v[0])] = clampf(float(v[1]) * 0.01, 0.0, CRUSH_MAX)
	var fell := []
	var check := {}
	for i in want_c:
		check[i] = true
	for v in crushed_list():
		check[int(v[0])] = true
	for i in check:
		if i < 0 or i >= fp_crush.size():
			continue
		var w := float(want_c.get(i, 0.0))
		if absf(fp_crush[i] - w) < 0.005 or fp_box[i].x <= 0.0 or fp_bk[i] < 0:
			continue
		if w > fp_crush[i]:
			fell.append([i, fp_box[i].x * (w - fp_crush[i])])
		fp_crush[i] = w
		_apply_crush(i)
	return fell


## Multiplayer guest: the host's blackouts (x, z, radius, 1).
func set_blackouts(list: Array) -> void:
	blackouts.clear()
	for v in list:
		blackouts.append(v)
	_update_blackouts()


func apply_damage_list(list: Array) -> void:
	for v in list:
		var i := int(v)
		if i >= 0 and i < fp_damaged.size():
			damage_building(i)


func reset_damage() -> void:
	for v in crushed_list():
		var i := int(v[0])
		fp_crush[i] = 0.0
		_apply_crush(i)
	for i in damaged_list():
		undamage_building(i)


## Removes buildings, trees and props under the player's base footprint.
func clear_area(c: Vector3, r: float) -> void:
	restore_area()
	cleared.append(Vector3(c.x, c.z, r + 8.0))
	for b in [b_build, b_roof, b_props, b_cyl, b_lights, b_detail, b_neon]:
		for ref in (b as Batch).refs_near(c, r + 8.0):
			(b as Batch).hide(ref)
			_hidden.append([b, ref])
	var f := int(ceil((r + 60.0) / FCELL))
	var ix0 := int(floor((c.x + half) / FCELL))
	var iz0 := int(floor((c.z + half) / FCELL))
	if _fp_dirty:
		_build_fp_index()
	for iz in range(maxi(0, iz0 - f), mini(_fn - 1, iz0 + f) + 1):
		for ix in range(maxi(0, ix0 - f), mini(_fn - 1, ix0 + f) + 1):
			var k := iz * _fn + ix
			for q in range(_fp_start[k], _fp_start[k + 1]):
				var i := _fp_items[q]
				if fp_hidden[i] == 0 and Vector2(fp_center[i].x - c.x, fp_center[i].z - c.z).length() < r + 8.0:
					fp_hidden[i] = 1
					_hidden_fp.append(i)
	if stream != null:
		stream.refresh_at(c.x, c.z, r + 60.0)


func restore_area() -> void:
	for h in _hidden:
		(h[0] as Batch).unhide(h[1])
	for i in _hidden_fp:
		fp_hidden[i] = 0
	_hidden.clear()
	_hidden_fp.clear()
	var old := cleared
	cleared = PackedVector3Array()
	if stream != null:
		for c in old:
			stream.refresh_at(c.x, c.y, c.z + 60.0)


## Nearest point to `p` where a base of the given type can stand (or of any type when there is none
## close by) — older saves may have their base where the reworked map now has water or a highway.
func nearest_base_spot(p: Vector3, loc: int) -> Vector3:
	if location_at(p.x, p.z) >= 0:
		return p
	var fallback := Vector3.INF
	var r := 40.0
	while r < 9000.0:
		var steps := maxi(8, int(TAU * r / 60.0))
		for i in steps:
			var a := TAU * i / steps
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			var l := location_at(q.x, q.z)
			if l == loc:
				return q
			if l >= 0 and fallback == Vector3.INF:
				fallback = q
		if fallback != Vector3.INF and r > 600.0:
			return fallback
		r += 40.0 if r < 800.0 else 150.0
	return fallback if fallback != Vector3.INF else p


func set_labels_visible(v: bool) -> void:
	_labels.visible = v


# --- Blackouts (power plant hit → district goes dark) -----------------------------------------
func add_blackout(p: Vector3, r: float) -> void:
	blackouts.append(Vector4(p.x, p.z, r, 1.0))
	while blackouts.size() > 4:
		blackouts.pop_front()
	_update_blackouts()


func clear_blackouts() -> void:
	blackouts.clear()
	_update_blackouts()


func _update_blackouts() -> void:
	var arr := PackedVector4Array()
	for i in 4:
		arr.append(blackouts[i] if i < blackouts.size() else Vector4(0, 0, 0, 0))
	for m in [build_mat, lights_mat, traffic_mat, _ground_mat, neon_mat, road_mat]:
		(m as ShaderMaterial).set_shader_parameter("blackouts", arr)
	if stream != null:
		stream.set_blackouts(arr)


# --- Generation ----------------------------------------------------------------------------------
## The zone raster: every row is classified on a worker thread.
func _gen_zones() -> void:
	zones.resize(zn * zn)
	urb.resize(zn * zn)
	var rows: Array = []
	rows.resize(zn)
	var gid := WorkerThreadPool.add_group_task(func(iz: int) -> void: rows[iz] = _zone_row(iz), zn, _threads(), true, "UAD zones")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	zones.clear()
	urb.clear()
	_zone_rows_d.clear()
	for iz in zn:
		var r: Array = rows[iz]
		zones.append_array(r[0])
		urb.append_array(r[1])
		_zone_rows_d.append(r[2])


func _zone_row(iz: int) -> Array:
	var zr := PackedByteArray()
	var ur := PackedByteArray()
	var dr := PackedByteArray()
	zr.resize(zn)
	ur.resize(zn)
	dr.resize(zn)
	var z := -half + (iz + 0.5) * zres
	for ix in zn:
		var x := -half + (ix + 0.5) * zres
		var f := classify_full(x, z)
		zr[ix] = f & 15
		ur[ix] = f >> 4
		dr[ix] = nearest_district(x, z)
	return [zr, ur, dr]


## The district of every raster cell, row by row (only kept until the ground texture is made).
var _zone_rows_d: Array = []


func _gen_ground() -> void:
	# what the ground shader reads: zone, how built-up, the district (nearest texel; the shader
	# smooths the borders itself)
	var data := PackedByteArray()
	data.resize(zn * zn * 4)
	var o := 0
	for iz in zn:
		var dr: PackedByteArray = _zone_rows_d[iz]
		for ix in zn:
			var i := iz * zn + ix
			data[o] = zones[i] * 51
			data[o + 1] = urb[i] * 127
			data[o + 2] = dr[ix]
			data[o + 3] = 255
			o += 4
	_zone_rows_d.clear()
	var img := Image.create_from_data(zn, zn, false, Image.FORMAT_RGBA8, data)
	_ground_mat = Shaders.material(Shaders.GROUND)
	_ground_mat.set_shader_parameter("info_tex", ImageTexture.create_from_image(img))
	_ground_mat.set_shader_parameter("half_size", half)
	_ground_mat.set_shader_parameter("zn", float(zn))
	var da := PackedVector4Array()
	var db := PackedVector4Array()
	for i in city.districts.size():
		var d: Array = city.districts[i]
		var pr: Dictionary = d_kind[i]
		da.append(Vector4(d[1], d[2], deg_to_rad(d[3]), d[4]))
		db.append(Vector4(pr.w, pr.aw, pr.ap, pr.led))
	while da.size() < Shaders.MAX_DISTRICTS:
		da.append(Vector4(99999, 99999, 0, 150))
		db.append(Vector4(4, 9, 3, 0))
	_ground_mat.set_shader_parameter("district_a", da)
	_ground_mat.set_shader_parameter("district_b", db)
	_ground_mat.set_shader_parameter("district_count", city.districts.size())
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	var gmi := Meshes.part(self, pm, _ground_mat)
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen_outer()


## The country beyond the map out to the horizon (Shaders.OUTER): fields, woods and villages, and
## the highways, railways and rivers of the map carried on from where they leave it.
func _gen_outer() -> void:
	var exits := PackedVector4Array()
	var dirs := PackedVector4Array()
	var add_exit := func(a: Vector2, b: Vector2, kind: int, w: float) -> void:
		# b is the end of a line, a the point before it: does the line run off the map there?
		if maxf(absf(b.x), absf(b.y)) < half * 0.9 or exits.size() >= 24:
			return
		var d := (b - a).normalized()
		if d == Vector2.ZERO:
			return
		exits.append(Vector4(b.x, b.y, kind, w))
		dirs.append(Vector4(d.x, d.y, float(exits.size()) * 1.7, 0.0))
	for r in city.rivers:
		var pts: PackedVector2Array = r.pts
		var ws: PackedFloat32Array = r.get("w", PackedFloat32Array())
		if pts.size() >= 2:
			add_exit.call(pts[1], pts[0], 2, ws[0] if ws.size() > 0 else 40.0)
			add_exit.call(pts[pts.size() - 2], pts[pts.size() - 1], 2, ws[ws.size() - 1] if ws.size() > 0 else 40.0)
	for r in city.roads:
		var pts: PackedVector2Array = r.pts
		if pts.size() >= 2:
			add_exit.call(pts[1], pts[0], 0, float(r.w))
			add_exit.call(pts[pts.size() - 2], pts[pts.size() - 1], 0, float(r.w))
	for r in city.rails:
		var pts: PackedVector2Array = r.pts
		if pts.size() >= 2:
			add_exit.call(pts[1], pts[0], 1, 3.0)
			add_exit.call(pts[pts.size() - 2], pts[pts.size() - 1], 1, 3.0)
	_outer_mat = Shaders.material(Shaders.OUTER)
	var count := exits.size()
	while exits.size() < 24:
		exits.append(Vector4(999999, 999999, 0, 0))
		dirs.append(Vector4(1, 0, 0, 0))
	_outer_mat.set_shader_parameter("exits", exits)
	_outer_mat.set_shader_parameter("exit_dirs", dirs)
	_outer_mat.set_shader_parameter("exit_count", count)
	_outer_mat.set_shader_parameter("map_half", half)
	var os: Array = city.outer_sea
	if os.size() >= 8:
		_outer_mat.set_shader_parameter("sea_a", Vector4(os[0], os[1], os[2], os[3]))
		_outer_mat.set_shader_parameter("sea_b", Vector4(os[4], os[5], os[6], os[7]))
		_outer_mat.set_shader_parameter("sea_on", 1.0)
	# a ring around the map, not a plane under it: two surfaces close together all over the city
	# would fight for the depth buffer. The ring tucks under the map's edge, so no seam can open.
	var R := OUTER_R
	var h := half - 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# subdivided: huge triangles lose precision in the vertex interpolation
	var cuts := [-R, -R * 0.45, -half * 1.6, -h, 0.0, h, half * 1.6, R * 0.45, R]
	for j in cuts.size() - 1:
		for i in cuts.size() - 1:
			var x0: float = cuts[i]
			var x1: float = cuts[i + 1]
			var z0: float = cuts[j]
			var z1: float = cuts[j + 1]
			if x0 >= -h and x1 <= h and z0 >= -h and z1 <= h:
				continue # the map itself
			for v in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]:
				st.add_vertex(v)
	var outer := st.commit()
	var mi := Meshes.part(self, outer, _outer_mat, Vector3(0, -0.6, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## How far the land beyond the map is drawn (the horizon from a few kilometres up).
const OUTER_R := 150000.0


## High-voltage lines leave every power plant for the edge of the map: lattice pylons with three
## sagging wires, skipped over houses, water and highways.
func _gen_power_lines() -> void:
	var steel := Color(0.5, 0.52, 0.55)
	var wire := Fx.solid(Color(0.25, 0.26, 0.28), 0.6, 0.5)
	var wires := Node3D.new()
	wires.name = "PowerLines"
	add_child(wires)
	for t in targets:
		if String(t.get("kind", "")) != "tpp":
			continue
		var c := Vector2(t.pos.x, t.pos.z)
		var a0 := rng.randf() * TAU
		for k in 2:
			var dir := Vector2.from_angle(a0 + k * (PI * 0.7 + rng.randf() * 0.6))
			var prev := Vector3.INF
			var d := 320.0
			while d < 9000.0:
				var p := c + dir * d
				d += 280.0
				if absf(p.x) > half - 60.0 or absf(p.y) > half - 60.0:
					break
				if water_dist(p.x, p.y) < 10.0 or road_dist(p.x, p.y) < 6.0 or building_at(p.x, p.y) >= 0 or is_reserved(p.x, p.y, 8.0):
					prev = Vector3.INF
					continue
				var h := 42.0
				for s in [-1.0, 1.0]:
					var q: Vector2 = p + Vector2(-dir.y, dir.x) * s * 3.4
					add_detail(Vector3(q.x, h * 0.5, q.y), Vector3(0.7, h, 0.7), 0.0, steel)
				var rot := atan2(dir.y, dir.x)
				add_detail(Vector3(p.x, h - 2.0, p.y), Vector3(0.5, 0.5, 18.0), -rot + PI * 0.5, steel)
				add_detail(Vector3(p.x, h - 9.0, p.y), Vector3(0.5, 0.5, 13.0), -rot + PI * 0.5, steel)
				add_footprint(p, Vector2(4, 4), 0.0, h, 1, "опора ЛЭП")
				add_light(Vector3(p.x, h + 1.0, p.y), Color(1.0, 0.08, 0.05), true, 1.1, 0.004)
				var top := Vector3(p.x, h - 2.3, p.y)
				if prev != Vector3.INF:
					var side := Vector3(-dir.y, 0, dir.x)
					for w in [-7.5, 0.0, 7.5]:
						var a: Vector3 = prev + side * w
						var b: Vector3 = top + side * w
						var pts := [a]
						for q in range(1, 6):
							var u := q / 6.0
							pts.append(a.lerp(b, u) - Vector3(0, 9.0 * 4.0 * u * (1.0 - u), 0))
						pts.append(b)
						for q in pts.size() - 1:
							var mi := MeshInstance3D.new()
							mi.mesh = Fx.cube(Vector3(0.14, 0.14, 1.0))
							mi.material_override = wire
							mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
							var sa: Vector3 = pts[q]
							var sb: Vector3 = pts[q + 1]
							mi.transform = Transform3D(Basis.looking_at((sb - sa).normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, sa.distance_to(sb))), (sa + sb) * 0.5)
							mi.visibility_range_end = 2500.0
							wires.add_child(mi)
				prev = top


func _gen_labels() -> void:
	_labels = Node3D.new()
	add_child(_labels)
	for l in city.labels:
		_label(String(l[0]), l[1], l[3] if (l as Array).size() > 3 else Color(0.8, 1.0, 0.9, 0.85), int(l[2]))
	for d in city.districts:
		_label(String(d[0]), Vector3(d[1], 70, d[2]), Color(0.8, 1.0, 0.9, 0.85), 56)
	for t in targets:
		_label(String(t.name), t.pos + Vector3(0, 160, 0), Color(1.0, 0.55, 0.4, 0.9), 40, "◎ ")
	GS.language_changed.connect(refresh_labels)


func refresh_labels() -> void:
	for l in _labels.get_children():
		(l as Label3D).text = String(l.get_meta("prefix", "")) + GS.t(String(l.get_meta("key", "")))


func _label(text: String, pos: Vector3, color: Color, size: int, prefix := "") -> void:
	var l := Label3D.new()
	l.set_meta("key", text)
	l.set_meta("prefix", prefix)
	l.text = prefix + GS.t(text)
	l.font = GS.font
	l.font_size = size
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	# captions keep their size on the screen, whatever the height of the map camera
	l.fixed_size = true
	l.pixel_size = 0.00042
	l.position = pos
	_labels.add_child(l)


# --- Environment ------------------------------------------------------------------------------
func _setup_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = Shaders.material(Shaders.SKY)
	sky.sky_material = _sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.fog_enabled = true
	# the sky draws its own horizon in the fog colour: the fog must not tint it again
	env.fog_sky_affect = 0.0
	_sky_mat.set_shader_parameter("sun_dir", _toward_light(SUN_DAY))
	_sky_mat.set_shader_parameter("moon_dir", _toward_light(SUN_NIGHT))
	_sky_mat.set_shader_parameter("cloud_cover", 0.3 + 0.3 * float(city.seed % 7) / 6.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_max_distance = 1400.0
	add_child(_sun)


## Where the directional light comes from (the sun by day, the moon by night): its rotation in
## degrees, and the unit vector pointing back at it for the sky.
const SUN_DAY := Vector3(-52, -35, 0)
const SUN_NIGHT := Vector3(-38, 155, 0)
## Haze on the horizon: day blue-grey, night the orange-brown of the city lights. Fog and sky
## share it, so the far land fades into the sky without a seam.
const HAZE_DAY := Color(0.7, 0.77, 0.85)
const HAZE_NIGHT := Color(0.095, 0.075, 0.082)


static func _toward_light(rot_deg: Vector3) -> Vector3:
	return Basis.from_euler(rot_deg * (PI / 180.0)) * Vector3(0, 0, 1)


## What every graphics level switches on. `near` / `mid` are the radii of the detail stream
## (everything of a street / lamps, trees and traffic), `far` how far the buildings are drawn.
const QUALITY := [
	{"near": 260.0, "mid": 1300.0, "far": 7000.0, "msaa": 0, "shadows": false, "glow": false, "life": false, "dense": 0.5},
	{"near": 420.0, "mid": 2600.0, "far": 14000.0, "msaa": 1, "shadows": true, "glow": true, "life": true, "dense": 0.8},
	{"near": 650.0, "mid": 4200.0, "far": 0.0, "msaa": 2, "shadows": true, "glow": true, "life": true, "dense": 1.0},
	{"near": 900.0, "mid": 6500.0, "far": 0.0, "msaa": 2, "shadows": true, "glow": true, "life": true, "dense": 1.3},
	{"near": 1300.0, "mid": 9500.0, "far": 0.0, "msaa": 3, "shadows": true, "glow": true, "life": true, "dense": 1.6},
]


func quality_def() -> Dictionary:
	return QUALITY[clampi(quality, 0, QUALITY.size() - 1)]


## 0 low, 1 high, 2 ultra, 3 max, 4 ultramax: shadows, glow and street life from high; the shaders
## read the same level (global "gfx") for clouds, stars, window interiors and reflections; Max and
## UltraMax add what only the Forward+ renderer can do (see _apply_forward).
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, QUALITY.size() - 1)
	var qd := quality_def()
	RenderingServer.global_shader_parameter_set("gfx", float(quality))
	_sun.shadow_enabled = bool(qd.shadows)
	env.glow_enabled = bool(qd.glow)
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][int(qd.msaa)]
	if b_traffic:
		var life: bool = qd.life
		b_traffic.set_visible(life)
		b_cars.set_visible(life)
		b_people.set_visible(life)
		b_detail.set_visible(life)
		var mid: float = qd.mid
		b_build.set_range(float(qd.far))
		b_roof.set_range(float(qd.far) * 0.6 if float(qd.far) > 0.0 else 12000.0)
		b_lights.set_range(mid * 2.2)
		b_traffic.set_range(mid * 1.6)
		b_cars.set_range(minf(mid, 3000.0))
		b_people.set_range(minf(mid * 0.4, 900.0))
		b_detail.set_range(mid)
		b_props.set_range(mid * 1.5)
		b_neon.set_range(mid * 2.0)
		b_cyl.set_range(mid * 3.0)
	_apply_forward()
	if stream != null:
		stream.apply_quality()
	set_night(night)


## Forward+ only (Max / UltraMax on a computer): ambient occlusion, screen-space reflections,
## volumetric haze under the lamps, soft shadows.
func _apply_forward() -> void:
	var on := forward and quality >= 3
	# the painted pools of lamp light: Forward+ shows them in a wider range, so they need less
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("lamp_gain", 2.4 if forward else 6.5)
	if road_mat != null:
		road_mat.set_shader_parameter("lamp_gain", 3.0 if forward else 8.0)
	var vp := get_viewport()
	if vp != null and forward:
		vp.positional_shadow_atlas_size = 8192 if quality >= 4 else 4096
	env.ssao_enabled = on
	env.ssr_enabled = on
	env.ssil_enabled = forward and quality >= 4
	env.volumetric_fog_enabled = on
	if not forward:
		return
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssr_max_steps = 96 if quality >= 4 else 56
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.6
	env.volumetric_fog_length = 420.0 if quality >= 4 else 260.0
	env.volumetric_fog_detail_spread = 2.2
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	# the haze belongs to the streets: it must not draw its own blocks over the sky
	env.volumetric_fog_sky_affect = 0.0
	_sun.light_volumetric_fog_energy = 0.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.shadow_blur = 1.4
	_sun.light_angular_distance = 0.6


func set_night(n: float) -> void:
	night = clampf(n, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night", night)
	_sun.rotation_degrees = SUN_DAY.lerp(SUN_NIGHT, night)
	_sun.light_color = Color(1.0, 0.93, 0.8).lerp(Color(0.55, 0.65, 1.0), night)
	var haze := HAZE_DAY.lerp(HAZE_NIGHT, night)
	# (at night the sky adds the glow of the city low over the horizon: the far land fades into that)
	env.fog_light_color = haze + Color(0.085, 0.05, 0.03, 0.0) * night
	if forward:
		# Forward+ works in a wider range: the same picture needs less of everything
		_sun.light_energy = lerpf(1.25, 0.05, night)
		env.ambient_light_color = Color(0.56, 0.62, 0.74).lerp(Color(0.1, 0.11, 0.2), night)
		env.ambient_light_energy = lerpf(0.55, 0.22, night)
		env.tonemap_exposure = lerpf(1.0, 1.05, night)
		env.fog_density = lerpf(0.00003, 0.00006, night) * fog_scale
		env.glow_intensity = lerpf(0.35, 0.8, night)
		env.glow_bloom = lerpf(0.0, 0.03, night)
		env.glow_hdr_threshold = 1.0
		env.volumetric_fog_density = lerpf(0.0005, 0.0022, night) * (1.0 if fog_scale > 0.0 else 0.0)
		env.volumetric_fog_albedo = Color(0.9, 0.9, 0.95)
		env.volumetric_fog_emission = haze * lerpf(0.0, 0.12, night)
		env.volumetric_fog_emission_energy = 1.0
	else:
		_sun.light_energy = lerpf(1.45, 0.3, night)
		env.ambient_light_color = Color(0.56, 0.62, 0.74).lerp(Color(0.17, 0.16, 0.22), night)
		env.ambient_light_energy = lerpf(0.6, 0.62, night)
		env.tonemap_exposure = lerpf(1.0, 1.3, night)
		env.fog_density = lerpf(0.000035, 0.00007, night) * fog_scale
		env.glow_intensity = lerpf(0.45, 0.95, night)
		env.glow_bloom = lerpf(0.02, 0.07, night)
	env.adjustment_saturation = lerpf(1.12, 1.04, night)
	env.adjustment_contrast = lerpf(1.06, 1.1, night)
	if _sky_mat:
		_sky_mat.set_shader_parameter("haze_day", Vector3(HAZE_DAY.r, HAZE_DAY.g, HAZE_DAY.b))
		_sky_mat.set_shader_parameter("haze_night", Vector3(HAZE_NIGHT.r, HAZE_NIGHT.g, HAZE_NIGHT.b))
	if stream != null:
		stream.set_night(night)


## 0 disables haze (overhead map view), 1 = normal atmosphere.
func set_fog_scale(s: float) -> void:
	fog_scale = s
	env.fog_enabled = s > 0.0
	set_night(night)


# --- Debug: top-down plan of the generated city (headless-friendly) ------------------------------------
## Writes a 1200×1200 PNG of the square (cx, cz, size): zones, water, avenues, rails, buildings,
## bridges, reserves. The whole map by default.
func dump_plan(path: String, cx := 0.0, cz := 0.0, size := 0.0) -> void:
	if size <= 0.0:
		size = half * 2.0
	var n := 1200
	var k := size / n
	var ox := cx - size * 0.5
	var oz := cz - size * 0.5
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var exact := k < zres * 0.7
	for py in n:
		for px in n:
			var x := ox + (px + 0.5) * k
			var z := oz + (py + 0.5) * k
			var c: Color
			var zv := classify(x, z) if exact else zone_at(x, z)
			if zv == Z_WATER:
				c = Color(0.15, 0.35, 0.7)
			else:
				match zv:
					Z_FOREST:
						c = Color(0.15, 0.4, 0.15)
					Z_CITY:
						c = Color(0.55, 0.55, 0.55)
					Z_SAND:
						c = Color(0.85, 0.78, 0.5)
					_:
						c = Color(0.62, 0.66, 0.42) if urban_at(x, z) == 0 else Color(0.7, 0.7, 0.5)
				if road_dist(x, z) < 0.0:
					c = Color(0.15, 0.15, 0.15)
			img.set_pixel(px, py, c)
	for i in fp_center.size():
		var cc := fp_center[i]
		var hs := fp_half[i]
		var r := hs.length()
		if cc.x + r < ox or cc.x - r > ox + size or cc.z + r < oz or cc.z - r > oz + size:
			continue
		var col := Color(0.95, 0.35, 0.25) if fp_name.has(i) else Color(0.25, 0.22, 0.3).lerp(Color(1, 1, 0.9), clampf(cc.y / 90.0, 0.0, 1.0))
		if is_bridge(i):
			col = Color(1.0, 0.85, 0.1)
		var ca := cos(fp_rot[i])
		var sa := sin(fp_rot[i])
		for py in range(maxi(0, int((cc.z - r - oz) / k)), mini(n - 1, int((cc.z + r - oz) / k)) + 1):
			for px in range(maxi(0, int((cc.x - r - ox) / k)), mini(n - 1, int((cc.x + r - ox) / k)) + 1):
				var dx := ox + (px + 0.5) * k - cc.x
				var dz := oz + (py + 0.5) * k - cc.z
				var lx := dx * ca + dz * sa
				var lz := -dx * sa + dz * ca
				if absf(lx) <= hs.x and absf(lz) <= hs.y:
					img.set_pixel(px, py, col)
	for rv in _rv:
		for q in 48:
			var a := TAU * q / 48.0
			var px := int((rv.x + cos(a) * rv.z - ox) / k)
			var py := int((rv.y + sin(a) * rv.z - oz) / k)
			if px >= 0 and py >= 0 and px < n and py < n:
				img.set_pixel(px, py, Color(1, 0, 1))
	for d in city.districts:
		var px := int((float(d[1]) - ox) / k)
		var py := int((float(d[2]) - oz) / k)
		for t in range(-5, 6):
			for q in [Vector2i(px + t, py), Vector2i(px, py + t)]:
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
					img.set_pixel(q.x, q.y, Color(1, 1, 0))
	img.save_png(path)
	print("UAD: plan of %s saved to %s (%.1f m per pixel)" % [city.id, path, k])
