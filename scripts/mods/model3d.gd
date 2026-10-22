extends RefCounted
## Models of the mods' own systems and threats: «<name>.uadmodel», a JSON file that the 3D editors
## (the game's mod workshop, the mod maker site) write and the game builds:
##   {"uad_model": 1, "kind": "weapon" | "enemy", "name": …,
##    "pivots": {"turret": [x, y, z], "gun": [x, y, z], "muzzle": [x, y, z], "spin": [x, y, z]},
##    "parts": [{"shape": "box" | "cylinder" | "sphere" | "prism" | "mesh", "group": "body" | "turret" | "gun" | "spin",
##               "pos": [x, y, z], "rot": [x, y, z] (degrees, Godot's Y-X-Z order), "size": [x, y, z],
##               "color": "#rrggbb", "mat": "paint" | "solid" | "metal" | "glass" | "glow",
##               "taper": [bottom, top] (cylinder radii, × size.x / 2), "apex": 0..1 (prism), "seg": n,
##               "tris": [x, y, z, …] (mesh: triangles, × size)}, …]}
## Metres; forward is -Z (as every model of the game). A weapon's "turret" parts turn round the turret
## pivot, its "gun" parts also tilt round the gun pivot (relative to the turret), the shots leave from
## the muzzle (relative to the gun); a threat's "spin" parts turn round the spin pivot (a propeller).
## The game's own models turn into this format with from_node() — the editors start from them.

const Fx = preload("res://scripts/core/fx.gd")

const VERSION := 1
const SHAPES := ["box", "cylinder", "sphere", "prism", "mesh"]
const GROUPS := ["body", "turret", "gun", "spin"]
const MATS := ["paint", "solid", "metal", "glass", "glow"]
const MAX_PARTS := 400
const MAX_TRIS_FLOATS := 18000
const MAX_SIZE := 80.0
const DEFAULT_PIVOTS := {"turret": [0.0, 1.6, 0.0], "gun": [0.0, 0.6, 0.0], "muzzle": [0.0, 0.0, -2.0], "spin": [0.0, 0.0, 1.0]}


# --- checking ------------------------------------------------------------------------------------
## A model as the game keeps it: every value checked and clamped. {"error": sentence} when it is no model.
static func sanitize(d) -> Dictionary:
	if not (d is Dictionary) or not (d.get("parts") is Array):
		return {"error": "not a UAD model (no \"parts\")"}
	var parts: Array = d.parts
	if parts.size() > MAX_PARTS:
		return {"error": "too many parts (%d, at most %d)" % [parts.size(), MAX_PARTS]}
	var out := {"uad_model": VERSION, "kind": "enemy" if String(d.get("kind", "weapon")) == "enemy" else "weapon",
		"name": String(d.get("name", "")).left(48), "pivots": {}, "parts": []}
	var pv = d.get("pivots", {})
	for k in DEFAULT_PIVOTS:
		out.pivots[k] = _vec(pv.get(k) if pv is Dictionary else null, DEFAULT_PIVOTS[k], -MAX_SIZE, MAX_SIZE)
	var floats := 0
	for p in parts:
		if not (p is Dictionary):
			continue
		var shape := String(p.get("shape", "box"))
		if not SHAPES.has(shape):
			shape = "box"
		var q := {"shape": shape, "group": String(p.get("group", "body")) if GROUPS.has(String(p.get("group", "body"))) else "body",
			"pos": _vec(p.get("pos"), [0.0, 0.0, 0.0], -MAX_SIZE, MAX_SIZE),
			"rot": _vec(p.get("rot"), [0.0, 0.0, 0.0], -720.0, 720.0),
			"size": _vec(p.get("size"), [1.0, 1.0, 1.0], 0.005, MAX_SIZE),
			"color": _color_hex(p.get("color", "#808080")),
			"mat": String(p.get("mat", "paint")) if MATS.has(String(p.get("mat", "paint"))) else "paint"}
		match shape:
			"cylinder":
				var t = p.get("taper", [1.0, 1.0])
				q["taper"] = [clampf(float(t[0]) if t is Array and t.size() == 2 else 1.0, 0.0, 1.0), clampf(float(t[1]) if t is Array and t.size() == 2 else 1.0, 0.0, 1.0)]
				q["seg"] = clampi(int(p.get("seg", 12)), 3, 32)
			"prism":
				q["apex"] = clampf(float(p.get("apex", 0.5)), 0.0, 1.0)
			"mesh":
				var tris = p.get("tris", [])
				if not (tris is Array) or tris.size() < 9:
					continue
				var n: int = tris.size() - tris.size() % 9
				if floats + n > MAX_TRIS_FLOATS:
					return {"error": "the model's own meshes are too detailed"}
				var flat := []
				for i in n:
					flat.append(clampf(float(tris[i]) if (tris[i] is float or tris[i] is int) else 0.0, -MAX_SIZE, MAX_SIZE))
				floats += n
				q["tris"] = flat
		out.parts.append(q)
	if out.parts.is_empty():
		return {"error": "the model has no parts"}
	return out


static func _vec(v, dflt: Array, lo: float, hi: float) -> Array:
	if v is Array and v.size() == 3:
		var out := []
		for x in v:
			out.append(clampf(float(x) if (x is float or x is int) else 0.0, lo, hi))
		return out
	return dflt.duplicate()


static func _color_hex(v) -> String:
	if v is String and Color.html_is_valid(v):
		return "#" + Color.html(v).to_html(false)
	return "#808080"


## How high over the turret pivot the gunner's eye goes (the game's "eye" of a system): a little over
## the top of the turret and the gun, so the camera behind them sees past the model.
static func eye_height(d: Dictionary) -> float:
	var pv: Dictionary = d.get("pivots", DEFAULT_PIVOTS)
	var top := 0.5
	for p in d.get("parts", []):
		var y := float(p.pos[1]) + float(p.size[1]) * 0.5
		if String(p.group) == "gun":
			y += float(pv.gun[1])
		elif String(p.group) != "turret":
			continue
		top = maxf(top, y)
	return clampf(top + 1.2, 1.5, 14.0)


# --- building ------------------------------------------------------------------------------------
## The model as nodes, with the metas the game's units and threats look for (turret, pitch, muzzle,
## idle_pitch; spin).
static func build(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pv: Dictionary = d.get("pivots", DEFAULT_PIVOTS)
	var weapon := String(d.get("kind", "weapon")) == "weapon"
	var groups := {"body": root}
	if weapon:
		var turret := _pivot(root, pv.get("turret", DEFAULT_PIVOTS.turret))
		var gun := _pivot(turret, pv.get("gun", DEFAULT_PIVOTS.gun))
		root.set_meta("turret", turret)
		root.set_meta("pitch", gun)
		root.set_meta("muzzle", _pivot(gun, pv.get("muzzle", DEFAULT_PIVOTS.muzzle)))
		root.set_meta("idle_pitch", 0.15)
		groups.turret = turret
		groups.gun = gun
	var mats := {}
	for p in d.get("parts", []):
		var g := String(p.group)
		if g == "spin" and not groups.has("spin"):
			var spin := _pivot(root, pv.get("spin", DEFAULT_PIVOTS.spin))
			root.set_meta("spin", spin)
			groups.spin = spin
		var parent: Node3D = groups.get(g, root)
		var mi := part_node(p, mats)
		if mi != null:
			parent.add_child(mi)
	return root


static func _pivot(parent: Node3D, v) -> Node3D:
	var n := Node3D.new()
	n.position = _v3(v)
	parent.add_child(n)
	return n


static func _v3(v) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() == 3 else Vector3.ZERO


## One part as a MeshInstance3D (materials shared through `mats`).
static func part_node(p: Dictionary, mats := {}) -> MeshInstance3D:
	var size := _v3(p.size)
	var mi := MeshInstance3D.new()
	match String(p.shape):
		"box":
			var m := BoxMesh.new()
			m.size = size
			mi.mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			var t: Array = p.get("taper", [1.0, 1.0])
			m.bottom_radius = 0.5 * float(t[0])
			m.top_radius = 0.5 * float(t[1])
			m.height = 1.0
			m.radial_segments = int(p.get("seg", 12))
			m.rings = 1
			mi.mesh = m
			mi.scale = size
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 16
			m.rings = 8
			mi.mesh = m
			mi.scale = size
		"prism":
			var m := PrismMesh.new()
			m.size = size
			m.left_to_right = float(p.get("apex", 0.5))
			mi.mesh = m
		"mesh":
			mi.mesh = _tri_mesh(p.get("tris", []))
			mi.scale = size
	if mi.mesh == null:
		return null
	mi.position = _v3(p.pos)
	mi.rotation_degrees = _v3(p.rot)
	var key := String(p.color) + String(p.mat)
	if not mats.has(key):
		mats[key] = material(String(p.mat), Color.html(String(p.color)))
	mi.material_override = mats[key]
	return mi


static func material(kind: String, c: Color) -> Material:
	match kind:
		"solid":
			return Fx.solid(c, 0.8)
		"metal":
			return Fx.solid(c, 0.38, 0.75)
		"glass":
			return Fx.solid(c, 0.06, 0.3)
		"glow":
			return Fx.glow(c, 2.5)
	return Fx.paint(c, 0.75, 0.1, 0.5)


static func _tri_mesh(tris: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size() - 2, 3):
		st.add_vertex(Vector3(float(tris[i]), float(tris[i + 1]), float(tris[i + 2])))
	st.generate_normals()
	return st.commit()


# --- the game's own models into the format ---------------------------------------------------------
## A built model (Meshes.weapon_model / enemy_model) as a model of the format: every mesh a part in the
## group of the pivot it hangs from, its scale folded into its size.
static func from_node(root: Node3D, kind: String, mname := "") -> Dictionary:
	var pivots := {}
	var by_node := {root: "body"}
	if root.has_meta("turret"):
		var tu: Node3D = root.get_meta("turret")
		var gu: Node3D = root.get_meta("pitch")
		by_node[tu] = "turret"
		by_node[gu] = "gun"
		pivots.turret = _arr(_rel(tu, root).origin)
		pivots.gun = _arr(_rel(gu, tu).origin)
		if root.has_meta("muzzle"):
			pivots.muzzle = _arr(_rel(root.get_meta("muzzle"), gu).origin)
	if root.has_meta("spin"):
		var sp: Node3D = root.get_meta("spin")
		by_node[sp] = "spin"
		pivots.spin = _arr(_rel(sp, root).origin)
	var parts := []
	_collect(root, root, by_node, parts)
	return {"uad_model": VERSION, "kind": kind, "name": mname, "pivots": pivots, "parts": parts}


static func _collect(n: Node, root: Node3D, by_node: Dictionary, parts: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
			var pivot := _group_node(c, root, by_node)
			var p := _part_of(c, _rel(c, pivot))
			if not p.is_empty():
				p["group"] = by_node[pivot]
				parts.append(p)
		if c is Node3D:
			_collect(c, root, by_node, parts)


static func _group_node(n: Node, root: Node3D, by_node: Dictionary) -> Node3D:
	var p := n.get_parent()
	while p != null and p != root and not by_node.has(p):
		p = p.get_parent()
	return p if p != null and by_node.has(p) else root


## The transform of `n` in the space of its ancestor `anc` (no scene tree needed).
static func _rel(n: Node3D, anc: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != anc:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _part_of(mi: MeshInstance3D, t: Transform3D) -> Dictionary:
	var sc := t.basis.get_scale()
	var rot := t.basis.orthonormalized().get_euler() * (180.0 / PI)
	var p := {"pos": _arr(t.origin), "rot": _arr(rot)}
	var m := mi.mesh
	if m is BoxMesh:
		p.shape = "box"
		p.size = _arr((m as BoxMesh).size * sc)
	elif m is CylinderMesh:
		var cm := m as CylinderMesh
		var r := maxf(maxf(cm.top_radius, cm.bottom_radius), 0.001)
		p.shape = "cylinder"
		p.size = _arr(Vector3(2.0 * r, cm.height, 2.0 * r) * sc)
		p.taper = [snappedf(cm.bottom_radius / r, 0.001), snappedf(cm.top_radius / r, 0.001)]
		p.seg = cm.radial_segments
	elif m is SphereMesh:
		var sm := m as SphereMesh
		p.shape = "sphere"
		p.size = _arr(Vector3(2.0 * sm.radius, sm.height, 2.0 * sm.radius) * sc)
	elif m is PrismMesh:
		p.shape = "prism"
		p.size = _arr((m as PrismMesh).size * sc)
		p.apex = snappedf((m as PrismMesh).left_to_right, 0.001)
	elif m is PlaneMesh:
		var s2 := (m as PlaneMesh).size
		p.shape = "box"
		p.size = _arr(Vector3(s2.x, 0.01, s2.y) * sc)
	elif m is ArrayMesh or m is PrimitiveMesh:
		# anything else: its triangles
		var tris := []
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var order: Array = Array(idx) if idx != null and (idx as PackedInt32Array).size() > 0 else range(verts.size())
			for i in order:
				var v: Vector3 = verts[i] * sc
				tris.append_array([snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
		if tris.size() < 9 or tris.size() > 9000:
			return {}
		p.shape = "mesh"
		p.size = [1.0, 1.0, 1.0]
		p.tris = tris
	else:
		return {}
	var mat := mi.material_override if mi.material_override != null else mi.get_active_material(0)
	var look := _look_of(mat)
	p.color = look[0]
	p.mat = look[1]
	return p


static func _look_of(mat: Material) -> Array:
	if mat is ShaderMaterial:
		var b = (mat as ShaderMaterial).get_shader_parameter("base")
		if b is Color:
			return ["#" + (b as Color).to_html(false), "paint"]
		return ["#808080", "paint"]
	if mat is StandardMaterial3D:
		var s := mat as StandardMaterial3D
		if s.emission_enabled:
			return ["#" + s.emission.to_html(false), "glow"]
		var c := "#" + s.albedo_color.to_html(false)
		if s.metallic > 0.5:
			return [c, "metal"]
		if s.roughness < 0.2:
			return [c, "glass"]
		return [c, "solid"]
	return ["#808080", "solid"]
