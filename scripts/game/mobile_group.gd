extends Node
## Mobile fire group (МОГ) [M]: the player takes a pickup with a heavy machine gun and a
## searchlight out into the city. The radio calls the drone the crew can still catch and puts a
## beacon on the ground where its course passes closest; you race there along the streets and
## over the bridges, jump to the gun and shoot it down in the searchlight.
##
## Two seats: the wheel (chase camera; W/S gas and brake, A/D steer, mouse looks around) and the
## gun (first person; mouse aims, LMB fires, RMB zooms). Space swaps seats. The truck is a moving
## WeaponUnit("mg"): while you drive, or when it is left parked, its crew fires by itself with
## auto-fire [F] on. The barrel overheats in long bursts. Blasts and falling debris nearby damage
## the truck; a wrecked one is back at the base the next morning.

const WeaponUnit = preload("res://scripts/game/weapon_unit.gd")
const Fx = preload("res://scripts/core/fx.gd")

const SCALE := 0.75
## Top speed on the highways (m/s, ≈108 km/h), the share of it elsewhere and in the woods.
const MAX_SPEED := 30.0
const OFF_ROAD := 0.62
const FOREST := 0.35
const ACCEL := 13.0
const BRAKE := 32.0
const REVERSE := 9.0
const STEER := 1.8
const HALF_W := 1.3
const HALF_L := 2.6
## The radio calls only what the gun can reach: drones below this height (world units).
const MAX_ALT := 330.0
const RADIO_RANGE := 1300.0
## Barrel heat per second of fire and cooling per second.
const HEAT := 0.55
const COOL := 0.4

var game
var map
var cam: Camera3D
var active := false
## "drive" or "gun".
var seat := "drive"
var unit: Node3D
var pos := Vector3.ZERO
var heading := 0.0
var speed := 0.0
var hp := 100.0
var wrecked := false
var heat := 0.0
var overheated := false
var fire_held := false
var zoomed := false
var cam_yaw := 0.0
var cam_pitch := 0.28
var gun_yaw := 0.0
var gun_pitch := 0.25
## The threat the radio is calling and the ground point where its course passes closest.
var tip = null
var tip_point := Vector3.INF
var tip_eta := 0.0
var _saved_fov := 62.0
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _light: SpotLight3D
## Headlights (they light the road) and the lamps themselves, front white and rear red.
var _heads: Array[SpotLight3D] = []
var _lamps: Array[MeshInstance3D] = []
var _beam: MeshInstance3D
var _pillar: MeshInstance3D
var _engine: AudioStreamPlayer
var _touch_move := -1
var _touch_origin := Vector2.ZERO
var _touch_vec := Vector2.ZERO
var _tip_t := 0.0


func _ready() -> void:
	_engine = AudioStreamPlayer.new()
	_engine.bus = "Effects"
	_engine.stream = SFX.stream("buzz")
	_engine.volume_db = -60.0
	add_child(_engine)


func _touch() -> bool:
	return DisplayServer.is_touchscreen_available()


## The truck, built the first time it is needed; it stays in the city afterwards.
func ensure_truck() -> void:
	if unit != null and is_instance_valid(unit):
		return
	unit = WeaponUnit.new()
	pos = _spawn_point()
	unit.setup(game, "mg", pos)
	unit.scale = Vector3.ONE * SCALE
	game.add_child(unit)
	heading = atan2(pos.x - GS.base_pos.x, pos.z - GS.base_pos.z)
	unit.rotation.y = heading
	_light = SpotLight3D.new()
	_light.spot_range = 900.0
	_light.spot_angle = 4.5
	_light.spot_attenuation = 0.6
	_light.light_energy = 0.0
	_light.light_color = Color(0.9, 0.95, 1.0)
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.4, -0.6)
	(unit.pitch as Node3D).add_child(_light)
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 26.0
	cone.bottom_radius = 0.35
	cone.height = 560.0
	cone.radial_segments = 16
	cone.rings = 1
	_beam.mesh = cone
	_beam.material_override = _beam_mat()
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.rotation_degrees = Vector3(-90, 0, 0)
	_beam.position = Vector3(0, 0.4, -280.0)
	_beam.visible = false
	(unit.pitch as Node3D).add_child(_beam)
	for sx in [-1.0, 1.0]:
		var hl := SpotLight3D.new()
		hl.spot_range = 70.0
		hl.spot_angle = 32.0
		hl.light_energy = 0.0
		hl.light_color = Color(1.0, 0.93, 0.8)
		hl.shadow_enabled = false
		hl.position = Vector3(1.05 * sx, 1.35, -3.6)
		hl.rotation_degrees = Vector3(-7, 0, 0)
		unit.model.add_child(hl)
		_heads.append(hl)
		for spec in [[Vector3(1.05 * sx, 1.35, -3.52), Color(1.0, 0.95, 0.85), 5.0], [Vector3(1.3 * sx, 1.4, 3.52), Color(1.0, 0.1, 0.05), 3.0]]:
			var lamp := MeshInstance3D.new()
			lamp.mesh = Fx.cube(Vector3(0.55, 0.3, 0.08))
			lamp.material_override = Fx.glow(spec[1], spec[2])
			lamp.position = spec[0]
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			unit.model.add_child(lamp)
			_lamps.append(lamp)
	_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.2
	pm.bottom_radius = 3.0
	pm.height = 160.0
	pm.radial_segments = 12
	_pillar.mesh = pm
	_pillar.material_override = _pillar_mat()
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.visible = false
	game.add_child(_pillar)
	wrecked = false
	hp = 100.0


static func _beam_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.09;
void fragment() {
	float f = pow(clamp(UV.y, 0.0, 1.0), 2.2);
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = vec3(0.85, 0.92, 1.0) * strength * f * edge;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func _pillar_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
void fragment() {
	float f = pow(clamp(UV.y, 0.0, 1.0), 1.6) * (0.75 + 0.25 * sin(TIME * 5.0));
	ALBEDO = vec3(1.0, 0.7, 0.2) * f * 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## A free spot on a street near the base (the highway if there is one close by).
func _spawn_point() -> Vector3:
	var best := Vector3.INF
	var r := 18.0
	while r < 360.0 and best == Vector3.INF:
		for i in 24:
			var a := TAU * i / 24.0
			var x := GS.base_pos.x + cos(a) * r
			var z := GS.base_pos.z + sin(a) * r
			if not _blocked(Vector3(x, 0, z), a) and map.water_dist(x, z) > 4.0 and map.road_dist(x, z) < 2.0:
				best = Vector3(x, _floor_at(x, z), z)
				break
		r += 12.0
	if best == Vector3.INF:
		best = game.walker.find_free(GS.base_pos + Vector3(0, 0, 30))
	return best


func enter() -> void:
	ensure_truck()
	if wrecked:
		game.hud.alert(GS.t("Пикап МОГ подбит — новый будет утром"), Color(1.0, 0.6, 0.3))
		return
	active = true
	seat = "drive"
	cam_yaw = 0.0
	cam_pitch = 0.28
	_saved_fov = cam.fov
	cam.fov = 70.0
	_cam_pos = pos + Vector3(0, 8, 0) - _fwd(heading) * 16.0
	unit.manual = false
	if _engine.stream != null:
		_engine.play()
	refresh_capture()


func exit() -> void:
	active = false
	fire_held = false
	zoomed = false
	if unit != null and is_instance_valid(unit):
		unit.manual = false
		unit.trigger = false
	_engine.stop()
	cam.fov = _saved_fov
	if _pillar != null:
		_pillar.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func refresh_capture() -> void:
	if not active or _touch():
		if active:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var free: bool = get_tree().paused or Input.is_key_pressed(KEY_ALT) or game.game_over or game.wants_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func switch_seat() -> void:
	if not active:
		return
	if seat == "drive":
		seat = "gun"
		gun_yaw = heading + cam_yaw
		gun_pitch = maxf(cam_pitch * 0.5, 0.25)
	else:
		seat = "drive"
		cam_yaw = wrapf(gun_yaw - heading, -PI, PI)
		fire_held = false
		zoomed = false
	SFX.play("click", -6.0)


static func _fwd(h: float) -> Vector3:
	return Vector3(-sin(h), 0, -cos(h))


# --- The ground --------------------------------------------------------------------------------
func _floor_at(x: float, z: float) -> float:
	var bi: int = map.building_at(x, z)
	if bi >= 0 and map.is_deck(bi):
		return map.fp_center[bi].y
	return 0.0


func _blocked_point(x: float, z: float, y: float) -> bool:
	if absf(x) > 990.0 or absf(z) > 990.0:
		return true
	var bi: int = map.building_at(x, z)
	if bi >= 0:
		if map.is_deck(bi):
			return false
		return y < map.fp_center[bi].y - 0.3
	return map.water_dist(x, z) < 0.0


## The truck's outline (four corners and the bumpers) against buildings, water and the map edge.
func _blocked(p: Vector3, h: float) -> bool:
	var f := _fwd(h)
	var r := Vector3(-f.z, 0, f.x)
	for o in [f * HALF_L + r * HALF_W, f * HALF_L - r * HALF_W, -f * HALF_L + r * HALF_W, -f * HALF_L - r * HALF_W, f * (HALF_L + 0.4), -f * (HALF_L + 0.4)]:
		if _blocked_point(p.x + o.x, p.z + o.z, p.y + 0.2):
			return true
	return false


func _top_speed(p: Vector3) -> float:
	var k := 1.0 if map.road_dist(p.x, p.z) < 1.5 or _floor_at(p.x, p.z) > 0.5 else OFF_ROAD
	if map.zone_at(p.x, p.z) == GS.Zone.FOREST:
		k = minf(k, FOREST)
	return MAX_SPEED * k


# --- Frame -----------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var night: float = game.map.night
	_light.light_energy = 14.0 * clampf((night - 0.3) / 0.4, 0.0, 1.0) if not wrecked else 0.0
	_beam.visible = _light.light_energy > 0.1
	var lit := night > 0.3 and not wrecked
	for hl in _heads:
		hl.light_energy = 2.2 if lit else 0.0
	for lamp in _lamps:
		lamp.visible = lit
	# at the gun the truck's own shield, barrel and muzzle glare would fill the picture
	unit.model.visible = not (active and seat == "gun")
	if not active:
		return
	refresh_capture()
	_radio(delta)
	if seat == "drive" and not get_tree().paused:
		_drive(delta)
	else:
		speed = move_toward(speed, 0.0, BRAKE * delta)
		_move(delta)
	unit.position = pos
	unit.rotation.y = heading
	_gun(delta)
	_camera(delta)
	_engine.volume_db = linear_to_db(clampf(0.25 + absf(speed) / MAX_SPEED * 0.6, 0.0, 1.0)) - 14.0
	_engine.pitch_scale = 0.32 + absf(speed) / MAX_SPEED * 0.45


func _drive(delta: float) -> void:
	var thr := _touch_vec.y
	var st := _touch_vec.x
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		thr += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		thr -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		st -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		st += 1.0
	thr = clampf(thr, -1.0, 1.0)
	st = clampf(st, -1.0, 1.0)
	var top := _top_speed(pos)
	if thr > 0.05:
		speed = move_toward(speed, top * thr, (ACCEL if speed >= 0.0 else BRAKE) * delta)
	elif thr < -0.05:
		speed = move_toward(speed, -REVERSE, (BRAKE if speed > 0.5 else ACCEL * 0.6) * delta)
	else:
		speed = move_toward(speed, 0.0, 5.0 * delta)
	if speed > top:
		speed = move_toward(speed, top, BRAKE * 0.6 * delta) # off the asphalt the truck bogs down
	# steering bites with speed and softens near the top speed
	var grip := clampf(absf(speed) / 6.0, 0.0, 1.0) * (1.0 - 0.45 * absf(speed) / MAX_SPEED)
	heading -= st * STEER * grip * signf(speed) * delta
	# the camera drifts back behind the truck while driving
	if absf(speed) > 3.0:
		cam_yaw = lerp_angle(cam_yaw, 0.0, 1.0 - exp(-delta * 1.2))
	_move(delta)


func _move(delta: float) -> void:
	var step := _fwd(heading) * speed * delta
	var np := pos + step
	if not _blocked(np, heading):
		pos = np
	elif not _blocked(Vector3(np.x, pos.y, pos.z), heading):
		pos.x = np.x
		speed *= 0.7
	elif not _blocked(Vector3(pos.x, pos.y, np.z), heading):
		pos.z = np.z
		speed *= 0.7
	else:
		# a wall: bounce back, the harder the faster
		var hit := absf(speed)
		speed = -speed * 0.25
		if hit > 8.0:
			shake(clampf(hit / 30.0, 0.2, 0.8))
			damage((hit - 8.0) * 0.9, GS.t("удар о препятствие"))
			game.play_3d("boom_small", pos, -14.0)
	pos.y = move_toward(pos.y, _floor_at(pos.x, pos.z), 25.0 * delta)


# --- The gun ---------------------------------------------------------------------------------------
func aim_dir() -> Vector3:
	return Vector3(-sin(gun_yaw) * cos(gun_pitch), sin(gun_pitch), -cos(gun_yaw) * cos(gun_pitch))


func _gun(delta: float) -> void:
	var at_gun := seat == "gun"
	unit.manual = at_gun
	if at_gun:
		var dir := aim_dir()
		unit.manual_dir = dir
		unit.manual_point = cam.global_position + dir * 400.0
	var firing := at_gun and fire_held and not overheated and not get_tree().paused
	unit.trigger = firing
	if firing:
		heat += HEAT * delta
		if heat >= 1.0:
			heat = 1.0
			overheated = true
			game.hud.alert(GS.t("СТВОЛ ПЕРЕГРЕЛСЯ — пауза"), Color(1.0, 0.55, 0.3))
	else:
		heat = maxf(0.0, heat - COOL * delta)
		if overheated and heat < 0.3:
			overheated = false


func _camera(delta: float) -> void:
	var so := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		so = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	if seat == "gun":
		var dir := aim_dir()
		var eye: Vector3 = (unit.pitch as Node3D).global_position + Vector3(0, 0.9, 0) - dir * 1.4
		cam.global_position = eye + so * 0.3
		cam.look_at(eye + dir, Vector3.UP)
		cam.fov = lerpf(cam.fov, 32.0 if zoomed else 70.0, 1.0 - exp(-delta * 10.0))
		return
	var yaw := heading + cam_yaw
	var back := _fwd(yaw)
	var want := pos - back * cos(cam_pitch) * 17.0 + Vector3(0, 3.0 + sin(cam_pitch) * 17.0, 0)
	# keep the camera out of the buildings around the truck
	var roof: float = map.ground_height(want.x, want.z)
	want.y = maxf(want.y, roof + 3.0)
	_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-delta * 7.0))
	cam.global_position = _cam_pos + so
	cam.look_at(pos + _fwd(heading) * 6.0 + Vector3(0, 2.2, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 70.0 + absf(speed) / MAX_SPEED * 12.0, 1.0 - exp(-delta * 4.0))


# --- The radio -------------------------------------------------------------------------------------
## Picks the drone the crew can still catch — its course passes close and it is low enough for
## the machine gun — and the ground point where it will be nearest.
func _radio(delta: float) -> void:
	_tip_t -= delta
	if _tip_t <= 0.0 or tip == null or not is_instance_valid(tip) or tip.dead:
		_tip_t = 0.5
		tip = null
		var best := INF
		for e in game.enemies:
			if e.dead or GS.eff("mg", e) < 0.25 or e.position.y > MAX_ALT:
				continue
			var d2 := Vector2(e.position.x - pos.x, e.position.z - pos.z)
			if d2.length() > RADIO_RANGE:
				continue
			var v := Vector2(e.vel.x, e.vel.z)
			var t := clampf(-d2.dot(v) / maxf(v.length_squared(), 0.01), 0.0, 90.0)
			var p := Vector2(e.position.x, e.position.z) + v * t
			var reach := p.distance_to(Vector2(pos.x, pos.z)) / (MAX_SPEED * 0.8)
			# catchable ones first (we get there before it passes), then the soonest
			var score := t + (0.0 if reach < t + 4.0 else 60.0 + reach)
			if score < best:
				best = score
				tip = e
				tip_point = _drivable_near(Vector3(p.x, 0.0, p.y))
				tip_eta = t
	elif tip != null:
		var v := Vector2(tip.vel.x, tip.vel.z)
		var d2 := Vector2(tip.position.x - pos.x, tip.position.z - pos.z)
		tip_eta = clampf(-d2.dot(v) / maxf(v.length_squared(), 0.01), 0.0, 90.0)
		var p := Vector2(tip.position.x, tip.position.z) + v * tip_eta
		if Vector2(tip_point.x, tip_point.z).distance_to(p) > 30.0:
			tip_point = _drivable_near(Vector3(p.x, 0.0, p.y))
	var show: bool = tip != null and seat == "drive" and tip_point.distance_to(pos) > 25.0
	_pillar.visible = show
	if show:
		_pillar.position = tip_point + Vector3(0, 80.0, 0)


## Where the truck can actually stand near `p`: the spot itself if it is a street, else the
## nearest free, dry spot — a highway if there is one within reach.
func _drivable_near(p: Vector3) -> Vector3:
	var fallback := Vector3.INF
	var r := 0.0
	while r <= 120.0:
		var n := maxi(1, int(r / 6.0) * 2)
		for i in n:
			var a := TAU * i / n
			var q := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
			if _blocked(q, a) or map.water_dist(q.x, q.z) < 3.0:
				continue
			q.y = _floor_at(q.x, q.z)
			if map.road_dist(q.x, q.z) < 1.5:
				return q
			if fallback == Vector3.INF:
				fallback = q
		if fallback != Vector3.INF and r >= 40.0:
			return fallback
		r += 8.0
	return fallback if fallback != Vector3.INF else p


# --- Damage ----------------------------------------------------------------------------------------
## A warhead or a wreck came down at `p`: the truck takes the blast if it is close.
func on_blast(p: Vector3, power := 1.0) -> void:
	if unit == null or not is_instance_valid(unit) or wrecked:
		return
	var d := p.distance_to(pos)
	if d > 45.0:
		return
	var k := 1.0 - d / 45.0
	if active:
		shake(0.4 + 0.6 * k)
	damage(k * k * 70.0 * power, GS.t("взрыв рядом"))


func damage(amount: float, why: String) -> void:
	if wrecked or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		_wreck(why)
	elif amount > 12.0:
		game.hud.log_event(GS.t("Пикап МОГ повреждён: %s (%d%%)") % [why, int(hp)], Color(1.0, 0.7, 0.35))


func _wreck(why: String) -> void:
	wrecked = true
	hp = 0.0
	Fx.explosion(game.fx_root, pos + Vector3(0, 1.5, 0), 1.2, Color(1.0, 0.5, 0.15), true)
	game.play_boom("explosion", pos, 0.0)
	unit.visible = false
	unit.set_process(false)
	unit.trigger = false
	game.hud.alert(GS.t("ПИКАП МОГ ПОДБИТ — экипаж эвакуирован"), Color(1.0, 0.45, 0.3))
	game.hud.log_event(GS.t("Пикап МОГ потерян: %s. Новый будет утром.") % why, Color(1.0, 0.5, 0.3))
	if active:
		game.set_view("top")


## Morning: a wrecked truck is replaced at the base, a damaged one repaired.
func repair() -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if wrecked:
		pos = _spawn_point()
		unit.visible = true
		unit.set_process(true)
		wrecked = false
	hp = 100.0
	heat = 0.0
	overheated = false


# --- Input -----------------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not active or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	var sens: float = float(GS.settings.sens)
	var inv := -1.0 if bool(GS.settings.invert_y) else 1.0
	var zk := 0.45 if zoomed else 1.0
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		if seat == "gun":
			gun_yaw -= mm.relative.x * 0.0022 * sens * zk
			gun_pitch = clampf(gun_pitch - mm.relative.y * 0.0022 * sens * inv * zk, -0.05, 1.45)
		else:
			cam_yaw = wrapf(cam_yaw - mm.relative.x * 0.003 * sens, -PI, PI)
			cam_pitch = clampf(cam_pitch - mm.relative.y * 0.003 * sens * inv, 0.05, 1.2)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not mb.pressed):
			fire_held = mb.pressed and seat == "gun"
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and seat == "gun":
			zoomed = not zoomed
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_SPACE or (event as InputEventKey).keycode == KEY_E:
			get_viewport().set_input_as_handled()
			switch_seat()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var half_w: float = get_viewport().get_visible_rect().size.x * 0.5
		if st.pressed and st.position.x < half_w and _touch_move < 0 and seat == "drive":
			_touch_move = st.index
			_touch_origin = st.position
		elif not st.pressed and st.index == _touch_move:
			_touch_move = -1
			_touch_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_move:
			var d := (sd.position - _touch_origin) / 90.0
			_touch_vec = Vector2(d.x, -d.y).limit_length(1.0)
		elif seat == "gun":
			gun_yaw -= sd.relative.x * 0.004 * sens * zk
			gun_pitch = clampf(gun_pitch - sd.relative.y * 0.004 * sens * inv * zk, -0.05, 1.45)
		else:
			cam_yaw = wrapf(cam_yaw - sd.relative.x * 0.005 * sens, -PI, PI)
