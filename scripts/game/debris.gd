extends MeshInstance3D
## Burning fragment of a destroyed target. Keeps the target's momentum (inertia),
## falls under gravity with light air drag, and reports where it lands.
## A "wreck" carries the target's own model (tumbling, on fire); if `warhead` is set it
## explodes on impact.

const Fx = preload("res://scripts/core/fx.gd")
const Trail = preload("res://scripts/game/trail.gd")

const GRAVITY := 9.81
const DRAG := 0.25
const INERTIA := 0.75
## Wreckage does not fall faster than this (air drag).
const TERMINAL := 75.0


## What a wreck starts with: the momentum of its target at the target's real speed. Flight runs
## GS.TEMPO times faster than life, a fall does not — so the pieces come down as far ahead of the
## kill as they would in life.
static func start_vel(target_vel: Vector3) -> Vector3:
	return target_vel * (INERTIA / GS.TEMPO)

var game
var vel := Vector3.ZERO
var penalty := 1000
var event_id := 0
var wreck: Node3D = null
var warhead := false
## A guest's copy of the host's wreck (multiplayer): shows where it lands, costs nothing here.
var cosmetic := false
var _axis := Vector3.UP
var _spin := 1.0
var _trail: CPUParticles3D
var _line: Node
## A fragment burns out on the way down: seconds its glow lasts (the airframe burns to the ground).
var _burn := 1.0e9
var _age := 0.0
## Every piece meets the air its own way.
var _terminal := TERMINAL


## Same integration as _process, used to predict where debris of a target would fall.
static func predict(map, pos: Vector3, v: Vector3) -> Vector3:
	var p := pos
	var vv := start_vel(v)
	var dt := 0.2
	for i in 1500:
		vv.y = maxf(vv.y - GRAVITY * dt, -TERMINAL)
		vv.x *= 1.0 - DRAG * dt
		vv.z *= 1.0 - DRAG * dt
		p += vv * dt
		if p.y <= 420.0 and p.y <= map.ground_height(p.x, p.z):
			return p
		if p.y <= 0.0:
			return p
	return p


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if wreck:
		_spin = randf_range(1.2, 3.0)
		add_child(wreck)
		wreck.transform = Transform3D.IDENTITY
		var fire := Fx.exhaust(Color(1.0, 0.45, 0.1), 40, 0.5, 1.8)
		fire.direction = Vector3.UP
		fire.spread = 40.0
		add_child(fire)
	else:
		mesh = Fx.cube(Vector3(randf_range(0.8, 2.2), randf_range(0.5, 1.4), randf_range(0.8, 2.4)))
		material_override = Fx.glow(Color(1.0, 0.42, 0.1), 3.5)
		_spin = randf_range(3.0, 9.0)
	# the fall is drawn as a burning line that curves down to the ground: the airframe drags a
	# column of fire and black smoke, a fragment a thin thread of sparks (one fragment in three:
	# a dozen ribbons for every kill of a big raid is more than the eye needs)
	if not wreck:
		_burn = randf_range(1.2, 4.5)
		_terminal = TERMINAL * randf_range(0.7, 1.15)
		if randf() > 0.34:
			return
	var line := Trail.new()
	_line = line
	line.follow = self
	line.back = 0.0
	line.step = 12.0 if wreck else 22.0
	line.hot = Color(1.0, 0.5, 0.16, 0.95)
	line.glow = Color(1.0, 0.52, 0.18)
	if wreck:
		line.life = 6.0
		line.hot_time = 1.3
		line.glow_time = 3.2
		line.w0 = 2.0
		line.w1 = 15.0
		line.wobble = 7.0
		line.smoke = Color(0.3, 0.28, 0.28, 0.55)
		line.glow_energy = 2.6
	else:
		line.life = 2.4
		line.hot_time = 0.5
		line.glow_time = randf_range(0.3, 0.9)
		line.w0 = 0.5
		line.w1 = 4.0
		line.wobble = 2.5
		line.smoke = Color(0.4, 0.36, 0.34, 0.22)
		line.hot_energy = 2.4
		line.glow_energy = 1.7
	game.fx_root.add_child(line)
	if not wreck:
		return
	_trail = CPUParticles3D.new()
	_trail.mesh = Fx.sphere(1.0, 5)
	_trail.material_override = Fx.smoke_mat()
	_trail.local_coords = false
	_trail.amount = 30
	_trail.lifetime = 2.2
	_trail.spread = 30.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3(0, 2.0, 0)
	_trail.scale_amount_min = 1.2
	_trail.scale_amount_max = 2.8
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.5, 0.15, 0.8))
	grad.add_point(0.2, Color(0.35, 0.3, 0.3, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	_trail.color_ramp = grad
	add_child(_trail)


func _process(delta: float) -> void:
	_age += delta
	if _age > _burn and visible:
		# burnt out: the piece goes on falling, dark
		visible = false
		if is_instance_valid(_line):
			_line.finish()
	vel.y = maxf(vel.y - GRAVITY * delta, -_terminal)
	vel.x *= 1.0 - DRAG * delta
	vel.z *= 1.0 - DRAG * delta
	position += vel * delta
	rotate(_axis, _spin * delta)
	var gh: float = game.map.ground_height(position.x, position.z)
	if position.y <= gh:
		position.y = gh
		game.debris_landed(self, gh)
		if _trail != null:
			_trail.emitting = false
			_trail.reparent(game.fx_root)
			var tr := _trail
			get_tree().create_timer(2.5, false).timeout.connect(tr.queue_free)
		queue_free()
