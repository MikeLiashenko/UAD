extends Node3D
## City fire and rescue service. Every hit leaves a live fire (scripts/game/fire.gd); the
## crews roll out of the station next to the base, drive to the nearest blaze, put it out and
## then rebuild what collapsed — the city slowly comes back instead of staying a ruin.
## Extra crews are bought in the shop (GS.crews).

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Fire = preload("res://scripts/game/fire.gd")

## Crews included with the city; the shop adds more on top.
const BASE_CREWS := 3
const DRIVE_SPEED := 34.0
const WORK_RANGE := 16.0
## Share of a blaze one crew knocks down per second.
const SUPPRESS_RATE := 0.22
## A crew that cannot reach its fire (across the river, behind a block) gives up after this long.
const DRIVE_TIMEOUT := 60.0
## Seconds to rebuild one collapsed building.
const REPAIR_TIME := 20.0
## How much of the city bar one rebuilt building brings back.
const REPAIR_CITY := 0.4

var game
var depot := Vector3.ZERO
var fires: Array = []
var crews: Array = []
var repairs: Array = []
## Deck centres of the Dnipro bridges — the crews route over them instead of swimming.
var _bridges: Array = []

var _t := 0.0
var _depot_node: Node3D


func _ready() -> void:
	depot = GS.base_pos + Vector3(-26, 0, 2)
	_depot_node = Meshes.fire_depot()
	_depot_node.position = depot
	_depot_node.rotation.y = PI * 0.5
	add_child(_depot_node)
	_bridges = game.map.bridge_points()
	_sync_crews()
	GS.state_changed.connect(_sync_crews)


func crew_limit() -> int:
	return BASE_CREWS + int(GS.crews)


## Builds (or parks) as many trucks as the city pays for.
func _sync_crews() -> void:
	while crews.size() < crew_limit():
		var i := crews.size()
		var truck := Meshes.fire_truck()
		var home: Vector3 = depot + Vector3(-9.0 + i * 6.0, 0, 13.0)
		truck.position = home
		truck.rotation.y = PI
		add_child(truck)
		crews.append({"node": truck, "home": home, "state": "idle", "fire": null, "t": 0.0, "idle_t": 0.0,
			"via": Vector3.ZERO, "has_via": false, "best": INF, "stuck": 0.0, "spray": null})


func active_fires() -> int:
	return fires.size()


func free_crews() -> int:
	var n := 0
	for c in crews:
		if String(c.state) == "idle":
			n += 1
	return n


## A hit, a burning wreck or a piece of debris set something alight.
func start_fire(pos: Vector3, bi: int, size := 1.0) -> void:
	if bi >= 0:
		for f in fires:
			if f.bi == bi:
				f.intensity = minf(1.0, f.intensity + 0.35)
				return
	var f := Fire.new()
	f.game = game
	f.bi = bi
	f.size = size
	f.position = pos
	game.fx_root.add_child(f)
	fires.append(f)
	game.hud.refresh()


## Reported by the fire itself once it is out (by water, or because it burned through).
func on_fire_out(f, by_crew: bool) -> void:
	fires.erase(f)
	for c in crews:
		if c.fire == f:
			c.fire = null
			# free again: the dispatcher sends this crew straight to the next blaze
			c.state = "idle"
			c.t = 0.0
			c.idle_t = 0.0
			_spray(c, false)
	if by_crew:
		GS.stats.fires_out = int(GS.stats.get("fires_out", 0)) + 1
		GS.city = minf(100.0, GS.city + 0.1)
		game.hud.log_event(GS.t("Пожар потушен: %s") % _where(f.bi), Color(0.5, 0.9, 1.0))
	else:
		game.hud.log_event(GS.t("Пожар выгорел сам: %s") % _where(f.bi), Color(1.0, 0.6, 0.3))
	if f.bi >= 0:
		queue_repair(f.bi)
	game.hud.refresh()


func _where(bi: int) -> String:
	return game.map.building_name(bi) if bi >= 0 else GS.t("открытая местность")


## Puts a building in line for the repair crews (collapsed floors and soot).
func queue_repair(bi: int) -> void:
	# a guest's city is rebuilt by the host's crews: the buildings arrive with the host's map
	if bi < 0 or Net.role == "guest":
		return
	for r in repairs:
		if int(r.bi) == bi:
			return
	if game.map.crush_of(bi) <= 0.0 and game.map.fp_damaged[bi] == 0:
		return
	repairs.append({"bi": bi, "crush": maxf(game.map.crush_of(bi), 0.01), "t": 0.0})


func _burning(bi: int) -> bool:
	for f in fires:
		if f.bi == bi:
			return true
	return false


func _process(delta: float) -> void:
	_t += delta
	_dispatch()
	for c in crews:
		_drive(c, delta)
	_repair(delta)


## Idle crews take the nearest fire nobody is working on yet.
func _dispatch() -> void:
	for c in crews:
		if String(c.state) != "idle":
			continue
		var best = null
		var best_d := INF
		for f in fires:
			if f.crew != null or f.intensity <= 0.0:
				continue
			var d: float = Vector2(f.position.x - c.node.position.x, f.position.z - c.node.position.z).length()
			if d < best_d:
				best_d = d
				best = f
		if best == null:
			return
		best.crew = c
		c.fire = best
		c.state = "drive"
		c.t = 0.0
		c.idle_t = 0.0
		_set_route(c, best.position)
		game.play_3d("alert", c.node.position, -22.0, 2.0)


## Is there water between these two points? (Sampled along the straight line.)
func _crosses_water(a: Vector3, b: Vector3) -> bool:
	var n := maxi(4, int(a.distance_to(b) / 25.0))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if game.map.water_dist(p.x, p.z) < 0.0:
			return true
	return false


## The bridge that makes the shortest detour from `a` to `b`, or Vector3.ZERO if none helps.
func _route_via(a: Vector3, b: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_len := INF
	for p in _bridges:
		var bp: Vector3 = p
		var l: float = a.distance_to(bp) + bp.distance_to(b)
		if l < best_len:
			best_len = l
			best = bp
	return best


func _set_route(c: Dictionary, goal: Vector3) -> void:
	c.has_via = false
	if _crosses_water(c.node.position, goal):
		var via := _route_via(c.node.position, goal)
		if via != Vector3.ZERO:
			c.via = via
			c.has_via = true
	c.best = INF
	c.stuck = 0.0


## A truck can drive down a street or over a bridge deck, but not through a block or the river.
func _passable(p: Vector3) -> bool:
	var bi: int = game.map.building_at(p.x, p.z)
	if bi >= 0:
		return game.map.is_bridge(bi)
	return game.map.water_dist(p.x, p.z) > 0.0


## Straight-line driving with a simple "try to swerve around the block" avoidance.
func _steer(from: Vector3, want: Vector3) -> Vector3:
	for a in [0.0, 0.45, -0.45, 0.95, -0.95, 1.6, -1.6]:
		var d := want.rotated(Vector3.UP, a)
		if _passable(from + d * 26.0):
			return d
	return want


func _drive(c: Dictionary, delta: float) -> void:
	var truck: Node3D = c.node
	for b in truck.get_meta("beacons", []):
		(b as Node3D).visible = String(c.state) != "idle" and int(_t * 6.0) % 2 == 0
	match String(c.state):
		"idle":
			if Vector2(c.home.x - truck.position.x, c.home.z - truck.position.z).length() > 20.0:
				# parked out in the city with nothing to do: head back to the station
				c.idle_t = float(c.idle_t) + delta
				if float(c.idle_t) > 5.0:
					_go_home(c)
			return
		"drive":
			var f = c.fire
			if f == null or not is_instance_valid(f):
				_go_home(c)
				return
			c.t = float(c.t) + delta
			if _advance(c, f.position, delta) <= WORK_RANGE:
				c.state = "work"
				_spray(c, true)
				return
			if float(c.t) > DRIVE_TIMEOUT or float(c.stuck) > 12.0:
				# no way through: back to the station, the fire has to burn itself out
				game.hud.log_event(GS.t("Расчёт не может подъехать: %s") % _where(f.bi), Color(1.0, 0.6, 0.3))
				f.crew = null
				c.fire = null
				_go_home(c)
		"work":
			var fw = c.fire
			if fw == null or not is_instance_valid(fw):
				_spray(c, false)
				_go_home(c)
				return
			var nozzle: Node3D = truck.get_meta("nozzle")
			nozzle.look_at(fw.global_position + Vector3(0, 2, 0), Vector3.UP)
			fw.suppress(delta * SUPPRESS_RATE)
		"return":
			if _advance(c, c.home, delta) < 4.0:
				c.state = "idle"
				truck.rotation.y = PI


func _go_home(c: Dictionary) -> void:
	_spray(c, false)
	c.state = "return"
	c.t = 0.0
	c.idle_t = 0.0
	_set_route(c, c.home)


## Drives one step towards `goal` (over a bridge when the river is in the way) and returns the
## flat distance still to go. Tracks whether the crew is actually making progress.
func _advance(c: Dictionary, goal: Vector3, delta: float) -> float:
	var truck: Node3D = c.node
	var aim := Vector3(goal.x, 0.0, goal.z)
	var flat := Vector2(aim.x - truck.position.x, aim.z - truck.position.z).length()
	var left := flat
	if bool(c.has_via):
		var via: Vector3 = c.via
		var dv := Vector2(via.x - truck.position.x, via.z - truck.position.z).length()
		if dv < 30.0:
			c.has_via = false
			c.best = INF
		else:
			aim = Vector3(via.x, 0.0, via.z)
			flat = dv
	if flat < float(c.best) - 4.0:
		c.best = flat
		c.stuck = 0.0
	else:
		c.stuck = float(c.stuck) + delta
	_move(truck, _steer(truck.position, (aim - truck.position).normalized()), delta)
	return left


func _move(truck: Node3D, dir: Vector3, delta: float) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d.length_squared() < 0.01:
		return
	truck.position += d * DRIVE_SPEED * delta
	# rides up onto the deck while crossing a bridge, back down to street level after it
	var bi: int = game.map.building_at(truck.position.x, truck.position.z)
	var deck: float = game.map.fp_center[bi].y if bi >= 0 and game.map.is_bridge(bi) else 0.0
	truck.position.y = move_toward(truck.position.y, deck, delta * 14.0)
	var want := atan2(-d.x, -d.z)
	truck.rotation.y = lerp_angle(truck.rotation.y, want, clampf(delta * 3.0, 0.0, 1.0))


## Water jet from the monitor on the roof while the crew works.
func _spray(c: Dictionary, on: bool) -> void:
	if on and c.spray == null:
		var jet := Fx.exhaust(Color(0.7, 0.85, 1.0), 40, 1.1, 1.2)
		jet.material_override = Fx.smoke_mat()
		jet.local_coords = false
		jet.spread = 6.0
		jet.initial_velocity_min = 26.0
		jet.initial_velocity_max = 34.0
		jet.gravity = Vector3(0, -9.0, 0)
		jet.emitting = true
		(c.node.get_meta("nozzle") as Node3D).add_child(jet)
		c.spray = jet
	elif not on and c.spray != null:
		(c.spray as CPUParticles3D).emitting = false
		var j = c.spray
		get_tree().create_timer(1.5, false).timeout.connect(func() -> void:
			if is_instance_valid(j):
				j.queue_free())
		c.spray = null


## Reconstruction: collapsed floors grow back and the soot is washed off. As many sites at
## once as there are crews — more crews rebuild the city faster.
func _repair(delta: float) -> void:
	var active := 0
	for r in repairs.duplicate():
		if active >= crew_limit():
			break
		var bi := int(r.bi)
		if _burning(bi):
			continue
		active += 1
		var rate: float = maxf(float(r.crush), 0.01) / REPAIR_TIME
		if game.map.repair_building(bi, rate * delta):
			repairs.erase(r)
			GS.city = minf(100.0, GS.city + REPAIR_CITY)
			GS.stats.rebuilt = int(GS.stats.get("rebuilt", 0)) + 1
			GS.state_changed.emit()
			var p: Vector3 = game.map.fp_center[bi]
			var dust := Fx.exhaust(Color(0.75, 0.72, 0.68), 24, 2.2, 2.2)
			dust.material_override = Fx.smoke_mat()
			dust.one_shot = true
			dust.explosiveness = 0.8
			dust.spread = 50.0
			dust.position = Vector3(p.x, p.y, p.z)
			dust.emitting = true
			game.fx_root.add_child(dust)
			get_tree().create_timer(4.0, false).timeout.connect(dust.queue_free)
			game.hud.log_event(GS.t("Восстановлено: %s") % game.map.building_name(bi), Color(0.5, 1.0, 0.7))


## Morning: the service catches up on everything that is still standing wrecked.
func sweep_damaged() -> void:
	for i in game.map.fp_crush.size():
		if game.map.fp_crush[i] > 0.0:
			queue_repair(i)
