extends MeshInstance3D
## A chunk of a collapsed building: falls off the shattered floors, tumbles, lands on what is
## left of the roof or in the street and lies there until the repair crews clear it away.

const Fx = preload("res://scripts/core/fx.gd")

const GRAVITY := 22.0
## How long a settled chunk stays before it is cleared.
const LINGER := 55.0

var game
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var _rest := 0.0
var _landed := false


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	spin = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


func _process(delta: float) -> void:
	if _landed:
		_rest -= delta
		if _rest <= 4.0:
			transparency = clampf(1.0 - _rest / 4.0, 0.0, 1.0)
		if _rest <= 0.0:
			queue_free()
		return
	vel.y -= GRAVITY * delta
	position += vel * delta
	rotation += spin * delta
	var ground: float = game.map.ground_height(position.x, position.z)
	if position.y <= ground + 0.4:
		position.y = ground + 0.4
		_landed = true
		_rest = LINGER + randf() * 10.0
		Fx.ground_hit(game.fx_root, position)
