extends Node
## Fighter interceptor [J]: an F-16 on patrol over the city. It takes off behind the city, the
## player flies it towards the incoming threats and brings them down with the M61 gun, AIM-9X
## heat-seekers and AIM-120s — and minds where the wreckage falls: over the rooftops it is a
## fine and a fire, just like for the ground systems.
##
## Steering is the mouse aim of the FPV console (an aim ring, the jet turns to it as hard as its
## speed allows); W/S throttle, Shift afterburner (drinks fuel), A/D and the arrows turn too.
## LMB gun (the rounds bend to the lead point of a threat near the pipper), RMB a missile: it
## takes the threat nearest the nose and picks AIM-9X or AIM-120 by the range itself; E / Q fire
## the one type. The lock marker only shows which threat that is. Fuel runs out (the jet goes home by itself), the
## ground and the tower blocks are fatal. Between sorties the jet is refuelled and rearmed;
## a lost one is replaced in the morning. Missiles come from the shop, unused ones go back.

const Meshes = preload("res://scripts/core/meshes.gd")
const Fx = preload("res://scripts/core/fx.gd")

const MIN_SPEED := 95.0
const MIL := 205.0
const BURNER := 260.0
const TURN := 1.2
const FUEL := 160.0
const ROUNDS := 510
const LOAD := {"aim9": 4, "aim120": 2}
const LOCK_CONE := deg_to_rad(40.0)
const LOCK_TIME := 0.3
## A missile fired before the lock is complete takes the best threat this far off the nose.
const SNAP_CONE := deg_to_rad(75.0)
## The gun helps: its rounds go to the lead point of a threat this close to the pipper.
const GUN_ASSIST := deg_to_rad(10.0)
## How far the gun reaches (its rounds fly GUN_LIFE seconds) and helps.
const GUN_REACH := 850.0
const GUN_LIFE := 0.8
## The lowest the jet goes above the roofs around its course: Auto-GCAS levels it off there instead
## of letting it dive in — low drones are hunted from just above the rooftops.
const FLOOR := 20.0
## How much harder than the pilot Auto-GCAS pulls (a multiple of TURN).
const GCAS_PULL := 2.4
const LOCK_RANGE := 2400.0
const REARM := 25.0
const LOSS := 15000
const AIM_GAIN := 0.0024
const MAX_ELEV := deg_to_rad(72.0)
const PATROL := 4500.0

var game
var map
var cam: Camera3D
var active := false
## "ready", "air", "rearm" (on the ground after a sortie) or "lost" (until the morning).
var state := "ready"
var rearm_t := 0.0
var jet: Node3D
var pos := Vector3.ZERO
var dir := Vector3.FORWARD
var aim := Vector3.FORWARD
var speed := 170.0
var throttle := 0.7
var burner := false
var fuel := FUEL
var rounds := ROUNDS
var loaded := {"aim9": 0, "aim120": 0}
var bank := 0.0
var lock = null
var lock_t := 0.0
var locked := false
var trigger := false
var pull_up := false
var outside := false
## Auto-GCAS, the automatic ground collision avoidance of the real F-16: it holds the jet at
## FLOOR above the ground and the roofs ahead. The pilot's aim ring stays where it is: the moment
## the ring points above the floor again, the jet follows it.
var gcas := false
## The least climb (rise per run) the floor allows this frame.
var _min_slope := -1.0
var kills_at_start := 0
## Seconds since the take-off (the HUD shows the controls card at the start of a sortie).
var air_t := 0.0
## A threat in the gun's help cone this frame, and where to aim the rounds to meet it.
var gun_target = null
var gun_lead := Vector3.ZERO
var _gun_cd := 0.0
var _gun_snd := 0.0
var _cam_pos := Vector3.ZERO
var _saved_fov := 62.0
var _engine: AudioStreamPlayer
var _bingo := false


func _ready() -> void:
	_engine = AudioStreamPlayer.new()
	_engine.bus = "Effects"
	_engine.stream = SFX.stream("buzz")
	_engine.volume_db = -60.0
	add_child(_engine)


func owned() -> bool:
	return bool(GS.unlocked.get("f16", false))


func _touch() -> bool:
	return DisplayServer.is_touchscreen_available()


## Why the jet cannot go up now, or "".
func blocker() -> String:
	if not owned():
		return GS.t("Нет истребителя — купите звено F-16 в магазине [%s]") % GS.key_label("shop")
	match state:
		"rearm":
			return GS.t("F-16 на земле: заправка и подвеска ещё %d с") % int(ceil(rearm_t))
		"lost":
			return GS.t("F-16 потерян — новый прибудет утром")
	return ""


# --- Sortie ------------------------------------------------------------------------------------
func enter() -> void:
	active = true
	state = "air"
	# take-off behind the city, heading out towards where the raids come from
	var sectors: Array = map.city.threat_sectors
	var v := Vector2.ZERO
	for a in sectors:
		v += Vector2(sin(deg_to_rad(float(a))), -cos(deg_to_rad(float(a))))
	var threat := Vector3(v.x, 0, v.y).normalized() if v.length() > 0.01 else Vector3.FORWARD
	pos = -threat * 900.0 + Vector3(0, 260.0, 0)
	dir = threat
	aim = dir
	speed = 175.0
	throttle = 0.7
	burner = false
	fuel = FUEL
	rounds = ROUNDS
	bank = 0.0
	lock = null
	locked = false
	lock_t = 0.0
	_bingo = false
	air_t = 0.0
	gun_target = null
	for k in LOAD:
		var n := mini(int(LOAD[k]), int(GS.ammo.get(k, 0)))
		loaded[k] = n
		GS.ammo[k] = int(GS.ammo.get(k, 0)) - n
	GS.state_changed.emit()
	kills_at_start = int(GS.stats.get("f16_kills", 0))
	jet = Meshes.f16()
	game.add_child(jet)
	_place_jet()
	_saved_fov = cam.fov
	cam.fov = 70.0
	_cam_pos = pos - dir * 30.0 + Vector3(0, 8, 0)
	if _engine.stream != null:
		_engine.play()
	refresh_capture()
	game.hud.alert(GS.t("ЗВЕНО F-16 В ВОЗДУХЕ"), Color(0.5, 0.9, 1.0))
	game.hud.log_event(GS.t("Вылет F-16: AIM-9X ×%d, AIM-120 ×%d, M61 %d снарядов") % [int(loaded.aim9), int(loaded.aim120), rounds], Color(0.5, 0.9, 1.0))


## Leaving the view ends the sortie: the jet heads home, unused missiles go back to the store.
func exit() -> void:
	if state == "air":
		_land(GS.t("возвращение на аэродром"))
	active = false
	trigger = false
	_engine.stop()
	cam.fov = _saved_fov
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _land(why: String) -> void:
	for k in loaded:
		GS.ammo[k] = int(GS.ammo.get(k, 0)) + int(loaded[k])
		loaded[k] = 0
	GS.state_changed.emit()
	state = "rearm"
	rearm_t = REARM
	if jet != null and is_instance_valid(jet):
		jet.queue_free()
	jet = null
	var kills := int(GS.stats.get("f16_kills", 0)) - kills_at_start
	game.hud.log_event(GS.t("F-16 садится (%s). Сбито за вылет: %d") % [why, kills], Color(0.5, 0.9, 1.0))


func _crash(why: String) -> void:
	Fx.explosion(game.fx_root, pos, 2.4, Color(1.0, 0.5, 0.15), true)
	game.play_boom("explosion", pos, 4.0)
	for k in loaded:
		loaded[k] = 0
	if jet != null and is_instance_valid(jet):
		jet.queue_free()
	jet = null
	state = "lost"
	GS.stats.f16_crashes = int(GS.stats.get("f16_crashes", 0)) + 1
	GS.add_money(-LOSS)
	game.hud.alert(GS.t("F-16 ПОТЕРЯН — пилот катапультировался"), Color(1.0, 0.35, 0.3))
	game.hud.log_event(GS.t("F-16 разбился: %s. Потеря самолёта −%s, новый — утром.") % [why, GS.fmt_money(LOSS)], Color(1.0, 0.4, 0.3))
	game.set_view("top")


## Morning: a lost jet is replaced, a grounded one is ready.
func morning() -> void:
	if state == "lost" or state == "rearm":
		state = "ready"
	# the partners' deliveries keep the flight armed: the store is topped up to a sortie's load
	if owned():
		var got := []
		for k in LOAD:
			var n := int(LOAD[k]) - int(GS.ammo.get(k, 0))
			if n > 0:
				GS.ammo[k] = int(LOAD[k])
				got.append("%s ×%d" % [String(GS.WEAPONS[k].short), n])
		if not got.is_empty():
			game.hud.log_event(GS.t("Поставка ракет для F-16: %s") % ", ".join(got), Color(0.5, 0.9, 1.0))


func refresh_capture() -> void:
	if not active or _touch():
		if active:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var free: bool = get_tree().paused or Input.is_key_pressed(KEY_ALT) or game.game_over or game.wants_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


## Turns the aim ring: yaw around the vertical, pitch up / down, never past MAX_ELEV.
func turn_aim(yaw: float, pitch: float) -> void:
	var a := aim.rotated(Vector3.UP, -yaw)
	var flat := Vector2(a.x, a.z).length()
	var elev := clampf(atan2(a.y, flat) + pitch, -MAX_ELEV, MAX_ELEV)
	var h := Vector2(a.x, a.z).normalized() if flat > 0.0001 else Vector2(0, -1)
	aim = Vector3(h.x * cos(elev), sin(elev), h.y * cos(elev)).normalized()


func range_of(kind: String) -> float:
	return float(GS.WEAPONS[kind].range)


# --- Frame -----------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if state == "rearm":
		rearm_t -= delta
		if rearm_t <= 0.0:
			state = "ready"
			game.hud.log_event(GS.t("F-16 заправлен и вооружён — готов к вылету [%s]") % GS.key_label("fighter"), Color(0.5, 0.9, 1.0))
	if not active or state != "air":
		return
	refresh_capture()
	air_t += delta
	if not get_tree().paused:
		_keys(delta)
	_fly(delta)
	if state != "air":
		return
	_lock(delta)
	_gun_aim()
	_gun(delta)
	_place_jet()
	_camera(delta)
	_engine.volume_db = linear_to_db(clampf(0.35 + throttle * 0.35 + (0.3 if burner else 0.0), 0.0, 1.0)) - 10.0
	_engine.pitch_scale = 0.22 + speed / BURNER * 0.35


func _keys(delta: float) -> void:
	if _touch():
		return
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
		turn_aim(kx * 1.3 * delta, ky * 0.9 * delta * (-1.0 if bool(GS.settings.invert_y) else 1.0))
	if Input.is_key_pressed(KEY_W):
		throttle = minf(1.0, throttle + 0.6 * delta)
	if Input.is_key_pressed(KEY_S):
		throttle = maxf(0.0, throttle - 0.6 * delta)
	burner = Input.is_key_pressed(KEY_SHIFT) and fuel > 0.0


func _fly(delta: float) -> void:
	var want := BURNER if burner else lerpf(MIN_SPEED, MIL, throttle)
	speed = move_toward(speed, want, (40.0 if want > speed else 28.0) * delta)
	speed = clampf(speed - dir.y * 45.0 * delta, MIN_SPEED * 0.8, BURNER * 1.1) # climbing costs speed
	# the patrol area: past it the jet is turned back towards the city
	var flat := Vector2(pos.x, pos.z).length()
	outside = flat > PATROL
	if flat > PATROL + 500.0:
		var home := Vector3(-pos.x, 0.0, -pos.z).normalized()
		aim = aim.slerp(home, clampf(delta * 0.7, 0.0, 1.0)).normalized()
	var steer := _floor_hold(aim)
	# the present course counts too: pulling out of a dive is done at full strength, wherever the
	# ring already is
	var dir_slope := dir.y / maxf(Vector2(dir.x, dir.z).length(), 0.05)
	gcas = steer.y > aim.y + 0.01 or dir_slope < _min_slope
	var old := dir
	var rate := TURN * clampf(speed / 175.0, 0.55, 1.15) * (0.9 if burner else 1.0) * (GCAS_PULL if gcas else 1.0)
	var ang := dir.angle_to(steer)
	if ang > 0.0001:
		dir = dir.slerp(steer, clampf(rate * delta / ang, 0.0, 1.0)).normalized()
	pos += dir * speed * delta
	# bank into the turn by the rate of turn around the vertical
	var yaw_rate := 0.0
	if delta > 0.0:
		yaw_rate = wrapf(atan2(-dir.x, -dir.z) - atan2(-old.x, -old.z), -PI, PI) / delta
	bank = lerpf(bank, clampf(yaw_rate * 1.6, -1.3, 1.3), 1.0 - exp(-delta * 4.0))
	fuel -= delta * (3.0 if burner else 1.0)
	if fuel < FUEL * 0.2 and not _bingo:
		_bingo = true
		game.hud.alert(GS.t("БИНГО — топлива на обратный путь"), Color(1.0, 0.7, 0.3))
	if fuel <= 0.0:
		game.set_view("top") # exit() lands it
		return
	var ground: float = _ground(pos)
	# PULL UP: the present course meets the ground or a roof within a second
	pull_up = false
	for k in [0.25, 0.5, 0.75, 1.0]:
		var q: Vector3 = pos + dir * speed * float(k)
		if q.y < _ground(q) + 3.0:
			pull_up = true
			break
	if pos.y < ground + 2.5:
		_crash(GS.t("столкновение с землёй") if ground < 1.0 else GS.t("столкновение со зданием"))


## The course the jet may take towards `want`: as steep down as it goes, but never below FLOOR
## over the ground and the roofs along the next second and a half of flight.
func _floor_hold(want: Vector3) -> Vector3:
	var flat := Vector3(want.x, 0.0, want.z)
	if flat.length() < 0.05:
		flat = Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.05:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	# the ground under the course the ring asks for, the present one (still turning) and the arc
	var now := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else flat
	var mid := (flat + now).normalized() if (flat + now).length() > 0.05 else flat
	# a dive cannot be stopped at once: the height it still loses while pulling out is added
	var dive := maxf(0.0, -asin(clampf(dir.y, -1.0, 1.0)))
	var pull_out := speed / (TURN * GCAS_PULL) * (1.0 - cos(dive))
	var floor_at := FLOOR + pull_out
	# below the floor already (it came in from above the rooftops): straight up to it
	var min_y := -1.0
	if pos.y < _canopy(pos) + FLOOR:
		min_y = 0.6
	for f in [flat, mid, now]:
		for k in [0.08, 0.15, 0.25, 0.35, 0.5, 0.65, 0.8, 1.0, 1.2, 1.5, 1.8]:
			var run: float = speed * float(k)
			var q: Vector3 = pos + (f as Vector3) * run
			# the climb (slope) needed to be at the floor over that spot
			min_y = maxf(min_y, (_canopy(q) + floor_at - pos.y) / run)
	_min_slope = min_y
	var slope := want.y / maxf(Vector2(want.x, want.z).length(), 0.05)
	if slope >= min_y:
		return want
	return (flat + Vector3(0, clampf(min_y, -3.0, 3.0), 0)).normalized()


## The highest roof around a spot: the floor keeps the jet above the rooftops, out of the street
## canyons where a tower could come up faster than it can climb.
func _canopy(p: Vector3) -> float:
	return map.ceiling(p.x, p.z) if absf(p.x) < 1000.0 and absf(p.z) < 1000.0 else 0.0


func _ground(p: Vector3) -> float:
	return map.ground_height(p.x, p.z) if absf(p.x) < 1000.0 and absf(p.z) < 1000.0 else 0.0


## Keeps the threat nearest the nose in the lock cone; half a second there and it is locked.
func _lock(delta: float) -> void:
	var best = null
	var best_a := LOCK_CONE
	for e in game.enemies:
		if e.dead or GS.eff("aim9", e) <= 0.0:
			continue
		var to: Vector3 = e.position - pos
		if to.length() > LOCK_RANGE:
			continue
		var a := dir.angle_to(to)
		if a < best_a:
			best_a = a
			best = e
	if best != null and best == lock:
		lock_t += delta
		if not locked and lock_t >= LOCK_TIME:
			locked = true
			SFX.play("click", -2.0, 1.6)
	else:
		lock = best
		lock_t = 0.0
		locked = false


## The threat nearest the pipper within the gun's reach, and its lead point (where the rounds
## meet it); the rounds are sent there when it is within GUN_ASSIST of the nose.
func _gun_aim() -> void:
	gun_target = null
	var def: Dictionary = GS.WEAPONS.f16gun
	var best := GUN_ASSIST
	for e in game.enemies:
		if e.dead or GS.eff("f16gun", e) <= 0.0:
			continue
		var rel: Vector3 = e.position - pos
		if rel.length() > GUN_REACH or rel.dot(dir) <= 0.0:
			continue
		var lp: Vector3 = e.position + e.vel * (rel.length() / (float(def.speed) + speed))
		var a := dir.angle_to(lp - pos)
		if a < best:
			best = a
			gun_target = e
			gun_lead = lp


func _gun(delta: float) -> void:
	_gun_cd -= delta
	_gun_snd -= delta
	if not trigger or rounds <= 0 or get_tree().paused:
		return
	var muzzle: Vector3 = (jet.get_meta("muzzle") as Node3D).global_position
	var def: Dictionary = GS.WEAPONS.f16gun
	while _gun_cd <= 0.0 and rounds > 0:
		_gun_cd += float(def.rate)
		rounds -= 1
		var s: float = def.spread
		var at := (gun_lead - muzzle).normalized() if gun_target != null else dir
		var d := (at + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
		game.spawn_bullet(muzzle, d * float(def.speed) + dir * speed, "f16gun", GUN_LIFE, true)
	if _gun_snd <= 0.0:
		_gun_snd = 0.07
		game.play_3d("cannon", pos, -4.0, 0.05)


## Could a missile of this kind go at `e` now: alive, within its range and off the nose by no
## more than SNAP_CONE? (Missiles of the ground batteries already on the way do not stop it: the
## pilot decides, they may still miss.)
func can_hit(e, kind: String) -> bool:
	if e == null or not is_instance_valid(e) or e.dead or GS.eff(kind, e) <= 0.0:
		return false
	return pos.distance_to(e.position) <= range_of(kind) and dir.angle_to(e.position - pos) <= SNAP_CONE


## The best threat for a missile of this kind: the nearest to the nose, then the closest; the
## locked one is kept, and one nobody is shooting at yet goes before one with missiles on the way.
func best_target(kind: String):
	var best = null
	var score := INF
	for e in game.enemies:
		if not can_hit(e, kind):
			continue
		var sc: float = dir.angle_to(e.position - pos) + pos.distance_to(e.position) / range_of(kind) * 0.3
		if e == lock and locked:
			sc -= 0.4
		if float(e.inbound) >= float(e.hp):
			sc += 1.0
		if sc < score:
			score = sc
			best = e
	return best


## Which missile the "РАКЕТА" button fires now: AIM-9X if a threat is within its reach (it is
## cheaper), else AIM-120; "" when neither has a target.
func auto_kind() -> String:
	for k in ["aim9", "aim120"]:
		if int(loaded[k]) > 0 and best_target(k) != null:
			return k
	return ""


## Fires a missile — "auto" picks the type — at the locked threat or, when the lock is not there
## yet, at the best one in front of the nose. Says why when it cannot.
func fire(kind: String) -> void:
	if not active or state != "air":
		return
	if kind == "auto":
		if int(loaded.aim9) + int(loaded.aim120) <= 0:
			game.hud.alert(GS.t("Ракеты кончились — бейте из пушки или садитесь на аэродром"), Color(1.0, 0.6, 0.3))
			return
		kind = auto_kind()
		if kind == "":
			_why_not("aim120" if int(loaded.aim120) > 0 else "aim9")
			return
	if int(loaded.get(kind, 0)) <= 0:
		game.hud.alert(GS.t("%s: пусто") % GS.t(String(GS.WEAPONS[kind].short)), Color(1.0, 0.6, 0.3))
		return
	var t = best_target(kind)
	if t == null:
		_why_not(kind)
		return
	lock = t
	locked = true
	loaded[kind] = int(loaded[kind]) - 1
	var from := pos - Vector3(0, 1.2, 0) + dir * 2.0
	game.spawn_missile(from, dir, lock, kind, dir * speed)
	game.hud.log_event(GS.t("Пуск %s по цели «%s»") % [GS.t(String(GS.WEAPONS[kind].short)), GS.t(String(lock.def.name))], Color(0.6, 0.95, 1.0))


## No target for this missile: tell the pilot what to do instead.
func _why_not(kind: String) -> void:
	var near = null
	var nd := INF
	for e in game.enemies:
		if e.dead or GS.eff(kind, e) <= 0.0 or dir.angle_to(e.position - pos) > SNAP_CONE:
			continue
		var d := pos.distance_to(e.position)
		if d < nd:
			nd = d
			near = e
	var short := GS.t(String(GS.WEAPONS[kind].short))
	if near == null:
		for e in game.enemies:
			if not e.dead and GS.eff(kind, e) <= 0.0 and dir.angle_to(e.position - pos) <= SNAP_CONE:
				game.hud.alert(GS.t("%s — баллистика: её сбивает только Patriot (и С-300), не истребитель") % GS.t(String(e.def.abbr)), Color(1.0, 0.7, 0.3))
				return
	if near != null:
		game.hud.alert(GS.t("Цель в %.1f км, %s бьёт до %.1f км — подлетите ближе") % [nd * 0.005, short, range_of(kind) * 0.005], Color(1.0, 0.7, 0.3))
	else:
		game.hud.alert(GS.t("Впереди нет целей — разверните нос по жёлтой стрелке"), Color(1.0, 0.7, 0.3))


# --- Picture -----------------------------------------------------------------------------------------
func _place_jet() -> void:
	if jet == null or not is_instance_valid(jet):
		return
	var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	b = b.rotated(b.z.normalized(), bank) # left turn (bank > 0): left wing down
	jet.global_transform = Transform3D(b, pos)
	(jet.get_meta("burner") as Node3D).visible = burner


func _camera(delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
	var want := pos - dir * 26.0 - flat * 4.0 + Vector3(0, 7.5, 0)
	_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-delta * 9.0))
	cam.global_position = _cam_pos
	var up := Vector3.UP.rotated(dir, -bank * 0.35) if absf(dir.y) < 0.95 else Vector3.FORWARD
	cam.look_at(pos + dir * 70.0, up)
	cam.fov = lerpf(cam.fov, 70.0 + (9.0 if burner else 0.0), 1.0 - exp(-delta * 4.0))


# --- Input -----------------------------------------------------------------------------------------
func set_trigger(on: bool) -> void:
	trigger = on


func _unhandled_input(event: InputEvent) -> void:
	if not active or state != "air" or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
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
					trigger = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					fire("auto")
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					fire("aim120")
			MOUSE_BUTTON_WHEEL_UP:
				throttle = minf(1.0, throttle + 0.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				throttle = maxf(0.0, throttle - 0.1)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_R:
				get_viewport().set_input_as_handled()
				fire("auto")
			KEY_E:
				get_viewport().set_input_as_handled()
				fire("aim9")
			KEY_Q:
				get_viewport().set_input_as_handled()
				fire("aim120")
