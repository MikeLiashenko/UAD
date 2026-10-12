extends Node
## MaxRealism (GS.realism): the night is fought from the ground. There is no map view and no
## battery panel — the player is one person on the position who walks to a system, takes its
## seat [E] and works it by hand, then gets up and walks to the next one.
##  * guns (pickup, ZU-23, Gepard, Shilka) — an optical sight, the lead is the gunner's;
##  * Igla and Avenger — an infrared seeker: its tone says when the missile has the target;
##  * everything with a radar of its own — an operator's console: a round scope with unnamed
##    blips, an azimuth and a range handwheel (the mouse), lock, and as many launches as the
##    operator decides. A missile either brings the target down or passes by (GS.kill_chance);
##  * the command post — the surveillance radar, the state of the city and the supply terminal
##    (scripts/ui/supply.gd): what is ordered there is brought by a column some seconds later.
## Threats carry no labels: what is coming is told over the radio (bearing, distance, how many)
## and read off the scope (speed and altitude of the tracked blip).

const RealismHud = preload("res://scripts/ui/realism_hud.gd")
const Training = preload("res://scripts/game/training.gd")

## Sights of the systems that do not work from the radar scope.
const IR_SIGHT := ["igla", "avenger"]
const OPTIC_SIGHT := ["mg", "zu23", "gepard", "shilka"]
## How close (to the hull) one has to stand to take a seat, metres.
const REACH := 2.4
## The surveillance radar of the command post.
const POST_RANGE := 100000.0
const SCALES := [5000.0, 10000.0, 25000.0, 50000.0, 100000.0, 250000.0, 500000.0]
const SWEEP_POST := 4.0
const SWEEP_SAM := 1.6
## The lock gate around the cursor: azimuth and a share of the range.
const GATE_AZ := 0.07
const GATE_RNG := 0.08
## Seconds a supply column takes to bring an order to the position.
const DELIVERY := {"weapon": 40.0, "ammo": 20.0, "camo": 30.0}

var game
var hud
var training
## What [E] would do right now on foot: {kind, id, name} or empty.
var near := {}
# --- the scope of the console the player sits at
var scope_az := 0.0
var scope_rng := 8000.0
var scope_scale := 25000.0
var track = null
var sweep := 0.0
## instance id -> {pos: Vector2 (metres from the base, x east, y south), age}
var blips := {}
## Own missiles in the air (drawn on the scope).
var missiles: Array = []
## Rounds sent at the blip being tracked.
var salvo := 0
var console_msg := ""
var console_t := 0.0
## Radio traffic, newest last: [{text, color, age}].
var radio_log: Array = []
## A short hint under the crosshair ("this is done on foot here").
var note := ""
var note_t := 0.0
var _greeted := false
## Played with fingers: the overlay draws a stick and buttons, hints name them instead of keys.
var touch := false
## Paid orders on the road: [{kind, id, n, t}] — t is the seconds left until the column arrives.
var orders: Array = []


func _ready() -> void:
	touch = GS.touch()
	attach_hud()
	if GS.training:
		training = Training.new()
		training.game = game
		training.rl = self
		add_child(training)


## The overlay lives inside the game HUD, which is rebuilt when the language changes.
func attach_hud() -> void:
	hud = RealismHud.new()
	hud.game = game
	hud.rl = self
	game.hud.root.add_child(hud)
	game.hud.root.move_child(hud, 1)


## The start of a session: on foot in the middle of the position, facing the command post.
func begin() -> void:
	game.mfg.ensure_truck()
	# on the range the drill targets are the trainee's: the crews hold their fire
	game.auto_fire = 0 if GS.training else 1
	game.walk_at = GS.base_pos + Vector3(4.0, 0, 8.0)
	game.walk_yaw = PI
	game.set_view("walk")
	if not _greeted and not GS.training:
		_greeted = true
		radio(GS.t("Позиция на связи. Расчёты стволов на местах, огонь по готовности."))
		if touch:
			radio(GS.t("Снабжение, радар и приказы — на командном пункте: зелёная кабина у мачты с красным огнём."), Color(0.75, 0.82, 0.76))
			radio(GS.t("Воздушную тревогу городу объявляете вы: кнопка «ТРЕВОГА» вверху экрана. Днём сирену никто не включит за вас."), Color(0.75, 0.82, 0.76))
		else:
			radio(GS.t("Снабжение, радар и приказы — на командном пункте: зелёная кабина у мачты с красным огнём. Там %s.") % GS.key_label("shop"), Color(0.75, 0.82, 0.76))
			radio(GS.t("Воздушную тревогу городу объявляете вы: %s, с любого места. Днём сирену никто не включит за вас.") % GS.key_label("alarm"), Color(0.75, 0.82, 0.76))


# --- Stations ------------------------------------------------------------------------------------
func sight_of(id: String) -> String:
	if id in IR_SIGHT:
		return "ir"
	if id in OPTIC_SIGHT:
		return "optic"
	return "radar"


## Where one stands to work the command post: in front of the cabin's screen.
func post_pos() -> Vector3:
	return GS.base_pos + Vector3(-2.0, 0, 18.6)


func _hull(id: String) -> float:
	match String(GS.WEAPONS[id].get("class", "gun")):
		"medium":
			return 3.0
		"long":
			return 3.6
	return 2.2


func stations() -> Array:
	var out := []
	for id in game.weapons:
		var w = game.weapons[id]
		out.append({"kind": "weapon", "id": String(id), "pos": w.global_position, "r": _hull(String(id)), "name": GS.t(String(w.def.name))})
	out.append({"kind": "post", "id": "post", "pos": post_pos(), "r": 1.2, "name": GS.t("Командный пункт")})
	var mg = game.mfg
	if mg.unit != null and is_instance_valid(mg.unit) and not mg.wrecked:
		out.append({"kind": "truck", "id": "truck", "pos": mg.pos, "r": 2.4, "name": GS.t("Пикап мобильной группы")})
	return out


## The station within arm's reach, the nearest one first.
func _find_near() -> Dictionary:
	var p: Vector3 = game.walker.pos
	var best := {}
	var bd := REACH
	for st in stations():
		var d: float = Vector2(st.pos.x - p.x, st.pos.z - p.z).length() - float(st.r)
		if d < bd:
			bd = d
			best = st
	return best


## Hulls a person cannot walk through. A spot the walker already stands in never blocks, so
## nobody is walled in by a system delivered on top of them.
func blocks(x: float, z: float) -> bool:
	var me: Vector3 = game.walker.pos
	for st in stations():
		if String(st.kind) == "post":
			continue
		var r: float = float(st.r) * 0.62
		if Vector2(st.pos.x - x, st.pos.z - z).length() < r and Vector2(st.pos.x - me.x, st.pos.z - me.z).length() >= r:
			return true
	# the cabin of the command post
	var l := Vector3(x, 0, z) - GS.base_pos
	var lm := me - GS.base_pos
	var inside := l.x > -6.0 and l.x < 2.0 and l.z > 20.4 and l.z < 23.6
	var me_in := lm.x > -6.0 and lm.x < 2.0 and lm.z > 20.4 and lm.z < 23.6
	return inside and not me_in


## [E]: take the seat in front of us, or get up from the one we are in.
func use() -> void:
	if game.game_over:
		return
	match String(game.view):
		"walk":
			if near.is_empty():
				say_note(GS.t("Рядом ничего нет: подойдите к машине вплотную"))
				return
			match String(near.kind):
				"weapon":
					sit(String(near.id))
				"post":
					enter_post()
				"truck":
					game.set_view("mfg")
		"base":
			stand_up()
		"post":
			game.walk_at = game.walker.pos
			game.walk_yaw = game.walker.yaw
			game.set_view("walk")
		"mfg":
			var h: float = game.mfg.heading
			game.walk_at = game.mfg.pos + Vector3(cos(h), 0, -sin(h)) * 2.8
			game.walk_yaw = h
			game.set_view("walk")
	SFX.play("click", -6.0, 0.8)


func sit(id: String) -> void:
	if not game.weapons.has(id):
		return
	game.select_weapon(id)
	_reset_scope(maxf(8000.0, float(game.weapons[id].effective_range()) * 0.6))
	game.set_view("base")


## Back on the ground on the inner side of the system, facing it.
func stand_up() -> void:
	var w = game.weapons.get(game.selected_weapon)
	if w != null:
		var out: Vector3 = w.global_position - GS.base_pos
		out.y = 0.0
		out = out.normalized() if out.length() > 0.1 else Vector3(0, 0, 1)
		game.walk_at = w.global_position - out * (_hull(String(game.selected_weapon)) + 1.2)
		game.walk_yaw = atan2(-out.x, -out.z)
	game.set_view("walk")


func enter_post() -> void:
	_reset_scope(50000.0)
	game.set_view("post")


func at_post() -> bool:
	return game.view == "post"


# --- The radar scope ------------------------------------------------------------------------------
## The console with the round scope is in front of the player.
func scope_on() -> bool:
	return game.view == "post" or (game.view == "base" and sight_of(String(game.selected_weapon)) == "radar")


func weapon():
	return game.weapons.get(game.selected_weapon) if game.view == "base" else null


## Instrumented range of the radar the player looks at.
func radar_range() -> float:
	var w = weapon()
	if w == null:
		return POST_RANGE
	return maxf(8000.0, float(w.effective_range()) * 1.15)


func _reset_scope(want: float) -> void:
	track = null
	salvo = 0
	blips.clear()
	scope_az = fposmod(-float(game.walker.yaw), TAU)
	scope_scale = SCALES[SCALES.size() - 1]
	for sc in SCALES:
		if sc >= want:
			scope_scale = sc
			break
	scope_rng = scope_scale * 0.4
	console_msg = ""


## Bearing of a point given from the base (x east, y south): 0 = north, clockwise.
static func az_of(rel: Vector2) -> float:
	return fposmod(atan2(rel.x, -rel.y), TAU)


static func rel_of(az: float, rng: float) -> Vector2:
	return Vector2(sin(az), -cos(az)) * rng


func _rel(e) -> Vector2:
	return Vector2(e.position.x - GS.base_pos.x, e.position.z - GS.base_pos.z)


## The radar has the threat: inside its range and above the radio horizon.
func sees(e) -> bool:
	var d := _rel(e).length()
	if d > radar_range():
		return false
	return d <= 4120.0 * (sqrt(GS.RADAR_MAST) + sqrt(maxf(float(e.position.y), 0.0)))


func step_scale(dir: int) -> void:
	var top := radar_range()
	var i: int = SCALES.find(scope_scale)
	i = clampi(i + dir, 0, SCALES.size() - 1)
	# no point in a scale twice as wide as the radar reaches
	while i > 0 and float(SCALES[i - 1]) >= top:
		i -= 1
	scope_scale = SCALES[i]
	scope_rng = minf(scope_rng, scope_scale)
	SFX.play("click", -10.0, 1.2)


## The two handwheels: azimuth and range.
func turn(d_az: float, d_rng: float) -> void:
	if track != null:
		return # the gate rides on the target while it is tracked
	scope_az = fposmod(scope_az + d_az, TAU)
	scope_rng = clampf(scope_rng + d_rng * scope_scale, 200.0, scope_scale)


## Lock the blip under the gate, or let the tracked one go.
func lock() -> void:
	if track != null:
		track = null
		salvo = 0
		say(GS.t("СОПРОВОЖДЕНИЕ СБРОШЕНО"))
		SFX.play("click", -4.0, 0.7)
		return
	var best = null
	var bs := 1.0
	var gate_r := scope_rng * GATE_RNG + 300.0
	for e in game.enemies:
		if e.dead or not sees(e):
			continue
		var id: int = e.get_instance_id()
		if not blips.has(id):
			continue
		var bp: Vector2 = blips[id].pos
		var daz := absf(angle_difference(az_of(bp), scope_az))
		var dr := absf(bp.length() - scope_rng)
		# close to the base a blip sits under the gate whatever the bearing
		var az_gate := maxf(GATE_AZ, 600.0 / maxf(bp.length(), 1.0))
		var s := maxf(daz / az_gate, dr / gate_r)
		if s < bs:
			bs = s
			best = e
	if best == null:
		say(GS.t("В СТРОБЕ ЦЕЛИ НЕТ"))
		SFX.play("click", -6.0, 0.6)
		return
	track = best
	salvo = 0
	say(GS.t("ЦЕЛЬ НА СОПРОВОЖДЕНИИ"))
	SFX.play("click", -2.0, 1.8)


## One missile at the tracked blip. How many to send is the operator's call.
func fire() -> void:
	var w = weapon()
	if w == null:
		return
	var is_drone: bool = String(w.def.kind) == "drone"
	if track == null or not is_instance_valid(track) or track.dead:
		say(GS.t("НЕТ СОПРОВОЖДЕНИЯ — захватите цель"))
	elif not w.can_engage(track):
		say(GS.t("КОМПЛЕКС ЭТУ ЦЕЛЬ НЕ БЕРЁТ"))
	elif not w.in_range(track):
		say(GS.t("ЦЕЛЬ ВНЕ ЗОНЫ ПОРАЖЕНИЯ"))
	elif int(GS.ammo.get(w.id, 0)) <= 0:
		say(GS.t("ДРОНОВ НЕТ") if is_drone else GS.t("РАКЕТ НЕТ"))
	elif w.cooldown > 0.0:
		say(GS.t("ПУСКОВАЯ НЕ ГОТОВА"))
	elif w.launch_at(track, false):
		salvo += 1
		say((GS.t("ПУСК ДРОНА · %d") if is_drone else GS.t("ПУСК · ракета %d")) % salvo)
		game.shake(0.5)
		return
	SFX.play("click", -6.0, 0.6)


## Where the operator's window looks: at the tracked target, or along the azimuth cursor.
func scope_look() -> Vector3:
	var w = weapon()
	if track != null and is_instance_valid(track) and w != null:
		return (track.position - w.global_position).normalized()
	return Vector3(sin(scope_az), 0.22, -cos(scope_az)).normalized()


## What the tracked blip is doing, for the readout: range, altitude, speed, closing or not.
func track_data() -> Dictionary:
	if track == null or not is_instance_valid(track) or track.dead:
		return {}
	var rel := _rel(track)
	var v := Vector2(track.vel.x, track.vel.z)
	return {
		"az": az_of(rel), "rng": rel.length(), "alt": float(track.position.y),
		"kmh": GS.real_kmh(track.vel.length()), "closing": rel.dot(v) < 0.0, "vy": float(track.vel.y),
	}


func say(text: String) -> void:
	console_msg = text
	console_t = 2.6


func say_note(text: String) -> void:
	note = text
	note_t = 3.2


func _update_scope(delta: float) -> void:
	var period := SWEEP_POST if game.view == "post" else SWEEP_SAM
	var prev := sweep
	sweep = fposmod(sweep + delta * TAU / period, TAU)
	if track != null and (not is_instance_valid(track) or track.dead):
		track = null
		say(GS.t("ЦЕЛЬ ПОТЕРЯНА"))
	elif track != null and not sees(track):
		track = null
		say(GS.t("ЦЕЛЬ УШЛА ИЗ ЗОНЫ ОБЗОРА"))
	var alive := {}
	for e in game.enemies:
		if e.dead or not sees(e):
			continue
		var id: int = e.get_instance_id()
		var rel := _rel(e)
		var a := az_of(rel)
		var crossed := (a > prev and a <= sweep) if sweep >= prev else (a > prev or a <= sweep)
		if crossed or e == track:
			blips[id] = {"pos": rel, "age": 0.0}
		alive[id] = true
	for id in blips.keys():
		var b: Dictionary = blips[id]
		b.age = float(b.age) + delta
		if float(b.age) > period * 1.6:
			blips.erase(id)
	if track != null:
		var rel := _rel(track)
		scope_az = az_of(rel)
		scope_rng = clampf(rel.length(), 200.0, scope_scale)
	var keep := []
	for m in missiles:
		if is_instance_valid(m):
			keep.append(m)
	missiles = keep


# --- Supplies -------------------------------------------------------------------------------------
func _order_name(kind: String, id: String, n: int) -> String:
	if kind == "camo":
		return GS.t("Маскировочная сеть")
	var def: Dictionary = GS.WEAPONS[id]
	if kind == "weapon":
		return GS.t(String(def.name))
	var one := GS.t("Дрон %s") % GS.t(String(def.short)) if String(def.kind) == "drone" else GS.t("Ракета %s") % GS.t(String(def.short))
	return "%s ×%d" % [one, n]


## Pays for a system, `n` rounds for one, or the camouflage net and puts the order on the road.
func order(kind: String, id: String, n: int) -> bool:
	var price := 0
	match kind:
		"weapon":
			if GS.unlocked.get(id, false) or on_order(kind, id) > 0:
				return false
			price = int(GS.WEAPONS[id].unlock)
		"ammo":
			price = int(GS.WEAPONS[id].missile_price) * n
		"camo":
			if GS.camo or on_order(kind, id) > 0:
				return false
			price = GS.CAMO_PRICE
		_:
			return false
	if not GS.spend(price):
		return false
	orders.append({"kind": kind, "id": id, "n": n, "t": float(DELIVERY[kind])})
	radio(GS.t("Заявка принята: %s. Колонна будет через %d с.") % [_order_name(kind, id, n), int(DELIVERY[kind])], Color(0.75, 0.82, 0.76))
	return true


## How much of something is on the road.
func on_order(kind: String, id: String) -> int:
	var n := 0
	for o in orders:
		if String(o.kind) == kind and String(o.id) == id:
			n += int(o.n)
	return n


## Seconds until the last of it arrives.
func order_eta(kind: String, id: String) -> float:
	var t := 0.0
	for o in orders:
		if String(o.kind) == kind and String(o.id) == id:
			t = maxf(t, float(o.t))
	return t


func _deliver(o: Dictionary, announce := true) -> void:
	var id := String(o.id)
	match String(o.kind):
		"weapon":
			GS.unlocked[id] = true
			if GS.WEAPONS[id].has("start_ammo"):
				GS.ammo[id] = int(GS.ammo.get(id, 0)) + int(GS.WEAPONS[id].start_ammo)
			game.add_weapon(id)
		"ammo":
			GS.ammo[id] = int(GS.ammo.get(id, 0)) + int(o.n)
		"camo":
			GS.camo = true
	GS.state_changed.emit()
	if announce:
		radio(GS.t("Колонна снабжения на позиции: %s.") % _order_name(String(o.kind), id, int(o.n)), Color(0.7, 0.95, 0.75))
		SFX.play("cash", -8.0)


## Everything on the road is unloaded at once: the world is being saved, and what was paid for
## must not be lost with the column.
func flush_orders() -> void:
	for o in orders:
		_deliver(o, false)
	orders.clear()


func _tick_orders(delta: float) -> void:
	if orders.is_empty():
		return
	var left := []
	for o in orders:
		o.t = float(o.t) - delta
		if float(o.t) <= 0.0:
			_deliver(o)
		else:
			left.append(o)
	orders = left


# --- Radio ----------------------------------------------------------------------------------------
func radio(text: String, color := Color(0.86, 0.9, 0.82)) -> void:
	if text == "":
		return
	radio_log.append({"text": text, "color": color, "age": 0.0})
	while radio_log.size() > 6:
		radio_log.pop_front()
	SFX.play("radio", -9.0, 1.0, 0.3)


## The raid warning as an observation post would give it: what, how many, where from.
func raid_call(e_def: Dictionary, count: int, from: Vector3, alt: float) -> void:
	var rel := Vector2(from.x - GS.base_pos.x, from.z - GS.base_pos.z)
	var txt := GS.t("Воздух! %s, целей: %d. Азимут %03d°, удаление %d км") % [GS.t(String(e_def.name)), count, int(rad_to_deg(az_of(rel))) % 360, int(rel.length() * 0.001)]
	if alt > 0.0:
		txt += GS.t(", высота %d м") % (int(alt / 50.0) * 50)
	radio(txt + ".", Color(1.0, 0.72, 0.5))
	SFX.play("alert", -8.0)


func on_kill(e) -> void:
	radio(GS.t("Цель поражена: %s.") % GS.t(String(e.def.name)), Color(0.7, 0.95, 0.75))


# --- Keys -----------------------------------------------------------------------------------------
## Every key of a MaxRealism session goes through here (see GameController._unhandled_input).
func key(kc: int) -> void:
	var act := GS.action_of(kc)
	match act:
		"use":
			use()
		"pause":
			game.hud.toggle_pause()
		"photo":
			game.take_photo()
		"alarm":
			game.toggle_alarm() # over the radio, from wherever the player stands or sits
		"night":
			if game.view == "base" and not scope_on():
				game.base_view.nv = not game.base_view.nv
		"shop":
			if _need_post():
				game.hud.open_shop()
		"strikes":
			if _need_post() and not GS.training:
				game.hud.open_strikes()
		"feed":
			if _need_post() and not GS.training:
				game.hud.open_feed()
		"auto":
			if _need_post():
				crew_order()
		"view", "walk", "fpv", "mfg", "fighter", "weapon_prev", "weapon_next", "home", "warp":
			say_note(GS.t("В MaxRealism кнопок нет: подойдите к машине и займите место — %s") % GS.key_label("use"))
	if act == "" and kc >= KEY_1 and kc <= KEY_9:
		say_note(GS.t("В MaxRealism кнопок нет: подойдите к машине и займите место — %s") % GS.key_label("use"))


func _need_post() -> bool:
	if at_post():
		return true
	say_note(GS.t("Это делается с командного пункта: кабина у мачты с красным огнём"))
	return false


## The gun crews either fire on their own or hold. The launchers are always the player's.
func crew_order() -> void:
	game.auto_fire = 0 if int(game.auto_fire) >= 1 else 1
	if int(game.auto_fire) >= 1:
		radio(GS.t("Расчётам стволов: огонь по готовности."))
	else:
		radio(GS.t("Расчётам стволов: огонь запрещаю."))


func crews_free() -> bool:
	return int(game.auto_fire) >= 1


# --- Input of the consoles ------------------------------------------------------------------------
func refresh_capture() -> void:
	if game.view != "post":
		return
	if GS.touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var free: bool = get_tree().paused or Input.is_key_pressed(KEY_ALT) or game.game_over or game.wants_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


## Mouse and touch on a console with a scope. True when the event was the console's.
func console_input(event: InputEvent) -> bool:
	if not scope_on():
		return false
	var sens: float = float(GS.settings.sens)
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			turn(mm.relative.x * 0.0022 * sens, -mm.relative.y * 0.0016 * sens)
		return true
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		turn(sd.relative.x * 0.004 * sens, -sd.relative.y * 0.003 * sens)
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return true
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				step_scale(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				step_scale(1)
			MOUSE_BUTTON_RIGHT:
				lock()
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and game.view == "base":
					fire()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if game.view != "post" or get_tree().paused or game.game_over:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	console_input(event)


func _process(delta: float) -> void:
	for r in radio_log:
		r.age = float(r.age) + delta
	while not radio_log.is_empty() and float(radio_log[0].age) > 16.0:
		radio_log.pop_front()
	console_t = maxf(0.0, console_t - delta)
	note_t = maxf(0.0, note_t - delta)
	_tick_orders(delta)
	near = _find_near() if game.view == "walk" else {}
	if scope_on():
		_update_scope(delta)
		if game.view == "post":
			refresh_capture()
			game.locked = track
	elif track != null:
		track = null
