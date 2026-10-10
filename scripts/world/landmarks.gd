extends RefCounted
## Landmark toolkit: primitives (boxes, domes, beams) and generic builders — bridges at any angle,
## thermal power plants, lattice TV towers, railway stations, airports, river / sea ports, stadiums,
## cathedrals, skyscrapers, container terminals, tank farms, a Ferris wheel, a lighthouse.
## Every city composes its unique skyline from these in scripts/world/cities/<id>.gd.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Shaders = preload("res://scripts/world/shaders.gd")

const PUB := 2
const IND := 1

## Height of the rail deck on a railway bridge (the trains run on it) and of a road bridge, and
## the length of a road bridge's approach ramp.
const RAIL_DECK := 14.6
const ROAD_DECK := 15.0
const RAMP := 130.0
## A small river gets a low bridge: the road surface this high, short ramps.
const LOW_DECK := 3.4
const LOW_RAMP := 44.0

static var root: Node3D
static var _gold: ShaderMaterial


static func begin(map) -> void:
	root = Node3D.new()
	root.name = "Landmarks"
	map.add_child(root)


## Every part of a landmark is drawn only as far as its size can be seen: a spire for many
## kilometres, a railing for a few hundred metres.
static func finish() -> void:
	_set_ranges(root)


static func _set_ranges(n: Node) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			if mi.mesh != null and mi.visibility_range_end <= 0.0:
				var size := (mi.global_transform.basis * mi.mesh.get_aabb().size).abs()
				var big := maxf(size.x, maxf(size.y, size.z))
				mi.visibility_range_end = clampf(big * 320.0, 900.0, 60000.0)
		_set_ranges(ch)


# --- Materials & primitives -------------------------------------------------------------------
## Gilded domes and statues: they shine a little by day and glow under the floodlights at night.
static func gold() -> ShaderMaterial:
	if _gold == null:
		_gold = flood(Color(1.0, 0.76, 0.33), 0.28, 1.0, 1.1, 0.4)
	return _gold


static var _lit := {}


## Facade washed by floodlights (Shaders.FLOODLIT): `e` is how strongly it is lit.
static func lit(c: Color, e := 0.12) -> ShaderMaterial:
	return flood(c, 0.8, 0.0, e * 3.2, e * 0.25)


static func flood(c: Color, rough: float, metal: float, strength: float, day := 0.0) -> ShaderMaterial:
	var key := "%s_%.2f_%.2f_%.2f_%.2f" % [c.to_html(), rough, metal, strength, day]
	if _lit.has(key):
		return _lit[key]
	var m := Shaders.material(Shaders.FLOODLIT)
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("flood", strength)
	m.set_shader_parameter("day_glow", day)
	_lit[key] = m
	return m


static func group(pos: Vector3, rot_deg := 0.0, parent: Node3D = null) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = deg_to_rad(rot_deg)
	(parent if parent != null else root).add_child(g)
	return g


static func box(g: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return Meshes.box(g, size, pos, mat, rot)


static func cyl(g: Node3D, rt: float, rb: float, h: float, pos: Vector3, mat: Material, seg := 12) -> MeshInstance3D:
	return Meshes.cyl(g, rt, rb, h, pos, mat, Vector3.ZERO, seg)


static func sph(g: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := Meshes.part(g, Fx.sphere(r, 12), mat, pos)
	mi.scale = sc
	return mi


## Straight beam between two local points (cables, lattice members, arch segments).
static func beam(g: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Fx.cube(Vector3(t, t, 1.0))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)
	var mid := (a + b) * 0.5
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(d.normalized(), up) * Basis.from_scale(Vector3(1, 1, d.length())), mid)


## Orthodox onion dome with a cross, sitting on `base` (local).
static func onion(g: Node3D, base: Vector3, r: float, mat: Material) -> void:
	sph(g, r, base + Vector3(0, r * 0.95, 0), mat, Vector3(1, 1.18, 1))
	cyl(g, 0.0, r * 0.45, r * 1.1, base + Vector3(0, r * 2.35, 0), mat, 8)
	var cm := gold()
	box(g, Vector3(0.18, r * 1.3, 0.18), base + Vector3(0, r * 3.4, 0), cm)
	box(g, Vector3(r * 0.7, 0.16, 0.16), base + Vector3(0, r * 3.6, 0), cm)


static func domed_drum(g: Node3D, base: Vector3, r: float, h: float, wall: Material, dome: Material) -> void:
	cyl(g, r, r, h, base + Vector3(0, h * 0.5, 0), wall, 12)
	onion(g, base + Vector3(0, h, 0), r * 1.05, dome)


## Invisible footprint (debris, roofs for the walker) of a part of a group, in group-local coordinates.
static func fp(map, g: Node3D, local: Vector3, half: Vector2, h: float, fname: String, kind := PUB) -> void:
	var w := g.transform * local
	map.add_footprint(Vector2(w.x, w.z), half, -g.rotation.y, h, kind, fname)


static func light(map, g: Node3D, local: Vector3, col := Color(1.0, 0.08, 0.05), blink := true, base := 1.3, k := 0.0045) -> void:
	var w := g.transform * local
	map.add_light(w, col, blink, base, k)


static func target(map, pos: Vector3, tname: String, kind := "") -> void:
	map.targets.append({"pos": pos, "name": tname, "kind": kind})


## A building of the city's instanced blocks (lit windows, collapses like any house) in group space.
static func block(map, g: Node3D, local: Vector3, half: Vector2, h: float, style: int, col: Color, bname := "", kind := PUB, roof_h := 0.0, roof_col := Color(0.35, 0.3, 0.3)) -> int:
	var w := g.transform * local
	return map.add_building(Vector2(w.x, w.z), half, -g.rotation.y, h, style, col, kind, roof_h, roof_col, bname)


# --- Generic church (the city generator puts these into historic districts) ---------------------------
static func small_church(map, pos: Vector3, rot: float, rng: RandomNumberGenerator, register := true) -> void:
	var g := group(pos, -rad_to_deg(rot))
	var walls: Array = [Color(0.95, 0.95, 0.9), Color(0.95, 0.88, 0.6), Color(0.6, 0.8, 0.9), Color(0.92, 0.8, 0.8)]
	var wall := lit(walls[rng.randi() % walls.size()], 0.15)
	var dome: Material = gold() if rng.randf() < 0.6 else Fx.solid([Color(0.2, 0.45, 0.3), Color(0.15, 0.3, 0.6)][rng.randi() % 2], 0.35, 0.6)
	box(g, Vector3(12, 11, 18), Vector3(0, 5.5, 0), wall)
	box(g, Vector3(18, 9, 8), Vector3(0, 4.5, 0), wall)
	domed_drum(g, Vector3(0, 11, 0), 2.6, 4.0, wall, dome)
	if rng.randf() < 0.6:
		for s in [Vector3(-4, 11, -6), Vector3(4, 11, -6), Vector3(-4, 11, 6), Vector3(4, 11, 6)]:
			domed_drum(g, s, 1.1, 2.0, wall, dome)
	# bell tower
	box(g, Vector3(6, 16, 6), Vector3(0, 8, -12), wall)
	onion(g, Vector3(0, 16, -12), 1.8, dome)
	if register:
		fp(map, g, Vector3(0, 0, -3), Vector2(9, 15), 16.0, "церковь")


## A big cross-domed cathedral: a main drum, `domes` smaller ones around it and an optional
## stepped bell tower in front (scale 1 ≈ 30 × 22 m).
static func cathedral(map, pos: Vector3, rot_deg: float, cname: String, wall_c: Color, dome_m: Material, s := 1.0, domes := 4, bell := true, bell_name := "") -> Node3D:
	var g := group(pos, rot_deg)
	var wall := lit(wall_c, 0.18)
	box(g, Vector3(30, 16, 22) * s, Vector3(0, 8 * s, 0), wall)
	box(g, Vector3(14, 12, 34) * s, Vector3(0, 6 * s, 0), wall)
	domed_drum(g, Vector3(0, 16 * s, 0), 4.0 * s, 6.0 * s, wall, dome_m)
	var ring := [Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6), Vector3(0, 0, -11), Vector3(0, 0, 11)]
	for i in mini(domes, ring.size()):
		domed_drum(g, (ring[i] as Vector3) * s + Vector3(0, 16 * s, 0), 1.8 * s, 3.0 * s, wall, dome_m)
	fp(map, g, Vector3.ZERO, Vector2(15, 17) * s, 30.0 * s, cname)
	if bell:
		var bt := Vector3(0, 0, 26 * s)
		for spec in [[Vector3(11, 14, 11), 7.0], [Vector3(9, 12, 9), 20.0], [Vector3(7, 10, 7), 31.0]]:
			box(g, (spec[0] as Vector3) * s, bt + Vector3(0, float(spec[1]) * s, 0), wall)
		onion(g, bt + Vector3(0, 36 * s, 0), 3.0 * s, dome_m)
		fp(map, g, bt, Vector2(6, 6) * s, 46.0 * s, bell_name if bell_name != "" else cname)
		light(map, g, bt + Vector3(0, 48 * s, 0))
	map.reserve(pos.x, pos.z, 30.0 * s)
	return g


## Classical public building (opera, university, museum): a body with a portico, optional dome.
static func classical(map, pos: Vector3, rot_deg: float, bname: String, size: Vector3, col: Color, dome = null, portico := true) -> Node3D:
	var g := group(pos, rot_deg)
	var m := lit(col, 0.2)
	box(g, size, Vector3(0, size.y * 0.5, 0), m)
	box(g, Vector3(size.x + 0.6, 1.2, size.z + 0.6), Vector3(0, size.y + 0.6, 0), lit(col.lightened(0.15), 0.2))
	if portico:
		var cw := minf(size.x * 0.5, 30.0)
		box(g, Vector3(cw, 2.0, 5.0), Vector3(0, size.y * 0.75, size.z * 0.5 + 2.5), m)
		box(g, Vector3(cw, size.y * 0.75, 0.2), Vector3(0, size.y * 0.37, size.z * 0.5 + 0.1), Fx.glow(Color(1.0, 0.85, 0.6), 0.9))
		var n := int(cw / 3.5)
		for i in n:
			cyl(g, 0.6, 0.7, size.y * 0.74, Vector3(-cw * 0.5 + 1.5 + i * (cw - 3.0) / maxf(n - 1, 1), size.y * 0.37, size.z * 0.5 + 4.2), m, 8)
	if dome is Material:
		sph(g, minf(size.x, size.z) * 0.28, Vector3(0, size.y + 1.0, 0), dome, Vector3(1, 0.7, 1))
	fp(map, g, Vector3.ZERO, Vector2(size.x * 0.5, size.z * 0.5), size.y + (minf(size.x, size.z) * 0.2 if dome is Material else 0.0), bname)
	map.reserve(pos.x, pos.z, Vector2(size.x, size.z).length() * 0.55)
	return g


## A column monument (Independence monument style) with a golden figure on top.
static func column(map, pos: Vector3, mname: String, h := 44.0, stone := Color(0.94, 0.94, 0.92)) -> Node3D:
	var g := group(pos, 0.0)
	var white := lit(stone, 0.25)
	cyl(g, 8.0, 9.0, 1.2, Vector3(0, 0.6, 0), Fx.solid(Color(0.5, 0.48, 0.46)), 24)
	box(g, Vector3(9, 6, 9), Vector3(0, 3.6, 0), white)
	cyl(g, 1.7, 2.0, h, Vector3(0, 6.6 + h * 0.5, 0), white, 16)
	cyl(g, 2.8, 1.8, 3.0, Vector3(0, h + 8.0, 0), white, 16)
	cyl(g, 0.7, 1.4, 5.0, Vector3(0, h + 12.0, 0), gold(), 10)
	sph(g, 0.8, Vector3(0, h + 15.2, 0), gold())
	fp(map, g, Vector3.ZERO, Vector2(5, 5), h + 14.0, mname)
	map.add_light(pos + Vector3(0, 1.5, 0), Color(1.0, 0.9, 0.7), false, 6.0, 0.003)
	map.reserve(pos.x, pos.z, 16.0)
	return g


## Skyscraper with warning lights and a lit crown. rot in degrees, half = footprint half-size.
static func tower(map, c: Vector2, half: Vector2, rot_deg: float, h: float, style: int, col: Color, tname: String, crown := Color(0.5, 0.9, 1.0)) -> void:
	map.add_building(c, half, deg_to_rad(rot_deg), h, style, col, PUB, 0.0, Color(), tname)
	map.reserve(c.x, c.y, half.length() + 6.0)
	var r := deg_to_rad(rot_deg)
	var ca := cos(r)
	var sa := sin(r)
	for s in [-1.0, 1.0]:
		var lx: float = s * (half.x - 0.8)
		var lz: float = s * (half.y - 0.8)
		map.add_light(Vector3(c.x + lx * ca - lz * sa, h + 1.0, c.y + lx * sa + lz * ca), Color(1.0, 0.08, 0.05), true, 1.4, 0.005)
	map.add_light(Vector3(c.x, h + 0.5, c.y), crown, false, 3.0, 0.004)


# --- Bridges ---------------------------------------------------------------------------------------
## A bridge from a to b (world xz, bank to bank plus the approaches). Styles: girder, cable (one tall
## pylon), cable_a (A-shaped pylon), arch, metro (two decks), truss, pedestrian, rail (a railway deck).
## Returns {"a", "b", "deck", "style", "fp"} for the traffic and the trains.
static func bridge(map, a: Vector2, b: Vector2, style: String, bname: String, is_target := false, road_w := 12.0, low := false) -> Dictionary:
	# bridges are lit at night: the piers and girders softly, the pylons and cables brighter
	var concrete := flood(Color(0.5, 0.5, 0.52), 0.85, 0.0, 0.25)
	var steel := flood(Color(0.62, 0.66, 0.7), 0.5, 0.6, 0.55)
	var cable_m := flood(Color(0.85, 0.87, 0.9), 0.4, 0.7, 0.9)
	var d := b - a
	var length := d.length()
	var half := length * 0.5
	var mid := (a + b) * 0.5
	var ang := atan2(-d.y, d.x)
	var g := group(Vector3(mid.x, 0, mid.y), rad_to_deg(ang))
	var ped := style == "pedestrian"
	var rail := style == "rail"
	var deck_y := ROAD_DECK if not ped and not rail else (12.0 if ped else RAIL_DECK - 0.7)
	if low and not ped:
		# a plain slab just above the water, whatever the style asked for
		deck_y = LOW_DECK - (0.7 if rail else 1.15)
		if not rail:
			style = "low"
	var width := 6.0 if ped else (9.0 if rail else road_w * 2.0 + 4.0)
	var deck_mat: Material = Fx.solid(Color(0.9, 0.9, 0.92), 0.5) if ped else concrete
	box(g, Vector3(length, 2.2 if not rail else 1.4, width), Vector3(0, deck_y, 0), deck_mat)
	if not rail:
		box(g, Vector3(length, 0.08, width - 3.0), Vector3(0, deck_y + 1.12, 0), Fx.solid(Color(0.08, 0.08, 0.09), 0.9))
		# kerb rails along both edges
		for s in [-1.0, 1.0]:
			box(g, Vector3(length, 1.1, 0.25), Vector3(0, deck_y + 1.65, s * (width * 0.5 - 0.2)), steel)
	var wa: Vector3 = g.transform * Vector3(-half - 6.0, 0, 0)
	var wb: Vector3 = g.transform * Vector3(half + 6.0, 0, 0)
	map.reserve(wa.x, wa.z, width + 8.0)
	map.reserve(wb.x, wb.z, width + 8.0)
	# piers stand in the water
	var k := -half + 30.0
	while k < half - 20.0:
		var pw: Vector3 = g.transform * Vector3(k, 0, 0)
		if map.water_dist(pw.x, pw.z) < 6.0:
			for s in ([-1.0, 1.0] if width > 14.0 else [0.0]):
				var pp: Vector3 = g.transform * Vector3(k, 0, s * width * 0.28)
				map.add_cyl(pp, 2.6 if not rail else 2.0, deck_y - 1.0, Color(0.46, 0.46, 0.48))
		k += 60.0
	# approaches: the deck ramps down to the road on both banks
	if not ped and not rail:
		var ramp := LOW_RAMP if low else RAMP
		var tilt := rad_to_deg(atan2(deck_y + 1.0, ramp))
		for s in [-1.0, 1.0]:
			box(g, Vector3(ramp + 2.0, 1.6, width), Vector3(s * (half + ramp * 0.5), (deck_y + 1.0) * 0.5 - 0.6, 0), concrete, Vector3(0, 0, -s * tilt))
			box(g, Vector3(ramp + 2.0, 0.08, width - 3.0), Vector3(s * (half + ramp * 0.5), (deck_y + 1.0) * 0.5 + 0.26, 0), Fx.solid(Color(0.08, 0.08, 0.09), 0.9), Vector3(0, 0, -s * tilt))
			for q in 3:
				var rw: Vector3 = g.transform * Vector3(s * (half + ramp * (0.2 + q * 0.3)), 0, 0)
				map.reserve(rw.x, rw.z, width * 0.5 + 6.0)
	# deck lamps (both sides) and car streams
	var lamp_col := Color(0.55, 0.75, 1.0) if ped else Color(0.9, 0.93, 1.0)
	var x := -half + 10.0
	while x < half:
		for s in [-1.0, 1.0]:
			light(map, g, Vector3(x, deck_y + (4.0 if rail else 9.0), s * (width * 0.5 - 0.8)), lamp_col, false, 1.1, 0.0022)
			if not rail and not ped:
				box(g, Vector3(0.3, 8.0, 0.3), Vector3(x, deck_y + 5.0, s * (width * 0.5 - 0.5)), steel)
		x += 34.0
	var ga: Vector3 = g.transform * Vector3(-half, 0, 0)
	var gb: Vector3 = g.transform * Vector3(half, 0, 0)
	if rail:
		pass
	elif not ped:
		map.add_traffic(Vector2(ga.x, ga.z), Vector2(gb.x, gb.z), 1.2, deck_y + 1.15, road_w)
		map.add_people(Vector2(ga.x, ga.z), Vector2(gb.x, gb.z), road_w + 0.6, deck_y + 1.15)
	else:
		map.add_people(Vector2(ga.x, ga.z), Vector2(gb.x, gb.z), 1.2, deck_y + 1.15)
	var water_half := maxf(half - 60.0, 30.0)
	match style:
		"cable_a":
			var px := half * 0.25
			var top := deck_y + 100.0
			var hw := width * 0.5 + 3.0
			for s in [-1.0, 1.0]:
				beam(g, Vector3(px, 0, s * hw), Vector3(px, top, s * 2.0), 4.0, concrete)
			box(g, Vector3(4.5, 12, 7), Vector3(px, top - 3.0, 0), concrete)
			var reach := minf(water_half * 0.85, 300.0)
			for i in 12:
				var dd := 20.0 + i * (reach - 20.0) / 11.0
				for s in [-1.0, 1.0]:
					beam(g, Vector3(px, top - 6.0 - i * 3.0, 0), Vector3(px + dd, deck_y + 1.0, s * (width * 0.5 - 0.6)), 0.4, cable_m)
					beam(g, Vector3(px, top - 6.0 - i * 3.0, 0), Vector3(px - dd, deck_y + 1.0, s * (width * 0.5 - 0.6)), 0.4, cable_m)
			for hh in [top * 0.5, top + 3.0]:
				light(map, g, Vector3(px, hh, 0))
			var pw2: Vector3 = g.transform * Vector3(px, 0, 0)
			map.add_footprint(Vector2(pw2.x, pw2.z), Vector2(4.0, hw), -ang, top, PUB, bname)
		"cable":
			var px := -half * 0.12
			var top := deck_y + 120.0
			box(g, Vector3(8, top, 9), Vector3(px, top * 0.5, 0), concrete)
			box(g, Vector3(10, 4, width + 4.0), Vector3(px, deck_y - 2.4, 0), concrete)
			var reach := minf(water_half * 0.85, 300.0)
			for i in 14:
				var dd := 18.0 + i * (reach - 18.0) / 13.0
				for s in [-1.0, 1.0]:
					beam(g, Vector3(px, top - 4.0 - i * 4.4, 0), Vector3(px + s * dd, deck_y + 1.0, 0), 0.42, cable_m)
			for hh in [top * 0.33, top * 0.66, top + 1.5]:
				light(map, g, Vector3(px, hh, 0))
			var pw3: Vector3 = g.transform * Vector3(px, 0, 0)
			map.add_footprint(Vector2(pw3.x, pw3.z), Vector2(4.5, 5.0), -ang, top, PUB, bname)
		"arch":
			var span := minf(water_half * 0.9, 240.0)
			var rise := clampf(span * 0.32, 30.0, 70.0)
			var n_arch := maxi(1, int(round(water_half / span)))
			for ai in n_arch:
				var cx0 := (ai - (n_arch - 1) * 0.5) * span * 2.0
				for s in [-1.0, 1.0]:
					var prev := Vector3(cx0 - span, deck_y, s * (width * 0.5 + 0.6))
					for i in range(1, 21):
						var t := float(i) / 20.0
						var ax := lerpf(-span, span, t)
						var ay := deck_y + rise * (1.0 - pow(ax / span, 2.0))
						var p := Vector3(cx0 + ax, ay, s * (width * 0.5 + 0.6))
						beam(g, prev, p, 2.6, steel)
						if i < 20 and i % 2 == 0:
							beam(g, p, Vector3(cx0 + ax, deck_y + 1.0, s * (width * 0.5 + 0.6)), 0.3, cable_m)
						prev = p
				light(map, g, Vector3(cx0, deck_y + rise + 2.0, 0))
		"metro":
			# the metro runs in the middle between the carriageways, on its own raised deck
			box(g, Vector3(length, 1.4, 9.0), Vector3(0, deck_y + 7.0, 0), concrete)
			var xx := -half + 12.0
			while xx < half:
				box(g, Vector3(1.4, 6.0, 1.4), Vector3(xx, deck_y + 4.0, -3.4), concrete)
				box(g, Vector3(1.4, 6.0, 1.4), Vector3(xx, deck_y + 4.0, 3.4), concrete)
				xx += 24.0
		"girder":
			for s in [-1.0, 1.0]:
				box(g, Vector3(length, 4.0, 1.0), Vector3(0, deck_y - 2.0, s * (width * 0.5 - 0.5)), steel)
		"truss", "rail":
			# (a low railway bridge is a plain plate girder: no truss over it)
			var bay := 26.0
			var segs := maxi(1, int(length / bay))
			bay = length / segs
			var th := 15.0
			for s in ([-width * 0.5 - 0.5, width * 0.5 + 0.5] if not low else []):
				beam(g, Vector3(-half, deck_y + th, s), Vector3(half, deck_y + th, s), 1.1, steel)
				for i in segs:
					var x0 := -half + i * bay
					beam(g, Vector3(x0, deck_y + 0.5, s), Vector3(x0 + bay, deck_y + th, s), 0.7, steel)
					beam(g, Vector3(x0, deck_y + th, s), Vector3(x0 + bay, deck_y + 0.5, s), 0.7, steel)
		"pedestrian":
			for s in [-1.0, 1.0]:
				box(g, Vector3(length, 1.2, 0.15), Vector3(0, deck_y + 1.7, s * 2.9), Fx.glow(Color(0.4, 0.7, 1.0), 0.6))
			# two slim pylons with hangers
			for px in [-half * 0.35, half * 0.35]:
				box(g, Vector3(1.6, 34.0, 1.6), Vector3(px, deck_y + 17.0, 0), Fx.solid(Color(0.9, 0.9, 0.92), 0.5))
				for i in 5:
					for s in [-1.0, 1.0]:
						beam(g, Vector3(px, deck_y + 32.0 - i * 3.0, 0), Vector3(px + s * (16.0 + i * 14.0), deck_y + 1.5, 0), 0.18, cable_m)
	var fi: int = map.add_footprint(mid, Vector2(half, width * 0.5), -ang, deck_y + (0.7 if rail else 1.15), PUB, bname)
	if is_target:
		target(map, Vector3(mid.x, deck_y, mid.y), bname, "bridge")
	return {"a": a, "b": b, "deck": deck_y + (0.7 if rail else 1.15), "style": style, "fp": fi, "name": bname, "w": road_w}


# --- Thermal power plants -------------------------------------------------------------------------
static func power_plant(map, c: Vector3, rot_deg: float, pname: String, towers := 1, stacks := 2, stack_h := 180.0) -> void:
	var brick := Fx.solid(Color(0.46, 0.33, 0.28), 0.9)
	var conc := Fx.solid(Color(0.62, 0.62, 0.6), 0.9)
	var white := Fx.solid(Color(0.86, 0.86, 0.84), 0.8)
	var red := Fx.solid(Color(0.75, 0.14, 0.12), 0.8)
	var winm := Fx.glow(Color(1.0, 0.8, 0.5), 1.2)
	var g := group(c, rot_deg)
	# the turbine hall, the boiler house and the control block (a real plant is 300 m long)
	box(g, Vector3(180, 34, 46), Vector3(0, 17, 0), brick)
	for i in 4:
		box(g, Vector3(174, 1.6, 0.3), Vector3(0, 7 + i * 7, 23.1), winm)
	box(g, Vector3(120, 22, 36), Vector3(-20, 11, 44), conc)
	box(g, Vector3(60, 52, 40), Vector3(50, 26, -10), conc)
	box(g, Vector3(30, 14, 22), Vector3(-80, 7, -36), conc)
	fp(map, g, Vector3(0, 0, 14), Vector2(92, 50), 34.0, pname, IND)
	fp(map, g, Vector3(50, 0, -10), Vector2(30, 20), 52.0, pname, IND)
	for si in stacks:
		var sx := -40.0 + si * 80.0 / maxf(stacks - 1, 1) if stacks > 1 else 0.0
		var base := Vector3(sx, 0, -52)
		var bands := 8
		var bh := stack_h / bands
		for i in bands:
			var r0 := lerpf(7.5, 3.6, float(i) / bands)
			var r1 := lerpf(7.5, 3.6, float(i + 1) / bands)
			cyl(g, r1, r0, bh, base + Vector3(0, (i + 0.5) * bh, 0), white if i % 2 == 0 else red, 16)
		fp(map, g, base, Vector2(7.5, 7.5), stack_h, "дымовая труба ТЭЦ", IND)
		for h in [stack_h * 0.33, stack_h * 0.66, stack_h + 1.5]:
			light(map, g, base + Vector3(0, h, 0), Color(1.0, 0.08, 0.05), true, 1.8, 0.0055)
		var sw: Vector3 = g.transform * (base + Vector3(0, stack_h + 2.0, 0))
		map.add_smoke(sw, false)
	# cooling towers (hyperboloid from two cones) with steam plumes
	for ti in towers:
		var ct := Vector3(140, 0, 20 - ti * 90.0)
		cyl(g, 22.0, 34.0, 44.0, ct + Vector3(0, 22, 0), conc, 28)
		cyl(g, 25.0, 22.0, 28.0, ct + Vector3(0, 58, 0), conc, 28)
		fp(map, g, ct, Vector2(32, 32), 72.0, "градирня ТЭЦ", IND)
		var steam := CPUParticles3D.new()
		steam.mesh = Fx.sphere(1.0, 6)
		steam.material_override = Fx.smoke_mat()
		steam.amount = 28
		steam.lifetime = 12.0
		steam.direction = Vector3.UP
		steam.spread = 12.0
		steam.initial_velocity_min = 5.0
		steam.initial_velocity_max = 9.0
		steam.gravity = Vector3(2.0, 0.8, 0.6)
		steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		steam.emission_sphere_radius = 16.0
		steam.scale_amount_min = 14.0
		steam.scale_amount_max = 28.0
		var sg := Gradient.new()
		sg.set_color(0, Color(0.75, 0.75, 0.78, 0.35))
		sg.set_color(1, Color(0.6, 0.6, 0.65, 0.0))
		steam.color_ramp = sg
		steam.position = ct + Vector3(0, 74, 0)
		steam.visibility_range_end = 9000.0
		g.add_child(steam)
	for i in 12:
		light(map, g, Vector3(-88 + i * 16, 35, 23.5), Color(1.0, 0.7, 0.4), false, 1.1, 0.002)
	map.reserve(c.x, c.z, 150.0 + (towers - 1) * 50.0)
	target(map, c + Vector3(0, 20, 0), pname, "tpp")


# --- Towers --------------------------------------------------------------------------------------
## Lattice TV tower (Kyiv, Kharkiv, Dnipro and Odesa all have one). `height` is the real height to
## the tip of the antenna; the lattice body takes about two thirds of it.
static func lattice_tower(map, pos: Vector3, tname: String, height := 385.0, is_target := true, spread := -1.0) -> void:
	var g := group(pos, 0.0)
	var steel := Fx.solid(Color(0.66, 0.66, 0.68), 0.45, 0.7)
	var red := Fx.solid(Color(0.72, 0.16, 0.12), 0.5, 0.5)
	if spread < 0.0:
		spread = height * 0.12
	var top := height * 0.5
	var waist := spread * 0.22
	var legs := [Vector3(-spread, 0, -spread), Vector3(spread, 0, -spread), Vector3(spread, 0, spread), Vector3(-spread, 0, spread)]
	var tops := [Vector3(-waist, top, -waist), Vector3(waist, top, -waist), Vector3(waist, top, waist), Vector3(-waist, top, waist)]
	var bays := 8
	for i in 4:
		beam(g, legs[i], tops[i], height * 0.008 + 0.8, steel)
		# lattice bracing between neighbouring legs
		var j := (i + 1) % 4
		for k in bays:
			var t0 := float(k) / bays
			var t1 := float(k + 1) / bays
			beam(g, (legs[i] as Vector3).lerp(tops[i], t0), (legs[j] as Vector3).lerp(tops[j], t1), 0.5, steel)
			beam(g, (legs[j] as Vector3).lerp(tops[j], t0), (legs[i] as Vector3).lerp(tops[i], t1), 0.5, steel)
			beam(g, (legs[i] as Vector3).lerp(tops[i], t1), (legs[j] as Vector3).lerp(tops[j], t1), 0.4, steel)
	# the equipment decks, the central lift shaft and the mast in red-and-white bands
	cyl(g, waist * 1.9, waist * 1.9, height * 0.03, Vector3(0, top * 0.62, 0), steel, 16)
	cyl(g, waist * 1.6, waist * 1.6, height * 0.035, Vector3(0, top + height * 0.02, 0), steel, 16)
	cyl(g, height * 0.006 + 0.6, height * 0.006 + 0.6, top, Vector3(0, top * 0.5, 0), steel, 8)
	var m0 := top + height * 0.04
	var mh := height - m0
	for b in 6:
		var r0 := lerpf(waist * 0.7, 0.5, b / 6.0)
		var r1 := lerpf(waist * 0.7, 0.5, (b + 1) / 6.0)
		cyl(g, r1, r0, mh / 6.0, Vector3(0, m0 + (b + 0.5) * mh / 6.0, 0), red if b % 2 == 0 else steel, 8)
	for hgt in [top * 0.62, top, m0 + mh * 0.33, m0 + mh * 0.66, height]:
		light(map, g, Vector3(0, hgt + 2.0, 0), Color(1.0, 0.08, 0.05), true, 2.2, 0.006)
		for s in [Vector3(-waist, 0, 0), Vector3(waist, 0, 0)]:
			light(map, g, s + Vector3(0, hgt, 0), Color(1.0, 0.08, 0.05), true, 1.6, 0.005)
	fp(map, g, Vector3.ZERO, Vector2(spread + 1.0, spread + 1.0), top * 0.6, tname)
	fp(map, g, Vector3.ZERO, Vector2(waist * 2.0, waist * 2.0), height * 0.96, tname)
	map.reserve(pos.x, pos.z, spread * 1.5 + 14.0)
	if is_target:
		target(map, pos + Vector3(0, top * 0.5, 0), tname, "tv")


# --- Transport -----------------------------------------------------------------------------------------
## Railway station: a main hall with a tower, platforms with canopies and a parked train (local +x).
static func station(map, pos: Vector3, rot_deg: float, sname: String, col := Color(0.95, 0.86, 0.6), tower_h := 32.0) -> Node3D:
	var g := group(pos, rot_deg)
	var cream := lit(col, 0.18)
	box(g, Vector3(150, 22, 34), Vector3(0, 11, 0), cream)
	box(g, Vector3(46, tower_h, 38), Vector3(0, tower_h * 0.5, 0), cream)
	box(g, Vector3(24, tower_h * 0.6, 0.3), Vector3(0, tower_h * 0.55, -19.2), Fx.glow(Color(1.0, 0.85, 0.55), 1.2))
	cyl(g, 0.0, 3.0, 14.0, Vector3(0, tower_h + 7.0, 0), gold(), 8)
	fp(map, g, Vector3.ZERO, Vector2(75, 17), 22.0, sname)
	fp(map, g, Vector3.ZERO, Vector2(23, 19), tower_h, sname)
	# platforms, canopies and tracks
	for i in 7:
		var z := 30.0 + i * 13.0
		box(g, Vector3(460, 0.4, 3.2), Vector3(30, 0.2, z), Fx.solid(Color(0.14, 0.13, 0.12)))
		box(g, Vector3(380, 0.6, 6.0), Vector3(30, 6.5, z + 6.5), Fx.solid(Color(0.4, 0.42, 0.45), 0.6, 0.4))
		var x := -150.0
		while x < 220.0:
			light(map, g, Vector3(x, 6.0, z + 6.5), Color(0.95, 0.95, 1.0), false, 0.9, 0.0022)
			x += 30.0
	for k in 2:
		var tr := Meshes.metro_train(10)
		tr.position = Vector3(-90 + k * 60, 0, 36.5 + k * 39.0)
		tr.rotation.y = PI * 0.5
		g.add_child(tr)
	var cw: Vector3 = g.transform * Vector3(30, 0, 70)
	map.reserve(pos.x, pos.z, 90.0)
	map.reserve(cw.x, cw.z, 235.0)
	target(map, pos + Vector3(0, 10, 0), sname, "rail")
	return g


## An airport: the runway along local x (2–3 km in reality), a taxiway, the apron with the
## terminal, the control tower and parked airliners on the +z side.
static func airport(map, pos: Vector3, rot_deg: float, aname: String, runway := 2300.0) -> void:
	var g := group(pos, rot_deg)
	var strip := Fx.solid(Color(0.1, 0.1, 0.11), 0.9)
	box(g, Vector3(runway, 0.3, 45), Vector3(0, 0.2, 0), strip)
	box(g, Vector3(runway * 0.9, 0.3, 22), Vector3(0, 0.2, 150), strip)
	box(g, Vector3(360, 0.3, 180), Vector3(0, 0.2, 250), strip)
	for s in [-1.0, 0.0, 1.0]:
		box(g, Vector3(22, 0.3, 150), Vector3(s * runway * 0.4, 0.2, 75), strip)
	# the centre line and the threshold bars
	var paint := Fx.solid(Color(0.8, 0.8, 0.76), 0.8)
	var cx := -runway * 0.5 + 60.0
	while cx < runway * 0.5 - 60.0:
		box(g, Vector3(30, 0.06, 0.9), Vector3(cx, 0.38, 0), paint)
		cx += 60.0
	var n := int(runway / 60.0)
	for i in n:
		var x := -runway * 0.5 + 30.0 + i * 60.0
		for s in [-23.5, 23.5]:
			light(map, g, Vector3(x, 0.8, s), Color(1.0, 0.95, 0.85), false, 0.9, 0.0024)
		light(map, g, Vector3(x * 0.9, 0.8, 162.0), Color(0.3, 0.5, 1.0), false, 0.8, 0.002)
	for s in [-1.0, 1.0]:
		for k in 8:
			light(map, g, Vector3(s * (runway * 0.5 + 30.0 + k * 30.0), 1.5, 0), Color(1.0, 0.15, 0.1) if s < 0 else Color(0.3, 1.0, 0.4), false, 1.3, 0.003)
	# terminal, control tower, parked aircraft
	block(map, g, Vector3(0, 0, 370), Vector2(110, 26), 18.0, 2, Color(0.4, 0.5, 0.6), aname)
	block(map, g, Vector3(190, 0, 360), Vector2(45, 30), 16.0, 3, Color(0.6, 0.62, 0.64), aname, IND, 5.0, Color(0.4, 0.42, 0.45))
	cyl(g, 3.5, 4.5, 40.0, Vector3(150, 20, 330), Fx.solid(Color(0.85, 0.85, 0.85)), 10)
	cyl(g, 7.0, 5.5, 6.0, Vector3(150, 43, 330), Fx.glow(Color(0.5, 0.9, 0.8), 0.9), 12)
	fp(map, g, Vector3(150, 0, 330), Vector2(6, 6), 46.0, aname)
	light(map, g, Vector3(150, 48, 330))
	var white := Fx.solid(Color(0.92, 0.93, 0.95), 0.4)
	for p in [Vector3(-120, 0, 280), Vector3(-60, 0, 280), Vector3(10, 0, 280), Vector3(80, 0, 280)]:
		var a := group(p, 90.0, g)
		cyl(a, 1.9, 1.9, 36.0, Vector3(0, 3.6, 0), white, 12).rotation_degrees = Vector3(90, 0, 0)
		cyl(a, 0.0, 1.9, 4.0, Vector3(0, 3.6, -20.0), white, 12).rotation_degrees = Vector3(-90, 0, 0)
		box(a, Vector3(34, 0.5, 5.5), Vector3(0, 3.0, 1.5), white)
		box(a, Vector3(12, 0.4, 3.0), Vector3(0, 4.2, 16.5), white)
		box(a, Vector3(0.5, 7, 5), Vector3(0, 8, 16), Fx.solid(Color(0.1, 0.35, 0.7)))
		for sx in [-6.0, 6.0]:
			cyl(a, 1.0, 1.0, 3.6, Vector3(sx, 2.0, -1.0), Fx.solid(Color(0.3, 0.32, 0.36), 0.4, 0.6), 10).rotation_degrees = Vector3(90, 0, 0)
	for x in range(-150, 160, 60):
		light(map, g, Vector3(x, 22.0, 340), Color(1.0, 0.9, 0.7), false, 1.6, 0.0022)
	var steps := int(runway / 110.0) + 1
	for i in steps:
		var p: Vector3 = g.transform * Vector3(-runway * 0.5 + i * runway / maxf(steps - 1, 1), 0, 60)
		map.reserve(p.x, p.z, 130.0)
	var tp: Vector3 = g.transform * Vector3(0, 0, 290)
	map.reserve(tp.x, tp.z, 240.0)
	target(map, g.transform * Vector3(0, 8, 340), aname, "airport")


## Cargo port on a quay: gantry cranes along the water (local +z faces the water), warehouses behind.
static func port(map, pos: Vector3, rot_deg: float, pname: String, cranes := 4, hall_name := "", hall_col := Color(0.95, 0.95, 0.92)) -> Node3D:
	var g := group(pos, rot_deg)
	var crane := Fx.solid(Color(0.85, 0.55, 0.15), 0.6, 0.3)
	for i in cranes:
		var c := Vector3(-(cranes - 1) * 12.0 + i * 24.0, 0, 8)
		for s in [-3.0, 3.0]:
			box(g, Vector3(1.0, 18, 1.0), c + Vector3(s, 9, -2), crane)
			box(g, Vector3(1.0, 18, 1.0), c + Vector3(s, 9, 4), crane)
		box(g, Vector3(8, 4, 8), c + Vector3(0, 20, 1), crane)
		beam(g, c + Vector3(0, 21, 1), c + Vector3(0, 34, 26), 0.9, crane)
		light(map, g, c + Vector3(0, 35, 26))
		fp(map, g, c + Vector3(0, 0, 1), Vector2(4, 4), 22.0, "портовый кран", IND)
	for i in 3:
		block(map, g, Vector3(-30.0 + i * 30.0, 0, -18), Vector2(12, 8), 10.0, 3, Color(0.55, 0.5, 0.45), "склад порта", IND, 3.0, Color(0.3, 0.32, 0.35))
	if hall_name != "":
		block(map, g, Vector3(cranes * 12.0 + 24.0, 0, 0), Vector2(20, 9), 14.0, 1, hall_col, hall_name)
		var rs: Vector3 = g.transform * Vector3(cranes * 12.0 + 24.0, 0, 0)
		map.reserve(rs.x, rs.z, 24.0)
	map.reserve(pos.x, pos.z, 26.0 + cranes * 8.0)
	target(map, pos + Vector3(0, 8, 0), pname, "port")
	return g


## Stadium bowl with a lit roof ring and a green pitch.
## A stadium at its real size (rx × rz are the outer half-axes: 130 × 105 m for a 70 000 arena).
static func stadium(map, pos: Vector3, rot_deg: float, sname: String, rx := 130.0, rz := 105.0, h := 38.0) -> void:
	var st := group(pos, rot_deg)
	var seats := Fx.solid(Color(0.75, 0.75, 0.78), 0.7)
	var dark := Fx.solid(Color(0.3, 0.32, 0.36), 0.8)
	var n := 56
	var depth := minf(rx, rz) * 0.36
	for i in n:
		var a := TAU * i / n
		for tier in 3:
			# three tiers stepping down towards the pitch
			var k := 1.0 - (tier + 0.5) * depth / 3.0 / minf(rx, rz)
			var p := Vector3(cos(a) * rx * k, 0, sin(a) * rz * k)
			var th := h * (1.0 - tier * 0.3)
			var seg := box(st, Vector3(depth / 3.0 + 0.4, th, TAU * maxf(rx, rz) / n + 0.6), p + Vector3(0, th * 0.5, 0), seats if tier > 0 else dark)
			seg.rotation.y = -atan2(sin(a) * rx, cos(a) * rz)
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.ring_mesh(1.0, 0.1)
	ring.material_override = Fx.glow(Color(0.85, 0.92, 1.0), 1.2)
	ring.scale = Vector3(rx + 6.0, 60, rz + 6.0)
	ring.position = Vector3(0, h + 3.0, 0)
	st.add_child(ring)
	var pitch := PlaneMesh.new()
	pitch.size = Vector2(105.0, 68.0)
	Meshes.part(st, pitch, Fx.glow(Color(0.2, 0.55, 0.25), 0.25), Vector3(0, 0.3, 0))
	for i in 8:
		var a := TAU * i / 8.0
		fp(map, st, Vector3(cos(a) * (rx - depth * 0.5), 0, sin(a) * (rz - depth * 0.5)), Vector2(depth * 0.9, depth * 0.9), h, sname)
		light(map, st, Vector3(cos(a) * rx, h + 8.0, sin(a) * rz), Color(0.95, 0.97, 1.0), false, 2.4, 0.003)
	map.reserve(pos.x, pos.z, maxf(rx, rz) + 24.0)


# --- Industry & leisure -----------------------------------------------------------------------------------
## Stacks of shipping containers on a yard (w × d, local axes), plus yard floodlights.
static func containers(map, c: Vector2, rot_deg: float, w: float, d: float, rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3), Color(0.55, 0.55, 0.58), Color(0.9, 0.9, 0.88), Color(0.4, 0.25, 0.5)]
	var r := deg_to_rad(rot_deg)
	var ca := cos(r)
	var sa := sin(r)
	var x := -w * 0.5 + 4.0
	while x < w * 0.5 - 4.0:
		var z := -d * 0.5 + 2.0
		while z < d * 0.5 - 2.0:
			if rng.randf() < 0.85:
				var n := rng.randi_range(1, 4)
				for k in n:
					var p := Vector2(c.x + x * ca - z * sa, c.y + x * sa + z * ca)
					map.add_solid(Vector3(p.x, 1.3 + k * 2.6, p.y), Vector3(12.0, 2.5, 2.4), r, cols[rng.randi() % cols.size()])
				var pf := Vector2(c.x + x * ca - z * sa, c.y + x * sa + z * ca)
				map.add_footprint(pf, Vector2(6.0, 1.2), r, n * 2.6, IND, "контейнерный терминал")
			z += 3.0
		x += 14.0
	for i in 4:
		var lx := lerpf(-w * 0.5, w * 0.5, i / 3.0)
		map.add_light(Vector3(c.x + lx * ca, 16.0, c.y + lx * sa), Color(1.0, 0.85, 0.6), false, 1.4, 0.0022)
	map.reserve(c.x, c.y, Vector2(w, d).length() * 0.5)


## A plant: rows of long workshop halls with saw-tooth roofs, chimneys with warning lights.
static func factory(map, c: Vector3, rot_deg: float, fname: String, halls := 4, stacks := 2, is_target := false) -> Node3D:
	var g := group(c, rot_deg)
	var cols := [Color(0.52, 0.5, 0.48), Color(0.58, 0.46, 0.4), Color(0.46, 0.48, 0.5)]
	for i in halls:
		var lz := (i - (halls - 1) * 0.5) * 52.0
		block(map, g, Vector3(0, 0, lz), Vector2(110, 22), 16.0 + (i % 2) * 5.0, 3, cols[i % cols.size()], fname, IND, 5.0, Color(0.36, 0.38, 0.4))
	for s in stacks:
		var p := Vector3(136.0, 0, (s - (stacks - 1) * 0.5) * 40.0)
		var w: Vector3 = g.transform * p
		var h := 90.0 + s * 20.0
		map.add_cyl(w, 3.4, h, Color(0.62, 0.58, 0.55))
		map.add_cyl(w + Vector3(0, h - 8.0, 0), 3.8, 4.0, Color(0.75, 0.15, 0.12))
		map.add_footprint(Vector2(w.x, w.z), Vector2(3.8, 3.8), 0.0, h, IND, "заводская труба")
		map.add_light(w + Vector3(0, h + 1.0, 0), Color(1.0, 0.08, 0.05), true, 1.5, 0.005)
		if s == 0:
			map.add_smoke(w + Vector3(0, h + 1.0, 0))
	for i in 8:
		light(map, g, Vector3(-105.0 + i * 30.0, 20.0, halls * 26.0 + 4.0), Color(1.0, 0.75, 0.45), false, 1.3, 0.002)
	map.reserve(c.x, c.z, 130.0 + halls * 18.0)
	if is_target:
		target(map, c + Vector3(0, 10, 0), fname, "plant")
	return g


## Oil / fuel tank farm: `n` tanks in two rows.
static func tanks(map, c: Vector3, rot_deg: float, n: int, r: float, tname: String, is_target := false) -> void:
	var g := group(c, rot_deg)
	var m := Fx.solid(Color(0.78, 0.78, 0.76), 0.7, 0.2)
	for i in n:
		var p := Vector3((i / 2) * (r * 2.6) - (n / 4) * r * 2.6, 0, (i % 2) * r * 2.6 - r * 1.3)
		cyl(g, r, r, r * 0.9, p + Vector3(0, r * 0.45, 0), m, 16)
		fp(map, g, p, Vector2(r, r), r * 0.9, tname, IND)
	light(map, g, Vector3(0, r + 2.0, 0), Color(1.0, 0.8, 0.5), false, 1.0, 0.002)
	map.reserve(c.x, c.z, n * r * 0.9 + r * 2.0)
	if is_target:
		target(map, c + Vector3(0, 6, 0), tname, "oil")


static func ferris_wheel(map, pos: Vector3, rot_deg: float, r: float, wname: String) -> void:
	var g := group(pos, rot_deg)
	var steel := Fx.solid(Color(0.85, 0.85, 0.88), 0.4, 0.6)
	var hub := Vector3(0, r + 4.0, 0)
	var rim := MeshInstance3D.new()
	rim.mesh = Fx.ring_mesh(r, 0.6)
	rim.material_override = Fx.glow(Color(0.9, 0.5, 1.0), 1.3)
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.position = hub
	g.add_child(rim)
	for i in 16:
		var a := TAU * i / 16.0
		var p := hub + Vector3(cos(a) * r, sin(a) * r, 0)
		beam(g, hub, p, 0.25, steel)
		box(g, Vector3(1.6, 1.8, 1.6), p + Vector3(0, -1.2, 0), Fx.solid(Color(0.95, 0.3, 0.3) if i % 2 == 0 else Color(0.3, 0.6, 0.95)))
	for s in [-1.0, 1.0]:
		beam(g, Vector3(-r * 0.45, 0, s * 3.0), hub, 0.8, steel)
		beam(g, Vector3(r * 0.45, 0, s * 3.0), hub, 0.8, steel)
	fp(map, g, Vector3(0, 0, 0), Vector2(r * 0.5, 4), r * 2.0 + 4.0, wname)
	light(map, g, hub + Vector3(0, r + 0.8, 0))
	map.reserve(pos.x, pos.z, r * 0.6 + 6.0)


static func lighthouse(map, pos: Vector3, lname: String, h := 26.0) -> void:
	var g := group(pos, 0.0)
	var white := lit(Color(0.95, 0.95, 0.92), 0.25)
	cyl(g, 1.8, 2.6, h, Vector3(0, h * 0.5, 0), white, 12)
	cyl(g, 2.4, 2.4, 3.0, Vector3(0, h + 1.5, 0), Fx.glow(Color(1.0, 0.95, 0.7), 2.4), 12)
	cyl(g, 0.0, 2.6, 2.0, Vector3(0, h + 4.0, 0), Fx.solid(Color(0.7, 0.15, 0.12)), 12)
	map.add_light(pos + Vector3(0, h + 1.5, 0), Color(1.0, 0.95, 0.7), true, 4.0, 0.004)
	fp(map, g, Vector3.ZERO, Vector2(2.6, 2.6), h + 5.0, lname)


## A breakwater / pier: a long concrete strip on the water (walkable deck) from a to b.
static func pier(map, a: Vector2, b: Vector2, w: float, pname: String) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	var ang := atan2(-d.y, d.x)
	var g := group(Vector3(mid.x, 0, mid.y), rad_to_deg(ang))
	box(g, Vector3(d.length(), 2.2, w), Vector3(0, 0.9, 0), Fx.solid(Color(0.52, 0.5, 0.47), 0.9))
	var x := -d.length() * 0.5 + 10.0
	while x < d.length() * 0.5:
		light(map, g, Vector3(x, 4.0, 0), Color(1.0, 0.85, 0.6), false, 0.8, 0.002)
		x += 40.0
	map.add_footprint(mid, Vector2(d.length() * 0.5, w * 0.5), -ang, 2.0, PUB, pname)


## A merchant ship (local +x = bow): hull, deck cargo, the bridge at the stern with lit windows.
## kind: "container", "bulk" (hatches and deck cranes) or "barge" (a river barge, no bridge).
static func ship(map, pos: Vector3, rot_deg: float, length: float, kind := "container", sname := "судно") -> void:
	var g := group(pos, rot_deg)
	var w := clampf(length * 0.16, 8.0, 26.0)
	var hull := Fx.solid([Color(0.45, 0.1, 0.08), Color(0.12, 0.14, 0.18), Color(0.15, 0.3, 0.45)][int(absf(pos.x + pos.z)) % 3], 0.7)
	box(g, Vector3(length, 4.0, w), Vector3(0, 1.2, 0), hull)
	box(g, Vector3(length * 0.14, 3.6, w * 0.7), Vector3(length * 0.54, 1.4, 0), hull, Vector3(0, 45, 0))
	box(g, Vector3(length * 0.98, 0.3, w * 0.96), Vector3(0, 3.3, 0), Fx.solid(Color(0.5, 0.5, 0.48), 0.8))
	if kind == "container":
		var cols := [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3), Color(0.6, 0.6, 0.62)]
		var x := -length * 0.3
		var i := 0
		while x < length * 0.4:
			box(g, Vector3(6.0, 2.6 * (2 + i % 3), w * 0.86), Vector3(x, 3.4 + 1.3 * (2 + i % 3), 0), Fx.solid(cols[i % cols.size()], 0.8))
			x += 6.6
			i += 1
	elif kind == "bulk":
		for i in 4:
			var x := -length * 0.25 + i * length * 0.16
			box(g, Vector3(length * 0.1, 1.2, w * 0.6), Vector3(x, 4.0, 0), Fx.solid(Color(0.3, 0.32, 0.3), 0.8))
			beam(g, Vector3(x + length * 0.08, 3.5, 0), Vector3(x + length * 0.08, 16.0, 0), 0.6, Fx.solid(Color(0.85, 0.7, 0.2), 0.6))
	if kind != "barge":
		var bx := -length * 0.4
		var white := lit(Color(0.92, 0.92, 0.9), 0.15)
		box(g, Vector3(length * 0.1, 10.0, w * 0.9), Vector3(bx, 8.0, 0), white)
		box(g, Vector3(length * 0.1 + 0.2, 1.0, w * 0.9 + 0.2), Vector3(bx, 11.0, 0), Fx.glow(Color(1.0, 0.85, 0.6), 1.2))
		box(g, Vector3(1.2, 6.0, 1.2), Vector3(bx - 2.0, 16.0, 0), Fx.solid(Color(0.2, 0.2, 0.22)))
		light(map, g, Vector3(bx, 19.5, 0), Color(1.0, 1.0, 0.9), false, 1.2, 0.003)
	for s in [-1.0, 1.0]:
		light(map, g, Vector3(length * 0.3, 4.2, s * w * 0.5), Color(1, 0.15, 0.1) if s < 0 else Color(0.2, 1, 0.3), false, 0.9, 0.0025)
	light(map, g, Vector3(length * 0.5, 6.0, 0), Color(1.0, 0.95, 0.85), false, 1.0, 0.0025)
	fp(map, g, Vector3.ZERO, Vector2(length * 0.5, w * 0.5), 10.0 if kind != "barge" else 4.0, sname, IND)
