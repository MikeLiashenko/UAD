extends Node3D
## Gameplay session: base, AA units, threats, projectiles, debris physics, economy hooks,
## the two views (overhead map / gunner at the base).

const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")
const Enemy = preload("res://scripts/game/enemy.gd")
const WeaponUnit = preload("res://scripts/game/weapon_unit.gd")
const Bullet = preload("res://scripts/game/bullet.gd")
const Missile = preload("res://scripts/game/missile.gd")
const Debris = preload("res://scripts/game/debris.gd")
const Rubble = preload("res://scripts/game/rubble.gd")
const Director = preload("res://scripts/game/director.gd")
const CameraRig = preload("res://scripts/game/camera_rig.gd")
const BaseView = preload("res://scripts/game/base_view.gd")
const Walker = preload("res://scripts/game/walker.gd")
const Drone = preload("res://scripts/game/drone.gd")
const FpvView = preload("res://scripts/game/fpv_view.gd")
const FireService = preload("res://scripts/game/fire_service.gd")
const Reel = preload("res://scripts/game/reel.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const RemotePlayers = preload("res://scripts/game/remote_players.gd")

## Every system gets its own spot around the base: guns close in, launchers further out,
## spread over a 320° arc so the western sector stays free for the fire station.
const SLOT_RING := {"gun": 15.0, "short": 20.0, "medium": 25.0, "long": 29.0}
const PICK_RADIUS := 44.0

var main
var map
var cam: Camera3D
var rig
var base_view
var fpv_view
var walker
var hud
var director
## City fire and rescue service: puts out fires and rebuilds what collapsed.
var fire_service
## Player of the nightly highlight reel (scripts/game/reel.gd).
var reel
## Intercepts filmed tonight, cut into the morning compilation.
var night_clips: Array = []
var autotest := false
var view := "top"

var enemies: Array = []
## Interceptor drones in the air right now (see scripts/game/drone.gd).
var drones: Array = []
var weapons := {}
var selected_weapon := "mg"
## Active tab of the battery panel: manual / auto / missile / patriot (see GS.WEAPON_GROUPS).
var weapon_group := "manual"
## 0 = off, 1 = guns and drones, 2 = everything including the SAM launchers.
var auto_fire := 0
var hovered = null
var locked = null
var game_over := false

var fx_root: Node3D
var enemy_root: Node3D
var base_node: Node3D
var camo_node: Node3D
var predict_marker: MeshInstance3D
var predict_info := {}
var range_ring: MeshInstance3D
var _lights: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _event_seq := 0
var _event_notes := {}
var _base_time_scale := 1.0
var _slowmo := false
## Drone handed to the FPV console by enter_fpv(), picked up in set_view("fpv").
var _fpv_drone = null
var _drone_seq := 0
## Multiplayer: the other players in the city, whose eyes the "watch" view looks through, and
## the friend being watched.
var remote
var watch_code := ""
var _watch_fov := 62.0
## A HUD panel wants the mouse (the player list): the gunner / FPV / walk views release it.
var ui_cursor := false
## A window is open in a multiplayer game, which never pauses: the mouse is released for it.
var overlay_open := false

# Shared raid (see "Multiplayer" at the end). Host: numbers for the threats, kills and impacts
# repeated in the snapshots, friends' damage counted so far and what they earned and paid, and who
# shot down the wreck behind each debris event. Guest: the puppets, our damage totals, the events
# already handled and the part of the host's bank already in our budget. Both: missile launches.
var _net_seq := 0
var _last_target := {}
var _net_events: Array = []
var _net_applied := {}
var _net_bank := {}
var _event_owner := {}
var net_enemies := {}
var _net_hits := {}
var _net_done := {}
var _bank_seen := {}
var _bank_init := false
var _net_launches: Array = []
var _launch_seq := 0
var _launch_seen := {}
## Guest: how far puppets had drifted from each new snapshot (the error the smoothing hides).
var net_err_sum := 0.0
var net_err_n := 0
var net_err_max := 0.0


func _ready() -> void:
	_rng.randomize()
	_base_time_scale = Engine.time_scale
	fx_root = Node3D.new()
	add_child(fx_root)
	enemy_root = Node3D.new()
	add_child(enemy_root)
	base_node = Meshes.base()
	base_node.position = GS.base_pos
	add_child(base_node)
	_lights = base_node.get_meta("lights")
	camo_node = Meshes.camo_net()
	camo_node.position = GS.base_pos
	camo_node.visible = GS.camo
	add_child(camo_node)
	for id in GS.WEAPON_ORDER:
		if GS.unlocked.get(id, false):
			add_weapon(id)
	predict_marker = MeshInstance3D.new()
	predict_marker.mesh = Fx.ring_mesh(16.0, 2.0)
	predict_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	predict_marker.visible = false
	add_child(predict_marker)
	range_ring = MeshInstance3D.new()
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_ring.position = GS.base_pos + Vector3(0, 1.5, 0)
	add_child(range_ring)
	rig = CameraRig.new()
	rig.cam = cam
	rig.target = GS.base_pos
	add_child(rig)
	rig.clicked.connect(_on_click)
	base_view = BaseView.new()
	base_view.game = self
	base_view.cam = cam
	add_child(base_view)
	fpv_view = FpvView.new()
	fpv_view.game = self
	fpv_view.cam = cam
	add_child(fpv_view)
	walker = Walker.new()
	walker.game = self
	walker.map = map
	walker.cam = cam
	add_child(walker)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	director = Director.new()
	director.game = self
	add_child(director)
	fire_service = FireService.new()
	fire_service.game = self
	add_child(fire_service)
	reel = Reel.new()
	reel.game = self
	reel.cam = cam
	reel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(reel)
	remote = RemotePlayers.new()
	remote.game = self
	add_child(remote)
	map.apply_damage_list(GS.damaged)
	map.apply_crush_list(GS.crushed)
	select_weapon(selected_weapon)
	GS.money_changed.connect(_on_money_changed)
	Net.raid_received.connect(net_apply_raid)
	Net.map_received.connect(net_apply_map)
	Net.guest_hits.connect(_on_guest_hits)
	Net.launches_received.connect(_on_launches)
	if Net.role == "guest":
		# what the host sent while we were choosing a position
		if not Net.map_state.is_empty():
			net_apply_map.call_deferred(Net.map_state)
		if not Net.raid.is_empty():
			net_apply_raid.call_deferred(Net.raid)


func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = _base_time_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_money_changed(_v: int) -> void:
	check_game_over()


## Recreates the HUD (after a language change) and reopens the pause menu.
func rebuild_hud() -> void:
	var old = hud
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	old.queue_free()
	hud._show_pause.call_deferred()


func save_progress() -> void:
	GS.damaged = map.damaged_list()
	GS.crushed = map.crushed_list()
	GS.save_world()


# --- Views ---------------------------------------------------------------------------------
func set_view(v: String) -> void:
	if v == view or game_over:
		return
	if v == "fpv" and (_fpv_drone == null or not is_instance_valid(_fpv_drone)):
		return # the console needs a drone in the air: see enter_fpv()
	var prev := view
	# leave the previous view
	if prev == "base":
		base_view.exit()
	elif prev == "walk":
		walker.exit()
	elif prev == "fpv":
		fpv_view.exit()
	elif prev == "watch":
		cam.fov = _watch_fov
		watch_code = ""
	view = v
	match v:
		"watch":
			rig.set_process(false)
			rig.set_process_unhandled_input(false)
			range_ring.visible = false
			hovered = null
			locked = null
			_watch_fov = cam.fov
		"base":
			rig.set_process(false)
			rig.set_process_unhandled_input(false)
			base_view.enter()
			range_ring.visible = false
			hovered = null
		"fpv":
			rig.set_process(false)
			rig.set_process_unhandled_input(false)
			range_ring.visible = false
			hovered = null
			locked = null
			fpv_view.enter(_fpv_drone, prev if prev != "fpv" else "top")
			_fpv_drone = null
		"walk":
			rig.set_process(false)
			rig.set_process_unhandled_input(false)
			range_ring.visible = false
			hovered = null
			locked = null
			var at: Vector3 = rig.target if prev == "top" else GS.base_pos + Vector3(0, 0, 44)
			walker.enter(at, rig.yaw)
			if auto_fire == 0:
				auto_fire = 1
				hud.log_event(GS.t("Пока вы гуляете, ствольная ПВО и дроны работают автоматически"), Color(0.6, 1.0, 0.8))
		_:
			rig.set_process(true)
			rig.set_process_unhandled_input(true)
			range_ring.visible = true
			locked = null
			if prev == "walk":
				rig.focus(walker.pos)
	hud.on_view_changed()


## Looks through a friend's camera until Esc / the view key (multiplayer).
func watch(code: String) -> void:
	if game_over or remote.eye_of(code) == null:
		return
	if view == "fpv":
		leave_fpv()
	watch_code = code
	if view == "watch":
		hud.on_view_changed()
	else:
		set_view("watch")


func toggle_view() -> void:
	if view == "watch":
		set_view("top")
		return
	if view == "fpv":
		leave_fpv()
		return
	set_view("top" if view != "top" else "base")


func toggle_walk() -> void:
	set_view("top" if view == "walk" else "walk")


## The on-screen hold button: fire / launch in the gunner view, boost on the FPV console.
func set_trigger(on: bool) -> void:
	if view == "fpv":
		fpv_view.set_trigger(on)
	else:
		base_view.set_trigger(on)


func refresh_capture() -> void:
	base_view.refresh_capture()
	fpv_view.refresh_capture()
	walker.refresh_capture()


## Label3D markers are replaced by the sight / video overlay in the gunner and FPV views.
func hide_markers() -> bool:
	return view == "base" or view == "fpv"


func zoom_view(f: float) -> void:
	if view == "base":
		base_view.zoom(f)
	elif view == "fpv":
		# the zoom buttons drive the throttle on the FPV console
		fpv_view.add_throttle(0.12 if f < 1.0 else -0.12)
	elif view == "top":
		rig.zoom(f)


func shake(amount: float) -> void:
	match view:
		"base":
			base_view.shake(amount)
		"fpv":
			fpv_view.shake(amount)
		"walk":
			walker.shake(amount)
		_:
			rig.shake(amount)


## Brief slow motion for spectacular kills in the gunner view.
func slowmo() -> void:
	# a shared raid runs on the host's clock: no bullet time in a multiplayer game
	if _slowmo or not bool(GS.settings.slowmo) or view != "base" or Net.is_online():
		return
	_slowmo = true
	Engine.time_scale = _base_time_scale * 0.3
	get_tree().create_timer(0.5, true, false, true).timeout.connect(_end_slowmo)


func _end_slowmo() -> void:
	Engine.time_scale = _base_time_scale
	_slowmo = false


# --- Interceptor drones ---------------------------------------------------------------------
## One drone leaves the rail. `tgt` may be null: an unassigned drone looks for work itself.
func spawn_drone(pos: Vector3, dir: Vector3, tgt) -> void:
	_drone_seq += 1
	var d := Drone.new()
	d.game = self
	d.target = tgt
	d.serial = _drone_seq
	d.speed = 45.0
	d.vel = (dir.normalized() + Vector3.UP * 0.35).normalized() * d.speed
	d.position = pos
	fx_root.add_child(d)
	drones.append(d)
	GS.stats.drones = int(GS.stats.get("drones", 0)) + 1
	Fx.explosion(fx_root, pos, 0.18, Color(0.7, 1.0, 0.8))
	var what: String = GS.t(String(tgt.def.name)) if tgt != null and is_instance_valid(tgt) else GS.t("свободная охота")
	hud.log_event(GS.t("Взлёт: дрон #%d → %s") % [_drone_seq, what], Color(0.5, 1.0, 0.8))
	if view == "base":
		shake(0.15)


## The rack sends one more drone up on the player's order. Returns the drone, or null when
## the rack is empty, reloading or not bought yet.
func launch_drone(announce := true):
	var w = weapons.get("drone")
	if w == null:
		if announce:
			hud.alert(GS.t("Дроны-перехватчики не куплены — магазин [B]"), Color(1.0, 0.7, 0.3))
		return null
	var tgt = find_auto_target(w)
	if tgt == null:
		var best := INF
		for e in enemies:
			if e.dead or not w.can_engage(e) or e.inbound >= e.hp:
				continue
			var dd: float = w.global_position.distance_to(e.position)
			if dd < best:
				best = dd
				tgt = e
	var before := drones.size()
	if not w.launch_at(tgt, announce):
		return null
	return drones[drones.size() - 1] if drones.size() > before else null


## [C] — sit down at the FPV console: take the freshest drone in the air, or send a new one up.
func enter_fpv() -> void:
	if game_over or view == "fpv":
		return
	if not GS.unlocked.get("drone", false):
		hud.alert(GS.t("%s ещё не куплен — откройте магазин [B]") % GS.t(String(GS.WEAPONS["drone"].name)), Color(1.0, 0.7, 0.3))
		return
	var d = drones[drones.size() - 1] if not drones.is_empty() else launch_drone()
	if d == null:
		return
	_fpv_drone = d
	set_view("fpv")


func leave_fpv() -> void:
	if view != "fpv":
		return
	var back: String = String(fpv_view.return_view)
	set_view(back if back != "fpv" else "top")


## A drone was lost, rammed its target or landed back home.
func on_drone_gone(d) -> void:
	drones.erase(d)
	if fpv_view != null and fpv_view.drone == d:
		# the feed dies with the drone: a moment of static, then the next drone or the old view
		fpv_view.feed_lost()


## Ram hit scored while the player was flying the drone by hand.
func fpv_hit(e) -> void:
	GS.stats.fpv_rams = int(GS.stats.get("fpv_rams", 0)) + 1
	if fpv_view != null and fpv_view.active:
		fpv_view.on_hit(e)


## Morning: everything still airborne comes home and goes back into the magazine.
func recall_drones() -> void:
	if drones.is_empty():
		return
	if view == "fpv":
		leave_fpv()
	for d in drones:
		if is_instance_valid(d):
			d.order_home()
	hud.log_event(GS.t("Отбой: дроны возвращаются на базу (%d)") % drones.size(), Color(0.5, 1.0, 0.7))


# --- Weapons -------------------------------------------------------------------------------
## Position of one system around the base, by its place in the roster and its class.
func slot_pos(id: String) -> Vector3:
	var n: int = GS.WEAPON_ORDER.size()
	var i: int = maxi(0, GS.WEAPON_ORDER.find(id))
	var a := deg_to_rad(-160.0 + 320.0 * float(i) / float(maxi(1, n - 1)))
	var r: float = float(SLOT_RING.get(String(GS.WEAPONS[id].get("class", "gun")), 20.0))
	return Vector3(sin(a) * r, 0, cos(a) * r)


func add_weapon(id: String) -> void:
	if weapons.has(id):
		return
	var w := WeaponUnit.new()
	w.setup(self, id, GS.base_pos + slot_pos(id))
	add_child(w)
	weapons[id] = w


## The systems actually bought, in roster order — what the panel and the number keys address.
func owned_weapons() -> Array:
	var out := []
	for id in GS.WEAPON_ORDER:
		if GS.unlocked.get(id, false):
			out.append(id)
	return out


## Bought systems of one control group: what the open tab shows and 1..9 select.
func owned_in_group(g: String) -> Array:
	var out := []
	for id in GS.WEAPON_ORDER:
		if GS.unlocked.get(id, false) and String(GS.WEAPONS[id].get("group", "manual")) == g:
			out.append(id)
	return out


func group_of(id: String) -> String:
	return String(GS.WEAPONS[id].get("group", "manual"))


## Opens a tab and takes its first system, so one click (or key) is enough to switch.
func select_group(g: String) -> void:
	var own := owned_in_group(g)
	weapon_group = g
	if not own.is_empty() and group_of(selected_weapon) != g:
		select_weapon(String(own[0]))
	else:
		hud.refresh()


## 1..9 — the bought systems in roster order, regardless of which tab is open.
func select_slot(i: int) -> void:
	var own := owned_weapons()
	if i >= 0 and i < own.size():
		select_weapon(String(own[i]))


## Steps through the whole battery; the panel tab follows the selection.
func cycle_weapon(step: int) -> void:
	var own := owned_weapons()
	if own.is_empty():
		return
	var i: int = own.find(selected_weapon)
	select_weapon(String(own[posmod(i + step, own.size())]))


func select_weapon(id: String) -> void:
	if not GS.unlocked.get(id, false):
		hud.alert(GS.t("%s ещё не куплен — откройте магазин [B]") % GS.t(String(GS.WEAPONS[id].name)), Color(1.0, 0.7, 0.3))
		return
	var prev := selected_weapon
	selected_weapon = id
	weapon_group = group_of(id)
	var r: float = weapons[id].effective_range()
	range_ring.mesh = Fx.ring_mesh(r, 2.0 + r * 0.002)
	range_ring.material_override = Fx.ghost(Color(0.2, 1.0, 0.6, 0.18), 1.0)
	if view == "base":
		base_view.on_weapon_changed(prev)
	hud.refresh()


## Smart auto-fire: engage the nearest target in range whose debris would fall somewhere
## safe; hold fire over houses unless the threat is about to reach its objective.
func find_auto_target(w):
	var best = null
	var best_d := INF
	for e in enemies:
		if e.dead or not w.can_engage(e):
			continue
		if w.def.kind == "gun" and e.type == "ballistic":
			continue
		if w.def.kind == "missile" and auto_fire < 2 and not autotest:
			continue
		if w.def.kind != "gun" and e.inbound >= e.hp:
			# already lethally committed: another interceptor would be thrown away
			continue
		var d: float = w.global_position.distance_to(e.position)
		if d > w.effective_range() * 1.02 or d >= best_d:
			continue
		var to_goal := Vector2(e.target_pos.x - e.position.x, e.target_pos.z - e.position.z).length()
		var urgent: bool = e.type != "scout" and (to_goal < 260.0 or d < 90.0)
		if not urgent and not predict_debris(e).safe:
			continue
		best_d = d
		best = e
	return best


func spawn_bullet(pos: Vector3, vel: Vector3, wid: String, life: float, manual := false) -> void:
	var b := Bullet.new()
	b.game = self
	b.vel = vel
	b.life = life
	b.weapon_id = wid
	b.damage = float(GS.WEAPONS[wid].damage)
	b.color = Color(1.0, 0.35, 0.12) if wid == "mg" else Color(1.0, 0.85, 0.3)
	b.manual = manual
	b.position = pos
	fx_root.add_child(b)


func spawn_missile(pos: Vector3, dir: Vector3, tgt, wid: String) -> void:
	var m := Missile.new()
	m.game = self
	m.target = tgt
	m.weapon_id = wid
	m.vel = dir.normalized() * 40.0
	m.position = pos
	fx_root.add_child(m)
	_net_note_launch(pos, tgt, wid)
	# launch: blast of smoke and a flash that lights the base
	var puff := Node3D.new()
	fx_root.add_child(puff)
	puff.global_position = pos
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.light_energy = 12.0
	l.omni_range = 90.0
	puff.add_child(l)
	var smoke := Fx.exhaust(Color(0.6, 0.55, 0.5), 30, 2.5, 4.0)
	smoke.material_override = Fx.smoke_mat()
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.spread = 60.0
	smoke.initial_velocity_min = 4.0
	smoke.initial_velocity_max = 12.0
	smoke.emitting = true
	puff.add_child(smoke)
	var tw := puff.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	tw.tween_callback(puff.queue_free).set_delay(3.0)
	hud.log_event(GS.t("Пуск %s → %s") % [GS.t(String(GS.WEAPONS[wid].short)), GS.t(String(tgt.def.name))], Color(0.6, 0.9, 1.0))
	if view == "base":
		shake(0.4)


# --- Nightly highlight reel -----------------------------------------------------------------
## How much a kill is worth to the edit: a ballistic intercept always makes the cut, a scout
## rarely does.
const CLIP_SCORE := {"ballistic": 4.0, "cruise": 2.5, "shahed": 1.0, "scout": 0.6}


## Somebody on a balcony filmed this one: remembered until the morning edit.
func record_clip(e) -> void:
	if night_clips.size() > 80:
		return
	night_clips.append({
		"t": int(director.phase_time),
		"p": [e.position.x, e.position.y, e.position.z],
		"v": [e.vel.x, e.vel.y, e.vel.z],
		"type": String(e.type),
		"variant": String(e.variant),
		"by": String(e.last_hit_by),
		"manual": view == "base" or view == "fpv",
		"district": map.district_name(e.position.x, e.position.z),
	})


## Morning: the channel cuts the best six clips of the night into one 30-second video.
func publish_video(day_n: int) -> Dictionary:
	var pool: Array = night_clips
	night_clips = []
	if pool.is_empty():
		return {}
	for c in pool:
		var s: float = float(CLIP_SCORE.get(String(c.type), 1.0))
		if bool(c.manual):
			s += 2.0
		if String(c.by) == "drone":
			s += 1.2
		c["score"] = s + _rng.randf() * 0.9
	pool.sort_custom(func(a, b) -> bool: return float(a.score) > float(b.score))
	var picked: Array = pool.slice(0, mini(GS.VIDEO_CLIPS, pool.size()))
	picked.sort_custom(func(a, b) -> bool: return int(a.t) < int(b.t))
	var likes := 0
	for c in picked:
		c["author"] = String(GS.video_authors()[_rng.randi() % GS.video_authors().size()])
		c["caption"] = _caption(c)
		c["likes"] = int(300.0 + 2400.0 * float(c.score) + float(_rng.randi() % 800))
		c["comments"] = int(float(c.likes) * 0.06)
		c.erase("score")
		likes += int(c.likes)
	var v := {"day": day_n, "clips": picked, "likes": likes, "views": int(float(likes) * 3.4)}
	GS.add_video(v)
	hud.log_event(GS.t("%s выложил нарезку ночи %d — %d роликов") % [GS.video_channel(), day_n, picked.size()], Color(0.6, 0.9, 1.0))
	return v


func _caption(c: Dictionary) -> String:
	var what: String = GS.t(String(GS.ENEMIES.get(String(c.get("variant", c.type)), GS.ENEMIES[String(c.type)]).name))
	var where: String = GS.t(String(c.district))
	if bool(c.manual):
		return GS.t("Руками! %s над районом %s") % [what, where]
	match _rng.randi() % 4:
		0:
			return GS.t("%s над районом %s — минус один!") % [what, where]
		1:
			return GS.t("Сбили прямо над нами · %s") % where
		2:
			return GS.t("%s шёл на район %s. Не зашёл.") % [what, where]
	return GS.t("Ночь, район %s, работает ПВО") % where


## Opens the compilation of a given night (0 = the latest one).
func play_video(day_n := 0) -> void:
	var v: Dictionary = GS.latest_video() if day_n <= 0 else GS.video_for_day(day_n)
	if v.is_empty() or (v.get("clips", []) as Array).is_empty():
		hud.alert(GS.t("За эту ночь роликов нет"), Color(1.0, 0.7, 0.3))
		return
	hud.open_video(v)


# --- Threats ---------------------------------------------------------------------------------
## Where a raid comes from. A weapon with its own launch area (the Kalibr from the sea, a KAB
## from over the border) keeps to it; for the rest half of the raids cross the player's sector.
func _edge_dir(variant := "") -> Vector3:
	var own: Array = map.city.raid_sectors.get(variant, [])
	var b := Vector2(GS.base_pos.x, GS.base_pos.z)
	if own.is_empty() and b.length() > 250.0 and _rng.randf() < 0.5:
		var ba := atan2(b.x, -b.y) + deg_to_rad(_rng.randf_range(-25.0, 25.0))
		return Vector3(sin(ba), 0, -cos(ba))
	var sectors: Array = own if not own.is_empty() else map.city.threat_sectors
	var a := deg_to_rad(float(sectors[_rng.randi_range(0, sectors.size() - 1)]) + _rng.randf_range(-15.0, 15.0))
	return Vector3(sin(a), 0, -cos(a))


## Strike targets near the player's sector are more likely (the base defends its district).
func _pick_target() -> Dictionary:
	var weights: Array[float] = []
	var total := 0.0
	for t in map.targets:
		var d := Vector2(t.pos.x - GS.base_pos.x, t.pos.z - GS.base_pos.z).length()
		var w := exp(-d / 450.0) + 0.04
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return map.targets[i]
	return map.targets[map.targets.size() - 1]


## Launches `count` threats of one weapon (a key of GS.ENEMIES). `aim` names the object when the
## strike is meant for one particular target (the Oreshnik on Pivdenmash).
## Threats launched this session by weapon (the test summary prints it).
var launched := {}


func launch(type: String, count: int, at_base: bool, alt := -1.0, aim := "") -> void:
	if not GS.ENEMIES.has(type):
		type = "shahed"
	launched[type] = int(launched.get(type, 0)) + count
	var def: Dictionary = GS.ENEMIES[type]
	var kind := GS.kind_of(type)
	var tgt_pos: Vector3
	var tgt_name: String
	if at_base:
		tgt_pos = GS.base_pos + Vector3(0, 1, 0)
		tgt_name = GS.t("База ПВО")
	else:
		var t: Dictionary = _pick_target()
		for tt in map.targets:
			if aim != "" and String(tt.name) == aim:
				t = tt
		tgt_pos = t.pos
		tgt_name = t.name
		_last_target = t
	# multiplayer: a strike "on the base" may be meant for any battery in the city
	var base_owner := ""
	var tidx: int = -2 if at_base else map.targets.find(_last_target)
	if at_base and Net.role == "host":
		var bases := [["", GS.base_pos]]
		for c in Net.others():
			if bool(Net.players[c].has_base):
				bases.append([String(c), Net.players[c].base])
		var pick: Array = bases[_rng.randi() % bases.size()]
		base_owner = String(pick[0])
		if base_owner != "":
			tgt_pos = (pick[1] as Vector3) + Vector3(0, 1, 0)
			tgt_name = GS.t("База %s") % String(Net.players[base_owner].nick)
	var dir := _edge_dir(type)
	var side := Vector3(-dir.z, 0, dir.x)
	var glide: bool = def.get("glide", false)
	var corridor := not at_base and not glide and ((kind == "shahed" and _rng.randf() < 0.8) or (kind == "cruise" and _rng.randf() < 0.6))
	var via_center := GS.base_pos + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(20.0, 110.0)
	for i in count:
		var start: Vector3
		var ealt := alt * _rng.randf_range(0.85, 1.15) if alt > 0.0 else -1.0
		if def.has("mirv"):
			# a re-entry body falls almost straight down on its target
			start = tgt_pos + dir * 260.0 + side * _rng.randf_range(-60, 60) + Vector3(0, 2300.0, 0)
		elif kind == "ballistic":
			var la: Array = def.get("launch_alt", [300.0, 520.0])
			start = dir * float(def.get("launch_dist", 1700.0)) + side * _rng.randf_range(-200, 200) + Vector3(0, _rng.randf_range(float(la[0]), float(la[1])), 0)
		elif glide:
			start = dir * float(def.get("launch_dist", 1350.0)) + side * ((i - count * 0.5) * 70.0 + _rng.randf_range(-20, 20))
			start.y = _rng.randf_range(float(def.alt_min), float(def.alt_max))
		else:
			var row := i / 4
			var col := i % 4
			start = dir * (1150.0 + row * 45.0) + side * ((col - 1.5) * 40.0 + _rng.randf_range(-10, 10))
			start.y = ealt if ealt > 0.0 else _rng.randf_range(float(def.alt_min), float(def.alt_max))
		var e := Enemy.new()
		var jitter := Vector3.ZERO
		if (kind == "shahed" or glide) and not at_base:
			jitter = Vector3(_rng.randf_range(-60, 60), 0, _rng.randf_range(-60, 60))
		elif def.has("mirv"):
			jitter = Vector3(_rng.randf_range(-70, 70), 0, _rng.randf_range(-70, 70))
		e.setup(self, type, start, tgt_pos + jitter, tgt_name, ealt)
		e.strike_base = at_base
		_net_seq += 1
		e.net_id = _net_seq
		e.net_target = tidx
		e.net_base_owner = base_owner
		if corridor:
			e.has_via = true
			e.via = via_center + Vector3(_rng.randf_range(-25, 25), 0, _rng.randf_range(-25, 25))
		enemy_root.add_child(e)
		enemies.append(e)
	if type == "scout":
		hud.log_event(GS.t("Замечен разведчик «Орлан» — ищет вашу базу"), Color(0.4, 0.9, 1.0))
		return
	var label: String = GS.t(String(def.plural))
	if count > 1:
		label += " ×%d" % count
	var alt_txt := ""
	if alt > 0.0:
		alt_txt = GS.t(" · высота ~%d м") % int(alt * 5.0)
	hud.alert(GS.t("⚠ ТРЕВОГА: ПУСК %s!") % label, Color(1.0, 0.25, 0.25))
	hud.log_event(GS.t("Пуск: %s → %s%s") % [label, tgt_name, alt_txt], Color(1.0, 0.45, 0.35))
	SFX.play("alert", -4.0)


func enemy_destroyed(e) -> void:
	# a friend's hit that brought it down earns them the reward (multiplayer host)
	var killer := _killer_of(e)
	var reward := _reward_for(e, killer)
	if killer == "":
		GS.add_money(reward)
		GS.stats.kills = int(GS.stats.kills) + 1
	else:
		_bank(killer, "e", reward)
		_bank(killer, "k", 1)
	record_clip(e)
	_event_seq += 1
	_event_owner[_event_seq] = killer
	var airburst := false
	var warhead := false
	match String(e.type):
		"ballistic":
			airburst = true
		"shahed":
			airburst = _rng.randf() < 0.45
			warhead = not airburst
		"cruise":
			airburst = _rng.randf() < 0.55
			warhead = not airburst
	if Net.role == "host" and e.net_id >= 0:
		var p: Vector3 = e.position
		var v: Vector3 = e.vel
		_net_event("k", e.net_id, [killer if killer != "" else Net.code(), _r(p.x), _r(p.y), _r(p.z), _r(v.x), _r(v.y), _r(v.z), 1 if airburst else 0, 1 if warhead else 0, reward])
	_kill_fx(e, airburst, warhead, reward, killer, false)
	# gunner-view feedback
	if killer != "":
		_remove_enemy(e)
		return
	if view == "base":
		var info := predict_debris(e)
		var dist: float = cam.global_position.distance_to(e.position)
		var txt := GS.t("ЦЕЛЬ ПОРАЖЕНА  +%s") % GS.fmt_money(reward)
		if not bool(info.safe):
			txt += GS.t("\nобломки летят на дома!")
		hud.reticle.kill(txt, Color(0.3, 1.0, 0.5) if bool(info.safe) else Color(1.0, 0.7, 0.2))
		if dist < 500.0:
			hud.flash(clampf(0.5 - dist / 1200.0, 0.08, 0.45))
		shake(clampf(1.0 - dist / 900.0, 0.1, 0.8))
		if e.type == "cruise" or e.type == "ballistic" or e == base_view.candidate:
			slowmo()
	_remove_enemy(e)


## An interceptor detonated without a lethal hit — told to the player so that spent
## missiles are never a mystery (`dist` is in world units, 1 unit ≈ 5 m).
func missile_missed(m, dist: float) -> void:
	GS.stats.misses = int(GS.stats.get("misses", 0)) + 1
	var short: String = GS.t(String(m.def.short))
	Fx.float_text(fx_root, m.position, GS.t("ПРОМАХ"), Color(1.0, 0.55, 0.25))
	hud.log_event(GS.t("Промах: ракета %s прошла в %d м от цели") % [short, int(dist * 5.0)], Color(1.0, 0.55, 0.25))
	if view == "base":
		hud.reticle.kill(GS.t("ПРОМАХ"), Color(1.0, 0.6, 0.3))


## How much of a building a warhead takes down, by weapon type.
const STRIKE_CRUSH := {"shahed": 0.15, "cruise": 0.25, "ballistic": 0.35}


## A warhead going off over the city: the building under it loses its upper floors, the rubble
## comes down into the street and what is left burns until the fire service arrives.
func strike_damage(p: Vector3, type: String, scale := 1.0, size := 1.6) -> void:
	var bi: int = map.building_at(p.x, p.z)
	if bi >= 0:
		var lost: float = map.crush_building(bi, float(STRIKE_CRUSH.get(type, 0.12)) * scale)
		if lost > 0.0:
			collapse_fx(bi, lost)
	fire_service.start_fire(Vector3(p.x, map.ground_height(p.x, p.z), p.z), bi, size)


## Floors coming down: chunks of wall tumble off the break and a dust cloud rolls out.
func collapse_fx(bi: int, lost: float) -> void:
	var c: Vector3 = map.fp_center[bi]
	var half: Vector2 = map.fp_half[bi]
	var top: float = c.y
	var n := clampi(int(lost * 0.7), 3, 12)
	for i in n:
		var r := Rubble.new()
		r.game = self
		var s := _rng.randf_range(1.4, 3.6)
		r.mesh = Fx.cube(Vector3(s, s * _rng.randf_range(0.4, 1.0), s * _rng.randf_range(0.6, 1.2)))
		r.material_override = Fx.solid(Color(0.42, 0.4, 0.38).lerp(Color(0.2, 0.18, 0.17), _rng.randf()), 0.95)
		r.position = Vector3(c.x + _rng.randf_range(-half.x, half.x), top + _rng.randf_range(0.0, lost * 0.5),
			c.z + _rng.randf_range(-half.y, half.y))
		r.vel = Vector3(_rng.randf_range(-9, 9), _rng.randf_range(0, 6), _rng.randf_range(-9, 9))
		fx_root.add_child(r)
	var dust := Fx.exhaust(Color(0.72, 0.7, 0.66), 44, 3.4, 4.5)
	dust.material_override = Fx.smoke_mat()
	dust.one_shot = true
	dust.explosiveness = 0.75
	dust.spread = 70.0
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 16.0
	dust.gravity = Vector3(0, 1.5, 0)
	dust.position = Vector3(c.x, top, c.z)
	dust.emitting = true
	fx_root.add_child(dust)
	get_tree().create_timer(6.0, false).timeout.connect(dust.queue_free)
	play_3d("boom_small", Vector3(c.x, top, c.z), -2.0)


func enemy_impact(e) -> void:
	var p: Vector3 = e.position
	var friend_base: bool = e.strike_base and e.net_base_owner != ""
	if Net.role == "host" and e.net_id >= 0:
		var decoy: bool = e.def.get("decoy", false) and not e.strike_base
		var flags := (1 if decoy else 0) | (2 if e.strike_base else 0) | (4 if e.missed or e.crippled else 0)
		var dmg := float(e.def.hit_damage) * 2.5 if e.strike_base else 0.0
		_net_event("i", e.net_id, [_r(p.x), _r(p.y), _r(p.z), flags, e.net_base_owner if friend_base else Net.code(), dmg, String(e.variant)])
	if e.def.get("decoy", false) and not e.strike_base:
		# a foam decoy has no warhead: it only breaks up where it comes down
		Fx.ground_hit(fx_root, p)
		play_3d("boom_small", p, -10.0)
		hud.log_event(GS.t("%s упала — без боевой части") % GS.t(String(e.def.name)), Color(0.8, 0.85, 0.7))
		_remove_enemy(e)
		return
	Fx.explosion(fx_root, p, 2.2, Color(1.0, 0.45, 0.1), true)
	strike_damage(p, String(e.type), float(e.def.get("crush", 1.0)), 2.0)
	for k in int(e.def.get("mirv", 0)) - 1:
		# kinetic submunitions: a spray of hits around the aim point
		var q := p + Vector3(_rng.randf_range(-45, 45), 0, _rng.randf_range(-45, 45))
		q.y = map.ground_height(q.x, q.z)
		Fx.explosion(fx_root, q, 1.0, Color(1.0, 0.7, 0.3), false)
		strike_damage(q, String(e.type), float(e.def.get("crush", 1.0)) * 0.5, 1.2)
	play_boom("explosion", p, 6.0)
	shake(clampf(1.0 - cam.global_position.distance_to(p) / 1200.0, 0.2, 1.0))
	if friend_base:
		# a friend's battery: they take the damage on their side, the repair bill goes with it
		_bank(e.net_base_owner, "p", int(float(e.def.hit_cost) * 0.5 * GS.penalty_mult()))
		hud.log_event(GS.t("Удар по базе %s: %s") % [_nick_of(e.net_base_owner), GS.t(String(e.def.name))], Color(1, 0.35, 0.3))
	elif e.strike_base:
		var dmg: float = float(e.def.hit_damage) * 2.5
		GS.base_hp = maxf(0.0, GS.base_hp - dmg)
		GS.add_money(-int(float(e.def.hit_cost) * 0.5 * GS.penalty_mult()))
		hud.alert(GS.t("УДАР ПО БАЗЕ! Повреждения −%d%%") % int(dmg), Color(1, 0.2, 0.2))
		hud.log_event(GS.t("Удар по базе: %s") % GS.t(String(e.def.name)), Color(1, 0.2, 0.2))
		if view == "base":
			hud.flash(0.6)
	elif e.missed or e.crippled:
		# A weapon thrown off course (or shot up and out of control) comes down off target:
		# cheaper than a hit on the object it was aimed at, but the house still burns.
		var what_hit: String = GS.t(String(e.def.name))
		var bi: int = map.building_at(p.x, p.z)
		if bi >= 0:
			var kind: int = map.building_kind(bi)
			var base_cost := maxf(float(GS.HOME_HIT_COST), float(e.def.hit_cost) * 0.6)
			var cost := _split_cost(int(base_cost * float(GS.KIND_PENALTY[kind]) * GS.penalty_mult()), "h")
			GS.add_money(-cost)
			GS.city = maxf(0.0, GS.city - 3.0 - float(e.def.hit_damage) * 0.25)
			GS.stats.homes = int(GS.stats.get("homes", 0)) + 1
			for i in _buildings_near(p, 14.0 + float(e.def.hit_damage)):
				map.damage_building(i)
			var what: String = map.building_name(bi)
			hud.alert(GS.t("%s ПОПАЛ В %s!  −%s") % [what_hit.to_upper(), what.to_upper(), GS.fmt_money(cost)], Color(1, 0.3, 0.2))
			hud.log_event(GS.t("%s: %s упал на %s") % [GS.t("Подбит") if e.crippled else GS.t("Сбит с курса РЭБ"), what_hit, what], Color(1, 0.35, 0.25))
		else:
			hud.log_event(GS.t("%s промахнулся и упал на пустырь — без жертв") % what_hit, Color(0.6, 1.0, 0.7))
	else:
		var cost := _split_cost(int(float(e.def.hit_cost) * GS.penalty_mult()), "i")
		GS.city = maxf(0.0, GS.city - float(e.def.hit_damage))
		GS.add_money(-cost)
		GS.stats.impacts = int(GS.stats.impacts) + 1
		for i in _buildings_near(p, 32.0):
			map.damage_building(i)
		hud.alert(GS.t("ПОПАДАНИЕ: %s  −%s") % [GS.t(e.target_name), GS.fmt_money(cost)], Color(1, 0.25, 0.2))
		hud.log_event(GS.t("Прилёт по объекту «%s»") % GS.t(e.target_name), Color(1, 0.3, 0.2))
		for t in map.targets:
			if String(t.get("kind", "")) == "tpp" and Vector2(t.pos.x - p.x, t.pos.z - p.z).length() < 90.0:
				map.add_blackout(t.pos, 420.0)
				hud.alert(GS.t("БЛЭКАУТ: %s повреждена — район без света") % GS.t(String(t.name)), Color(1.0, 0.8, 0.3))
				hud.log_event(GS.t("Блэкаут вокруг «%s»") % GS.t(String(t.name)), Color(1.0, 0.8, 0.3))
	GS.state_changed.emit()
	_remove_enemy(e)
	check_game_over()


func enemy_left(e) -> void:
	_remove_enemy(e)


func base_detected(_scout) -> void:
	GS.base_found = true
	GS.state_changed.emit()
	hud.alert(GS.t("⚠ РАЗВЕДЧИК ОБНАРУЖИЛ БАЗУ! Ночью ждите точный удар"), Color(1.0, 0.7, 0.2))
	hud.log_event(GS.t("База раскрыта противником!"), Color(1.0, 0.6, 0.2))
	SFX.play("alert", -2.0)


func on_enemy_crippled(_e) -> void:
	hud.alert(GS.t("Подбитый шахед потерял управление — падает!"), Color(1.0, 0.6, 0.2))


func on_manual_hit(_e) -> void:
	hud.reticle.hit()


func _remove_enemy(e) -> void:
	enemies.erase(e)
	if locked == e:
		locked = null
	if hovered == e:
		hovered = null
	e.queue_free()


func _buildings_near(p: Vector3, r: float) -> Array:
	var out := []
	var x := p.x - r
	while x <= p.x + r:
		var z := p.z - r
		while z <= p.z + r:
			var bi: int = map.building_at(x, z)
			if bi >= 0 and not out.has(bi):
				out.append(bi)
			z += 6.0
		x += 6.0
	return out


# --- Debris ------------------------------------------------------------------------------
func debris_landed(d, gh: float) -> void:
	var p: Vector3 = d.position
	var notes: Dictionary = _event_notes.get(d.event_id, {})
	_event_notes[d.event_id] = notes
	var boom: bool = d.wreck != null and d.warhead
	if boom:
		Fx.explosion(fx_root, p + Vector3(0, 2, 0), 1.3, Color(1.0, 0.5, 0.12), true)
		play_boom("explosion", p, 2.0)
		shake(clampf(1.0 - cam.global_position.distance_to(p) / 900.0, 0.1, 0.7))
	var bi: int = map.building_at(p.x, p.z)
	if d.cosmetic:
		# a guest's copy of the host's wreck: the roof, the fine and the fire come with the host's map
		if bi >= 0:
			Fx.ground_hit(fx_root, p)
			play_3d("boom_small", p, -8.0)
		elif map.zone_at(p.x, p.z) == GS.Zone.WATER:
			Fx.splash(fx_root, p)
			play_3d("splash", p, -6.0)
		else:
			Fx.ground_hit(fx_root, p)
		return
	# the wreck of a friend's kill is on their bill (multiplayer host)
	var owner := String(_event_owner.get(d.event_id, ""))
	if bi >= 0:
		var kind: int = map.building_kind(bi)
		var fresh: bool = map.damage_building(bi)
		# A roof is paid for once: further pieces of the same wreck only add scrap-clearing costs.
		var pen := int(float(d.penalty) * float(GS.KIND_PENALTY[kind]) * GS.penalty_mult()
			* (1.5 if boom else 1.0) * (1.0 if fresh else 0.25))
		if owner != "":
			_bank(owner, "p", pen)
			if fresh:
				_bank(owner, "r", 1)
		else:
			GS.add_money(-pen)
			if fresh:
				GS.stats.roofs = int(GS.stats.roofs) + 1
		if fresh:
			fire_service.start_fire(Vector3(p.x, gh, p.z), bi, 1.4 if boom else 1.0)
		if boom:
			# a wreck with a live warhead takes the top floor with it
			var lost: float = map.crush_building(bi, 0.1)
			if lost > 0.0:
				collapse_fx(bi, lost)
		Fx.ground_hit(fx_root, p)
		var what: String = map.building_name(bi)
		Fx.float_text(fx_root, p, "−%s %s" % [GS.fmt_money(pen), what], Color(1.0, 0.3, 0.25))
		play_3d("boom_small", p, -8.0)
		if not notes.has("roof"):
			notes["roof"] = true
			hud.log_event(GS.t("%s упали на: %s! Штраф за ремонт") % [GS.t("Обломки с БЧ") if boom else GS.t("Обломки"), what], Color(1.0, 0.35, 0.3))
		return
	match map.zone_at(p.x, p.z):
		GS.Zone.WATER:
			Fx.splash(fx_root, p)
			play_3d("splash", p, -6.0)
			GS.stats.splash = int(GS.stats.splash) + 1
			if not notes.has("water"):
				notes["water"] = true
				Fx.float_text(fx_root, p, GS.ctext("water_safe"), Color(0.4, 0.8, 1.0))
		GS.Zone.FOREST:
			Fx.ground_hit(fx_root, p)
			if not notes.has("forest"):
				notes["forest"] = true
				Fx.float_text(fx_root, p, GS.t("в лес — без ущерба"), Color(0.4, 1.0, 0.5))
		_:
			Fx.ground_hit(fx_root, p)


## Where would the debris of this target land if it were shot down right now?
func predict_debris(e) -> Dictionary:
	var p: Vector3 = Debris.predict(map, e.position, e.vel)
	var bi: int = map.building_at(p.x, p.z)
	var zone: int = map.zone_at(p.x, p.z)
	var info := {"pos": p, "safe": true, "text": "", "color": Color(0.3, 1.0, 0.5)}
	if bi >= 0 or (map.urban_at(p.x, p.z) > 0 and _buildings_near(p, 12.0).size() > 0):
		info.safe = false
		var what: String = map.building_name(bi) if bi >= 0 else GS.t("жилая застройка")
		info.text = GS.t("%s — штраф!") % what.to_upper()
		info.color = Color(1.0, 0.25, 0.2)
	elif zone == GS.Zone.WATER:
		info.text = GS.ctext("water_label")
		info.color = Color(0.35, 0.8, 1.0)
	elif zone == GS.Zone.FOREST:
		info.text = GS.t("ЛЕС / ПАРК — безопасно")
	elif zone == GS.Zone.CITY:
		info.text = GS.t("УЛИЦА — риск для домов")
		info.color = Color(1.0, 0.75, 0.2)
		info.safe = false
	else:
		info.text = GS.t("ПОЛЕ — безопасно")
	return info


# --- Input -------------------------------------------------------------------------------
func pick_enemy(screen_pos: Vector2):
	var best = null
	var best_d := PICK_RADIUS
	for e in enemies:
		if e.dead or cam.is_position_behind(e.position):
			continue
		var sp := cam.unproject_position(e.position)
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func _on_click(pos: Vector2) -> void:
	if game_over or view != "top":
		return
	var e = pick_enemy(pos)
	var w = weapons.get(selected_weapon)
	if w == null:
		return
	if e == null:
		if w.target != null:
			w.target = null
			hud.log_event(GS.t("%s: прекратить огонь") % GS.t(String(w.def.short)), Color(0.7, 0.8, 0.8))
		return
	if not w.can_engage(e):
		hud.alert(GS.t("%s не может поразить: %s") % [GS.t(String(w.def.short)), GS.t(String(e.def.name))], Color(1.0, 0.6, 0.2))
		return
	w.target = e
	w.auto_assigned = false
	locked = e
	SFX.play("click", -4.0)
	if not w.in_range(e):
		hud.log_event(GS.t("%s: цель вне зоны — огонь при входе") % GS.t(String(w.def.short)), Color(1.0, 0.8, 0.4))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = (event as InputEventKey).keycode
	var battery: bool = view != "walk" and view != "fpv"
	# Esc always opens the pause menu, however the controls are rebound — or first closes the
	# player list / stops watching a friend
	if kc == KEY_ESCAPE:
		if hud.players_open():
			hud.toggle_players()
		elif view == "watch":
			set_view("top")
		else:
			hud.toggle_pause()
		return
	if view == "watch" and GS.action_of(kc) != "view" and GS.action_of(kc) != "pause" and GS.action_of(kc) != "shop" and GS.action_of(kc) != "feed":
		return # the battery is not ours to command while looking through a friend's eyes
	# 1..9 pick a system straight from the battery, whichever tab it lives on
	if kc >= KEY_1 and kc <= KEY_9:
		if battery:
			select_slot(kc - KEY_1)
		return
	match GS.action_of(kc):
		"weapon_prev":
			if battery:
				cycle_weapon(-1)
		"weapon_next":
			if battery:
				cycle_weapon(1)
		"fpv":
			if view == "fpv":
				leave_fpv()
			elif view != "walk":
				enter_fpv()
		"auto":
			if view != "walk":
				toggle_auto()
		"shop":
			hud.open_shop()
		"feed":
			hud.open_feed()
		"pause":
			hud.toggle_pause()
		"home":
			if view == "top":
				rig.focus(GS.base_pos)
		"view":
			toggle_view()
		"walk":
			toggle_walk()
		"night":
			if view == "base":
				base_view.nv = not base_view.nv
			elif view == "fpv":
				fpv_view.nv = not fpv_view.nv
				fpv_view.nv_auto = false


## [F] cycles: off -> barrels and drones -> the whole battery. Automatic fire still waits for a
## safe debris zone, so switching everything on does not mean shooting over the rooftops.
func toggle_auto() -> void:
	auto_fire = (auto_fire + 1) % 3
	hud.log_event(GS.t("Автоогонь: %s") % auto_mode_name(), Color(0.6, 1.0, 0.8))
	hud.refresh()


func auto_mode_name() -> String:
	match auto_fire:
		1:
			return GS.t("СТВОЛЫ И ДРОНЫ")
		2:
			return GS.t("ВСЯ БАТАРЕЯ")
	return GS.t("ВЫКЛ")


# --- Frame update ----------------------------------------------------------------------------
## Tab (the player list) is taken before the GUI can use it to move focus between buttons.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and Net.is_online():
		if GS.action_of((event as InputEventKey).keycode) == "players":
			get_viewport().set_input_as_handled()
			hud.toggle_players()


func _process(delta: float) -> void:
	_t += delta
	if view == "watch":
		var eye = remote.eye_of(watch_code) if Net.players.has(watch_code) else null
		if eye == null:
			hud.log_event(GS.t("Трансляция прервалась: игрок покинул мир"), Color(1.0, 0.75, 0.25))
			set_view("top")
		else:
			cam.global_transform = eye[0]
			cam.fov = eye[1]
	if Net.is_online():
		Net.set_local(GS.base_pos, GS.base_loc, cam.global_transform, cam.fov, view)
	if view == "top":
		var vp := get_viewport()
		hovered = pick_enemy(vp.get_mouse_position()) if not DisplayServer.is_touchscreen_available() else null
	var focus_e = hovered if hovered != null else locked
	if focus_e != null and is_instance_valid(focus_e) and not focus_e.dead:
		predict_info = predict_debris(focus_e)
		predict_info["enemy"] = focus_e
		predict_marker.visible = true
		predict_marker.position = predict_info.pos + Vector3(0, 1.0, 0)
		predict_marker.material_override = Fx.ghost(predict_info.color, 1.6)
		var s := 1.0 + 0.12 * sin(_t * 8.0)
		predict_marker.scale = Vector3(s, 1, s)
	else:
		predict_info = {}
		predict_marker.visible = false
	var spin: Node3D = base_node.get_meta("spin")
	spin.rotate_y(delta * 2.0)
	var night: float = map.night
	for i in _lights.size():
		var pivot: Node3D = _lights[i]
		pivot.visible = night > 0.45
		if not pivot.visible:
			continue
		if i == 0 and locked != null and is_instance_valid(locked) and not locked.dead:
			if (locked.position - pivot.global_position).length() > 1.0:
				pivot.look_at(locked.position, Vector3.UP)
		else:
			pivot.rotation = Vector3(0.55 + 0.25 * sin(_t * 0.23 + i * 2.0), sin(_t * 0.3 + i * 1.7) * 1.2 + i * PI, 0)
	camo_node.visible = GS.camo


func play_3d(sound: String, pos: Vector3, vol := 0.0, min_gap := 0.0) -> void:
	var d := cam.global_position.distance_to(pos)
	var att := clampf(1.0 - d / 2200.0, 0.05, 1.0)
	SFX.play(sound, vol + linear_to_db(att), 1.0, min_gap)


## Explosions are heard after they are seen (sound travels ~340 m/s; capped for gameplay).
func play_boom(sound: String, pos: Vector3, vol := 0.0) -> void:
	var delay := minf(cam.global_position.distance_to(pos) / 340.0, 2.5)
	if delay < 0.05:
		play_3d(sound, pos, vol)
		return
	var cb := func() -> void:
		if is_inside_tree():
			play_3d(sound, pos, vol)
	get_tree().create_timer(delay, false).timeout.connect(cb)


# --- Flow ------------------------------------------------------------------------------------
func on_morning(report: Dictionary) -> void:
	map.clear_blackouts()
	var vid := publish_video(int(report.get("day", GS.day)))
	report["clips"] = (vid.get("clips", []) as Array).size()
	recall_drones()
	# daylight: the crews get to everything that is still standing wrecked
	fire_service.sweep_damaged()
	hud.show_morning(report)


func check_game_over() -> void:
	if game_over:
		return
	var reason := ""
	if GS.base_hp <= 0.0:
		reason = GS.t("База ПВО уничтожена")
	elif GS.city <= 0.0:
		reason = GS.t("Город получил критические разрушения")
	elif GS.money <= GS.DEBT_LIMIT and not (director and director.is_night()):
		# Debt never ends the run mid-raid: the morning report writes part of it off first.
		reason = GS.t("Финансирование прекращено: огромные долги за ремонт")
	if reason != "":
		if view != "top":
			set_view("top")
		game_over = true
		SFX.stop_siren()
		hud.show_game_over(reason)


func purchase_weapon(id: String) -> bool:
	if GS.unlock_weapon(id):
		add_weapon(id)
		SFX.play("cash", -4.0)
		hud.log_event(GS.t("Получено: %s") % GS.t(String(GS.WEAPONS[id].name)), Color(0.4, 1.0, 0.6))
		select_weapon(id)
		return true
	return false


# --- Multiplayer: one raid for everybody ------------------------------------------------------------
## Kills and impacts stay in the snapshots this long, so a guest who missed one still sees it.
const NET_EVENT_KEEP := 4.0

## Explosion, debris and the falling airframe of a threat that went down. The debris of a guest's
## copy of a host kill (`cosmetic`) only shows where it lands: the host has counted the damage.
func _kill_fx(e, airburst: bool, warhead: bool, reward: int, killer: String, cosmetic: bool) -> void:
	var big: float = 1.8 if e.type == "ballistic" else (1.25 if e.type == "cruise" else 0.95)
	if not e.has_meta("boomed"):
		Fx.explosion(fx_root, e.position, big if airburst else big * 0.6, Color(1.0, 0.55, 0.15), airburst)
		play_boom("explosion", e.position, 0.0 if airburst else -4.0)
	var what := GS.t(String(e.def.name))
	var note := GS.t("сбит") if not airburst else GS.t("подрыв БЧ в воздухе")
	if killer == "" or killer == Net.code():
		Fx.float_text(fx_root, e.position, "+" + GS.fmt_money(reward), Color(0.3, 1.0, 0.5))
		hud.log_event(GS.t("Сбит: %s (%s)  +%s") % [what, note, GS.fmt_money(reward)], Color(0.35, 1.0, 0.55))
	else:
		var col := _color_of(killer)
		Fx.float_text(fx_root, e.position, _nick_of(killer), col)
		hud.log_event(GS.t("%s сбил: %s (%s)") % [_nick_of(killer), what, note], col)
	var n: int = int(e.def.debris) + (4 if airburst else 0)
	for i in n:
		var d := Debris.new()
		d.game = self
		d.event_id = _event_seq
		d.penalty = int(e.def.debris_penalty)
		d.cosmetic = cosmetic
		d.position = e.position + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1), _rng.randf_range(-2, 2))
		var spread := 22.0 if airburst else 12.0
		d.vel = e.vel * Debris.INERTIA + Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-4, 10), _rng.randf_range(-spread, spread))
		fx_root.add_child(d)
	if not airburst and e.model != null:
		# the airframe itself falls, burning and tumbling
		var m: Node3D = e.model
		e.remove_child(m)
		m.visible = true
		var w := Debris.new()
		w.game = self
		w.event_id = _event_seq
		w.penalty = int(e.def.debris_penalty) * 2
		w.cosmetic = cosmetic
		w.wreck = m
		w.warhead = warhead
		w.position = e.position
		w.rotation = e.rotation
		w.vel = e.vel * Debris.INERTIA + Vector3(0, 3, 0)
		fx_root.add_child(w)


func _r(v: float) -> float:
	return snappedf(v, 0.1)


## Who brought a threat down: "" = this machine, else a friend's code (host side).
func _killer_of(e) -> String:
	var by := String(e.last_hit_by)
	return by.substr(4) if by.begins_with("net:") else ""


## The reward for a kill, with the location bonus of the battery that made it.
func _reward_for(e, killer: String) -> int:
	var loc: int = GS.base_loc
	if killer != "" and Net.players.has(killer):
		loc = int(Net.players[killer].loc)
	var lm: float = float(GS.LOCATIONS[loc].reward) if GS.LOCATIONS.has(loc) else 1.0
	return int(round(float(e.def.reward) * lm * GS.income_mult()))


func _nick_of(code: String) -> String:
	return String(Net.players[code].nick) if Net.players.has(code) else GS.t("Игрок")


func _color_of(code: String) -> Color:
	return Net.players[code].color if Net.players.has(code) else Color(0.35, 0.8, 1.0)


## Host: adds to what a friend earned (e), paid (p) or scored (k kills, r roofs, i impacts, h homes).
func _bank(code: String, field: String, amount: int) -> void:
	if code == "" or code == Net.code():
		return
	if not _net_bank.has(code):
		_net_bank[code] = {"e": 0, "p": 0, "k": 0, "r": 0, "i": 0, "h": 0}
	_net_bank[code][field] = int(_net_bank[code][field]) + amount


## Host: a hit on the city is paid by everybody defending it. Returns the host's own share.
func _split_cost(cost: int, field: String) -> int:
	if Net.role != "host" or Net.players.size() <= 1:
		return cost
	var part := int(ceil(float(cost) / Net.players.size()))
	for c in Net.others():
		_bank(String(c), "p", part)
		if field != "":
			_bank(String(c), field, 1)
	return part


func _net_event(kind: String, id: int, data: Array) -> void:
	_net_events.append({"t": _t, "kind": kind, "id": id, "data": data})


func _enemy_by_key(key: String):
	if Net.role == "guest":
		var p = net_enemies.get(key)
		return p if p != null and is_instance_valid(p) else null
	var id := int(key.substr(1))
	for e in enemies:
		if e.net_id == id:
			return e
	return null


## Host: the raid as the guests see it (Net sends it RAID_EVERY). Every threat in the air as
## [variant, position, velocity, hp fraction, flags, target], the kills and impacts of the last
## seconds, each friend's earnings and how much of their damage has been counted.
func net_snapshot() -> Dictionary:
	var es := {}
	for e in enemies:
		if e.dead or e.net_id < 0:
			continue
		var p: Vector3 = e.position
		var v: Vector3 = e.vel
		var f := (1 if e.crippled else 0) | (2 if e.strike_base else 0)
		es["e%d" % e.net_id] = [String(e.variant), _r(p.x), _r(p.y), _r(p.z), _r(v.x), _r(v.y), _r(v.z), snappedf(e.hp / e.max_hp, 0.001), f, int(e.net_target)]
	_net_events = _net_events.filter(func(v) -> bool: return _t - float(v.t) < NET_EVENT_KEEP)
	var ks := {}
	var im := {}
	for v in _net_events:
		(ks if String(v.kind) == "k" else im)["e%d" % int(v.id)] = v.data
	var acks := {}
	for code in _net_applied:
		var sub := {}
		for key in _net_applied[code]:
			if es.has(key):
				sub[key] = snappedf(float(_net_applied[code][key]), 0.01)
		if not sub.is_empty():
			acks[code] = sub
	return {"ph": int(director.phase), "pt": snappedf(director.phase_time, 0.01), "pl": snappedf(director.phase_len, 0.01),
		"day": GS.day, "city": snappedf(GS.city, 0.1), "e": es, "k": ks, "i": im, "bank": _net_bank, "a": acks}


## Host: buildings state for the guests (sent when it changes).
func net_map_state() -> Dictionary:
	var b := []
	for v in map.blackouts:
		b.append([_r(v.x), _r(v.y), _r(v.z)])
	return {"d": map.damaged_list(), "c": map.crushed_list(), "b": b}


## Host: a friend's running damage totals — the new part is dealt to the threats it hit.
func _on_guest_hits(code: String, totals: Dictionary) -> void:
	if Net.role != "host":
		return
	if not _net_applied.has(code):
		_net_applied[code] = {}
	var done: Dictionary = _net_applied[code]
	for key in totals:
		var total := float(totals[key])
		var delta := total - float(done.get(key, 0.0))
		if delta <= 0.0:
			continue
		done[key] = total
		var e = _enemy_by_key(String(key))
		if e != null and not e.dead:
			e.take_damage(delta, "net:" + code)


## Guest: one raid snapshot from the host.
func net_apply_raid(r: Dictionary) -> void:
	if Net.role != "guest":
		return
	director.net_follow(r)
	var city := float(r.get("city", GS.city))
	if absf(city - GS.city) > 0.01:
		GS.city = city
		GS.state_changed.emit()
		check_game_over()
	var t := int(float(r.get("t", Net.server_now())))
	var acks = r.get("a", {})
	var mine: Dictionary = acks.get(Net.code(), {}) if acks is Dictionary and acks.get(Net.code()) is Dictionary else {}
	var es: Dictionary = r.get("e", {}) if r.get("e") is Dictionary else {}
	var fresh := {}
	for key in es:
		var a = es[key]
		if _net_done.has(key) or not (a is Array) or (a as Array).size() < 10:
			continue
		var unconfirmed := maxf(0.0, float(_net_hits.get(key, 0.0)) - float(mine.get(key, 0.0)))
		var en = net_enemies.get(key)
		if en == null or not is_instance_valid(en):
			en = _spawn_puppet(String(key), a)
			fresh[String(a[0])] = int(fresh.get(String(a[0]), 0)) + 1
		en.net_update(a, t, unconfirmed)
	var ks = r.get("k", {})
	if ks is Dictionary:
		for key in ks:
			if not _net_done.has(key) and ks[key] is Array:
				_net_done[key] = true
				_net_kill(String(key), ks[key])
	var im = r.get("i", {})
	if im is Dictionary:
		for key in im:
			if not _net_done.has(key) and im[key] is Array:
				_net_done[key] = true
				_net_impact(String(key), im[key])
	# gone without a kill or an impact: a scout that flew away
	for key in net_enemies.keys():
		if not es.has(key):
			var en = net_enemies[key]
			net_enemies.erase(key)
			_net_hits.erase(key)
			if en != null and is_instance_valid(en):
				_remove_enemy(en)
	_net_apply_bank(r.get("bank", {}))
	for variant in fresh:
		_net_launch_alert(String(variant), int(fresh[variant]))


func _spawn_puppet(key: String, a: Array):
	var e := Enemy.new()
	e.puppet = true
	e.net_id = int(key.substr(1))
	var p := Vector3(float(a[1]), float(a[2]), float(a[3]))
	var tidx := int(a[9])
	var tname := ""
	if tidx >= 0 and tidx < map.targets.size():
		tname = String(map.targets[tidx].name)
	elif tidx == -2:
		tname = GS.t("База ПВО")
	e.setup(self, String(a[0]), p, p, tname)
	enemy_root.add_child(e)
	enemies.append(e)
	net_enemies[key] = e
	return e


## The same alarm the host heard when the salvo was launched.
func _net_launch_alert(variant: String, count: int) -> void:
	if not GS.ENEMIES.has(variant):
		return
	if variant == "scout":
		hud.log_event(GS.t("Замечен разведчик «Орлан» — ищет вашу базу"), Color(0.4, 0.9, 1.0))
		return
	var label: String = GS.t(String(GS.ENEMIES[variant].plural))
	if count > 1:
		label += " ×%d" % count
	hud.alert(GS.t("⚠ ТРЕВОГА: ПУСК %s!") % label, Color(1.0, 0.25, 0.25))
	SFX.play("alert", -4.0)


## Guest: our own hit on a puppet. The running total goes to the host with our presence.
func net_hit(e, amount: float) -> void:
	var key := "e%d" % e.net_id
	_net_hits[key] = snappedf(float(_net_hits.get(key, 0.0)) + amount, 0.01)
	Net.set_extra("h", _net_hits)


## Guest: our hit most probably brought it down — show it at once, the host confirms in a moment.
func net_predicted_kill(e) -> void:
	e.set_meta("boomed", true)
	var big: float = 1.8 if e.type == "ballistic" else (1.25 if e.type == "cruise" else 0.95)
	Fx.explosion(fx_root, e.position, big * 0.8, Color(1.0, 0.55, 0.15), true)
	play_boom("explosion", e.position, -2.0)
	e.visible = false
	if view == "base":
		hud.reticle.kill(GS.t("ЦЕЛЬ ПОРАЖЕНА"), Color(0.3, 1.0, 0.5))


## Guest: the host's word that a threat went down.
func _net_kill(key: String, k: Array) -> void:
	var e = net_enemies.get(key)
	net_enemies.erase(key)
	_net_hits.erase(key)
	if e == null or not is_instance_valid(e):
		return
	e.position = Vector3(float(k[1]), float(k[2]), float(k[3]))
	e.vel = Vector3(float(k[4]), float(k[5]), float(k[6]))
	e.visible = true
	_event_seq += 1
	var killer := String(k[0])
	if killer == Net.code():
		record_clip(e)
		if view == "base" and not e.has_meta("boomed"):
			hud.reticle.kill(GS.t("ЦЕЛЬ ПОРАЖЕНА  +%s") % GS.fmt_money(int(k[9])), Color(0.3, 1.0, 0.5))
	_kill_fx(e, int(k[7]) == 1, int(k[8]) == 1, int(k[9]), killer, true)
	e.dead = true
	_remove_enemy(e)


## Guest: the host's word that a threat reached the ground. The buildings follow with the map.
func _net_impact(key: String, im: Array) -> void:
	var e = net_enemies.get(key)
	net_enemies.erase(key)
	_net_hits.erase(key)
	var p := Vector3(float(im[0]), float(im[1]), float(im[2]))
	var flags := int(im[3])
	var owner := String(im[4])
	var def: Dictionary = GS.ENEMIES.get(String(im[6]), GS.ENEMIES["shahed"])
	if flags & 1:
		Fx.ground_hit(fx_root, p)
		play_3d("boom_small", p, -10.0)
		hud.log_event(GS.t("%s упала — без боевой части") % GS.t(String(def.name)), Color(0.8, 0.85, 0.7))
	else:
		Fx.explosion(fx_root, p, 2.2, Color(1.0, 0.45, 0.1), true)
		play_boom("explosion", p, 6.0)
		shake(clampf(1.0 - cam.global_position.distance_to(p) / 1200.0, 0.2, 1.0))
		var gy: float = map.ground_height(p.x, p.z)
		fire_service.start_fire(Vector3(p.x, gy, p.z), map.building_at(p.x, p.z), 2.0)
		if flags & 2:
			if owner == Net.code():
				var dmg := float(im[5])
				GS.base_hp = maxf(0.0, GS.base_hp - dmg)
				hud.alert(GS.t("УДАР ПО БАЗЕ! Повреждения −%d%%") % int(dmg), Color(1, 0.2, 0.2))
				hud.log_event(GS.t("Удар по базе: %s") % GS.t(String(def.name)), Color(1, 0.2, 0.2))
				if view == "base":
					hud.flash(0.6)
			else:
				hud.log_event(GS.t("Удар по базе %s: %s") % [_nick_of(owner), GS.t(String(def.name))], Color(1, 0.35, 0.3))
		else:
			hud.log_event(GS.t("Прилёт: %s") % GS.t(String(def.name)), Color(1, 0.3, 0.2))
	GS.state_changed.emit()
	if e != null and is_instance_valid(e):
		_remove_enemy(e)
	check_game_over()


## Guest: what the host has credited to us so far — the new part goes into our budget and stats.
func _net_apply_bank(b) -> void:
	var mine = b.get(Net.code()) if b is Dictionary else null
	var totals: Dictionary = mine if mine is Dictionary else {}
	if not _bank_init:
		# joining mid-session: whatever the host counted for an earlier visit is not ours to take
		_bank_init = true
		for f in totals:
			_bank_seen[f] = int(float(totals[f]))
		return
	var changed := false
	for f in ["e", "p", "k", "r", "i", "h"]:
		var total := int(float(totals.get(f, 0)))
		var d := total - int(_bank_seen.get(f, 0))
		if d <= 0:
			continue
		_bank_seen[f] = total
		changed = true
		match f:
			"e":
				GS.add_money(d)
			"p":
				GS.add_money(-d)
			"k":
				GS.stats.kills = int(GS.stats.kills) + d
			"r":
				GS.stats.roofs = int(GS.stats.roofs) + d
			"i":
				GS.stats.impacts = int(GS.stats.impacts) + d
			"h":
				GS.stats.homes = int(GS.stats.get("homes", 0)) + d
	if changed:
		GS.state_changed.emit()


## Guest: the buildings as the host has them — collapses since the last state come down here too.
func net_apply_map(m: Dictionary) -> void:
	if Net.role != "guest":
		return
	var d: Array = m.get("d", []) if m.get("d") is Array else []
	var c: Array = m.get("c", []) if m.get("c") is Array else []
	for fell in map.sync_damage(d, c):
		collapse_fx(int(fell[0]), float(fell[1]))
	var bo := []
	var b = m.get("b", [])
	if b is Array:
		for v in b:
			if v is Array and (v as Array).size() >= 3:
				bo.append(Vector4(float(v[0]), float(v[1]), float(v[2]), 1.0))
	map.set_blackouts(bo)


## Our own missile launch, told to the others so they see it fly (it does no damage there).
func _net_note_launch(pos: Vector3, tgt, wid: String) -> void:
	if not Net.is_online() or tgt == null or not is_instance_valid(tgt) or tgt.net_id < 0:
		return
	_launch_seq += 1
	_net_launches.append({"t": _t, "d": [_launch_seq, wid, _r(pos.x), _r(pos.y), _r(pos.z), "e%d" % tgt.net_id]})
	_net_launches = _net_launches.filter(func(v) -> bool: return _t - float(v.t) < 3.0)
	Net.set_extra("m", _net_launches.map(func(v) -> Array: return v.d))


## A friend's missiles: drawn flying at the same threat (the damage is theirs to report).
func _on_launches(code: String, list: Array) -> void:
	var top := 0
	for it in list:
		if it is Array and (it as Array).size() >= 6:
			top = maxi(top, int(it[0]))
	if not _launch_seen.has(code):
		_launch_seen[code] = top # joined late: old launches are history
		return
	for it in list:
		if not (it is Array) or (it as Array).size() < 6 or int(it[0]) <= int(_launch_seen[code]):
			continue
		var tgt = _enemy_by_key(String(it[5]))
		if tgt == null or tgt.dead or not GS.WEAPONS.has(String(it[1])):
			continue
		var m := Missile.new()
		m.game = self
		m.cosmetic = true
		m.target = tgt
		m.weapon_id = String(it[1])
		m.vel = Vector3.UP * 40.0
		m.position = Vector3(float(it[2]), float(it[3]), float(it[4]))
		fx_root.add_child(m)
	_launch_seen[code] = maxi(top, int(_launch_seen[code]))


## The mouse is wanted by a panel (player list) or an open window in a game that does not pause.
func wants_cursor() -> bool:
	return ui_cursor or overlay_open
