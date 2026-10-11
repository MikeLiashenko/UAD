extends Node3D
## Surface-to-air interceptor with lead-pursuit guidance and a proximity fuse.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Bullet = preload("res://scripts/game/bullet.gd")
const Trail = preload("res://scripts/game/trail.gd")

var game
var target
var weapon_id := "iris"
var def: Dictionary
var vel := Vector3.UP
var speed := 60.0
var max_speed := 300.0
var turn := 3.0
var life := 14.0
var boost := 0.35

var _trail: CPUParticles3D
var _done := false
var _committed := 0.0
var _age := 0.0
## A friend's missile drawn on our screen (multiplayer): flies at the same threat, deals no damage.
var cosmetic := false


func _ready() -> void:
	def = GS.WEAPONS[weapon_id]
	# the air picture runs GS.TEMPO times faster than life: speed, turn rate and the burn of the motor
	max_speed = GS.shot_speed(weapon_id)
	turn = float(def.turn) * GS.TEMPO
	boost /= GS.TEMPO
	# enough fuel and battery to fly out to the edge of its zone, and a little more
	life = float(def.range) / max_speed * 1.7 + 2.0
	add_child(Meshes.interceptor(weapon_id in ["patriot", "s300", "s400", "s500"]))
	_trail = CPUParticles3D.new()
	_trail.mesh = Fx.sphere(1.0, 6)
	_trail.material_override = Fx.smoke_mat()
	_trail.local_coords = false
	_trail.amount = 40
	_trail.lifetime = 1.4
	_trail.direction = Vector3.BACK
	_trail.spread = 8.0
	_trail.initial_velocity_min = 1.0
	_trail.initial_velocity_max = 3.0
	_trail.gravity = Vector3(0, 0.8, 0)
	_trail.scale_amount_min = 1.0
	_trail.scale_amount_max = 2.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.6, 0.7))
	grad.add_point(0.12, Color(0.75, 0.75, 0.78, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.5, 0.55, 0.0))
	_trail.color_ramp = grad
	_trail.position = Vector3(0, 0, 3.0)
	add_child(_trail)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.light_energy = 3.0
	l.omni_range = 40.0
	l.position = Vector3(0, 0, 3.5)
	add_child(l)
	# the long streak across the sky
	var ribbon := Trail.new()
	ribbon.follow = self
	# a heavy long-range round draws a fat column and a long arc of light, a shoulder-fired one a
	# thin thread
	var heavy := clampf((float(def.range) - 5000.0) / 35000.0, 0.0, 1.0)
	ribbon.life = lerpf(6.5, 10.0, heavy)
	ribbon.glow_time = lerpf(5.0, 8.0, heavy)
	ribbon.w0 = lerpf(1.1, 2.0, heavy)
	ribbon.w1 = lerpf(11.0, 24.0, heavy)
	ribbon.wobble = lerpf(9.0, 18.0, heavy)
	game.fx_root.add_child(ribbon)
	_orient()
	if cosmetic:
		return
	if _target_ok() and not GS.realism:
		_committed = float(def.damage) * GS.eff(weapon_id, target)
		target.inbound += _committed
	if target and target.has_method("evade"):
		target.evade()


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and not target.dead


func _orient() -> void:
	var n := vel.normalized()
	look_at(position + n, Vector3.UP if absf(n.y) < 0.97 else Vector3.FORWARD)


func _process(delta: float) -> void:
	if _done:
		return
	life -= delta
	_age += delta
	boost -= delta
	speed = minf(max_speed, speed + max_speed * 1.3 * GS.TEMPO * delta)
	var dir := vel.normalized()
	if _target_ok():
		if boost <= 0.0:
			var aim := Bullet.lead(position, target.position, target.vel, speed)
			var want := (aim - position).normalized()
			var ang := dir.angle_to(want)
			if ang > 0.0001:
				dir = dir.slerp(want, clampf(turn * delta / ang, 0.0, 1.0)).normalized()
	elif String(def.get("class", "")) == "air" and not cosmetic and _retarget(dir):
		pass # an air-to-air missile whose target is gone turns on the next threat ahead
	else:
		life = minf(life, 1.2)
	vel = dir * speed
	var p0 := position
	position += vel * delta
	_orient()
	if _target_ok():
		# the proximity fuse works on the closest approach inside the frame: at these closing
		# speeds the two cross tens of metres between two frames
		var r: float = target.radius + 12.0
		var rel0: Vector3 = p0 - target.position
		var rel1: Vector3 = rel0 + (vel - target.vel) * delta
		if Bullet.seg_dist(rel0, rel1, Vector3.ZERO) < r:
			position = target.position
			_detonate(true)
			return
	# a roof right beside the launcher does not stop a round that is still leaving its rail
	if life <= 0.0 or position.y < 0.5 or (_age > 0.6 and position.y < 400.0 and position.y < game.map.ground_height(position.x, position.z)):
		_detonate(false)


## The nearest threat within 35° of the nose and 15 km that is not already taken care of.
func _retarget(dir: Vector3) -> bool:
	var best = null
	var bd := 15000.0
	for e in game.enemies:
		if e.dead or GS.eff(weapon_id, e) <= 0.0 or e.inbound >= e.hp:
			continue
		var to: Vector3 = e.position - position
		if to.length() < bd and dir.angle_to(to) < deg_to_rad(35.0):
			bd = to.length()
			best = e
	if best == null:
		return false
	target = best
	_committed = float(def.damage) * GS.eff(weapon_id, target)
	target.inbound += _committed
	return true


## Fragments still reach a target this close to the burst point.
const FRAG_RADIUS := 45.0


func _detonate(hit: bool) -> void:
	_done = true
	if cosmetic:
		Fx.explosion(game.fx_root, position, 0.55, Color(1.0, 0.85, 0.5))
		game.play_3d("boom_small", position, -4.0)
		_trail.emitting = false
		_trail.reparent(game.fx_root)
		var ct := _trail
		get_tree().create_timer(2.5, false).timeout.connect(ct.queue_free)
		queue_free()
		return
	if _target_ok():
		target.inbound = maxf(0.0, target.inbound - _committed)
	if GS.realism and _target_ok():
		# no hit points here: the round either brings the target down or passes by
		if hit and randf() < GS.kill_chance(weapon_id, target):
			target.take_damage(target.hp + 1.0, weapon_id)
		else:
			game.missile_missed(self, position.distance_to(target.position))
	elif hit and _target_ok():
		var eff: float = GS.eff(weapon_id, target)
		target.take_damage(float(def.damage) * eff, weapon_id)
		if eff < 0.5 and not target.dead:
			game.hud.log_event(GS.t("%s: цели «%s» нужно несколько ракет") % [GS.t(String(def.short)), GS.t(String(target.def.name))], Color(1, 0.6, 0.2))
	elif _target_ok():
		# A miss is not always a wasted missile: the warhead sprays the target with fragments.
		var d: float = position.distance_to(target.position)
		var frag: float = clampf(1.0 - d / FRAG_RADIUS, 0.0, 1.0)
		if frag > 0.0:
			target.take_damage(float(def.damage) * GS.eff(weapon_id, target) * frag * 0.5, weapon_id)
		game.missile_missed(self, d)
	Fx.explosion(game.fx_root, position, 0.55, Color(1.0, 0.85, 0.5))
	game.play_3d("boom_small", position, -4.0)
	_trail.emitting = false
	_trail.reparent(game.fx_root)
	var tr := _trail
	get_tree().create_timer(2.5, false).timeout.connect(tr.queue_free)
	queue_free()
