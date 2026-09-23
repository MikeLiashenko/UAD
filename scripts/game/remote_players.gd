extends Node3D
## The other players of a multiplayer session in the 3D city: each friend's base (the same model
## as ours) under a beacon in their colour with a name tag, and their "eye" — a small glowing
## camera that sits where their camera is and turns where they look. Positions arrive a few
## times a second (Net) and are smoothed here.

const Meshes = preload("res://scripts/core/meshes.gd")
const Fx = preload("res://scripts/core/fx.gd")

## Eyes closer than this to our own camera are hidden (we are looking through them).
const EYE_HIDE := 6.0

var game
## code -> {root, base, beacon, tag, eye, eye_tag, cam: smoothed Transform3D, fov}
var _p := {}


func _process(delta: float) -> void:
	var me := Net.code()
	for c in Net.players:
		if c == me:
			continue
		var pl: Dictionary = Net.players[c]
		if not _p.has(c):
			_p[c] = _make(pl, String(c))
		_update(_p[c], pl, delta)
	for c in _p.keys():
		if not Net.players.has(c):
			(_p[c].root as Node3D).queue_free()
			_p.erase(c)


func _make(pl: Dictionary, code: String) -> Dictionary:
	var col: Color = pl.color
	var root := Node3D.new()
	add_child(root)
	var base := Meshes.base()
	base.visible = false
	root.add_child(base)
	# beacon: a tall thin beam of the player's colour, visible across the city at night
	var beacon := Node3D.new()
	var beam := Meshes.cyl(beacon, 1.6, 1.6, 260.0, Vector3(0, 130, 0), Fx.ghost(Color(col.r, col.g, col.b, 0.22), 1.6), Vector3.ZERO, 8)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Meshes.part(beacon, Fx.ring_mesh(36.0, 2.0), Fx.ghost(Color(col.r, col.g, col.b, 0.8), 1.8), Vector3(0, 1.2, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.visible = false
	root.add_child(beacon)
	var tag := _label(String(pl.nick), col, 34)
	tag.visible = false
	root.add_child(tag)
	# the eye: a lens with a short cone pointing where the friend looks
	var eye := Node3D.new()
	var lens := SphereMesh.new()
	lens.radius = 1.6
	lens.height = 3.2
	lens.radial_segments = 12
	lens.rings = 6
	Meshes.part(eye, lens, Fx.ghost(col, 2.4))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.6
	cone.height = 7.0
	cone.radial_segments = 10
	cone.rings = 1
	# cylinder axis is Y: tip back at the lens, mouth opening towards -Z (the look direction)
	Meshes.part(eye, cone, Fx.ghost(Color(col.r, col.g, col.b, 0.35), 1.4), Vector3(0, 0, -3.5), Vector3(-90, 0, 0))
	for mi in eye.get_children():
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.visible = false
	root.add_child(eye)
	var eye_tag := _label("", col, 26)
	eye_tag.visible = false
	root.add_child(eye_tag)
	return {"code": code, "root": root, "base": base, "beacon": beacon, "tag": tag, "eye": eye, "eye_tag": eye_tag,
		"cam": Transform3D.IDENTITY, "fov": 62.0, "placed": false, "base_at": Vector3.INF}


func _label(text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = GS.font
	l.font_size = size
	l.outline_size = 9
	l.modulate = Color(col.r, col.g, col.b, 1.0)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.pixel_size = 0.0011
	l.render_priority = 9
	return l


func _update(n: Dictionary, pl: Dictionary, delta: float) -> void:
	var nick := String(pl.nick)
	if bool(pl.has_base):
		var at: Vector3 = pl.base
		if not (n.base_at as Vector3).is_equal_approx(at):
			n.base_at = at
			var gy: float = game.map.ground_height(at.x, at.z)
			(n.base as Node3D).position = Vector3(at.x, gy, at.z)
			(n.beacon as Node3D).position = Vector3(at.x, gy, at.z)
			(n.tag as Node3D).position = Vector3(at.x, gy + 34.0, at.z)
		(n.base as Node3D).visible = true
		(n.beacon as Node3D).visible = not game.hide_markers()
		(n.tag as Label3D).visible = true
		(n.tag as Label3D).text = GS.t("База %s") % nick
	if not bool(pl.has_cam):
		(n.eye as Node3D).visible = false
		(n.eye_tag as Label3D).visible = false
		return
	# Smoothing over ~5 updates a second: the eye keeps moving with the friend's last known
	# velocity (carried forward by the age of the sample) and eases out the rest of the error;
	# the turn follows quickly enough for a gunner's turret and hides the steps between samples.
	var target: Transform3D = pl.cam
	var vel: Vector3 = pl.get("cam_vel", Vector3.ZERO)
	var age := clampf(float(Net.server_now() - int(pl.get("cam_t", 0))) / 1000.0, 0.0, 0.5)
	var want: Vector3 = target.origin + vel * age
	var cur: Transform3D = n.cam
	if not bool(n.placed) or cur.origin.distance_to(want) > 400.0:
		cur = Transform3D(target.basis, want)
		n.placed = true
	else:
		var origin: Vector3 = cur.origin + vel * delta
		origin += (want - origin) * (1.0 - exp(-delta * 6.0))
		var q := cur.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), 1.0 - exp(-delta * 10.0))
		cur = Transform3D(Basis(q), origin)
	n.cam = cur
	n.fov = lerpf(float(n.fov), float(pl.fov), 1.0 - exp(-delta * 10.0))
	var eye: Node3D = n.eye
	eye.global_transform = cur
	var mine: Vector3 = game.cam.global_position
	var close: bool = mine.distance_to(cur.origin) < EYE_HIDE or (game.view == "watch" and game.watch_code == String(n.code))
	eye.visible = not close
	var et: Label3D = n.eye_tag
	et.visible = eye.visible
	et.global_position = cur.origin + Vector3(0, 4.5, 0)
	et.text = "%s · %s" % [nick, view_name(String(pl.view))]


## Smoothed camera of a friend (for watching through their eyes); null when unknown.
func eye_of(c: String):
	if not _p.has(c) or not bool(_p[c].placed):
		return null
	return [_p[c].cam, _p[c].fov]


static func view_name(v: String) -> String:
	match v:
		"base":
			return GS.t("у орудия")
		"fpv":
			return GS.t("пилотирует FPV")
		"walk":
			return GS.t("гуляет по городу")
		"watch":
			return GS.t("смотрит за другом")
		"top":
			return GS.t("над картой")
	return GS.t("выбирает позицию")
