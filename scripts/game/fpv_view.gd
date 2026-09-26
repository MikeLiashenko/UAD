extends Node
## FPV console: the player takes the sticks of one interceptor drone and flies it into a target
## by hand. The camera rides the drone's nose camera, the video feed breaks up with distance
## from the base and the link drops past the control range — beyond it the drone finishes on
## its own. See scripts/game/drone.gd for the autonomous behaviour and scripts/ui/fpv_osd.gd
## for the overlay.
##
## Steering works like a flight game's mouse aim: the mouse (or a swipe) moves an aim point in
## the sky and the drone turns towards it as fast as it can; the picture follows the drone, so
## the centre of the screen is always where it is going. Near a threat the aim point is drawn
## gently onto the lead point — where to fly to meet it — and a ram on any threat counts.
##
## Controls: mouse / swipe — aim, W-S — throttle, A-D and the arrows — turn, Shift or LMB —
## boost, Space — next drone, R — send home, C / V / Esc — back to the previous view.

const Bullet = preload("res://scripts/game/bullet.gd")

const FOV := 96.0
## Radians of aim per pixel of mouse travel (times the sensitivity setting).
const AIM_GAIN := 0.0026
## Keyboard turn rates, rad/s, and throttle change per second.
const KEY_YAW := 1.4
const KEY_PITCH := 1.0
const KEY_THROTTLE := 0.7
## The aim point is pulled onto the lead point inside this angle...
const ASSIST_CONE := deg_to_rad(9.0)
## ...by up to this many rad/s (stronger the closer the aim already is).
const ASSIST_RATE := 1.1
## The aim may not point steeper than this up or down.
const MAX_ELEV := deg_to_rad(80.0)

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
## The camera picks plain / night vision by the light (proper night only: at dusk the plain
## camera still sees more) until the pilot presses N.
var nv_auto := true
var _throttle := 1.0
## Where the pilot steers: a world direction (drone.aim follows it).
var aim := Vector3.FORWARD
## Lead point of the locked threat, world space (Vector3.INF when there is none).
var lead := Vector3.INF
## The picture's own orientation, smoothed so the feed never jerks.
var _view: Basis = Basis()
var _roll := 0.0
var _saved_fov := 62.0
var _shake := 0.0
var _t := 0.0
var _buzz: AudioStreamPlayer
var _warned_link := false
var _warned_batt := false
## Seconds of "no signal" left after the flown drone is gone (the picture freezes into static).
var lost_t := 0.0


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
	nv_auto = true
	nv = game.map.night > 0.65
	_warned_link = false
	_warned_batt = false
	lost_t = 0.0
	_saved_fov = cam.fov
	cam.fov = FOV
	d.take_control()
	GS.stats.fpv_flights = int(GS.stats.get("fpv_flights", 0)) + 1
	aim = _start_aim(d)
	_view = Basis.looking_at(aim, Vector3.UP)
	_roll = 0.0
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


## The flown drone rammed, crashed or ran dry: the feed breaks into static for a moment.
func feed_lost() -> void:
	drone = null # it is being removed: no hand-over, its commitment went with it
	boost = false
	lost_t = 1.3
	if osd != null and osd._kill_t <= 0.0:
		osd.kill(GS.t("ДРОН ПОТЕРЯН"), Color(1.0, 0.55, 0.3))


## Takes over `d` without leaving the console (Space, or when the flown drone is gone).
func adopt(d) -> void:
	lost_t = 0.0
	if drone != null and is_instance_valid(drone) and drone != d:
		drone.release_control()
	drone = d
	d.take_control()
	aim = _start_aim(d)
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


## Where the ring starts when a drone is taken over: at its target, or level ahead — not up the
## steep climb the swarm flies, where the pilot would see nothing but sky.
func _start_aim(d) -> Vector3:
	var t = d.target
	if t != null and is_instance_valid(t) and not t.dead:
		return (t.position - d.position).normalized()
	var v: Vector3 = d.vel
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.01 else Vector3.FORWARD


## Turns the aim point: yaw around the vertical, pitch up / down, never past MAX_ELEV.
func turn_aim(yaw: float, pitch: float) -> void:
	var a := aim.rotated(Vector3.UP, -yaw)
	var flat := Vector2(a.x, a.z).length()
	var elev := clampf(atan2(a.y, flat) + pitch, -MAX_ELEV, MAX_ELEV)
	var h := Vector2(a.x, a.z).normalized() if flat > 0.0001 else Vector2(0, -1)
	aim = Vector3(h.x * cos(elev), sin(elev), h.y * cos(elev)).normalized()


## Touch: step the throttle without a mouse wheel.
func add_throttle(step: float) -> void:
	_throttle = clampf(_throttle + step, 0.25, 1.0)


func _process(delta: float) -> void:
	if not active:
		return
	refresh_capture()
	if drone == null or not is_instance_valid(drone):
		drone = null
		lost_t -= delta
		if lost_t <= 0.0:
			if not game.drones.is_empty():
				adopt(game.drones[game.drones.size() - 1])
			else:
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
			GS.stats.fpv_link_lost = int(GS.stats.get("fpv_link_lost", 0)) + 1
		game.leave_fpv()
		return
	if drone.battery < 8.0 and not _warned_batt:
		_warned_batt = true
		game.hud.alert(GS.t("АККУМУЛЯТОР РАЗРЯЖЕН — ищите цель!"), Color(1.0, 0.5, 0.25))
	# --- keys: W-S throttle, A-D / arrows turn the aim
	if not get_tree().paused and not _touch():
		var kx := 0.0
		var ky := 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kx -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kx += 1.0
		if Input.is_key_pressed(KEY_UP):
			ky += 1.0
		if Input.is_key_pressed(KEY_DOWN):
			ky -= 1.0
		if kx != 0.0 or ky != 0.0:
			turn_aim(kx * KEY_YAW * delta, ky * KEY_PITCH * delta * (-1.0 if bool(GS.settings.invert_y) else 1.0))
		if Input.is_key_pressed(KEY_W):
			add_throttle(KEY_THROTTLE * delta)
		if Input.is_key_pressed(KEY_S):
			add_throttle(-KEY_THROTTLE * delta)
		boost = boost or Input.is_key_pressed(KEY_SHIFT)
	if nv_auto:
		nv = game.map.night > 0.65
	_assist(delta)
	drone.aim = aim
	drone.in_throttle = _throttle * (1.35 if boost else 1.0)
	# --- the picture: straight down the flight path from the nose, banking into turns, smoothed
	var fwd: Vector3 = drone.vel.normalized() if drone.vel.length_squared() > 0.01 else aim
	_roll = lerpf(_roll, -float(drone.in_yaw) * 0.45, 1.0 - exp(-delta * 4.0))
	var want := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.FORWARD)
	want = want.rotated(want.z.normalized(), _roll)
	_view = _view.slerp(want, 1.0 - exp(-delta * 14.0)).orthonormalized()
	var jitter := Vector3.ZERO
	if boost:
		jitter += (_view.x * sin(_t * 53.0) + _view.y * sin(_t * 41.0)) * 0.03
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		jitter += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.5
	cam.global_transform = Transform3D(_view, (drone.cam_mount() as Node3D).global_position + jitter)
	cam.fov = lerpf(cam.fov, FOV + (10.0 if boost else 0.0), 1.0 - exp(-delta * 6.0))
	# --- rotor noise follows the throttle
	_buzz.volume_db = linear_to_db(clampf(0.35 + 0.45 * drone.in_throttle, 0.0, 1.0)) - 8.0
	_buzz.pitch_scale = clampf(0.8 + 0.5 * drone.speed / maxf(drone.max_speed, 1.0) + (0.15 if boost else 0.0), 0.6, 1.9)


## Locks the threat the pilot is aiming at and draws the aim point onto its lead point, gently
## and only when it is already close — the pilot still flies, the console just steadies the hand.
func _assist(delta: float) -> void:
	lead = Vector3.INF
	var best = null
	var best_a := ASSIST_CONE * 1.6
	for e in game.enemies:
		if e.dead or GS.eff(drone.weapon_id, e) <= 0.0:
			continue
		var a := aim.angle_to(e.position - drone.position)
		if a < best_a:
			best_a = a
			best = e
	if best != null:
		drone.lock(best)
	var t = drone.target
	if t == null or not is_instance_valid(t) or t.dead:
		return
	lead = Bullet.lead(drone.position, t.position, t.vel, maxf(drone.speed, 40.0))
	var to_lead: Vector3 = (lead - drone.position).normalized()
	var off := aim.angle_to(to_lead)
	if off < ASSIST_CONE and off > 0.0001:
		var k := 1.0 - off / ASSIST_CONE
		aim = aim.slerp(to_lead, clampf(ASSIST_RATE * (0.35 + 0.65 * k) * delta / off, 0.0, 1.0)).normalized()


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
		turn_aim(mm.relative.x * AIM_GAIN * sens, -mm.relative.y * AIM_GAIN * sens * inv)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		turn_aim(sd.relative.x * AIM_GAIN * 1.6 * sens, -sd.relative.y * AIM_GAIN * 1.6 * sens * inv)
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
