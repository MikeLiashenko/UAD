extends Node3D
## One aerial threat. Behaviour depends on type:
##  scout     — daytime recon drone, loiters and searches for the player's base
##  shahed    — slow kamikaze drone; can miss its target, or lose control when hit, and fall on homes
##  cruise    — fast, hugs the terrain between waypoints, pops up before the strike, can jink
##  ballistic — follows a ballistic arc from far outside the map
## On top of the flight model every threat is a real weapon (`variant`, GS.ENEMIES): a Kalibr or an
## Oniks flies like a cruise missile, a Kinzhal or an S-300 like a ballistic one with its own flight
## time, a KAB glide bomb slides down from high above the border straight onto its target.
## Each threat flies in its own altitude band and slowly changes height during flight.

const Meshes = preload("res://scripts/core/meshes.gd")
const Fx = preload("res://scripts/core/fx.gd")

const B_GRAVITY := 26.0
const DETECT_TIME := 14.0
## Chance that a weapon is thrown off course by jamming and lands away from its target.
const MISS_CHANCE := {"shahed": 0.24, "cruise": 0.18, "ballistic": 0.16}

var game
## Flight model: scout / shahed / cruise / ballistic.
var type := "shahed"
## The actual weapon (a key of GS.ENEMIES): "kalibr", "kab", "kinzhal", "gerbera" …
var variant := "shahed"
var def: Dictionary
var hp := 1.0
var max_hp := 1.0
var vel := Vector3.ZERO
var speed := 40.0
var radius := 4.0
var dead := false
## Damage already on its way from interceptors in flight (keeps the player from double-firing).
var inbound := 0.0
var age := 0.0
var target_pos := Vector3.ZERO
var target_name := ""
var strike_base := false
var waypoints: Array[Vector3] = []
var cruise_alt := -1.0
## Route point: the raid's corridor crosses the player's sector here.
var via := Vector3.ZERO
var has_via := false
## Shahed guidance errors: `missed` = GPS spoofed / EW, `crippled` = damaged and out of control.
var missed := false
var crippled := false
## Which system hit it last (for the morning highlight reel; "net:<code>" = a friend's).
var last_hit_by := ""

## Multiplayer. `net_id` numbers the threat in the host's raid snapshots. On a guest the threat is
## a `puppet`: it does not fly on its own but follows the snapshots — moving on with the last
## known velocity and easing out the error when the next one arrives — and the damage it takes
## is reported to the host, which decides when it goes down.
var net_id := -1
var puppet := false
## Host: whose base a strike "on the base" is aimed at ("" = the host's own).
var net_base_owner := ""
## Host: index of the strike target in map.targets (-1 none, -2 a base).
var net_target := -1
var _net_p := Vector3.ZERO
var _net_v := Vector3.ZERO
var _net_t := 0
var _net_placed := false
## A puppet brought down by our own hit waits this long for the host to confirm the kill.
var _pred_t := 0.0

var model: Node3D
var marker: Label3D
var _spin: Node3D
var _flash := 0.0
var _p0 := Vector3.ZERO
var _v0 := Vector3.ZERO
var _flight := 15.0
var _life := 85.0
var _leaving := false
var _alt_amp := 0.0
var _alt_freq := 0.1
var _alt_phase := 0.0
var _rng := RandomNumberGenerator.new()


func setup(g, t: String, start: Vector3, tgt: Vector3, tname: String, alt := -1.0) -> void:
	game = g
	variant = t if GS.ENEMIES.has(t) else "shahed"
	type = GS.kind_of(variant)
	position = start
	target_pos = tgt
	target_name = tname
	_rng.randomize()
	if alt > 0.0:
		cruise_alt = alt


func _ready() -> void:
	def = GS.ENEMIES[variant]
	hp = float(def.hp)
	max_hp = hp
	speed = float(def.speed) * _rng.randf_range(0.92, 1.08)
	radius = float(def.radius)
	if cruise_alt <= 0.0:
		cruise_alt = _rng.randf_range(float(def.alt_min), float(def.alt_max))
	_alt_amp = cruise_alt * _rng.randf_range(0.08, 0.25)
	_alt_freq = _rng.randf_range(0.03, 0.09)
	_alt_phase = _rng.randf() * TAU
	model = Meshes.enemy_model(variant)
	add_child(model)
	if model.has_meta("spin"):
		_spin = model.get_meta("spin")
	marker = Label3D.new()
	marker.font = GS.font
	marker.font_size = 30
	marker.outline_size = 8
	marker.outline_modulate = Color(0, 0, 0, 0.8)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.pixel_size = 0.0011
	marker.render_priority = 10
	add_child(marker)
	if puppet:
		_update_marker()
		return
	# EW / GPS spoofing: the weapon comes down somewhere near, not on, its target. Missiles are
	# harder to throw off than a Shahed, but when it happens they stray much further.
	if not strike_base and not def.has("mirv") and _rng.randf() < float(MISS_CHANCE.get(type, 0.0)):
		missed = true
		var spread := 170.0 if type == "shahed" else (260.0 if type == "cruise" else 420.0)
		var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(60.0, spread)
		var mx := target_pos.x + off.x
		var mz := target_pos.z + off.y
		target_pos = Vector3(mx, game.map.ground_height(mx, mz), mz)
	match type:
		"ballistic":
			_p0 = position
			var fl: Array = def.get("flight", [15.0, 22.0])
			_flight = _rng.randf_range(float(fl[0]), float(fl[1]))
			_v0 = (target_pos - _p0 + Vector3(0, 0.5 * B_GRAVITY * _flight * _flight, 0)) / _flight
			vel = _v0
		"cruise" when def.get("glide", false):
			# a glide bomb: released far out and high up, it slides down one straight line
			_p0 = position
			_flight = Vector2(target_pos.x - _p0.x, target_pos.z - _p0.z).length() / speed
			vel = (target_pos - _p0) / _flight
			waypoints.append(target_pos)
		"cruise":
			var from := Vector2(position.x, position.z)
			var to := Vector2(via.x, via.z) if has_via else Vector2(target_pos.x, target_pos.z)
			var side := (to - from).orthogonal().normalized()
			var fracs := [0.4] if has_via else [0.35, 0.65]
			for f in fracs:
				var p := from.lerp(to, f) + side * _rng.randf_range(-300.0, 300.0)
				waypoints.append(Vector3(p.x, cruise_alt, p.y))
			if has_via:
				waypoints.append(Vector3(via.x, cruise_alt, via.z))
			waypoints.append(target_pos)
		"scout":
			_pick_scout_waypoint()
		_:
			if has_via:
				waypoints.append(Vector3(via.x, cruise_alt, via.z))
			waypoints.append(target_pos)
	if type != "ballistic" and not def.get("glide", false):
		vel = (waypoints[0] - position).normalized() * speed
		vel.y = 0.0
	_update_marker()


func _process(delta: float) -> void:
	if dead:
		if puppet and _pred_t > 0.0:
			_pred_t -= delta
			if _pred_t <= 0.0:
				# the host never confirmed our kill (someone else's hit decided it): back it comes
				dead = false
				visible = true
		return
	age += delta
	if puppet:
		_net_follow(delta)
	else:
		match type:
			"ballistic":
				_fly_ballistic()
			"cruise" when def.get("glide", false):
				_fly_glide()
			"scout":
				_fly_scout(delta)
			_:
				_fly_direct(delta)
	if dead or not is_inside_tree():
		return
	if _spin:
		_spin.rotate_z(delta * 45.0)
	if vel.length_squared() > 0.01:
		var n := vel.normalized()
		look_at(position + n, Vector3.UP if absf(n.y) < 0.97 else Vector3.FORWARD)
	_flash = maxf(0.0, _flash - delta)
	_update_marker()


func _steer(aim: Vector3, turn: float, delta: float) -> void:
	var cur := vel.normalized()
	var want := (aim - position).normalized()
	var ang := cur.angle_to(want)
	if ang > 0.0001:
		cur = cur.slerp(want, clampf(turn * delta / ang, 0.0, 1.0)).normalized()
	vel = cur * speed
	position += vel * delta


## Desired cruise altitude right now: slow climbs/descents, and never below the rooftops ahead.
func _alt_here() -> float:
	var a := cruise_alt + _alt_amp * sin(age * _alt_freq * TAU + _alt_phase)
	var fwd := Vector3(vel.x, 0, vel.z).normalized() * maxf(speed * 1.3, 40.0)
	var ahead := position + fwd
	var ceil_h: float = maxf(game.map.ceiling(ahead.x, ahead.z), game.map.ceiling(position.x, position.z))
	return maxf(a, ceil_h + 14.0)


func _fly_direct(delta: float) -> void:
	var wp: Vector3 = waypoints[0]
	var final := waypoints.size() == 1
	var hd := Vector2(wp.x - position.x, wp.z - position.z).length()
	var dive := 170.0 if type == "shahed" else 120.0
	var aim := Vector3(wp.x, _alt_here(), wp.z)
	if final and type == "cruise" and hd < 380.0 and hd > dive:
		aim.y = _alt_here() + 60.0 # terminal pop-up before diving onto the target
	if final and (hd < dive or crippled):
		aim = wp
	var turn := 1.0 if type == "shahed" else 1.6 * maxf(1.0, speed / 115.0)
	if crippled:
		turn = 0.6
	_steer(aim, turn, delta)
	if not final and hd < 45.0:
		waypoints.pop_front()
	if final and (position.distance_to(wp) < 7.0 or (hd < 25.0 and position.y <= wp.y + 2.0)):
		game.enemy_impact(self)
	elif position.y <= game.map.ground_height(position.x, position.z):
		game.enemy_impact(self)


func _fly_ballistic() -> void:
	var t := age
	position = _p0 + _v0 * t - Vector3(0, 0.5 * B_GRAVITY * t * t, 0)
	vel = _v0 - Vector3(0, B_GRAVITY * t, 0)
	if t >= _flight or position.y <= game.map.ground_height(position.x, position.z):
		position = target_pos
		game.enemy_impact(self)


## The UMPK wings keep the bomb on a shallow glide that steepens over the target.
func _fly_glide() -> void:
	var u := clampf(age / _flight, 0.0, 1.0)
	var flat := _p0.lerp(target_pos, u)
	var y := lerpf(_p0.y, target_pos.y, pow(u, 1.7))
	var p := Vector3(flat.x, y, flat.z)
	vel = (p - position) / maxf(get_process_delta_time(), 0.001)
	position = p
	if u >= 1.0 or position.y <= game.map.ground_height(position.x, position.z):
		position = target_pos
		game.enemy_impact(self)


func _pick_scout_waypoint() -> void:
	var p: Vector3
	if _leaving:
		var d := Vector3(position.x, 0, position.z).normalized()
		if d == Vector3.ZERO:
			d = Vector3.FORWARD
		p = d * 1400.0
	elif _rng.randf() < 0.4:
		p = GS.base_pos + Vector3(_rng.randf_range(-350, 350), 0, _rng.randf_range(-350, 350))
	else:
		p = Vector3(_rng.randf_range(-850, 850), 0, _rng.randf_range(-850, 850))
	waypoints.clear()
	waypoints.append(Vector3(p.x, cruise_alt, p.z))


func _fly_scout(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 and not _leaving:
		_leaving = true
		_pick_scout_waypoint()
	var wp: Vector3 = waypoints[0]
	_steer(Vector3(wp.x, _alt_here(), wp.z), 0.7, delta)
	if Vector2(wp.x - position.x, wp.z - position.z).length() < 40.0:
		_pick_scout_waypoint()
	if _leaving and Vector2(position.x, position.z).length() > 1300.0:
		game.enemy_left(self)
		return
	if not GS.base_found:
		var hd := Vector2(GS.base_pos.x - position.x, GS.base_pos.z - position.z).length()
		if hd < 320.0:
			GS.detection += delta * GS.detect_multiplier()
			if GS.detection >= DETECT_TIME:
				game.base_detected(self)
				_leaving = true
				_pick_scout_waypoint()


## A snapshot entry from the host: [variant, x, y, z, vx, vy, vz, hp fraction, flags, target]
## taken at server time `t`. `unconfirmed` is our own damage the host has not counted in yet.
func net_update(a: Array, t: int, unconfirmed: float) -> void:
	_net_p = Vector3(float(a[1]), float(a[2]), float(a[3]))
	_net_v = Vector3(float(a[4]), float(a[5]), float(a[6]))
	_net_t = t
	if _net_placed and not dead:
		var drift := position.distance_to(_predicted())
		game.net_err_sum += drift
		game.net_err_n += 1
		game.net_err_max = maxf(game.net_err_max, drift)
	var flags := int(a[8])
	if not dead:
		hp = maxf(max_hp * float(a[7]) - unconfirmed, 0.001)
	strike_base = flags & 2 != 0
	if flags & 1 and not crippled:
		crippled = true
		_crippled_fx()
	if not _net_placed:
		_net_placed = true
		position = _predicted()
		vel = _net_v


## Where the host's threat is now: the last snapshot carried on by its velocity (and gravity for
## a ballistic body) for as long as the snapshot is old.
func _predicted() -> Vector3:
	var dt := clampf(float(Net.server_now() - _net_t) / 1000.0, 0.0, 1.5)
	var p := _net_p + _net_v * dt
	if type == "ballistic":
		p.y -= 0.5 * B_GRAVITY * dt * dt
	return p


func _net_follow(delta: float) -> void:
	var dt := clampf(float(Net.server_now() - _net_t) / 1000.0, 0.0, 1.5)
	var v := _net_v
	if type == "ballistic":
		v.y -= B_GRAVITY * dt
	# dead reckoning: move on with the velocity, then ease out whatever error is left
	position += v * delta
	var err := _predicted() - position
	if err.length() > 120.0:
		position += err
	else:
		position += err * (1.0 - exp(-delta * 5.0))
	vel = v


## Cruise missiles may jink when an interceptor is launched at them.
func evade() -> void:
	if puppet or type != "cruise" or def.get("glide", false) or waypoints.size() < 1 or _rng.randf() > 0.5:
		return
	var fwd := Vector3(vel.x, 0, vel.z).normalized()
	var side := Vector3(-fwd.z, 0, fwd.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var j := position + fwd * 260.0 + side * 180.0
	waypoints.push_front(Vector3(j.x, cruise_alt + _rng.randf_range(-15.0, 40.0), j.z))


## `by` is the id of the system that landed the hit — the nightly highlight reel credits it.
func take_damage(amount: float, by := "") -> void:
	if dead or amount <= 0.0:
		return
	if by != "":
		last_hit_by = by
	hp -= amount
	_flash = 0.12
	if puppet:
		# the host decides; we only show what our hit probably did
		game.net_hit(self, amount)
		if hp <= 0.0:
			dead = true
			_pred_t = 3.0
			game.net_predicted_kill(self)
		return
	if hp <= 0.0:
		dead = true
		game.enemy_destroyed(self)
	elif type == "shahed" and not crippled and hp < max_hp * 0.6 and _rng.randf() < 0.35:
		_lose_control()


## A damaged Shahed loses its guidance and glides down wherever it happens to be heading.
func _lose_control() -> void:
	crippled = true
	strike_base = false
	var fwd := Vector3(vel.x, 0, vel.z).normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var p := position + fwd * _rng.randf_range(90.0, 240.0) + side * _rng.randf_range(-60.0, 60.0)
	target_pos = Vector3(p.x, game.map.ground_height(p.x, p.z), p.z)
	waypoints.clear()
	waypoints.append(target_pos)
	_crippled_fx()
	game.on_enemy_crippled(self)


## Black smoke trailing from a Shahed that lost its guidance.
func _crippled_fx() -> void:
	target_name = GS.t("потерял управление")
	var smoke := Fx.exhaust(Color(0.5, 0.2, 0.05), 24, 1.2, 2.0)
	smoke.material_override = Fx.smoke_mat()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.5, 0.15, 0.8))
	g.add_point(0.2, Color(0.25, 0.22, 0.22, 0.6))
	g.set_color(g.get_point_count() - 1, Color(0.15, 0.15, 0.15, 0.0))
	smoke.color_ramp = g
	add_child(smoke)


func _update_marker() -> void:
	marker.visible = bool(GS.settings.markers) and not game.hide_markers()
	if not marker.visible:
		return
	var c: Color = def.color
	var abbr := String(def.abbr)
	var txt := "◆ " + abbr
	if game.locked == self:
		txt = "[ ◆ " + abbr + " ]"
		c = Color(1.0, 0.3, 0.3)
	elif game.hovered == self:
		txt = "[ " + abbr + " ]"
		c = Color(1, 1, 1)
	if crippled:
		txt += " !"
		c = Color(1.0, 0.5, 0.2)
	if _flash > 0.0:
		c = Color(1, 1, 1)
	if hp < max_hp:
		txt += "  %d%%" % int(100.0 * hp / max_hp)
	marker.text = txt
	marker.modulate = c
