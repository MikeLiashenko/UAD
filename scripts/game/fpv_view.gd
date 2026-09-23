extends Node
## FPV console: the player takes the sticks of one interceptor drone and flies it into a target
## by hand. The camera rides the drone's nose camera, the video feed breaks up with distance
## from the base and the link drops past the control range — beyond it the drone finishes on
## its own. See scripts/game/drone.gd for the autonomous behaviour and scripts/ui/fpv_osd.gd
## for the overlay.
##
## Controls: mouse / drag — steer, W-S — throttle, Shift or LMB — boost,
## Space — next drone, R — send home, C / V / Esc — back to the previous view.

const FOV := 96.0
## Steering input decays back to centre like a spring-loaded stick.
const STICK_DECAY := 2.6
const STICK_GAIN := 0.0042

var game
var cam: Camera3D
var active := false
var drone = null
## The console overlay (scripts/ui/fpv_osd.gd), owned by the HUD.
var osd
## The view to come back to when the drone is gone or the player steps away from the console.
var return_view := "top"
## 0..1 video quality: 1 = clean feed, 0 = link lost.
var signal_q := 1.0
var boost := false
## Image intensifier on the drone camera: on by default at night, N toggles it.
var nv := false
var _throttle := 1.0
var _saved_fov := 62.0
var _shake := 0.0
var _t := 0.0
var _buzz: AudioStreamPlayer
var _warned_link := false
var _warned_batt := false


func _ready() -> void:
	_buzz = AudioStreamPlayer.new()
	_buzz.bus = "Effects"
	_buzz.stream = SFX.stream("buzz")
	_buzz.volume_db = -60.0
	add_child(_buzz)


func _touch() -> bool:
	return DisplayServer.is_touchscreen_available()


## Link range in world units: past this distance the drone flies on its own.
func link_range() -> float:
	return float(GS.WEAPONS["drone"].get("link", 1500.0))


func enter(d, from_view: String) -> void:
	active = true
	drone = d
	return_view = from_view
	signal_q = 1.0
	boost = false
	_throttle = 1.0
	nv = game.map.night > 0.4
	_warned_link = false
	_warned_batt = false
	_saved_fov = cam.fov
	cam.fov = FOV
	d.take_control()
	if _buzz.stream != null:
		_buzz.play()
	refresh_capture()
	game.hud.log_event(GS.t("Пульт FPV: принято управление дроном #%d") % int(d.serial), Color(0.5, 1.0, 0.8))


func exit() -> void:
	active = false
	if drone != null and is_instance_valid(drone):
		drone.release_control()
	drone = null
	boost = false
	_buzz.stop()
	cam.fov = _saved_fov
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


## The ram hit landed while the player was flying: feedback on the console itself.
func on_hit(e) -> void:
	shake(0.8)
	if osd != null:
		var txt := GS.t("ТАРАН!") if e.dead else GS.t("ПОПАДАНИЕ — ЦЕЛЬ ДЕРЖИТСЯ")
		osd.kill(txt, Color(0.4, 1.0, 0.6) if e.dead else Color(1.0, 0.8, 0.35))


## Takes over `d` without leaving the console (Space, or when the flown drone is gone).
func adopt(d) -> void:
	if drone != null and is_instance_valid(drone) and drone != d:
		drone.release_control()
	drone = d
	d.take_control()
	signal_q = 1.0
	_warned_link = false
	_warned_batt = false
	game.hud.log_event(GS.t("Пульт FPV: переключение на дрон #%d") % int(d.serial), Color(0.5, 1.0, 0.8))
	SFX.play("click", -4.0)


## Hands the console to another drone in the air (Space). False if there is no other one.
func next_drone() -> bool:
	if game.drones.size() < 2:
		return false
	var i: int = game.drones.find(drone)
	var d = game.drones[(i + 1) % game.drones.size()]
	if d == drone:
		return false
	adopt(d)
	return true


## Touch: step the throttle without a mouse wheel.
func add_throttle(step: float) -> void:
	_throttle = clampf(_throttle + step, 0.25, 1.0)


func _process(delta: float) -> void:
	if not active:
		return
	refresh_capture()
	if drone == null or not is_instance_valid(drone):
		game.leave_fpv()
		return
	_t += delta
	# --- link budget: the picture breaks up long before the drone stops obeying
	var d_base: float = drone.position.distance_to(GS.base_pos)
	var lr := link_range()
	signal_q = clampf(1.0 - (d_base - lr * 0.55) / (lr * 0.45), 0.0, 1.0)
	if signal_q <= 0.0:
		if not _warned_link:
			_warned_link = true
			game.hud.alert(GS.t("СВЯЗЬ С ДРОНОМ ПОТЕРЯНА — дрон продолжит сам"), Color(1.0, 0.6, 0.2))
			game.hud.log_event(GS.t("Потеря сигнала: дрон перешёл на автономный режим"), Color(1.0, 0.6, 0.2))
		game.leave_fpv()
		return
	if drone.battery < 8.0 and not _warned_batt:
		_warned_batt = true
		game.hud.alert(GS.t("АККУМУЛЯТОР РАЗРЯЖЕН — ищите цель!"), Color(1.0, 0.5, 0.25))
	# --- sticks
	if not get_tree().paused and not _touch():
		var kx := 0.0
		var ky := 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kx -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kx += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			ky += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			ky -= 1.0
		if kx != 0.0 or ky != 0.0:
			drone.in_yaw = clampf(drone.in_yaw + kx * delta * 2.2, -1.0, 1.0)
			drone.in_pitch = clampf(drone.in_pitch + ky * delta * 2.2, -1.0, 1.0)
		boost = boost or Input.is_key_pressed(KEY_SHIFT)
	# the stick returns to centre when it is let go
	var decay := 1.0 - exp(-delta * STICK_DECAY)
	drone.in_yaw = lerpf(drone.in_yaw, 0.0, decay)
	drone.in_pitch = lerpf(drone.in_pitch, 0.0, decay)
	drone.in_throttle = _throttle * (1.35 if boost else 1.0)
	# --- camera rides the nose mount, tilted up the way a real FPV camera is
	var mount: Node3D = drone.cam_mount()
	var b: Basis = drone.global_transform.basis
	var eye: Vector3 = mount.global_position
	var vib := (0.035 + 0.05 * clampf(drone.speed / maxf(drone.max_speed, 1.0), 0.0, 1.0)) * (1.6 if boost else 1.0)
	var jitter: Vector3 = b.x * sin(_t * 61.0) * vib + b.y * sin(_t * 47.0) * vib
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		jitter += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.5
	cam.global_position = eye + jitter
	var look: Vector3 = (-b.z).rotated(b.x.normalized(), deg_to_rad(12.0))
	cam.look_at(cam.global_position + look, b.y)
	cam.fov = lerpf(cam.fov, FOV + (10.0 if boost else 0.0), 1.0 - exp(-delta * 6.0))
	# --- rotor noise follows the throttle
	_buzz.volume_db = linear_to_db(clampf(0.35 + 0.45 * drone.in_throttle, 0.0, 1.0)) - 8.0
	_buzz.pitch_scale = clampf(0.8 + 0.5 * drone.speed / maxf(drone.max_speed, 1.0) + (0.15 if boost else 0.0), 0.6, 1.9)


## The threat closest to the centre of the feed — what the OSD boxes and ranges.
func feed_target():
	if drone == null or not is_instance_valid(drone):
		return null
	var best = null
	var best_a := deg_to_rad(38.0)
	var fwd := -cam.global_transform.basis.z
	for e in game.enemies:
		if e.dead:
			continue
		var a := fwd.angle_to(e.position - cam.global_position)
		if a < best_a:
			best_a = a
			best = e
	return best


## Touch "РАЗГОН" button and the shared trigger plumbing.
func set_trigger(on: bool) -> void:
	boost = on


func _unhandled_input(event: InputEvent) -> void:
	if not active or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	if drone == null or not is_instance_valid(drone):
		return
	var sens: float = float(GS.settings.sens)
	var inv := -1.0 if bool(GS.settings.invert_y) else 1.0
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		drone.in_yaw = clampf(drone.in_yaw + mm.relative.x * STICK_GAIN * sens, -1.0, 1.0)
		drone.in_pitch = clampf(drone.in_pitch - mm.relative.y * STICK_GAIN * sens * inv, -1.0, 1.0)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		drone.in_yaw = clampf(drone.in_yaw + sd.relative.x * STICK_GAIN * 1.8 * sens, -1.0, 1.0)
		drone.in_pitch = clampf(drone.in_pitch - sd.relative.y * STICK_GAIN * 1.8 * sens * inv, -1.0, 1.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not mb.pressed:
					boost = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					add_throttle(0.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					add_throttle(-0.12)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match GS.action_of((event as InputEventKey).keycode):
			"fpv_next":
				if not next_drone():
					game.hud.alert(GS.t("В воздухе больше нет дронов"), Color(1.0, 0.7, 0.3))
			"fpv_home":
				drone.order_home()
				game.hud.log_event(GS.t("Дрон #%d отправлен на базу") % int(drone.serial), Color(0.6, 0.9, 1.0))
				game.leave_fpv()
