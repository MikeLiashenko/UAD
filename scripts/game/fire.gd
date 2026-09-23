extends Node3D
## One fire burning on a roof, in the street or on a crash site. Unlike the one-shot Fx.fire
## effect this one is a live object: it keeps burning until a crew of the city fire service
## puts it out (see scripts/game/fire_service.gd) or until the building burns itself out.

const Fx = preload("res://scripts/core/fx.gd")

## A fire nobody attends dies down on its own after this many seconds — the building is left
## gutted (and stays collapsed until the repair crews get to it).
const BURN_OUT := 210.0

var game
## Building this fire sits on, or -1 for a fire on open ground.
var bi := -1
var size := 1.0
## 1 = full blaze, 0 = out.
var intensity := 1.0
## The crew currently working this fire (see fire_service.gd).
var crew = null

var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D
var _glare: MeshInstance3D
var _age := 0.0
var _done := false


func _ready() -> void:
	_flames = CPUParticles3D.new()
	_flames.mesh = Fx.sphere(1.0, 6)
	_flames.material_override = Fx.fire_mat()
	_flames.amount = 22
	_flames.lifetime = 0.9
	_flames.direction = Vector3.UP
	_flames.spread = 20.0
	_flames.initial_velocity_min = 4.0
	_flames.initial_velocity_max = 9.0
	_flames.gravity = Vector3(0, 3, 0)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = 2.5 * size
	var fg := Gradient.new()
	fg.set_color(0, Color(1.0, 0.8, 0.4, 0.9))
	fg.add_point(0.4, Color(1.0, 0.35, 0.05, 0.6))
	fg.set_color(fg.get_point_count() - 1, Color(0.4, 0.05, 0.0, 0.0))
	_flames.color_ramp = fg
	add_child(_flames)
	_smoke = Fx.exhaust(Color(0.5, 0.5, 0.5), 14, 5.0, 4.0 * size)
	_smoke.material_override = Fx.smoke_mat()
	_smoke.local_coords = false
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 3.0
	_smoke.initial_velocity_max = 8.0
	_smoke.gravity = Vector3(1.5, 6.0, 0)
	_smoke.emitting = true
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = 30.0 * size
	_light.position.y = 4.0
	add_child(_light)
	_glare = Fx.glare(Color(1.0, 0.45, 0.12), 1.2, 3.0 * size, 0.004, 0.1, 0.6)
	_glare.position.y = 2.0
	add_child(_glare)
	_refresh()


## Water on the fire: `amount` is the share of the blaze knocked down this frame.
func suppress(amount: float) -> void:
	if _done:
		return
	intensity = maxf(0.0, intensity - amount)
	_refresh()
	if intensity <= 0.0:
		_out(true)


func _refresh() -> void:
	var k := clampf(intensity, 0.0, 1.0)
	_flames.scale_amount_min = (0.4 + 0.8 * k) * size
	_flames.scale_amount_max = (0.8 + 1.8 * k) * size
	_flames.emission_sphere_radius = (0.8 + 1.7 * k) * size
	_light.light_energy = 0.6 + 2.2 * k
	_glare.scale = Vector3.ONE * (0.4 + 0.6 * k)


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	# a blaze left alone eats through the building and finally dies on its own
	if crew == null:
		intensity = minf(1.0, intensity + delta * 0.02)
	if _age > BURN_OUT:
		_out(false)
		return
	_refresh()


func _out(by_crew: bool) -> void:
	if _done:
		return
	_done = true
	intensity = 0.0
	_flames.emitting = false
	_smoke.emitting = false
	_glare.visible = false
	if by_crew:
		# a cloud of steam where the water hits the embers
		var steam := Fx.exhaust(Color(0.8, 0.85, 0.9), 26, 2.4, 3.0 * size)
		steam.material_override = Fx.smoke_mat()
		steam.one_shot = true
		steam.explosiveness = 0.7
		steam.spread = 55.0
		steam.initial_velocity_min = 3.0
		steam.initial_velocity_max = 9.0
		steam.gravity = Vector3(0, 2.5, 0)
		steam.emitting = true
		add_child(steam)
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, 1.5)
	tw.tween_callback(queue_free).set_delay(4.0)
	game.fire_service.on_fire_out(self, by_crew)
