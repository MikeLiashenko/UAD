extends RefCounted
## District-based city generator. Every district of the city (CityDef.districts) has its own rotated
## street grid (avenues every third line — the ground shader draws exactly the same grid), and fills
## its blocks according to its character: historic perimeter blocks, Soviet panel microdistricts,
## "khrushchyovkas", Stalin-era avenues, new high-rises, industry, docks, seaside villas and private
## houses with pitched roofs in the suburbs.

const Landmarks = preload("res://scripts/world/landmarks.gd")

const HALF := 1000.0


const PANEL := [Color(0.78, 0.76, 0.72), Color(0.7, 0.72, 0.74), Color(0.82, 0.8, 0.72), Color(0.66, 0.68, 0.66), Color(0.75, 0.7, 0.62), Color(0.84, 0.74, 0.58), Color(0.6, 0.68, 0.78)]
const STALIN := [Color(0.86, 0.76, 0.55), Color(0.82, 0.66, 0.5), Color(0.9, 0.85, 0.72), Color(0.72, 0.56, 0.46), Color(0.78, 0.8, 0.78), Color(0.62, 0.74, 0.68), Color(0.86, 0.72, 0.72), Color(0.92, 0.9, 0.82)]
const ODESA := [Color(0.93, 0.86, 0.68), Color(0.88, 0.8, 0.62), Color(0.95, 0.92, 0.82), Color(0.85, 0.72, 0.6), Color(0.78, 0.84, 0.8), Color(0.92, 0.78, 0.64), Color(0.96, 0.94, 0.88)]
const PODIL := [Color(0.9, 0.8, 0.6), Color(0.72, 0.84, 0.78), Color(0.88, 0.72, 0.7), Color(0.8, 0.82, 0.9), Color(0.94, 0.9, 0.78), Color(0.85, 0.66, 0.52)]
const BRICK := [Color(0.64, 0.42, 0.34), Color(0.74, 0.68, 0.62), Color(0.82, 0.8, 0.76), Color(0.7, 0.5, 0.4)]
const GLASS := [Color(0.25, 0.35, 0.5), Color(0.3, 0.42, 0.46), Color(0.36, 0.38, 0.44), Color(0.2, 0.3, 0.36), Color(0.45, 0.4, 0.3)]
const NEWRES := [Color(0.92, 0.9, 0.86), Color(0.86, 0.62, 0.42), Color(0.56, 0.63, 0.76), Color(0.95, 0.92, 0.84), Color(0.7, 0.3, 0.25), Color(0.4, 0.45, 0.5)]
const INDUST := [Color(0.5, 0.5, 0.52), Color(0.56, 0.46, 0.4), Color(0.62, 0.6, 0.55), Color(0.42, 0.45, 0.48)]
const HOUSE := [Color(0.92, 0.9, 0.85), Color(0.86, 0.78, 0.64), Color(0.76, 0.7, 0.62), Color(0.9, 0.84, 0.8), Color(0.82, 0.62, 0.5), Color(0.8, 0.86, 0.8)]
const ROOF := [Color(0.5, 0.18, 0.12), Color(0.35, 0.2, 0.15), Color(0.3, 0.32, 0.35), Color(0.24, 0.4, 0.28), Color(0.56, 0.3, 0.2), Color(0.2, 0.25, 0.4)]
const METAL_ROOF := [Color(0.34, 0.36, 0.38), Color(0.25, 0.42, 0.34), Color(0.4, 0.3, 0.26)]
const TREE := Color(0.12, 0.3, 0.1)

const RES := 0
const IND := 1
const PUB := 2


static func nearest(districts: Array, x: float, z: float) -> int:
	var best := 0
	var bd := INF
	for i in districts.size():
		var d: Array = districts[i]
		var dd := Vector2(x - float(d[1]), z - float(d[2])).length_squared()
		if dd < bd:
			bd = dd
			best = i
	return best


static func _w(ctx: Dictionary, lx: float, lz: float) -> Vector2:
	return Vector2(ctx.seed.x + lx * ctx.ca - lz * ctx.sa, ctx.seed.y + lx * ctx.sa + lz * ctx.ca)


static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi() % arr.size()]


## Places one building if it lies fully inside its district's (convex) Voronoi cell — so
## neighbouring districts never overlap — and clear of water, parks and landmarks.
static func _fits(map, ctx: Dictionary, cx: float, cz: float, sx: float, sz: float) -> bool:
	var p := _w(ctx, cx, cz)
	var r := Vector2(sx, sz).length() * 0.5
	if map.urban_at(p.x, p.y) == 0 or map.zone_at(p.x, p.y) == GS.Zone.FOREST:
		return false
	if map.water_dist(p.x, p.y) < r + 2.0 or map.is_reserved(p.x, p.y, r * 0.85):
		return false
	var di: int = ctx.di
	for s in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var c := _w(ctx, cx + s.x * sx, cz + s.y * sz)
		if nearest(ctx.ds, c.x, c.y) != di:
			return false
	return _clear_of_roads(map, ctx, cx, cz, sx, sz, r)


## Highways and railways cut through the blocks: the footprint (sampled every ≤ 12 m, so a road
## cannot slip between the samples) must stay off them.
static func _clear_of_roads(map, ctx: Dictionary, cx: float, cz: float, sx: float, sz: float, r: float) -> bool:
	var p := _w(ctx, cx, cz)
	var dc: float = map.road_dist(p.x, p.y)
	if dc > r + 1.5:
		return true
	if dc < 1.5:
		return false
	var nx := int(ceil(sx / 12.0)) + 1
	var nz := int(ceil(sz / 12.0)) + 1
	for iz in nz:
		for ix in nx:
			var q := _w(ctx, cx + (float(ix) / (nx - 1) - 0.5) * (sx + 3.0), cz + (float(iz) / (nz - 1) - 0.5) * (sz + 3.0))
			if map.road_dist(q.x, q.y) < 1.0:
				return false
	return true


static func _b(map, ctx: Dictionary, cx: float, cz: float, sx: float, sz: float, h: float, style: int, col: Color, kind := RES, roof_h := 0.0, roof_col := Color(0.4, 0.2, 0.15)) -> int:
	if not _fits(map, ctx, cx, cz, sx, sz):
		return -1
	var p := _w(ctx, cx, cz)
	var i: int = map.add_building(p, Vector2(sx * 0.5, sz * 0.5), ctx.rot, h, style, col, kind, roof_h, roof_col)
	_details(map, ctx, cx, cz, sx, sz, h, style, col, roof_h, i)
	if h > 44.0:
		# aviation warning lights on two opposite roof corners
		for s in [-1.0, 1.0]:
			var c := _w(ctx, cx + s * (sx * 0.5 - 0.6), cz + s * (sz * 0.5 - 0.6))
			map.add_light(Vector3(c.x, h + 1.2, c.y), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)
	if h > 24.0 and roof_h <= 0.0 and style != 2:
		var mr: Vector2i = map.add_prop_box(Vector3(p.x, h + 1.4, p.y), Vector3(minf(6.0, sx * 0.3), 2.8, minf(4.0, sz * 0.4)), ctx.rot, Color(0.55, 0.55, 0.56))
		map.attach(i, map.b_build, mr, true)
	return i


const GOLD := Color(0.95, 0.72, 0.3)
const NEON_SHOP := [Color(1.0, 0.85, 0.55), Color(0.95, 0.95, 1.0), Color(1.0, 0.5, 0.3), Color(0.5, 0.9, 1.0), Color(1.0, 0.95, 0.7)]
const NEON_SIGN := [Color(1.0, 0.2, 0.35), Color(0.2, 0.7, 1.0), Color(0.3, 1.0, 0.5), Color(1.0, 0.8, 0.2), Color(0.9, 0.35, 1.0), Color(1.0, 1.0, 1.0)]


## What a real building carries: loggias with lit windows down the panel blocks, entrance lamps,
## air conditioners, antennas and water tanks on the flat roofs, corner turrets with spires on
## the Stalin-era palaces, stepped crowns on the towers. All of it is glued to the building.
static func _details(map, ctx: Dictionary, cx: float, cz: float, sx: float, sz: float, h: float, style: int, col: Color, roof_h: float, bi: int) -> void:
	var rng: RandomNumberGenerator = map.rng
	var along_x := sx >= sz
	var long := sx if along_x else sz
	var deep := sz if along_x else sx
	if style == 0 and h >= 14.0 and long >= 28.0:
		var n := int(long / 7.5)
		var lc := col.lightened(0.1)
		for side in [-1.0, 1.0]:
			for k in n:
				if rng.randf() < 0.22:
					continue
				var t := (k + 0.5) / n - 0.5
				var off: float = side * (deep * 0.5 + 0.55)
				var lx := cx + (t * (long - 4.0) if along_x else off)
				var lz := cz + (off if along_x else t * (long - 4.0))
				var q := _w(ctx, lx, lz)
				var size := Vector3(2.8, h - 3.4, 1.1) if along_x else Vector3(1.1, h - 3.4, 2.8)
				map.attach(bi, map.b_build, map.add_prop_box(Vector3(q.x, 3.0 + (h - 3.4) * 0.5, q.y), size, ctx.rot, lc, 0), false)
		# a lamp over every entrance on the courtyard side
		var ne := maxi(1, int(long / 18.0))
		for k in ne:
			var t := (k + 0.5) / ne - 0.5
			var off := deep * 0.5 + 0.9
			var q := _w(ctx, cx + (t * long if along_x else off), cz + (off if along_x else t * long))
			map.add_light(Vector3(q.x, 2.8, q.y), Color(1.0, 0.82, 0.55), false, 0.7, 0.0018)
	if roof_h <= 0.0 and style != 4 and style != 3 and h > 8.0:
		var clutter := rng.randi_range(1, 3) if style != 2 else rng.randi_range(0, 2)
		for k in clutter:
			var q := _w(ctx, cx + rng.randf_range(-0.35, 0.35) * sx, cz + rng.randf_range(-0.35, 0.35) * sz)
			map.attach(bi, map.b_detail, map.add_detail(Vector3(q.x, h + 0.5, q.y), Vector3(1.5, 1.0, 1.1), ctx.rot, Color(0.62, 0.62, 0.64)), true)
		if rng.randf() < 0.35:
			var q := _w(ctx, cx + rng.randf_range(-0.4, 0.4) * sx, cz + rng.randf_range(-0.4, 0.4) * sz)
			var ah := rng.randf_range(3.0, 7.0)
			map.attach(bi, map.b_detail, map.add_detail(Vector3(q.x, h + ah * 0.5, q.y), Vector3(0.14, ah, 0.14), 0.0, Color(0.4, 0.4, 0.42)), true)
			map.attach(bi, map.b_detail, map.add_detail(Vector3(q.x, h + ah * 0.8, q.y), Vector3(2.2, 0.1, 0.1), ctx.rot, Color(0.4, 0.4, 0.42)), true)
		if (style == 0 or style == 1) and rng.randf() < 0.15:
			var q := _w(ctx, cx + rng.randf_range(-0.3, 0.3) * sx, cz + rng.randf_range(-0.3, 0.3) * sz)
			map.attach(bi, map.b_cyl, map.add_cyl(Vector3(q.x, h, q.y), 1.3, 2.4, Color(0.5, 0.52, 0.55)), true)
	if style == 1 and h >= 18.0 and rng.randf() < 0.14:
		# a corner turret with a spire, the signature of the post-war avenues
		var sgx := -1.0 if rng.randf() < 0.5 else 1.0
		var sgz := -1.0 if rng.randf() < 0.5 else 1.0
		var q := _w(ctx, cx + sgx * (sx * 0.5 - 3.0), cz + sgz * (sz * 0.5 - 3.0))
		var th := h + rng.randf_range(6.0, 11.0)
		map.attach(bi, map.b_build, map.add_prop_box(Vector3(q.x, th * 0.5, q.y), Vector3(6.2, th, 6.2), ctx.rot, col.lightened(0.05), 1), false)
		map.attach(bi, map.b_cyl, map.add_cyl(Vector3(q.x, th, q.y), 1.4, 3.0, col.lightened(0.1)), true)
		map.attach(bi, map.b_cyl, map.add_cyl(Vector3(q.x, th + 3.0, q.y), 0.35, 7.0, GOLD), true)
	var central := String(ctx.kind) in ["historic", "stalin", "new", "odesa", "pechersk", "podil"]
	if central and (style == 1 or style == 2) and long >= 14.0:
		# shop fronts: a lit fascia over the ground floor on one long side
		if rng.randf() < 0.45:
			var sd: float = (deep * 0.5 + 0.25) * (1.0 if rng.randf() < 0.5 else -1.0)
			var q := _w(ctx, cx + (0.0 if along_x else sd), cz + (sd if along_x else 0.0))
			var sz3 := Vector3(long * 0.8, 0.9, 0.25) if along_x else Vector3(0.25, 0.9, long * 0.8)
			map.add_neon(Vector3(q.x, 4.3, q.y), sz3, ctx.rot, NEON_SHOP[rng.randi() % NEON_SHOP.size()])
		# a neon sign on the roof edge of the taller ones
		if h > 22.0 and rng.randf() < 0.14:
			var sd2: float = deep * 0.5 - 0.6
			var q2 := _w(ctx, cx + (0.0 if along_x else sd2), cz + (sd2 if along_x else 0.0))
			var ssz := Vector3(minf(long * 0.5, 16.0), 2.4, 0.4) if along_x else Vector3(0.4, 2.4, minf(long * 0.5, 16.0))
			map.attach(bi, map.b_neon, map.add_neon(Vector3(q2.x, h + 1.8, q2.y), ssz, ctx.rot, NEON_SIGN[rng.randi() % NEON_SIGN.size()]), true)
	if style == 2 and h > 60.0:
		# stepped glass crown
		var q := _w(ctx, cx, cz)
		map.attach(bi, map.b_build, map.add_prop_box(Vector3(q.x, h + 3.0, q.y), Vector3(sx * 0.7, 6.0, sz * 0.7), ctx.rot, col, 2), true)


## A playground in a courtyard: a slide, swings, a sandbox and a bench.
static func _playground(map, ctx: Dictionary, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var c := _w(ctx, x, z)
	if map.building_at(c.x, c.y) >= 0 or map.road_dist(c.x, c.y) < 6.0 or map.water_dist(c.x, c.y) < 6.0 or map.is_reserved(c.x, c.y, 6.0):
		return
	var cols := [Color(0.9, 0.25, 0.2), Color(0.2, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35)]
	var r: float = ctx.rot
	var put := func(lx: float, lz: float, y: float, size: Vector3, colr: Color) -> void:
		var q := _w(ctx, x + lx, z + lz)
		map.add_detail(Vector3(q.x, y, q.y), size, r, colr)
	put.call(0.0, 0.0, 0.15, Vector3(4.0, 0.3, 4.0), Color(0.8, 0.72, 0.5))
	put.call(4.0, 0.0, 1.2, Vector3(1.2, 2.4, 1.2), cols[rng.randi() % 4])
	put.call(5.6, 0.0, 0.8, Vector3(2.4, 0.2, 1.0), cols[rng.randi() % 4])
	for s in [-1.2, 1.2]:
		put.call(-3.5 + s, 3.5, 1.1, Vector3(0.15, 2.2, 0.15), Color(0.35, 0.35, 0.38))
	put.call(-3.5, 3.5, 2.2, Vector3(2.8, 0.15, 0.15), Color(0.35, 0.35, 0.38))
	put.call(-3.5, 3.5, 0.6, Vector3(0.8, 0.08, 0.4), cols[rng.randi() % 4])
	put.call(0.0, -4.0, 0.25, Vector3(2.4, 0.5, 0.6), Color(0.45, 0.3, 0.2))


## A tower crane over a construction site: mast, jib, counter-jib and the warning lights.
static func _crane(map, ctx: Dictionary, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var c := _w(ctx, x, z)
	if map.building_at(c.x, c.y) >= 0 or map.road_dist(c.x, c.y) < 4.0 or map.is_reserved(c.x, c.y, 4.0):
		return
	var h := rng.randf_range(70.0, 105.0)
	var yellow := Color(0.95, 0.72, 0.1)
	map.add_detail(Vector3(c.x, h * 0.5, c.y), Vector3(1.8, h, 1.8), ctx.rot, yellow)
	var a := rng.randf() * TAU
	var d := Vector2(cos(a), sin(a))
	var j := c + d * 20.0
	map.add_detail(Vector3(j.x, h + 1.0, j.y), Vector3(1.2, 1.2, 46.0), -atan2(d.x, d.y), yellow)
	var cj := c - d * 12.0
	map.add_detail(Vector3(cj.x, h + 0.6, cj.y), Vector3(2.4, 2.4, 3.0), -atan2(d.x, d.y), Color(0.5, 0.5, 0.52))
	map.add_detail(Vector3(c.x, h + 4.0, c.y), Vector3(1.0, 6.0, 1.0), ctx.rot, yellow)
	map.add_footprint(c, Vector2(1.5, 1.5), 0.0, h + 7.0, IND, "башенный кран")
	for q in [c, c + d * 42.0]:
		map.add_light(Vector3(q.x, h + 7.5 if q == c else h + 2.0, q.y), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)


static func _trees(map, ctx: Dictionary, x0: float, x1: float, z0: float, z1: float, n: int, rng: RandomNumberGenerator, s := 1.0) -> void:
	if x1 - x0 < 3.0 or z1 - z0 < 3.0:
		return
	for i in n:
		var p := _w(ctx, rng.randf_range(x0, x1), rng.randf_range(z0, z1))
		if map.building_at(p.x, p.y) < 0 and map.water_dist(p.x, p.y) > 2.0 and map.road_dist(p.x, p.y) > 0.5:
			var g := rng.randf_range(0.8, 1.15)
			map.add_tree(p, rng.randf_range(0.7, 1.15) * s, Color(TREE.r * g, TREE.g * g, TREE.b * g))


static func build(map) -> void:
	var rng: RandomNumberGenerator = map.rng
	var ds: Array = map.city.districts
	for di in ds.size():
		var d: Array = ds[di]
		var ctx := {"seed": Vector2(d[1], d[2]), "rot": deg_to_rad(float(d[3])), "B": float(d[4]), "kind": String(d[5]), "di": di, "ds": ds}
		ctx.ca = cos(ctx.rot)
		ctx.sa = sin(ctx.rot)
		var bs: float = ctx.B
		var n := int(ceil(1150.0 / bs))
		for j in range(-n, n):
			for i in range(-n, n):
				var cw := _w(ctx, (i + 0.5) * bs, (j + 0.5) * bs)
				if absf(cw.x) > HALF - 15.0 or absf(cw.y) > HALF - 15.0:
					continue
				if nearest(ds, cw.x, cw.y) != di:
					continue
				var u: int = map.urban_at(cw.x, cw.y)
				if u == 0:
					continue
				var sc := 1.0 if u == 2 else 0.55
				var wl := (7.0 if posmod(i, 3) == 0 else 4.0) * sc
				var wr := (7.0 if posmod(i + 1, 3) == 0 else 4.0) * sc
				var wt := (7.0 if posmod(j, 3) == 0 else 4.0) * sc
				var wb := (7.0 if posmod(j + 1, 3) == 0 else 4.0) * sc
				ctx.x0 = i * bs + wl + 3.0
				ctx.x1 = (i + 1) * bs - wr - 3.0
				ctx.z0 = j * bs + wt + 3.0
				ctx.z1 = (j + 1) * bs - wb - 3.0
				if u == 1:
					_fill_private(map, ctx, rng)
				else:
					_fill_block(map, ctx, rng)
		_streets(map, ctx, rng)


static func _fill_block(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	match String(ctx.kind):
		"historic":
			if r < 0.05:
				_fill_church(map, ctx, rng)
			elif r < 0.12:
				_fill_square(map, ctx, rng)
			elif r < 0.18:
				_fill_new(map, ctx, rng, true)
			else:
				_fill_perimeter(map, ctx, rng, 4, 8, STALIN, 3.6, 0.45)
		"podil":
			var p := _w(ctx, (ctx.x0 + ctx.x1) * 0.5, (ctx.z0 + ctx.z1) * 0.5)
			if r < 0.07:
				_fill_church(map, ctx, rng)
			elif r < 0.14:
				_fill_square(map, ctx, rng)
			elif map.water_dist(p.x, p.y) < 140.0 and r < 0.45:
				_fill_industrial(map, ctx, rng)
			else:
				_fill_perimeter(map, ctx, rng, 3, 5, PODIL, 3.6, 0.6)
		"pechersk":
			if r < 0.35:
				_fill_perimeter(map, ctx, rng, 5, 9, STALIN, 3.6, 0.3)
			elif r < 0.62:
				_fill_new(map, ctx, rng, true)
			elif r < 0.9:
				_fill_panel(map, ctx, rng, [9, 12, 16])
			else:
				_fill_square(map, ctx, rng)
		"west":
			if r < 0.4:
				_fill_khrush(map, ctx, rng)
			elif r < 0.7:
				_fill_panel(map, ctx, rng, [9, 12, 16])
			else:
				_fill_industrial(map, ctx, rng)
		"khrush":
			if r < 0.6:
				_fill_khrush(map, ctx, rng)
			elif r < 0.9:
				_fill_panel(map, ctx, rng, [9, 9, 12])
			else:
				_fill_industrial(map, ctx, rng)
		"mixed":
			if r < 0.35:
				_fill_panel(map, ctx, rng, [9, 12, 16])
			elif r < 0.62:
				_fill_khrush(map, ctx, rng)
			elif r < 0.84:
				_fill_new(map, ctx, rng, false)
			else:
				_fill_industrial(map, ctx, rng)
		"new":
			if r < 0.55:
				_fill_new(map, ctx, rng, false)
			elif r < 0.9:
				_fill_panel(map, ctx, rng, [16, 16, 22])
			else:
				_fill_mall(map, ctx, rng)
		"industrial":
			if r < 0.55:
				_fill_industrial(map, ctx, rng)
			elif r < 0.85:
				_fill_panel(map, ctx, rng, [9, 12, 16])
			else:
				_fill_khrush(map, ctx, rng)
		"stalin":
			# wide Stalin-era avenues: 5–9 storey palaces with spires here and there, a few squares
			if r < 0.06:
				_fill_square(map, ctx, rng)
			elif r < 0.1:
				_fill_church(map, ctx, rng)
			elif r < 0.22:
				_fill_new(map, ctx, rng, true)
			elif r < 0.3:
				_fill_khrush(map, ctx, rng)
			else:
				_fill_perimeter(map, ctx, rng, 5, 9, STALIN, 3.7, 0.2)
		"odesa":
			# 19th-century limestone blocks of 2–4 floors on a strict grid, courtyards and acacias
			if r < 0.06:
				_fill_church(map, ctx, rng)
			elif r < 0.14:
				_fill_square(map, ctx, rng)
			elif r < 0.2:
				_fill_new(map, ctx, rng, true)
			else:
				_fill_perimeter(map, ctx, rng, 2, 4, ODESA, 4.0, 0.35)
		"villas":
			# seaside: private villas, a few new towers, sanatoriums
			if r < 0.5:
				_fill_private(map, ctx, rng)
			elif r < 0.78:
				_fill_new(map, ctx, rng, false)
			else:
				_fill_panel(map, ctx, rng, [9, 12])
		"docks":
			# port land: container yards, warehouses, a few old blocks
			if r < 0.4:
				_fill_containers(map, ctx, rng)
			elif r < 0.8:
				_fill_industrial(map, ctx, rng)
			else:
				_fill_khrush(map, ctx, rng)
		"private":
			if r < 0.85:
				_fill_private(map, ctx, rng)
			else:
				_fill_khrush(map, ctx, rng)
		_:
			if r < 0.75:
				_fill_panel(map, ctx, rng, [9, 12, 16, 16])
			elif r < 0.9:
				_fill_new(map, ctx, rng, false)
			else:
				_fill_khrush(map, ctx, rng)


# --- Block types ---------------------------------------------------------------------------------
## Pre-revolutionary / Stalin-era perimeter block: buildings along the street line, a courtyard inside.
static func _fill_perimeter(map, ctx: Dictionary, rng: RandomNumberGenerator, fmin: int, fmax: int, palette: Array, fh: float, roof_p: float) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var depth := rng.randf_range(9.0, 12.0)
	var style := 1
	if x1 - x0 < depth * 2.0 + 4.0 or z1 - z0 < depth * 2.0 + 4.0:
		# too small for a courtyard: a cluster of houses of different heights
		var nx := 2 if x1 - x0 > 20.0 else 1
		var nz := 2 if z1 - z0 > 20.0 else 1
		var cw := (x1 - x0) / nx
		var cd := (z1 - z0) / nz
		for a in nx:
			for b in nz:
				var roof_h := rng.randf_range(2.5, 4.0) if rng.randf() < roof_p else 0.0
				_b(map, ctx, x0 + (a + 0.5) * cw, z0 + (b + 0.5) * cd, cw - 0.4, cd - 0.4, rng.randi_range(fmin, fmax) * fh, style, _pick(rng, palette), RES, roof_h, _pick(rng, METAL_ROOF))
		return
	for side in 2:
		var zc := z0 + depth * 0.5 if side == 0 else z1 - depth * 0.5
		var x := x0
		while x < x1 - 4.0:
			var seg := minf(rng.randf_range(14.0, 30.0), x1 - x)
			if x1 - (x + seg) < 9.0:
				seg = x1 - x
			if rng.randf() > 0.06:
				var roof_h := rng.randf_range(2.5, 4.5) if rng.randf() < roof_p else 0.0
				_b(map, ctx, x + seg * 0.5, zc, seg - 0.3, depth - rng.randf_range(0.0, 1.5), rng.randi_range(fmin, fmax) * fh, style, _pick(rng, palette), RES, roof_h, _pick(rng, METAL_ROOF))
			x += seg
	for side in 2:
		var xc := x0 + depth * 0.5 if side == 0 else x1 - depth * 0.5
		var z := z0 + depth
		while z < z1 - depth - 4.0:
			var seg := minf(rng.randf_range(14.0, 26.0), z1 - depth - z)
			if z1 - depth - (z + seg) < 8.0:
				seg = z1 - depth - z
			if rng.randf() > 0.12:
				var roof_h := rng.randf_range(2.5, 4.0) if rng.randf() < roof_p else 0.0
				_b(map, ctx, xc, z + seg * 0.5, depth - rng.randf_range(0.0, 1.5), seg - 0.3, rng.randi_range(fmin, fmax) * fh, style, _pick(rng, palette), RES, roof_h, _pick(rng, METAL_ROOF))
			z += seg
	_trees(map, ctx, x0 + depth + 2.0, x1 - depth - 2.0, z0 + depth + 2.0, z1 - depth - 2.0, rng.randi_range(1, 4), rng, 0.8)


## Soviet panel microdistrict: long 9–16 storey slabs, point towers, a school, courtyard trees.
static func _fill_panel(map, ctx: Dictionary, rng: RandomNumberGenerator, floors: Array) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var W := x1 - x0
	var D := z1 - z0
	var fl: int = _pick(rng, floors)
	var h := fl * 3.0
	var col: Color = _pick(rng, PANEL)
	var depth := 12.5
	match rng.randi() % 4:
		0:
			var length := minf(W * 0.92, 96.0)
			_b(map, ctx, (x0 + x1) * 0.5, z0 + depth * 0.5 + 1.0, length, depth, h, 0, col)
			if D > 40.0:
				_b(map, ctx, (x0 + x1) * 0.5, z1 - depth * 0.5 - 1.0, length * rng.randf_range(0.6, 1.0), depth, h, 0, _pick(rng, PANEL))
			if D > 52.0:
				_b(map, ctx, x0 + 10.0, (z0 + z1) * 0.5, 16.0, 16.0, h + 12.0, 0, _pick(rng, PANEL))
			else:
				# row of garages in the courtyard
				_b(map, ctx, (x0 + x1) * 0.5, (z0 + z1) * 0.5, minf(W * 0.6, 40.0), 6.0, 3.0, 6, Color(0.42, 0.42, 0.44))
			if D > 44.0 and rng.randf() < 0.7:
				_playground(map, ctx, (x0 + x1) * 0.5 + W * 0.2, (z0 + z1) * 0.5, rng)
			_trees(map, ctx, x0 + 3.0, x1 - 3.0, z0 + depth + 4.0, z1 - depth - 4.0, rng.randi_range(3, 7), rng)
		1:
			if rng.randf() < 0.6:
				_playground(map, ctx, x0 + depth + (W - depth) * 0.5, z0 + depth + (D - depth) * 0.5, rng)
			_b(map, ctx, (x0 + x1) * 0.5, z0 + depth * 0.5, W * 0.95, depth, h, 0, col)
			var lz := (D - depth) * rng.randf_range(0.55, 0.85)
			_b(map, ctx, x0 + depth * 0.5, z0 + depth + lz * 0.5 + 0.5, depth, lz, h, 0, col)
			_trees(map, ctx, x0 + depth + 4.0, x1 - 3.0, z0 + depth + 4.0, z1 - 3.0, rng.randi_range(3, 6), rng)
		2:
			var cnt := 3 if W > 58.0 else 2
			var tall := maxi(fl, 16) * 3.0 + rng.randi_range(0, 3) * 3.0
			for k in cnt:
				var f := (k + 0.5) / cnt
				_b(map, ctx, lerpf(x0 + 10.0, x1 - 10.0, f), lerpf(z0 + 10.0, z1 - 10.0, f if k % 2 == 0 else 1.0 - f), 17.0, 17.0, tall, 0, _pick(rng, PANEL))
			_trees(map, ctx, x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0, rng.randi_range(4, 8), rng)
		_:
			_b(map, ctx, (x0 + x1) * 0.5, z0 + depth * 0.5, W * 0.9, depth, h, 0, col)
			if D > 40.0:
				# school / kindergarten
				_b(map, ctx, x0 + minf(34.0, W * 0.6) * 0.5 + 2.0, z1 - 9.0, minf(34.0, W * 0.6), 14.0, 10.0, 0, Color(0.9, 0.78, 0.55) if rng.randf() < 0.5 else Color(0.85, 0.65, 0.62))
			_trees(map, ctx, x0 + 2.0, x1 - 2.0, z0 + depth + 3.0, z1 - 17.0, rng.randi_range(4, 8), rng)


## Five-storey "khrushchyovkas" in rows with trees between them.
static func _fill_khrush(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var col: Color = _pick(rng, BRICK)
	var length := minf((x1 - x0) * 0.86, 62.0)
	var z := z0 + 6.0
	while z + 5.5 < z1:
		var off := rng.randf_range(-3.0, 3.0)
		_b(map, ctx, (x0 + x1) * 0.5 + off, z, length, 11.0, 15.0, 0, col if rng.randf() < 0.7 else _pick(rng, BRICK), RES, 2.2 if rng.randf() < 0.25 else 0.0, Color(0.3, 0.3, 0.32))
		if z + 14.0 < z1:
			_trees(map, ctx, x0 + 2.0, x1 - 2.0, z + 8.0, minf(z + 17.0, z1), rng.randi_range(2, 4), rng)
		z += 24.0


## New residential / office high-rises (20–36 floors), optional retail podium and LED crowns.
static func _fill_new(map, ctx: Dictionary, rng: RandomNumberGenerator, central: bool) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var W := x1 - x0
	var D := z1 - z0
	var cnt := 1 if W < 44.0 else rng.randi_range(1, 3)
	var glass := rng.randf() < (0.55 if central else 0.3)
	if rng.randf() < 0.55:
		_b(map, ctx, (x0 + x1) * 0.5, z1 - 6.0, W * 0.95, 11.0, 7.2, 1, _pick(rng, STALIN), PUB if central else RES)
	for k in cnt:
		var f := (k + 0.5) / cnt
		var sx := rng.randf_range(17.0, 24.0)
		var sz := rng.randf_range(15.0, 22.0)
		var fl := rng.randi_range(20, 36)
		var h := fl * (3.4 if glass else 3.1)
		var cx := lerpf(x0 + sx * 0.5 + 1.0, x1 - sx * 0.5 - 1.0, f)
		var cz := lerpf(z0 + sz * 0.5 + 1.0, z1 - sz * 0.5 - 12.0, rng.randf())
		if D < sz + 14.0:
			cz = (z0 + z1) * 0.5
		var col: Color = _pick(rng, GLASS) if glass else _pick(rng, NEWRES)
		_b(map, ctx, cx, cz, sx, sz, h, 2 if glass else 0, col, IND if glass else RES)
		if k == 0 and rng.randf() < 0.1:
			_crane(map, ctx, x1 - 4.0, z0 + 4.0, rng)
		# LED crown lighting, typical for new Kyiv towers
		if rng.randf() < 0.6:
			var lc: Color = _pick(rng, [Color(0.4, 0.9, 1.0), Color(1.0, 1.0, 1.0), Color(0.9, 0.4, 1.0), Color(1.0, 0.8, 0.4)])
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var c := _w(ctx, cx + s.x * sx * 0.5, cz + s.y * sz * 0.5)
				map.add_light(Vector3(c.x, h + 0.3, c.y), lc, false, 1.0, 0.0022)
	_trees(map, ctx, x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0, rng.randi_range(1, 4), rng)


## Warehouses, a factory chimney with warning lights, storage tanks.
static func _fill_industrial(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var W := x1 - x0
	var D := z1 - z0
	var wx := W * rng.randf_range(0.5, 0.8)
	var wz := D * rng.randf_range(0.45, 0.7)
	var saw := rng.randf() < 0.35
	_b(map, ctx, x0 + wx * 0.5, z0 + wz * 0.5, wx, wz, rng.randf_range(8.0, 15.0), 3, _pick(rng, INDUST), IND, 4.0 if saw else 0.0, Color(0.4, 0.42, 0.44))
	if W - wx > 16.0:
		_b(map, ctx, x1 - (W - wx) * 0.5 + 1.0, z0 + D * 0.3, W - wx - 4.0, D * 0.5, rng.randf_range(6.0, 10.0), 3, _pick(rng, INDUST), IND)
	if rng.randf() < 0.45:
		var p := _w(ctx, x1 - 6.0, z1 - 6.0)
		var ch := rng.randf_range(38.0, 70.0)
		map.add_cyl(Vector3(p.x, 0, p.y), rng.randf_range(1.4, 2.2), ch, Color(0.62, 0.58, 0.55))
		map.add_cyl(Vector3(p.x, ch - 6.0, p.y), 2.3, 3.0, Color(0.75, 0.15, 0.12))
		map.add_footprint(p, Vector2(2.2, 2.2), 0.0, ch, IND, "дымовая труба")
		map.add_light(Vector3(p.x, ch + 1.0, p.y), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)
		if rng.randf() < 0.5:
			map.add_smoke(Vector3(p.x, ch + 1.0, p.y))
	elif rng.randf() < 0.5 and D - wz > 16.0:
		for k in 2:
			var p := _w(ctx, x0 + 8.0 + k * 15.0, z1 - 8.0)
			map.add_cyl(Vector3(p.x, 0, p.y), 6.0, 10.0, Color(0.72, 0.72, 0.7))
			map.add_footprint(p, Vector2(6.0, 6.0), 0.0, 10.0, IND, "резервуар")
	for k in 3:
		var p := _w(ctx, rng.randf_range(x0, x1), rng.randf_range(z0, z1))
		map.add_light(Vector3(p.x, 9.0, p.y), Color(1.0, 0.75, 0.45), false, 1.0, 0.002)


## Container yard: stacks of boxes and floodlights (docks of a river / sea port).
static func _fill_containers(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _w(ctx, (ctx.x0 + ctx.x1) * 0.5, (ctx.z0 + ctx.z1) * 0.5)
	var w: float = ctx.x1 - ctx.x0
	var d: float = ctx.z1 - ctx.z0
	if w < 30.0 or d < 20.0:
		_fill_industrial(map, ctx, rng)
		return
	for s in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var q := _w(ctx, (ctx.x0 + ctx.x1) * 0.5 + s.x * w, (ctx.z0 + ctx.z1) * 0.5 + s.y * d)
		if nearest(ctx.ds, q.x, q.y) != int(ctx.di) or map.water_dist(q.x, q.y) < 4.0 or map.road_dist(q.x, q.y) < 2.0:
			_fill_industrial(map, ctx, rng)
			return
	if map.is_reserved(c.x, c.y, 10.0):
		return
	Landmarks.containers(map, c, rad_to_deg(ctx.rot), w, d, rng)


## Shopping mall with a bright facade.
static func _fill_mall(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	_b(map, ctx, (x0 + x1) * 0.5, (z0 + z1) * 0.5, (x1 - x0) * 0.9, (z1 - z0) * 0.8, 14.0, 2, Color(0.35, 0.4, 0.5), PUB)
	for k in 6:
		var p := _w(ctx, lerpf(x0, x1, k / 5.0), z0 + 1.0)
		map.add_light(Vector3(p.x, 12.0, p.y), _pick(rng, [Color(1, 0.3, 0.5), Color(0.3, 0.8, 1.0), Color(1, 0.9, 0.5)]), false, 1.4, 0.0024)


## Square / small park with a monument.
static func _fill_square(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var c := _w(ctx, (x0 + x1) * 0.5, (z0 + z1) * 0.5)
	map.add_cyl(Vector3(c.x, 0, c.y), 2.2, 4.0, Color(0.5, 0.48, 0.46))
	map.add_solid(Vector3(c.x, 6.0, c.y), Vector3(1.4, 4.0, 1.4), ctx.rot, Color(0.3, 0.36, 0.32))
	map.add_light(Vector3(c.x, 1.0, c.y), Color(1.0, 0.85, 0.6), false, 2.0, 0.002)
	_trees(map, ctx, x0, x1, z0, z1, rng.randi_range(6, 12), rng)


static func _fill_church(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _w(ctx, (ctx.x0 + ctx.x1) * 0.5, (ctx.z0 + ctx.z1) * 0.5)
	Landmarks.small_church(map, Vector3(c.x, 0, c.y), ctx.rot, rng)
	_trees(map, ctx, ctx.x0, ctx.x1, ctx.z0, ctx.z1, rng.randi_range(3, 6), rng)


## Suburb: private houses with pitched roofs on garden plots.
static func _fill_private(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = ctx.x0
	var x1: float = ctx.x1
	var z0: float = ctx.z0
	var z1: float = ctx.z1
	var px := x0
	while px + 14.0 < x1:
		var pw := rng.randf_range(17.0, 21.0)
		var pz := z0
		while pz + 14.0 < z1:
			var pd := rng.randf_range(17.0, 21.0)
			if rng.randf() < 0.8:
				var hw := rng.randf_range(7.0, 10.0)
				var hd := rng.randf_range(8.0, 11.0)
				var fl := 1 if rng.randf() < 0.6 else 2
				var cx := px + minf(pw, x1 - px) * 0.5 + rng.randf_range(-2.0, 2.0)
				var cz := pz + hd * 0.5 + 2.0
				_b(map, ctx, cx, cz, hw, hd, fl * 3.1 + 0.4, 4, _pick(rng, HOUSE), RES, rng.randf_range(2.6, 4.2), _pick(rng, ROOF))
				if rng.randf() < 0.7:
					_trees(map, ctx, px + 1.0, px + pw - 1.0, cz + hd * 0.5 + 1.0, pz + pd - 1.0, rng.randi_range(1, 2), rng, 0.65)
			else:
				_trees(map, ctx, px, px + pw, pz, pz + pd, 3, rng, 0.8)
			pz += pd
		px += pw


# --- Streets: lamps, chestnut avenues, car streams -------------------------------------------------
static func _streets(map, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var bs: float = ctx.B
	var di: int = ctx.di
	var n := int(ceil(700.0 / bs))
	var boulevard := String(ctx.kind) in ["historic", "podil", "pechersk", "stalin", "odesa"]
	for axis in 2:
		for k in range(-n, n + 1):
			var avenue := posmod(k, 3) == 0
			var line := k * bs
			for m in range(-30, 30):
				var along := m * 24.0 + 12.0
				var mid := _w(ctx, line, along) if axis == 0 else _w(ctx, along, line)
				if nearest(ctx.ds, mid.x, mid.y) != di:
					continue
				var u: int = map.urban_at(mid.x, mid.y)
				if u == 0 or map.water_dist(mid.x, mid.y) < 6.0 or map.road_dist(mid.x, mid.y) < 4.0:
					continue
				if u == 1 and posmod(m, 2) == 1:
					continue
				var w := (7.0 if avenue else 4.0) * (1.0 if u == 2 else 0.55)
				var col := Color(0.82, 0.88, 1.0) if avenue and u == 2 else Color(1.0, 0.6, 0.25)
				for sgn in [-1.0, 1.0]:
					var across: float = line + sgn * (w + 1.5)
					var p := _w(ctx, across, along) if axis == 0 else _w(ctx, along, across)
					if map.building_at(p.x, p.y) >= 0 or map.road_dist(p.x, p.y) < 1.0:
						continue
					map.add_light(Vector3(p.x, 7.5, p.y), col, false, 0.9, 0.0021)
					map.add_solid(Vector3(p.x, 3.75, p.y), Vector3(0.25, 7.5, 0.25), 0.0, Color(0.2, 0.2, 0.22))
					if rng.randf() < (0.6 if u == 2 else 0.25):
						# cars parked along the kerb, nose to tail
						var ca: float = line + sgn * (w - 1.3)
						var n_cars := rng.randi_range(1, 3)
						for kc in n_cars:
							var al := along - 6.0 + kc * 5.2 + rng.randf_range(-0.4, 0.4)
							var cp := _w(ctx, ca, al) if axis == 0 else _w(ctx, al, ca)
							var cq := _w(ctx, ca, al + 1.0) if axis == 0 else _w(ctx, al + 1.0, ca)
							if map.building_at(cp.x, cp.y) < 0 and map.road_dist(cp.x, cp.y) > 1.0 and map.water_dist(cp.x, cp.y) > 3.0 and not map.is_reserved(cp.x, cp.y, 1.5):
								map.add_parked(cp, (cq - cp) * (1.0 if rng.randf() < 0.8 else -1.0), map.CAR_PAINT[rng.randi() % map.CAR_PAINT.size()])
					if not (boulevard and avenue) and u == 2 and rng.randf() < 0.3:
						var ta2: float = line + sgn * (w + 4.0)
						var t2 := _w(ctx, ta2, along + 12.0) if axis == 0 else _w(ctx, along + 12.0, ta2)
						if map.building_at(t2.x, t2.y) < 0 and map.road_dist(t2.x, t2.y) > 1.0:
							map.add_tree(t2, rng.randf_range(0.65, 0.9), Color(0.12, 0.3, 0.11))
					if boulevard and avenue and u == 2:
						# chestnut trees between lamps (Khreshchatyk style)
						var ta: float = line + sgn * (w + 4.5)
						var t := _w(ctx, ta, along + 12.0) if axis == 0 else _w(ctx, along + 12.0, ta)
						if map.building_at(t.x, t.y) < 0:
							map.add_tree(t, rng.randf_range(0.8, 1.0), Color(0.13, 0.32, 0.11))
			if avenue:
				_traffic_line(map, ctx, axis, line, di)
				if axis == 0:
					_traffic_lights(map, ctx, line, n, bs, rng)


## Signals where an avenue meets the cross streets: two poles on opposite corners, one showing
## red and one green, switching over.
static func _traffic_lights(map, ctx: Dictionary, line: float, n: int, bs: float, rng: RandomNumberGenerator) -> void:
	for j in range(-n, n + 1):
		var along := j * bs
		var c := _w(ctx, line, along)
		if nearest(ctx.ds, c.x, c.y) != int(ctx.di) or map.urban_at(c.x, c.y) != 2 or map.water_dist(c.x, c.y) < 10.0 or map.road_dist(c.x, c.y) < 6.0:
			continue
		var w2 := 7.0 if posmod(j, 3) == 0 else 4.0
		var ph := rng.randf()
		for s in [-1.0, 1.0]:
			var q := _w(ctx, line + s * 8.5, along - s * (w2 + 1.5))
			if map.building_at(q.x, q.y) >= 0:
				continue
			map.add_solid(Vector3(q.x, 2.4, q.y), Vector3(0.2, 4.8, 0.2), 0.0, Color(0.18, 0.18, 0.2))
			map.add_solid(Vector3(q.x, 4.4, q.y), Vector3(0.45, 1.3, 0.45), ctx.rot, Color(0.1, 0.1, 0.1))
			var p2: float = ph + (0.0 if s < 0.0 else 0.5)
			map.b_lights.add(Transform3D(Basis(), Vector3(q.x, 4.8, q.y)), Color(1.0, 0.1, 0.05), Color(p2, 1.0, 0.5, 0.0015))
			map.b_lights.add(Transform3D(Basis(), Vector3(q.x, 4.0, q.y)), Color(0.2, 1.0, 0.35), Color(p2 + 0.5, 1.0, 0.5, 0.0015))


static func _traffic_line(map, ctx: Dictionary, axis: int, line: float, di: int) -> void:
	var run_start := 0.0
	var in_run := false
	var s := -700.0
	while s <= 710.0:
		var p := _w(ctx, line, s) if axis == 0 else _w(ctx, s, line)
		var ok: bool = s <= 700.0 and nearest(ctx.ds, p.x, p.y) == di and map.urban_at(p.x, p.y) == 2 and map.water_dist(p.x, p.y) > 4.0 and map.road_dist(p.x, p.y) > 2.0
		if ok and not in_run:
			run_start = s
			in_run = true
		elif not ok and in_run:
			var a := run_start
			while s - 10.0 - a >= 60.0:
				var b := minf(a + 260.0, s - 10.0)
				var pa := _w(ctx, line, a) if axis == 0 else _w(ctx, a, line)
				var pb := _w(ctx, line, b) if axis == 0 else _w(ctx, b, line)
				map.add_traffic(pa, pb, 0.8)
				map.add_people(pa, pb, 9.3)
				a = b
			in_run = false
		s += 10.0
