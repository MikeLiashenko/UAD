extends Node3D
## Moving city life: boats along the water lanes, metro trains over the metro bridges, and
## passenger trains running along every railway of the city (up the ramps onto the rail bridges).

const Meshes = preload("res://scripts/core/meshes.gd")
const Fx = preload("res://scripts/core/fx.gd")

const CAR_LEN := 15.5
const TRAIN_SPEED := 24.0

var map
var _boats: Array = []
var _metros: Array = []
var _trains: Array = []
## Boat lanes with their cumulative lengths and the lateral room at every point.
var _lanes: Array = []
var _t := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_build_lanes()
	if not _lanes.is_empty():
		for i in 8:
			var lane: Dictionary = _lanes[i % _lanes.size()]
			var b := Meshes.boat()
			add_child(b)
			_boats.append({"n": b, "lane": lane, "s": rng.randf() * float(lane.total), "v": rng.randf_range(5.0, 10.0) * (1.0 if i % 2 == 0 else -1.0), "off": rng.randf_range(0.3, 0.55) * (1.0 if i % 2 == 0 else -1.0)})
	for bd in map.built_bridges:
		if String(bd.style) == "metro":
			var m := Meshes.metro_train(5)
			add_child(m)
			_metros.append({"n": m, "b": bd, "phase": rng.randf() * 30.0})
	for tr in map.tracks:
		var total: float = (tr.len as PackedFloat32Array)[(tr.len as PackedFloat32Array).size() - 1]
		if total < 200.0:
			continue
		for k in int(tr.trains):
			var cars := []
			var body := Fx.solid([Color(0.2, 0.45, 0.3), Color(0.25, 0.3, 0.55), Color(0.55, 0.12, 0.1)][k % 3], 0.5, 0.2)
			var win := Fx.glow(Color(1.0, 0.92, 0.75), 1.8)
			for c in int(tr.cars):
				var car := Node3D.new()
				Meshes.box(car, Vector3(3.1, 3.4, 14.8), Vector3(0, 1.8, 0), body)
				Meshes.box(car, Vector3(3.15, 0.9, 12.0), Vector3(0, 2.3, 0), win)
				if c == 0:
					var head := Fx.glare(Color(1, 0.95, 0.8), 2.2, 1.3, 0.003, 0.0)
					head.position = Vector3(0, 1.5, -7.6)
					car.add_child(head)
				add_child(car)
				cars.append(car)
			_trains.append({"cars": cars, "tr": tr, "total": total, "s": rng.randf() * total, "dir": 1.0 if k % 2 == 0 else -1.0, "wait": 0.0})


## Lanes from the city file, or the centre lines of the wide rivers.
func _build_lanes() -> void:
	var src: Array = map.city.boat_lanes
	if src.is_empty():
		for r in map.city.rivers:
			if float((r.w as PackedFloat32Array)[0]) >= 34.0:
				src.append(r.pts)
	for pts in src:
		var p: PackedVector2Array = pts
		if p.size() < 2:
			continue
		var lens := PackedFloat32Array()
		var room := PackedFloat32Array()
		var acc := 0.0
		for i in p.size():
			if i > 0:
				acc += p[i - 1].distance_to(p[i])
			lens.append(acc)
			# how far from the lane a boat may go before it hits the bank
			var r := 4.0
			while r < 70.0 and map.water_dist(p[i].x, p[i].y) < -6.0 and _wet_side(p, i, r):
				r += 4.0
			room.append(r)
		_lanes.append({"pts": p, "len": lens, "room": room, "total": acc})


func _wet_side(p: PackedVector2Array, i: int, r: float) -> bool:
	var d := (p[mini(i + 1, p.size() - 1)] - p[maxi(i - 1, 0)]).normalized()
	var n := Vector2(-d.y, d.x)
	return map.water_dist(p[i].x + n.x * r, p[i].y + n.y * r) < -5.0 and map.water_dist(p[i].x - n.x * r, p[i].y - n.y * r) < -5.0


## Point, direction and lateral room at distance s along a lane.
func _lane_at(lane: Dictionary, s: float) -> Array:
	var lens: PackedFloat32Array = lane.len
	var pts: PackedVector2Array = lane.pts
	var i := lens.bsearch(s) - 1
	i = clampi(i, 0, pts.size() - 2)
	var t := clampf((s - lens[i]) / maxf(lens[i + 1] - lens[i], 0.001), 0.0, 1.0)
	var room := lerpf((lane.room as PackedFloat32Array)[i], (lane.room as PackedFloat32Array)[i + 1], t)
	return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized(), room]


func _track_at(tr: Dictionary, s: float) -> Array:
	var lens: PackedFloat32Array = tr.len
	var pts: PackedVector3Array = tr.pts
	var i := clampi(lens.bsearch(s) - 1, 0, pts.size() - 2)
	var t := clampf((s - lens[i]) / maxf(lens[i + 1] - lens[i], 0.001), 0.0, 1.0)
	return [pts[i].lerp(pts[i + 1], t), pts[i + 1] - pts[i]]


func _process(delta: float) -> void:
	_t += delta
	for b in _boats:
		var lane: Dictionary = b.lane
		var total: float = lane.total
		b.s = fposmod(float(b.s) + float(b.v) * delta, total)
		var la := _lane_at(lane, b.s)
		var p: Vector2 = la[0]
		var d: Vector2 = la[1] * signf(b.v)
		var n := Vector2(-la[1].y, la[1].x)
		var pos: Vector2 = p + n * float(b.off) * float(la[2])
		var node: Node3D = b.n
		node.visible = map.water_dist(pos.x, pos.y) < -2.0
		node.position = Vector3(pos.x, 0.4, pos.y)
		node.rotation.y = atan2(-d.x, -d.y)
	# metro: 30 s cycle, the crossing takes ~16 s
	for m in _metros:
		var bd: Dictionary = m.b
		var a: Vector2 = bd.a
		var bb: Vector2 = bd.b
		var dir := (bb - a).normalized()
		var span := a.distance_to(bb) + 160.0
		var tt := _t + float(m.phase)
		var mt := fmod(tt, 30.0) / 16.0
		var node: Node3D = m.n
		node.visible = mt <= 1.0
		if node.visible:
			var fwd := 1.0 if int(tt / 30.0) % 2 == 0 else -1.0
			var start := (a - dir * 80.0) if fwd > 0.0 else (bb + dir * 80.0)
			var p := start + dir * fwd * mt * span
			node.position = Vector3(p.x, float(bd.deck) + 6.7, p.y)
			node.rotation.y = atan2(-dir.x * fwd, -dir.y * fwd)
	# trains run end to end along their railway, pause, and come back
	for tr in _trains:
		var total: float = tr.total
		if float(tr.wait) > 0.0:
			tr.wait = float(tr.wait) - delta
		else:
			tr.s = float(tr.s) + TRAIN_SPEED * delta * float(tr.dir)
			if tr.s > total or tr.s < 0.0:
				tr.s = clampf(tr.s, 0.0, total)
				tr.dir = -float(tr.dir)
				tr.wait = 6.0
		var cars: Array = tr.cars
		for i in cars.size():
			var s := clampf(float(tr.s) - float(tr.dir) * i * CAR_LEN, 0.0, total)
			var at := _track_at(tr.tr, s)
			var p: Vector3 = at[0]
			var fd: Vector3 = at[1] * float(tr.dir)
			var car: Node3D = cars[i]
			car.position = p + Vector3(0, 0.2, 0)
			if Vector2(fd.x, fd.z).length() > 0.01:
				car.rotation = Vector3(atan2(fd.y, Vector2(fd.x, fd.z).length()), atan2(-fd.x, -fd.z), 0)
