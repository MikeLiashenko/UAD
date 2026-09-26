extends Node
## Root: owns the shared city map + camera and switches between screens
## (main menu → worlds → create world → base position → game). The map is rebuilt when a world of
## another city is created or played (Kyiv, Kharkiv, Dnipro, Odesa — scripts/world/cities/).
##
## Command-line test hooks (after `--`):
##   --autotest                 start a throw-away game with auto-fire (not saved)
##   --city=kyiv|kharkiv|dnipro|odesa   which city to load (autotest, map screen, menu)
##   --plan=path.png            write a top-down plan of the generated city (works headless)
##   --switchtest               play a saved world of another city: the map is rebuilt under it
##   --loc=river|forest|city|field  --weapons=mg,gepard,drone,iris,patriot  --day=N  --money=N
##   --view=base|fpv [--aimbot] [--weapon=id]   gunner / FPV drone view; aimbot tracks threats
##   --fpv-at=SECONDS           jump to the FPV drone console mid-raid
##   --crush=X,Z                collapse and set fire to the building at X,Z (fire-service test)
##   --camat=X,Z[,DIST]         park the overhead camera on a spot
##   --screen=menu|settings|map|worlds|create|game   --open=shop|pause|morning|gameover|feed|video|record
##   --keytest                  verify the rebindable control map
##   --mptest                   multiplayer self-test, offline: codes, the Firebase event mirror and
##                              (with --autotest) friends in the city, watching, player list, requests
##   --mpid=CODE                play as another friend code (a second copy on the same computer)
##   --acctest                  accounts self-test, offline (in-memory database, stand-in sign-in):
##                              register, nick rules, friends by nick, sign in / out, rename,
##                              saved session, deletion, a session revoked elsewhere
##   --mphost / --mpjoin=CODE   a live two-copy session through the database (see _mp_live_setup)
##   --offscreen --shotlist=f.json [--shot-ui]   pictures without a window (tools_scripts/shots.sh)
##   --fakerelease=N            pretend build N was published (the update offer in the menu)
##   --avitest[=path]           write a synthetic clip and read the container back
##   --exporttest               run the video recorder on generated frames and verify the file
##   --press=K,K,K              send those keys one per second (input round trip)
##   --bind=action:KEY          rebind a control before the session (with --press)
##   --shot=path.png --shot-at=SECONDS   --quit-at=SECONDS   --speed=N   --follow

const CityMap = preload("res://scripts/world/city_map.gd")
const Cities = preload("res://scripts/world/cities.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const WorldsMenu = preload("res://scripts/ui/worlds_menu.gd")
const AccountUi = preload("res://scripts/ui/account_ui.gd")
const CreateWorld = preload("res://scripts/ui/create_world.gd")
const MapSelect = preload("res://scripts/ui/map_select.gd")
const Game = preload("res://scripts/game/game_controller.gd")
const Bullet = preload("res://scripts/game/bullet.gd")
const Avi = preload("res://scripts/core/avi.gd")
const VideoExport = preload("res://scripts/game/video_export.gd")

var map
var cam: Camera3D
var ui: CanvasLayer
var screen: Node
var game: Node
var pending_world := {"name": GS.t("Оборона Киева"), "difficulty": 1, "city": "kyiv"}
var _mode := "menu"
var _orbit := 0.6

var _args := {}
var _clock := 0.0
var _shot_done := false
## Building collapsed by the --crush test hook, reported again in the summary.
var _crush_bi := -1
## --press test hook: index of the key already sent from the list.
var _press_i := -1
## Key sent last frame, reported once the input system has actually delivered it.
var _press_pending := ""
## Clock reading when --open=video started the cut, so its real length can be reported.
var _video_t0 := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	UiKit.install_theme()
	_parse_args()
	if not _args.has("offscreen"):
		get_window().min_size = Vector2i(960, 540)
	# the menu shows the city of the most recently played world
	var start_city := Cities.DEFAULT
	var recent := GS.list_worlds()
	if not recent.is_empty():
		start_city = String(recent[0].get("city_id", Cities.DEFAULT))
	start_city = String(_args.get("city", start_city))
	GS.city_id = start_city if Cities.has(start_city) else Cities.DEFAULT
	_build_map(GS.city_id)
	pending_world = {"name": GS.ctext("defense"), "difficulty": 1, "city": GS.city_id}
	cam = Camera3D.new()
	cam.far = 9000.0
	cam.near = 0.5
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	if _args.has("offscreen"):
		_setup_offscreen()
	Net.main = self
	Net.session_ended.connect(_on_session_ended)
	if _args.has("plan"):
		# --plan=file.png [--plan-at=x,z,size] (a close-up of one part of the city)
		var pa := String(_args.get("plan-at", "0,0,2000")).split(",")
		map.dump_plan(String(_args.plan), float(pa[0]), float(pa[1]), float(pa[2]))
	if _args.has("mptest"):
		_mp_unit_selftest()
	if _args.has("acctest"):
		_acct_selftest()
	if _args.has("mphost") or _args.has("mpjoin"):
		_mp_live_setup()
	if not _args.has("quit-at"):
		# a normal launch (not a test run): is there a newer build?
		Net.check_release()
	if _args.has("fakerelease"):
		# test hook: pretend the database announced a newer build (the update offer in the menu)
		Net.release = {"build": int(_args.fakerelease), "version": "1.0.0", "date": "2026-09-24",
			"notes": GS.t("Общие налёты в сети, новые города, отражения в воде."), "exe": "https://example.invalid/UAD.exe",
			"apk": "https://example.invalid/UAD.apk", "site": "https://mikeliashenko.github.io/UAD/"}
		# a link outside the game's releases must fall back to the site
		print("fakerelease: update available=%s url=%s" % [Net.update_available(), Net.update_url()])
	if _args.has("keytest"):
		_key_selftest()
	if _args.has("savetest"):
		_save_selftest()
	if _args.has("switchtest"):
		_switch_selftest.call_deferred()
	if _args.has("avitest"):
		_avi_selftest()
	if _args.has("exporttest"):
		_export_selftest()
	if _args.has("probe"):
		var pp := String(_args.probe).split(",")
		var x0 := float(pp[0])
		var z0 := float(pp[1])
		for dx in [-1.0, 0.0, 0.5, 1.0, 2.0, 4.0]:
			var bi: int = map.building_at(x0 + dx, z0)
			print("UAD PROBE x=%.1f: bi=%d name=%s top=%.1f water=%.1f" % [x0 + dx, bi, map.building_name(bi) if bi >= 0 else "-", map.fp_center[bi].y if bi >= 0 else 0.0, map.water_dist(x0 + dx, z0)])
	var scr := String(_args.get("screen", "game" if _args.has("autotest") else "menu"))
	match scr:
		"map":
			show_map_select()
		"worlds":
			show_worlds()
		"settings":
			show_settings()
		"create":
			show_create_world()
		"game":
			_start_autotest()
		_:
			show_menu()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("speed"):
		Engine.time_scale = float(_args.speed)
	if _args.has("nomarkers"):
		GS.settings.markers = false
	if _args.has("lang"):
		GS.set_language(String(_args.lang))
	if _args.has("bind"):
		# test hook: --bind=action:KEY[,action:KEY] rebinds before the session starts
		for pair in String(_args["bind"]).split(","):
			var kv := pair.split(":")
			if kv.size() == 2:
				GS.set_key(kv[0].strip_edges(), OS.find_keycode_from_string(kv[1].strip_edges()))
	GS.track_missing = _args.has("i18ncheck")


## Replaces the map with another city's (synchronous — callers show the loading screen first).
func _build_map(id: String) -> void:
	if map and is_instance_valid(map):
		remove_child(map)
		map.free()
	map = CityMap.new()
	map.city_id = id
	add_child(map)


var _loading: Control


## Makes sure the map shows city `id`, then calls `then`. Building a city takes a moment, so a
## loading screen is drawn first (two frames, so it is really on screen before the hitch).
func switch_city(id: String, then: Callable) -> void:
	if not Cities.has(id):
		id = Cities.DEFAULT
	if map and is_instance_valid(map) and map.city_id == id:
		then.call()
		return
	_end_game()
	_clear_screen()
	_loading = UiKit.full_rect(ColorRect.new())
	(_loading as ColorRect).color = Color(0.01, 0.03, 0.04, 1.0)
	var lbl := UiKit.glow_label(GS.t("Загрузка карты: %s…") % GS.t(String(Cities.get_def(id).name)), 30, UiKit.NEON)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_child(lbl)
	ui.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	_build_map(id)
	_loading.queue_free()
	_loading = null
	then.call()


func _clear_screen() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = null


func _end_game() -> void:
	if game and is_instance_valid(game):
		game.queue_free()
	game = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	map.restore_area()
	map.reset_damage()
	map.clear_blackouts()
	SFX.stop_siren()


func _show(node: Control, mode: String) -> void:
	SFX.play_music("menu")
	_clear_screen()
	_mode = mode
	screen = node
	ui.add_child(node)


func show_menu() -> void:
	Net.close()
	_end_game()
	map.set_labels_visible(false)
	map.set_night(1.0)
	var m := MainMenu.new()
	m.main = self
	_show(m, "menu")


func show_settings() -> void:
	var s := SettingsMenu.new()
	s.closed.connect(show_menu)
	_show(s, "settings")


func show_worlds() -> void:
	Net.close()
	_end_game()
	map.set_labels_visible(false)
	map.set_night(1.0)
	var w := WorldsMenu.new()
	w.main = self
	_show(w, "menu")


func show_create_world() -> void:
	_end_game()
	map.set_labels_visible(false)
	map.set_night(1.0)
	var c := CreateWorld.new()
	c.main = self
	_show(c, "menu")


func show_map_select(params := {}) -> void:
	if not params.is_empty():
		pending_world = params
	var cid := String(pending_world.get("city", Cities.DEFAULT))
	if map.city_id != cid:
		switch_city(cid, show_map_select)
		return
	GS.city_id = cid
	_end_game()
	map.set_labels_visible(true)
	var m := MapSelect.new()
	m.main = self
	_show(m, "map")


## New world from the map screen: create, save immediately, start day 1.
func create_world(pos: Vector3, loc: int) -> void:
	GS.new_world(String(pending_world.get("name", GS.ctext("defense"))), int(pending_world.get("difficulty", 1)), pos, loc, map.city_id)
	if bool(pending_world.get("guest", false)):
		if Net.role != "guest":
			show_worlds() # the host closed the world while we were choosing
			return
		# a guest's defence lives only as long as the visit: nothing is written to disk
		GS.world_id = ""
		GS.day = maxi(1, int(Net.world.get("day", 1)))
		_start_session()
		return
	GS.save_world()
	_start_session()


## A friend accepted our join request: load their city and pick where our base stands.
func join_world(info: Dictionary) -> void:
	if Net.role != "guest":
		return
	var cid := String(info.get("city", Cities.DEFAULT))
	pending_world = {"name": String(info.get("world", GS.t("Мир"))), "difficulty": clampi(int(info.get("difficulty", 1)), 0, 2),
		"city": cid if Cities.has(cid) else Cities.DEFAULT, "guest": true, "host": String(info.get("n", "?"))}
	show_map_select()


## "Disconnect" from the pause menu of a guest.
func leave_session() -> void:
	Net.close()
	show_menu()


## The host closed the world or the connection broke while we were a guest.
func _on_session_ended(reason: String) -> void:
	_end_game()
	_clear_screen()
	_mode = "menu"
	var root := UiKit.full_rect(Control.new())
	var m := UiKit.modal(root, Vector2(480, 0))
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ОТКЛЮЧЕНО"), 36, UiKit.RED))
	var l := UiKit.label(reason, 18, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	v.add_child(l)
	v.add_child(UiKit.button(GS.t("В главное меню"), show_menu))
	_show(root, "menu")


func play_world(id: String) -> void:
	var cid := String(GS.read_world(id).get("city_id", Cities.DEFAULT))
	if map.city_id != cid and Cities.has(cid):
		switch_city(cid, play_world.bind(id))
		return
	if GS.load_world(id):
		_start_session()
	else:
		show_worlds()


func _start_session() -> void:
	_end_game()
	_clear_screen()
	_mode = "game"
	map.set_labels_visible(false)
	# a base saved on an older layout may now stand in the water or on a highway
	var spot: Vector3 = map.nearest_base_spot(GS.base_pos, GS.base_loc)
	if not spot.is_equal_approx(GS.base_pos):
		GS.base_pos = spot
		var l: int = map.location_at(spot.x, spot.z)
		if l >= 0:
			GS.base_loc = l
	map.clear_area(GS.base_pos, 34.0)
	game = Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.main = self
	game.map = map
	game.cam = cam
	game.autotest = _args.has("autotest")
	add_child(game)
	if GS.world_id != "":
		GS.save_world()


## Saves (only during the day — nights restart from their morning) and returns to the menu.
func exit_to_menu() -> void:
	_save_if_safe()
	show_menu()


func _save_if_safe() -> void:
	if game and is_instance_valid(game) and not game.game_over and GS.world_id != "":
		if not game.director.is_night():
			game.save_progress()


func quit_game() -> void:
	_save_if_safe()
	Net.close()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save_if_safe()


func _process(delta: float) -> void:
	_fit_near()
	if _args.has("follow") and game and is_instance_valid(game) and not game.enemies.is_empty():
		var near = _nearest_enemy()
		game.rig.focus(near.position)
		game.rig._t_dist = 300.0
		game.rig._t_pitch = 0.1
		game.locked = near
	if _args.has("aimbot") and game and is_instance_valid(game) and game.view == "base" and not game.enemies.is_empty():
		_aimbot()
	if _args.has("aimbot") and game and is_instance_valid(game) and game.view == "fpv":
		_fpv_pilot(delta)
	elif _args.has("aimbot") and String(_args.get("view", "")) == "fpv" and game and is_instance_valid(game) and not game.drones.is_empty() and not game.enemies.is_empty():
		game.enter_fpv() # the test pilot takes the next drone as soon as one is up
	if _args.has("fpv-at") and game and is_instance_valid(game) and _clock >= float(_args["fpv-at"]):
		# test hook: sit down at the FPV console mid-raid (a drone is launched if none is up)
		_args.erase("fpv-at")
		game.enter_fpv()
	if _args.has("camat") and game and is_instance_valid(game) and _clock >= 1.0:
		# test hook: park the overhead camera on a spot (x,z[,distance])
		var ap := String(_args["camat"]).split(",")
		_args.erase("camat")
		game.rig.focus(Vector3(float(ap[0]), 0, float(ap[1])))
		game.rig._t_dist = float(ap[2]) if ap.size() > 2 else 150.0
		game.rig._t_pitch = 0.5
	if _args.has("crush") and game and is_instance_valid(game) and _clock >= 1.5:
		# test hook: collapse the building at x,z and set it on fire (fire service / rubble check)
		var cp := String(_args["crush"]).split(",")
		_args.erase("crush")
		var cx := float(cp[0])
		var cz := float(cp[1])
		var bi: int = map.building_at(cx, cz)
		if bi < 0:
			var best := INF
			for i in map.fp_center.size():
				if map.fp_box[i].x <= 0.0 or map.fp_hidden[i] == 1:
					continue
				var d: float = Vector2(map.fp_center[i].x - cx, map.fp_center[i].z - cz).length()
				if d < best:
					best = d
					bi = i
			if bi >= 0:
				cx = map.fp_center[bi].x
				cz = map.fp_center[bi].z
		_crush_bi = bi
		game.strike_damage(Vector3(cx, map.ground_height(cx, cz) + 2.0, cz), "cruise", 1.4, 2.0)
		print("UAD CRUSH at %.1f,%.1f building=%d name=%s h=%.1f of %.1f crush=%.2f" % [cx, cz, bi, map.building_name(bi) if bi >= 0 else "-", map.fp_center[bi].y if bi >= 0 else 0.0, map.fp_box[bi].x if bi >= 0 else 0.0, map.crush_of(bi)])
	if _press_pending != "" and game and is_instance_valid(game):
		print("UAD PRESS %s -> weapon=%s group=%s view=%s auto=%d" % [_press_pending, game.selected_weapon, game.weapon_group, game.view, game.auto_fire])
		_press_pending = ""
	if _args.has("press") and game and is_instance_valid(game) and _clock >= 3.0:
		# test hook: feed real key presses through the input system, one per second
		var seq := String(_args["press"]).split(",")
		var i := int(_clock - 3.0)
		if i < seq.size() and i != _press_i:
			_press_i = i
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(seq[i].strip_edges())
			ev.physical_keycode = ev.keycode
			ev.pressed = true
			Input.parse_input_event(ev)
			# parse_input_event is queued, so the effect shows up on the next frame
			_press_pending = String(seq[i])
	if _args.has("mptest") and game and is_instance_valid(game):
		_mp_session_selftest()
	if _args.has("mphost") or _args.has("mpjoin"):
		_mp_live_step()
	if _video_t0 >= 0.0 and game and is_instance_valid(game) and not game.reel.playing:
		print("UAD VIDEO ran %.1f s for %d clips" % [_clock - _video_t0, game.reel.clips.size()])
		_video_t0 = -1.0
	if _args.has("open") and game and is_instance_valid(game) and _clock >= 2.0:
		# video and feed wait for the first published cut; everything else opens right away
		var what := String(_args["open"])
		if not ((what == "video" or what == "feed" or what == "record") and GS.videos.is_empty()):
			_args.erase("open")
			_args["opened"] = what
			_open_screen(what)
	if (_mode == "menu" or _mode == "settings") and _shots.is_empty():
		_orbit += delta * 0.05
		cam.global_position = Vector3(cos(_orbit) * 950.0, 300.0, sin(_orbit) * 950.0)
		cam.look_at(Vector3(0, 90, 0), Vector3.UP)
	_clock += delta / maxf(Engine.time_scale, 0.001)
	_shot_list_step()
	if _shot_cam != null:
		_shot_cam.global_transform = cam.global_transform
		_shot_cam.fov = cam.fov
		_shot_cam.near = cam.near
		_shot_cam.far = cam.far
	if _args.has("shot") and not _shot_done and _clock >= float(_args.get("shot-at", "3")):
		_shot_done = true
		_frame_image().save_png(String(_args.shot))
		print("UAD: screenshot saved to ", _args.shot)
	if _args.has("quit-at") and _clock >= float(_args["quit-at"]) and not _quitting:
		_quitting = true
		_print_summary()
		if Net.role != "" or _args.has("mphost") or _args.has("mpjoin"):
			_mp_live_report()
			# leave the session tidily: the deletes need a moment on the wire
			Net.close()
			if _args.has("mphost") or _args.has("mpjoin"):
				Net.quiet = true
				Net.db.delete("users/" + Net.code())
			get_tree().create_timer(1.8, true, false, true).timeout.connect(get_tree().quit)
		else:
			get_tree().quit()


## Test hook: opens one of the modal screens on a running session.
func _open_screen(what: String) -> void:
	match what:
		"shop":
			game.hud.open_shop()
		"pause":
			game.hud.toggle_pause()
		"morning":
			game.hud.show_morning({"day": 1, "kills": 12, "roofs": 2, "impacts": 1, "homes": 1, "earned": 14000, "penalties": 11000, "funding": 11000, "bonus": 0})
		"gameover":
			game.hud.show_game_over(GS.t("Город получил критические разрушения"))
		"feed":
			game.hud.open_feed()
		"video", "record":
			# a compilation is a fixed-length cut: it is watched at real speed even when the
			# session was fast-forwarded to reach the morning
			Engine.time_scale = 1.0
			if what == "record":
				game.hud.open_video(GS.latest_video(), Callable(), true)
			else:
				game.play_video()
			_video_t0 = _clock
			print("UAD VIDEO opened at t=%.1f day=%d clips=%d" % [_clock, GS.day, (GS.latest_video().get("clips", []) as Array).size()])


func _nearest_enemy():
	var near = game.enemies[0]
	for e in game.enemies:
		if e.position.distance_to(GS.base_pos) < near.position.distance_to(GS.base_pos):
			near = e
	return near


## Test helper: points the gunner sight at the nearest threat (with lead) and fires.
## --aimbot in the FPV view: a test pilot turns the aim ring towards the nearest threat no faster
## than a hand on a mouse would (1.5 rad/s); the console's own lead assist does the rest.
func _fpv_pilot(delta: float) -> void:
	var fv = game.fpv_view
	if fv.drone == null or not is_instance_valid(fv.drone):
		return
	var best = null
	var bd := INF
	for e in game.enemies:
		if not e.dead and GS.eff("drone", e) > 0.0 and fv.drone.position.distance_to(e.position) < bd:
			bd = fv.drone.position.distance_to(e.position)
			best = e
	if best == null:
		return
	var to: Vector3 = (best.position - fv.drone.position).normalized()
	var off: float = fv.aim.angle_to(to)
	if off > 0.0001:
		fv.aim = fv.aim.slerp(to, clampf(1.5 * delta / off, 0.0, 1.0)).normalized()


func _aimbot() -> void:
	var bv = game.base_view
	var w = bv.weapon()
	var e = _nearest_enemy()
	var aim: Vector3 = e.position
	if String(w.def.kind) == "gun":
		aim = Bullet.lead(w.muzzle.global_position, e.position, e.vel, float(w.def.speed))
	var d: Vector3 = (aim - cam.global_position).normalized()
	bv.yaw = atan2(-d.x, -d.z)
	bv.pitch = asin(clampf(d.y, -1.0, 1.0))
	var in_r: bool = w.in_range(e)
	if String(w.def.kind) == "gun":
		bv.trigger = in_r
	elif bv.lock_ready:
		bv.launch()


# --- Automated test harness ------------------------------------------------------------
func _start_autotest() -> void:
	var want := {"river": GS.Loc.RIVER, "forest": GS.Loc.FOREST, "city": GS.Loc.CITY, "field": GS.Loc.FIELD}
	var loc_want: int = want.get(String(_args.get("loc", "river")), GS.Loc.RIVER)
	var pos := Vector3.ZERO
	var found := false
	var r := 0.0
	while r < 950.0 and not found:
		var a := 0.0
		while a < TAU:
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			if map.location_at(p.x, p.z) == loc_want:
				pos = p
				found = true
				break
			a += 0.2
		r += 40.0
	GS.new_world("autotest", 1, pos, loc_want, map.city_id)
	GS.world_id = "" # never written to disk
	_start_session()
	var ids := String(_args.get("weapons", "mg,gepard,drone,iris,patriot")).split(",")
	GS.money = 400000
	for id in ids:
		game.purchase_weapon(id)
	GS.money = int(_args.get("money", "25000"))
	for aid in GS.AMMO_ORDER:
		GS.ammo[aid] = 40
	game.auto_fire = 1
	GS.day = int(_args.get("day", "3"))
	GS.money_changed.emit(GS.money)
	if _args.has("weapon"):
		game.select_weapon(String(_args.weapon))
	if String(_args.get("view", "top")) == "base":
		game.set_view("base")
		game.base_view.nv = _args.has("nv")
	elif String(_args.get("view", "top")) == "fpv":
		game.enter_fpv()
	elif String(_args.get("view", "top")) == "walk":
		game.set_view("walk")
		if _args.has("walkat"):
			var p := String(_args.walkat).split(",")
			game.walker.pos = game.walker.find_free(Vector3(float(p[0]), 0, float(p[1])))
		if _args.has("walkyaw"):
			game.walker.yaw = deg_to_rad(float(_args.walkyaw))
		game.walker.pitch = float(_args.get("walkpitch", "0.08"))
		game.walker.test_forward = _args.has("walkfwd")
	print("UAD: autotest base at ", pos, " loc=", loc_want)


## Controls round trip: defaults resolve, a rebind sticks and takes the key from its old owner.
func _key_selftest() -> void:
	GS.reset_keys()
	var ok := true
	for a in GS.KEY_ACTIONS:
		var id := String(a[0])
		if GS.key_of(id) != int(a[2]) or GS.action_of(int(a[2])) != id:
			ok = false
			print("UAD KEYTEST: default broken for ", id)
	# rebind "shop" onto the key that "feed" holds: feed must lose it, shop must answer to it
	var feed_key: int = GS.key_of("feed")
	GS.set_key("shop", feed_key)
	var moved: bool = GS.action_of(feed_key) == "shop" and GS.key_of("feed") == 0
	# and it survives a save / load of the settings file
	GS.save_settings()
	GS.settings["keys"] = {}
	GS.load_settings()
	var kept: bool = GS.key_of("shop") == feed_key
	GS.reset_keys()
	var reset_ok: bool = GS.key_of("shop") != feed_key and GS.action_of(feed_key) == "feed"
	print("UAD KEYTEST: defaults=%s rebind=%s persisted=%s reset=%s" % [ok, moved, kept, reset_ok])


## A world of another city: saved from the menu, played, the map must follow it.
func _switch_selftest() -> void:
	var other := "odesa" if map.city_id != "odesa" else "kharkiv"
	var before: String = map.city_id
	GS.new_world("switchtest", 1, Vector3(0, 0, 0), GS.Loc.CITY, other)
	GS.save_world()
	var id := GS.world_id
	play_world(id)
	while map.city_id != other or game == null:
		await get_tree().process_frame
	var spot_ok: bool = map.location_at(GS.base_pos.x, GS.base_pos.z) >= 0 or map.building_at(GS.base_pos.x, GS.base_pos.z) < 0
	print("UAD SWITCHTEST: from=%s to=%s city_id=%s channel=%s base=%s ok=%s" % [before, map.city_id, GS.city_id, GS.video_channel(), str(GS.base_pos), spot_ok])
	GS.delete_world(id)
	GS.world_id = ""


## Round trip: create → save → list → load → verify → delete.
func _save_selftest() -> void:
	GS.new_world(GS.t("Тестовый мир"), 2, Vector3(123, 0, -45), GS.Loc.RIVER, "odesa")
	GS.money = 77777
	GS.day = 5
	GS.unlocked["gepard"] = true
	GS.damaged = [3, 17, 42]
	GS.save_world()
	var id := GS.world_id
	var found := GS.list_worlds().any(func(w) -> bool: return String(w.id) == id)
	GS.money = 0
	GS.day = 1
	var ok := GS.load_world(id)
	var good := ok and found and GS.city_id == "odesa" and GS.money == 77777 and GS.day == 5 and GS.difficulty == 2 and GS.unlocked.has("gepard") and GS.damaged == [3, 17, 42] and GS.base_pos.is_equal_approx(Vector3(123, 0, -45))
	GS.delete_world(id)
	var gone := not GS.list_worlds().any(func(w) -> bool: return String(w.id) == id)
	print("UAD SAVETEST: listed=%s loaded=%s fields_ok=%s deleted=%s" % [found, ok, good, gone])


## Writes a short Motion-JPEG clip from generated frames and a tone, then reads the container
## back: the video export can be checked this way without a window, since a headless run renders
## nothing to capture. Only the file format is under test here, not the screen grab.
func _avi_selftest() -> void:
	var to := String(_args.get("avitest", "1"))
	var scratch: bool = to == "1"
	if scratch:
		to = "user://avitest.avi"
	var w := 128
	var h := 224
	var fps := 30
	var rate := 44100
	var frames := 45
	var avi = Avi.new()
	if not avi.open(to, w, h, fps, rate, 2):
		print("UAD AVITEST: cannot write ", to)
		return
	var chunk: int = rate / fps
	for i in frames:
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(float(i) / float(frames), 0.35, 0.8))
		avi.add_video(img.save_jpg_to_buffer(0.8))
		var buf := PackedVector2Array()
		buf.resize(chunk)
		for k in chunk:
			var v: float = sin(TAU * 440.0 * float(i * chunk + k) / float(rate)) * 0.2
			buf[k] = Vector2(v, v)
		avi.add_audio(Avi.to_pcm16(buf))
	avi.close()
	_avi_verify(to, frames)
	if scratch:
		DirAccess.remove_absolute(to)


## Drives the real recorder over generated frames: it picks the file, opens it, writes a second
## of video and closes — everything the export does except looking at the screen.
func _export_selftest() -> void:
	var ex = VideoExport.new()
	add_child(ex)
	ex.synthetic = true
	var started: bool = ex.start(99)
	var frames := 0
	if started:
		for i in VideoExport.FPS:
			ex.test_advance(1.0 / float(VideoExport.FPS))
		frames = ex._avi.frames
		ex.finish(true)
	var kept: bool = FileAccess.file_exists(ex.path)
	print("UAD EXPORTTEST: started=%s frames=%d kept=%s path=%s" % [started, frames, kept, ex.path])
	if kept:
		_avi_verify(ex.path, frames)
		if String(_args.get("exporttest", "1")) != "keep":
			DirAccess.remove_absolute(ex.path)
	ex.queue_free()


## Walks the RIFF tree the way a player would: header, the two stream lists, the frames and the
## index at the end, and checks that every size written back at close actually lines up.
func _avi_verify(to: String, frames: int) -> void:
	var f := FileAccess.open(to, FileAccess.READ)
	if f == null:
		print("UAD AVITEST: cannot read back ", to)
		return
	var bytes := f.get_length()
	var riff := f.get_buffer(4).get_string_from_ascii()
	var riff_size := f.get_32()
	var form := f.get_buffer(4).get_string_from_ascii()
	f.seek(16)
	var hdrl_size := f.get_32()
	f.seek(48)
	var total := f.get_32() # avih dwTotalFrames
	var movi_at: int = 20 + hdrl_size
	f.seek(movi_at)
	var movi_tag := f.get_buffer(4).get_string_from_ascii()
	var movi_size := f.get_32()
	var movi_name := f.get_buffer(4).get_string_from_ascii()
	var idx_at: int = movi_at + 8 + movi_size
	f.seek(idx_at)
	var idx_tag := f.get_buffer(4).get_string_from_ascii()
	var idx_size := f.get_32()
	f.close()
	var ok: bool = riff == "RIFF" and form == "AVI " and riff_size == bytes - 8
	var lists: bool = movi_tag == "LIST" and movi_name == "movi" and idx_tag == "idx1"
	# the index must end exactly at the end of the file and cover every chunk written
	var index_ok: bool = lists and idx_at + 8 + idx_size == bytes and idx_size % 16 == 0 and idx_size / 16 >= frames
	print("UAD AVITEST: riff_ok=%s lists_ok=%s frames=%d/%d index=%d index_ok=%s bytes=%d" % [
		ok, lists, total, frames, idx_size / 16 if lists else -1, index_ok, bytes])


## --mptest, first part: pure logic with no network — friend codes, the Firebase event-stream
## mirror (put / patch / delete, events split across chunks) and connection bars.
func _mp_unit_selftest() -> void:
	Net.dry = true # nothing the test does may end up in the player's settings file
	Net.set_offline() # …or on the network
	const FbStream = preload("res://scripts/core/fb_stream.gd")
	const PingBars = preload("res://scripts/ui/ping_bars.gd")
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	check.call(Net.parse_code("abcd-efgh") == "ABCDEFGH", "code parse lower+dash")
	check.call(Net.parse_code("ABCD EFGH") == "ABCDEFGH", "code parse space")
	check.call(Net.parse_code("ABCD-EFG0") == "", "code with 0 rejected")
	check.call(Net.parse_code("ABC") == "", "short code rejected")
	check.call(Net.fmt_code("ABCDEFGH") == "ABCD-EFGH", "code format")
	check.call(Net.parse_code(Net.code()) == Net.code(), "own code valid")
	var s := FbStream.new()
	s.handle_event("event: put\ndata: {\"path\":\"/\",\"data\":{\"AAAABBBB\":{\"n\":\"Мыкола\",\"t\":5}}}")
	check.call(s.synced and s.data.AAAABBBB.n == "Мыкола", "snapshot put")
	s.handle_event("event: patch\ndata: {\"path\":\"/AAAABBBB\",\"data\":{\"v\":\"base\",\"b\":[1,2,3]}}")
	check.call(s.data.AAAABBBB.v == "base" and s.data.AAAABBBB.n == "Мыкола", "patch merges")
	s.handle_event("event: put\ndata: {\"path\":\"/CCCCDDDD/n\",\"data\":\"Оля\"}")
	check.call(s.data.CCCCDDDD.n == "Оля", "deep put creates")
	s.handle_event("event: put\ndata: {\"path\":\"/AAAABBBB\",\"data\":null}")
	check.call(not s.data.has("AAAABBBB"), "put null deletes")
	s.handle_event("event: keep-alive\ndata: null")
	check.call(s.data.has("CCCCDDDD"), "keep-alive ignored")
	# a Cyrillic nick cut in half by a chunk boundary, CRLF line ends
	var raw := "event: put\r\ndata: {\"path\":\"/EEEEFFFF\",\"data\":{\"n\":\"Жора\"}}\r\n\r\n".to_utf8_buffer()
	s._buf = raw.slice(0, 40)
	s._parse()
	check.call(not s.data.has("EEEEFFFF"), "half event waits")
	s._buf.append_array(raw.slice(40))
	s._parse()
	check.call(s.data.has("EEEEFFFF") and s.data.EEEEFFFF.n == "Жора", "split utf8 event")
	s.free()
	check.call(PingBars.for_ping(80) == 5 and PingBars.for_ping(2000) == 1, "ping bars")
	check.call(Net.reason_text("no", "Оля") != "no" and Net.reason_text("closed") != "closed", "reason texts")
	print("UAD MPTEST unit: %s" % ("OK" if fails.is_empty() else "FAIL " + ", ".join(fails)))
	if String(_args.get("screen", "")) == "worlds":
		# the multiplayer tab with one friend of each kind: world open, online, offline
		WorldsMenu.last_tab = "mp"
		GS.settings["friends"] = [{"code": "KYVHAST2", "name": "Мыкола"}, {"code": "DESA7777", "name": "Оля"}, {"code": "ZHRAXXX3", "name": "Жора"}]
		Net.friend_info = {
			"KYVHAST2": {"online": true, "nick": "Мыкола", "s": "host", "ping": 140, "w": {"n": "Мыкола", "world": GS.ctext("defense", "kyiv"), "city": "kyiv", "day": 7, "night": true, "players": 2, "max": 4}},
			"DESA7777": {"online": true, "nick": "Оля", "s": "game", "ping": 320, "w": {}},
			"ZHRAXXX3": {"online": false, "nick": "Жора", "s": "", "ping": 0, "w": {}},
		}


## Depth precision: the near plane moves out as the camera climbs — 0.5 m at street level, up to
## 12 m high over the city. With 0.5 m everywhere the depth buffer could no longer tell the roads,
## their markings and the water from the ground a kilometre away, and the map flickered.
func _fit_near() -> void:
	var high: bool = game == null or not is_instance_valid(game) or String(game.view) == "top"
	cam.near = clampf(cam.global_position.y * 0.03, 0.5, 12.0) if high else 0.5


## Waits for an account call that answers through cb(ok: bool, text: String); returns [ok, text].
func _acct_call(f: Callable) -> Array:
	var box := []
	f.call(func(ok: bool, text: String) -> void: box.append_array([ok, text]))
	var frames := 0
	while box.is_empty() and frames < 600:
		frames += 1
		await get_tree().process_frame
	return box if not box.is_empty() else [false, "timeout"]


## --acctest: the optional accounts, offline. The database is an in-memory stand-in (FbDb.mock) and
## so is Firebase Authentication (api_key "mock"): nothing reaches the network or the settings file.
func _acct_selftest() -> void:
	const Account = preload("res://scripts/core/account.gd")
	# a saved session survives a restart only if the settings file keeps the key
	var kept := GS.settings.has("account")
	Net.dry = true
	Net.set_offline()
	Net.db.mock = {}
	Net.account.auth.api_key = "mock"
	# a real session saved on this computer is set aside (in memory only: Net.dry keeps the file)
	Net.account.logout()
	Net.account.lost = false
	GS.settings["account"] = {}
	GS.settings["nick"] = "Тарас"
	GS.settings["friends"] = [{"code": "FRNDAAAA", "name": "Мыкола"}]
	var m: Dictionary = Net.db.mock
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	check.call(kept, "account is a saved setting")
	var dev := Net.device_code()
	check.call(Net.accounts_enabled() and not Net.account.active() and Net.code() == dev, "starts on the device code")
	check.call(Account.check_nick("ab") != "" and Account.check_nick("a.b.c") != "" and Account.check_nick("x/y_z") != "", "bad nicks refused")
	check.call(Account.check_nick("Тарас_1") == "" and Account.check_nick("Їжак-2") == "" and Account.check_nick("Olha") == "", "good nicks pass")
	# registering moves the device's code, nick and friends into the account
	var r: Array = await _acct_call(func(cb: Callable) -> void: Net.register("Тарас", "taras@test.ua", "secret1", cb))
	check.call(r[0], "register: %s" % r[1])
	var uid := Net.account.auth.uid
	check.call(Net.account.active() and Net.code() == dev and Net.nick() == "Тарас", "account keeps the device code and nick")
	check.call(Net.friends().size() == 1 and String(Net.friends()[0].code) == "FRNDAAAA", "device friends moved in")
	check.call(m.get("names", {}).get("тарас", {}).get("c") == dev and m.get("codes", {}).get(dev) == uid, "nick and code claimed")
	check.call(m.get("accounts", {}).get(uid, {}).get("f", {}).has("FRNDAAAA"), "friend list in the cloud")
	check.call(Net.db.auth != "" and Net.conn.auth == Net.db.auth, "the token rides with requests")
	check.call(not var_to_str(GS.settings).contains("secret1"), "the password is never stored")
	Net.logout()
	check.call(not Net.account.active() and Net.code() == dev and Net.db.auth == "", "sign out: device code back, no token")
	# nicks are unique whatever the letter case; a refused nick creates no login
	r = await _acct_call(func(cb: Callable) -> void: Net.register("ТАРАС", "other@test.ua", "secret2", cb))
	check.call(not r[0] and not Net.account.auth._mock_users.has("other@test.ua"), "nick taken in any letter case")
	r = await _acct_call(func(cb: Callable) -> void: Net.register("Olha", "bad-mail", "secret2", cb))
	check.call(not r[0] and not Net.account.active(), "bad email refused")
	# a second account made on this device: the device's code already has an owner
	r = await _acct_call(func(cb: Callable) -> void: Net.register("Olha", "olha@test.ua", "secret3", cb))
	var olha_code := Net.code()
	check.call(r[0] and olha_code != dev and Net.parse_code(olha_code) == olha_code, "second account gets its own code")
	r = await _acct_call(func(cb: Callable) -> void: Net.add_friend("тАрАс", cb))
	check.call(r[0] and Net.last_added == dev and String(r[1]) == "Тарас", "friend found by nick")
	r = await _acct_call(func(cb: Callable) -> void: Net.add_friend("nobody_here", cb))
	check.call(not r[0], "unknown nick")
	r = await _acct_call(func(cb: Callable) -> void: Net.add_friend("olha", cb))
	check.call(not r[0], "own nick refused")
	r = await _acct_call(func(cb: Callable) -> void: Net.add_friend("a", cb))
	check.call(not r[0], "neither a code nor a nick")
	Net.logout()
	r = await _acct_call(func(cb: Callable) -> void: Net.login("taras@test.ua", "wrong-pass", cb))
	check.call(not r[0] and not Net.account.active(), "wrong password refused")
	# a friend added on the device while signed out joins the account at sign-in
	GS.settings["friends"] = [{"code": "FRNDBBBB", "name": "Оля"}]
	r = await _acct_call(func(cb: Callable) -> void: Net.login(" TARAS@test.ua ", "secret1", cb))
	check.call(r[0] and Net.code() == dev and Net.nick() == "Тарас", "sign in brings the account back")
	var codes := Net.friends().map(func(f) -> String: return String(f.code))
	check.call(codes.has("FRNDAAAA") and codes.has("FRNDBBBB") and m.accounts[uid].f.has("FRNDBBBB"), "device friends merged at sign-in")
	Net.remove_friend("FRNDAAAA")
	await get_tree().process_frame
	check.call(not m.accounts[uid].f.has("FRNDAAAA"), "removed from the cloud list")
	r = await _acct_call(func(cb: Callable) -> void: Net.rename("OLHA", cb))
	check.call(not r[0] and Net.nick() == "Тарас", "rename to a taken nick refused")
	r = await _acct_call(func(cb: Callable) -> void: Net.rename("Taras_UA", cb))
	check.call(r[0] and Net.nick() == "Taras_UA" and m.names.has("taras_ua") and not m.names.has("тарас") and m.accounts[uid].n == "Taras_UA", "rename moves the nick")
	# the saved session is picked up after a restart
	var again := Account.new()
	add_child(again)
	again.setup("mock", Net.db, Callable())
	again.auth._mock_users = Net.account.auth._mock_users
	for i in 5:
		await get_tree().process_frame
	check.call(again.active() and again.auth.has_token() and again.code == dev and again.nick == "Taras_UA", "session restored after a restart")
	again.queue_free()
	r = await _acct_call(func(cb: Callable) -> void: Net.delete_account("nope", cb))
	check.call(not r[0] and Net.account.active(), "deletion asks for the password")
	r = await _acct_call(func(cb: Callable) -> void: Net.delete_account("secret1", cb))
	check.call(r[0] and not Net.account.active() and Net.code() == dev, "account deleted, device code back")
	check.call(not m.names.has("taras_ua") and not m.get("codes", {}).has(dev) and not m.get("accounts", {}).has(uid), "nick, code and profile gone")
	check.call(not Net.account.auth._mock_users.has("taras@test.ua"), "the login itself is gone")
	# the password was changed elsewhere: the saved session stops working and the device takes over
	r = await _acct_call(func(cb: Callable) -> void: Net.login("olha@test.ua", "secret3", cb))
	check.call(r[0] and Net.code() == olha_code, "second account signs in")
	Net.account.auth._mock_users.erase("olha@test.ua")
	Net.account.auth.refresh()
	for i in 5:
		await get_tree().process_frame
	check.call(not Net.account.active() and Net.account.lost and Net.code() == dev, "revoked session falls back to the device")
	print("UAD ACCTEST: %s" % ("OK" if fails.is_empty() else "FAIL " + ", ".join(fails)))
	if _args.has("accshow"):
		_acct_show(String(_args.accshow))


## --acctest --accshow=out|in|login|register|manage|delete: the multiplayer tab in that state (or
## with that dialog open), for pictures of the account screens.
func _acct_show(what: String) -> void:
	Net.account.lost = false
	GS.settings["nick"] = "Тарас"
	GS.settings["friends"] = [{"code": "KYVHAST2", "name": "Мыкола"}, {"code": "DESA7777", "name": "Оля"}, {"code": "ZHRAXXX3", "name": "Жора"}]
	if what in ["in", "manage", "delete"]:
		await _acct_call(func(cb: Callable) -> void: Net.register("Тарас", "taras@ukr.net", "secret1", cb))
	Net.friend_info = {
		"KYVHAST2": {"online": true, "nick": "Мыкола", "s": "host", "ping": 140, "w": {"n": "Мыкола", "world": GS.ctext("defense", "kyiv"), "city": "kyiv", "day": 7, "night": true, "players": 2, "max": 4}},
		"DESA7777": {"online": true, "nick": "Оля", "s": "game", "ping": 320, "w": {}},
		"ZHRAXXX3": {"online": false, "nick": "Жора", "s": "", "ping": 0, "w": {}},
	}
	# friends' state stays as set above: polls fail quietly without the stand-in database
	Net.db.mock = null
	WorldsMenu.last_tab = "mp"
	show_worlds()
	var w = screen
	await get_tree().process_frame
	match what:
		"login":
			w._open_login()
		"register":
			w._open_register()
		"manage":
			w._open_account()
		"delete":
			w._open_account()
			await get_tree().process_frame
			AccountUi.confirm_delete(w, Callable())


var _mp_stage := 0
const _MP_FAKE := "TESTPLYR"


## --mptest with --autotest: a friend is faked into an offline "session" (no database) and the
## game has to show them in the city and on the radar, watch through their eyes, list them on
## Tab and show a join request the host can accept.
func _mp_session_selftest() -> void:
	if _mp_stage == 0 and _clock >= 1.0:
		_mp_stage = 1
		Net.set_offline() # every write fails quietly, no stream reaches the network
		Net.open_world()
		var p := Net._player("Мыкола", 1)
		p.base = GS.base_pos + Vector3(220, 0, 90)
		p.has_base = true
		p.loc = GS.base_loc
		p.cam = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1)), p.base + Vector3(0, 12, 0))
		p.has_cam = true
		p.view = "base"
		p.ping = 180
		Net.players[_MP_FAKE] = p
	elif _mp_stage == 1 and _clock >= 2.0:
		_mp_stage = 2
		var node: Dictionary = game.remote._p.get(_MP_FAKE, {})
		var base_ok: bool = not node.is_empty() and (node.base as Node3D).visible and (node.base as Node3D).position.distance_to(Net.players[_MP_FAKE].base) < 30.0
		print("UAD MPTEST friend base shown=%s eye=%s" % [base_ok, not node.is_empty() and (node.eye as Node3D).visible])
		game.watch(_MP_FAKE)
	elif _mp_stage == 2 and _clock >= 3.0:
		_mp_stage = 3
		var d: float = cam.global_position.distance_to(Net.players[_MP_FAKE].cam.origin)
		print("UAD MPTEST watch view=%s cam_dist=%.2f banner=%s" % [game.view, d, game.hud._watch_lbl.visible])
		game.set_view("top")
		game.hud.toggle_players()
		Net.pending["ZZZZYYYY"] = {"nick": "Оля", "t": Net._clock}
		Net.join_requested.emit("ZZZZYYYY", "Оля")
	elif _mp_stage == 3 and _clock >= 4.0:
		_mp_stage = 4
		var rows: int = game.hud._players._rows.get_child_count() if game.hud.players_open() else -1
		print("UAD MPTEST list open=%s rows=%d cursor=%s card=%s" % [game.hud.players_open(), rows, game.ui_cursor, game.hud._req_cards.has("ZZZZYYYY")])
		game.hud._answer_request("ZZZZYYYY", true)
		print("UAD MPTEST accepted players=%d card_gone=%s" % [Net.players.size(), not game.hud._req_cards.has("ZZZZYYYY")])
		Net.players.erase(_MP_FAKE)
	elif _mp_stage == 4 and _clock >= 4.5:
		_mp_stage = 5
		print("UAD MPTEST friend removed from city=%s" % [not game.remote._p.has(_MP_FAKE)])
		Net.close()
		print("UAD MPTEST closed role='%s'" % Net.role)


## --offscreen: pictures without a window on anybody's screen. The capture script
## (tools_scripts/shots.sh) starts the game with a tiny borderless window that never takes the
## focus (override.cfg) far outside every screen and without sound; the 3D view is rendered into
## an off-screen buffer of --shot-size (1920x1080) that --shot / --shotlist save.
var _shot_vp: SubViewport
var _shot_cam: Camera3D
## --shotlist=file.json: [{file, pos: [x, y, z], look: [x, y, z], fov, night, fog, hold}, …]
## taken one after another in the same run, then the game quits.
var _shots: Array = []
var _shot_i := 0
var _shot_t := -1.0


func _setup_offscreen() -> void:
	var w := get_window()
	w.position = Vector2i(-32000, -32000)
	var screens := []
	var visible_somewhere := false
	var wr := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	for i in DisplayServer.get_screen_count():
		var sr := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		screens.append(sr)
		if sr.intersects(wr):
			visible_somewhere = true
	print("UAD OFFSCREEN window %s on screens %s visible=%s" % [wr, screens, visible_somewhere])
	if visible_somewhere:
		# never flash a window on the player's screen: better no picture at all
		print("UAD OFFSCREEN window would be visible — aborting")
		get_tree().quit()
		return
	var size := Vector2i(1920, 1080)
	if _args.has("shot-size"):
		var p := String(_args["shot-size"]).split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	_shot_vp = SubViewport.new()
	_shot_vp.size = size
	_shot_vp.world_3d = get_viewport().find_world_3d()
	_shot_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shot_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_shot_vp)
	_shot_cam = Camera3D.new()
	_shot_vp.add_child(_shot_cam)
	_shot_cam.current = true
	get_tree().create_timer(1.0, true, false, true).timeout.connect(func() -> void:
		print("UAD OFFSCREEN after 1 s: focused=%s window=%s" % [DisplayServer.window_is_focused(), Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())]))
	if _args.has("shotlist"):
		var f := FileAccess.open(String(_args.shotlist), FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				_shots = parsed
		print("UAD SHOTS %d planned" % _shots.size())


## The rendered picture: the off-screen buffer in a capture run, the window otherwise.
func _frame_image() -> Image:
	# --shot-ui: the whole window with the interface (the capture script gives it full size then)
	var tex := _shot_vp.get_texture() if _shot_vp != null and not _args.has("shot-ui") else get_viewport().get_texture()
	return tex.get_image()


## One entry of the shot list per call: aim the camera, let the frame settle, save it.
func _shot_list_step() -> void:
	if _shots.is_empty() or _shot_i >= _shots.size() or _clock < float(_args.get("shot-start", "1.5")):
		return
	var s: Dictionary = _shots[_shot_i]
	if game != null and is_instance_valid(game):
		game.rig.set_process(false) # the camera belongs to the shot list now
	var pos: Array = s.get("pos", [900, 300, 900])
	var look: Array = s.get("look", [0, 60, 0])
	cam.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	cam.look_at(Vector3(float(look[0]), float(look[1]), float(look[2])), Vector3.UP)
	cam.fov = float(s.get("fov", 62.0))
	if s.has("night") and (game == null or not is_instance_valid(game)):
		map.set_night(float(s.night))
	if s.has("fog"):
		map.set_fog_scale(float(s.fog))
	if _shot_t < 0.0:
		_shot_t = _clock
		return
	if _clock - _shot_t < float(s.get("hold", 0.6)):
		return
	var file := String(s.get("file", "shot_%d.png" % _shot_i))
	var img := _frame_image()
	if file.ends_with(".jpg"):
		img.save_jpg(file, float(s.get("quality", 0.9)))
	else:
		img.save_png(file)
	print("UAD SHOT %d/%d saved %s (%d fps)" % [_shot_i + 1, _shots.size(), file, Engine.get_frames_per_second()])
	_shot_i += 1
	_shot_t = -1.0
	if _shot_i >= _shots.size() and not _args.has("quit-at"):
		get_tree().quit()


## --mphost (with --autotest) / --mpjoin=CODE: a real session between two copies of the game
## through the database — run both headless with their own --mpid. The host opens its world,
## lets the guest in and starts the night once the guest's battery stands; the guest knocks,
## takes a position next to the host and fires at the shared raid. Both print what arrived.
var _quitting := false
var _mp_live := {"opened": false, "night": false, "joined_at": -1.0, "picked": false, "armed": false, "last": 0.0}


func _mp_live_setup() -> void:
	Net.dry = true # the test never touches the player's settings file
	GS.settings["nick"] = GS.t("Хост-тест") if _args.has("mphost") else GS.t("Гость-тест")
	if _args.has("mphost"):
		Net.join_requested.connect(func(c: String, n: String) -> void:
			print("UAD MPLIVE host: request from %s (%s) at %.1f s" % [n, c, _clock])
			Net.accept(c))
		Net.player_joined.connect(func(n: String) -> void:
			print("UAD MPLIVE host: %s joined at %.1f s" % [n, _clock])
			_mp_live.joined_at = _clock)
		Net.player_left.connect(func(n: String) -> void: print("UAD MPLIVE host: %s left at %.1f s" % [n, _clock]))
		return
	Net.request_sent.connect(func() -> void: print("UAD MPLIVE guest: request sent at %.1f s" % _clock))
	Net.join_answered.connect(func(ok: bool, info: Dictionary) -> void:
		print("UAD MPLIVE guest: answer ok=%s at %.1f s (%s)" % [ok, _clock, info.get("world", info.get("reason", ""))])
		if ok:
			join_world(info))
	Net.connect_failed.connect(func(r: String) -> void: print("UAD MPLIVE guest: failed: " + r))
	Net.session_ended.connect(func(r: String) -> void: print("UAD MPLIVE guest: session ended: " + r))
	# --mpdelay=SECONDS: knock only once the host has had time to open its world
	get_tree().create_timer(float(_args.get("mpdelay", "0.1"))).timeout.connect(func() -> void:
		Net.request_join(Net.parse_code(String(_args.mpjoin))))


func _mp_live_step() -> void:
	var g_ok: bool = game != null and is_instance_valid(game)
	if _args.has("mphost"):
		if not _mp_live.opened and g_ok and _clock > 1.0:
			_mp_live.opened = true
			Net.open_world()
			print("UAD MPLIVE host: world open, code %s" % Net.code())
		var placed := Net.others().any(func(c) -> bool: return bool(Net.players[c].has_base))
		if g_ok and not _mp_live.night and placed:
			# the guest's battery stands: dusk falls at once
			_mp_live.night = true
			game.director.phase_time = game.director.phase_len
			if _args.has("mpholdfire"):
				# the guest has to do the shooting: kills, rewards and debris bills go to them
				game.auto_fire = 0
				for id in game.weapons:
					game.weapons[id].target = null
			print("UAD MPLIVE host: night starts at %.1f s" % _clock)
	else:
		if Net.role == "guest" and not _mp_live.picked and screen != null and is_instance_valid(screen) and screen.get_script() == MapSelect:
			_mp_live.picked = true
			var hb: Array = Net.world.get("base", [0.0, 0.0])
			var spot: Vector3 = map.nearest_base_spot(Vector3(float(hb[0]) + 140.0, 0, float(hb[1])), GS.Loc.FIELD)
			var loc: int = map.location_at(spot.x, spot.z)
			print("UAD MPLIVE guest: base at %.0f,%.0f (host at %.0f,%.0f) at %.1f s" % [spot.x, spot.z, float(hb[0]), float(hb[1]), _clock])
			create_world(spot, loc if loc >= 0 else GS.Loc.FIELD)
		if g_ok and Net.role == "guest" and not _mp_live.armed:
			_mp_live.armed = true
			GS.money = 400000
			for id in ["mg", "gepard", "iris"]:
				game.purchase_weapon(id)
			GS.money = 30000
			for aid in GS.AMMO_ORDER:
				GS.ammo[aid] = 40
			game.auto_fire = 2
	if _clock - float(_mp_live.last) >= 10.0:
		_mp_live.last = _clock
		_mp_live_report()


func _mp_live_report() -> void:
	var q := Net.quality()
	var g_ok: bool = game != null and is_instance_valid(game)
	if _args.has("mphost"):
		var applied := 0
		if g_ok:
			for c in game._net_applied:
				applied += (game._net_applied[c] as Dictionary).size()
		print("UAD MPLIVE host t=%.0f: players=%d enemies=%d snapshots=%d raid_rtt=%dms state_rtt=%dms guest_hit_targets=%d bank=%s phase=%s" % [
			_clock, Net.players.size(), game.enemies.size() if g_ok else -1, Net._raid_seq, int(Net.conn_raid.rtt_avg), q.rtt, applied,
			JSON.stringify(game._net_bank) if g_ok else "{}", game.director.phase_name() if g_ok else "-"])
	else:
		var err := "-"
		if g_ok and game.net_err_n > 0:
			err = "avg %.1f m · max %.1f m (%d updates)" % [game.net_err_sum / game.net_err_n * 5.0, game.net_err_max * 5.0, game.net_err_n]
		print("UAD MPLIVE guest t=%.0f: role=%s puppets=%d raid=%.1f/s lag=%dms rtt=%dms kills=%d money=%d phase=%s correction=%s" % [
			_clock, Net.role, game.net_enemies.size() if g_ok else -1, q.hz, q.lag, q.rtt, int(GS.stats.get("kills", 0)), GS.money,
			game.director.phase_name() if g_ok else "-", err])


func _print_summary() -> void:
	print("UAD SUMMARY: fps=%d day=%d money=%d city=%.0f base=%.0f stats=%s enemies=%d cam=%s" % [
		Engine.get_frames_per_second(), GS.day, GS.money, GS.city, GS.base_hp, str(GS.stats), game.enemies.size() if game else -1, str(cam.global_position)])
	if GS.track_missing:
		print("UAD I18N missing (%s): %d" % [TranslationServer.get_locale(), GS.missing.size()])
		for k in GS.missing:
			print("   ", k)
	if _crush_bi >= 0:
		print("UAD CRUSH NOW: h=%.1f of %.1f crush=%.2f damaged=%d fires=%d repairs=%d" % [
			map.fp_center[_crush_bi].y, map.fp_box[_crush_bi].x, map.crush_of(_crush_bi), map.fp_damaged[_crush_bi],
			game.fire_service.active_fires() if game else -1, game.fire_service.repairs.size() if game else -1])
	if game:
		print("UAD FEED: videos=%d clips=%d playing=%s idx=%d day=%d phase=%d t=%.1f paused=%s" % [GS.videos.size(),
			(GS.latest_video().get("clips", []) as Array).size(), str(game.reel.playing), game.reel.index,
			GS.day, game.director.phase, game.director.phase_time, str(get_tree().paused)])
	if game:
		print("UAD LAUNCHED: ", game.launched)
	if game and game.view == "walk":
		print("UAD WALK: pos=%s on_floor=%s" % [str(game.walker.pos), game.walker.on_floor])
	if game:
		print("UAD RIG: target=%s dist=%.1f pitch=%.2f tdist=%.1f tpitch=%.2f proc=%s" % [str(game.rig.target), game.rig.dist, game.rig.pitch, game.rig._t_dist, game.rig._t_pitch, game.rig.is_processing()])
