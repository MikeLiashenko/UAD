extends Node
## Orbit camera around a ground focus point. Mouse: LMB-drag pan, RMB-drag rotate, wheel zoom.
## Keyboard: WASD/arrows pan, Q/E rotate, +/- zoom. Touch: drag pan, pinch zoom.
## A short LMB press/release without dragging is reported as `clicked` (target selection).

signal clicked(pos: Vector2)

const DRAG_THRESHOLD := 10.0

var cam: Camera3D
var target := Vector3.ZERO
var yaw := 0.4
var pitch := 0.5
var dist := 380.0
var bounds := 1150.0

var _t_target := Vector3.ZERO
var _t_yaw := 0.4
var _t_pitch := 0.5
var _t_dist := 380.0
var _left := false
var _right := false
var _moved := false
var _press := Vector2.ZERO
var _touches := {}
var _pinch := 0.0
var _shake := 0.0


func _ready() -> void:
	_t_target = target
	_t_yaw = yaw
	_t_pitch = pitch
	_t_dist = dist


func focus(p: Vector3) -> void:
	_t_target = Vector3(p.x, 0, p.z)


func zoom(f: float) -> void:
	_t_dist = clampf(_t_dist * f, 40.0, 1600.0)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _forward() -> Vector3:
	return Vector3(-sin(_t_yaw), 0, -cos(_t_yaw))


func _right_vec() -> Vector3:
	return Vector3(cos(_t_yaw), 0, -sin(_t_yaw))


func _process(delta: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y -= 1
	if mv != Vector2.ZERO:
		_t_target += (_right_vec() * mv.x + _forward() * mv.y) * _t_dist * 1.1 * delta
	if Input.is_key_pressed(KEY_Q):
		_t_yaw += 1.4 * delta
	if Input.is_key_pressed(KEY_E):
		_t_yaw -= 1.4 * delta
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom(1.0 - delta * 1.5)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom(1.0 + delta * 1.5)
	_t_target.x = clampf(_t_target.x, -bounds, bounds)
	_t_target.z = clampf(_t_target.z, -bounds, bounds)
	_t_pitch = clampf(_t_pitch, 0.06, 1.35)

	var k := 1.0 - exp(-delta * 9.0)
	target = target.lerp(_t_target, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	dist = lerpf(dist, _t_dist, k)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var shake_off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 4.0
	cam.global_position = target + off + shake_off
	cam.look_at(target + Vector3(0, dist * 0.18, 0) + shake_off, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom(1.14)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left = true
					_moved = false
					_press = mb.position
				else:
					if _left and not _moved and _touches.size() < 2:
						clicked.emit(mb.position)
					_left = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_right = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left:
			if mm.position.distance_to(_press) > DRAG_THRESHOLD:
				_moved = true
			if _moved and _touches.size() < 2:
				var s := _t_dist * 0.0022
				_t_target -= _right_vec() * mm.relative.x * s
				_t_target += _forward() * mm.relative.y * s
		if _right:
			_t_yaw -= mm.relative.x * 0.005
			_t_pitch += mm.relative.y * 0.004
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch = 0.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_moved = true
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _pinch > 0.0 and d > 1.0:
				zoom(_pinch / d)
			_pinch = d
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / (event as InputEventMagnifyGesture).factor)
