extends MeshInstance3D
## Burning fragment of a destroyed target. Keeps the target's momentum (inertia),
## falls under gravity with light air drag, and reports where it lands.
## A "wreck" carries the target's own model (tumbling, on fire); if `warhead` is set it
## explodes on impact.

const Fx = preload("res://scripts/core/fx.gd")

const GRAVITY := 32.0
const DRAG := 0.25
const INERTIA := 0.75

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


## Same integration as _process, used to predict where debris of a target would fall.
static func predict(map, pos: Vector3, v: Vector3) -> Vector3:
	var p := pos
	var vv := v * INERTIA
	var dt := 0.08
	for i in 800:
		vv.y -= GRAVITY * dt
		vv.x *= 1.0 - DRAG * dt
		vv.z *= 1.0 - DRAG * dt
		p += vv * dt
		if p.y <= 60.0 and p.y <= map.ground_height(p.x, p.z):
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
	_trail = CPUParticles3D.new()
	_trail.mesh = Fx.sphere(1.0, 5)
	_trail.material_override = Fx.smoke_mat()
	_trail.local_coords = false
	_trail.amount = 40 if wreck else 24
	_trail.lifetime = 2.2 if wreck else 1.6
	_trail.spread = 30.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3(0, 2.0, 0)
	_trail.scale_amount_min = 1.2 if wreck else 0.8
	_trail.scale_amount_max = 2.8 if wreck else 1.8
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.5, 0.15, 0.8))
	grad.add_point(0.2, Color(0.35, 0.3, 0.3, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	_trail.color_ramp = grad
	add_child(_trail)


func _process(delta: float) -> void:
	vel.y -= GRAVITY * delta
	vel.x *= 1.0 - DRAG * delta
	vel.z *= 1.0 - DRAG * delta
	position += vel * delta
	rotate(_axis, _spin * delta)
	var gh: float = game.map.ground_height(position.x, position.z)
	if position.y <= gh:
		position.y = gh
		game.debris_landed(self, gh)
		_trail.emitting = false
		_trail.reparent(game.fx_root)
		var tr := _trail
		get_tree().create_timer(2.5, false).timeout.connect(tr.queue_free)
		queue_free()
