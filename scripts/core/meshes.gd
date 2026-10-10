extends RefCounted
## Procedural models built from primitive meshes (box / cylinder / prism / sphere).
## Convention: every model's "forward" is -Z (matches Node3D.look_at).
## Weapon models expose meta: "turret" (yaw node), "pitch" (elevation node), "muzzle", optional "spin".

const Fx = preload("res://scripts/core/fx.gd")


static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return part(parent, Fx.cube(size), mat, pos, rot)


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, seg := 10) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return part(parent, c, mat, pos, rot)


static func node(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func _wheels(root: Node3D, xs: float, zs: Array, r := 0.75) -> void:
	var tire := Fx.solid(Color(0.05, 0.05, 0.055), 0.95)
	var hub := Fx.solid(Color(0.26, 0.28, 0.24), 0.6, 0.4)
	for z in zs:
		for sx in [-1.0, 1.0]:
			var c := Vector3(xs * sx, r, float(z))
			cyl(root, r, r, 0.6, c, tire, Vector3(0, 0, 90), 16)
			# the rim with its hub, a mudguard over the tyre
			cyl(root, r * 0.56, r * 0.56, 0.64, c, hub, Vector3(0, 0, 90), 10)
			cyl(root, r * 0.2, r * 0.2, 0.72, c, tire, Vector3(0, 0, 90), 6)
			box(root, Vector3(0.66, 0.07, r * 2.3), c + Vector3(0, r + 0.14, 0), tire)


static func _weapon_rig(root: Node3D, turret_pos: Vector3, pitch_y: float) -> Array:
	var turret := node(root, turret_pos)
	var pitch := node(turret, Vector3(0, pitch_y, 0))
	root.set_meta("turret", turret)
	root.set_meta("pitch", pitch)
	return [turret, pitch]


# --- Air-defense units -------------------------------------------------------------
static func pickup() -> Node3D:
	var root := Node3D.new()
	var paint := Fx.paint(Color(0.52, 0.48, 0.34), 0.7, 0.2, 0.35)
	var dark := Fx.solid(Color(0.1, 0.1, 0.1), 0.6, 0.3)
	var glass := Fx.solid(Color(0.05, 0.08, 0.1), 0.08, 0.3)
	# the frame, the bonnet, the cab with its glass and the load bed
	box(root, Vector3(3.1, 0.5, 7.0), Vector3(0, 1.0, 0), dark)
	box(root, Vector3(3.2, 0.75, 2.1), Vector3(0, 1.6, -2.45), paint)
	box(root, Vector3(3.2, 0.2, 0.55), Vector3(0, 1.92, -1.5), paint, Vector3(-28, 0, 0))
	box(root, Vector3(3.15, 0.75, 2.5), Vector3(0, 1.6, -0.2), paint)
	box(root, Vector3(2.9, 0.85, 2.0), Vector3(0, 2.4, -0.15), paint)
	box(root, Vector3(2.7, 0.75, 0.08), Vector3(0, 2.38, -1.22), glass, Vector3(-22, 0, 0))
	box(root, Vector3(2.7, 0.6, 0.06), Vector3(0, 2.42, 0.86), glass)
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.06, 0.6, 1.5), Vector3(1.46 * sx, 2.42, -0.2), glass)
		box(root, Vector3(0.12, 0.7, 3.4), Vector3(1.54 * sx, 1.75, 2.6), paint)
		box(root, Vector3(0.5, 0.22, 0.12), Vector3(1.15 * sx, 1.72, -3.52), Fx.glow(Color(1.0, 0.95, 0.8), 0.6))
		box(root, Vector3(0.3, 0.2, 0.1), Vector3(1.3 * sx, 1.6, 4.32), Fx.glow(Color(0.9, 0.1, 0.05), 0.5))
		box(root, Vector3(0.14, 0.12, 0.3), Vector3(1.7 * sx, 2.25, -1.1), dark)
		box(root, Vector3(0.1, 1.2, 0.1), Vector3(1.3 * sx, 2.2, 0.95), dark)
	box(root, Vector3(3.1, 0.7, 0.12), Vector3(0, 1.75, 4.3), paint)
	box(root, Vector3(3.0, 0.1, 3.4), Vector3(0, 1.42, 2.6), dark)
	box(root, Vector3(3.3, 0.3, 0.25), Vector3(0, 1.05, -3.55), dark)
	box(root, Vector3(1.9, 0.4, 0.08), Vector3(0, 1.6, -3.52), dark)
	box(root, Vector3(2.7, 0.1, 0.1), Vector3(0, 2.82, 0.95), dark)
	_wheels(root, 1.6, [-2.3, 2.3])
	var rig := _weapon_rig(root, Vector3(0, 1.8, 1.8), 1.35)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	# the heavy machine gun on its pedestal: receiver, barrel with a flash hider, an ammunition
	# box on the left, spade grips and a shield
	cyl(turret, 0.18, 0.25, 1.3, Vector3(0, 0.65, 0), dark)
	box(turret, Vector3(0.6, 0.1, 0.6), Vector3(0, 0.05, 0), dark)
	box(turret, Vector3(1.5, 0.9, 0.08), Vector3(0, 1.3, -0.7), paint)
	box(pitch, Vector3(0.3, 0.32, 1.1), Vector3(0, 0, 0), dark)
	cyl(pitch, 0.07, 0.08, 2.2, Vector3(0, 0, -1.6), dark, Vector3(90, 0, 0), 8)
	cyl(pitch, 0.11, 0.11, 0.3, Vector3(0, 0, -2.6), dark, Vector3(90, 0, 0), 8)
	cyl(pitch, 0.1, 0.1, 0.9, Vector3(0, 0, -0.95), Fx.solid(Color(0.2, 0.2, 0.2), 0.5, 0.5), Vector3(90, 0, 0), 8)
	box(pitch, Vector3(0.36, 0.34, 0.5), Vector3(-0.36, -0.05, 0.1), Fx.paint(Color(0.3, 0.33, 0.22), 0.8, 0.2, 0.0))
	for sx in [-1.0, 1.0]:
		box(pitch, Vector3(0.05, 0.3, 0.05), Vector3(0.12 * sx, 0, 0.7), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0, -2.7)))
	return root


static func gepard() -> Node3D:
	var root := Node3D.new()
	var olive := Fx.paint(Color(0.3, 0.34, 0.2), 0.8, 0.15, 0.7)
	var dark := Fx.solid(Color(0.1, 0.1, 0.1), 0.7)
	var steel := Fx.solid(Color(0.36, 0.38, 0.36), 0.5, 0.6)
	_tracks(root, 4.3, 7.9)
	# the hull of the Leopard: a sloped glacis, the engine deck with its grilles, tool boxes
	box(root, Vector3(3.6, 1.1, 7.2), Vector3(0, 1.55, 0.2), olive)
	box(root, Vector3(3.6, 0.7, 1.6), Vector3(0, 1.6, -3.9), olive, Vector3(-32, 0, 0))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.5, 0.35, 2.2), Vector3(1.5 * sx, 2.25, 2.4), olive)
		box(root, Vector3(0.3, 0.16, 0.1), Vector3(1.2 * sx, 1.9, -4.35), Fx.glow(Color(1.0, 0.95, 0.8), 0.5))
		box(root, Vector3(1.0, 0.06, 1.6), Vector3(0.8 * sx, 2.13, 2.9), dark)
	var rig := _weapon_rig(root, Vector3(0, 2.1, 0.4), 0.8)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	# the tall slab-sided turret, hatches, smoke dischargers
	box(turret, Vector3(2.6, 1.5, 3.2), Vector3(0, 0.75, 0), olive)
	box(turret, Vector3(2.2, 0.3, 2.6), Vector3(0, 1.62, 0.1), olive)
	cyl(turret, 0.42, 0.42, 0.12, Vector3(0.6, 1.82, -0.3), dark, Vector3.ZERO, 12)
	cyl(turret, 0.42, 0.42, 0.12, Vector3(-0.6, 1.82, -0.3), dark, Vector3.ZERO, 12)
	for sx in [-1.0, 1.0]:
		for k in 4:
			cyl(turret, 0.07, 0.07, 0.4, Vector3(1.36 * sx, 1.1, 0.5 + k * 0.22), steel, Vector3(-40, 0, 0), 6)
	# the search radar turning on its arm at the back
	var spin := node(turret, Vector3(0, 2.2, 1.5))
	box(spin, Vector3(2.5, 0.75, 0.14), Vector3(0, 0.2, 0), steel)
	box(spin, Vector3(0.2, 0.5, 0.3), Vector3(0, -0.25, 0.1), dark)
	root.set_meta("spin", spin)
	cyl(turret, 0.08, 0.1, 0.7, Vector3(0, 1.9, 1.5), dark, Vector3.ZERO, 6)
	# the tracking radar on the turret front: a dish under its dome
	cyl(turret, 0.6, 0.6, 0.5, Vector3(0, 1.0, -1.8), steel, Vector3(90, 0, 0), 16)
	part(turret, Fx.sphere(0.6, 12), steel, Vector3(0, 1.0, -2.0))
	# the two 35 mm guns in their cradles on the sides of the turret
	for sx in [-1.0, 1.0]:
		box(pitch, Vector3(0.5, 0.7, 2.2), Vector3(1.55 * sx, 0, -0.2), olive)
		cyl(pitch, 0.16, 0.18, 1.2, Vector3(1.55 * sx, 0, -1.8), dark, Vector3(90, 0, 0), 10)
		cyl(pitch, 0.09, 0.1, 3.0, Vector3(1.55 * sx, 0, -3.6), dark, Vector3(90, 0, 0), 8)
		cyl(pitch, 0.13, 0.13, 0.5, Vector3(1.55 * sx, 0, -5.0), steel, Vector3(90, 0, 0), 8)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0, -5.2)))
	return root


static func iris() -> Node3D:
	var root := Node3D.new()
	var sand := Fx.paint(Color(0.38, 0.4, 0.3), 0.8, 0.15, 0.5)
	var dark := Fx.solid(Color(0.08, 0.08, 0.08), 0.6)
	var glass := Fx.solid(Color(0.05, 0.08, 0.1), 0.08, 0.3)
	# the truck: frame, cab with its windows, a generator behind it
	box(root, Vector3(2.8, 0.5, 9.5), Vector3(0, 1.25, 0), dark)
	box(root, Vector3(3.0, 1.1, 2.4), Vector3(0, 2.0, -3.6), sand)
	box(root, Vector3(3.0, 1.0, 2.2), Vector3(0, 3.0, -3.5), sand)
	box(root, Vector3(2.7, 0.8, 0.08), Vector3(0, 3.05, -4.64), glass, Vector3(-8, 0, 0))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.06, 0.7, 1.3), Vector3(1.51 * sx, 3.05, -3.7), glass)
		box(root, Vector3(0.45, 0.2, 0.1), Vector3(1.1 * sx, 1.75, -4.83), Fx.glow(Color(1.0, 0.95, 0.8), 0.6))
		box(root, Vector3(0.16, 0.3, 0.3), Vector3(1.66 * sx, 3.0, -4.5), dark)
	box(root, Vector3(3.1, 0.35, 0.3), Vector3(0, 1.35, -4.85), dark)
	box(root, Vector3(2.6, 1.2, 1.3), Vector3(0, 2.1, -1.6), sand)
	box(root, Vector3(2.9, 0.12, 5.0), Vector3(0, 1.6, 2.2), dark)
	_wheels(root, 1.5, [-3.4, 0.6, 2.8])
	var rig := _weapon_rig(root, Vector3(0, 1.9, 3.4), 0.3)
	var pitch: Node3D = rig[1]
	# the launcher: a frame of eight sealed canisters, their round caps to the front
	box(pitch, Vector3(2.7, 0.2, 5.7), Vector3(0, -0.05, -2.6), dark)
	for ix in 4:
		for iy in 2:
			var c := Vector3(-0.96 + ix * 0.64, 0.42 + iy * 0.68, -2.6)
			cyl(pitch, 0.3, 0.3, 5.4, c, sand, Vector3(90, 0, 0), 12)
			cyl(pitch, 0.31, 0.31, 0.1, c + Vector3(0, 0, -2.72), dark, Vector3(90, 0, 0), 12)
			cyl(pitch, 0.33, 0.33, 0.12, c + Vector3(0, 0, 1.2), dark, Vector3(90, 0, 0), 12)
	for sx in [-1.0, 1.0]:
		box(pitch, Vector3(0.1, 1.5, 0.12), Vector3(1.32 * sx, 0.75, -4.6), dark)
		box(pitch, Vector3(0.1, 1.5, 0.12), Vector3(1.32 * sx, 0.75, -0.6), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.8, -5.6)))
	root.set_meta("idle_pitch", 0.35)
	return root


static func patriot() -> Node3D:
	var root := Node3D.new()
	var khaki := Fx.paint(Color(0.45, 0.42, 0.32), 0.8, 0.15, 0.4)
	var dark := Fx.solid(Color(0.08, 0.08, 0.08), 0.6)
	var steel := Fx.solid(Color(0.34, 0.35, 0.33), 0.6, 0.5)
	# the M901 launching station: a semi-trailer on its outriggers, the generator at the front
	box(root, Vector3(3.0, 0.5, 9.4), Vector3(0, 1.25, 0), dark)
	box(root, Vector3(3.2, 0.3, 9.0), Vector3(0, 1.6, 0), khaki)
	box(root, Vector3(2.6, 1.3, 1.8), Vector3(0, 2.4, -3.4), khaki)
	box(root, Vector3(2.2, 0.9, 0.08), Vector3(0, 2.4, -4.32), dark)
	_wheels(root, 1.6, [2.2, 3.6], 0.8)
	cyl(root, 0.15, 0.15, 3.0, Vector3(0, 1.0, -5.5), dark, Vector3(90, 0, 0), 6)
	for sx in [-1.0, 1.0]:
		for sz in [-3.6, 0.6]:
			box(root, Vector3(1.6, 0.16, 0.2), Vector3(2.2 * sx, 1.3, sz), steel)
			cyl(root, 0.1, 0.1, 1.3, Vector3(2.9 * sx, 0.65, sz), steel, Vector3.ZERO, 8)
			cyl(root, 0.4, 0.4, 0.08, Vector3(2.9 * sx, 0.04, sz), steel, Vector3.ZERO, 10)
	var rig := _weapon_rig(root, Vector3(0, 1.6, 3.0), 0.4)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	cyl(turret, 1.3, 1.4, 0.4, Vector3(0, 0.2, 0), steel, Vector3.ZERO, 16)
	# four canisters in their frame, ribbed, with square blow-out covers
	box(pitch, Vector3(3.2, 0.2, 6.8), Vector3(0, -0.05, -3.0), dark)
	for ix in 2:
		for iy in 2:
			var c := Vector3(-0.77 + ix * 1.54, 0.65 + iy * 1.22, -3.0)
			box(pitch, Vector3(1.42, 1.1, 6.5), c, khaki)
			for k in 5:
				box(pitch, Vector3(1.5, 1.18, 0.1), c + Vector3(0, 0, -2.8 + k * 1.4), steel)
			box(pitch, Vector3(1.2, 0.9, 0.08), c + Vector3(0, 0, -3.28), dark)
	for sx in [-1.0, 1.0]:
		box(pitch, Vector3(0.12, 2.6, 0.14), Vector3(1.62 * sx, 1.25, -5.9), dark)
		box(pitch, Vector3(0.12, 2.6, 0.14), Vector3(1.62 * sx, 1.25, -0.2), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 1.2, -6.5)))
	root.set_meta("idle_pitch", 0.66)
	return root


static func weapon_model(id: String) -> Node3D:
	match id:
		"zu23":
			return zu23()
		"gepard":
			return gepard()
		"shilka":
			return shilka()
		"igla":
			return igla()
		"avenger":
			return avenger()
		"drone":
			return drone_rack()
		"osa":
			return osa()
		"iris":
			return iris()
		"nasams":
			return nasams()
		"buk":
			return buk()
		"s300":
			return s300()
		"patriot":
			return patriot()
	return pickup()


# --- Base infrastructure ------------------------------------------------------
static func base() -> Node3D:
	var root := Node3D.new()
	var bag := Fx.solid(Color(0.42, 0.38, 0.27), 0.95)
	var green := Fx.solid(Color(0.2, 0.26, 0.16), 0.8)
	var dark := Fx.solid(Color(0.1, 0.1, 0.1), 0.6)
	cyl(root, 32.0, 32.0, 0.25, Vector3(0, 0.12, 0), Fx.solid(Color(0.16, 0.15, 0.12), 1.0), Vector3.ZERO, 32)
	for i in 20:
		var a := TAU * float(i) / 20.0
		if i == 5:
			continue # entrance
		var p := Vector3(cos(a), 0, sin(a)) * 30.0
		var seg := box(root, Vector3(9.0, 1.4, 1.6), p + Vector3(0, 0.7, 0), bag)
		seg.rotation.y = -a + PI / 2.0
	box(root, Vector3(8.0, 3.0, 3.2), Vector3(-2, 1.5, 22), green)
	box(root, Vector3(2.0, 1.4, 0.1), Vector3(-2, 2.0, 20.35), Fx.glow(Color(0.2, 1.0, 0.6), 1.5))
	cyl(root, 0.1, 0.15, 14.0, Vector3(3, 7.0, 22), dark, Vector3.ZERO, 6)
	part(root, Fx.sphere(0.35, 6), Fx.glow(Color(1, 0.1, 0.1), 6.0), Vector3(3, 14.2, 22))
	# rotating search radar
	cyl(root, 0.35, 0.5, 9.0, Vector3(20, 4.5, 16), dark, Vector3.ZERO, 8)
	var spin := node(root, Vector3(20, 9.3, 16))
	box(spin, Vector3(7.0, 2.4, 0.3), Vector3(0, 0.6, 0), Fx.solid(Color(0.6, 0.62, 0.6), 0.5, 0.3), Vector3(-15, 0, 0))
	root.set_meta("spin", spin)
	# searchlights: pivot's -Z is the beam direction
	var lights: Array = []
	for sx in [-1.0, 1.0]:
		cyl(root, 0.8, 1.0, 1.6, Vector3(22 * sx, 0.8, -18), dark)
		var pivot := node(root, Vector3(22 * sx, 2.2, -18))
		var spot := SpotLight3D.new()
		spot.light_color = Color(0.85, 0.92, 1.0)
		spot.light_energy = 6.0
		spot.spot_range = 700.0
		spot.spot_angle = 5.0
		spot.spot_attenuation = 0.4
		pivot.add_child(spot)
		var beam := cyl(pivot, 0.6, 22.0, 520.0, Vector3(0, 0, -262), Fx.ghost(Color(0.5, 0.6, 0.8, 0.05), 1.0), Vector3(90, 0, 0), 12)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lights.append(pivot)
	root.set_meta("lights", lights)
	return root


static func camo_net() -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.24, 0.12, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pm := PlaneMesh.new()
	pm.size = Vector2(56, 56)
	pm.subdivide_width = 6
	pm.subdivide_depth = 6
	part(root, pm, m, Vector3(0, 6.5, 0))
	var pole := Fx.solid(Color(0.2, 0.16, 0.1))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			cyl(root, 0.15, 0.15, 6.5, Vector3(26 * sx, 3.25, 26 * sz), pole, Vector3.ZERO, 5)
	return root


# --- Threats ---------------------------------------------------------------------
static func scout() -> Node3D:
	var root := Node3D.new()
	var gray := Fx.paint(Color(0.55, 0.58, 0.56), 0.6, 0.1, 0.0)
	cyl(root, 0.35, 0.35, 3.0, Vector3.ZERO, gray, Vector3(90, 0, 0), 8)
	box(root, Vector3(8.0, 0.12, 1.1), Vector3(0, 0.15, -0.2), gray)
	cyl(root, 0.1, 0.1, 2.4, Vector3(0, 0, 2.3), gray, Vector3(90, 0, 0), 5)
	box(root, Vector3(0.1, 0.9, 0.7), Vector3(0, 0.45, 3.3), gray)
	box(root, Vector3(2.4, 0.08, 0.5), Vector3(0, 0, 3.3), gray)
	part(root, Fx.sphere(0.25, 6), Fx.glow(Color(1, 0.1, 0.1), 6.0), Vector3(-4, 0.15, -0.2))
	part(root, Fx.sphere(0.25, 6), Fx.glow(Color(0.1, 1, 0.2), 6.0), Vector3(4, 0.15, -0.2))
	var spin := node(root, Vector3(0, 0, 1.6))
	box(spin, Vector3(0.12, 1.6, 0.08), Vector3.ZERO, Fx.solid(Color(0.1, 0.1, 0.1)))
	root.set_meta("spin", spin)
	return root


static func shahed() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.paint(Color(0.24, 0.25, 0.26), 0.7, 0.1, 0.0)
	var mb := MeshBuilder.new()
	var w := Color(1, 1, 1)
	# the delta wing: thick along the body, thin at the tips; the apex at the nose and a straight
	# trailing edge
	var a_t := Vector3(0, 0.1, -2.3)
	var a_b := Vector3(0, -0.1, -2.3)
	var r_t := Vector3(0, 0.24, 2.3)
	var r_b := Vector3(0, -0.2, 2.3)
	for sx in [-1.0, 1.0]:
		var t_t := Vector3(3.1 * sx, 0.04, 2.3)
		var t_b := Vector3(3.1 * sx, -0.03, 2.3)
		var f_t := Vector3(3.1 * sx, 0.04, 1.5)
		var f_b := Vector3(3.1 * sx, -0.03, 1.5)
		mb.quad_n(a_t, f_t, t_t, r_t, Vector3(0, 1, 0), w)
		mb.quad_n(a_b, f_b, t_b, r_b, Vector3(0, -1, 0), w)
		mb.quad_n(a_t, a_b, f_b, f_t, Vector3(sx, 0, -1).normalized(), w)
		mb.quad_n(f_t, f_b, t_b, t_t, Vector3(sx, 0, 0), w)
		mb.quad_n(r_t, r_b, t_b, t_t, Vector3(0, 0, 1), w)
		# the fins on the wing tips, above and below
		mb.box(Vector3(0.07, 1.4, 1.0), Vector3(3.08 * sx, 0.0, 1.85), w)
	# the body blended into the wing, the nose with the warhead, the engine at the tail
	mb.loft([[-2.75, 0.05, 0.05, -0.05, 0.05, 0.02], [-2.2, 0.27, 0.26, -0.26, 0.27, 0.1], [-1.0, 0.4, 0.38, -0.36, 0.43, 0.14],
		[1.2, 0.4, 0.38, -0.34, 0.45, 0.14], [2.3, 0.3, 0.28, -0.24, 0.35, 0.1], [2.7, 0.22, 0.22, -0.2, 0.25, 0.08]], w)
	mb.cyl(0.25, 0.25, 0.45, Vector3(0, 0.03, 2.85), Color(0.4, 0.4, 0.4), 0.0, Vector3(90, 0, 0), 10)
	part(root, mb.commit(), mat)
	part(root, Fx.sphere(0.26, 6), Fx.glow(Color(1.0, 0.55, 0.2), 4.0), Vector3(0, 0.03, 2.75))
	# hot piston engine: dim flickering glow, visible at night as a moving spark
	var g := Fx.glare(Color(1.0, 0.5, 0.15), 1.3, 1.2, 0.0024, 0.0, 0.9)
	g.position = Vector3(0, 0, 3.0)
	root.add_child(g)
	var spin := node(root, Vector3(0, 0.03, 3.12))
	box(spin, Vector3(0.12, 1.6, 0.05), Vector3.ZERO, Fx.solid(Color(0.1, 0.1, 0.1)))
	cyl(spin, 0.1, 0.06, 0.2, Vector3(0, 0, 0.05), Fx.solid(Color(0.1, 0.1, 0.1)), Vector3(90, 0, 0), 6)
	root.set_meta("spin", spin)
	return root


static func cruise() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.paint(Color(0.68, 0.7, 0.72), 0.35, 0.5, 0.0)
	var dark := Fx.solid(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var mb := MeshBuilder.new()
	var w := Color(1, 1, 1)
	# a flattened body with an ogive nose, the wings swung out from under it, three tail
	# surfaces and the turbofan hanging under the tail
	mb.loft([[-4.6, 0.04, 0.04, -0.04, 0.04, 0.01], [-4.2, 0.22, 0.2, -0.18, 0.2, 0.08], [-3.4, 0.42, 0.36, -0.36, 0.4, 0.14],
		[-1.0, 0.5, 0.42, -0.42, 0.45, 0.16], [2.6, 0.5, 0.42, -0.42, 0.45, 0.16], [3.5, 0.36, 0.32, -0.3, 0.36, 0.12], [3.9, 0.2, 0.2, -0.16, 0.2, 0.07]], w)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(2.9, 0.07, 0.85), Vector3(1.6 * sx, -0.36, 0.25), w, 0.0, Vector3(0, -7.0 * sx, 0))
		mb.box(Vector3(1.2, 0.06, 0.6), Vector3(0.75 * sx, 0.1, 3.35), w, 0.0, Vector3(0, 0, -18.0 * sx))
	mb.box(Vector3(0.07, 1.0, 0.7), Vector3(0, 0.8, 3.3), w)
	mb.cyl(0.21, 0.24, 1.5, Vector3(0, -0.66, 2.9), w, 0.0, Vector3(90, 0, 0), 12)
	part(root, mb.commit(), mat)
	cyl(root, 0.18, 0.18, 0.06, Vector3(0, -0.66, 2.13), dark, Vector3(90, 0, 0), 12)
	part(root, Fx.sphere(0.24, 8), Fx.glow(Color(1.0, 0.6, 0.2), 6.0), Vector3(0, -0.66, 3.65))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 2.0
	l.omni_range = 25.0
	l.position = Vector3(0, -0.4, 4.5)
	root.add_child(l)
	# turbojet: yellow-white plume with a short glowing trail
	var g := Fx.glare(Color(1.0, 0.72, 0.38), 2.4, 2.2, 0.0034, 0.12, 0.3)
	g.position = Vector3(0, -0.6, 4.2)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.5, 0.15), 26, 0.3, 0.9)
	ex.position = Vector3(0, -0.6, 4.2)
	root.add_child(ex)
	return root


static func ballistic() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.paint(Color(0.45, 0.5, 0.4), 0.5, 0.2, 0.0)
	cyl(root, 0.8, 0.8, 9.0, Vector3.ZERO, mat, Vector3(90, 0, 0), 12)
	cyl(root, 0.0, 0.8, 2.6, Vector3(0, 0, -5.8), mat, Vector3(-90, 0, 0), 12)
	for i in 4:
		var a := TAU * float(i) / 4.0
		box(root, Vector3(0.08, 1.6, 1.4), Vector3(cos(a) * 1.1, sin(a) * 1.1, 3.9), mat, Vector3(0, 0, rad_to_deg(a) + 90.0))
	var flame := cyl(root, 0.15, 0.85, 8.0, Vector3(0, 0, 8.5), Fx.ghost(Color(1.0, 0.7, 0.3, 0.9), 3.0), Vector3(90, 0, 0), 10)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 5.0
	l.omni_range = 70.0
	l.position = Vector3(0, 0, 6.0)
	root.add_child(l)
	# re-entry: blinding plasma glow and a long burning streak
	var g := Fx.glare(Color(1.0, 0.86, 0.62), 4.0, 7.0, 0.009, 0.45, 0.2)
	g.position = Vector3(0, 0, 4.0)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.45, 0.1), 60, 0.9, 3.0)
	ex.position = Vector3(0, 0, 6.0)
	root.add_child(ex)
	return root


## Gerbera / Parodiya: a cheap foam copy of a Shahed — lighter, smaller, no engine glow worth the name.
static func gerbera() -> Node3D:
	var root := shahed()
	root.scale = Vector3.ONE * 0.8
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh:
			(c as MeshInstance3D).material_override = Fx.paint(Color(0.62, 0.6, 0.52), 0.8, 0.0, 0.0)
	return root


## Geran-3: the jet Shahed — a turbojet pod on the back and a long hot plume.
static func geran3() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.solid(Color(0.12, 0.12, 0.13), 0.6)
	var wing := PrismMesh.new()
	wing.size = Vector3(6.0, 5.4, 0.3)
	part(root, wing, mat, Vector3(0, 0, 0.3), Vector3(-90, 0, 0))
	cyl(root, 0.4, 0.4, 4.4, Vector3.ZERO, mat, Vector3(90, 0, 0), 8)
	cyl(root, 0.0, 0.4, 1.0, Vector3(0, 0, -2.7), mat, Vector3(-90, 0, 0), 8)
	cyl(root, 0.32, 0.32, 1.8, Vector3(0, 0.55, 1.8), Fx.solid(Color(0.3, 0.3, 0.32), 0.4, 0.6), Vector3(90, 0, 0), 8)
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.08, 1.0, 0.9), Vector3(3.0 * sx, 0.4, 2.4), mat)
	var g := Fx.glare(Color(1.0, 0.72, 0.38), 2.2, 2.0, 0.003, 0.1, 0.3)
	g.position = Vector3(0, 0.55, 2.9)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.5, 0.15), 20, 0.25, 0.7)
	ex.position = Vector3(0, 0.55, 2.9)
	root.add_child(ex)
	return root


## Molniya: a small plywood fixed-wing drone with a pusher prop.
static func molniya() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.solid(Color(0.5, 0.46, 0.36), 0.8)
	box(root, Vector3(0.4, 0.4, 2.2), Vector3.ZERO, mat)
	box(root, Vector3(3.2, 0.06, 0.6), Vector3(0, 0.2, -0.2), mat)
	box(root, Vector3(1.2, 0.06, 0.4), Vector3(0, 0.1, 1.0), mat)
	part(root, Fx.sphere(0.12, 5), Fx.glow(Color(1, 0.2, 0.1), 4.0), Vector3(0, -0.1, -1.1))
	var spin := node(root, Vector3(0, 0, 1.2))
	box(spin, Vector3(0.06, 0.9, 0.04), Vector3.ZERO, Fx.solid(Color(0.1, 0.1, 0.1)))
	root.set_meta("spin", spin)
	return root


## Kalibr: a sea-launched cruise missile, darker and a little longer than a Kh-101.
static func kalibr() -> Node3D:
	var root := cruise()
	root.scale = Vector3(0.9, 0.9, 1.15)
	return root


## Oniks: a big supersonic ramjet missile with a ring intake and a white-hot plume.
static func oniks() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.solid(Color(0.8, 0.8, 0.78), 0.35, 0.4)
	cyl(root, 0.62, 0.62, 8.4, Vector3.ZERO, mat, Vector3(90, 0, 0), 12)
	cyl(root, 0.3, 0.62, 1.2, Vector3(0, 0, -4.8), mat, Vector3(-90, 0, 0), 12)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		box(root, Vector3(0.08, 1.4, 1.6), Vector3(cos(a) * 0.9, sin(a) * 0.9, 3.4), mat, Vector3(0, 0, rad_to_deg(a) + 90.0))
	var g := Fx.glare(Color(1.0, 0.9, 0.75), 3.4, 4.0, 0.006, 0.3, 0.15)
	g.position = Vector3(0, 0, 4.6)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.7, 0.4), 50, 0.5, 1.8)
	ex.position = Vector3(0, 0, 4.6)
	root.add_child(ex)
	return root


## Kh-31P: an anti-radiation missile — slim, cruciform wings, ramjet glow.
static func kh31p() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.solid(Color(0.7, 0.72, 0.66), 0.4, 0.4)
	cyl(root, 0.3, 0.3, 5.2, Vector3.ZERO, mat, Vector3(90, 0, 0), 8)
	cyl(root, 0.0, 0.3, 0.9, Vector3(0, 0, -3.05), mat, Vector3(-90, 0, 0), 8)
	for i in 4:
		var a := TAU * float(i) / 4.0
		box(root, Vector3(0.06, 1.0, 1.2), Vector3(cos(a) * 0.55, sin(a) * 0.55, 0.4), mat, Vector3(0, 0, rad_to_deg(a) + 90.0))
	var g := Fx.glare(Color(1.0, 0.8, 0.6), 2.6, 2.4, 0.004, 0.2, 0.2)
	g.position = Vector3(0, 0, 2.8)
	root.add_child(g)
	return root


## KAB with the UMPK kit: a fat FAB-500 body, folding glide wings, a tail cone — no engine.
static func kab() -> Node3D:
	var root := Node3D.new()
	var body := Fx.solid(Color(0.3, 0.34, 0.28), 0.7)
	var kit := Fx.solid(Color(0.5, 0.52, 0.5), 0.5, 0.3)
	cyl(root, 0.6, 0.6, 3.2, Vector3.ZERO, body, Vector3(90, 0, 0), 12)
	part(root, Fx.sphere(0.6, 10), body, Vector3(0, 0, -1.6))
	cyl(root, 0.6, 0.25, 1.4, Vector3(0, 0, 2.3), body, Vector3(90, 0, 0), 12)
	box(root, Vector3(4.6, 0.08, 0.5), Vector3(0, 0.7, -0.2), kit)
	box(root, Vector3(0.12, 0.7, 0.2), Vector3(0, 0.35, -0.2), kit)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		box(root, Vector3(0.06, 0.9, 0.8), Vector3(cos(a) * 0.55, sin(a) * 0.55, 2.8), kit, Vector3(0, 0, rad_to_deg(a) + 90.0))
	# no engine: only a dim satellite-navigation light, the bomb is almost invisible at night
	part(root, Fx.sphere(0.12, 5), Fx.glow(Color(1.0, 0.3, 0.2), 2.0), Vector3(0, 0.3, 2.9))
	return root


## Kinzhal: a sleek dark aeroballistic missile wrapped in a violet plasma glow.
static func kinzhal() -> Node3D:
	var root := Node3D.new()
	var mat := Fx.solid(Color(0.2, 0.22, 0.24), 0.4, 0.5)
	cyl(root, 0.55, 0.55, 7.0, Vector3.ZERO, mat, Vector3(90, 0, 0), 12)
	cyl(root, 0.0, 0.55, 2.4, Vector3(0, 0, -4.7), mat, Vector3(-90, 0, 0), 12)
	for i in 4:
		var a := TAU * float(i) / 4.0
		box(root, Vector3(0.06, 1.1, 1.0), Vector3(cos(a) * 0.7, sin(a) * 0.7, 3.2), mat, Vector3(0, 0, rad_to_deg(a) + 90.0))
	var g := Fx.glare(Color(0.9, 0.6, 1.0), 4.4, 7.0, 0.009, 0.5, 0.25)
	g.position = Vector3(0, 0, -3.0)
	root.add_child(g)
	var ex := Fx.exhaust(Color(0.85, 0.5, 1.0), 60, 0.8, 2.6)
	ex.position = Vector3(0, 0, 3.8)
	root.add_child(ex)
	return root


## S-300 fired at the ground: a long white SAM with its booster flame.
static func s300_missile() -> Node3D:
	var root := ballistic()
	root.scale = Vector3(0.7, 0.7, 0.85)
	return root


## Kh-22: a huge anti-ship missile diving from the stratosphere.
static func kh22() -> Node3D:
	var root := ballistic()
	root.scale = Vector3(1.1, 1.1, 1.3)
	return root


## Oreshnik: an incandescent re-entry body — no missile to see, only a falling star.
static func oreshnik() -> Node3D:
	var root := Node3D.new()
	cyl(root, 0.0, 1.1, 3.2, Vector3.ZERO, Fx.glow(Color(1.0, 0.85, 0.55), 6.0), Vector3(-90, 0, 0), 10)
	var g := Fx.glare(Color(1.0, 0.92, 0.7), 6.0, 12.0, 0.012, 0.8, 0.1)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.6, 0.25), 80, 1.4, 4.0)
	ex.position = Vector3(0, 0, 2.0)
	root.add_child(ex)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.light_energy = 8.0
	l.omni_range = 160.0
	root.add_child(l)
	return root


static func enemy_model(type: String) -> Node3D:
	match type:
		"scout":
			return scout()
		"cruise":
			return cruise()
		"ballistic":
			return ballistic()
		"gerbera":
			return gerbera()
		"geran3":
			return geran3()
		"molniya":
			return molniya()
		"kalibr":
			return kalibr()
		"oniks":
			return oniks()
		"kh31p":
			return kh31p()
		"kab":
			return kab()
		"kinzhal":
			return kinzhal()
		"s300":
			return s300_missile()
		"kh22":
			return kh22()
		"oreshnik":
			return oreshnik()
	return shahed()


# --- Interceptor ---------------------------------------------------------------------
static func interceptor(big: bool) -> Node3D:
	var root := Node3D.new()
	var r := 0.35 if big else 0.25
	var length := 5.0 if big else 3.6
	var mat := Fx.solid(Color(0.92, 0.92, 0.9), 0.4)
	cyl(root, r, r, length, Vector3.ZERO, mat, Vector3(90, 0, 0), 8)
	cyl(root, 0.0, r, 0.9, Vector3(0, 0, -length / 2.0 - 0.45), mat, Vector3(-90, 0, 0), 8)
	var flame := cyl(root, 0.1, r * 1.6, 3.0, Vector3(0, 0, length / 2.0 + 1.5), Fx.ghost(Color(1.0, 0.85, 0.5, 1.0), 4.0), Vector3(90, 0, 0), 8)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# solid-rocket motor: the brightest thing in the night sky
	var g := Fx.glare(Color(1.0, 0.9, 0.72), 4.5 if big else 3.5, 2.8, 0.0065 if big else 0.0055, 0.35, 0.25)
	g.position = Vector3(0, 0, length / 2.0 + 0.8)
	root.add_child(g)
	var ex := Fx.exhaust(Color(1.0, 0.55, 0.15), 40, 0.45, 1.3 if big else 1.0)
	ex.position = Vector3(0, 0, length / 2.0 + 0.8)
	root.add_child(ex)
	return root


## FPV interceptor drone: an X-frame quadcopter with a shaped charge in the nose.
## Meta "rotors" holds the four spinning discs; "cam" is the FPV camera mount point.
static func fpv_drone() -> Node3D:
	var root := Node3D.new()
	var frame := Fx.solid(Color(0.09, 0.1, 0.12), 0.5)
	var carbon := Fx.solid(Color(0.05, 0.05, 0.06), 0.35)
	var warhead := Fx.solid(Color(0.35, 0.3, 0.12), 0.6)
	box(root, Vector3(0.62, 0.3, 1.05), Vector3.ZERO, frame)
	box(root, Vector3(0.5, 0.42, 0.34), Vector3(0, 0.12, -0.45), frame)
	cyl(root, 0.0, 0.26, 0.5, Vector3(0, 0.02, -0.95), warhead, Vector3(-90, 0, 0), 10)
	var rotors: Array[Node3D] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var arm_at := Vector3(0.36 * sx, 0.04, 0.5 * sz)
			box(root, Vector3(0.12, 0.08, 0.95), arm_at * 0.55, carbon, Vector3(0, rad_to_deg(atan2(arm_at.x, arm_at.z)), 0))
			cyl(root, 0.12, 0.12, 0.16, arm_at + Vector3(0, 0.08, 0), frame, Vector3.ZERO, 8)
			var rot := node(root, arm_at + Vector3(0, 0.2, 0))
			var blade := Fx.ghost(Color(0.55, 0.7, 0.8, 0.5), 0.6)
			for a in [0.0, 90.0]:
				box(rot, Vector3(0.9, 0.02, 0.09), Vector3.ZERO, blade, Vector3(0, a, 0))
			rotors.append(rot)
	# navigation lights: a green nose and red tail, visible across the night sky
	var nose := Fx.glare(Color(0.4, 1.0, 0.5), 1.1, 2.2, 0.0022, 0.5, 0.3)
	nose.position = Vector3(0, 0.05, -0.8)
	root.add_child(nose)
	var tail := Fx.glare(Color(1.0, 0.3, 0.25), 1.0, 2.0, 0.002, 0.5, 0.3)
	tail.position = Vector3(0, 0.12, 0.6)
	root.add_child(tail)
	root.set_meta("rotors", rotors)
	root.set_meta("cam", node(root, Vector3(0, 0.22, -0.62)))
	return root


## Launch rack for the interceptor drones: a light truck with a rail of drones and an antenna.
static func drone_rack() -> Node3D:
	var root := Node3D.new()
	var paint := Fx.solid(Color(0.22, 0.3, 0.24), 0.7)
	var dark := Fx.solid(Color(0.1, 0.11, 0.12), 0.5)
	var glass := Fx.solid(Color(0.1, 0.18, 0.22), 0.1, 0.4)
	box(root, Vector3(3.0, 0.8, 6.6), Vector3(0, 1.25, 0), paint)
	box(root, Vector3(2.9, 1.5, 2.6), Vector3(0, 2.4, -1.9), paint)
	box(root, Vector3(2.7, 0.85, 0.1), Vector3(0, 2.55, -3.18), glass, Vector3(-16, 0, 0))
	# operator's station: screens on the tailgate
	box(root, Vector3(1.9, 1.1, 0.14), Vector3(0, 2.3, 3.3), Fx.glow(Color(0.35, 0.9, 1.0), 1.4))
	_wheels(root, 1.5, [-2.1, 2.1])
	var rig := _weapon_rig(root, Vector3(0, 1.65, 1.2), 0.55)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	cyl(turret, 0.16, 0.16, 2.6, Vector3(1.25, 1.5, 1.4), dark, Vector3.ZERO, 6)
	cyl(turret, 0.5, 0.5, 0.12, Vector3(1.25, 2.85, 1.4), dark, Vector3(0, 0, 0), 12)
	box(pitch, Vector3(2.4, 0.16, 2.4), Vector3(0, -0.15, -0.6), dark)
	# three drones sitting on the rail, ready to go
	for i in 3:
		var d := fpv_drone()
		d.scale = Vector3.ONE * 1.35
		d.position = Vector3(-0.85 + i * 0.85, 0.12, -0.6)
		pitch.add_child(d)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.3, -1.9)))
	root.set_meta("idle_pitch", 0.3)
	return root


## Towed twin 23 mm on a firing position: two barrels on a small carriage, ammo crates.
static func zu23() -> Node3D:
	var root := Node3D.new()
	var olive := Fx.paint(Color(0.28, 0.32, 0.2), 0.85, 0.15, 0.5)
	var dark := Fx.solid(Color(0.12, 0.12, 0.12), 0.6)
	var sand := Fx.solid(Color(0.45, 0.42, 0.3), 0.95)
	# sandbag ring around the emplacement
	for i in 14:
		var a := TAU * i / 14.0
		box(root, Vector3(1.5, 0.55, 0.9), Vector3(cos(a) * 3.6, 0.28, sin(a) * 3.6), sand, Vector3(0, rad_to_deg(-a), 0))
	box(root, Vector3(2.6, 0.3, 3.0), Vector3(0, 0.55, 0), olive)
	_wheels(root, 1.35, [0.9], 0.45)
	for sz in [-1.0, 1.0]:
		box(root, Vector3(0.25, 0.25, 2.2), Vector3(1.1 * sz, 0.45, -1.8), olive, Vector3(0, 12.0 * sz, 0))
	var rig := _weapon_rig(root, Vector3(0, 0.75, 0), 0.75)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	cyl(turret, 0.45, 0.55, 0.6, Vector3(0, 0.1, 0), olive, Vector3.ZERO, 10)
	box(turret, Vector3(1.9, 0.5, 0.12), Vector3(0, 0.6, 0.8), olive)
	box(turret, Vector3(0.5, 0.7, 0.5), Vector3(0.95, 0.75, 0.5), olive)
	box(pitch, Vector3(1.0, 0.4, 0.8), Vector3.ZERO, dark)
	for sx in [-0.42, 0.42]:
		cyl(pitch, 0.1, 0.12, 2.4, Vector3(sx, 0.05, -1.3), dark, Vector3(90, 0, 0), 8)
		box(pitch, Vector3(0.34, 0.34, 0.5), Vector3(sx, 0.05, 0.45), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.05, -2.6)))
	root.set_meta("idle_pitch", 0.25)
	return root


## ZSU-23-4 Shilka: tracked hull, four barrels and the dish of the gun radar.
static func shilka() -> Node3D:
	var root := Node3D.new()
	var olive := Fx.paint(Color(0.24, 0.28, 0.18), 0.85, 0.15, 0.7)
	var dark := Fx.solid(Color(0.1, 0.1, 0.11), 0.6)
	var steel := Fx.solid(Color(0.5, 0.52, 0.55), 0.45, 0.6)
	_tracks(root, 3.4, 7.2)
	box(root, Vector3(3.5, 1.0, 6.8), Vector3(0, 1.5, 0), olive)
	box(root, Vector3(3.2, 0.5, 2.0), Vector3(0, 2.15, -2.4), olive, Vector3(-14, 0, 0))
	var rig := _weapon_rig(root, Vector3(0, 2.0, 0.4), 0.9)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	box(turret, Vector3(3.2, 1.5, 3.4), Vector3(0, 0.55, 0), olive)
	box(turret, Vector3(2.6, 0.4, 2.6), Vector3(0, 1.4, 0), olive)
	# search radar drum on its mast
	var mast := node(turret, Vector3(0, 1.6, 1.3))
	cyl(mast, 0.16, 0.16, 1.1, Vector3(0, 0.55, 0), steel, Vector3.ZERO, 8)
	var dish := node(mast, Vector3(0, 1.25, 0))
	cyl(dish, 0.95, 0.95, 0.25, Vector3.ZERO, steel, Vector3(0, 0, 0), 14)
	box(dish, Vector3(1.9, 0.5, 0.12), Vector3(0, 0.3, 0), steel)
	root.set_meta("spin", dish)
	box(pitch, Vector3(1.5, 0.6, 1.2), Vector3.ZERO, dark)
	for sx in [-0.5, 0.5]:
		for sy in [-0.22, 0.22]:
			cyl(pitch, 0.09, 0.11, 3.2, Vector3(sx, sy, -1.9), dark, Vector3(90, 0, 0), 8)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0, -3.5)))
	root.set_meta("idle_pitch", 0.22)
	return root


## MANPADS post: a dug-in team with a launch tube on a swivel and ready rounds.
static func igla() -> Node3D:
	var root := Node3D.new()
	var sand := Fx.solid(Color(0.46, 0.43, 0.31), 0.95)
	var olive := Fx.paint(Color(0.26, 0.3, 0.19), 0.85, 0.1, 0.4)
	var tube := Fx.solid(Color(0.32, 0.34, 0.26), 0.7)
	var dark := Fx.solid(Color(0.13, 0.13, 0.13), 0.6)
	for i in 12:
		var a := TAU * i / 12.0
		box(root, Vector3(1.4, 0.5, 0.8), Vector3(cos(a) * 3.0, 0.25, sin(a) * 3.0), sand, Vector3(0, rad_to_deg(-a), 0))
	box(root, Vector3(1.6, 0.5, 1.0), Vector3(1.9, 0.25, 1.6), olive)
	for i in 3:
		cyl(root, 0.16, 0.16, 1.7, Vector3(1.6 + i * 0.26, 0.78, 1.6), tube, Vector3(78, 0, 0), 8)
	var rig := _weapon_rig(root, Vector3(0, 0.6, 0), 1.0)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	cyl(turret, 0.28, 0.34, 1.1, Vector3(0, -0.1, 0), dark, Vector3.ZERO, 8)
	# gunner: a stubby figure shouldering the tube
	box(turret, Vector3(0.5, 0.9, 0.35), Vector3(-0.45, 0.45, 0.25), olive)
	cyl(turret, 0.2, 0.2, 0.3, Vector3(-0.45, 1.0, 0.25), Fx.solid(Color(0.55, 0.42, 0.32), 0.9), Vector3.ZERO, 8)
	cyl(pitch, 0.17, 0.17, 2.0, Vector3(0, 0.35, -0.6), tube, Vector3(90, 0, 0), 10)
	box(pitch, Vector3(0.3, 0.3, 0.4), Vector3(0, 0.15, 0.35), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.35, -1.7)))
	root.set_meta("idle_pitch", 0.5)
	return root


## Avenger: light 4x4 with two four-round Stinger pods on a powered turret.
static func avenger() -> Node3D:
	var root := Node3D.new()
	var sand := Fx.paint(Color(0.42, 0.4, 0.31), 0.8, 0.15, 0.4)
	var dark := Fx.solid(Color(0.12, 0.12, 0.13), 0.6)
	var glass := Fx.solid(Color(0.1, 0.18, 0.22), 0.15, 0.4)
	box(root, Vector3(3.0, 1.0, 5.4), Vector3(0, 1.1, 0), sand)
	box(root, Vector3(2.8, 1.1, 2.0), Vector3(0, 2.0, -1.5), sand)
	box(root, Vector3(2.6, 0.7, 0.12), Vector3(0, 2.2, -2.5), glass, Vector3(-14, 0, 0))
	_wheels(root, 1.45, [-1.7, 1.7], 0.7)
	var rig := _weapon_rig(root, Vector3(0, 1.6, 1.1), 0.9)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	cyl(turret, 0.7, 0.8, 0.9, Vector3(0, -0.15, 0), sand, Vector3.ZERO, 10)
	box(turret, Vector3(0.9, 0.7, 0.9), Vector3(0, 0.45, 0), dark)
	for sx in [-1.05, 1.05]:
		var pod := node(pitch, Vector3(sx, 0.15, 0))
		box(pod, Vector3(0.8, 0.9, 2.1), Vector3.ZERO, sand)
		for i in 2:
			for j in 2:
				cyl(pod, 0.16, 0.16, 2.0, Vector3(-0.2 + i * 0.4, -0.2 + j * 0.4, 0), dark, Vector3(90, 0, 0), 8)
	# sight ball between the pods
	part(pitch, Fx.sphere(0.32, 10), Fx.solid(Color(0.08, 0.1, 0.12), 0.2, 0.5), Vector3(0, 0.15, -0.9))
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.15, -1.4)))
	root.set_meta("idle_pitch", 0.35)
	return root


## Osa-AKM: amphibious 6x6 with four tubes and the tracking dish between them.
static func osa() -> Node3D:
	var root := Node3D.new()
	var olive := Fx.paint(Color(0.27, 0.31, 0.21), 0.85, 0.15, 0.7)
	var dark := Fx.solid(Color(0.11, 0.11, 0.12), 0.6)
	var steel := Fx.solid(Color(0.52, 0.54, 0.56), 0.4, 0.6)
	box(root, Vector3(3.4, 1.3, 8.0), Vector3(0, 1.3, 0), olive)
	box(root, Vector3(3.0, 0.8, 2.6), Vector3(0, 2.3, -2.6), olive, Vector3(-10, 0, 0))
	_wheels(root, 1.6, [-2.6, 0.0, 2.6], 0.75)
	var rig := _weapon_rig(root, Vector3(0, 2.0, 0.8), 1.0)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	box(turret, Vector3(2.6, 1.2, 2.8), Vector3(0, 0.1, 0), olive)
	var dish := node(turret, Vector3(0, 1.0, 0.2))
	cyl(dish, 1.2, 1.2, 0.2, Vector3.ZERO, steel, Vector3(70, 0, 0), 16)
	root.set_meta("spin", dish)
	for sx in [-1.0, -0.35, 0.35, 1.0]:
		cyl(pitch, 0.22, 0.24, 3.2, Vector3(sx, 0.2, -0.9), dark, Vector3(90, 0, 0), 8)
		cyl(pitch, 0.1, 0.1, 0.5, Vector3(sx, 0.2, -2.6), Fx.solid(Color(0.75, 0.75, 0.7), 0.6), Vector3(90, 0, 0), 8)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.2, -2.7)))
	root.set_meta("idle_pitch", 0.45)
	return root


## NASAMS: a truck carrying a frame of six launch canisters that tilts up to fire.
static func nasams() -> Node3D:
	var root := Node3D.new()
	var green := Fx.paint(Color(0.22, 0.29, 0.22), 0.8, 0.15, 0.5)
	var canister := Fx.paint(Color(0.36, 0.38, 0.34), 0.7, 0.2, 0.0)
	var dark := Fx.solid(Color(0.12, 0.12, 0.13), 0.6)
	var glass := Fx.solid(Color(0.1, 0.18, 0.22), 0.15, 0.4)
	box(root, Vector3(3.0, 0.7, 7.4), Vector3(0, 1.2, 0.4), green)
	box(root, Vector3(2.9, 1.6, 2.4), Vector3(0, 2.3, -2.6), green)
	box(root, Vector3(2.7, 0.8, 0.12), Vector3(0, 2.6, -3.78), glass, Vector3(-14, 0, 0))
	_wheels(root, 1.5, [-2.5, 1.6, 2.9], 0.72)
	var rig := _weapon_rig(root, Vector3(0, 1.6, 1.9), 0.5)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	box(turret, Vector3(2.6, 0.4, 3.2), Vector3(0, -0.2, 0), dark)
	for i in 3:
		for j in 2:
			box(pitch, Vector3(0.78, 0.78, 3.2), Vector3(-0.85 + i * 0.85, 0.1 + j * 0.82, 0), canister)
	box(pitch, Vector3(2.7, 0.2, 0.5), Vector3(0, 0.5, 1.7), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.5, -1.8)))
	root.set_meta("idle_pitch", 0.55)
	return root


## Buk-M1 TELAR: tracked chassis, radar dome and four heavy missiles on the rail.
static func buk() -> Node3D:
	var root := Node3D.new()
	var olive := Fx.paint(Color(0.25, 0.29, 0.19), 0.85, 0.15, 0.7)
	var dark := Fx.solid(Color(0.11, 0.11, 0.12), 0.6)
	var white := Fx.solid(Color(0.78, 0.78, 0.74), 0.6)
	_tracks(root, 3.6, 8.4)
	box(root, Vector3(3.7, 1.2, 8.0), Vector3(0, 1.6, 0), olive)
	box(root, Vector3(3.3, 0.6, 2.2), Vector3(0, 2.4, -2.9), olive, Vector3(-12, 0, 0))
	var rig := _weapon_rig(root, Vector3(0, 2.2, 0.2), 0.8)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	box(turret, Vector3(3.0, 1.0, 3.6), Vector3(0, 0.0, 0), olive)
	# tracking radar dome at the front of the rail
	part(turret, Fx.sphere(0.95, 12), Fx.solid(Color(0.8, 0.8, 0.78), 0.4), Vector3(0, 1.1, -1.5))
	box(pitch, Vector3(2.6, 0.35, 5.4), Vector3(0, -0.1, 0), dark)
	for i in 4:
		var x := -1.05 + i * 0.7
		cyl(pitch, 0.24, 0.3, 5.2, Vector3(x, 0.45, 0), white, Vector3(90, 0, 0), 10)
		cyl(pitch, 0.0, 0.26, 0.9, Vector3(x, 0.45, -2.9), white, Vector3(-90, 0, 0), 10)
		for a in [0.0, 90.0]:
			box(pitch, Vector3(0.9, 0.06, 0.8), Vector3(x, 0.45, 2.2), white, Vector3(0, 0, a))
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.45, -3.2)))
	root.set_meta("idle_pitch", 0.5)
	return root


## S-300PS TEL: 8x8 tractor with four vertical launch tubes raised over the tail.
static func s300() -> Node3D:
	var root := Node3D.new()
	var green := Fx.paint(Color(0.2, 0.26, 0.2), 0.85, 0.15, 0.6)
	var tube := Fx.paint(Color(0.42, 0.44, 0.4), 0.7, 0.2, 0.0)
	var dark := Fx.solid(Color(0.11, 0.11, 0.12), 0.6)
	var glass := Fx.solid(Color(0.1, 0.18, 0.22), 0.15, 0.4)
	box(root, Vector3(3.6, 1.0, 11.0), Vector3(0, 1.45, 0), green)
	box(root, Vector3(3.4, 1.8, 2.8), Vector3(0, 2.8, -4.2), green)
	box(root, Vector3(3.2, 0.9, 0.12), Vector3(0, 3.1, -5.58), glass, Vector3(-14, 0, 0))
	_wheels(root, 1.8, [-3.6, -2.2, 3.0, 4.4], 0.85)
	box(root, Vector3(3.2, 0.5, 4.4), Vector3(0, 2.0, 2.6), dark)
	var rig := _weapon_rig(root, Vector3(0, 2.2, 4.3), 0.3)
	var turret: Node3D = rig[0]
	var pitch: Node3D = rig[1]
	box(turret, Vector3(3.2, 0.6, 1.2), Vector3(0, -0.2, 0), dark)
	for sx in [-0.95, 0.95]:
		for sz in [-0.95, 0.95]:
			cyl(pitch, 0.42, 0.42, 7.4, Vector3(sx, 0.2, sz - 3.2), tube, Vector3(90, 0, 0), 12)
			cyl(pitch, 0.44, 0.3, 0.5, Vector3(sx, 0.2, sz - 6.9), Fx.solid(Color(0.6, 0.25, 0.15), 0.8), Vector3(90, 0, 0), 12)
	box(pitch, Vector3(2.6, 0.3, 1.0), Vector3(0, 0.2, 0.6), dark)
	root.set_meta("muzzle", node(pitch, Vector3(0, 0.2, -7.2)))
	root.set_meta("idle_pitch", 1.2)
	return root


## Track units for the armoured chassis (Gepard, Shilka, Buk): the run on the ground and the
## return run, the slopes up to the sprocket and the idler, six road wheels, a side skirt.
static func _tracks(root: Node3D, width: float, length: float) -> void:
	var rubber := Fx.solid(Color(0.07, 0.07, 0.08), 0.95)
	var steel := Fx.solid(Color(0.26, 0.27, 0.25), 0.7, 0.4)
	var skirt := Fx.paint(Color(0.25, 0.29, 0.19), 0.85, 0.15, 0.7)
	for sx in [-1.0, 1.0]:
		var x: float = width * 0.5 * sx
		box(root, Vector3(0.8, 0.22, length * 0.8), Vector3(x, 0.11, 0), rubber)
		box(root, Vector3(0.8, 0.2, length * 0.92), Vector3(x, 1.12, 0), rubber)
		for e in [-1.0, 1.0]:
			box(root, Vector3(0.8, 0.2, length * 0.17), Vector3(x, 0.56, e * length * 0.455), rubber, Vector3(-e * 52.0, 0, 0))
			cyl(root, 0.4, 0.4, 0.7, Vector3(x, 0.78, e * length * 0.455), steel, Vector3(0, 0, 90), 12)
		for i in 6:
			var z := -length * 0.36 + i * length * 0.144
			cyl(root, 0.4, 0.4, 0.62, Vector3(x, 0.5, z), steel, Vector3(0, 0, 90), 12)
			cyl(root, 0.14, 0.14, 0.68, Vector3(x, 0.5, z), rubber, Vector3(0, 0, 90), 6)
		box(root, Vector3(0.08, 0.5, length * 0.9), Vector3(x + sx * 0.42, 1.0, 0), skirt)


# --- Fire and rescue service ---------------------------------------------------------
## Fire engine of the city service: red body, ladder on the roof, blue beacons.
## Meta "beacons" holds the flashing lights, "nozzle" the water monitor mount.
static func fire_truck() -> Node3D:
	var root := Node3D.new()
	var red := Fx.solid(Color(0.62, 0.08, 0.07), 0.6)
	var white := Fx.solid(Color(0.85, 0.87, 0.88), 0.6)
	var dark := Fx.solid(Color(0.1, 0.1, 0.11), 0.5)
	var glass := Fx.solid(Color(0.12, 0.2, 0.26), 0.15, 0.4)
	var steel := Fx.solid(Color(0.55, 0.57, 0.6), 0.4, 0.7)
	box(root, Vector3(2.6, 1.5, 4.6), Vector3(0, 1.85, 0.9), red)
	box(root, Vector3(2.5, 0.35, 4.2), Vector3(0, 2.75, 0.9), white)
	box(root, Vector3(2.5, 1.7, 2.4), Vector3(0, 2.0, -2.2), red)
	box(root, Vector3(2.35, 0.75, 0.12), Vector3(0, 2.4, -3.42), glass, Vector3(-12, 0, 0))
	box(root, Vector3(2.4, 0.5, 0.4), Vector3(0, 1.2, -3.3), white)
	# ladder along the roof
	for sx in [-0.55, 0.55]:
		box(root, Vector3(0.12, 0.12, 5.2), Vector3(sx, 3.05, 0.6), steel)
	for i in 9:
		box(root, Vector3(1.2, 0.07, 0.1), Vector3(0, 3.05, -1.9 + i * 0.6), steel)
	_wheels(root, 1.25, [-2.1, 1.6], 0.6)
	var beacons: Array[Node3D] = []
	for sx in [-0.8, 0.8]:
		var b := Fx.glare(Color(0.3, 0.55, 1.0), 2.4, 1.6, 0.004, 0.6, 0.0)
		b.position = Vector3(sx, 3.15, -2.2)
		root.add_child(b)
		beacons.append(b)
	root.set_meta("beacons", beacons)
	root.set_meta("nozzle", node(root, Vector3(0, 3.2, 0.6)))
	return root


## Fire station beside the base: a two-gate garage the crews roll out of.
static func fire_depot() -> Node3D:
	var root := Node3D.new()
	var wall := Fx.solid(Color(0.68, 0.24, 0.18), 0.8)
	var trim := Fx.solid(Color(0.85, 0.86, 0.88), 0.7)
	var gate := Fx.solid(Color(0.2, 0.22, 0.25), 0.5)
	box(root, Vector3(11.0, 4.6, 7.0), Vector3(0, 2.3, 0), wall)
	box(root, Vector3(11.4, 0.4, 7.4), Vector3(0, 4.7, 0), trim)
	for sx in [-2.6, 2.6]:
		box(root, Vector3(3.6, 3.4, 0.2), Vector3(sx, 1.7, -3.55), gate)
	box(root, Vector3(4.0, 0.6, 0.15), Vector3(0, 4.0, -3.6), trim)
	var sign := Fx.glare(Color(1.0, 0.45, 0.2), 1.6, 2.2, 0.0035, 0.5, 0.0)
	sign.position = Vector3(0, 4.0, -3.7)
	root.add_child(sign)
	# apron the trucks park on
	box(root, Vector3(13.0, 0.12, 6.0), Vector3(0, 0.06, -6.6), Fx.solid(Color(0.22, 0.22, 0.24), 0.95))
	return root


# --- Composite meshes ---------------------------------------------------------------
## Merges primitive meshes into one ArrayMesh with per-part vertex colours, so a whole
## prop (e.g. a tree) is a single MultiMesh instance. parts: [[Mesh, Transform3D, Color], ...]
static func combine(parts: Array) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for p in parts:
		mb.add_mesh(p[0], p[1], p[2], Vector2.ZERO)
	return mb.commit()


## Collects geometry into one surface: vertex colours tint the parts, UV.x tells the shader which
## material a part is (0 = paint / leaves / clothes, taking the instance colour), UV.y carries a
## per-vertex value (height in a crown, for the shading and the sway).
class MeshBuilder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	## Second UV set, only for the leaf cards (where on the card a pixel is); filled up with zeros
	## for everything else when the mesh is committed.
	var uv2s := PackedVector2Array()

	## A leaf card: a square of side s around p in the plane (t1, t2), shaded with the normal n of
	## the crown it belongs to. UV.y = v (height in the crown), UV2 = the corner of the card.
	func card(p: Vector3, t1: Vector3, t2: Vector3, s: float, n: Vector3, c: Color, v: float, part := 4.0) -> void:
		while uv2s.size() < verts.size():
			uv2s.append(Vector2.ZERO)
		var base := verts.size()
		var h := s * 0.5
		var corners := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
		for k in corners:
			verts.append(p + t1 * (float(k[0]) * h) + t2 * (float(k[1]) * h))
			norms.append(n)
			cols.append(c)
			uvs.append(Vector2(part, v))
			uv2s.append(Vector2(float(k[0]) * 0.5 + 0.5, float(k[1]) * 0.5 + 0.5))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## A quad with a given outward normal (the winding is put right by itself).
	func quad_n(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, part := 0.0) -> void:
		if (p2 - p0).cross(p1 - p0).dot(n) < 0.0:
			quad(p0, p3, p2, p1, c, part)
		else:
			quad(p0, p1, p2, p3, c, part)

	## A smooth skin through cross-sections [z, half width at the bottom, half width at the top,
	## y bottom, y top, corner radius] (a car body): every section is a ring of eight points with
	## chamfered corners, the normals are shared between the faces so the surface shades as one
	## curved panel. Both ends are closed.
	func loft(sections: Array, c: Color, part := 0.0) -> void:
		var rings: Array = []
		for s in sections:
			var z := float(s[0])
			var wb := float(s[1])
			var wt := float(s[2])
			var y0 := float(s[3])
			var y1 := float(s[4])
			var r := minf(float(s[5]), (y1 - y0) * 0.45)
			var rt := minf(r * 1.4, (y1 - y0) * 0.45)
			var ws := wt + (wb - wt) * rt / maxf(y1 - y0, 0.001)
			rings.append(PackedVector3Array([Vector3(wb - r, y0, z), Vector3(wb, y0 + r, z), Vector3(ws, y1 - rt, z), Vector3(wt - rt, y1, z),
				Vector3(-(wt - rt), y1, z), Vector3(-ws, y1 - rt, z), Vector3(-wb, y0 + r, z), Vector3(-(wb - r), y0, z)]))
		var n := rings.size()
		var base := verts.size()
		for k in n:
			var ring: PackedVector3Array = rings[k]
			var prev: PackedVector3Array = rings[maxi(k - 1, 0)]
			var next: PackedVector3Array = rings[mini(k + 1, n - 1)]
			var mid := (ring[1] + ring[5]) * 0.5
			for i in 8:
				var along := next[i] - prev[i]
				var around := ring[(i + 1) % 8] - ring[(i + 7) % 8]
				var nn := around.cross(along).normalized()
				if nn.dot(ring[i] - mid) < 0.0:
					nn = -nn
				verts.append(ring[i])
				norms.append(nn)
				cols.append(c)
				uvs.append(Vector2(part, 0.0))
		for k in n - 1:
			for i in 8:
				var a := base + k * 8 + i
				var b := base + k * 8 + (i + 1) % 8
				var c2 := base + (k + 1) * 8 + (i + 1) % 8
				var d := base + (k + 1) * 8 + i
				var out := verts[a] - Vector3(0, (verts[base + k * 8 + 1].y + verts[base + k * 8 + 5].y) * 0.5, verts[a].z)
				if (verts[c2] - verts[a]).cross(verts[b] - verts[a]).dot(out) < 0.0:
					idx.append_array(PackedInt32Array([a, d, c2, a, c2, b]))
				else:
					idx.append_array(PackedInt32Array([a, b, c2, a, c2, d]))
		for e in 2:
			var ring: PackedVector3Array = rings[0 if e == 0 else n - 1]
			var nz := Vector3(0, 0, -1.0 if e == 0 else 1.0)
			var cb := verts.size()
			for i in 8:
				verts.append(ring[i])
				norms.append(nz)
				cols.append(c)
				uvs.append(Vector2(part, 0.0))
			for i in range(1, 7):
				if (ring[i + 1] - ring[0]).cross(ring[i] - ring[0]).dot(nz) < 0.0:
					idx.append_array(PackedInt32Array([cb, cb + i + 1, cb + i]))
				else:
					idx.append_array(PackedInt32Array([cb, cb + i, cb + i + 1]))

	func add_mesh(m: Mesh, xf: Transform3D, c: Color, uv: Vector2) -> void:
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(c)
			uvs.append(uv)
		if ind == null or (ind as PackedInt32Array).is_empty():
			for i in v.size():
				idx.append(base + i)
		else:
			for i in ind:
				idx.append(base + i)

	func box(size: Vector3, pos: Vector3, c: Color, part := 0.0, rot := Vector3.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		add_mesh(m, Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos), c, Vector2(part, 0.0))

	func cyl(rt: float, rb: float, h: float, pos: Vector3, c: Color, part := 0.0, rot := Vector3.ZERO, seg := 8) -> void:
		var m := CylinderMesh.new()
		m.top_radius = rt
		m.bottom_radius = rb
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		add_mesh(m, Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos), c, Vector2(part, 0.0))

	## A lumpy ball (a crown of leaves, a bush): a sphere whose surface is pushed in and out.
	## UV.y = 0 at its bottom … 1 at its top.
	func blob(center: Vector3, radii: Vector3, seg: int, rings: int, seed: float, lump: float, c: Color, part := 0.0) -> void:
		var base := verts.size()
		for r in rings + 1:
			var v := float(r) / rings
			var phi := v * PI
			for s in seg + 1:
				var u := float(s % seg) / seg
				var th := u * TAU
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var k := 1.0 + lump * (sin(d.x * 5.1 + seed) * sin(d.y * 4.3 + seed * 1.7) * sin(d.z * 4.7 + seed * 0.6) + 0.5 * sin(d.x * 9.7 + d.z * 8.3 + seed * 2.3))
				verts.append(center + d * radii * k)
				norms.append((d / radii).normalized())
				cols.append(c)
				uvs.append(Vector2(part, 1.0 - v))
		for r in rings:
			for s in seg:
				var a := base + r * (seg + 1) + s
				var b := a + seg + 1
				idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))

	## A hull through cross-sections [z, half width, y bottom, y top] (a car body, a cabin):
	## sides, top, bottom and both ends.
	func hull(sections: Array, c: Color, part := 0.0) -> void:
		for i in sections.size() - 1:
			var a: Array = sections[i]
			var b: Array = sections[i + 1]
			var a0 := Vector3(-a[1], a[2], a[0])
			var a1 := Vector3(a[1], a[2], a[0])
			var a2 := Vector3(a[1], a[3], a[0])
			var a3 := Vector3(-a[1], a[3], a[0])
			var b0 := Vector3(-b[1], b[2], b[0])
			var b1 := Vector3(b[1], b[2], b[0])
			var b2 := Vector3(b[1], b[3], b[0])
			var b3 := Vector3(-b[1], b[3], b[0])
			quad(a3, a2, b2, b3, c, part)   # top
			quad(a1, a0, b0, b1, c, part)   # bottom
			quad(a2, a1, b1, b2, c, part)   # +x side
			quad(a0, a3, b3, b0, c, part)   # −x side
		var f: Array = sections[0]
		quad(Vector3(f[1], f[3], f[0]), Vector3(-f[1], f[3], f[0]), Vector3(-f[1], f[2], f[0]), Vector3(f[1], f[2], f[0]), c, part)
		var l: Array = sections[sections.size() - 1]
		quad(Vector3(-l[1], l[3], l[0]), Vector3(l[1], l[3], l[0]), Vector3(l[1], l[2], l[0]), Vector3(-l[1], l[2], l[0]), c, part)

	## One flat quad with its own normal (corners counter-clockwise seen from outside).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color, part := 0.0) -> void:
		var n := (p2 - p0).cross(p1 - p0).normalized()
		var base := verts.size()
		for p in [p0, p1, p2, p3]:
			verts.append(p)
			norms.append(n)
			cols.append(c)
			uvs.append(Vector2(part, 0.0))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	func commit() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		a[Mesh.ARRAY_TEX_UV] = uvs
		if not uv2s.is_empty():
			while uv2s.size() < verts.size():
				uv2s.append(Vector2.ZERO)
			a[Mesh.ARRAY_TEX_UV2] = uv2s
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return am


static var _cache := {}


static func _cyl_mesh(rt: float, rb: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _xf(pos: Vector3, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis().scaled(scale), pos)


## Wraps clumps of a crown ([centre, radii]) in leaf cards over a smaller dark core. y0..y1 is the
## height span of the crown (for the shading), per the number of cards a clump gets.
static func _leafy(mb: MeshBuilder, clumps: Array, y0: float, y1: float, per: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var white := Color(1, 1, 1)
	for i in clumps.size():
		var c: Vector3 = clumps[i][0]
		var r: Vector3 = clumps[i][1]
		mb.blob(c, r * 0.66, 8, 5, 1.0 + i * 1.7, 0.2, Color(0.5, 0.5, 0.5))
		for k in per:
			var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.55, 1.0), rng.randf_range(-1.0, 1.0))
			if d.length() < 0.2:
				continue
			d = d.normalized()
			var p := c + d * r * rng.randf_range(0.6, 1.0)
			# the card leans off the surface of the clump, every one its own way
			var nc := (d + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.8).normalized()
			var t1 := nc.cross(Vector3.UP if absf(nc.y) < 0.9 else Vector3.RIGHT).normalized()
			var t2 := nc.cross(t1)
			var spin := rng.randf() * TAU
			var a1 := t1 * cos(spin) + t2 * sin(spin)
			var a2 := nc.cross(a1)
			var shade := rng.randf_range(0.8, 1.15)
			mb.card(p, a1, a2, rng.randf_range(1.9, 2.8), (d + Vector3(0, 0.5, 0)).normalized(), Color(shade, shade, shade), clampf((p.y - y0) / (y1 - y0), 0.0, 1.0))


## Chestnut / linden / poplar: a trunk and a crown of lumpy clumps. About 11 m at scale 1.
## detail 0 = seen from kilometres (one clump), 1 = a street tree, 2 = close up (branches, nine
## clumps). Shaders.TREE shades it: UV.x = 1 on the wood.
static func deciduous_mesh(detail := 1) -> ArrayMesh:
	var key := "tree%d" % detail
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var white := Color(1, 1, 1)
	if detail <= 0:
		mb.cyl(0.2, 0.32, 4.0, Vector3(0, 2.0, 0), white, 1.0, Vector3.ZERO, 5)
		mb.blob(Vector3(0, 7.0, 0), Vector3(3.6, 3.9, 3.6), 7, 4, 1.0, 0.16, white)
	elif detail == 1:
		mb.cyl(0.18, 0.34, 4.6, Vector3(0, 2.3, 0), white, 1.0, Vector3.ZERO, 6)
		mb.blob(Vector3(0, 7.2, 0), Vector3(3.3, 3.2, 3.3), 9, 5, 1.0, 0.2, white)
		mb.blob(Vector3(1.6, 8.6, 0.7), Vector3(2.2, 2.0, 2.2), 8, 4, 2.3, 0.2, white)
		mb.blob(Vector3(-1.5, 6.4, -1.1), Vector3(2.3, 1.9, 2.3), 8, 4, 4.1, 0.2, white)
	elif detail >= 3:
		# close up (Max / UltraMax): the trunk forks into boughs, every clump is a dark core
		# wrapped in sprays of leaves — cards whose gaps the shader cuts out, so the outline of
		# the crown is leaves and sky, not a polygon
		mb.cyl(0.21, 0.4, 5.2, Vector3(0, 2.6, 0), white, 1.0, Vector3.ZERO, 10)
		for b in [[Vector3(1.0, 6.2, 0.3), Vector3(0, 0, -34)], [Vector3(-0.9, 6.0, -0.6), Vector3(22, 0, 32)], [Vector3(0.1, 6.6, 1.0), Vector3(-32, 0, 4)],
				[Vector3(0.3, 7.6, -0.3), Vector3(8, 0, -8)], [Vector3(-0.2, 6.2, -1.2), Vector3(38, 0, -6)]]:
			mb.cyl(0.07, 0.17, 3.4, b[0], white, 1.0, b[1], 6)
		var clumps := [[Vector3(0, 8.5, 0), Vector3(2.6, 2.4, 2.6)], [Vector3(2.0, 7.4, 0.6), Vector3(2.0, 1.7, 2.0)], [Vector3(-1.9, 7.2, -0.9), Vector3(2.1, 1.8, 2.0)],
			[Vector3(0.4, 7.0, 2.1), Vector3(1.9, 1.6, 1.9)], [Vector3(-0.5, 6.9, -2.2), Vector3(1.9, 1.6, 1.8)], [Vector3(1.3, 9.7, -0.8), Vector3(1.7, 1.5, 1.7)],
			[Vector3(-1.2, 9.5, 0.9), Vector3(1.7, 1.5, 1.7)], [Vector3(2.4, 6.0, -1.4), Vector3(1.4, 1.2, 1.4)], [Vector3(-2.5, 5.9, 1.2), Vector3(1.5, 1.2, 1.4)]]
		_leafy(mb, clumps, 4.6, 11.4, 30, 811)
	else:
		mb.cyl(0.2, 0.38, 5.0, Vector3(0, 2.5, 0), white, 1.0, Vector3.ZERO, 8)
		# main boughs
		for b in [[Vector3(0.9, 6.0, 0.3), Vector3(0, 0, -32)], [Vector3(-0.8, 5.8, -0.5), Vector3(20, 0, 30)], [Vector3(0.1, 6.4, 0.9), Vector3(-30, 0, 4)]]:
			mb.cyl(0.08, 0.16, 3.0, b[0], white, 1.0, b[1], 5)
		var clumps := [[Vector3(0, 8.4, 0), Vector3(2.6, 2.4, 2.6)], [Vector3(2.0, 7.4, 0.6), Vector3(2.0, 1.7, 2.0)], [Vector3(-1.9, 7.2, -0.9), Vector3(2.1, 1.8, 2.0)],
			[Vector3(0.4, 7.0, 2.1), Vector3(1.9, 1.6, 1.9)], [Vector3(-0.5, 6.9, -2.2), Vector3(1.9, 1.6, 1.8)], [Vector3(1.3, 9.6, -0.8), Vector3(1.7, 1.5, 1.7)],
			[Vector3(-1.2, 9.4, 0.9), Vector3(1.7, 1.5, 1.7)], [Vector3(2.4, 6.0, -1.4), Vector3(1.4, 1.2, 1.4)], [Vector3(-2.5, 5.9, 1.2), Vector3(1.5, 1.2, 1.4)]]
		for i in clumps.size():
			mb.blob(clumps[i][0], clumps[i][1], 10, 6, 1.0 + i * 1.7, 0.24, white)
	var m := mb.commit()
	_cache[key] = m
	return m


## Scots pine: a tall bare trunk with a flat crown at the top. About 16 m at scale 1.
static func conifer_mesh(detail := 1) -> ArrayMesh:
	var key := "pine%d" % detail
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var white := Color(1, 1, 1)
	if detail <= 0:
		mb.cyl(0.12, 0.26, 9.0, Vector3(0, 4.5, 0), white, 1.0, Vector3.ZERO, 5)
		mb.blob(Vector3(0, 11.2, 0), Vector3(2.9, 3.6, 2.9), 7, 4, 3.0, 0.2, white)
	elif detail >= 3:
		mb.cyl(0.11, 0.28, 10.5, Vector3(0, 5.25, 0), white, 1.0, Vector3.ZERO, 10)
		for b in [[Vector3(0.7, 8.2, 0.1), Vector3(0, 0, -62)], [Vector3(-0.6, 7.4, -0.3), Vector3(30, 0, 58)], [Vector3(0.9, 10.6, 0.3), Vector3(0, 0, -48)], [Vector3(-0.8, 10.9, -0.5), Vector3(20, 0, 50)]]:
			mb.cyl(0.03, 0.07, 2.0, b[0], white, 1.0, b[1], 5)
		_leafy(mb, [[Vector3(0, 12.6, 0), Vector3(2.4, 2.0, 2.4)], [Vector3(1.3, 10.8, 0.5), Vector3(2.0, 1.3, 2.0)], [Vector3(-1.2, 11.0, -0.8), Vector3(2.1, 1.3, 1.9)],
			[Vector3(0.2, 9.4, -1.3), Vector3(1.7, 1.0, 1.6)], [Vector3(-0.4, 14.0, 0.4), Vector3(1.5, 1.5, 1.5)]], 8.4, 15.5, 30, 433)
	else:
		var seg := 6 if detail == 1 else 8
		mb.cyl(0.11, 0.28, 10.5, Vector3(0, 5.25, 0), white, 1.0, Vector3.ZERO, seg)
		var clumps := [[Vector3(0, 12.6, 0), Vector3(2.4, 2.0, 2.4)], [Vector3(1.3, 10.8, 0.5), Vector3(2.0, 1.3, 2.0)], [Vector3(-1.2, 11.0, -0.8), Vector3(2.1, 1.3, 1.9)],
			[Vector3(0.2, 9.4, -1.3), Vector3(1.7, 1.0, 1.6)], [Vector3(-0.4, 14.0, 0.4), Vector3(1.5, 1.5, 1.5)]]
		for i in (clumps.size() if detail >= 2 else 3):
			mb.blob(clumps[i][0], clumps[i][1], 8 if detail == 1 else 10, 4 if detail == 1 else 6, 2.0 + i * 1.3, 0.26, white)
		if detail >= 2:
			# a few dead boughs under the crown
			for b in [[Vector3(0.7, 8.2, 0.1), Vector3(0, 0, -62)], [Vector3(-0.6, 7.4, -0.3), Vector3(30, 0, 58)]]:
				mb.cyl(0.03, 0.06, 1.6, b[0], white, 1.0, b[1], 4)
	var m := mb.commit()
	_cache[key] = m
	return m


## Passenger car (≈4.5 m), front towards -Z. Instance colour paints the body; UV.x marks the
## glass (1), tyres and trim (2), head lamps (3) and tail lamps (4) for Shaders.CAR.
## detail 0 = a box with a cabin, 1 = a shaped body with wheels, 2 = bumpers, mirrors, arches.
static func car_mesh(detail := 1) -> ArrayMesh:
	var key := "car%d" % detail
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var paint := Color(1, 1, 1)
	if detail <= 0:
		mb.box(Vector3(1.8, 0.62, 4.4), Vector3(0, 0.6, 0), paint)
		mb.box(Vector3(1.6, 0.56, 2.3), Vector3(0, 1.18, 0.25), paint, 1.0)
		mb.box(Vector3(1.86, 0.3, 4.2), Vector3(0, 0.24, 0), paint, 2.0)
	elif detail >= 3:
		# close up (Max / UltraMax): a curved skin — the body from bumper to bumper, the cabin
		# leaning in to the roof — with the glass set into it, lamps, a grille, plates, mirrors
		mb.loft([[-2.24, 0.62, 0.58, 0.4, 0.6, 0.06], [-2.14, 0.83, 0.78, 0.27, 0.7, 0.1], [-1.55, 0.9, 0.86, 0.2, 0.82, 0.1], [-0.95, 0.91, 0.88, 0.2, 0.92, 0.09],
			[0.0, 0.92, 0.88, 0.2, 0.95, 0.09], [1.25, 0.91, 0.87, 0.2, 0.97, 0.09], [1.9, 0.88, 0.84, 0.24, 0.96, 0.1], [2.14, 0.8, 0.76, 0.3, 0.86, 0.1],
			[2.25, 0.66, 0.62, 0.4, 0.72, 0.06]], paint)
		mb.loft([[-1.0, 0.84, 0.8, 0.9, 0.95, 0.02], [-0.3, 0.83, 0.64, 0.92, 1.4, 0.07], [0.3, 0.83, 0.65, 0.93, 1.43, 0.07], [0.95, 0.83, 0.64, 0.94, 1.41, 0.07],
			[1.74, 0.84, 0.78, 0.95, 1.0, 0.02]], paint)
		# windscreen, rear window and the side glass, a hair proud of the cabin
		var wn := Vector3(0, 0.84, -0.55).normalized()
		mb.quad_n(Vector3(-0.73, 1.0, -0.91) + wn * 0.014, Vector3(0.73, 1.0, -0.91) + wn * 0.014, Vector3(0.59, 1.365, -0.35) + wn * 0.014, Vector3(-0.59, 1.365, -0.35) + wn * 0.014, wn, paint, 1.0)
		var rn := Vector3(0, 0.88, 0.47).normalized()
		mb.quad_n(Vector3(-0.59, 1.375, 1.01) + rn * 0.014, Vector3(0.59, 1.375, 1.01) + rn * 0.014, Vector3(0.71, 1.045, 1.65) + rn * 0.014, Vector3(-0.71, 1.045, 1.65) + rn * 0.014, rn, paint, 1.0)
		for sx in [-1.0, 1.0]:
			var sn := Vector3(sx * 0.92, 0.4, 0).normalized()
			var xb: float = sx * 0.836
			var xt: float = sx * 0.694
			mb.quad_n(Vector3(xb, 1.0, -0.76), Vector3(xb, 1.0, 0.2), Vector3(xt, 1.33, 0.2), Vector3(xt, 1.33, -0.27), sn, paint, 1.0)
			mb.quad_n(Vector3(xb, 1.0, 0.29), Vector3(xb, 1.0, 1.46), Vector3(xt, 1.33, 0.9), Vector3(xt, 1.33, 0.29), sn, paint, 1.0)
			# the mirror, the door handles, a dark sill
			mb.box(Vector3(0.17, 0.11, 0.1), Vector3(0.97 * sx, 1.02, -0.74), paint)
			mb.box(Vector3(0.03, 0.03, 0.16), Vector3(0.925 * sx, 0.86, -0.1), paint, 5.0)
			mb.box(Vector3(0.03, 0.03, 0.16), Vector3(0.92 * sx, 0.87, 0.95), paint, 5.0)
			mb.box(Vector3(0.05, 0.1, 2.3), Vector3(0.9 * sx, 0.26, 0.0), paint, 2.0)
			# lamps: a wide head lamp wrapping the corner, a tall tail lamp
			mb.box(Vector3(0.44, 0.13, 0.16), Vector3(0.56 * sx, 0.67, -2.15), paint, 3.0, Vector3(0, -12.0 * sx, 0))
			mb.box(Vector3(0.36, 0.17, 0.12), Vector3(0.6 * sx, 0.8, 2.17), paint, 4.0, Vector3(0, 10.0 * sx, 0))
		for wz in [-1.38, 1.36]:
			for sx in [-1.0, 1.0]:
				mb.cyl(0.335, 0.335, 0.23, Vector3(0.8 * sx, 0.335, wz), paint, 2.0, Vector3(0, 0, 90), 18)
				mb.cyl(0.2, 0.2, 0.245, Vector3(0.805 * sx, 0.335, wz), paint, 5.0, Vector3(0, 0, 90), 12)
				mb.cyl(0.07, 0.07, 0.26, Vector3(0.805 * sx, 0.335, wz), paint, 2.0, Vector3(0, 0, 90), 8)
		# the grille and the lower intakes, the plates
		mb.box(Vector3(0.74, 0.13, 0.06), Vector3(0, 0.6, -2.235), paint, 2.0)
		mb.box(Vector3(1.3, 0.12, 0.08), Vector3(0, 0.36, -2.2), paint, 2.0)
		mb.box(Vector3(1.36, 0.12, 0.08), Vector3(0, 0.38, 2.2), paint, 2.0)
		mb.box(Vector3(0.5, 0.11, 0.03), Vector3(0, 0.47, -2.262), paint, 6.0)
		mb.box(Vector3(0.5, 0.11, 0.03), Vector3(0, 0.6, 2.262), paint, 6.0)
	else:
		# the body, nose first: bumper, bonnet, the waist under the cabin, boot, tail
		mb.hull([[-2.25, 0.8, 0.3, 0.6], [-2.1, 0.88, 0.24, 0.7], [-1.0, 0.9, 0.22, 0.84], [1.25, 0.9, 0.22, 0.9], [2.1, 0.88, 0.26, 0.86], [2.22, 0.8, 0.34, 0.7]], paint)
		# the glasshouse and the roof panel over it
		mb.hull([[-1.0, 0.82, 0.84, 0.86], [-0.3, 0.72, 0.86, 1.38], [0.85, 0.72, 0.88, 1.4], [1.6, 0.8, 0.9, 0.92]], paint, 1.0)
		mb.hull([[-0.32, 0.7, 1.37, 1.42], [0.86, 0.7, 1.39, 1.44]], paint)
		var seg := 8 if detail == 1 else 14
		for wz in [-1.38, 1.36]:
			for sx in [-1.0, 1.0]:
				mb.cyl(0.33, 0.33, 0.24, Vector3(0.82 * sx, 0.33, wz), paint, 2.0, Vector3(0, 0, 90), seg)
				if detail >= 2:
					mb.cyl(0.19, 0.19, 0.26, Vector3(0.83 * sx, 0.33, wz), Color(1, 1, 1), 5.0, Vector3(0, 0, 90), 8)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(0.42, 0.16, 0.08), Vector3(0.6 * sx, 0.62, -2.21), paint, 3.0)
			mb.box(Vector3(0.44, 0.14, 0.08), Vector3(0.6 * sx, 0.72, 2.2), paint, 4.0)
		if detail >= 2:
			mb.box(Vector3(1.7, 0.16, 0.14), Vector3(0, 0.36, -2.24), paint, 2.0)
			mb.box(Vector3(1.7, 0.16, 0.14), Vector3(0, 0.4, 2.22), paint, 2.0)
			mb.box(Vector3(0.6, 0.12, 0.05), Vector3(0, 0.5, 2.25), paint, 5.0)
			for sx in [-1.0, 1.0]:
				mb.box(Vector3(0.2, 0.12, 0.12), Vector3(0.98 * sx, 0.95, -0.72), paint)
				mb.box(Vector3(0.04, 0.5, 0.04), Vector3(0.76 * sx, 1.12, 0.28), paint, 2.0)
	var m := mb.commit()
	_cache[key] = m
	return m


## Pedestrian (≈1.8 m), facing -Z: UV.x marks the skin (1), trousers and shoes (2) and hair (3);
## the coat takes the instance colour (Shaders.PEOPLE).
static func person_mesh() -> ArrayMesh:
	if _cache.has("person"):
		return _cache["person"]
	var mb := MeshBuilder.new()
	var c := Color(1, 1, 1)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(0.17, 0.86, 0.2), Vector3(0.1 * sx, 0.43, 0), c, 2.0)
		mb.box(Vector3(0.11, 0.62, 0.14), Vector3(0.29 * sx, 1.13, 0), c)
	mb.box(Vector3(0.44, 0.64, 0.26), Vector3(0, 1.17, 0), c)
	mb.cyl(0.07, 0.07, 0.1, Vector3(0, 1.53, 0), c, 1.0, Vector3.ZERO, 6)
	mb.blob(Vector3(0, 1.68, 0), Vector3(0.12, 0.14, 0.13), 7, 4, 0.0, 0.0, c, 1.0)
	mb.blob(Vector3(0, 1.73, 0.02), Vector3(0.125, 0.11, 0.135), 7, 3, 0.0, 0.0, c, 3.0)
	var m := mb.commit()
	_cache["person"] = m
	return m


## A street lamp post, 9 m at scale 1: the arm reaches out towards -Z with the lamp head at its
## end (the glow is a separate sprite there).
static func lamp_post_mesh() -> ArrayMesh:
	if _cache.has("post"):
		return _cache["post"]
	var mb := MeshBuilder.new()
	var c := Color(1, 1, 1)
	mb.cyl(0.14, 0.2, 0.9, Vector3(0, 0.45, 0), c, 0.0, Vector3.ZERO, 8)
	mb.cyl(0.07, 0.11, 8.2, Vector3(0, 5.0, 0), c, 0.0, Vector3.ZERO, 8)
	mb.cyl(0.05, 0.06, 2.1, Vector3(0, 9.1, -0.98), c, 0.0, Vector3(80, 0, 0), 6)
	mb.box(Vector3(0.34, 0.12, 0.8), Vector3(0, 9.26, -2.1), Color(1.6, 1.6, 1.6))
	var m := mb.commit()
	_cache["post"] = m
	return m


# --- Living city props --------------------------------------------------------------------
static func boat() -> Node3D:
	var root := Node3D.new()
	var hull := Fx.solid(Color(0.85, 0.85, 0.82), 0.6)
	box(root, Vector3(4.5, 1.8, 16.0), Vector3(0, 0.6, 0), Fx.solid(Color(0.15, 0.2, 0.3), 0.6))
	box(root, Vector3(3.6, 1.6, 8.0), Vector3(0, 2.2, 1.5), hull)
	box(root, Vector3(3.7, 0.5, 7.0), Vector3(0, 2.4, 1.5), Fx.glow(Color(1.0, 0.8, 0.5), 1.6))
	box(root, Vector3(2.6, 1.4, 3.0), Vector3(0, 3.6, -1.0), hull)
	for spec in [[Vector3(0, 5.0, -1.0), Color(1, 1, 0.9)], [Vector3(-2.3, 1.8, -6.0), Color(1, 0.15, 0.1)], [Vector3(2.3, 1.8, -6.0), Color(0.2, 1, 0.3)]]:
		var g := Fx.glare(spec[1], 1.6, 0.8, 0.0022, 0.0)
		g.position = spec[0]
		root.add_child(g)
	return root


static func metro_train(cars := 5) -> Node3D:
	var root := Node3D.new()
	var body := Fx.solid(Color(0.2, 0.35, 0.55), 0.5, 0.2)
	var win := Fx.glow(Color(1.0, 0.92, 0.75), 1.8)
	for i in cars:
		var z := float(i) * 15.0
		box(root, Vector3(3.0, 3.2, 14.2), Vector3(0, 1.6, z), body)
		box(root, Vector3(3.05, 0.9, 12.0), Vector3(0, 2.1, z), win)
	var head := Fx.glare(Color(1, 0.95, 0.8), 2.0, 1.2, 0.003, 0.0)
	head.position = Vector3(0, 1.4, -7.4)
	root.add_child(head)
	var tail := Fx.glare(Color(1, 0.1, 0.05), 1.6, 0.8, 0.0025, 0.0)
	tail.position = Vector3(0, 1.4, (cars - 1) * 15.0 + 7.4)
	root.add_child(tail)
	return root


## F-16 fighter for the interceptor sorties (scripts/game/fighter.gd), nose towards -Z, about
## 15 m long. Meta "burner": the afterburner flame (shown with the throttle past military power),
## "muzzle": the M61 gun port, "rails": the four missile stations under the wings.
static func f16() -> Node3D:
	var root := Node3D.new()
	var grey := Fx.solid(Color(0.46, 0.5, 0.54), 0.55, 0.15)
	var dark := Fx.solid(Color(0.2, 0.22, 0.25), 0.6)
	var glass := Fx.solid(Color(0.55, 0.45, 0.2), 0.08, 0.6)
	# fuselage with the chin intake and a pointed radome
	cyl(root, 0.75, 0.85, 11.0, Vector3(0, 0, 0.5), grey, Vector3(90, 0, 0), 12)
	cyl(root, 0.0, 0.75, 3.2, Vector3(0, 0, -6.6), grey, Vector3(-90, 0, 0), 12)
	box(root, Vector3(1.3, 0.8, 3.2), Vector3(0, -0.85, -1.6), dark)
	# bubble canopy
	var can := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.62
	sm.height = 1.24
	can.mesh = sm
	can.material_override = glass
	can.scale = Vector3(0.85, 0.75, 2.3)
	can.position = Vector3(0, 0.72, -3.4)
	root.add_child(can)
	# cropped-delta wing, horizontal tail, the fin
	for sx in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.mesh = _wing_mesh(4.9, 3.6, 1.2, 0.18)
		wing.material_override = grey
		wing.position = Vector3(0.6 * sx, -0.1, 1.2)
		wing.scale = Vector3(sx, 1, 1)
		root.add_child(wing)
		var stab := MeshInstance3D.new()
		stab.mesh = _wing_mesh(2.6, 2.0, 0.9, 0.14)
		stab.material_override = grey
		stab.position = Vector3(0.5 * sx, 0.0, 5.2)
		stab.scale = Vector3(sx, 1, 1)
		root.add_child(stab)
		# wingtip rail with a missile, and the navigation light
		box(root, Vector3(0.14, 0.14, 2.6), Vector3(5.45 * sx, -0.05, 2.1), Fx.solid(Color(0.85, 0.85, 0.82), 0.5))
		var nav := MeshInstance3D.new()
		nav.mesh = Fx.cube(Vector3(0.18, 0.18, 0.18))
		nav.material_override = Fx.glow(Color(1.0, 0.1, 0.05) if sx < 0.0 else Color(0.1, 1.0, 0.25), 6.0)
		nav.position = Vector3(5.5 * sx, 0.0, 0.8)
		root.add_child(nav)
	var fin := MeshInstance3D.new()
	fin.mesh = _wing_mesh(2.9, 2.8, 1.0, 0.14)
	fin.material_override = grey
	fin.rotation_degrees = Vector3(0, 0, 90)
	fin.position = Vector3(0, 0.6, 4.3)
	root.add_child(fin)
	# nozzle and the afterburner
	cyl(root, 0.62, 0.72, 1.2, Vector3(0, 0, 6.5), dark, Vector3(90, 0, 0), 12)
	var burner := Node3D.new()
	burner.position = Vector3(0, 0, 7.2)
	root.add_child(burner)
	var flame := cyl(burner, 0.05, 0.62, 4.5, Vector3(0, 0, 2.2), Fx.ghost(Color(1.0, 0.6, 0.3, 1.0), 5.0), Vector3(90, 0, 0), 10)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Fx.glare(Color(1.0, 0.7, 0.45), 5.0, 2.6, 0.006, 0.35, 0.25)
	burner.add_child(g)
	burner.visible = false
	# the nozzle glows even at military power; a white strobe on the fin for the night
	var glow := MeshInstance3D.new()
	glow.mesh = Fx.sphere(0.5, 8)
	glow.material_override = Fx.glow(Color(1.0, 0.55, 0.25), 3.0)
	glow.position = Vector3(0, 0, 7.05)
	glow.scale = Vector3(1, 1, 0.3)
	root.add_child(glow)
	var strobe := Fx.glare(Color(1.0, 1.0, 1.0), 4.0, 1.6, 0.005, 0.2, 0.9)
	strobe.position = Vector3(0, 3.2, 5.6)
	root.add_child(strobe)
	root.set_meta("burner", burner)
	root.set_meta("muzzle", node(root, Vector3(-0.7, 0.4, -3.8)))
	return root


## A flat, swept surface (wing, tail) of span `span` along +x, root chord `root_c`, tip chord
## `tip_c`, thickness `t`; the leading edge sweeps back towards +z.
static func _wing_mesh(span: float, root_c: float, tip_c: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sweep := root_c - tip_c
	var top := [Vector3(0, t, -root_c * 0.5), Vector3(span, t * 0.4, -root_c * 0.5 + sweep), Vector3(span, t * 0.4, -root_c * 0.5 + sweep + tip_c), Vector3(0, t, root_c * 0.5)]
	var bot := []
	for p in top:
		bot.append(Vector3(p.x, -p.y, p.z))
	var quads := [[top[0], top[1], top[2], top[3]], [bot[3], bot[2], bot[1], bot[0]],
		[bot[0], bot[1], top[1], top[0]], [top[3], top[2], bot[2], bot[3]], [top[1], bot[1], bot[2], top[2]]]
	for q in quads:
		# both windings: the surfaces are thin and must show from either side
		for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]], [q[0], q[2], q[1]], [q[0], q[3], q[2]]]:
			var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()
