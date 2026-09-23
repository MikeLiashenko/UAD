extends Node
## Gunner view ("вид с базы"). The camera sits at the selected AA system and looks through its
## sight. Mouse (captured) or touch-drag aims; LMB fires guns / launches a missile at a locked
## target; RMB or wheel zooms; N toggles the night-vision sight; hold Alt for a free cursor.

const FOV_MIN := 10.0
const FOV_MAX := 75.0
const LOCK_TIME := 0.7

var game
var cam: Camera3D
var active := false
var yaw := 0.0
var pitch := 0.35
var fov := 70.0
var zoom_fov := 70.0
var trigger := false
var candidate = null
var lock = null
var lock_t := 0.0
var lock_ready := false
var nv := false
var _shake := 0.0
var _saved_fov := 62.0


func _touch() -> bool:
	return DisplayServer.is_touchscreen_available()


func weapon():
	return game.weapons.get(game.selected_weapon)


func aim_dir() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func enter() -> void:
	active = true
	yaw = game.rig.yaw
	pitch = 0.35
	zoom_fov = 70.0
	fov = 70.0
	_saved_fov = cam.fov
	trigger = false
	refresh_capture()
	var w = weapon()
	if w:
		w.manual = true


func exit() -> void:
	active = false
	trigger = false
	candidate = null
	lock = null
	nv = false
	for id in game.weapons:
		var w = game.weapons[id]
		w.manual = false
		w.trigger = false
	cam.fov = _saved_fov
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func on_weapon_changed(prev_id: String) -> void:
	var p = game.weapons.get(prev_id)
	if p:
		p.manual = false
		p.trigger = false
	var w = weapon()
	if w:
		w.manual = active
	lock = null
	lock_ready = false


func refresh_capture() -> void:
	if not active or _touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var free: bool = get_tree().paused or Input.is_key_pressed(KEY_ALT) or game.game_over or game.wants_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func zoom(f: float) -> void:
	zoom_fov = clampf(zoom_fov * f, FOV_MIN, FOV_MAX)


func _process(delta: float) -> void:
	if not active:
		return
	refresh_capture()
	var w = weapon()
	if w == null:
		return
	var dir := aim_dir()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var eye: Vector3 = w.eye_pos() - flat * 3.5
	fov = lerpf(fov, zoom_fov, 1.0 - exp(-delta * 10.0))
	cam.fov = fov
	var so := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		so = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	cam.global_position = eye + so
	cam.look_at(eye + dir * 100.0 + so * 3.0, Vector3.UP)
	candidate = _find_candidate(dir)
	var conv := 450.0
	if candidate != null:
		conv = cam.global_position.distance_to(candidate.position)
	w.manual = true
	w.manual_dir = dir
	w.manual_point = eye + dir * conv
	w.trigger = trigger and String(w.def.kind) == "gun"
	if String(w.def.kind) != "gun":
		if candidate != null and w.can_engage(candidate) and w.in_range(candidate):
			if candidate != lock:
				lock = candidate
				lock_t = 0.0
				lock_ready = false
			lock_t += delta
			if not lock_ready and lock_t >= LOCK_TIME:
				lock_ready = true
				SFX.play("click", -2.0, 1.8)
		else:
			lock = null
			lock_ready = false
			lock_t = 0.0
	game.locked = candidate


## The threat closest to the crosshair inside the sight's cone (narrower when zoomed in).
func _find_candidate(dir: Vector3):
	var best = null
	var best_a := deg_to_rad(7.0) * fov / 70.0 + 0.01
	for e in game.enemies:
		if e.dead:
			continue
		var a := dir.angle_to(e.position - cam.global_position)
		if a < best_a:
			best = e
			best_a = a
	return best


## Sends one interceptor — a missile, or a drone from the rack — at the locked target.
func launch() -> void:
	var w = weapon()
	if w == null or String(w.def.kind) == "gun":
		return
	if lock != null and lock_ready and is_instance_valid(lock) and not lock.dead:
		if w.launch_at(lock):
			shake(0.5 if String(w.def.kind) == "missile" else 0.2)
			lock_ready = false
			lock_t = 0.0
			if String(w.def.kind) == "drone":
				game.hud.log_event(GS.t("Дрон пошёл на цель — [C] взять управление"), Color(0.5, 1.0, 0.8))
	elif lock != null:
		game.hud.alert(GS.t("ЗАХВАТ ЦЕЛИ… удерживайте прицел"), Color(1.0, 0.8, 0.3))
	else:
		game.hud.alert(GS.t("НЕТ ЗАХВАТА — наведите прицел на цель в зоне поражения"), Color(1.0, 0.6, 0.2))


func set_trigger(on: bool) -> void:
	var w = weapon()
	if w == null:
		return
	if String(w.def.kind) == "gun":
		trigger = on
	elif on:
		launch()


func _unhandled_input(event: InputEvent) -> void:
	if not active or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return # touch handled below; on-screen FIRE button fires
	var sens: float = float(GS.settings.sens) * fov / 70.0
	var inv := -1.0 if bool(GS.settings.invert_y) else 1.0
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.0024 * sens
		pitch = clampf(pitch - mm.relative.y * 0.0024 * sens * inv, -0.12, 1.52)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		yaw -= sd.relative.x * 0.004 * sens
		pitch = clampf(pitch - sd.relative.y * 0.004 * sens * inv, -0.12, 1.52)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not mb.pressed:
					set_trigger(mb.pressed)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					zoom_fov = 20.0 if zoom_fov > 40.0 else 70.0
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom(0.85)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom(1.18)
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / (event as InputEventMagnifyGesture).factor)
