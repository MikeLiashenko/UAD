extends RefCounted
## District-based city generator at real scale. Every district of the city (CityDef.districts) has
## its own rotated street grid (every ap-th line an avenue — the ground shader draws exactly the same
## grid) and fills its blocks according to its character: historic perimeter blocks with courtyards,
## Soviet panel microdistricts with schools and kindergartens, rows of "khrushchyovkas", Stalin-era
## avenues, new high-rises, industry, docks, seaside villas and private houses on garden plots.
##
## The work is cut by tile and runs on worker threads, so nothing here touches the scene or shared
## state: tile_buildings() returns the houses of a tile as raw records and MultiMesh buffers (the map
## merges them in tile order, so every building gets the same index on every machine);
## tile_decor() makes the small things of a street — lamps, trees, parked cars, balconies, fences —
## for the detail stream around the camera. Every block has its own random seed.

const Batch = preload("res://scripts/world/batch.gd")

## GS.Zone as plain constants: the generator compares zones on many threads, and reaching the enum
## through the autoload every time would make them wait for each other.
const Z_FIELD := 0
const Z_FOREST := 1
const Z_WATER := 2
const Z_CITY := 3
const Z_SAND := 4

const TILE := 500.0

const PANEL := [Color(0.78, 0.76, 0.72), Color(0.7, 0.72, 0.74), Color(0.82, 0.8, 0.72), Color(0.66, 0.68, 0.66), Color(0.75, 0.7, 0.62), Color(0.84, 0.74, 0.58), Color(0.6, 0.68, 0.78)]
const STALIN := [Color(0.86, 0.76, 0.55), Color(0.82, 0.66, 0.5), Color(0.9, 0.85, 0.72), Color(0.72, 0.56, 0.46), Color(0.78, 0.8, 0.78), Color(0.62, 0.74, 0.68), Color(0.86, 0.72, 0.72), Color(0.92, 0.9, 0.82)]
const ODESA := [Color(0.93, 0.86, 0.68), Color(0.88, 0.8, 0.62), Color(0.95, 0.92, 0.82), Color(0.85, 0.72, 0.6), Color(0.78, 0.84, 0.8), Color(0.92, 0.78, 0.64), Color(0.96, 0.94, 0.88)]
const PODIL := [Color(0.9, 0.8, 0.6), Color(0.72, 0.84, 0.78), Color(0.88, 0.72, 0.7), Color(0.8, 0.82, 0.9), Color(0.94, 0.9, 0.78), Color(0.85, 0.66, 0.52)]
const BRICK := [Color(0.64, 0.42, 0.34), Color(0.74, 0.68, 0.62), Color(0.82, 0.8, 0.76), Color(0.7, 0.5, 0.4), Color(0.78, 0.74, 0.66)]
const GLASS := [Color(0.25, 0.35, 0.5), Color(0.3, 0.42, 0.46), Color(0.36, 0.38, 0.44), Color(0.2, 0.3, 0.36), Color(0.45, 0.4, 0.3)]
const NEWRES := [Color(0.92, 0.9, 0.86), Color(0.86, 0.62, 0.42), Color(0.56, 0.63, 0.76), Color(0.95, 0.92, 0.84), Color(0.7, 0.3, 0.25), Color(0.4, 0.45, 0.5), Color(0.84, 0.8, 0.7)]
const INDUST := [Color(0.5, 0.5, 0.52), Color(0.56, 0.46, 0.4), Color(0.62, 0.6, 0.55), Color(0.42, 0.45, 0.48), Color(0.66, 0.66, 0.62)]
const HOUSE := [Color(0.92, 0.9, 0.85), Color(0.86, 0.78, 0.64), Color(0.76, 0.7, 0.62), Color(0.9, 0.84, 0.8), Color(0.82, 0.62, 0.5), Color(0.8, 0.86, 0.8), Color(0.7, 0.42, 0.32)]
const ROOF := [Color(0.5, 0.18, 0.12), Color(0.35, 0.2, 0.15), Color(0.3, 0.32, 0.35), Color(0.24, 0.4, 0.28), Color(0.56, 0.3, 0.2), Color(0.2, 0.25, 0.4)]
const METAL_ROOF := [Color(0.34, 0.36, 0.38), Color(0.25, 0.42, 0.34), Color(0.4, 0.3, 0.26), Color(0.46, 0.24, 0.2)]
const PUBLIC := [Color(0.9, 0.78, 0.55), Color(0.85, 0.65, 0.62), Color(0.78, 0.84, 0.86), Color(0.9, 0.88, 0.8)]
const CONTAINER := [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3), Color(0.55, 0.55, 0.58), Color(0.9, 0.9, 0.88), Color(0.4, 0.25, 0.5)]
const TREE := Color(0.13, 0.31, 0.11)
const GOLD := Color(0.95, 0.72, 0.3)
const NEON_SHOP := [Color(1.0, 0.85, 0.55), Color(0.95, 0.95, 1.0), Color(1.0, 0.5, 0.3), Color(0.5, 0.9, 1.0), Color(1.0, 0.95, 0.7), Color(0.4, 1.0, 0.5)]
const NEON_SIGN := [Color(1.0, 0.2, 0.35), Color(0.2, 0.7, 1.0), Color(0.3, 1.0, 0.5), Color(1.0, 0.8, 0.2), Color(0.9, 0.35, 1.0), Color(1.0, 1.0, 1.0)]
const CAR_PAINT := [Color(0.9, 0.9, 0.9), Color(0.08, 0.08, 0.09), Color(0.6, 0.62, 0.65), Color(0.6, 0.08, 0.06), Color(0.1, 0.22, 0.5), Color(0.35, 0.36, 0.38), Color(0.85, 0.75, 0.3), Color(0.15, 0.35, 0.2), Color(0.75, 0.76, 0.78), Color(0.2, 0.2, 0.22)]
const CLOTHES := [Color(0.15, 0.15, 0.2), Color(0.5, 0.1, 0.1), Color(0.2, 0.3, 0.55), Color(0.75, 0.7, 0.6), Color(0.3, 0.45, 0.3), Color(0.9, 0.9, 0.9), Color(0.55, 0.35, 0.2), Color(0.95, 0.8, 0.2)]

const RES := 0
const IND := 1
const PUB := 2

# block types (kept with every block for the detail stream)
const T_PERIM := 0
const T_PANEL := 1
const T_KHRUSH := 2
const T_NEW := 3
const T_IND := 4
const T_PRIVATE := 5
const T_VILLA := 6
const T_CONT := 7
const T_MALL := 8
const T_SQUARE := 9
const T_CHURCH := 10

## Street profile of a district character: w / aw = half width of a street / of an avenue, ap = every
## ap-th line is an avenue, set = green strip between the pavement and the houses, park = how much
## rarer the small parks are (1 = none), led = white LED lamps on the avenues instead of sodium ones.
const PROFILES := {
	"historic": {"w": 5.0, "aw": 9.0, "ap": 3, "set": 0.6, "park": 0.0, "led": 0.0},
	"podil": {"w": 4.6, "aw": 7.5, "ap": 4, "set": 0.4, "park": 0.05, "led": 0.0},
	"pechersk": {"w": 5.0, "aw": 9.5, "ap": 3, "set": 2.0, "park": -0.05, "led": 1.0},
	"stalin": {"w": 6.0, "aw": 11.5, "ap": 3, "set": 3.0, "park": 0.0, "led": 1.0},
	"odesa": {"w": 5.5, "aw": 8.5, "ap": 4, "set": 0.6, "park": 0.05, "led": 0.0},
	"panel": {"w": 4.5, "aw": 11.5, "ap": 2, "set": 9.0, "park": 0.0, "led": 1.0},
	"khrush": {"w": 4.2, "aw": 9.5, "ap": 3, "set": 7.0, "park": -0.03, "led": 0.0},
	"mixed": {"w": 4.5, "aw": 10.0, "ap": 3, "set": 6.0, "park": 0.0, "led": 0.0},
	"west": {"w": 4.5, "aw": 10.5, "ap": 3, "set": 6.0, "park": 0.0, "led": 1.0},
	"new": {"w": 5.0, "aw": 11.5, "ap": 2, "set": 7.0, "park": 0.05, "led": 1.0},
	"industrial": {"w": 5.0, "aw": 9.0, "ap": 3, "set": 5.0, "park": 0.25, "led": 0.0},
	"docks": {"w": 5.0, "aw": 8.5, "ap": 3, "set": 3.0, "park": 1.0, "led": 0.0},
	"private": {"w": 3.2, "aw": 6.0, "ap": 4, "set": 1.5, "park": 0.1, "led": 0.0},
	"villas": {"w": 3.5, "aw": 6.5, "ap": 4, "set": 2.0, "park": -0.05, "led": 0.0},
}


static func profile(kind: String) -> Dictionary:
	return PROFILES.get(kind, PROFILES.panel)


## District characters as numbers (the generator runs on many threads and compares them a lot).
const KINDS := ["panel", "historic", "podil", "pechersk", "west", "khrush", "mixed", "new", "industrial", "stalin", "odesa", "villas", "docks", "private"]
const K_PANEL := 0
const K_HISTORIC := 1
const K_PODIL := 2
const K_PECHERSK := 3
const K_WEST := 4
const K_KHRUSH := 5
const K_MIXED := 6
const K_NEW := 7
const K_INDUSTRIAL := 8
const K_STALIN := 9
const K_ODESA := 10
const K_VILLAS := 11
const K_DOCKS := 12
const K_PRIVATE := 13


static func kind_id(kind: String) -> int:
	return maxi(0, KINDS.find(kind))


## The houses of one tile, as the map's registry and batches take them.
class TileOut:
	var centers := PackedVector3Array()
	var halfs := PackedVector2Array()
	var rots := PackedFloat32Array()
	var kinds := PackedByteArray()
	var boxes := PackedVector2Array()
	var styles := PackedByteArray()
	var cols := PackedColorArray()
	var seeds := PackedFloat32Array()
	var atts := PackedByteArray()
	var att_roofs := PackedByteArray()
	## Index of the box in build_buf / of the roof in roof_buf (−1 = none).
	var build_i := PackedInt32Array()
	var roof_i := PackedInt32Array()
	var names := {}
	var build_buf := PackedFloat32Array()
	var roof_buf := PackedFloat32Array()
	var lights_buf := PackedFloat32Array()
	var cyl_buf := PackedFloat32Array()
	var prop_buf := PackedFloat32Array()
	## 8 floats per block: district, type, x0, x1, z0, z1 (district frame), i, j.
	var blocks := PackedFloat32Array()
	var churches: Array = []
	var smokes: Array = []


## The small things of one tile for the detail stream. Every array is a MultiMesh buffer.
class Decor:
	var lamp := PackedFloat32Array()      # street lamp glows (LIGHTS)
	var pole := PackedFloat32Array()      # lamp posts
	var tree := PackedFloat32Array()      # deciduous
	var pine := PackedFloat32Array()      # conifers
	var car := PackedFloat32Array()       # parked cars
	var box := PackedFloat32Array()       # plain props (vertex colour)
	var bbox := PackedFloat32Array()      # pieces in the building shader (balcony stacks, canopies)
	var neon := PackedFloat32Array()      # glowing signs
	var cyl := PackedFloat32Array()       # cylinders
	var tlight := PackedFloat32Array()    # moving car lights
	var tcar := PackedFloat32Array()      # moving car bodies
	var ppl := PackedFloat32Array()       # pedestrians
	## Real lights near the camera (Forward+): x, y, z, r, g, b per lamp.
	var lights := PackedFloat32Array()


## Random numbers of the generator: a 48-bit linear congruential sequence in plain integers. The
## engine's RandomNumberGenerator is an object, and every call on an object takes a global lock in
## debug builds — two dozen generator threads would queue on it. It also makes the city exactly
## the same on every platform.
class Rnd:
	var s := 1

	func seed_with(v: int) -> void:
		s = (v ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF
		randi()
		randi()

	func randi() -> int:
		s = (s * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
		return s >> 16

	func randf() -> float:
		s = (s * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
		return float(s >> 16) / 4294967296.0

	func randf_range(a: float, b: float) -> float:
		s = (s * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
		return a + (b - a) * (float(s >> 16) / 4294967296.0)

	func randi_range(a: int, b: int) -> int:
		s = (s * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
		return a + (s >> 16) % (b - a + 1)


class Ctx:
	var map
	var out: TileOut
	var rng: Rnd
	var seed := Vector2.ZERO
	var rot := 0.0
	var ca := 1.0
	var sa := 0.0
	var B := 150.0
	var kind := 0
	var di := 0
	var u := 2
	## Street profile: half widths of a street and of an avenue, the avenue period, the setback.
	var pw := 4.5
	var paw := 11.0
	var pap := 3
	var pset := 5.0
	var led := false
	var x0 := 0.0
	var x1 := 0.0
	var z0 := 0.0
	var z1 := 0.0

	func w(lx: float, lz: float) -> Vector2:
		return Vector2(seed.x + lx * ca - lz * sa, seed.y + lx * sa + lz * ca)


static func _pick(rng: Rnd, arr: Array):
	return arr[rng.randi() % arr.size()]


static func _ctx(map, di: int) -> Ctx:
	var df: PackedFloat32Array = map._df
	var dp: PackedFloat32Array = map._dp
	var o := di * 8
	var c := Ctx.new()
	c.map = map
	c.seed = Vector2(df[o], df[o + 1])
	c.ca = df[o + 2]
	c.sa = df[o + 3]
	c.B = df[o + 4]
	c.kind = int(df[o + 7])
	c.pw = dp[o]
	c.paw = dp[o + 1]
	c.pap = int(dp[o + 2])
	c.pset = dp[o + 3]
	c.led = dp[o + 4] > 0.5
	c.rot = dp[o + 5]
	c.di = di
	return c


## Range of grid lines of a district that cross a tile: [i0, i1, j0, j1] (in block units).
static func _tile_range(c: Ctx, x0: float, z0: float, margin := 0.0) -> Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in [Vector2(x0 - margin, z0 - margin), Vector2(x0 + TILE + margin, z0 - margin), Vector2(x0 + TILE + margin, z0 + TILE + margin), Vector2(x0 - margin, z0 + TILE + margin)]:
		var rel: Vector2 = p - c.seed
		var l := Vector2(rel.x * c.ca + rel.y * c.sa, -rel.x * c.sa + rel.y * c.ca)
		mn = mn.min(l)
		mx = mx.max(l)
	return [int(floor(mn.x / c.B)), int(floor(mx.x / c.B)), int(floor(mn.y / c.B)), int(floor(mx.y / c.B))]


static func _block_seed(city_seed: int, di: int, i: int, j: int, salt := 0) -> int:
	return (city_seed * 73856093) ^ ((di + 1) * 19349663) ^ ((i + 4096) * 83492791) ^ ((j + 4096) * 2971215073) ^ (salt * 1000003)


# --- Pass A: the houses of a tile (worker thread) ---------------------------------------------------------
static func tile_buildings(map, t: int) -> TileOut:
	var half: float = map.half
	var tx: int = t % int(map.tn)
	var tz: int = t / int(map.tn)
	var x0 := -half + tx * TILE
	var z0 := -half + tz * TILE
	var out := TileOut.new()
	var rng := Rnd.new()
	var city_seed: int = map.city_seed
	var dc_start: PackedInt32Array = map._dc_start
	var dc_items: PackedInt32Array = map._dc_items
	for dq in range(dc_start[t], dc_start[t + 1]):
		var di := dc_items[dq]
		var c := _ctx(map, di)
		c.out = out
		c.rng = rng
		var bs := c.B
		var rg := _tile_range(c, x0, z0)
		for j in range(rg[2], rg[3] + 1):
			for i in range(rg[0], rg[1] + 1):
				var cw := c.w((i + 0.5) * bs, (j + 0.5) * bs)
				if cw.x < x0 or cw.x >= x0 + TILE or cw.y < z0 or cw.y >= z0 + TILE:
					continue
				if absf(cw.x) > half - 40.0 or absf(cw.y) > half - 40.0:
					continue
				if map.nearest_district(cw.x, cw.y) != di:
					continue
				var u: int = map.classify_full(cw.x, cw.y) >> 4
				if u == 0:
					continue
				c.u = u
				var sc := 1.0 if u == 2 else 0.7
				var ap := c.pap
				var ins: float = 3.2 + c.pset * sc
				c.x0 = i * bs + (c.paw if posmod(i, ap) == 0 else c.pw) * sc + ins
				c.x1 = (i + 1) * bs - (c.paw if posmod(i + 1, ap) == 0 else c.pw) * sc - ins
				c.z0 = j * bs + (c.paw if posmod(j, ap) == 0 else c.pw) * sc + ins
				c.z1 = (j + 1) * bs - (c.paw if posmod(j + 1, ap) == 0 else c.pw) * sc - ins
				rng.seed_with(_block_seed(city_seed, di, i, j))
				var type := T_PRIVATE
				if u == 1:
					_fill_private(c, 0.6)
				else:
					type = _fill_block(c)
				out.blocks.append_array(PackedFloat32Array([di, type, c.x0, c.x1, c.z0, c.z1, i, j]))
	if out.blocks.is_empty():
		return null
	return out


## Places one building if it lies fully inside its district's (convex) Voronoi cell — so
## neighbouring districts never overlap — and clear of water, parks, landmarks and highways.
static func _fits(c: Ctx, cx: float, cz: float, sx: float, sz: float) -> bool:
	var map = c.map
	var p := c.w(cx, cz)
	var r := Vector2(sx, sz).length() * 0.5
	var f: int = map.classify_full(p.x, p.y)
	if (f >> 4) == 0 or (f & 15) != Z_CITY and (f & 15) != Z_FIELD:
		return false
	if map.water_dist(p.x, p.y) < r + 5.0 or map.is_reserved(p.x, p.y, r * 0.85):
		return false
	for k in 4:
		var q := c.w(cx + (0.5 if k == 1 or k == 2 else -0.5) * sx, cz + (0.5 if k >= 2 else -0.5) * sz)
		if map.nearest_district(q.x, q.y) != c.di:
			return false
	# highways and railways cut through the blocks: the footprint (sampled every ≤ 14 m, so a road
	# cannot slip between the samples) must stay off them
	var dc: float = map.road_dist(p.x, p.y)
	if dc > r + 2.0:
		return true
	if dc < 2.0:
		return false
	var nx := int(ceil(sx / 14.0)) + 1
	var nz := int(ceil(sz / 14.0)) + 1
	for iz in nz:
		for ix in nx:
			var q := c.w(cx + (float(ix) / (nx - 1) - 0.5) * (sx + 4.0), cz + (float(iz) / (nz - 1) - 0.5) * (sz + 4.0))
			if map.road_dist(q.x, q.y) < 1.5:
				return false
	return true


## A piece glued to the last building's box (it follows the box in the batch).
static func _attach(c: Ctx, li: int, center: Vector3, size: Vector3, col: Color, style: int, on_roof: bool) -> void:
	var o := c.out
	var n := int(o.atts[li])
	if n >= 8:
		return
	Batch.push(o.build_buf, Transform3D(Basis(Vector3.UP, -c.rot) * Basis.from_scale(size), center), col, Color(0.0, c.rng.randf(), style / 10.0, 0.0))
	o.atts[li] = n + 1
	if on_roof:
		o.att_roofs[li] = int(o.att_roofs[li]) | (1 << n)


static func _light(o: TileOut, pos: Vector3, col: Color, blink: bool, base: float, k: float, ph: float) -> void:
	Batch.push(o.lights_buf, Transform3D(Basis(), pos), col, Color(ph, 1.0 if blink else 0.0, base, k))


## One building of a block: the record, its box (and roof) and what shows from afar — warning
## lights on the tall ones, the machine room, corner turrets, a glass crown. Returns its index in
## the tile, or −1 when it does not fit.
static func _b(c: Ctx, cx: float, cz: float, sx: float, sz: float, h: float, style: int, col: Color, kind := RES, roof_h := 0.0, roof_col := Color(0.4, 0.2, 0.15), bname := "") -> int:
	if sx < 4.0 or sz < 4.0 or not _fits(c, cx, cz, sx, sz):
		return -1
	var o := c.out
	var rng := c.rng
	var p := c.w(cx, cz)
	var li := o.centers.size()
	var seed := rng.randf()
	o.build_i.append(o.build_buf.size() / Batch.STRIDE)
	Batch.push(o.build_buf, Transform3D(Basis(Vector3.UP, -c.rot) * Basis.from_scale(Vector3(sx, h, sz)), Vector3(p.x, h * 0.5, p.y)), col, Color(0.0, seed, style / 10.0, 0.0))
	if roof_h > 0.0:
		o.roof_i.append(o.roof_buf.size() / Batch.STRIDE)
		var rb: Basis
		if sx > sz:
			rb = Basis(Vector3.UP, -c.rot + PI * 0.5) * Basis.from_scale(Vector3(sz, roof_h, sx))
		else:
			rb = Basis(Vector3.UP, -c.rot) * Basis.from_scale(Vector3(sx, roof_h, sz))
		Batch.push(o.roof_buf, Transform3D(rb, Vector3(p.x, h + roof_h * 0.5, p.y)), roof_col, Color(0.0, rng.randf(), 0.7, 0.0))
	else:
		o.roof_i.append(-1)
	o.centers.append(Vector3(p.x, h + roof_h * 0.6, p.y))
	o.halfs.append(Vector2(sx * 0.5, sz * 0.5))
	o.rots.append(c.rot)
	o.kinds.append(kind)
	o.boxes.append(Vector2(h, roof_h))
	o.styles.append(style)
	o.cols.append(col)
	o.seeds.append(seed)
	o.atts.append(0)
	o.att_roofs.append(0)
	if bname != "":
		o.names[li] = bname
	if h > 62.0:
		# aviation warning lights on two opposite roof corners
		for s in [-1.0, 1.0]:
			var q := c.w(cx + s * (sx * 0.5 - 0.6), cz + s * (sz * 0.5 - 0.6))
			_light(o, Vector3(q.x, h + 1.2, q.y), Color(1.0, 0.08, 0.05), true, 1.4, 0.0045, rng.randf())
	if h > 24.0 and roof_h <= 0.0 and style != 2 and style != 3:
		# the lift machine room
		var mq := c.w(cx + rng.randf_range(-0.2, 0.2) * sx, cz + rng.randf_range(-0.15, 0.15) * sz)
		_attach(c, li, Vector3(mq.x, h + 1.5, mq.y), Vector3(minf(7.0, sx * 0.3), 3.0, minf(5.0, sz * 0.45)), col.darkened(0.12), 6, true)
	if style == 1 and h >= 20.0 and rng.randf() < 0.16:
		# a corner turret with a spire, the signature of the post-war avenues
		var sgx := -1.0 if rng.randf() < 0.5 else 1.0
		var sgz := -1.0 if rng.randf() < 0.5 else 1.0
		var tq := c.w(cx + sgx * (sx * 0.5 - 3.4), cz + sgz * (sz * 0.5 - 3.4))
		var th := h + rng.randf_range(6.0, 12.0)
		_attach(c, li, Vector3(tq.x, th * 0.5, tq.y), Vector3(7.0, th, 7.0), col.lightened(0.05), 1, false)
		_attach(c, li, Vector3(tq.x, th + 1.6, tq.y), Vector3(3.0, 3.2, 3.0), col.lightened(0.1), 6, true)
		_attach(c, li, Vector3(tq.x, th + 7.0, tq.y), Vector3(0.6, 8.0, 0.6), GOLD, 6, true)
	if style == 2 and h > 60.0:
		# stepped glass crown
		_attach(c, li, Vector3(p.x, h + 3.5, p.y), Vector3(sx * 0.7, 7.0, sz * 0.7), col, 2, true)
		if h > 95.0:
			_attach(c, li, Vector3(p.x, h + 10.0, p.y), Vector3(sx * 0.4, 6.0, sz * 0.4), col, 2, true)
			_light(o, Vector3(p.x, h + 14.0, p.y), Color(1.0, 0.08, 0.05), true, 1.6, 0.005, rng.randf())
	return li


## An invisible footprint of the block (a chimney, a tank, a crane).
static func _fp(c: Ctx, p: Vector2, hs: Vector2, h: float, kind: int, fname: String) -> void:
	var o := c.out
	var li := o.centers.size()
	o.build_i.append(-1)
	o.roof_i.append(-1)
	o.centers.append(Vector3(p.x, h, p.y))
	o.halfs.append(hs)
	o.rots.append(0.0)
	o.kinds.append(kind)
	o.boxes.append(Vector2.ZERO)
	o.styles.append(6)
	o.cols.append(Color(0.5, 0.5, 0.5))
	o.seeds.append(0.0)
	o.atts.append(0)
	o.att_roofs.append(0)
	o.names[li] = fname


static func _cyl(o: TileOut, base: Vector3, r: float, h: float, col: Color) -> void:
	Batch.push(o.cyl_buf, Transform3D(Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), base + Vector3(0, h * 0.5, 0)), col, Color(0, 0, 0, 0))


static func _prop(c: Ctx, center: Vector3, size: Vector3, col: Color) -> void:
	Batch.push(c.out.prop_buf, Transform3D(Basis(Vector3.UP, -c.rot) * Basis.from_scale(size), center), col, Color(0, 0, 0, 0))


## Length of a slab made of whole 18 m sections, not longer than `room`.
static func _sections(room: float) -> float:
	return maxf(36.0, floorf(room / 18.0) * 18.0)


static func _fill_block(c: Ctx) -> int:
	var rng := c.rng
	var r := rng.randf()
	match c.kind:
		K_HISTORIC:
			if r < 0.04:
				return _fill_church(c)
			elif r < 0.1:
				return _fill_square(c)
			elif r < 0.16:
				return _fill_new(c, true)
			return _fill_perimeter(c, 4, 7, STALIN, 3.7, 0.5)
		K_PODIL:
			var p := c.w((c.x0 + c.x1) * 0.5, (c.z0 + c.z1) * 0.5)
			if r < 0.06:
				return _fill_church(c)
			elif r < 0.12:
				return _fill_square(c)
			elif c.map.water_dist(p.x, p.y) < 320.0 and r < 0.45:
				return _fill_industrial(c)
			return _fill_perimeter(c, 2, 5, PODIL, 3.6, 0.65)
		K_PECHERSK:
			if r < 0.35:
				return _fill_perimeter(c, 5, 9, STALIN, 3.6, 0.3)
			elif r < 0.62:
				return _fill_new(c, true)
			elif r < 0.9:
				return _fill_panel(c, [9, 12, 16])
			return _fill_square(c)
		K_WEST:
			if r < 0.4:
				return _fill_khrush(c)
			elif r < 0.7:
				return _fill_panel(c, [9, 12, 16])
			return _fill_industrial(c)
		K_KHRUSH:
			if r < 0.62:
				return _fill_khrush(c)
			elif r < 0.9:
				return _fill_panel(c, [9, 9, 12])
			return _fill_industrial(c)
		K_MIXED:
			if r < 0.35:
				return _fill_panel(c, [9, 12, 16])
			elif r < 0.6:
				return _fill_khrush(c)
			elif r < 0.8:
				return _fill_new(c, false)
			elif r < 0.9:
				return _fill_private(c, 0.85)
			return _fill_industrial(c)
		K_NEW:
			if r < 0.5:
				return _fill_new(c, false)
			elif r < 0.88:
				return _fill_panel(c, [16, 16, 22, 25])
			return _fill_mall(c)
		K_INDUSTRIAL:
			if r < 0.62:
				return _fill_industrial(c)
			elif r < 0.85:
				return _fill_panel(c, [9, 12, 16])
			return _fill_khrush(c)
		K_STALIN:
			# wide Stalin-era avenues: 5–9 storey palaces with spires here and there, a few squares
			if r < 0.05:
				return _fill_square(c)
			elif r < 0.08:
				return _fill_church(c)
			elif r < 0.2:
				return _fill_new(c, true)
			elif r < 0.3:
				return _fill_khrush(c)
			return _fill_perimeter(c, 5, 9, STALIN, 3.7, 0.2)
		K_ODESA:
			# 19th-century limestone blocks of 2–4 floors on a strict grid, courtyards and acacias
			if r < 0.05:
				return _fill_church(c)
			elif r < 0.12:
				return _fill_square(c)
			elif r < 0.17:
				return _fill_new(c, true)
			return _fill_perimeter(c, 2, 4, ODESA, 4.0, 0.4)
		K_VILLAS:
			# seaside: private villas, a few new towers, sanatoriums
			if r < 0.5:
				return _fill_villas(c)
			elif r < 0.75:
				return _fill_new(c, false)
			return _fill_panel(c, [9, 12])
		K_DOCKS:
			# port land: container yards, warehouses, a few old blocks
			if r < 0.4:
				return _fill_containers(c)
			elif r < 0.85:
				return _fill_industrial(c)
			return _fill_khrush(c)
		K_PRIVATE:
			if r < 0.9:
				return _fill_private(c, 0.88)
			return _fill_khrush(c)
	if r < 0.72:
		return _fill_panel(c, [9, 12, 16, 16])
	elif r < 0.88:
		return _fill_new(c, false)
	return _fill_khrush(c)


# --- Block types ---------------------------------------------------------------------------------
## Pre-revolutionary / Stalin-era perimeter block: houses wall to wall along the street line, a
## courtyard inside with a wing or two.
static func _fill_perimeter(c: Ctx, fmin: int, fmax: int, palette: Array, fh: float, roof_p: float) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var depth := rng.randf_range(12.5, 15.5)
	var base_fl := rng.randi_range(fmin, fmax)
	if x1 - x0 < depth * 2.0 + 12.0 or z1 - z0 < depth * 2.0 + 12.0:
		# too small for a courtyard: a cluster of houses of different heights
		var nx := 2 if x1 - x0 > 26.0 else 1
		var nz := 2 if z1 - z0 > 26.0 else 1
		var cw := (x1 - x0) / nx
		var cd := (z1 - z0) / nz
		for a in nx:
			for b in nz:
				var rh := rng.randf_range(2.5, 4.0) if rng.randf() < roof_p else 0.0
				_b(c, x0 + (a + 0.5) * cw, z0 + (b + 0.5) * cd, cw - 0.4, cd - 0.4, rng.randi_range(fmin, fmax) * fh + 1.0, 1, _pick(rng, palette), RES, rh, _pick(rng, METAL_ROOF))
		return T_PERIM
	for side in 2:
		var zc := z0 + depth * 0.5 if side == 0 else z1 - depth * 0.5
		var x := x0
		while x < x1 - 6.0:
			var seg := minf(rng.randf_range(18.0, 44.0), x1 - x)
			if x1 - (x + seg) < 13.0:
				seg = x1 - x
			if rng.randf() > 0.05:
				var rh := rng.randf_range(2.5, 4.5) if rng.randf() < roof_p else 0.0
				var fl := clampi(base_fl + rng.randi_range(-1, 1), fmin, fmax)
				_b(c, x + seg * 0.5, zc, seg - 0.25, depth - rng.randf_range(0.0, 1.6), fl * fh + 1.0, 1, _pick(rng, palette), RES, rh, _pick(rng, METAL_ROOF))
			x += seg
	for side in 2:
		var xc := x0 + depth * 0.5 if side == 0 else x1 - depth * 0.5
		var z := z0 + depth
		while z < z1 - depth - 6.0:
			var seg := minf(rng.randf_range(18.0, 40.0), z1 - depth - z)
			if z1 - depth - (z + seg) < 12.0:
				seg = z1 - depth - z
			if rng.randf() > 0.1:
				var rh := rng.randf_range(2.5, 4.0) if rng.randf() < roof_p else 0.0
				var fl := clampi(base_fl + rng.randi_range(-1, 1), fmin, fmax)
				_b(c, xc, z + seg * 0.5, depth - rng.randf_range(0.0, 1.6), seg - 0.25, fl * fh + 1.0, 1, _pick(rng, palette), RES, rh, _pick(rng, METAL_ROOF))
			z += seg
	# wings in the courtyard
	var iw := x1 - x0 - depth * 2.0
	var id := z1 - z0 - depth * 2.0
	if iw > 44.0 and id > 44.0:
		var wings := rng.randi_range(0, 2)
		for k in wings:
			var wx := lerpf(x0 + depth + 14.0, x1 - depth - 14.0, (k + 0.5) / wings + rng.randf_range(-0.1, 0.1))
			var wlen := id * rng.randf_range(0.45, 0.75)
			_b(c, wx, z0 + depth + 1.0 + wlen * 0.5, 11.5, wlen, maxi(fmin, base_fl - 1) * fh + 0.8, 1, _pick(rng, palette), RES, 0.0)
	return T_PERIM


## Soviet panel microdistrict: long 9–16 storey slabs around a yard, point towers, a school or a
## kindergarten in the middle.
static func _fill_panel(c: Ctx, floors: Array) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var W := x1 - x0
	var D := z1 - z0
	var fl: int = _pick(rng, floors)
	var h := fl * 2.8 + 1.2
	var col: Color = _pick(rng, PANEL)
	var dep := rng.randf_range(12.0, 13.5)
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	match rng.randi() % 4:
		0:
			# a slab on the street, two wings behind it, the kindergarten in the yard
			var ln := _sections(minf(W - 4.0, 126.0))
			_b(c, cx, z0 + dep * 0.5, ln, dep, h, 0, col)
			var wl := _sections(minf(D * 0.5, 90.0))
			_b(c, x0 + dep * 0.5, z0 + dep + 10.0 + wl * 0.5, dep, wl, h, 0, col)
			_b(c, x1 - dep * 0.5, z0 + dep + 10.0 + wl * 0.5, dep, wl, _pick(rng, floors) * 2.8 + 1.2, 0, _pick(rng, PANEL))
			if D > 100.0:
				_b(c, cx, z1 - 14.0, minf(48.0, W * 0.4), 22.0, 7.4, 0, _pick(rng, PUBLIC), PUB)
		1:
			# parallel slabs with a point tower at the end
			var rows := 2 if D < 120.0 else 3
			for k in rows:
				var zc := lerpf(z0 + dep * 0.5, z1 - dep * 0.5, float(k) / (rows - 1))
				var ln := _sections(minf(W - 30.0, rng.randf_range(72.0, 126.0)))
				_b(c, x0 + ln * 0.5 + rng.randf_range(0.0, 6.0), zc, ln, dep, (fl if k != 1 else _pick(rng, floors)) * 2.8 + 1.2, 0, col if rng.randf() < 0.6 else _pick(rng, PANEL))
			if W > 130.0:
				_b(c, x1 - 12.0, cz, 22.0, 22.0, (maxi(fl, 16) + rng.randi_range(0, 6)) * 2.8 + 1.2, 0, _pick(rng, PANEL))
		2:
			# point towers in a staggered line, a shop between them
			var cnt := clampi(int(W / 55.0), 2, 4)
			var tall := (maxi(fl, 16) + rng.randi_range(0, 8)) * 2.8 + 1.2
			for k in cnt:
				var f := (k + 0.5) / cnt
				_b(c, lerpf(x0 + 12.0, x1 - 12.0, f), z0 + 12.0 + (D - 24.0) * (0.12 if k % 2 == 0 else 0.88), 22.0, 22.0, tall, 0, _pick(rng, PANEL))
			_b(c, cx, cz, minf(44.0, W * 0.3), 18.0, 4.6, 1, _pick(rng, PUBLIC), PUB)
		_:
			# two L-shaped houses and the school
			var ln := _sections(minf(W * 0.55, 108.0))
			_b(c, x0 + ln * 0.5, z0 + dep * 0.5, ln, dep, h, 0, col)
			_b(c, x0 + dep * 0.5, z0 + dep + 0.4 + 27.0, dep, 54.0, h, 0, col)
			var col2: Color = _pick(rng, PANEL)
			_b(c, x1 - ln * 0.5, z1 - dep * 0.5, ln, dep, _pick(rng, floors) * 2.8 + 1.2, 0, col2)
			if D > 110.0:
				_b(c, x1 - 30.0, z0 + 24.0, 56.0, 16.0, 10.8, 0, _pick(rng, PUBLIC), PUB)
	return T_PANEL


## Five-storey brick "khrushchyovkas" in rows with trees between them.
static func _fill_khrush(c: Ctx) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var col: Color = _pick(rng, BRICK)
	var W := x1 - x0
	var per := 1 if W < 150.0 else 2
	var z := z0 + 6.0
	var row := 0
	while z + 6.0 < z1:
		for k in per:
			var room := W / per
			var ln := minf(room - 12.0, rng.randf_range(54.0, 82.0))
			var bx := x0 + room * (k + 0.5) + rng.randf_range(-4.0, 4.0)
			if row % 4 == 3 and rng.randf() < 0.3:
				# a nine-storey brick tower among the rows
				_b(c, bx, z + 2.0, 26.0, 15.0, 27.5, 0, _pick(rng, BRICK))
			else:
				_b(c, bx, z, ln, 12.0, 15.2, 0, col if rng.randf() < 0.7 else _pick(rng, BRICK), RES, 2.4 if rng.randf() < 0.3 else 0.0, Color(0.3, 0.3, 0.32))
		z += rng.randf_range(34.0, 40.0)
		row += 1
	return T_KHRUSH


## New residential / office high-rises (20–36 floors), a retail podium, a tower crane on a site.
static func _fill_new(c: Ctx, central: bool) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var W := x1 - x0
	var D := z1 - z0
	var cnt := 1 if W < 60.0 else rng.randi_range(2, clampi(int(W / 45.0), 2, 4))
	var glass := rng.randf() < (0.55 if central else 0.25)
	if rng.randf() < 0.55:
		_b(c, (x0 + x1) * 0.5, z1 - 9.0, minf(W * 0.9, 110.0), 16.0, 8.4, 1, _pick(rng, STALIN), PUB if central else RES)
	for k in cnt:
		var f := (k + 0.5) / cnt
		var slab := rng.randf() < 0.3
		var sx := rng.randf_range(44.0, 62.0) if slab else rng.randf_range(22.0, 30.0)
		var sz := rng.randf_range(15.0, 18.0) if slab else rng.randf_range(19.0, 26.0)
		if sx > W / cnt - 6.0:
			sx = maxf(18.0, W / cnt - 6.0)
		var fl := rng.randi_range(20, 36) if not slab else rng.randi_range(16, 26)
		var h := fl * (3.6 if glass else 3.05) + 1.5
		var cx := lerpf(x0 + sx * 0.5 + 1.0, x1 - sx * 0.5 - 1.0, f)
		var cz := lerpf(z0 + sz * 0.5 + 1.0, z1 - sz * 0.5 - 20.0, rng.randf())
		if D < sz + 24.0:
			cz = (z0 + z1) * 0.5
		var col: Color = _pick(rng, GLASS) if glass else _pick(rng, NEWRES)
		var li := _b(c, cx, cz, sx, sz, h, 2 if glass else 0, col, IND if glass else RES)
		if li >= 0 and rng.randf() < 0.6:
			# LED crown lighting, typical for the new towers
			var lc: Color = _pick(rng, [Color(0.4, 0.9, 1.0), Color(1.0, 1.0, 1.0), Color(0.9, 0.4, 1.0), Color(1.0, 0.8, 0.4)])
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q := c.w(cx + s.x * sx * 0.5, cz + s.y * sz * 0.5)
				_light(c.out, Vector3(q.x, h + 0.3, q.y), lc, false, 1.2, 0.0022, rng.randf())
		if k == 0 and rng.randf() < 0.12:
			_crane(c, x1 - 6.0, z0 + 6.0)
	return T_NEW


## A tower crane over a construction site: mast, jib, counter-jib and the warning lights.
static func _crane(c: Ctx, x: float, z: float) -> void:
	var rng := c.rng
	var p := c.w(x, z)
	var map = c.map
	if map.road_dist(p.x, p.y) < 6.0 or map.is_reserved(p.x, p.y, 6.0) or map.water_dist(p.x, p.y) < 8.0:
		return
	var h := rng.randf_range(80.0, 125.0)
	var yellow := Color(0.95, 0.72, 0.1)
	_prop(c, Vector3(p.x, h * 0.5, p.y), Vector3(2.0, h, 2.0), yellow)
	var a := rng.randf() * TAU
	var d := Vector2(cos(a), sin(a))
	var jl := 52.0
	var j := p + d * jl * 0.42
	Batch.push(c.out.prop_buf, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)) * Basis.from_scale(Vector3(1.3, 1.3, jl)), Vector3(j.x, h + 1.0, j.y)), yellow, Color(0, 0, 0, 0))
	var cj := p - d * 14.0
	Batch.push(c.out.prop_buf, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)) * Basis.from_scale(Vector3(2.6, 2.6, 3.4)), Vector3(cj.x, h + 0.6, cj.y)), Color(0.5, 0.5, 0.52), Color(0, 0, 0, 0))
	_prop(c, Vector3(p.x, h + 4.5, p.y), Vector3(1.1, 7.0, 1.1), yellow)
	_fp(c, p, Vector2(1.6, 1.6), h + 8.0, IND, "башенный кран")
	_light(c.out, Vector3(p.x, h + 8.5, p.y), Color(1.0, 0.08, 0.05), true, 1.3, 0.0045, rng.randf())
	var tip := p + d * jl * 0.92
	_light(c.out, Vector3(tip.x, h + 2.0, tip.y), Color(1.0, 0.08, 0.05), true, 1.3, 0.0045, rng.randf())


## Workshops and warehouses, a factory chimney with warning lights, storage tanks.
static func _fill_industrial(c: Ctx) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var W := x1 - x0
	var D := z1 - z0
	var wx := W * rng.randf_range(0.5, 0.78)
	var wz := D * rng.randf_range(0.42, 0.66)
	var saw := rng.randf() < 0.35
	_b(c, x0 + wx * 0.5, z0 + wz * 0.5, wx, wz, rng.randf_range(9.0, 17.0), 3, _pick(rng, INDUST), IND, 4.5 if saw else 0.0, Color(0.4, 0.42, 0.44))
	if W - wx > 24.0:
		_b(c, x1 - (W - wx) * 0.5 + 2.0, z0 + D * 0.3, W - wx - 8.0, D * 0.5, rng.randf_range(7.0, 12.0), 3, _pick(rng, INDUST), IND)
	if D - wz > 34.0:
		# the office of the works
		_b(c, x0 + 22.0, z1 - 9.0, 40.0, 14.0, rng.randi_range(3, 5) * 3.3 + 0.8, 0, _pick(rng, PANEL), IND)
	if rng.randf() < 0.4:
		var p := c.w(x1 - 9.0, z1 - 9.0)
		if c.map.classify_full(p.x, p.y) >> 4 > 0 and c.map.road_dist(p.x, p.y) > 5.0 and not c.map.is_reserved(p.x, p.y, 5.0):
			var ch := rng.randf_range(45.0, 90.0)
			_cyl(c.out, Vector3(p.x, 0, p.y), rng.randf_range(1.6, 2.6), ch, Color(0.62, 0.58, 0.55))
			_cyl(c.out, Vector3(p.x, ch - 7.0, p.y), 2.8, 3.4, Color(0.75, 0.15, 0.12))
			_fp(c, p, Vector2(2.6, 2.6), ch, IND, "дымовая труба")
			_light(c.out, Vector3(p.x, ch + 1.0, p.y), Color(1.0, 0.08, 0.05), true, 1.3, 0.0045, rng.randf())
			if rng.randf() < 0.25:
				c.out.smokes.append(Vector3(p.x, ch + 1.0, p.y))
	elif rng.randf() < 0.5 and D - wz > 30.0:
		for k in 2:
			var p := c.w(x1 - 14.0 - k * 24.0, z1 - 14.0)
			if c.map.classify_full(p.x, p.y) >> 4 > 0 and c.map.road_dist(p.x, p.y) > 9.0 and not c.map.is_reserved(p.x, p.y, 9.0):
				_cyl(c.out, Vector3(p.x, 0, p.y), 9.0, 12.0, Color(0.72, 0.72, 0.7))
				_fp(c, p, Vector2(9.0, 9.0), 12.0, IND, "резервуар")
	for k in 3:
		var p := c.w(rng.randf_range(x0, x1), rng.randf_range(z0, z1))
		_light(c.out, Vector3(p.x, 11.0, p.y), Color(1.0, 0.75, 0.45), false, 1.1, 0.002, rng.randf())
	return T_IND


## Container yard: stacks of boxes and floodlights (docks of a river / sea port).
static func _fill_containers(c: Ctx) -> int:
	var rng := c.rng
	var w: float = c.x1 - c.x0
	var d: float = c.z1 - c.z0
	if w < 50.0 or d < 40.0:
		return _fill_industrial(c)
	for s in [Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.5, 0.5)]:
		var q := c.w(lerpf(c.x0, c.x1, s.x), lerpf(c.z0, c.z1, s.y))
		if c.map.nearest_district(q.x, q.y) != c.di or c.map.water_dist(q.x, q.y) < 6.0 or c.map.road_dist(q.x, q.y) < 3.0 or c.map.is_reserved(q.x, q.y, 6.0) or (c.map.classify_full(q.x, q.y) >> 4) == 0:
			return _fill_industrial(c)
	var x := c.x0 + 8.0
	while x < c.x1 - 8.0:
		var z := c.z0 + 3.0
		while z < c.z1 - 3.0:
			if rng.randf() < 0.82:
				var n := rng.randi_range(1, 5)
				var p := c.w(x, z)
				for k in n:
					_prop(c, Vector3(p.x, 1.3 + k * 2.6, p.y), Vector3(12.0, 2.5, 2.4), _pick(rng, CONTAINER))
				_fp(c, p, Vector2(6.2, 6.2), n * 2.6, IND, "контейнерный терминал")
			z += 2.9
			if int(z - c.z0) % 18 > 14:
				z += 10.0 # a lane for the reach stackers
		x += 15.0
	for i in 4:
		var q := c.w(lerpf(c.x0, c.x1, i / 3.0), (c.z0 + c.z1) * 0.5)
		_light(c.out, Vector3(q.x, 22.0, q.y), Color(1.0, 0.85, 0.6), false, 1.6, 0.0022, rng.randf())
	return T_CONT


## Shopping mall with a bright facade and a car park.
static func _fill_mall(c: Ctx) -> int:
	var rng := c.rng
	var W := c.x1 - c.x0
	var D := c.z1 - c.z0
	_b(c, (c.x0 + c.x1) * 0.5, c.z0 + D * 0.32, minf(W * 0.9, 160.0), D * 0.56, rng.randf_range(14.0, 20.0), 2, Color(0.35, 0.4, 0.5), PUB)
	for k in 6:
		var p := c.w(lerpf(c.x0 + W * 0.08, c.x1 - W * 0.08, k / 5.0), c.z0 + D * 0.62)
		_light(c.out, Vector3(p.x, 14.0, p.y), _pick(rng, [Color(1, 0.3, 0.5), Color(0.3, 0.8, 1.0), Color(1, 0.9, 0.5)]), false, 1.6, 0.0024, rng.randf())
	return T_MALL


## Square / small park with a monument (the detail stream plants it).
static func _fill_square(_c: Ctx) -> int:
	return T_SQUARE


static func _fill_church(c: Ctx) -> int:
	var p := c.w((c.x0 + c.x1) * 0.5, (c.z0 + c.z1) * 0.5)
	var map = c.map
	if (map.classify_full(p.x, p.y) >> 4) < 2 or map.is_reserved(p.x, p.y, 26.0) or map.road_dist(p.x, p.y) < 24.0 or map.water_dist(p.x, p.y) < 30.0:
		return T_SQUARE
	_fp(c, p, Vector2(10, 16), 18.0, PUB, "церковь")
	c.out.rots[c.out.rots.size() - 1] = c.rot
	c.out.churches.append([Vector3(p.x, 0, p.y), c.rot])
	return T_CHURCH


## Private houses with pitched roofs on garden plots, row behind row.
static func _fill_private(c: Ctx, fill: float) -> int:
	var rng := c.rng
	var x0 := c.x0
	var x1 := c.x1
	var z0 := c.z0
	var z1 := c.z1
	var pz := z0
	var row := 0
	while pz + 22.0 < z1:
		var pd := rng.randf_range(32.0, 38.0)
		var px := x0
		while px + 16.0 < x1:
			var pw := rng.randf_range(19.0, 25.0)
			if rng.randf() < fill:
				var hw := rng.randf_range(8.0, 11.5)
				var hd := rng.randf_range(8.5, 12.0)
				var fl := 1 if rng.randf() < 0.55 else 2
				var cx := px + minf(pw, x1 - px) * 0.5 + rng.randf_range(-2.0, 2.0)
				# the houses of neighbouring rows face their own lanes, back to back
				var cz := pz + hd * 0.5 + 5.0 if row % 2 == 0 else pz + pd - hd * 0.5 - 5.0
				_b(c, cx, cz, hw, hd, fl * 3.0 + 0.6, 4, _pick(rng, HOUSE), RES, rng.randf_range(2.6, 4.2), _pick(rng, ROOF))
			px += pw
		pz += pd
		row += 1
	return T_PRIVATE


## Seaside villas and small hotels on larger plots.
static func _fill_villas(c: Ctx) -> int:
	var rng := c.rng
	var pz := c.z0
	while pz + 30.0 < c.z1:
		var pd := rng.randf_range(40.0, 52.0)
		var px := c.x0
		while px + 24.0 < c.x1:
			var pw := rng.randf_range(28.0, 40.0)
			if rng.randf() < 0.82:
				var hw := rng.randf_range(11.0, 17.0)
				var hd := rng.randf_range(11.0, 16.0)
				var fl := rng.randi_range(2, 3)
				var flat := rng.randf() < 0.4
				_b(c, px + pw * 0.5, pz + pd * 0.45, hw, hd, fl * 3.2 + 0.6, 4 if not flat else 0, _pick(rng, HOUSE if not flat else NEWRES), RES, 0.0 if flat else rng.randf_range(3.0, 4.6), _pick(rng, ROOF))
			px += pw
		pz += pd
	return T_VILLA


# --- Pass B: the detail of a tile (worker thread, for the stream around the camera) ---------------------------
static func _box(buf: PackedFloat32Array, center: Vector3, size: Vector3, rot: float, col: Color, cd := Color(0, 0, 0, 0)) -> void:
	Batch.push(buf, Transform3D(Basis(Vector3.UP, -rot) * Basis.from_scale(size), center), col, cd)


static func _free(map, p: Vector2, r: float) -> bool:
	return map.building_at(p.x, p.y) < 0 and map.water_dist(p.x, p.y) > r + 2.0 and map.road_dist(p.x, p.y) > r and not map.is_reserved(p.x, p.y, r) and not map.is_cleared(p.x, p.y, r)


static func _tree(dec: Decor, rng: Rnd, p: Vector2, s: float, conifer := false) -> void:
	var g := rng.randf_range(0.78, 1.15)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), Vector3(p.x, 0, p.y))
	if conifer:
		Batch.push(dec.pine, xf, Color(0.09 * g, 0.24 * g, 0.08 * g), Color(rng.randf(), 0, 0, 0))
	else:
		Batch.push(dec.tree, xf, Color(TREE.r * g, TREE.g * g * rng.randf_range(0.92, 1.08), TREE.b * g), Color(rng.randf(), 0, 0, 0))


## `near` = everything of a street (posts, parked cars, balconies, fences, people); otherwise only
## what shows from a few kilometres: the glow of the lamps, the trees, the traffic. `dense` scales
## the amount with the graphics level.
static func tile_decor(map, t: int, near: bool, dense: float) -> Decor:
	var half: float = map.half
	var tx: int = t % int(map.tn)
	var tz: int = t / int(map.tn)
	var x0 := -half + tx * TILE
	var z0 := -half + tz * TILE
	var dec := Decor.new()
	var rng := Rnd.new()
	rng.seed_with(_block_seed(map.city_seed, 977, tx, tz, 5 if near else 3))
	_decor_streets(map, t, x0, z0, dec, rng, near, dense)
	_decor_blocks(map, t, dec, rng, near, dense)
	_decor_green(map, x0, z0, dec, rng, near, dense)
	if near:
		_decor_buildings(map, t, dec, rng, dense)
		_decor_road_lamps(map, t, dec)
	return dec


## Lamps along both kerbs of every street of the district grids, trees and parked cars between
## them, traffic on the avenues.
static func _decor_streets(map, t: int, x0: float, z0: float, dec: Decor, rng: Rnd, near: bool, dense: float) -> void:
	var sp := 32.0
	var dc_start: PackedInt32Array = map._dc_start
	var dc_items: PackedInt32Array = map._dc_items
	for dq in range(dc_start[t], dc_start[t + 1]):
		var di := dc_items[dq]
		var c := _ctx(map, di)
		var bs := c.B
		var ap := c.pap
		var rg := _tile_range(c, x0, z0, 4.0)
		var boulevard: bool = c.kind in [K_HISTORIC, K_PODIL, K_PECHERSK, K_STALIN, K_ODESA]
		var led := c.led
		for axis in 2:
			var k0: int = rg[0] if axis == 0 else rg[2]
			var k1: int = rg[1] if axis == 0 else rg[3]
			var a0: float = (rg[2] if axis == 0 else rg[0]) * bs
			var a1: float = ((rg[3] if axis == 0 else rg[1]) + 1) * bs
			for k in range(k0, k1 + 2):
				var avenue := posmod(k, ap) == 0
				var line := k * bs
				var m0 := int(floor(a0 / sp))
				var m1 := int(ceil(a1 / sp))
				for m in range(m0, m1 + 1):
					var along := m * sp + sp * 0.5
					var mid := c.w(line, along) if axis == 0 else c.w(along, line)
					if mid.x < x0 or mid.x >= x0 + TILE or mid.y < z0 or mid.y >= z0 + TILE:
						continue
					if map.nearest_district(mid.x, mid.y) != di:
						continue
					var u: int = map.urban_at(mid.x, mid.y)
					if u == 0 or map.water_dist(mid.x, mid.y) < 10.0 or map.road_dist(mid.x, mid.y) < 6.0:
						continue
					if u == 1 and posmod(m, 2) == 1:
						continue
					var sc := 1.0 if u == 2 else 0.7
					var w: float = (c.paw if avenue else c.pw) * sc
					# is this spot at a junction? (no lamps or cars in the middle of a crossing)
					var cross := fposmod(along, bs)
					var at_junction := cross < 13.0 or cross > bs - 13.0
					var col := Color(0.86, 0.9, 1.0) if avenue and led and u == 2 else Color(1.0, 0.62, 0.27)
					var sgn := 1.0 if posmod(m, 2) == 0 else -1.0
					if avenue:
						sgn = 1.0
					for pass_i in (2 if avenue else 1):
						var sg := sgn if pass_i == 0 else -sgn
						var across: float = line + sg * (w + 1.3)
						var p := c.w(across, along) if axis == 0 else c.w(along, across)
						if not at_junction and map.building_at(p.x, p.y) < 0 and not map.is_cleared(p.x, p.y, 2.0):
							var lh := 9.5 if avenue else 7.5
							# the lamp head hangs over the carriageway
							var hx: float = line + sg * (w - 0.6)
							var hp := c.w(hx, along) if axis == 0 else c.w(along, hx)
							Batch.push(dec.lamp, Transform3D(Basis(), Vector3(hp.x, lh, hp.y)), col, Color(rng.randf(), 0.0, 0.95, 0.0021))
							if near:
								var yaw := atan2(-(hp.x - p.x), -(hp.y - p.y))
								Batch.push(dec.pole, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1, lh / 9.0, 1)), Vector3(p.x, 0, p.y)), Color(0.22, 0.23, 0.25), Color(0, 0, 0, 0))
								var aim := (hp - p).normalized()
								dec.lights.append_array(PackedFloat32Array([hp.x, lh - 0.3, hp.y, col.r, col.g, col.b, aim.x, aim.y]))
					if at_junction:
						continue
					for sg in [-1.0, 1.0]:
						if near and u >= 1 and rng.randf() < (0.62 if u == 2 else 0.25) * minf(dense, 1.2):
							# cars parked along the kerb, nose to tail
							var ca: float = line + sg * (w - 1.25)
							var n_cars := rng.randi_range(1, 4)
							for kc in n_cars:
								var al := along - 9.0 + kc * 5.4 + rng.randf_range(-0.4, 0.4)
								var cp := c.w(ca, al) if axis == 0 else c.w(al, ca)
								var cq := c.w(ca, al + 1.0) if axis == 0 else c.w(al + 1.0, ca)
								if map.building_at(cp.x, cp.y) < 0 and map.road_dist(cp.x, cp.y) > 1.5 and not map.is_reserved(cp.x, cp.y, 2.0) and not map.is_cleared(cp.x, cp.y, 3.0):
									var dir: Vector2 = (cq - cp) * (sg if rng.randf() < 0.85 else -sg)
									Batch.push(dec.car, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y) + rng.randf_range(-0.03, 0.03)), Vector3(cp.x, 0.0, cp.y)), _pick(rng, CAR_PAINT), Color(rng.randf(), 0, 0, 0))
						# street trees between the lamps
						var tp := 0.0
						if boulevard and avenue and u == 2:
							tp = 0.9
						elif u == 2:
							tp = 0.4
						elif u == 1:
							tp = 0.25
						if not near:
							tp *= 0.4
						if rng.randf() < tp:
							var ta: float = line + sg * (w + 2.6)
							var tpos := c.w(ta, along + sp * 0.5) if axis == 0 else c.w(along + sp * 0.5, ta)
							if map.building_at(tpos.x, tpos.y) < 0 and map.road_dist(tpos.x, tpos.y) > 1.5 and not map.is_cleared(tpos.x, tpos.y, 3.0):
								_tree(dec, rng, tpos, rng.randf_range(0.8, 1.15))
					if near and u == 2 and rng.randf() < 0.1 * dense:
						# a bench and a bin on the pavement
						var bx: float = line + (w + 2.2) * (1.0 if rng.randf() < 0.5 else -1.0)
						var bp := c.w(bx, along + 6.0) if axis == 0 else c.w(along + 6.0, bx)
						if map.building_at(bp.x, bp.y) < 0:
							var br := c.rot + (0.0 if axis == 1 else PI * 0.5)
							_box(dec.box, Vector3(bp.x, 0.45, bp.y), Vector3(1.8, 0.08, 0.5), br, Color(0.4, 0.27, 0.17))
							_box(dec.box, Vector3(bp.x, 0.22, bp.y), Vector3(1.6, 0.44, 0.08), br, Color(0.15, 0.15, 0.16))
							_box(dec.box, Vector3(bp.x + 1.4, 0.4, bp.y + 0.6), Vector3(0.4, 0.8, 0.4), br, Color(0.2, 0.32, 0.22))
				if avenue:
					_decor_traffic(map, c, axis, line, a0, a1, x0, z0, dec, rng, near)


## Car streams and pedestrians along one avenue line, block by block.
static func _decor_traffic(map, c: Ctx, axis: int, line: float, a0: float, a1: float, x0: float, z0: float, dec: Decor, rng: Rnd, near: bool) -> void:
	var bs := c.B
	var w := c.paw
	var j0 := int(floor(a0 / bs))
	var j1 := int(ceil(a1 / bs))
	for j in range(j0, j1):
		var sa := j * bs + 10.0
		var sb := (j + 1) * bs - 10.0
		var pa := c.w(line, sa) if axis == 0 else c.w(sa, line)
		var pb := c.w(line, sb) if axis == 0 else c.w(sb, line)
		var mid := (pa + pb) * 0.5
		# a run belongs to the tile its middle is in
		if mid.x < x0 or mid.x >= x0 + TILE or mid.y < z0 or mid.y >= z0 + TILE:
			continue
		if map.nearest_district(mid.x, mid.y) != c.di or map.urban_at(mid.x, mid.y) != 2:
			continue
		if map.water_dist(mid.x, mid.y) < 14.0 or map.road_dist(mid.x, mid.y) < 8.0 or map.water_dist(pa.x, pa.y) < 6.0 or map.water_dist(pb.x, pb.y) < 6.0:
			continue
		var d := pb - pa
		var length := d.length()
		var dir := d / length
		var side := Vector2(-dir.y, dir.x)
		var lanes := 1 if w < 8.0 else 2
		for lane in lanes * 2:
			var fwd := lane % 2 == 0
			var from := pa if fwd else pb
			var to_dir := dir if fwd else -dir
			var off := side * ((1.9 + (lane / 2) * 3.3) * (1.0 if fwd else -1.0))
			var basis := Basis.looking_at(Vector3(to_dir.x, 0, to_dir.y), Vector3.UP)
			var col := Color(1.0, 0.93, 0.78) if fwd else Color(1.0, 0.12, 0.07)
			if rng.randf() < 0.75:
				var o := from + off
				var xf := Transform3D(basis, Vector3(o.x, 0.0, o.y))
				var cd := Color(rng.randf_range(9.0, 15.0), length, rng.randf(), 0.0)
				Batch.push(dec.tlight, xf, col, cd)
				Batch.push(dec.tcar, xf, _pick(rng, CAR_PAINT), cd)
		if near:
			for s in [-1.0, 1.0]:
				for i in int(length / 45.0) + 1:
					var fwd := rng.randf() < 0.5
					var start: Vector2 = pa if fwd else pb
					var from: Vector2 = start + side * float(s) * (w + 2.6 + rng.randf_range(-0.7, 0.7))
					var to_dir: Vector2 = dir if fwd else -dir
					Batch.push(dec.ppl, Transform3D(Basis.looking_at(Vector3(to_dir.x, 0, to_dir.y), Vector3.UP), Vector3(from.x, 0.0, from.y)), _pick(rng, CLOTHES), Color(rng.randf_range(1.1, 1.8), length, rng.randf(), rng.randf()))


## What stands inside the blocks: courtyard trees, playgrounds, garages, fences, monuments.
static func _decor_blocks(map, t: int, dec: Decor, rng: Rnd, near: bool, dense: float) -> void:
	var blocks = map.tile_blocks[t]
	if blocks == null:
		return
	var bl: PackedFloat32Array = blocks
	for bi in bl.size() / 8:
		var o := bi * 8
		var c := _ctx(map, int(bl[o]))
		var type := int(bl[o + 1])
		c.x0 = bl[o + 2]
		c.x1 = bl[o + 3]
		c.z0 = bl[o + 4]
		c.z1 = bl[o + 5]
		var W := c.x1 - c.x0
		var D := c.z1 - c.z0
		var area := W * D
		# trees of the yard: a share from afar, all of them near
		var per := 0.0
		match type:
			T_PANEL, T_KHRUSH:
				per = 1.0 / 420.0
			T_PERIM:
				per = 1.0 / 900.0
			T_NEW, T_MALL:
				per = 1.0 / 1400.0
			T_PRIVATE, T_VILLA:
				per = 1.0 / 520.0
			T_SQUARE, T_CHURCH:
				per = 1.0 / 260.0
			T_IND:
				per = 1.0 / 4000.0
		var n := int(area * per * (1.0 if near else 0.35) * minf(dense, 1.3))
		for i in n:
			var p := c.w(rng.randf_range(c.x0, c.x1), rng.randf_range(c.z0, c.z1))
			if _free(map, p, 2.0):
				_tree(dec, rng, p, rng.randf_range(0.75, 1.25) * (0.75 if type == T_PRIVATE else 1.0), type == T_PRIVATE and rng.randf() < 0.15)
		if type == T_SQUARE:
			var m := c.w((c.x0 + c.x1) * 0.5, (c.z0 + c.z1) * 0.5)
			if _free(map, m, 4.0):
				Batch.push(dec.cyl, Transform3D(Basis.from_scale(Vector3(5.0, 4.0, 5.0)), Vector3(m.x, 2.0, m.y)), Color(0.5, 0.48, 0.46), Color(0, 0, 0, 0))
				_box(dec.box, Vector3(m.x, 6.2, m.y), Vector3(1.5, 4.4, 1.5), c.rot, Color(0.3, 0.36, 0.32))
				Batch.push(dec.lamp, Transform3D(Basis(), Vector3(m.x, 1.2, m.y)), Color(1.0, 0.85, 0.6), Color(rng.randf(), 0.0, 2.2, 0.002))
		if not near:
			continue
		match type:
			T_PANEL, T_KHRUSH:
				if rng.randf() < 0.75:
					_playground(map, c, dec, rng, (c.x0 + c.x1) * 0.5 + rng.randf_range(-0.2, 0.2) * W, (c.z0 + c.z1) * 0.5 + rng.randf_range(-0.15, 0.15) * D)
				# a row of garages and cars left in the yard
				var g := c.w(c.x0 + W * rng.randf_range(0.25, 0.75), c.z0 + D * rng.randf_range(0.3, 0.7))
				if rng.randf() < 0.5 and _free(map, g, 12.0):
					for k in rng.randi_range(4, 8):
						var gp := g + Vector2(c.ca, c.sa) * (k * 3.4)
						if map.building_at(gp.x, gp.y) < 0:
							_box(dec.box, Vector3(gp.x, 1.25, gp.y), Vector3(3.2, 2.5, 6.0), c.rot, Color(0.4, 0.4, 0.42) if k % 3 != 0 else Color(0.34, 0.3, 0.26))
				for k in int(8 * dense):
					var cp := c.w(rng.randf_range(c.x0 + 6.0, c.x1 - 6.0), rng.randf_range(c.z0 + 6.0, c.z1 - 6.0))
					if _free(map, cp, 3.0):
						Batch.push(dec.car, Transform3D(Basis(Vector3.UP, -c.rot + (PI * 0.5 if rng.randf() < 0.5 else 0.0)), Vector3(cp.x, 0.0, cp.y)), _pick(rng, CAR_PAINT), Color(rng.randf(), 0, 0, 0))
			T_MALL, T_NEW:
				# the car park in rows
				var rows := 3 if type == T_MALL else 1
				for r in rows:
					var pz := c.z1 - 10.0 - r * 12.0
					var px := c.x0 + 6.0
					while px < c.x1 - 6.0:
						if rng.randf() < 0.55:
							var cp := c.w(px, pz)
							if _free(map, cp, 2.5):
								Batch.push(dec.car, Transform3D(Basis(Vector3.UP, -c.rot), Vector3(cp.x, 0.0, cp.y)), _pick(rng, CAR_PAINT), Color(rng.randf(), 0, 0, 0))
						px += 2.7


## A playground in a courtyard: a slide, swings, a sandbox and a bench.
static func _playground(map, c: Ctx, dec: Decor, rng: Rnd, x: float, z: float) -> void:
	var m := c.w(x, z)
	if not _free(map, m, 8.0):
		return
	var cols := [Color(0.9, 0.25, 0.2), Color(0.2, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35)]
	var r := c.rot
	var put := func(lx: float, lz: float, y: float, size: Vector3, colr: Color) -> void:
		var q := c.w(x + lx, z + lz)
		_box(dec.box, Vector3(q.x, y, q.y), size, r, colr)
	put.call(0.0, 0.0, 0.15, Vector3(4.0, 0.3, 4.0), Color(0.8, 0.72, 0.5))
	put.call(4.0, 0.0, 1.2, Vector3(1.2, 2.4, 1.2), cols[rng.randi() % 4])
	put.call(5.6, 0.0, 0.8, Vector3(2.4, 0.2, 1.0), cols[rng.randi() % 4])
	for s in [-1.2, 1.2]:
		put.call(-3.5 + s, 3.5, 1.1, Vector3(0.15, 2.2, 0.15), Color(0.35, 0.35, 0.38))
	put.call(-3.5, 3.5, 2.2, Vector3(2.8, 0.15, 0.15), Color(0.35, 0.35, 0.38))
	put.call(-3.5, 3.5, 0.6, Vector3(0.8, 0.08, 0.4), cols[rng.randi() % 4])
	put.call(0.0, -4.0, 0.25, Vector3(2.4, 0.5, 0.6), Color(0.45, 0.3, 0.2))
	put.call(-6.0, -2.0, 1.0, Vector3(2.0, 2.0, 0.1), cols[rng.randi() % 4])


## Woods, parks and the trees of the open country.
static func _decor_green(map, x0: float, z0: float, dec: Decor, rng: Rnd, near: bool, dense: float) -> void:
	var cell := 12.0 if near else 30.0
	var n := int(TILE / cell)
	var chance := (0.85 if near else 0.5) * minf(dense, 1.4)
	for iz in n:
		for ix in n:
			var x := x0 + (ix + rng.randf()) * cell
			var z := z0 + (iz + rng.randf()) * cell
			var zone: int = map.zone_at(x, z)
			if zone == Z_FOREST:
				if rng.randf() > chance:
					continue
				var p := Vector2(x, z)
				if not _free(map, p, 1.5):
					continue
				var park: bool = map.city.city_norm(x, z) < 0.75
				var conifer := rng.randf() < (0.15 if park else 0.7)
				_tree(dec, rng, p, (rng.randf_range(1.0, 1.7) if conifer else rng.randf_range(0.95, 1.5)) * (1.0 if near else 1.6), conifer)
				if near and rng.randf() < 0.5:
					var p2 := p + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
					if _free(map, p2, 1.5):
						_tree(dec, rng, p2, rng.randf_range(0.8, 1.3), conifer)
			elif zone == Z_SAND and near and rng.randf() < 0.05 and map.city.city_norm(x, z) < 1.0:
				# parasols on the city beaches
				if map.water_dist(x, z) > 4.0 and map.building_at(x, z) < 0:
					var bc: Color = _pick(rng, [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.2, 0.7, 0.4), Color(0.95, 0.95, 0.9)])
					_box(dec.box, Vector3(x, 1.1, z), Vector3(0.1, 2.2, 0.1), 0.0, Color(0.85, 0.85, 0.85))
					Batch.push(dec.cyl, Transform3D(Basis.from_scale(Vector3(2.6, 0.25, 2.6)), Vector3(x, 2.2, z)), bc, Color(0, 0, 0, 0))
			elif zone == Z_FIELD and rng.randf() < (0.012 if near else 0.006):
				var p := Vector2(x, z)
				if map.urban_at(x, z) == 0 and _free(map, p, 2.0):
					_tree(dec, rng, p, rng.randf_range(1.0, 1.6))


## What a real house carries: stacks of balconies down the panel blocks, a canopy and a lamp over
## every entrance, air conditioners, antennas and vents on the flat roofs, shop fronts and cornices
## on the old streets, porches and fences in the private sector.
static func _decor_buildings(map, t: int, dec: Decor, rng: Rnd, dense: float) -> void:
	var f0: int = map.tile_fp0[t]
	var fn: int = map.tile_fpn[t]
	var central_kinds := [K_HISTORIC, K_STALIN, K_NEW, K_ODESA, K_PECHERSK, K_PODIL]
	var df: PackedFloat32Array = map._df
	var city_seed: int = map.city_seed
	for i in range(f0, f0 + fn):
		if map.fp_bk[i] < 0 or map.fp_hidden[i] == 1:
			continue
		var c3: Vector3 = map.fp_center[i]
		var hs: Vector2 = map.fp_half[i]
		var rot: float = map.fp_rot[i]
		var box: Vector2 = map.fp_box[i]
		var style := int(map.fp_style[i])
		var col: Color = map.fp_col[i]
		var h: float = box.x * (1.0 - float(map.fp_crush[i]))
		var crushed: bool = map.fp_crush[i] > 0.01
		var ca := cos(rot)
		var sa := sin(rot)
		var sx := hs.x * 2.0
		var sz := hs.y * 2.0
		var along_x := sx >= sz
		var long := sx if along_x else sz
		var deep := sz if along_x else sx
		rng.seed_with(_block_seed(city_seed, 311, i, 0))
		# local (lx, lz) of the building → world
		var W := func(lx: float, lz: float) -> Vector2:
			return Vector2(c3.x + lx * ca - lz * sa, c3.z + lx * sa + lz * ca)
		if style == 0 and h >= 12.0:
			# balcony stacks on both long sides: one piece per column, the shader draws the floors
			var fh := 2.8 if box.x < 80.0 else 3.05
			var n := int(long / 6.0)
			var lc := col.lightened(0.08)
			for side in [-1.0, 1.0]:
				for k in n:
					if rng.randf() < 0.35:
						continue
					var tt := (k + 0.5) / n - 0.5
					var off: float = side * (deep * 0.5 + 0.6)
					var q: Vector2 = W.call(tt * (long - 3.0) if along_x else off, off if along_x else tt * (long - 3.0))
					var bh: float = floorf((h - 4.0) / fh) * fh
					if bh < fh:
						continue
					var size := Vector3(3.2, bh, 1.25) if along_x else Vector3(1.25, bh, 3.2)
					_box(dec.bbox, Vector3(q.x, 3.2 + bh * 0.5, q.y), size, rot, lc, Color(0.0, rng.randf(), 0.8, fh / 10.0))
			# a canopy, a door and a lamp at every entrance on the yard side
			var ne := maxi(1, int(long / 18.0))
			for k in ne:
				var tt := (k + 0.5) / ne - 0.5
				var off := deep * 0.5 + 1.1
				var q: Vector2 = W.call(tt * long if along_x else off, off if along_x else tt * long)
				var size := Vector3(3.4, 0.22, 2.4) if along_x else Vector3(2.4, 0.22, 3.4)
				_box(dec.box, Vector3(q.x, 2.75, q.y), size, rot, Color(0.42, 0.42, 0.44))
				var dq: Vector2 = W.call(tt * long if along_x else deep * 0.5 + 0.06, deep * 0.5 + 0.06 if along_x else tt * long)
				_box(dec.box, Vector3(dq.x, 1.1, dq.y), Vector3(1.5, 2.2, 0.12) if along_x else Vector3(0.12, 2.2, 1.5), rot, Color(0.2, 0.16, 0.14))
				Batch.push(dec.lamp, Transform3D(Basis(), Vector3(q.x, 2.5, q.y)), Color(1.0, 0.82, 0.55), Color(rng.randf(), 0.0, 0.55, 0.0016))
		if style == 0 or style == 1:
			# air conditioners hung under the windows
			var fh2 := 2.8 if style == 0 else 3.7
			var na := int(long * h / 260.0 * dense)
			for k in mini(na, 26):
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var u := rng.randf_range(-0.46, 0.46) * long
				var fl := rng.randi_range(1, maxi(1, int(h / fh2) - 1))
				var off := side * (deep * 0.5 + 0.28)
				var q: Vector2 = W.call(u if along_x else off, off if along_x else u)
				_box(dec.box, Vector3(q.x, fl * fh2 + 0.5, q.y), Vector3(0.85, 0.55, 0.42) if along_x else Vector3(0.42, 0.55, 0.85), rot, Color(0.82, 0.82, 0.8))
		if box.y <= 0.0 and style != 4 and style != 3 and h > 8.0 and not crushed:
			# the roof: vents, a parapet lip, aerials
			for k in rng.randi_range(1, 4):
				var q: Vector2 = W.call(rng.randf_range(-0.38, 0.38) * sx, rng.randf_range(-0.38, 0.38) * sz)
				_box(dec.box, Vector3(q.x, h + 0.55, q.y), Vector3(1.6, 1.1, 1.2), rot, Color(0.6, 0.6, 0.62))
			if rng.randf() < 0.4:
				var q: Vector2 = W.call(rng.randf_range(-0.4, 0.4) * sx, rng.randf_range(-0.4, 0.4) * sz)
				var ah := rng.randf_range(3.0, 8.0)
				_box(dec.box, Vector3(q.x, h + ah * 0.5, q.y), Vector3(0.14, ah, 0.14), 0.0, Color(0.4, 0.4, 0.42))
				_box(dec.box, Vector3(q.x, h + ah * 0.8, q.y), Vector3(2.4, 0.1, 0.1), rot, Color(0.4, 0.4, 0.42))
			if rng.randf() < 0.18:
				var q: Vector2 = W.call(rng.randf_range(-0.3, 0.3) * sx, rng.randf_range(-0.3, 0.3) * sz)
				Batch.push(dec.cyl, Transform3D(Basis.from_scale(Vector3(2.6, 2.4, 2.6)), Vector3(q.x, h + 1.2, q.y)), Color(0.5, 0.52, 0.55), Color(0, 0, 0, 0))
		if style == 1 and not crushed:
			# the cornice all around, a plinth at the foot
			_box(dec.bbox, Vector3(c3.x, h - 0.9, c3.z), Vector3(sx + 0.9, 0.5, sz + 0.9), rot, col.lightened(0.18), Color(0.0, rng.randf(), 0.6, 0.0))
			_box(dec.bbox, Vector3(c3.x, 0.45, c3.z), Vector3(sx + 0.3, 0.9, sz + 0.3), rot, col.darkened(0.3), Color(0.0, rng.randf(), 0.6, 0.0))
			# small balconies with iron railings
			var nb := int(long / 9.0)
			for k in nb:
				if rng.randf() < 0.55:
					continue
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var tt := (k + 0.5) / nb - 0.5
				var off := side * (deep * 0.5 + 0.5)
				var fl := rng.randi_range(1, maxi(1, int(h / 3.7) - 1))
				var q: Vector2 = W.call(tt * long if along_x else off, off if along_x else tt * long)
				_box(dec.box, Vector3(q.x, fl * 3.7 + 0.6, q.y), Vector3(2.6, 0.14, 1.0) if along_x else Vector3(1.0, 0.14, 2.6), rot, col.darkened(0.2))
				_box(dec.box, Vector3(q.x, fl * 3.7 + 1.15, q.y), Vector3(2.6, 1.0, 0.06) if along_x else Vector3(0.06, 1.0, 2.6), rot, Color(0.12, 0.12, 0.13))
		var dk := int(df[map.nearest_district(c3.x, c3.z) * 8 + 7])
		if dk in central_kinds and (style == 1 or style == 2) and long >= 14.0:
			# shop signs: light boxes standing out from the wall over the pavement
			var n_sign := clampi(int(long / 16.0), 1, 4)
			for k in n_sign:
				if rng.randf() < 0.55:
					continue
				var sd: float = (deep * 0.5 + 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
				var tt: float = ((k + rng.randf_range(0.25, 0.75)) / n_sign - 0.5) * long
				var q: Vector2 = W.call(tt if along_x else sd, sd if along_x else tt)
				_box(dec.neon, Vector3(q.x, rng.randf_range(3.3, 4.4), q.y), Vector3(0.14, 0.75, 0.9) if along_x else Vector3(0.9, 0.75, 0.14), rot, _pick(rng, NEON_SHOP))
			# a neon sign on the roof edge of the taller ones
			if h > 22.0 and rng.randf() < 0.045 and not crushed:
				var sd2: float = deep * 0.5 - 0.6
				var q2: Vector2 = W.call(0.0 if along_x else sd2, sd2 if along_x else 0.0)
				_box(dec.neon, Vector3(q2.x, h + 1.8, q2.y), Vector3(minf(long * 0.5, 18.0), 2.6, 0.4) if along_x else Vector3(0.4, 2.6, minf(long * 0.5, 18.0)), rot, _pick(rng, NEON_SIGN))
		if style == 4:
			# a private house: the chimney, the porch, a fence around the plot, a shed
			if not crushed:
				var q: Vector2 = W.call(sx * rng.randf_range(-0.25, 0.25), sz * rng.randf_range(-0.2, 0.2))
				_box(dec.box, Vector3(q.x, h + box.y * 0.7, q.y), Vector3(0.7, box.y + 1.2, 0.7), rot, Color(0.5, 0.3, 0.24))
			var pq: Vector2 = W.call(0.0, hs.y + 0.9)
			_box(dec.box, Vector3(pq.x, 0.3, pq.y), Vector3(2.4, 0.6, 1.8), rot, Color(0.5, 0.48, 0.45))
			_box(dec.box, Vector3(pq.x, 2.5, pq.y), Vector3(2.8, 0.14, 2.2), rot, col.darkened(0.25))
			var fw := sx + 9.0
			var fd := sz + 16.0
			var fc := Color(0.36, 0.3, 0.24) if rng.randf() < 0.5 else Color(0.5, 0.52, 0.5)
			for e in [[0.0, fd * 0.5, fw, 0.12], [0.0, -fd * 0.5, fw, 0.12], [fw * 0.5, 0.0, 0.12, fd], [-fw * 0.5, 0.0, 0.12, fd]]:
				var fq: Vector2 = W.call(float(e[0]), float(e[1]))
				if map.building_at(fq.x, fq.y) < 0 and map.road_dist(fq.x, fq.y) > 1.0:
					_box(dec.box, Vector3(fq.x, 0.85, fq.y), Vector3(float(e[2]), 1.7, float(e[3])), rot, fc)
			if rng.randf() < 0.5:
				var sq: Vector2 = W.call(sx * 0.5 + 3.0, -sz * 0.5 - 3.5)
				if map.building_at(sq.x, sq.y) < 0:
					_box(dec.box, Vector3(sq.x, 1.2, sq.y), Vector3(3.6, 2.4, 5.0), rot, Color(0.45, 0.42, 0.38))
			if rng.randf() < 0.6:
				var cq: Vector2 = W.call(-sx * 0.5 - 2.6, hs.y + 2.0)
				if map.building_at(cq.x, cq.y) < 0 and map.road_dist(cq.x, cq.y) > 1.5:
					Batch.push(dec.car, Transform3D(Basis(Vector3.UP, -rot), Vector3(cq.x, 0.0, cq.y)), _pick(rng, CAR_PAINT), Color(rng.randf(), 0, 0, 0))
		if style == 3 and long > 30.0:
			# workshop gates and a floodlight over them
			var q: Vector2 = W.call(0.0 if along_x else hs.x + 0.1, hs.y + 0.1 if along_x else 0.0)
			_box(dec.box, Vector3(q.x, 2.6, q.y), Vector3(5.0, 5.2, 0.2) if along_x else Vector3(0.2, 5.2, 5.0), rot, Color(0.25, 0.27, 0.3))
			Batch.push(dec.lamp, Transform3D(Basis(), Vector3(q.x, 6.5, q.y)), Color(1.0, 0.8, 0.5), Color(rng.randf(), 0.0, 0.8, 0.0018))


## Posts of the lamps along the avenues (their glow is always there, see CityMap._build_road).
static func _decor_road_lamps(map, t: int, dec: Decor) -> void:
	if not map.road_lamps.has(t):
		return
	var rl: PackedFloat32Array = map.road_lamps[t]
	for i in rl.size() / 4:
		var o := i * 4
		if map.is_cleared(rl[o], rl[o + 2], 2.0):
			continue
		Batch.push(dec.pole, Transform3D(Basis(Vector3.UP, rl[o + 3]) * Basis.from_scale(Vector3(1.1, rl[o + 1] / 9.0, 1.1)), Vector3(rl[o], 0, rl[o + 2])), Color(0.22, 0.23, 0.25), Color(0, 0, 0, 0))
		dec.lights.append_array(PackedFloat32Array([rl[o] - sin(rl[o + 3]) * 1.9, rl[o + 1] - 0.3, rl[o + 2] - cos(rl[o + 3]) * 1.9, 0.9, 0.93, 1.0, -sin(rl[o + 3]), -cos(rl[o + 3])]))
