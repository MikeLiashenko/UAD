extends Node3D
## Interceptor drone: a cheap quadcopter that rams its target. Launched by the "drone" rack,
## it hunts on its own, loiters when the sky is clear and flies home when the battery runs low
## (a recovered drone goes back into the magazine). The player can take the controls in the
## FPV view at any moment — see scripts/game/fpv_view.gd.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Bullet = preload("res://scripts/game/bullet.gd")

const ACCEL := 90.0
const HIT_MARGIN := 3.0
const RTB_BATTERY := 12.0
const LOITER_ALT := 120.0
## The swarm works over its own sector: a drone dragged further than this gives up the chase.
const PATROL_RADIUS := 1700.0
## Clearance kept over roofs and terrain on autopilot (dropped for the terminal dive).
const CLEARANCE := 12.0
## Range at which the autopilot stops avoiding obstacles and goes straight for the target.
const TERMINAL := 60.0
## Soft ceiling: above this the drone stops climbing and settles back down (~2.1 km on the HUD).
const MAX_ALT := 420.0

var game
var target
var weapon_id := "drone"
var def: Dictionary
var vel := Vector3.FORWARD
var speed := 30.0
var max_speed := 175.0
var turn := 2.8
var battery := 46.0
var fpv := false
## Serial number inside the sortie — what the FPV console and the event log call this drone.
var serial := 1
## Player input while in FPV: -1..1 steering and 0..1.6 throttle.
var in_yaw := 0.0
var in_pitch := 0.0
var in_throttle := 1.0

var state := "chase"
var _loiter := 0.0
var _loiter_at := Vector3.ZERO
var _rotors: Array[Node3D] = []
var _committed := 0.0
## Climb-out seconds right after launch: the drone gets above the rooftops before it hunts.
var _climb := 1.1
var _done := false
var _model: Node3D


func _ready() -> void:
	def = GS.WEAPONS[weapon_id]
	max_speed = float(def.speed)
	turn = float(def.turn)
	battery = float(def.get("battery", 46.0))
	_model = Meshes.fpv_drone()
	_model.scale = Vector3.ONE * 2.2
	add_child(_model)
	var rr: Array = _model.get_meta("rotors", [])
	for r in rr:
		_rotors.append(r as Node3D)
	_commit()
	_orient()


func cam_mount() -> Node3D:
	return _model.get_meta("cam") as Node3D


## Battery left, 0..1 — the FPV console's fuel gauge.
func charge() -> float:
	return clampf(battery / maxf(float(def.get("battery", 46.0)), 1.0), 0.0, 1.0)


func state_text() -> String:
	if fpv:
		return GS.t("РУЧНОЕ")
	match state:
		"chase":
			return GS.t("ПЕРЕХВАТ")
		"loiter":
			return GS.t("БАРРАЖ")
	return GS.t("НА БАЗУ")


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and not target.dead


func _commit() -> void:
	if _target_ok():
		_committed = float(def.damage) * GS.eff(weapon_id, target)
		target.inbound += _committed


func _release() -> void:
	if _target_ok() and _committed > 0.0:
		target.inbound = maxf(0.0, target.inbound - _committed)
	_committed = 0.0


## Re-assigns the drone to the nearest engageable threat; returns false if the sky is clear.
## Like the smart auto-fire, the swarm prefers a target whose wreckage would come down
## somewhere harmless — but a threat over the rooftops is still worse than the roofs.
func retarget() -> bool:
	var best = null
	var best_d := INF
	var risky = null
	var risky_d := INF
	for e in game.enemies:
		if e.dead or GS.eff(weapon_id, e) <= 0.0 or e.inbound >= e.hp:
			continue
		if e.position.distance_to(GS.base_pos) > PATROL_RADIUS:
			continue
		var d: float = position.distance_to(e.position)
		if not bool(game.predict_debris(e).safe):
			if d < risky_d:
				risky_d = d
				risky = e
			continue
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		best = risky
	if best == null:
		return false
	_release()
	target = best
	_commit()
	state = "chase"
	return true


func take_control() -> void:
	fpv = true
	in_throttle = 1.0


func release_control() -> void:
	fpv = false
	in_yaw = 0.0
	in_pitch = 0.0
	if not _target_ok():
		retarget()


## "R" on the FPV console (and the morning recall): break off and land back at the rack.
func order_home() -> void:
	_release()
	target = null
	state = "rtb"


func _orient() -> void:
	var n := vel.normalized()
	look_at(position + n, Vector3.UP if absf(n.y) < 0.97 else Vector3.FORWARD)
	# bank into the turn, like a real quad leaning towards its direction of travel
	_model.rotation.z = lerpf(_model.rotation.z, clampf(-in_yaw, -1.0, 1.0) * 0.5, 0.15)


## Keeps the autopilot off the roofs: climb while something ahead is higher than we are.
func _avoid(want: Vector3) -> Vector3:
	if position.y > MAX_ALT:
		return (want + Vector3.DOWN * 0.7).normalized()
	var ahead := position + want * 45.0
	var obst: float = maxf(game.map.ground_height(ahead.x, ahead.z), game.map.ceiling(ahead.x, ahead.z))
	obst = maxf(obst, game.map.ceiling(position.x, position.z))
	if position.y >= obst + CLEARANCE:
		return want
	var climb: float = clampf((obst + CLEARANCE - position.y) / 40.0, 0.0, 1.0)
	return (want + Vector3.UP * climb * 1.6).normalized()


func _process(delta: float) -> void:
	if _done:
		return
	battery -= delta
	for r in _rotors:
		r.rotate_y(delta * 70.0)
	var dir := vel.normalized()
	var want := dir
	var want_speed := max_speed
	if fpv:
		# The player flies it: steering input turns the drone, throttle sets the speed.
		var up := Vector3.UP
		var right := dir.cross(up).normalized()
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT
		want = (dir + right * in_yaw * 1.4 + up * in_pitch * 1.2).normalized()
		if absf(in_pitch) < 0.05:
			# stabilised flight: with the stick centred the quad levels off and keeps clear of the
			# roofs; push the stick down and it dives where you tell it to
			want = Vector3(want.x, want.y * exp(-delta * 1.6), want.z).normalized()
			want = _avoid(want)
		want_speed = max_speed * clampf(in_throttle, 0.25, 1.35)
	else:
		match state:
			"chase":
				if not _target_ok() and not retarget():
					state = "loiter"
					_loiter = 10.0
					_loiter_at = position
				if _target_ok():
					want = (Bullet.lead(position, target.position, target.vel, maxf(speed, 40.0)) - position).normalized()
					if position.distance_to(target.position) > TERMINAL:
						want = _avoid(want)
					if position.distance_to(GS.base_pos) > PATROL_RADIUS:
						order_home()
			"loiter":
				_loiter -= delta
				if retarget():
					pass
				elif _loiter <= 0.0 or battery < RTB_BATTERY:
					state = "rtb"
				else:
					var c := _loiter_at + Vector3(0, LOITER_ALT - _loiter_at.y, 0)
					var ang := float(Time.get_ticks_msec()) * 0.0006
					want = _avoid((c + Vector3(cos(ang), 0, sin(ang)) * 90.0 - position).normalized())
					want_speed = max_speed * 0.45
			"rtb":
				var home: Vector3 = GS.base_pos + Vector3(0, 26, 0)
				var d_home: float = position.distance_to(home)
				want = (home - position).normalized()
				if d_home > 40.0:
					want = _avoid(want)
				want_speed = max_speed * (0.35 if d_home < 60.0 else 0.8)
				if d_home < 18.0:
					_recover()
					return
		if state != "rtb" and battery < RTB_BATTERY and not _target_ok():
			state = "rtb"
	if _climb > 0.0:
		# climb-out: everything the rack sends up first gets some air under it
		_climb -= delta
		want = (want + Vector3.UP * 1.1).normalized()
	var ang := dir.angle_to(want)
	if ang > 0.0001:
		dir = dir.slerp(want, clampf(turn * delta / ang, 0.0, 1.0)).normalized()
	speed = move_toward(speed, want_speed, ACCEL * delta)
	vel = dir * speed
	var p0 := position
	position += vel * delta
	_orient()
	if _target_ok():
		var r: float = target.radius + HIT_MARGIN
		if Bullet.seg_dist(p0, position, target.position) < r:
			_detonate(true)
			return
	# Real collision: ground_height() is the roof of the building actually under the drone.
	# ceiling() is only the conservative 3x3-cell maximum used by the avoidance planner.
	if position.y <= game.map.ground_height(position.x, position.z) + 0.6:
		_detonate(false)
		return
	if battery <= 0.0:
		_detonate(false)


func _detonate(hit: bool) -> void:
	if _done:
		return
	_done = true
	var was = target
	_release()
	if hit and was != null and is_instance_valid(was) and not was.dead:
		var eff: float = GS.eff(weapon_id, was)
		GS.stats.rams = int(GS.stats.get("rams", 0)) + 1
		was.take_damage(float(def.damage) * eff, weapon_id)
		if fpv:
			game.fpv_hit(was)
		elif not was.dead:
			game.hud.log_event(GS.t("Дрон #%d таранил цель, но она осталась в воздухе") % serial, Color(1.0, 0.8, 0.4))
	elif not hit:
		var why: String = GS.t("разряжен аккумулятор") if battery <= 0.0 else GS.t("столкновение")
		game.hud.log_event(GS.t("Дрон #%d потерян: %s") % [serial, why], Color(1.0, 0.55, 0.3))
	Fx.explosion(game.fx_root, position, 0.45, Color(1.0, 0.8, 0.4))
	game.play_3d("boom_small", position, -6.0)
	game.on_drone_gone(self)
	queue_free()


## Landed back at the base with the battery still alive: straight back into the magazine.
func _recover() -> void:
	_done = true
	_release()
	GS.ammo["drone"] = int(GS.ammo.get("drone", 0)) + 1
	GS.state_changed.emit()
	game.hud.log_event(GS.t("Дрон #%d вернулся на базу — боекомплект пополнен") % serial, Color(0.5, 1.0, 0.7))
	game.play_3d("prop", position, -12.0)
	game.on_drone_gone(self)
	queue_free()
