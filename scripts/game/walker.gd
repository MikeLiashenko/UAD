extends Node
## On-foot first-person view ("прогулка по городу"). Collides with every building footprint,
## climbs onto bridge decks, can't walk into the Dnipro. WASD / arrows move, Shift runs,
## Space jumps, mouse looks. Touch: left half of the screen = joystick, right half = look.

const EYE := 1.7
const WALK := 4.5
const RUN := 11.0
const JUMP := 6.5
const GRAVITY := 20.0
const RADIUS := 0.45

var game
var map
var cam: Camera3D
var active := false
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var on_floor := true
var _bob := 0.0
var _last_step := 0.0
var _shake := 0.0
var _saved_fov := 62.0
var _jump_held := false
var _move_touch := -1
var _move_origin := Vector2.ZERO
var _move_vec := Vector2.ZERO
var test_forward := false


func enter(at: Vector3, face_yaw: float) -> void:
	active = true
	pos = find_free(at)
	vel = Vector3.ZERO
	yaw = face_yaw
	pitch = 0.08
	_saved_fov = cam.fov
	cam.fov = 72.0
	refresh_capture()


func exit() -> void:
	active = false
	_move_touch = -1
	_move_vec = Vector2.ZERO
	cam.fov = _saved_fov
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func refresh_capture() -> void:
	if not active or DisplayServer.is_touchscreen_available():
		if active:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var free: bool = get_tree().paused or Input.is_key_pressed(KEY_ALT) or game.game_over or game.wants_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Nearest free, dry spot to `p` (spiral search).
func find_free(p: Vector3) -> Vector3:
	var r := 0.0
	while r < 300.0:
		var steps := maxi(1, int(r / 4.0))
		for i in steps:
			var a := TAU * i / steps
			var x := p.x + cos(a) * r
			var z := p.z + sin(a) * r
			if not _blocked(x, z, 0.0) and map.water_dist(x, z) > 1.0:
				return Vector3(x, _floor_at(x, z), z)
		r += 4.0
	return Vector3(p.x, 0, p.z)


## Walkable height here: bridge deck or the ground.
func _floor_at(x: float, z: float) -> float:
	var bi: int = map.building_at(x, z)
	if bi >= 0 and map.is_deck(bi):
		return map.fp_center[bi].y
	return 0.0


func _blocked_point(x: float, z: float, y: float) -> bool:
	if absf(x) > 995.0 or absf(z) > 995.0:
		return true
	var bi: int = map.building_at(x, z)
	if bi >= 0:
		if map.is_deck(bi):
			return false
		return y < map.fp_center[bi].y - 0.3
	return map.water_dist(x, z) < 0.0


func _blocked(x: float, z: float, y: float) -> bool:
	if _blocked_point(x, z, y):
		return true
	for o in [Vector2(RADIUS, 0), Vector2(-RADIUS, 0), Vector2(0, RADIUS), Vector2(0, -RADIUS)]:
		if _blocked_point(x + o.x, z + o.y, y):
			return true
	return false


func _process(delta: float) -> void:
	if not active:
		return
	refresh_capture()
	var input := _move_vec
	if test_forward:
		input.y = 1.0
	if not get_tree().paused:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input.y -= 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input.x += 1.0
	if input.length() > 1.0:
		input = input.normalized()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var running := Input.is_key_pressed(KEY_SHIFT) or _move_vec.length() > 0.95
	var wish := (fwd * input.y + right * input.x) * (RUN if running else WALK)
	var k := 1.0 - exp(-delta * (12.0 if on_floor else 2.0))
	vel.x = lerpf(vel.x, wish.x, k)
	vel.z = lerpf(vel.z, wish.z, k)
	var jump := Input.is_key_pressed(KEY_SPACE)
	if jump and not _jump_held and on_floor:
		vel.y = JUMP
		on_floor = false
	_jump_held = jump
	vel.y -= GRAVITY * delta
	# move with per-axis sliding against walls
	var nx := pos.x + vel.x * delta
	if not _blocked(nx, pos.z, pos.y):
		pos.x = nx
	else:
		vel.x = 0.0
	var nz := pos.z + vel.z * delta
	if not _blocked(pos.x, nz, pos.y):
		pos.z = nz
	else:
		vel.z = 0.0
	pos.y += vel.y * delta
	var fl := _floor_at(pos.x, pos.z)
	if pos.y <= fl:
		# stepping up onto a bridge deck works like climbing the stairs
		pos.y = move_toward(pos.y, fl, delta * 30.0) if fl - pos.y > 0.2 else fl
		vel.y = 0.0
		on_floor = true
	elif pos.y > fl + 0.05:
		on_floor = false
	# head bob + footsteps
	var hs := Vector2(vel.x, vel.z).length()
	if on_floor and hs > 0.6:
		_bob += delta * hs * 1.7
		if int(_bob / PI) != int(_last_step / PI):
			SFX.play("step", -16.0 + (3.0 if hs > 7.0 else 0.0), 1.0 + randf_range(-0.1, 0.1))
		_last_step = _bob
	var bob := sin(_bob * 2.0) * 0.045 * clampf(hs / WALK, 0.0, 1.6)
	var so := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		so = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
	var eye := pos + Vector3(0, EYE + bob, 0) + so
	cam.global_position = eye
	var look := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	cam.look_at(eye + look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not active or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	var sens: float = float(GS.settings.sens)
	var inv := -1.0 if bool(GS.settings.invert_y) else 1.0
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.0024 * sens
		pitch = clampf(pitch - mm.relative.y * 0.0024 * sens * inv, -1.45, 1.5)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var half_w: float = get_viewport().get_visible_rect().size.x * 0.5
		if st.pressed and st.position.x < half_w and _move_touch < 0:
			_move_touch = st.index
			_move_origin = st.position
		elif not st.pressed and st.index == _move_touch:
			_move_touch = -1
			_move_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _move_touch:
			var d := (sd.position - _move_origin) / 90.0
			_move_vec = Vector2(d.x, -d.y).limit_length(1.0)
		else:
			yaw -= sd.relative.x * 0.005 * sens
			pitch = clampf(pitch - sd.relative.y * 0.005 * sens * inv, -1.45, 1.5)
