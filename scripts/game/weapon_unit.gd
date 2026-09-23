extends Node3D
## One air-defense system at the base. Guns keep firing at the assigned target while it is
## in range; missile systems launch exactly one interceptor per order (ammo costs money).
## In the gunner view the unit is `manual`: the turret follows the sight and fires on trigger.

const Meshes = preload("res://scripts/core/meshes.gd")
const Fx = preload("res://scripts/core/fx.gd")
const Bullet = preload("res://scripts/game/bullet.gd")

var game
var id := "mg"
var def: Dictionary
var target = null
var auto_assigned := false
var cooldown := 0.0
var manual := false
var manual_dir := Vector3.FORWARD
var manual_point := Vector3.ZERO
var trigger := false

var model: Node3D
var turret: Node3D
var pitch: Node3D
var muzzle: Node3D
var spin: Node3D
var idle_pitch := 0.15
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_glare: MeshInstance3D
var _flash_t := 0.0
var _scan := 0.0
var _barrel := 1.0
var _retarget := 0.0


func setup(g, wid: String, pos: Vector3) -> void:
	game = g
	id = wid
	position = pos


func _ready() -> void:
	def = GS.WEAPONS[id]
	model = Meshes.weapon_model(id)
	add_child(model)
	turret = model.get_meta("turret")
	pitch = model.get_meta("pitch")
	muzzle = model.get_meta("muzzle")
	if model.has_meta("spin"):
		spin = model.get_meta("spin")
	idle_pitch = float(model.get_meta("idle_pitch", 0.15))
	var d := Vector3(position.x, 0, position.z).normalized()
	rotation.y = atan2(-d.x, -d.z)
	_scan = randf() * TAU
	_flash = MeshInstance3D.new()
	_flash.mesh = Fx.sphere(0.9, 8)
	_flash.material_override = Fx.glow(Color(1.0, 0.8, 0.4), 8.0)
	_flash.visible = false
	muzzle.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 22.0
	muzzle.add_child(_flash_light)
	_flash_glare = Fx.glare(Color(1.0, 0.8, 0.5), 3.0, 2.5, 0.004, 0.4)
	_flash_glare.visible = false
	muzzle.add_child(_flash_glare)


func effective_range() -> float:
	var r: float = def.range
	if def.kind == "gun":
		r *= float(GS.loc_def().gun_range)
	return r


func can_engage(e) -> bool:
	return GS.eff(id, e) > 0.0


func in_range(e) -> bool:
	return global_position.distance_to(e.position) <= effective_range()


## Gunner's eye point for the sight camera.
func eye_pos() -> Vector3:
	return turret.global_position + Vector3(0, float(def.eye), 0)


func status_text() -> String:
	if def.kind == "drone" and int(GS.ammo.get(id, 0)) <= 0:
		return GS.t("НЕТ ДРОНОВ") if game.drones.is_empty() else GS.t("РОЙ В ВОЗДУХЕ")
	if manual:
		return GS.t("РУЧНОЙ")
	if target == null:
		return GS.t("ОЖИДАНИЕ")
	if not in_range(target):
		return GS.t("ВНЕ ЗОНЫ")
	match String(def.kind):
		"gun":
			return GS.t("ОГОНЬ")
		"drone":
			return GS.t("ЗАПУСК")
	return GS.t("ПУСК")


func _process(delta: float) -> void:
	cooldown -= delta
	if spin:
		spin.rotate_y(delta * 4.0)
	_flash_t -= delta
	var fl := _flash_t > 0.0
	_flash.visible = fl
	_flash_glare.visible = fl
	_flash_light.light_energy = 6.0 if fl else 0.0
	if manual:
		_aim_dir(manual_dir, delta * 3.0)
		if def.kind == "gun" and trigger and cooldown <= 0.0:
			_fire_gun_at(manual_point, true)
		return
	if target != null and (not is_instance_valid(target) or target.dead):
		target = null
	# [F] mode 1 = barrels and drones only, mode 2 = the SAM launchers join in as well.
	var auto_mode: int = int(game.auto_fire)
	var can_auto: bool = auto_mode >= 2 or (auto_mode >= 1 and (def.kind == "gun" or def.kind == "drone")) or (game.autotest and def.kind == "missile")
	_retarget -= delta
	if can_auto and (target == null or auto_assigned) and _retarget <= 0.0:
		# re-evaluated periodically so auto-fire stops when the debris zone becomes unsafe
		_retarget = 0.25
		target = game.find_auto_target(self)
		auto_assigned = true
	if target == null:
		_scan += delta * 0.35
		_aim_dir(Vector3(sin(_scan), idle_pitch, cos(_scan)), delta * 0.3)
		return
	var mp := muzzle.global_position
	var aim: Vector3 = target.position
	if def.kind == "gun":
		aim = Bullet.lead(mp, target.position, target.vel, float(def.speed))
	elif def.kind == "drone":
		# the rail throws the drone up at a fixed angle; it climbs out and then hunts
		aim = target.position + Vector3(0, 60.0, 0)
	else:
		aim = target.position + Vector3(0, global_position.distance_to(target.position) * 0.3, 0)
	_aim_dir(aim - turret.global_position, delta)
	if not in_range(target) or cooldown > 0.0:
		return
	if def.kind == "gun":
		_fire_gun_at(aim, false)
	else:
		launch_at(target, false)
		target = null


func _aim_dir(world_dir: Vector3, delta: float) -> void:
	var ld := model.global_transform.basis.inverse() * world_dir
	var yaw := atan2(-ld.x, -ld.z)
	var elev := atan2(ld.y, Vector2(ld.x, ld.z).length())
	var k := clampf(delta * 8.0, 0.0, 1.0)
	turret.rotation.y = lerp_angle(turret.rotation.y, yaw, k)
	pitch.rotation.x = lerpf(pitch.rotation.x, clampf(elev, -0.05, 1.5), k)


func _fire_gun_at(aim: Vector3, is_manual: bool) -> void:
	cooldown = float(def.rate)
	var mp := muzzle.global_position
	if id == "gepard":
		_barrel = -_barrel
		mp += pitch.global_basis.x * 1.55 * _barrel
	var s: float = def.spread
	var dir := (aim - mp).normalized()
	dir = (dir + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
	game.spawn_bullet(mp, dir * float(def.speed), id, effective_range() / float(def.speed) * 1.25, is_manual)
	_flash_t = 0.035
	if id == "gepard":
		game.play_3d("cannon", global_position, -8.0 + (4.0 if is_manual else 0.0), 0.05)
	else:
		game.play_3d("mg", global_position, -10.0 + (4.0 if is_manual else 0.0), 0.06)


## Launches one interceptor (missile or drone) at `e`. Returns false when out of ammunition
## or still reloading. Automatic launches stay silent: only the player's own orders answer back.
func launch_at(e, announce := true) -> bool:
	if cooldown > 0.0:
		return false
	var is_drone: bool = def.kind == "drone"
	if e != null and is_instance_valid(e) and e.inbound >= e.hp:
		# Interceptors already in flight will finish this target: don't burn another one.
		if announce:
			var txt := GS.t("ЦЕЛЬ УЖЕ ПЕРЕХВАЧЕНА — дрон не потрачен") if is_drone else GS.t("ЦЕЛЬ УЖЕ ПЕРЕХВАЧЕНА — ракета не потрачена")
			game.hud.alert(txt, Color(0.5, 0.95, 0.7))
		cooldown = 0.2
		return false
	if int(GS.ammo.get(id, 0)) <= 0:
		if announce:
			var msg := GS.t("НЕТ ДРОНОВ %s — купите в магазине [B]") if is_drone else GS.t("НЕТ РАКЕТ %s — купите в магазине [B]")
			game.hud.alert(msg % GS.t(String(def.short)), Color(1.0, 0.6, 0.2))
		cooldown = 1.0
		return false
	GS.ammo[id] = int(GS.ammo[id]) - 1
	GS.state_changed.emit()
	cooldown = float(def.rate)
	var fwd := -pitch.global_basis.z
	if is_drone:
		game.spawn_drone(muzzle.global_position, fwd, e)
		_flash_t = 0.12
		game.play_3d("prop", global_position, -2.0 if manual else -6.0)
	else:
		game.spawn_missile(muzzle.global_position, fwd, e, id)
		_flash_t = 0.3
		game.play_3d("launch", global_position, 0.0 if manual else -2.0)
	return true
