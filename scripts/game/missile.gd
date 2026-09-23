extends Node3D
## Surface-to-air interceptor with lead-pursuit guidance and a proximity fuse.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Bullet = preload("res://scripts/game/bullet.gd")

var game
var target
var weapon_id := "iris"
var def: Dictionary
var vel := Vector3.UP
var speed := 40.0
var max_speed := 300.0
var turn := 3.0
var life := 14.0
var boost := 0.35

var _trail: CPUParticles3D
var _done := false
var _committed := 0.0
## A friend's missile drawn on our screen (multiplayer): flies at the same threat, deals no damage.
var cosmetic := false


func _ready() -> void:
	def = GS.WEAPONS[weapon_id]
	max_speed = float(def.speed)
	turn = float(def.turn)
	add_child(Meshes.interceptor(weapon_id == "patriot"))
	_trail = CPUParticles3D.new()
	_trail.mesh = Fx.sphere(1.0, 6)
	_trail.material_override = Fx.smoke_mat()
	_trail.local_coords = false
	_trail.amount = 90
	_trail.lifetime = 2.2
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
	_orient()
	if cosmetic:
		return
	if _target_ok():
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
	boost -= delta
	speed = minf(max_speed, speed + max_speed * 1.3 * delta)
	var dir := vel.normalized()
	if _target_ok():
		if boost <= 0.0:
			var aim := Bullet.lead(position, target.position, target.vel, speed)
			var want := (aim - position).normalized()
			var ang := dir.angle_to(want)
			if ang > 0.0001:
				dir = dir.slerp(want, clampf(turn * delta / ang, 0.0, 1.0)).normalized()
	else:
		life = minf(life, 1.2)
	vel = dir * speed
	var p0 := position
	position += vel * delta
	_orient()
	if _target_ok():
		var r: float = target.radius + 8.0
		if Bullet.seg_dist(p0, position, target.position) < r:
			_detonate(true)
			return
	if life <= 0.0 or position.y < 0.5:
		_detonate(false)


## Fragments still reach a target this close to the burst point.
const FRAG_RADIUS := 34.0


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
	if hit and _target_ok():
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
