extends Node3D
## Plays back the nightly highlight reel: the clips the city filmed are re-staged in the real
## Kyiv — the camera stands where the phone stood, the target flies the course it flew, the
## interceptor comes in and the sky lights up. A title card, six clips shot six different ways
## and a sign-off make the compilation the channel publishes every morning.
##
## Everything here is direction: which shot a clip gets, where the operator stood, when the bang
## reaches them (sound is slower than light, so the flash comes first), when the cut drops into
## slow motion. The overlay that frames all this as a phone video is scripts/ui/video_ui.gd.

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

signal clip_started(index: int)
signal finished

## How a clip was filmed. The editor never runs the same shot twice in a row.
##   balcony — off to the side and high up, the classic phone-over-the-railing shot
##   street  — down among the houses, the operator swings the phone to follow
##   pass    — almost under the track: the thing goes over the camera
##   dash    — from a car on the move, steady and wide
##   window  — phone propped against the glass, barely moving
##   onboard — the camera the interceptor itself carries
const STYLES := ["balcony", "street", "pass", "dash", "window", "onboard"]
## Seconds of debris and reaction after the intercept; the rest of the clip is the approach.
## These are clip seconds, not wall clock: slow motion stretches them back out, which is why a
## clip is cut short of the five seconds the channel advertises and still plays for five.
const TAIL := 1.5
## The title card and the sign-off, in seconds.
const INTRO := 2.0
const OUTRO := 3.2
## Slow motion around the hit: when it starts, when it lets go, and how far it slows down.
const SLOW_IN := 0.3
const SLOW_OUT := 0.7
const SLOW_RATE := 0.35
## How much wall clock the slow motion adds to a clip. The clip is shortened by exactly this
## much so the compilation still runs the thirty seconds the channel promises (measured, not
## derived: the ramps in and out of bullet time make the arithmetic messy).
const SLOW_STRETCH := 1.0
## Speed of sound: the bang reaches the phone after the flash, and so does the shake.
const MACH := 340.0

var game
var cam: Camera3D
var video := {}
var clips: Array = []
var index := -1
var playing := false
## "intro" (title card) | "clip" | "outro" (sign-off) — what is on screen right now.
var phase := "intro"
## Play head inside the current clip or card, in clip seconds.
var t := 0.0
## 0 .. 1, the white cut between clips; drawn by the overlay.
var flash := 0.0
## 0 .. 1 while the action runs in slow motion; the overlay badges it.
var slow := 0.0
## Kick the frame takes when the blast wave arrives.
var shake := 0.0

var _len := 5.0
var _hit_t := 3.1
var _hit_p := Vector3.ZERO
var _vel := Vector3.FORWARD
var _style := "balcony"
var _last_style := ""
var _eye := Vector3.ZERO
var _eye_to := Vector3.ZERO
var _fov0 := 38.0
var _fov1 := 26.0
var _wob := 1.0
var _jit := 0.16
var _lag := 5.0
var _look := Vector3.ZERO
var _actor: Node3D
var _shot: Node3D
var _shot_kind := "gun"
var _shot_from := Vector3.ZERO
var _shot_ctrl := Vector3.ZERO
var _shot_travel := 1.6
var _tracers: Array = []
var _ride_eye := Vector3.ZERO
var _ride_dir := Vector3.FORWARD
var _boomed := false
var _cues: Array = []
var _saved_fov := 62.0
var _saved_night := 1.0
var _saved_music := ""
var _orbit := 0.0
var _rng := RandomNumberGenerator.new()


# --- Timing ----------------------------------------------------------------------------------
## Length of whatever is on screen: the current clip, or the card.
func clip_len() -> float:
	match phase:
		"intro":
			return INTRO
		"outro":
			return OUTRO
	return _len


## What the channel claims in the caption: six clips of five seconds.
func nominal_len() -> float:
	return GS.VIDEO_CLIP_LEN * float(clips.size())


func total_len() -> float:
	return nominal_len() + INTRO + OUTRO


## 0 .. 1 through the whole compilation, cards included.
func progress() -> float:
	var done := 0.0
	match phase:
		"intro":
			done = t
		"outro":
			done = INTRO + nominal_len() + t
		_:
			done = INTRO + GS.VIDEO_CLIP_LEN * (float(index) + clip_k())
	return clampf(done / maxf(total_len(), 0.001), 0.0, 1.0)


func clip_k() -> float:
	return clampf(t / maxf(clip_len(), 0.001), 0.0, 1.0)


func style() -> String:
	return _style if phase == "clip" else phase


func current() -> Dictionary:
	return clips[index] if index >= 0 and index < clips.size() else {}


# --- Playback --------------------------------------------------------------------------------
func play(v: Dictionary) -> void:
	video = v
	clips = v.get("clips", [])
	if clips.is_empty():
		finished.emit()
		return
	_rng.seed = int(v.get("day", 1)) * 7919
	playing = true
	index = -1
	phase = "intro"
	t = 0.0
	flash = 1.0
	_last_style = ""
	# nothing in the session may tick while the cut is on screen: no clock, no raid, no day
	get_tree().paused = true
	_saved_fov = cam.fov
	_saved_night = game.map.night
	# the video was shot at night, so the city — and the music under it — go back to night
	game.map.set_night(1.0)
	_saved_music = SFX.music_track()
	SFX.play_music("night")
	_orbit = _rng.randf() * TAU
	_card_camera(0.0)


func stop() -> void:
	if not playing:
		return
	playing = false
	_clear()
	cam.fov = _saved_fov
	game.map.set_night(_saved_night)
	SFX.play_music(_saved_music)
	finished.emit()


## Space or the button: straight on to the next clip, or out of a card.
func skip() -> void:
	if playing:
		_advance()


func _clear() -> void:
	for n in [_actor, _shot]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	for tr in _tracers:
		var node = tr.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_tracers.clear()
	_cues.clear()
	_actor = null
	_shot = null


## Title card, then the clips, then the sign-off, then out.
func _advance() -> void:
	_clear()
	flash = 1.0
	t = 0.0
	slow = 0.0
	match phase:
		"intro":
			phase = "clip"
			index = -1
			_begin_clip()
		"clip":
			if index + 1 >= clips.size():
				phase = "outro"
			else:
				_begin_clip()
		_:
			stop()


func _begin_clip() -> void:
	index += 1
	if index >= clips.size():
		phase = "outro"
		return
	_boomed = false
	var c: Dictionary = clips[index]
	_hit_p = _vec(c.get("p", [0, 100, 0]))
	_vel = _vec(c.get("v", [0, 0, -40]))
	if _vel.length_squared() < 1.0:
		_vel = Vector3(0, 0, -40)
	_style = _pick_style(c)
	_last_style = _style
	_len = GS.VIDEO_CLIP_LEN - SLOW_STRETCH + _rng.randf_range(-0.15, 0.3)
	_hit_t = _len - TAIL
	# the camera goes up first: the sound cues need to know how far the operator is standing
	_shot_from = GS.base_pos + Vector3(0, 6, 0)
	_setup_camera()
	_setup_shot(String(c.get("by", "mg")))
	_spawn_actor(String(c.get("variant", c.get("type", "shahed"))))
	# the operator already has the target in frame when the clip starts
	_look = _actor.position
	_clip_camera(0.0)
	clip_started.emit(index)


## Picks how this one was filmed: never the same shot twice, and only a guided weapon carries a
## camera of its own.
func _pick_style(c: Dictionary) -> String:
	var def: Dictionary = GS.WEAPONS.get(String(c.get("by", "mg")), {})
	var kind := String(def.get("kind", "gun"))
	var pool: Array = STYLES.duplicate()
	if kind == "gun":
		pool.erase("onboard")
	else:
		pool.append("onboard") # when there is an onboard camera, it is worth showing
	pool.erase(_last_style)
	return String(pool[_rng.randi() % pool.size()])


func _spawn_actor(type: String) -> void:
	_actor = Meshes.enemy_model(type)
	# a touch bigger than life: on a phone-sized frame the real thing is a speck
	_actor.scale = Vector3.ONE * (1.25 if _style == "pass" or _style == "onboard" else 1.6)
	add_child(_actor)
	_actor.position = _hit_p - _vel * _hit_t
	# on a night phone video the target reads as a bright flickering dot with a hot trail
	_actor.add_child(Fx.glare(Color(1.0, 0.6, 0.25), 2.6, 3.2, 0.0016, 0.7, 0.8))
	var trail := Fx.exhaust(Color(1.0, 0.5, 0.15), 26, 0.9, 0.9)
	trail.local_coords = false
	trail.emitting = true
	_actor.add_child(trail)
	# a Shahed is heard long before anyone sees it
	if GS.kind_of(type) == "shahed":
		_cue(0.1, "buzz", -17.0, 0.85)


# --- Camera ----------------------------------------------------------------------------------
## Places the operator for the chosen shot: where they stood, where they drift to, how wide the
## phone is zoomed and how badly their hands shake.
func _setup_camera() -> void:
	var p := _hit_p
	var side := Vector3(-_vel.z, 0, _vel.x).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	if _rng.randf() < 0.5:
		side = -side
	var fwd := _vel.normalized()
	match _style:
		"street":
			var at1: Vector3 = p + side * _rng.randf_range(70.0, 115.0) - fwd * _rng.randf_range(0.0, 60.0)
			_eye = _open_eye(at1, 1.7)
			_eye_to = _eye + side * 2.0
			_fov0 = 46.0
			_fov1 = 30.0
			_wob = 1.4
			_jit = 0.22
			_lag = 3.4
		"pass":
			var at2: Vector3 = p + side * _rng.randf_range(16.0, 34.0) - fwd * _rng.randf_range(20.0, 70.0)
			_eye = _open_eye(at2, 1.7)
			_eye_to = _eye
			_fov0 = 64.0
			_fov1 = 50.0
			_wob = 1.1
			_jit = 0.3
			_lag = 2.4
		"dash":
			var at3: Vector3 = p + side * _rng.randf_range(120.0, 190.0)
			_eye = _open_eye(at3, 1.5)
			# a car does not stop to film: the whole clip rolls forward
			_eye_to = _eye + (fwd * 0.6 + side * 0.8).normalized() * 13.0 * _len
			_fov0 = 55.0
			_fov1 = 47.0
			_wob = 0.35
			_jit = 0.07
			_lag = 4.2
		"window":
			_eye = _window_eye(p, side)
			_eye_to = _eye
			_fov0 = 34.0
			_fov1 = 24.0
			_wob = 0.25
			_jit = 0.04
			_lag = 6.0
		"onboard":
			_eye = _shot_from
			_eye_to = _hit_p
			_fov0 = 74.0
			_fov1 = 64.0
			_wob = 0.5
			_jit = 0.12
			_lag = 9.0
		_:
			_eye = _filming_spot(p, _vel)
			_eye_to = _eye + side * _rng.randf_range(-1.5, 1.5)
			_fov0 = _rng.randf_range(34.0, 42.0)
			_fov1 = 26.0
			_wob = 1.0
			_jit = 0.16
			_lag = 5.0
	cam.fov = _fov0
	_ride_eye = _eye
	_ride_dir = (p - _eye).normalized()


## Nudges a spot out of the river and puts the eye above the ground — or above the roof, when
## the operator turns out to be standing on one.
func _open_eye(at: Vector3, h: float) -> Vector3:
	var best := at
	for i in 5:
		if game.map.zone_at(best.x, best.z) != GS.Zone.WATER:
			break
		best += Vector3(_rng.randf_range(-90.0, 90.0), 0, _rng.randf_range(-90.0, 90.0))
	return Vector3(best.x, game.map.ground_height(best.x, best.z) + h, best.z)


## A phone propped against the glass: a couple of floors below the roof of a block nearby.
func _window_eye(p: Vector3, side: Vector3) -> Vector3:
	var best := _open_eye(p + side * 150.0, 12.0)
	for i in 8:
		var at: Vector3 = p + side.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2)) * _rng.randf_range(110.0, 220.0)
		if game.map.building_at(at.x, at.z) < 0:
			continue
		var roof: float = game.map.ground_height(at.x, at.z)
		if roof < 9.0:
			continue
		best = Vector3(at.x, roof - _rng.randf_range(3.0, maxf(roof * 0.45, 3.5)), at.z)
		break
	return best


## Where the phone was held: off to the side of the track, out in the open and far enough back
## that the target sits high in the frame instead of behind the nearest tree.
func _filming_spot(p: Vector3, v: Vector3) -> Vector3:
	var side := Vector3(-v.z, 0, v.x).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var away: float = clampf(p.y * 0.85, 110.0, 240.0)
	var best := Vector3(p.x, 2.0, p.z) + side * away
	var best_score := -INF
	for i in 9:
		var dir: Vector3 = side.rotated(Vector3.UP, _rng.randf_range(-1.0, 1.0)) * (1.0 if i % 2 == 0 else -1.0)
		var at: Vector3 = p + dir * away * _rng.randf_range(0.85, 1.15)
		var ground: float = game.map.ground_height(at.x, at.z)
		var eye := Vector3(at.x, ground + _rng.randf_range(1.6, 3.0), at.z)
		var score: float = _rng.randf() * 3.0
		match game.map.zone_at(at.x, at.z):
			GS.Zone.WATER:
				score -= 60.0 # nobody films standing in the Dnipro
			GS.Zone.FOREST:
				score -= 25.0 # branches in the way
		if game.map.building_at(at.x, at.z) >= 0:
			score += 10.0 # a rooftop is a great vantage point
		# a tower right overhead, or a block between the phone and the target, ruins the shot
		if game.map.ceiling(at.x, at.z) > ground + 30.0:
			score -= 20.0
		var mid: Vector3 = eye.lerp(p, 0.45)
		if game.map.ceiling(mid.x, mid.z) > mid.y:
			score -= 35.0
		if score > best_score:
			best_score = score
			best = eye
	return best


func _vec(a) -> Vector3:
	var arr: Array = a if a is Array else [0, 0, 0]
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


# --- The interceptor -------------------------------------------------------------------------
## What comes in to kill it: a burst of tracers from the guns, a missile arcing over the city, or
## the drone itself. Everything is timed to arrive exactly on the beat.
func _setup_shot(by: String) -> void:
	var def: Dictionary = GS.WEAPONS.get(by, GS.WEAPONS["mg"])
	_shot_kind = String(def.get("kind", "gun"))
	_shot_from = GS.base_pos + Vector3(0, 6, 0)
	var dist: float = _shot_from.distance_to(_hit_p)
	# a missile lofts over the city instead of flying a taut string
	_shot_ctrl = _shot_from.lerp(_hit_p, 0.5) + Vector3(0, dist * 0.16, 0)
	match _shot_kind:
		"missile":
			_shot_travel = clampf(dist / 260.0, 1.2, 2.6)
			_shot = Node3D.new()
			add_child(_shot)
			_shot.add_child(Meshes.interceptor(by == "patriot" or by == "s300"))
			_shot.add_child(Fx.glare(Color(1.0, 0.85, 0.5), 3.0, 2.2, 0.0022, 0.6, 0.35))
			var plume := Fx.exhaust(Color(1.0, 0.7, 0.35), 40, 1.5, 1.7)
			plume.material_override = Fx.smoke_mat()
			plume.local_coords = false
			plume.emitting = true
			_shot.add_child(plume)
			_cue(_hit_t - _shot_travel + _ear(_shot_from), "launch", -9.0, 1.0)
		"drone":
			_shot_travel = clampf(dist / 150.0, 1.6, 3.2)
			_shot = Node3D.new()
			add_child(_shot)
			var d := Meshes.fpv_drone()
			d.scale = Vector3.ONE * 2.2
			_shot.add_child(d)
			_shot.add_child(Fx.glare(Color(0.4, 1.0, 0.6), 1.6, 1.2, 0.0018, 0.5, 1.4))
			_cue(_hit_t - 0.9, "prop", -14.0, 1.1)
		_:
			_shot_travel = clampf(dist / 900.0, 0.5, 1.3)
			_make_tracers(by)


## A burst on its way: the rounds leave the battery staggered and walk onto the target.
func _make_tracers(by: String) -> void:
	var def: Dictionary = GS.WEAPONS.get(by, {})
	# an autocannon throws fewer, fatter, slower rounds than a machine gun
	var heavy: bool = float(def.get("damage", 8.0)) >= 12.0
	var count: int = 7 if heavy else 11
	var gap: float = 0.13 if heavy else 0.07
	for i in count:
		var tracer := MeshInstance3D.new()
		tracer.mesh = Fx.cube(Vector3(0.5, 0.5, 14.0) if heavy else Vector3(0.32, 0.32, 9.0))
		tracer.material_override = Fx.glow(Color(1.0, 0.78, 0.32), 7.0)
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.visible = false
		add_child(tracer)
		# the last rounds of the burst are the ones that connect; the rest lead and trail it
		var miss := Vector3.ZERO
		if i < count - 2:
			miss = Vector3(_rng.randf_range(-7, 7), _rng.randf_range(-5, 6), _rng.randf_range(-7, 7))
		_tracers.append({"node": tracer, "off": float(count - 2 - i) * gap, "miss": miss})
	# the gunfire reaches the operator late, and only as a distant rattle
	var ear: float = _ear(_shot_from)
	for i in 3:
		_cue(_hit_t - _shot_travel + ear + float(i) * 0.22, "cannon" if heavy else "mg", -13.0, 1.0)


## Seconds the sound needs to travel from a point to the camera.
func _ear(from: Vector3) -> float:
	return minf(from.distance_to(_eye) / MACH, 1.4)


func _cue(at: float, sound: String, db: float, pitch: float) -> void:
	_cues.append({"t": at, "s": sound, "db": db, "p": pitch})


## The interceptor along its run: 0 at the battery, 1 on the target.
func _shot_pos(k: float) -> Vector3:
	match _shot_kind:
		"missile":
			return _shot_from.lerp(_shot_ctrl, k).lerp(_shot_ctrl.lerp(_hit_p, k), k)
		"drone":
			var base: Vector3 = _shot_from.lerp(_hit_p, k)
			var side: Vector3 = (_hit_p - _shot_from).cross(Vector3.UP).normalized()
			# an FPV drone never flies straight: it weaves in and settles on the target
			return base + side * sin(k * 9.0) * 7.0 * (1.0 - k) + Vector3(0, sin(k * 5.5) * 4.0 * (1.0 - k), 0)
	return _shot_from.lerp(_hit_p, k)


# --- Per frame -------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not playing:
		return
	# hold the session frozen and the city dark for as long as the cut runs
	if not get_tree().paused:
		get_tree().paused = true
	if game.map.night < 0.999:
		game.map.set_night(1.0)
	flash = maxf(flash - delta * 3.4, 0.0)
	shake = maxf(shake - delta * 2.6, 0.0)
	if phase == "clip":
		_tick_clip(delta)
		return
	t += delta
	_card_camera(delta)
	if t >= clip_len():
		_advance()


## Slow motion: the cut drops into bullet time just before the hit and climbs out of it while
## the pieces are still falling. A dashcam clip keeps rolling at speed — that is its charm.
func _rate() -> float:
	if _style == "dash":
		return 1.0
	var a: float = _hit_t - SLOW_IN
	var b: float = _hit_t + SLOW_OUT
	if t < a or t > b:
		return 1.0
	var k: float = minf((t - a) / 0.16, (b - t) / 0.4)
	return lerpf(1.0, SLOW_RATE, clampf(k, 0.0, 1.0))


func _tick_clip(delta: float) -> void:
	var rate := _rate()
	slow = clampf((1.0 - rate) / (1.0 - SLOW_RATE), 0.0, 1.0)
	t += delta * rate
	_fire_cues()
	# the target flies its recorded course and dies exactly on the beat
	if _actor != null and is_instance_valid(_actor):
		_actor.position = _hit_p - _vel * maxf(_hit_t - t, 0.0)
		_actor.look_at(_actor.position + _vel.normalized(), Vector3.UP)
		_actor.visible = t < _hit_t
	_move_shot()
	if not _boomed and t >= _hit_t:
		_boomed = true
		_detonate()
	_clip_camera(delta)
	if t >= _len:
		_advance()


func _fire_cues() -> void:
	var i := 0
	while i < _cues.size():
		var c: Dictionary = _cues[i]
		if t >= float(c.t):
			SFX.play(String(c.s), float(c.db), float(c.p))
			_cues.remove_at(i)
		else:
			i += 1


func _move_shot() -> void:
	var k: float = clampf(1.0 - (_hit_t - t) / _shot_travel, 0.0, 1.0)
	if _shot != null and is_instance_valid(_shot):
		_shot.visible = t < _hit_t and k > 0.0
		if _shot.visible:
			var pos := _shot_pos(k)
			var ahead := _shot_pos(minf(k + 0.02, 1.0))
			_shot.position = pos
			if (ahead - pos).length_squared() > 0.001:
				_shot.look_at(ahead, Vector3.UP)
	for tr in _tracers:
		var node: MeshInstance3D = tr["node"]
		var tk: float = clampf(1.0 - (_hit_t - t + float(tr["off"])) / _shot_travel, -1.0, 1.4)
		node.visible = tk > 0.0 and tk < 1.25 and t < _hit_t + 0.25
		if node.visible:
			var to: Vector3 = _hit_p + (tr["miss"] as Vector3)
			node.position = _shot_from.lerp(to, tk)
			if node.position.distance_squared_to(to) > 1.0:
				node.look_at(to, Vector3.UP)


## Handheld: a slow drift, the jitter of a hand, and the flinch when the blast arrives.
func _clip_camera(delta: float) -> void:
	var k := clip_k()
	var eye: Vector3 = _eye.lerp(_eye_to, k * k * (3.0 - 2.0 * k))
	if _style == "onboard":
		eye = _onboard_eye(delta)
	var wob := Vector3(sin(t * 1.7) * 0.5, sin(t * 2.3) * 0.35, cos(t * 1.3) * 0.5) * _wob
	var kick: float = _jit + shake * 1.6
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * kick
	cam.global_position = eye + wob + jitter
	var look: Vector3 = _hit_p
	if _actor != null and is_instance_valid(_actor) and t < _hit_t:
		look = _actor.global_position
	# the operator is always a beat late following the target
	_look = _look.lerp(look, clampf(delta * _lag, 0.0, 1.0))
	if cam.global_position.distance_squared_to(_look) > 0.01:
		cam.look_at(_look, Vector3.UP)
	# the phone zooms in on the target, then jerks wide at the flash
	var want: float = lerpf(_fov0, _fov1, k)
	if _boomed and t < _hit_t + 0.5:
		want = _fov1 + 14.0
	cam.fov = lerpf(cam.fov, want, clampf(delta * 3.0, 0.0, 1.0))


## The camera the interceptor carries: it rides behind the missile, and after the hit it keeps
## flying through the fireball, slowing down, while the wreck falls away below.
func _onboard_eye(delta: float) -> Vector3:
	if t < _hit_t:
		var k: float = clampf(1.0 - (_hit_t - t) / _shot_travel, 0.0, 1.0)
		var pos := _shot_pos(k)
		var ahead := _shot_pos(minf(k + 0.03, 1.0))
		if pos.distance_squared_to(ahead) > 0.001:
			_ride_dir = (ahead - pos).normalized()
		_ride_eye = pos - _ride_dir * 11.0 + Vector3(0, 2.4, 0)
		return _ride_eye
	var speed: float = 26.0 * maxf(1.0 - (t - _hit_t) / TAIL, 0.0)
	_ride_eye += _ride_dir * speed * delta
	return _ride_eye


## The title card and the sign-off: a slow, high drift over the sleeping city.
func _card_camera(delta: float) -> void:
	_orbit += delta * 0.045
	var k: float = clampf(t / maxf(clip_len(), 0.001), 0.0, 1.0)
	var r: float = 560.0 if phase == "intro" else 700.0
	var h: float = lerpf(250.0, 200.0, k) if phase == "intro" else lerpf(180.0, 330.0, k)
	cam.global_position = Vector3(cos(_orbit) * r, h, sin(_orbit) * r)
	cam.look_at(Vector3(0, 70, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 52.0, clampf(delta * 2.0, 0.0, 1.0))


func _detonate() -> void:
	var c: Dictionary = current()
	var type := String(c.get("type", "shahed"))
	var big: float = 1.8 if type == "ballistic" else (1.3 if type == "cruise" else 1.0)
	Fx.explosion(self, _hit_p, big, Color(1.0, 0.55, 0.15), true)
	# burning pieces tumbling out of the fireball, kept light — this is only a replay
	for i in 9:
		var piece := MeshInstance3D.new()
		piece.mesh = Fx.cube(Vector3.ONE * _rng.randf_range(0.6, 1.8))
		piece.material_override = Fx.glow(Color(1.0, 0.5, 0.15), 3.0)
		piece.position = _hit_p
		add_child(piece)
		var away := _vel * 0.4 + Vector3(_rng.randf_range(-20, 20), _rng.randf_range(-4, 12), _rng.randf_range(-20, 20))
		var tw := piece.create_tween()
		tw.tween_property(piece, "position", _hit_p + away * 2.0 + Vector3(0, -45, 0), TAIL * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(piece, "transparency", 1.0, TAIL * 1.4)
		tw.tween_callback(piece.queue_free)
	# light first, sound after: the bang and the flinch arrive together, a beat late. The
	# distance is taken from where the camera actually is — an onboard camera is right there.
	var delay: float = minf(cam.global_position.distance_to(_hit_p) / MACH, 1.4)
	_cue(_hit_t + delay, "explosion", -4.0, 1.0)
	var when := get_tree().create_timer(delay / maxf(_rate(), 0.2), true, false, true)
	when.timeout.connect(func() -> void: shake = 1.0)
