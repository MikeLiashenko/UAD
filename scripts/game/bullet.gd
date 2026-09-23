extends MeshInstance3D
## Tracer round. Continuous (swept-segment) hit detection against every live target.

const Fx = preload("res://scripts/core/fx.gd")

var game
var vel := Vector3.ZERO
var life := 1.0
var weapon_id := "mg"
var damage := 1.0
var color := Color(1.0, 0.45, 0.15)
var manual := false


static func seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## First-order intercept point for a projectile of `speed` fired from `from`.
static func lead(from: Vector3, tp: Vector3, tv: Vector3, speed: float) -> Vector3:
	var t := from.distance_to(tp) / maxf(speed, 1.0)
	for i in 3:
		t = from.distance_to(tp + tv * t) / maxf(speed, 1.0)
	return tp + tv * t


func _ready() -> void:
	mesh = Fx.cube(Vector3(0.3, 0.3, 7.0) if not manual else Vector3(0.22, 0.22, 5.0))
	material_override = Fx.glow(color, 6.0)
	extra_cull_margin = 8.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orient()


func _orient() -> void:
	if vel.length_squared() > 0.01:
		var n := vel.normalized()
		look_at(position + n, Vector3.UP if absf(n.y) < 0.97 else Vector3.FORWARD)


func _process(delta: float) -> void:
	var p0 := position
	vel.y -= 4.9 * delta
	var p1 := p0 + vel * delta
	for e in game.enemies:
		if e.dead:
			continue
		if seg_dist(p0, p1, e.position) < e.radius + 0.8:
			var eff: float = GS.eff(weapon_id, e)
			e.take_damage(damage * eff, weapon_id)
			if manual:
				game.on_manual_hit(e)
			queue_free()
			return
	position = p1
	_orient()
	life -= delta
	if life <= 0.0 or p1.y < 0.0:
		queue_free()
