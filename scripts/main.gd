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
##   --parade=id,id,…           (with --autotest) those threat models in a row over the battery
##   --fpsprobe=FROM,TO         frame rate between those seconds: average, the slow frames, where the
##                              time goes (script, render CPU, GPU), draw calls and triangles
##   --gfxoff=a,b,…             switch parts of the picture off for a measurement: msaa, ssr, ssil,
##                              ssao, vfog, shadows, glow, lamps (their real lights), scale=0.67
##   --fxstage                  (with --autotest) night at once and a staged raid on the battery,
##                              the same every run: the sky effects for the shot list
##   --crush=X,Z                collapse and set fire to the building at X,Z (fire-service test)
##   --camat=X,Z[,DIST]         park the overhead camera on a spot
##   --screen=menu|settings|map|worlds|create|game   --open=shop|pause|morning|gameover|feed|video|record
##   --daystrike=ballistic|cruise   (with --autotest) a strike in the daytime, without the dice
##   --touch --alarmtouch       fingers on the air-raid alarm button of the usual game
##   --touch --hunttouch        a finger on the launcher button (a hunt) opens the strike map on it
##   --keytest                  verify the rebindable control map
##   --mptest                   multiplayer self-test, offline: codes, the Firebase event mirror and
##                              (with --autotest) friends in the city, watching, player list, requests
##   --mpid=CODE                play as another friend code (a second copy on the same computer)
##   --striketest               counter-strikes on launch sites: every city has its sites, discovery,
##                              reach and ships, a strike landing, the raid shrinking, repairs, saving
##   --sitesdown                every launch site destroyed before the night (the raid must shrink)
##   --autohunt                 (with --autotest) HIMARS / ATACMS go at every launcher caught in the open
##   --open=strikes [--strikedemo]   the strike map (the demo shows every state of a site)
##   --acctest                  accounts self-test, offline (in-memory database, stand-in sign-in):
##                              register, nick rules, friends by nick, sign in / out, rename,
##                              saved session, deletion, a session revoked elsewhere
##   --mphost / --mpjoin=CODE   a live two-copy session through the database (see _mp_live_setup)
##   --offscreen --shotlist=f.json [--shot-ui]   pictures without a window (tools_scripts/shots.sh)
##   --fakerelease=N            pretend build N was published (the update offer in the menu)
##   --avitest[=path]           write a synthetic clip and read the container back
##   --exporttest               run the video recorder on generated frames and verify the file
##   --customcity[=flip]        the ready-made drawn city of a new server (with --plan: its plan)
##   --srvtest                  a server's draft against the bot (with --autotest): the drawn city, the
##                              match clock, the bot's strikes on us; --srv-side=0|1 --srv-armor=N
##                              --srv-income=N --srv-money=N --srv-dist=N change the rules of the run
##   --srv-strike=SECONDS[,weapon,count]   our own strike at the other city at that moment
##   --srv-end=SECONDS          the other city falls at that moment (the end of a match)
##   --srv-blank                (with --srvtest) the city is an empty field: nothing drawn at all
##   --srvflow                  the way of a player through a draft's test: the server's screen, "test
##                              against the bot" for the second city, the position on the map, the match
##   --edittest                 the city editor worked through its own handlers: the 3D view (the
##                              city built from the drawing, taps and drags on the ground, the city
##                              built again after a change), then on the plan every tool, a drag,
##                              undo, the limits, "Done"
##   --editview=plan|3d         the view the city editor opens in (pictures of --screen=cityedit)
##   --touch --edittouch        (with --screen=cityedit) fingers on the 3D editor through the input
##                              system: a tap puts a district, a drag on it moves it, a drag on empty
##                              ground moves the camera, two fingers pinch it closer
##   --citytest                 the map editor's own cities: the store, a world created in a drawn
##                              city (saved, loaded, the editor's copy deleted), launch sites, the
##                              drawing handed to a guest of a friend's world
##   --screen=cities            the map editor's list (with --offline: two cities to look at)
##   --srvunit                  servers self-test, offline (in-memory database): hostile city and
##                              server data, publishing, the list, joining a side, the captain and
##                              the handover, strikes and outcomes, leaving
##   --open=attack              the attack screen of a match
##   --screen=server|cityedit|servers   the server's screen, the city editor, the servers tab
##   --offline                  nothing reaches the network and no setting is written (pictures of
##                              the multiplayer and server screens); --srvdemo fills the list of servers
##   --press=K,K,K              send those keys one per second (input round trip)
##   --bind=action:KEY          rebind a control before the session (with --press)
##   --shot=path.png --shot-at=SECONDS   --quit-at=SECONDS   --speed=N   --follow

const CityMap = preload("res://scripts/world/city_map.gd")
const Cities = preload("res://scripts/world/cities.gd")
const Shaders = preload("res://scripts/world/shaders.gd")
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
const ServerDef = preload("res://scripts/core/server_def.gd")
const ServerEditor = preload("res://scripts/ui/server_editor.gd")
const CityEditor = preload("res://scripts/ui/city_editor.gd")
const CityStore = preload("res://scripts/core/city_store.gd")
const CitiesMenu = preload("res://scripts/ui/cities_menu.gd")
const StrikesRules = preload("res://scripts/game/strikes.gd")

var map
var cam: Camera3D
var ui: CanvasLayer
var screen: Node
var game: Node
var pending_world := {"name": GS.t("Оборона Киева"), "difficulty": 1, "city": "kyiv"}
## The match on a server being set up or played: {"def": ServerDef, "side": 0 | 1, "bot": bool}.
var server := {}
## The city the "create world" screen opens on (the map editor's "create a world in this city").
var create_city := ""
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
## --hunttouch: frames since the launcher button was first seen.
var _ht := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	UiKit.install_theme()
	_parse_args()
	if not _args.has("offscreen"):
		get_window().min_size = Vector2i(960, 540)
	CityStore.register_all() # the cities drawn in the map editor are cities like the others
	# the menu shows the city of the most recently played world
	var start_city := Cities.DEFAULT
	var recent := GS.list_worlds()
	if not recent.is_empty():
		start_city = String(recent[0].get("city_id", Cities.DEFAULT))
	start_city = String(_args.get("city", start_city))
	if _args.has("customcity"):
		# test hook: the ready-made drawn city of a new server (=flip for its mirrored twin)
		start_city = "srv_test_0"
		Cities.register(start_city, Cities.CustomCity.sample("Северск", String(_args.customcity) == "flip"))
	if _args.has("srvtest"):
		# test hook: a new server's draft, the city of one side on screen from the start
		server = {"def": _test_server(), "side": clampi(int(_args.get("srv-side", "0")), 0, 1), "bot": true}
		start_city = ServerDef.city_id(server.def, int(server.side))
		Cities.register(start_city, server.def.cities[int(server.side)])
	GS.city_id = start_city if Cities.has(start_city) else Cities.DEFAULT
	_build_map(GS.city_id)
	pending_world = {"name": GS.ctext("defense"), "difficulty": 1, "city": GS.city_id}
	cam = Camera3D.new()
	cam.far = 170000.0
	cam.near = 0.5
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_setup_post()
	if _args.has("offscreen"):
		_setup_offscreen()
	Net.main = self
	Net.session_ended.connect(_on_session_ended)
	if _args.has("plan"):
		# --plan=file.png [--plan-at=x,z,size] (a close-up of one part of the city)
		var pa := String(_args.get("plan-at", "0,0,0")).split(",")
		map.dump_plan(String(_args.plan), float(pa[0]), float(pa[1]), float(pa[2]))
	if _args.has("mptest"):
		_mp_unit_selftest()
	if _args.has("acctest"):
		_acct_selftest()
	if _args.has("striketest"):
		_strike_selftest()
	if _args.has("srvunit"):
		_srv_unit_selftest()
	if _args.has("edittest"):
		_editor_selftest.call_deferred()
	if _args.has("citytest"):
		_city_selftest.call_deferred()
	if _args.has("mphost") or _args.has("mpjoin"):
		_mp_live_setup()
	if not _args.has("quit-at"):
		# a normal launch (not a test run): is there a newer build?
		Net.check_release()
	if _args.has("fakerelease"):
		# test hook: pretend the database announced a newer build (the update offer in the menu)
		Net.release = {"build": int(_args.fakerelease), "version": "1.0.%d" % int(_args.fakerelease), "name": "v1.0.%d Alpha" % int(_args.fakerelease), "date": "2026-09-24",
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
			if _args.has("owncity"):
				# test hook: the screen opened on a city of the player's own
				show_create_world(false, CityStore.city_id(CityStore.create(Cities.CustomCity.sample("Новоград"))))
			else:
				show_create_world()
		"cities":
			if CityStore.dry:
				CityStore.create(Cities.CustomCity.sample("Новоград"))
				CityStore.create(Cities.CustomCity.sample("Приречье", true))
			show_cities()
		"game":
			if _args.has("srvtest"):
				_start_server_test()
			else:
				_start_autotest()
		"server":
			show_server(_test_server())
		"cityedit":
			show_city_editor(_test_server(), 0)
			if _args.has("editsel"):
				# a picture with something selected: the road, and a river half drawn
				screen._sel = {"type": "road", "i": 0, "pt": 2}
				screen._draft = [[-5200.0, 4600.0], [-3000.0, 5200.0], [-600.0, 4700.0]]
				screen._refresh.call_deferred()
		"servers":
			WorldsMenu.last_tab = "servers"
			show_worlds()
			if _args.has("srvdemo"):
				# a list as the database would give it, for a look at the tab
				screen._srv_public = [
					{"id": "K7MQ4XRT", "name": "Северск против Южного", "owner": "AAAAAAAA", "nick": "Мыкола", "team": 8, "cities": ["Северск", "Южный"], "players": [5, 4]},
					{"id": "P3HD8WQN", "name": "Дуэль портов", "owner": "BBBBBBBB", "nick": "Оксана", "team": 4, "cities": ["Приморск", "Гавань"], "players": [4, 4]},
					{"id": "Z9XC2VBM", "name": "Два берега", "owner": "CCCCCCCC", "nick": "Tablet_Mike", "team": 2, "cities": ["Левый", "Правый"], "players": [0, 0]},
				]
				screen._srv_state = "ok"
				screen._srv_entries.clear()
				screen._rebuild_servers.call_deferred()
		"training":
			# the MaxRealism range (--train-bot walks through its lessons by itself)
			start_training()
		_:
			show_menu()


## The camera layer (Shaders.CAMERA) over the 3D picture and under the interface: Max / UltraMax
## on the Forward+ renderer, when the player has not switched it off.
var _post: ColorRect
var _post_shot: ColorRect


func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_post = _post_rect()
	layer.add_child(_post)
	GS.state_changed.connect(_update_post)
	_update_post()


func _post_rect() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = Shaders.CAMERA
	m.shader = sh
	r.material = m
	return r


func _update_post() -> void:
	var on: bool = int(GS.settings.quality) >= 3 and bool(GS.settings.get("film", true)) and RenderingServer.get_current_rendering_method() == "forward_plus"
	if _post != null:
		_post.visible = on
	if _post_shot != null:
		_post_shot.visible = on


## How much of the camera shows: 0.45 in play, 1 for a photo.
func set_post_amount(a: float) -> void:
	for r in [_post, _post_shot]:
		if r != null:
			((r as ColorRect).material as ShaderMaterial).set_shader_parameter("amount", a)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("speed"):
		Engine.time_scale = float(_args.speed)
	if _args.has("nomarkers"):
		GS.settings.markers = false
	if _args.has("offline") or _args.has("srvtest") or _args.has("srvunit") or _args.has("srvflow") or _args.has("edittest") or _args.has("citytest"):
		ServerDef.dry = true # a test's server never lands among the player's drafts
		CityStore.dry = true # …nor a test's city among the player's cities
	if _args.has("offline"):
		Net.set_offline()
		Net.dry = true
	if _args.has("touch"):
		GS.force_touch = true # the interface of a touch screen (sticks, on-screen buttons)
	if _args.has("quality"):
		# test hook: the graphics level of this run only (the settings file is not touched)
		GS.settings.quality = int(_args.quality)
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
	# a drawn city may have been redrawn under the same id
	if map and is_instance_valid(map) and map.city_id == id and map.city == Cities.get_def(id):
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
	var veil := _loading
	_build_map(id)
	# (another change of city may have started while this one waited for its two frames)
	if veil != null and is_instance_valid(veil):
		veil.queue_free()
	if _loading == veil:
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


func show_create_world(real := false, city := "") -> void:
	if real:
		pending_world["realism"] = true # straight from the training range
	create_city = city
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
	if map.city_id != cid or map.city != Cities.get_def(cid):
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
	if bool(pending_world.get("pvp", false)):
		_enter_server(pos, loc)
		return
	var guest := bool(pending_world.get("guest", false))
	GS.new_world(String(pending_world.get("name", GS.ctext("defense"))), int(pending_world.get("difficulty", 1)), pos, loc, map.city_id, bool(pending_world.get("realism", false)) and not guest)
	if guest:
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


# --- Servers: two drawn cities firing at each other (ServerDef, scripts/game/pvp.gd) ------------------
## The screen of one of the player's own servers: its rules, its two cities, the test, publishing.
func show_server(def: Dictionary) -> void:
	Net.close()
	_end_game()
	server = {}
	map.set_labels_visible(false)
	map.set_night(1.0)
	var s := ServerEditor.new()
	s.main = self
	s.def = def
	_show(s, "menu")


## The "Servers" tab of the play screen.
func show_servers() -> void:
	WorldsMenu.last_tab = "servers"
	show_worlds()


## The city editor on one of the two cities of a server: every change goes into its draft.
func show_city_editor(def: Dictionary, side: int) -> void:
	_end_game()
	var e := CityEditor.new()
	e.main = self
	e.city_id = ServerDef.city_id(def, side)
	e.view = String(_args.get("editview", "3d"))
	e.source = def.cities[side]
	e.caption = GS.t("ГОРОД %d") % (side + 1)
	e.caption_color = UiKit.NEON if side == 0 else UiKit.CYAN
	e.flip = side == 1
	e.changed.connect(func(city: Dictionary) -> void:
		def.cities[side] = city
		def["dirty"] = bool(def.get("published", false))
		ServerDef.save(def))
	e.done.connect(func(city: Dictionary) -> void:
		def.cities[side] = city
		ServerDef.save(def)
		show_server(def))
	_show(e, "editor")


## Builds the map of a registered city at once (the city editor's 3D view; its own veil is up).
func build_city(id: String) -> void:
	_build_map(id)


## The map editor's list: the cities the player has drawn (main menu → "Map editor").
func show_cities() -> void:
	Net.close()
	_end_game()
	map.set_labels_visible(false)
	map.set_night(1.0)
	var c := CitiesMenu.new()
	c.main = self
	_show(c, "menu")


## The city editor on one of the player's own cities (CityStore): every change is written at once.
func show_map_editor(id: String) -> void:
	var entry := CityStore.read(id)
	if entry.is_empty():
		show_cities()
		return
	_end_game()
	CitiesMenu.last = id
	var e := CityEditor.new()
	e.main = self
	e.city_id = CityStore.city_id(id)
	e.view = String(_args.get("editview", "3d"))
	e.source = entry.city
	e.caption = GS.t("МОЙ ГОРОД")
	e.changed.connect(func(city: Dictionary) -> void: CityStore.save(id, city))
	e.done.connect(func(city: Dictionary) -> void:
		CityStore.save(id, city)
		show_cities())
	_show(e, "editor")


## Enters a match as a defender of the city of `side`: the city is built and the player picks
## where the battery stands. `bot`: a draft's test, the other city is played by the machine.
func start_server(def: Dictionary, side: int, bot: bool) -> void:
	server = {"def": def, "side": side, "bot": bot}
	var cid := ServerDef.city_id(def, side)
	# the same drawing keeps its map; a redrawn city is registered anew and built again
	if not Cities.is_custom(cid) or JSON.stringify(Cities.get_def(cid).data) != JSON.stringify(Cities.CustomCity.clean(def.cities[side])):
		Cities.register(cid, def.cities[side])
	pending_world = {"name": "%s · %s" % [String(def.name), ServerDef.city_name(def, side)], "difficulty": 1, "city": cid, "pvp": true}
	show_map_select()


## The position is picked: the match starts (nothing of it is ever written to disk).
func _enter_server(pos: Vector3, loc: int) -> void:
	if server.is_empty():
		show_worlds()
		return
	var def: Dictionary = server.def
	GS.new_world(String(def.name), 1, pos, loc, map.city_id, false)
	GS.world_id = ""
	GS.pvp = server.duplicate()
	GS.city_armor = float(def.rules.armor)
	GS.money = int(def.rules.money)
	GS.money_changed.emit(GS.money)
	_start_session()


## Out of a match: back to the server's screen after a draft's test, to the list of servers otherwise.
func leave_server() -> void:
	var was := server
	Net.close()
	server = {}
	if bool(was.get("bot", false)):
		show_server(was.def)
	else:
		WorldsMenu.last_tab = "servers"
		show_worlds()


## The same match once more, from the choice of the position.
func restart_server() -> void:
	if server.is_empty():
		show_worlds()
	else:
		start_server(server.def, int(server.side), bool(server.bot))


## Test hooks: a new draft with the rules of the command line.
func _test_server() -> Dictionary:
	var def := ServerDef.blank("TESTTEST", "test")
	def.id = "TESTSRV2"
	for k in ["armor", "income", "money", "dist"]:
		if _args.has("srv-" + k):
			def.rules[k] = float(_args["srv-" + k])
	if _args.has("srv-blank"):
		def.cities[0] = Cities.CustomCity.blank("Пустошь", 4000.0)
	return ServerDef.clean(def)


## --srvtest: straight into a draft's test with a battery already bought (see _start_autotest).
func _start_server_test() -> void:
	pending_world = {"name": String(server.def.name), "difficulty": 1, "city": map.city_id, "pvp": true}
	var want := {"river": GS.Loc.RIVER, "forest": GS.Loc.FOREST, "city": GS.Loc.CITY, "field": GS.Loc.FIELD}
	var loc_want: int = want.get(String(_args.get("loc", "river")), GS.Loc.RIVER)
	var pos := _find_spot(loc_want)
	_enter_server(pos, loc_want)
	var money := GS.money
	GS.money = 400000
	for id in String(_args.get("weapons", "mg,gepard,drone,iris,patriot")).split(","):
		game.purchase_weapon(id)
	GS.money = money
	for aid in GS.AMMO_ORDER:
		GS.ammo[aid] = 40
	game.auto_fire = 2 if _args.has("autoall") else 1
	GS.money_changed.emit(GS.money)
	print("UAD SRVTEST: %s side=%d base at %s rules=%s targets=%d" % [map.city_id, int(server.side), str(pos), str(server.def.rules), map.targets.size()])


## A friend accepted our join request: load their city and pick where our base stands.
func join_world(info: Dictionary) -> void:
	if Net.role != "guest":
		return
	var cid := String(info.get("city", Cities.DEFAULT))
	if info.get("cd") is Dictionary:
		# the host's world is in a city the host drew: here it is built from the same drawing
		cid = "net_" + Net.host
		Cities.register(cid, info.cd)
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
	if _args.has("fxstage") and game and is_instance_valid(game):
		_fx_stage(delta)
	if _args.has("fpsprobe"):
		_fps_probe(delta)
	if _args.has("lockfirst") and game and is_instance_valid(game) and not game.enemies.is_empty():
		# test hook: the first target is the selected one (the target card of the top view)
		game.locked = game.enemies[0]
	if _args.has("follow") and game and is_instance_valid(game) and not game.enemies.is_empty():
		var near = _nearest_enemy()
		game.rig.focus(near.position)
		game.rig._t_dist = 1500.0
		game.rig._t_pitch = 0.1
		game.locked = near
	if _args.has("aimbot") and game and is_instance_valid(game) and game.view == "base" and not game.enemies.is_empty():
		_aimbot()
	if game and is_instance_valid(game) and game.rl != null:
		_realism_hooks(delta)
	if _args.has("twisttest") and game and is_instance_valid(game) and game.view == "top" and _clock >= 3.0:
		_twist_selftest()
	if _args.has("firetouch") and game and is_instance_valid(game) and game.view == "base" and _clock >= 3.0:
		# --touch --firetouch (the usual game, --view=base): one finger aims, another holds the fire button
		var fb: Vector2 = game.hud.fire_btn.get_global_rect().get_center()
		var mid := get_viewport().get_visible_rect().size * 0.5
		match int(_tt.stage):
			0:
				_finger(0, mid, true)
				_slide(0, mid, Vector2(60, 0))
				_finger(1, fb, true)
			4:
				print("UAD FIRETOUCH button shown=%s held by the second finger: trigger=%s" % [game.hud.fire_btn.is_visible_in_tree(), game.base_view.trigger])
				_finger(1, fb, false)
			8:
				print("UAD FIRETOUCH released: trigger=%s" % game.base_view.trigger)
				_finger(0, mid + Vector2(60, 0), false)
		_tt.stage = int(_tt.stage) + 1
	if _args.has("alarmtouch") and game and is_instance_valid(game) and game.rl == null and _clock >= 3.0:
		# --touch --alarmtouch (the usual game): the alarm button under the second finger on the
		# screen, then under the only one — each tap must count once
		var ab: Vector2 = game.hud.alarm_btn.get_global_rect().get_center()
		var away := get_viewport().get_visible_rect().size * 0.5
		match int(_tt.stage):
			0:
				_finger(0, away, true)
				_finger(1, ab, true)
			4:
				print("UAD ALARMTOUCH second finger: alarm=%s shown=%s" % [game.alarm, game.hud.alarm_btn.is_visible_in_tree()])
				_finger(1, ab, false)
				_finger(0, away, false)
			8:
				_finger(0, ab, true)
			12:
				_finger(0, ab, false)
			16:
				print("UAD ALARMTOUCH only finger: alarm=%s locked=%s" % [game.alarm, game.locked != null])
		_tt.stage = int(_tt.stage) + 1
	if _args.has("hunttouch") and game and is_instance_valid(game) and (_ht > 0 or game.hud.hunt_btn.is_visible_in_tree()):
		# --touch --hunttouch: the launcher button under the second finger opens the strike map on
		# that launcher
		var hb: Vector2 = game.hud.hunt_btn.get_global_rect().get_center()
		var away := get_viewport().get_visible_rect().size * 0.5
		match _ht:
			0:
				_finger(0, away, true)
				_finger(1, hb, true)
			4:
				_finger(1, hb, false)
				_finger(0, away, false)
				var ov = game.hud._overlay
				print("UAD HUNTTOUCH map=%s on=%s hot=%s" % [ov != null and ov.get_script() == preload("res://scripts/ui/strike_map.gd"), String(ov._sel) if ov != null and "_sel" in ov else "", str(StrikesRules.hot.keys())])
		_ht += 1
	if _args.has("f16input") and game and is_instance_valid(game) and game.view == "fighter":
		_f16_input(delta)
	elif _args.has("aimbot") and game and is_instance_valid(game) and game.view == "fighter":
		_fighter_pilot(delta)
	elif (_args.has("aimbot") or _args.has("f16input")) and String(_args.get("view", "")) == "fighter" and game and is_instance_valid(game) and game.fighter.state == "ready" and not game.enemies.is_empty():
		game.toggle_fighter() # the test pilot goes up again once the jet is rearmed
	if _args.has("aimbot") and game and is_instance_valid(game) and game.view == "mfg":
		_mfg_pilot(delta)
	if _args.has("aimbot") and game and is_instance_valid(game) and game.view == "fpv":
		_fpv_pilot(delta)
	elif _args.has("aimbot") and String(_args.get("view", "")) == "fpv" and game and is_instance_valid(game) and not game.drones.is_empty() and not game.enemies.is_empty():
		game.enter_fpv() # the test pilot takes the next drone as soon as one is up
	if _args.has("sitesdown") and game and is_instance_valid(game):
		# test hook: every launch site of the city struck out before the night
		_args.erase("sitesdown")
		for st in preload("res://scripts/game/strikes.gd").sites(map.city):
			GS.sites[String(st.id)] = {"known": true, "st": "destroyed", "n": 5, "def": 0.0}
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
	if _args.has("srv-strike") and game and is_instance_valid(game) and game.pvp != null:
		# test hook: our own strike at the other city — "seconds[,weapon,count]"
		var sp := String(_args["srv-strike"]).split(",")
		if _clock >= float(sp[0]):
			_args.erase("srv-strike")
			var sw := String(sp[1]) if sp.size() > 1 else "shahed"
			var sc := int(sp[2]) if sp.size() > 2 else 4
			var sent: bool = game.pvp.launch_strike(sw, sc, Vector2(100, 200))
			print("UAD SRVTEST strike %s x%d sent=%s money=%d blocker=%s" % [sw, sc, sent, GS.money, game.pvp.blocker(sw, sc)])
	if _args.has("srv-end") and game and is_instance_valid(game) and game.pvp != null and _clock >= float(_args["srv-end"]):
		_args.erase("srv-end")
		game.pvp.set_enemy_hp(0.0)
	if _args.has("srvflow"):
		_srv_flow_step()
	if _args.has("edittouch") and screen != null and is_instance_valid(screen) and screen.get_script() == CityEditor and _clock >= 2.0 and (int(_et.n) > 0 or (not screen._building and not screen._stale)):
		_edit_touch_step()
	if _args.has("mptest") and game and is_instance_valid(game):
		_mp_session_selftest()
	if _args.has("mphost") or _args.has("mpjoin"):
		_mp_live_step()
	if _args.has("autohunt") and game and is_instance_valid(game) and not StrikesRules.hot.is_empty():
		for id in StrikesRules.hot:
			var hs := StrikesRules.site(map.city, String(id))
			if StrikesRules.hunting(String(id)) == 0 and not hs.is_empty():
				for w in ["atacms", "himars"]:
					if StrikesRules.blocker(hs, w, not game.director.is_night()) == "":
						StrikesRules.send(hs, w)
						print("UAD HUNT sent %s at %s (%.0f s left)" % [w, id, float(StrikesRules.hot[id])])
						break
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
		# the menu camera circles the heart of the city
		var mf: Vector3 = map.city.map_focus
		cam.global_position = mf + Vector3(cos(_orbit) * 2400.0, 620.0, sin(_orbit) * 2400.0)
		cam.look_at(mf + Vector3(0, 120, 0), Vector3.UP)
	_clock += delta / maxf(Engine.time_scale, 0.001)
	_shot_list_step()
	if _shot_cam != null:
		_shot_cam.global_transform = cam.global_transform
		_shot_cam.fov = cam.fov
		_shot_cam.near = cam.near
		_shot_cam.far = cam.far
	if _args.has("shot") and not _shot_done and _clock >= float(_args.get("shot-at", "3")):
		_shot_done = true
		_save_picture(_frame_image(), String(_args.shot), float(_args.get("shot-quality", "0.9")))
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
		"strikes":
			if _args.has("strikedemo"):
				_strike_demo()
			game.hud.open_strikes()
		"attack":
			game.hud.open_strikes()
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
## --view=fighter --aimbot: a test pilot. The ring goes to the lead point of the nearest threat
## no faster than a hand would move it; AIM-120 from afar, AIM-9X closer, the gun at the end.
func _fighter_pilot(delta: float) -> void:
	var f = game.fighter
	if not f.active or f.state != "air":
		return
	var best = null
	var bd := INF
	for e in game.enemies:
		if not e.dead and GS.eff("aim9", e) > 0.0 and f.pos.distance_to(e.position) < bd:
			bd = f.pos.distance_to(e.position)
			best = e
	f.trigger = false
	var want: Vector3 = Vector3(GS.base_pos.x - f.pos.x, 1500.0 - f.pos.y, GS.base_pos.z - f.pos.z).normalized()
	if best != null:
		want = (Bullet.lead(f.pos, best.position, best.vel, (1050.0 + f.speed) * GS.TEMPO) - f.pos).normalized()
		f.burner = bd > 9000.0
		f.throttle = 0.85
		if f.locked and f.lock == best and float(best.inbound) < float(best.hp):
			if bd > 16000.0 and int(f.loaded.aim120) > 0 and bd < f.range_of("aim120"):
				f.fire("aim120")
			elif bd <= f.range_of("aim9") and bd > 1200.0 and int(f.loaded.aim9) > 0:
				f.fire("aim9")
		f.trigger = bd < 1000.0 and f.dir.angle_to(want) < 0.05
	# the test pilot keeps above the roofs: missiles do the low work
	if f.pos.y + want.y * 1500.0 < 450.0:
		want = Vector3(want.x, maxf(want.y, (450.0 - f.pos.y) / 1500.0), want.z).normalized()
	if f.pull_up or f.pos.y < 300.0:
		want = (want + Vector3(0, 1.5, 0)).normalized()
		f.aim = want # a pilot pulls hard when the warning sounds
	var off: float = f.aim.angle_to(want)
	if off > 0.0001:
		f.aim = f.aim.slerp(want, clampf(1.5 * delta / off, 0.0, 1.0)).normalized()


## --view=fighter --f16input: a pilot with the person's hands only — the arrow keys to steer and
## the right mouse button for missiles, sent as real input events, so what a person presses is
## what gets checked: it points the ring straight at the nearest threat, however low, and leaves
## the ground to Auto-GCAS. --f16kab (--city=kharkiv): KABs first, missiles on KABs only.
var _in := {"presses": 0, "launched": 0, "kab": 0, "gun": 0.0, "cd": 0.0, "seen_kab": false}


func _f16_input(delta: float) -> void:
	var f = game.fighter
	if not f.active or f.state != "air":
		return
	var best = null
	var bd := INF
	for e in game.enemies:
		if e.dead or GS.eff("aim9", e) <= 0.0:
			continue
		var d: float = f.pos.distance_to(e.position) * (0.3 if String(e.variant) == "kab" and _args.has("f16kab") else 1.0)
		if d < bd:
			bd = d
			best = e
	var want: Vector3 = Vector3(GS.base_pos.x - f.pos.x, 1500.0 - f.pos.y, GS.base_pos.z - f.pos.z).normalized()
	if best != null:
		want = (best.position - f.pos).normalized()
		if String(best.variant) == "kab":
			_in.seen_kab = true
	# --f16dive: the ring held straight down at the ground (Auto-GCAS must save the jet)
	if _args.has("f16dive"):
		want = Vector3(want.x, -4.0, want.z).normalized()
	# steer towards `want`
	var yaw := wrapf(atan2(want.x, -want.z) - atan2(f.aim.x, -f.aim.z), -PI, PI)
	var pitch := asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(f.aim.y, -1.0, 1.0))
	# with the arrow keys (a window-less run cannot capture the mouse for mouse steering)
	var hold := {KEY_RIGHT: yaw > 0.03, KEY_LEFT: yaw < -0.03, KEY_UP: pitch > 0.03, KEY_DOWN: pitch < -0.03}
	for kc in hold:
		if bool(hold[kc]) != Input.is_key_pressed(kc):
			var ke := InputEventKey.new()
			ke.keycode = kc
			ke.physical_keycode = kc
			ke.pressed = bool(hold[kc])
			Input.parse_input_event(ke)
	# RMB for a missile when there is a target for it (the events reach the jet on the next
	# frame: launches are counted by the stores going down)
	var total: int = int(f.loaded.aim9) + int(f.loaded.aim120)
	if total < int(_in.get("total", total)):
		_in.launched += 1
		if bool(_in.get("aim_kab", false)):
			_in.kab += 1
	_in.total = total
	_in.cd -= delta
	var kind: String = f.auto_kind()
	var tgt = f.best_target(kind) if kind != "" else null
	# --f16kab: missiles for the KABs only
	if tgt != null and _in.cd <= 0.0 and (String(tgt.variant) == "kab" or not _args.has("f16kab")):
		_in.cd = 1.2
		_in.aim_kab = String(tgt.variant) == "kab"
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = pressed
			Input.parse_input_event(mb)
		_in.presses += 1
	# the gun: the on-screen button's way (a window-less run has no captured mouse for LMB)
	game.set_trigger(f.gun_target != null)
	if f.trigger:
		_in.gun += delta


## --view=mfg --aimbot: a test crew. The driver makes for the radio's beacon and backs off the
## walls it runs into; once the drone is in reach the gunner takes over and leads it.
var _mfg_stuck := 0.0
var _mfg_back := 0.0


func _mfg_pilot(delta: float) -> void:
	var m = game.mfg
	if not m.active:
		return
	var tip = m.tip
	if tip == null or not is_instance_valid(tip) or tip.dead:
		m._touch_vec = Vector2.ZERO
		m.fire_held = false
		return
	var reach: bool = m.pos.distance_to(tip.position) < float(GS.WEAPONS.mg.range) * 0.85
	if reach and m.seat == "drive":
		m._touch_vec = Vector2.ZERO
		m.switch_seat()
	elif not reach and m.seat == "gun":
		m.fire_held = false
		m.switch_seat()
	if m.seat == "gun":
		var muzzle: Vector3 = (m.unit.muzzle as Node3D).global_position
		var ld := Bullet.lead(muzzle, tip.position, tip.vel, GS.shot_speed("mg"))
		var d := (ld - muzzle).normalized()
		var wy := atan2(-d.x, -d.z)
		var wp := asin(clampf(d.y, -1.0, 1.0))
		m.gun_yaw = rotate_toward(m.gun_yaw, wy, 2.5 * delta)
		m.gun_pitch = move_toward(m.gun_pitch, wp, 2.5 * delta)
		m.fire_held = absf(angle_difference(m.gun_yaw, wy)) < 0.03 and absf(m.gun_pitch - wp) < 0.03
		return
	var to: Vector3 = m.tip_point - m.pos
	var diff := angle_difference(m.heading, atan2(-to.x, -to.z))
	var steer := clampf(-diff * 2.0, -1.0, 1.0)
	var thr := 1.0 if absf(diff) < 1.2 else 0.4
	if Vector2(to.x, to.z).length() < 20.0:
		thr = 0.0
	if _mfg_back > 0.0:
		_mfg_back -= delta
		thr = -1.0
		steer = -steer
	elif absf(m.speed) < 1.0 and thr > 0.0:
		_mfg_stuck += delta
		if _mfg_stuck > 1.0:
			_mfg_back = 1.2
			_mfg_stuck = 0.0
	else:
		_mfg_stuck = 0.0
	m._touch_vec = Vector2(steer, thr)


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
		aim = Bullet.lead(w.muzzle.global_position, e.position, e.vel, GS.shot_speed(w.id))
	var d: Vector3 = (aim - cam.global_position).normalized()
	bv.yaw = atan2(-d.x, -d.z)
	bv.pitch = asin(clampf(d.y, -1.0, 1.0))
	var in_r: bool = w.in_range(e)
	if String(w.def.kind) == "gun":
		bv.trigger = in_r
	elif bv.lock_ready:
		bv.launch()


# --- Automated test harness ------------------------------------------------------------
## The spot of the wanted kind nearest to the heart of the city.
func _find_spot(loc_want: int) -> Vector3:
	var r := 0.0
	var mf: Vector3 = map.city.map_focus
	while r < map.half * 0.9:
		var a := 0.0
		while a < TAU:
			var p := mf + Vector3(cos(a) * r, 0, sin(a) * r)
			if map.location_at(p.x, p.z) == loc_want:
				return p
			a += 0.2
		r += 150.0
	return Vector3.ZERO


## The training range of the MaxRealism mode (scripts/game/training.gd): a position on the
## riverside of the city on screen with a pickup, an Igla crew and an S-300. Never saved.
func start_training() -> void:
	const Training = preload("res://scripts/game/training.gd")
	GS.new_world(GS.t("Учебный полигон"), 0, _find_spot(GS.Loc.RIVER), GS.Loc.RIVER, map.city_id, true)
	GS.world_id = "" # never written to disk
	GS.training = true
	GS.unlocked = {}
	for id in Training.KIT:
		GS.unlocked[id] = true
		if GS.AMMO_ORDER.has(id):
			GS.ammo[id] = 40
	_start_session()


func _start_autotest() -> void:
	var want := {"river": GS.Loc.RIVER, "forest": GS.Loc.FOREST, "city": GS.Loc.CITY, "field": GS.Loc.FIELD}
	var loc_want: int = want.get(String(_args.get("loc", "river")), GS.Loc.RIVER)
	var pos := _find_spot(loc_want)
	GS.new_world("autotest", 1, pos, loc_want, map.city_id, _args.has("realism"))
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
	if _args.has("daystrike"):
		# a strike in the daytime without the dice: --daystrike=ballistic|cruise
		game.director.day_strike(GS.day, String(_args.daystrike))
	if _args.has("weapon"):
		game.select_weapon(String(_args.weapon))
	if String(_args.get("view", "top")) == "base":
		game.set_view("base")
		game.base_view.nv = _args.has("nv")
	elif String(_args.get("view", "top")) == "fpv":
		game.enter_fpv()
	elif String(_args.get("view", "top")) == "fighter":
		if _args.has("f16"):
			GS.unlocked["f16"] = true
			GS.ammo["aim9"] = 8
			GS.ammo["aim120"] = 4
		game.toggle_fighter()
		if _args.has("aimbot"):
			game.auto_fire = 0 # every kill is the jet's
	elif String(_args.get("view", "top")) == "mfg":
		game.toggle_mfg()
		if _args.has("aimbot"):
			game.auto_fire = 0 # every kill is the mobile group's own
	elif String(_args.get("view", "top")) == "walk":
		game.set_view("walk")
		if _args.has("walkat"):
			var p := String(_args.walkat).split(",")
			game.walker.pos = game.walker.find_free(Vector3(float(p[0]), 0, float(p[1])))
		if _args.has("walkyaw"):
			game.walker.yaw = deg_to_rad(float(_args.walkyaw))
		game.walker.pitch = float(_args.get("walkpitch", "0.08"))
		game.walker.test_forward = _args.has("walkfwd")
	if _args.has("parade"):
		# the threat models side by side, 60 m over the battery, for a look at them (shots.sh)
		const Meshes = preload("res://scripts/core/meshes.gd")
		var row := String(_args.parade).split(",")
		for i in row.size():
			var m: Node3D = Meshes.enemy_model(row[i])
			m.position = GS.base_pos + Vector3((i - (row.size() - 1) * 0.5) * 14.0, 60.0, 0.0)
			game.fx_root.add_child(m)
	print("UAD: autotest base at ", pos, " loc=", loc_want)


## --fpsprobe / --gfxoff: what the frame rate is and what it is spent on. The measured viewport is
## the off-screen one of a capture run when there is one (the window is 64 pixels there).
var _probe := {"on": false, "done": false, "frames": [], "procs": [], "cpu": 0.0, "gpu": 0.0, "n": 0, "draws": 0, "prims": 0, "objs": 0}


func _fps_probe(delta: float) -> void:
	if bool(_probe.done):
		return
	var span := String(_args.fpsprobe).split(",")
	var from := float(span[0])
	var to := float(span[1]) if span.size() > 1 else from + 10.0
	var vp: Viewport = _shot_vp if _shot_vp != null else get_viewport()
	if not bool(_probe.on):
		if _clock < from - 2.0:
			return
		_probe.on = true
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		if _args.has("gfxoff"):
			_gfx_off(vp)
		return
	if _clock < from:
		return
	(_probe.frames as Array).append(delta / maxf(Engine.time_scale, 0.001))
	_probe.cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
	_probe.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	(_probe.procs as Array).append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_probe.draws += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_probe.prims += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_probe.objs += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	_probe.n += 1
	if _clock < to:
		return
	_probe.done = true
	var fr: Array = _probe.frames
	fr.sort()
	var total := 0.0
	for f in fr:
		total += float(f)
	var n := float(maxi(int(_probe.n), 1))
	var slow: float = fr[int(fr.size() * 0.99)] if fr.size() > 0 else 0.0
	var pr: Array = _probe.procs
	pr.sort()
	_probe_stream()
	print("UAD FPS %s q=%d size=%s off=[%s]: avg=%.1f median=%.1f low1%%=%.1f | frame %.1f ms: game step %.1f ms, render cpu %.1f ms, gpu %.1f ms | draws=%d objects=%d tris=%.2fM" % [
		RenderingServer.get_current_rendering_method(), int(GS.settings.quality), str(vp.get_visible_rect().size), String(_args.get("gfxoff", "")),
		float(fr.size()) / maxf(total, 0.001), 1.0 / maxf(float(fr[fr.size() / 2]), 0.0001), 1.0 / maxf(slow, 0.0001),
		float(fr[fr.size() / 2]) * 1000.0, float(pr[pr.size() / 2]), _probe.cpu / n, _probe.gpu / n,
		int(_probe.draws / n), int(_probe.objs / n), float(_probe.prims) / n / 1.0e6])


## What the detail stream holds now: instances and triangles by kind, near and mid sets apart.
func _probe_stream() -> void:
	for pair in [["near", map.stream._near], ["mid", map.stream._mid]]:
		var sets: Dictionary = pair[1]
		var by := {}
		for t in sets:
			if not (sets[t] as Node3D).visible:
				continue
			for c in (sets[t] as Node).get_children():
				var mmi := c as MultiMeshInstance3D
				if mmi == null:
					continue
				var mesh: Mesh = mmi.multimesh.mesh
				var tris := 0
				for si in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(si)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				var key := "%d tris%s" % [tris, " +shadow" if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else ""]
				var e: Array = by.get(key, [0, 0])
				e[0] += mmi.multimesh.instance_count
				e[1] += mmi.multimesh.instance_count * tris
				by[key] = e
		var keys := by.keys()
		keys.sort_custom(func(a, b) -> bool: return int(by[a][1]) > int(by[b][1]))
		var parts := []
		for k in keys:
			parts.append("%s × %d = %.2fM" % [k, int(by[k][0]), float(by[k][1]) / 1.0e6])
		print("UAD STREAM %s tiles=%d: %s" % [pair[0], sets.size(), "; ".join(parts)])


func _gfx_off(vp: Viewport) -> void:
	var env: Environment = map.env
	for what in String(_args.gfxoff).split(","):
		match what:
			"msaa":
				vp.msaa_3d = Viewport.MSAA_DISABLED
			"msaa2":
				vp.msaa_3d = Viewport.MSAA_2X
			"msaa4":
				vp.msaa_3d = Viewport.MSAA_4X
			"ssr":
				env.ssr_enabled = false
			"ssil":
				env.ssil_enabled = false
			"ssao":
				env.ssao_enabled = false
			"vfog":
				env.volumetric_fog_enabled = false
			"glow":
				env.glow_enabled = false
			"haze":
				Game.Fx.no_haze = true
			"trails":
				const Trail = preload("res://scripts/game/trail.gd")
				Trail.off = true
			"sparks":
				Game.Fx.no_sparks = true
			"lamps":
				map.forward = false
			"life":
				for b in [map.b_traffic, map.b_cars, map.b_people, map.b_detail, map.b_props]:
					b.set_visible(false)
			"lights":
				map.b_lights.set_visible(false)
			"build":
				map.b_build.set_visible(false)
				map.b_roof.set_visible(false)
			"stream":
				map.stream.visible = false
			"shadows":
				map._sun.shadow_enabled = false
				RenderingServer.global_shader_parameter_set("lamp_real", Vector4(0, 0, 0, 0))
			_:
				if what.begins_with("scale="):
					vp.scaling_3d_scale = float(what.substr(6))
				elif what.begins_with("fsr="):
					vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
					vp.msaa_3d = Viewport.MSAA_DISABLED
					vp.scaling_3d_scale = float(what.substr(4))


## --fxstage: night falls at once and the battery is raided on a fixed timetable, from a fixed
## side and close in, so that a shot list finds launches, trails and intercepts in the sky at
## known seconds. [second, weapon, count, altitude, kilometres out].
const FX_STAGE := [
	[1.0, "shahed", 6, 700.0, 3.2], [3.0, "cruise", 4, 250.0, 7.0], [6.0, "ballistic", 2, 0.0, 0.0],
	[8.0, "geran3", 4, 1200.0, 6.0], [11.0, "kalibr", 4, 180.0, 8.0], [13.0, "shahed", 8, 400.0, 3.0],
	[16.0, "ballistic", 3, 0.0, 0.0], [18.0, "cruise", 5, 300.0, 7.0], [21.0, "geran5", 4, 900.0, 6.0],
]
var _fx_t := -1.0
var _fx_i := 0


func _fx_stage(delta: float) -> void:
	if _fx_t < 0.0:
		_fx_t = 0.0
		Game.Fx.quiet = true
		seed(7)
		game._rng.seed = 7
		if String(_args.fxstage) != "day": # --fxstage=day: the same raid in daylight
			game.director.start_night()
			game.director.night_blend = 1.0
		game.director.schedule.clear()
		game.director.phase_len = 1.0e6
	_fx_t += delta
	# the phase never ends, and its clock reads like a watch in progress (the pictures show it)
	game.director.phase_len = game.director.phase_time + 137.0
	GS.base_hp = 100.0
	GS.city = 100.0
	if String(_args.fxstage) == "calm": # --fxstage=calm: the night without a raid
		return
	if _fx_i >= FX_STAGE.size():
		if game.enemies.is_empty() or _fx_t > 30.0:
			_fx_t = 0.0 # the raid starts over
			_fx_i = 0
		return
	var s: Array = FX_STAGE[_fx_i]
	if _fx_t < float(s[0]):
		return
	_fx_i += 1
	var before: int = game.enemies.size()
	game.launch(String(s[1]), int(s[2]), true, float(s[3]))
	# the same bearings every run, and close in: no minute of waiting for the first trail
	var bearing := deg_to_rad(40.0 + 25.0 * float(_fx_i % 4))
	var from := Vector3(sin(bearing), 0.0, -cos(bearing))
	var side := Vector3(-from.z, 0.0, from.x)
	for k in range(before, game.enemies.size()):
		var e = game.enemies[k]
		if String(e.type) == "ballistic":
			continue
		var j := k - before
		e.position = GS.base_pos + from * (float(s[4]) * 1000.0 + (j / 4) * 300.0) + side * ((j % 4 - 1.5) * 260.0) + Vector3(0, float(s[3]) * (0.9 + 0.05 * (j % 5)), 0)
		e.waypoints.clear()
		e.waypoints.append(e.target_pos)
		e.cruise_alt = e.position.y
		e.vel = Vector3(e.target_pos.x - e.position.x, 0.0, e.target_pos.z - e.position.z).normalized() * e.speed


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
	GS.new_world(GS.t("Тестовый мир"), 2, Vector3(123, 0, -45), GS.Loc.RIVER, "odesa", true)
	GS.money = 77777
	GS.day = 5
	GS.unlocked["gepard"] = true
	GS.damaged = [3, 17, 42]
	GS.save_world()
	var id := GS.world_id
	var found := GS.list_worlds().any(func(w) -> bool: return String(w.id) == id)
	GS.money = 0
	GS.day = 1
	GS.realism = false
	var ok := GS.load_world(id)
	var good := ok and found and GS.realism and GS.city_id == "odesa" and GS.money == 77777 and GS.day == 5 and GS.difficulty == 2 and GS.unlocked.has("gepard") and GS.damaged == [3, 17, 42] and GS.base_pos.is_equal_approx(Vector3(123, 0, -45))
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


## --srvflow: what a player does to try a draft — from the server's screen into the match.
var _flow := 0


func _srv_flow_step() -> void:
	match _flow:
		0:
			if _clock >= 1.0:
				_flow = 1
				show_server(_test_server())
		1:
			if _clock >= 2.0 and screen != null and screen.get_script() == ServerEditor:
				_flow = 2
				print("UAD SRVFLOW server screen: cities=%d arsenal=%d" % [screen.def.cities.size(), screen._arsenal_btns.size()])
				start_server(screen.def, 1, true) # what "Test against the bot" of the second city does
		2:
			if screen != null and is_instance_valid(screen) and screen.get_script() == MapSelect and _loading == null:
				_flow = 3
				var spot := _find_spot(GS.Loc.FIELD)
				print("UAD SRVFLOW map: city=%s custom=%s half=%d spot=%s loc=%d" % [map.city_id, Cities.is_custom(map.city_id), int(map.half), str(spot), map.location_at(spot.x, spot.z)])
				create_world(spot, GS.Loc.FIELD)
		3:
			if game and is_instance_valid(game) and game.pvp != null:
				_flow = 4
				print("UAD SRVFLOW match: side=%d bot=%s money=%d armor=%.2f saved_id='%s' city=%s enemy=%s" % [game.pvp.side, game.pvp.bot, GS.money, GS.city_armor, GS.world_id, game.pvp.my_name(), game.pvp.enemy_name()])
				_flow_t = _clock
		4:
			if _clock - _flow_t >= 3.0:
				_flow = 5
				leave_server()
		5:
			if screen != null and is_instance_valid(screen) and screen.get_script() == ServerEditor:
				_flow = 6
				print("UAD SRVFLOW back on the server screen: game=%s pvp=%s role='%s'" % [game != null and is_instance_valid(game), not GS.pvp.is_empty() and game != null, Net.role])


var _flow_t := 0.0


## --edittouch: real touch events on the 3D editor (one step every few frames; the 3D city is
## built when it starts). The first finger is also the emulated mouse, as on a device.
var _et := {"n": 0, "at": Vector2(430, 400), "d0": Vector2.ZERO, "cam0": Vector3.ZERO, "dist0": 0.0}


func _edit_touch_step() -> void:
	var ed = screen
	var at: Vector2 = _et.at
	_et.n = int(_et.n) + 1
	match int(_et.n):
		1:
			ed.data.districts.clear()
			ed._set_tool("district")
			_finger(0, at, true)
		4:
			_finger(0, at, false)
		8:
			var d: Array = ed.data.districts[0] if ed.data.districts.size() == 1 else ["", 0.0, 0.0]
			_et.d0 = Vector2(float(d[1]), float(d[2]))
			var g = ed._ground(at)
			print("UAD EDITTOUCH tap: districts=%d at the finger=%s" % [ed.data.districts.size(), g != null and (_et.d0 as Vector2).distance_to(g) < 5.0])
			ed._stale = false # (the test goes on without waiting for the city to be built again)
			ed._set_tool("select")
			_finger(0, at, true)
		10, 12, 14:
			_slide(0, at + Vector2(25, 0) * ((int(_et.n) - 10) / 2), Vector2(25, 0))
		16:
			_finger(0, at + Vector2(75, 0), false)
		20:
			var d: Array = ed.data.districts[0]
			print("UAD EDITTOUCH drag on the district: moved %d m east, undo steps=%d" % [int(float(d[1]) - (_et.d0 as Vector2).x), ed._undo.size()])
			ed._stale = false
			_et.cam0 = ed._rig._t_target
			_finger(0, Vector2(120, 620), true)
		22, 24, 26:
			_slide(0, Vector2(120, 620) + Vector2(30, 0) * ((int(_et.n) - 22) / 2), Vector2(30, 0))
		28:
			_finger(0, Vector2(210, 620), false)
		32:
			var d: Array = ed.data.districts[0]
			print("UAD EDITTOUCH drag on empty ground: camera moved %d m, districts=%d, the district stayed=%s" % [int((ed._rig._t_target as Vector3).distance_to(_et.cam0)), ed.data.districts.size(), absf(float(d[1]) - (_et.d0 as Vector2).x) > 50.0])
			_et.dist0 = ed._rig._t_dist
			_finger(0, Vector2(380, 400), true)
			_finger(1, Vector2(480, 400), true)
		34, 36, 38:
			_slide(0, Vector2(380, 400) - Vector2(20, 0) * ((int(_et.n) - 34) / 2), Vector2(-20, 0))
			_slide(1, Vector2(480, 400) + Vector2(20, 0) * ((int(_et.n) - 34) / 2), Vector2(20, 0))
		40:
			_finger(1, Vector2(540, 400), false)
			_finger(0, Vector2(320, 400), false)
		44:
			print("UAD EDITTOUCH pinch: distance x%.2f, districts=%d (two fingers place nothing)" % [ed._rig._t_dist / maxf(float(_et.dist0), 1.0), ed.data.districts.size()])
			_args.erase("edittouch")


## --edittest: the city editor through its own handlers, the way taps and drags reach it.
func _editor_selftest() -> void:
	const CC = preload("res://scripts/world/custom_city.gd")
	var def := _test_server()
	def.cities[0] = CC.blank("Чистый лист", 7000.0)
	show_city_editor(def, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var ed = screen
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	# --- the 3D view: the city is built from the drawing and drawn on where it stands
	var wait_built := func() -> void:
		var n := 0
		while (ed._building or ed._stale) and n < 1200:
			n += 1
			await get_tree().process_frame
	await wait_built.call()
	check.call(ed.view == "3d" and map.city_id == ed.city_id and map.visible and ed._giz.visible and not ed._plan.visible, "the editor opens in 3D on the built city (%s)" % map.city_id)
	await get_tree().process_frame
	var at := Vector2(430, 400) # a point of the screen over the view, clear of the panels
	var g0 = ed._ground(at)
	check.call(g0 != null and ed._inside(g0), "the ground under a point of the screen: %s" % str(g0))
	ed._set_tool("district")
	ed._rig_click(at)
	check.call(ed.data.districts.size() == 1 and Vector2(float(ed.data.districts[0][1]), float(ed.data.districts[0][2])).distance_to(g0) < 1.0 and ed._stale, "a tap on the ground puts a district there")
	await get_tree().process_frame
	check.call(ed._giz.vertex_count() > 100 and ed._giz.label_count() == 1, "the district is marked over the city at once (%d vertices)" % ed._giz.vertex_count())
	await wait_built.call()
	check.call(not ed._stale and map.city == Cities.get_def(ed.city_id) and map.city.districts.size() == 1 and String(map.city.districts[0][5]) == "panel", "the city is built again from the changed drawing")
	await get_tree().process_frame
	# the select tool: a drag that starts on the district moves it, one on empty ground is the camera's
	ed._set_tool("select")
	var before := Vector2(float(ed.data.districts[0][1]), float(ed.data.districts[0][2]))
	var steps: int = ed._undo.size()
	check.call(ed._rig_grab(at), "a drag on a district is the editor's")
	ed._rig_drag(at + Vector2(60, 0), 1)
	ed._rig_drag(at + Vector2(60, 0), 2)
	var after := Vector2(float(ed.data.districts[0][1]), float(ed.data.districts[0][2]))
	check.call(after.x - before.x > 100.0 and absf(after.y - before.y) < 60.0 and ed._undo.size() == steps + 1 and ed._stale, "the district follows the finger across the ground (%d m)" % int(after.x - before.x))
	check.call(not ed._rig_grab(Vector2(60, 660)) and ed._drag.is_empty(), "a drag on empty ground is left to the camera")
	check.call(ed._m_per_unit(g0) > 1.0 and ed._m_per_unit(g0) < 100.0, "a finger's miss is measured in metres of the ground (%.1f m a unit)" % ed._m_per_unit(g0))
	var far: float = ed._rig._t_dist
	ed._zoom(1.0 / 1.3)
	check.call(ed._rig._t_dist < far, "the + button brings the camera closer")
	ed._fit()
	# --- the plan: the other view of the same drawing
	ed.set_view("plan")
	check.call(ed.view == "plan" and ed._plan.visible and not map.visible and not ed._giz.visible and not ed._rig.is_processing(), "the flat plan is a button away")
	while not ed._undo.is_empty():
		ed.undo()
	check.call(ed.data.districts.is_empty() and ed._plan.size.x > 300.0, "an empty city on the plan")
	# a district under the finger, selected at once
	ed._set_tool("district")
	ed._kind = "historic"
	ed._on_tap(Vector2(500, -300))
	check.call(ed.data.districts.size() == 1 and String(ed.data.districts[0][4]) == "historic" and String(ed._sel.get("type", "")) == "district", "district placed and selected")
	ed._on_tap(Vector2(99999, 0))
	check.call(ed.data.districts.size() == 1, "a tap beyond the edge places nothing")
	# a river point by point; one point is no river
	ed._set_tool("river")
	ed._on_tap(Vector2(-6000, -2000))
	ed._set_tool("select")
	check.call(ed.data.rivers.is_empty(), "one point makes no river")
	ed._set_tool("river")
	for p in [Vector2(-6000, -2000), Vector2(0, -1500), Vector2(6000, -2500)]:
		ed._on_tap(p)
	check.call(ed._draft.size() == 3 and ed.data.rivers.is_empty(), "the river is still being drawn")
	ed.undo()
	check.call(ed._draft.size() == 2, "undo takes the last point back")
	ed._on_tap(Vector2(6000, -2500))
	ed._finish_line()
	check.call(ed.data.rivers.size() == 1 and ed.data.rivers[0].p.size() == 3 and float(ed.data.rivers[0].p[0][2]) == 150.0, "river finished with its width")
	ed._set_tool("road")
	ed._on_tap(Vector2(-5000, 500))
	ed._on_tap(Vector2(5000, 800))
	ed._set_tool("object") # changing the tool finishes the line
	check.call(ed.data.roads.size() == 1, "changing the tool finishes the road")
	ed._object = "tpp"
	ed._on_tap(Vector2(-2000, 2000))
	ed._set_tool("lake")
	ed._on_tap(Vector2(3000, 3000))
	ed._set_tool("forest")
	ed._on_tap(Vector2(-4000, -5000))
	check.call(ed.data.objects.size() == 1 and String(ed.data.objects[0].k) == "tpp" and ed.data.lakes.size() == 1 and ed.data.forests.size() == 1, "object, lake and forest placed")
	# picking and dragging with the select tool
	ed._set_tool("select")
	ed._on_tap(Vector2(-2000, 2000))
	check.call(String(ed._sel.get("type", "")) == "object", "an object is picked by a tap")
	ed._on_tap(Vector2(0, -1500))
	check.call(String(ed._sel.get("type", "")) == "river" and int(ed._sel.pt) == 1, "a point of the river is picked")
	ed._on_tap(Vector2(520, -280))
	check.call(String(ed._sel.get("type", "")) == "district", "a district is picked inside its circle")
	var undo_n: int = ed._undo.size()
	ed._on_drag(Vector2(520, -280), 0)
	ed._on_drag(Vector2(1520, 720), 1)
	ed._on_drag(Vector2(1520, 720), 2)
	check.call(absf(float(ed.data.districts[0][1]) - 1500.0) < 1.0 and absf(float(ed.data.districts[0][2]) - 700.0) < 1.0 and ed._undo.size() == undo_n + 1, "district dragged, one undo step")
	var c0: Vector2 = ed._plan.center
	ed._on_drag(Vector2(-6500, 6500), 0)
	ed._on_drag(Vector2(-6000, 6000), 1)
	ed._on_drag(Vector2(-6000, 6000), 2)
	check.call(ed._plan.center != c0 and ed._undo.size() == undo_n + 1, "dragging empty ground moves the plan, not the city")
	ed.undo()
	check.call(absf(float(ed.data.districts[0][1]) - 500.0) < 1.0, "undo puts the district back")
	# the limits hold
	ed._set_tool("district")
	for i in 60:
		ed._on_tap(Vector2(-6000 + i * 200.0, 4000))
	check.call(ed.data.districts.size() == CC.MAX_DISTRICTS, "no more districts than the limit")
	# delete, resize, done
	ed._set_tool("select")
	ed._on_tap(Vector2(3000, 3000))
	ed._delete_selected()
	check.call(ed.data.lakes.is_empty(), "the selected lake deleted")
	ed._resize_city(4000.0)
	var inside := true
	for d in ed.data.districts:
		inside = inside and absf(float(d[1])) <= 4000.0 and absf(float(d[2])) <= 4000.0
	check.call(float(ed.data.size) == 4000.0 and inside, "a smaller square keeps everything inside")
	# back in 3D the city is built from everything drawn on the plan
	ed.set_view("3d")
	await wait_built.call()
	check.call(map.visible and map.city == Cities.get_def(ed.city_id) and map.city.districts.size() == CC.MAX_DISTRICTS and int(map.half) == 4000 and map.fp_box.size() > 1000, "back in 3D: the city of the plan is built (%d buildings)" % map.fp_box.size())
	ed._name.text = "Новоград%\n"
	ed._done()
	await get_tree().process_frame
	check.call(screen.get_script() == ServerEditor and String(def.cities[0].name) == "Новоград" and def.cities[0].districts.size() == CC.MAX_DISTRICTS and def.cities[0].rivers.size() == 1, "done: the server has the drawn city")
	check.call(not FileAccess.file_exists(ServerDef.DIR + String(def.id) + ".json"), "a test writes no draft to disk")
	# the generator takes what was drawn
	var cid := ServerDef.city_id(def, 0)
	Cities.register(cid, def.cities[0])
	_build_map(cid)
	check.call(map.city_id == cid and map.targets.size() >= 1 and map.fp_box.size() > 1000, "the drawn city is built: %d buildings, %d targets" % [map.fp_box.size(), map.targets.size()])
	print("UAD EDITTEST: %s" % ("OK" if fails.is_empty() else "FAIL " + " | ".join(fails)))


## --citytest: the cities of the map editor, offline and in memory. The store keeps and lists them;
## a world is created in one, saved and loaded; the editor's copy is deleted and the world still
## has its city; a redrawn city drops what the save knew of its buildings; the city has launch
## sites to strike; a guest of a friend's world gets the drawing from the host.
func _city_selftest() -> void:
	const CC = preload("res://scripts/world/custom_city.gd")
	const Strikes = preload("res://scripts/game/strikes.gd")
	Net.dry = true
	Net.set_offline()
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	check.call(CityStore.list().is_empty(), "the test starts with no cities (and reads none of the player's)")
	var id := CityStore.create(CC.sample("Новоград"))
	var cid := CityStore.city_id(id)
	check.call(CityStore.list().size() == 1 and String(CityStore.read(id).city.name) == "Новоград" and Cities.has(cid) and Cities.is_custom(cid), "a city is kept and known to the game")
	check.call(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CityStore.DIR)) or not FileAccess.file_exists(CityStore.DIR + id + ".json"), "a test writes no city to disk")
	# the "create world" screen takes it, and not a server's city
	show_create_world(false, cid)
	await get_tree().process_frame
	check.call(screen.get_script() == CreateWorld and String(screen._city) == cid and screen._own_btn.button_pressed and String(screen._own_btn.text) == "Новоград", "the create-world screen opens on the drawn city")
	screen._set_city("kyiv")
	check.call(String(screen._city) == "kyiv" and not screen._own_btn.button_pressed, "back to one of the game's cities")
	Cities.register("srv_TESTSRV2_0", CC.sample("Чужой"))
	screen._set_city("srv_TESTSRV2_0")
	check.call(String(screen._city) == Cities.DEFAULT, "a server's city is not offered for a world")
	screen._set_city(cid)
	screen._name.text = "Мир в Новограде"
	screen._next()
	var frames := 0
	while (screen == null or not is_instance_valid(screen) or screen.get_script() != MapSelect or _loading != null) and frames < 900:
		frames += 1
		await get_tree().process_frame
	check.call(map.city_id == cid and int(map.half) == 7000 and map.targets.size() == 6, "the map of the drawn city is built (%s, %d targets)" % [map.city_id, map.targets.size()])
	var spot := _find_spot(GS.Loc.FIELD)
	create_world(spot, GS.Loc.FIELD)
	var wid := GS.world_id
	check.call(game != null and GS.city_id == cid and wid != "" and game.pvp == null, "a world in the drawn city is running")
	check.call(game.director.schedule.size() >= 1 and not Strikes.sites(map.city).is_empty(), "it has its raids and launch sites to strike (%d sites)" % Strikes.sites(map.city).size())
	GS.damaged = [3, 17]
	GS.save_world()
	var saved := GS.read_world(wid)
	check.call(String(saved.get("city_id", "")) == cid and saved.get("city_data") is Dictionary and int(saved.get("map_ver", 0)) == int(Cities.get_def(cid).version), "the save carries the drawing")
	show_menu()
	check.call(GS.load_world(wid) and GS.city_id == cid and GS.damaged == [3, 17], "the world loads in its city")
	# the city redrawn: another layout, the save's building numbers are dropped
	var redrawn: Dictionary = CityStore.read(id).city
	redrawn.districts.append(["Новый район", 3000.0, -3000.0, 0.0, "panel", 800.0])
	CityStore.save(id, redrawn)
	check.call(GS.load_world(wid) and GS.city_id == cid and GS.damaged.is_empty() and Cities.get_def(cid).districts.size() == 9, "a redrawn city: the world follows it, damage marks dropped")
	# the city deleted from the editor: the world's own copy takes over
	CityStore.remove(id)
	Cities._custom.erase(cid) # as after a restart of the game
	check.call(not Cities.has(cid) and CityStore.list().is_empty(), "the city is gone from the editor")
	var again := GS.list_worlds().filter(func(w) -> bool: return String(w.id) == wid)
	check.call(again.size() == 1 and Cities.has(cid) and GS.load_world(wid) and GS.city_id == cid and String(GS.city_def().name) == "Новоград" and GS.city_def().districts.size() == 8, "the world still has its city: the copy in the save")
	GS.delete_world(wid)
	check.call(not GS.list_worlds().any(func(w) -> bool: return String(w.id) == wid), "the test's world is deleted")
	# a friend's world in a drawn city: the host hands the drawing over, an older game is turned away
	GS.city_id = cid
	var info: Dictionary = Net._world_info()
	check.call(String(info.get("cn", "")) == "Новоград" and not info.has("cd"), "the friends' list gets the city's name, not the drawing")
	Net.role = "guest"
	Net.host = "HASTAAAA"
	join_world({"world": "Мир друга", "city": cid, "n": "Друг", "difficulty": 1, "cd": Cities.get_def(cid).data})
	check.call(String(pending_world.city) == "net_HASTAAAA" and Cities.has("net_HASTAAAA") and Cities.get_def("net_HASTAAAA").districts.size() == 8, "a guest builds the host's city from the drawing")
	frames = 0
	while (map.city_id != "net_HASTAAAA" or _loading != null) and frames < 900:
		frames += 1
		await get_tree().process_frame
	check.call(map.city_id == "net_HASTAAAA" and screen.get_script() == MapSelect, "…and picks a position in it")
	join_world({"world": "x", "city": "kyiv", "n": "Друг", "difficulty": 1})
	check.call(String(pending_world.city) == "kyiv", "a world in one of the game's cities joins as before")
	Net._drop()
	show_menu()
	print("UAD CITYTEST: %s" % ("OK" if fails.is_empty() else "FAIL " + " | ".join(fails)))


## Waits until the deferred answers of the in-memory database have been delivered.
func _settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame
		Net.mock_sync()


## --srvunit: servers, offline. Hostile data is cleaned, a server is published into an in-memory
## database, listed, fetched and joined; the captain's role is taken, handed over and taken back;
## strikes and their outcomes cross between the sides; leaving tidies the database.
func _srv_unit_selftest() -> void:
	const CC = preload("res://scripts/world/custom_city.gd")
	Net.dry = true
	Net.set_offline()
	Net.db.mock = {}
	Net._code_override = "TESTAAAA"
	var m: Dictionary = Net.db.mock
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	# --- data from strangers
	var junk := CC.clean("nonsense")
	check.call(junk.districts.is_empty() and float(junk.size) == 7000.0 and String(junk.name) != "", "a city of nonsense is an empty city")
	var many := []
	for i in 300:
		many.append(["Р%d" % i, 1.0e12, -1.0e12, 9999.0, "castle", 1.0e9])
	var hostile := CC.clean({"name": "Зло%s\n\t<b>" + "x".repeat(500), "size": 1.0e9, "seed": "abc", "districts": many, "rivers": [{"p": "zz"}, {"p": [[0, 0, NAN], [1, 1]]}, 7],
		"lakes": [[0, 0, -5, INF]], "objects": [{"k": 5, "x": "a"}, {"k": "tpp", "x": 1.0e9, "z": 0, "n": 12}], "roads": {"a": 1}})
	check.call(float(hostile.size) == CC.SIZE_MAX and hostile.districts.size() == CC.MAX_DISTRICTS, "size and count limits")
	check.call(not String(hostile.name).contains("%") and not String(hostile.name).contains("\n") and String(hostile.name).length() <= CC.NAME_MAX, "names are plain short text")
	check.call(absf(float(hostile.districts[0][1])) <= CC.SIZE_MAX and String(hostile.districts[0][4]) == "panel" and float(hostile.districts[0][5]) <= 2500.0, "district clamped, unknown kind replaced")
	check.call(hostile.rivers.is_empty() and hostile.roads.is_empty(), "broken lines dropped")
	check.call(hostile.lakes.size() == 1 and float(hostile.lakes[0][2]) >= 60.0 and is_finite(float(hostile.lakes[0][3])), "ellipses finite")
	check.call(hostile.objects.size() == 2 and String(hostile.objects[0].k) == "gov" and float(hostile.objects[1].x) == CC.SIZE_MAX and String(hostile.objects[1].n) == "", "objects cleaned")
	check.call(ServerDef.clean({"id": "bad", "cities": [{}, {}]}).is_empty() and ServerDef.clean({"id": "TESTSRV2", "cities": [{}]}).is_empty() and ServerDef.clean(5).is_empty(), "no server without an id and two cities")
	var odd := ServerDef.clean({"id": "TESTSRV2", "name": "%d%s", "cities": [{}, "x"], "rules": {"money": -5, "income": 1.0e12, "armor": 0, "team": 99, "arsenal": ["nuke", "shahed"]}})
	check.call(int(odd.rules.money) == 5000 and int(odd.rules.income) == 60000 and float(odd.rules.armor) == 0.25 and int(odd.rules.team) == ServerDef.TEAM_MAX, "rules clamped")
	check.call(odd.rules.arsenal == ["shahed"] and not String(odd.name).contains("%"), "unknown weapons dropped")
	check.call(absf(ServerDef.transit("shahed", 300.0) - 98.0) < 1.5 and ServerDef.transit("ballistic", 300.0) == ServerDef.TRANSIT_MIN and ServerDef.transit("shahed", 2000.0) == ServerDef.TRANSIT_MAX, "transit times")
	# --- publishing, the list, the download
	var def := _test_server()
	var r: Array = await _acct_call(func(cb: Callable) -> void: Net.srv_publish(def, cb))
	var sid := String(def.id)
	var servers: Dictionary = m.get("servers", {})
	check.call(r[0] and servers.get("list", {}).get(sid, {}).get("o") == "TESTAAAA" and servers.get("defs", {}).get(sid, {}).get("cities", []).size() == 2, "published: %s" % r[1])
	check.call(not servers.defs[sid].has("published") and String(servers.defs[sid].owner) == "TESTAAAA", "the draft's own marks stay at home")
	var box := []
	Net.srv_list(func(ok: bool, list: Array) -> void: box.append([ok, list]))
	await _settle()
	check.call(box.size() == 1 and box[0][0] and box[0][1].size() == 1 and String(box[0][1][0].id) == sid and box[0][1][0].players == [0, 0], "listed")
	box.clear()
	Net.srv_fetch(sid, func(d: Dictionary) -> void: box.append(d))
	await _settle()
	check.call(box.size() == 1 and String(box[0].get("name", "")) == String(def.name) and box[0].cities[1].districts.size() == 8, "fetched")
	Net.srv_fetch("ZZZZZZZZ", func(d: Dictionary) -> void: box.append(d))
	await _settle()
	check.call(box.size() == 2 and box[1].is_empty(), "a server that is not there")
	# --- joining: alone on the side, so the captain
	r = await _acct_call(func(cb: Callable) -> void: Net.srv_join(def, 0, cb))
	await _settle()
	var live: Dictionary = m.servers.get("live", {}).get(sid, {})
	check.call(r[0] and live.get("s0", {}).has("TESTAAAA") and float(live.s0.TESTAAAA.get("j", 0)) > 0.0, "joined: %s" % r[1])
	await _settle()
	check.call(Net.role == "host" and Net.host == "TESTAAAA" and m.servers.live[sid].s0.get("cap") == "TESTAAAA", "alone on the side: captain (role=%s)" % Net.role)
	check.call(Net.srv_enemy_count() == 0, "nobody on the other side yet")
	var now := float(Net.server_now())
	m.servers.live[sid]["x"] = {"pl": {"s1": {"n": 3, "t": now}}}
	await _settle()
	check.call(Net.srv_enemy_count() == 3, "the other side counted")
	# --- a strike of ours goes out, one of theirs comes in, an outcome goes back
	Net.srv_send_strike(1, {"id": "TESTAAAA_1_1", "w": "shahed", "c": 4, "x": 0, "z": 0, "by": "TESTAAAA", "n": "me", "t": now, "d": 98.0})
	await _settle()
	check.call(m.servers.live[sid].x.get("in1", {}).has("TESTAAAA_1_1"), "strike written for the other side")
	m.servers.live[sid].x["in0"] = {"ENEMYBBB_1_1": {"id": "ENEMYBBB_1_1", "w": "cruise", "c": 2, "x": 100, "z": 200, "by": "ENEMYBBB", "n": "Враг", "t": now, "d": 25.0}}
	await _settle()
	check.call((Net.srv_x().get("in0", {}) as Dictionary).has("ENEMYBBB_1_1"), "their strike seen")
	Net.srv_send_result(0, {"id": "ENEMYBBB_1_1", "h": 1, "k": 1})
	await _settle()
	check.call(m.servers.live[sid].x.get("res", {}).get("ENEMYBBB_1_1", {}).get("h") == 1 and not m.servers.live[sid].x.get("in0", {}).has("ENEMYBBB_1_1"), "outcome written, strike done with")
	# --- an older player is on the side and holds the raid: we follow; they go silent: we take over
	var changes := [0]
	Net.srv_captain_changed.connect(func() -> void: changes[0] += 1)
	m.servers.live[sid].s0["ELDERCCC"] = {"n": "Старший", "s": 1, "t": float(Net.server_now()), "j": 5.0}
	m.servers.live[sid].s0["cap"] = "ELDERCCC"
	await _settle()
	check.call(Net.role == "guest" and Net.host == "ELDERCCC" and Net.players.size() == 2 and changes[0] == 1, "another captain: we follow (role=%s)" % Net.role)
	m.servers.live[sid].s0["ELDERCCC"]["t"] = float(Net.server_now()) - Net.STALE_MS - 5000.0
	Net._cap_claim_t = -99.0
	await _settle()
	await _settle()
	check.call(Net.role == "host" and m.servers.live[sid].s0.get("cap") == "TESTAAAA" and changes[0] >= 2, "the captain went silent: the raid is ours (role=%s)" % Net.role)
	# --- leaving: with the other side still there only our side goes; as the last one, everything
	Net.close()
	await _settle()
	check.call(Net.role == "" and Net.srv.is_empty() and not m.servers.live[sid].has("s0") and m.servers.live[sid].has("x"), "left: our side is gone, the match stays")
	r = await _acct_call(func(cb: Callable) -> void: Net.srv_join(def, 1, cb))
	await _settle()
	await _settle()
	check.call(r[0] and Net.role == "host" and int(Net.srv.side) == 1, "back on the other side")
	Net.close()
	await _settle()
	check.call(not m.servers.get("live", {}).has(sid), "the last player leaves nothing behind")
	# --- a finished match is wiped by whoever comes next
	m.servers["live"] = {sid: {"x": {"end": {"l": 0, "t": 1.0}, "hp": {"s0": {"v": 0, "t": 1.0}}}, "s1": {"GANEDDDD": {"n": "x", "s": 0, "t": float(Net.server_now()), "j": 1.0}}}}
	r = await _acct_call(func(cb: Callable) -> void: Net.srv_join(def, 0, cb))
	await _settle()
	check.call(r[0] and not (m.servers.live[sid].get("x", {}) as Dictionary).has("end") and not m.servers.live[sid].has("s1"), "a finished match is cleared for the next one")
	Net.close()
	await _settle()
	# --- a full side lets nobody in
	var full := {}
	for i in int(def.rules.team):
		full["FULL%sAAA" % "ABCDEFGH"[i]] = {"n": "p", "s": i, "t": float(Net.server_now()), "j": 1.0}
	m.servers["live"] = {sid: {"s0": full}}
	r = await _acct_call(func(cb: Callable) -> void: Net.srv_join(def, 0, cb))
	check.call(not r[0] and Net.role == "", "a full side: %s" % r[1])
	r = await _acct_call(func(cb: Callable) -> void: Net.srv_unpublish(sid, cb))
	check.call(r[0] and not m.servers.get("list", {}).has(sid) and not m.servers.get("defs", {}).has(sid), "unpublished")
	print("UAD SRVUNIT: %s" % ("OK" if fails.is_empty() else "FAIL " + " | ".join(fails)))


## Depth precision: the near plane moves out as the camera climbs — 0.5 m at street level, up to
## 12 m high over the city. With 0.5 m everywhere the depth buffer could no longer tell the roads,
## their markings and the water from the ground a kilometre away, and the map flickered.
func _fit_near() -> void:
	var high: bool = game == null or not is_instance_valid(game) or String(game.view) == "top"
	cam.near = clampf(cam.global_position.y * 0.03, 0.5, 60.0) if high else 0.3


## --strikedemo: every site known, one damaged, one destroyed, strikes in flight, money to spend.
func _strike_demo() -> void:
	const Strikes = preload("res://scripts/game/strikes.gd")
	var ss: Array = Strikes.sites(map.city)
	var hidden := -1 # the last launch site stays unknown (the rear is known from the start)
	for i in ss.size():
		if String(ss[i].supply) == "":
			hidden = i
	for i in ss.size():
		var st := {"known": true, "st": "ok", "n": 0, "def": 0.0}
		if i == 1:
			st = {"known": true, "st": "damaged", "n": 2, "def": 0.08}
		elif i == 2:
			st = {"known": true, "st": "destroyed", "n": 3, "def": 0.16}
		elif i == hidden:
			st.known = false
		GS.sites[String(ss[i].id)] = st
	GS.strikes = [{"site": String(ss[0].id), "w": "lyutyi"}, {"site": String(ss[min(3, ss.size() - 1)].id), "w": "neptune"}]
	# a launcher caught in the act, with a HIMARS on its way to another one
	for s in ss:
		if bool(Strikes.KINDS[String(s.id)].get("hunt", false)) and bool(GS.sites[String(s.id)].known) and Strikes.hot.size() < 2:
			Strikes.hot[String(s.id)] = 27.0 if Strikes.hot.is_empty() else 12.0
	if Strikes.hot.size() == 2:
		Strikes.hunts = [{"site": String(Strikes.hot.keys()[1]), "w": "himars", "t": 5.0, "flight": 12.0, "p": 0.8}]
	GS.money = maxi(GS.money, 60000)
	GS.day = maxi(GS.day, 3)


## --striketest: the counter-strike rules, without a game running.
func _strike_selftest() -> void:
	const Strikes = preload("res://scripts/game/strikes.gd")
	var fails := []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	for cid in Cities.IDS:
		var c = Cities.get_def(cid)
		var ss: Array = Strikes.sites(c)
		check.call(ss.size() >= 4, "%s has sites" % cid)
		for w in Strikes.city_weapons(c):
			if w != "oreshnik":
				check.call(ss.any(func(s) -> bool: return (s.weapons as Array).has(w)), "%s: a site launches %s" % [cid, w])
		for s in ss:
			check.call(float(s.bearing) >= 0.0 and float(s.bearing) < 360.0 and float(s.km) > 0.0, "%s/%s placed" % [cid, s.id])
	var kyiv = Cities.get_def("kyiv")
	var odesa = Cities.get_def("odesa")
	GS.sites = {}
	GS.strikes = []
	GS.day = 3
	GS.money = 100000
	var drones := Strikes.site(kyiv, "drones")
	check.call(Strikes.blocker(drones, "lyutyi", true) != "", "unknown site cannot be struck")
	check.call(String(Strikes.seen(kyiv, "gerbera").get("id", "")) == "drones" and Strikes.seen(kyiv, "shahed").is_empty(), "a launch reveals its site once")
	check.call(Strikes.blocker(drones, "lyutyi", true) == "" and Strikes.blocker(drones, "lyutyi", false) != "", "strikes by day only")
	var strat := Strikes.site(kyiv, "strategic")
	Strikes.seen(kyiv, "cruise")
	check.call(Strikes.blocker(strat, "neptune", true) != "" and Strikes.blocker(strat, "lyutyi", true) == "", "reach: only the long-range drone gets to the bombers")
	var fleet := Strikes.site(odesa, "fleet")
	Strikes.seen(odesa, "kalibr")
	check.call(Strikes.blocker(fleet, "lyutyi", true) != "" and Strikes.blocker(fleet, "neptune", true) == "", "ships: Neptune yes, drone no")
	# the weapons of v1.3: reach, the day they come into service, the ballistic missile's pierce
	var kharkiv = Cities.get_def("kharkiv")
	Strikes.seen(kharkiv, "molniya")
	var mol := Strikes.site(kharkiv, "molniya")
	check.call(Strikes.blocker(mol, "himars", true) == "" and Strikes.blocker(drones, "himars", true) != "", "HIMARS: the border positions only")
	check.call(Strikes.blocker(drones, "atacms", true) != "" and Strikes.blocker(strat, "flamingo", true) != "", "ATACMS and Flamingo wait for their days")
	GS.day = 7
	check.call(Strikes.blocker(strat, "flamingo", true) == "" and Strikes.blocker(strat, "storm", true) != "", "the Flamingo reaches the bombers")
	var s400 := Strikes.site(kyiv, "s400")
	Strikes.seen(kyiv, "s400")
	check.call(Strikes.blocker(s400, "atacms", true) == "" and Strikes.chance(s400, "atacms") > Strikes.chance(s400, "storm") + 0.1, "ATACMS gets through a strong air defence")
	for w in Strikes.WEAPON_ORDER:
		check.call(Strikes.WEAPONS.has(w) and GS.t(String(Strikes.WEAPONS[w].desc)) != "", "%s described" % w)
	# a combined strike: the drones keep the site's air defence busy, the missiles get through more
	# often; the site is reinforced once a dusk, not once per drone
	var base_ch := Strikes.chance(s400, "storm")
	GS.strikes = [{"site": "s400", "w": "lyutyi"}, {"site": "s400", "w": "lyutyi"}]
	check.call(is_equal_approx(Strikes.escort("s400"), 0.2) and Strikes.chance(s400, "storm", Strikes.escort("s400")) > base_ch + 0.05, "drones cover the missiles")
	GS.strikes.append_array([{"site": "s400", "w": "storm"}, {"site": "s400", "w": "lyutyi"}, {"site": "s400", "w": "lyutyi"}, {"site": "s400", "w": "lyutyi"}])
	check.call(is_equal_approx(Strikes.escort("s400"), Strikes.ESCORT_MAX), "the cover has its limit")
	var cr := Strikes.resolve(kyiv, RandomNumberGenerator.new())
	var storm_cover := 0.0
	var lyutyi_cover := 0.0
	for r in cr:
		if String(r.w) == "storm":
			storm_cover = float(r.escort)
		else:
			lyutyi_cover = float(r.escort)
	check.call(cr.size() == 6 and String(cr[0].w) == "lyutyi" and is_equal_approx(storm_cover, 0.3) and is_equal_approx(lyutyi_cover, 0.3), "drones come first, everything covered")
	check.call(is_equal_approx(float(Strikes.state("s400").def), 0.08), "one reinforcement for the whole salvo")
	GS.sites.erase("s400")
	Strikes.seen(kyiv, "s400")
	# hunting the launchers: a launch puts them in the open, HIMARS goes at once even by night, a hit
	# calls off the rest of the site's launches tonight; airfields are never in the open
	GS.day = 3
	Strikes.reset_hunts()
	Strikes.seen(kharkiv, "s300")
	var s300 := Strikes.site(kharkiv, "s300")
	check.call(Strikes.blocker(s300, "himars", false) != "", "by night only a launcher in the open")
	check.call(not Strikes.heat(kharkiv, "s300").is_empty() and Strikes.hot.has("s300"), "a launch puts the launcher in the open")
	check.call(Strikes.heat(kharkiv, "s300").is_empty(), "…once per launch window")
	Strikes.seen(kharkiv, "kab")
	Strikes.heat(kharkiv, "kab")
	check.call(not Strikes.hot.has("kab"), "an airfield is never in the open")
	check.call(Strikes.blocker(s300, "himars", false) == "" and Strikes.blocker(s300, "storm", false) != "", "HIMARS by night at the launcher, Storm Shadow waits for the day")
	var mh := GS.money
	Strikes.send(s300, "himars")
	check.call(GS.money == mh - 7000 and Strikes.hunting("s300") == 1 and GS.strikes.is_empty(), "a hunt flies now, not at dusk")
	Strikes.hunts[0].p = 1.0
	var hr := Strikes.hunt_step(kharkiv, 5.0, RandomNumberGenerator.new())
	check.call(hr.is_empty() and Strikes.hunting("s300") == 1 and is_equal_approx(float(Strikes.hot.s300), Strikes.HOT_TIME - 5.0), "it takes its seconds")
	var before := {"s300": Strikes.output(kharkiv, "s300"), "kab": Strikes.output(kharkiv, "kab")}
	hr = Strikes.hunt_step(kharkiv, 8.0, RandomNumberGenerator.new())
	check.call(hr.size() == 1 and bool(hr[0].hit) and String(Strikes.state("s300").st) == "destroyed" and int(Strikes.state("s300").n) == 1, "the launcher is hit: out for tonight")
	var night := [{"t": 50.0, "type": "s300", "count": 2}, {"t": 60.0, "type": "kab", "count": 2}, {"t": 70.0, "warn": true}]
	check.call(Strikes.thin(night, kharkiv, before, RandomNumberGenerator.new()) == 2 and night.size() == 2 and String(night[0].type) == "kab", "its launches tonight are called off, the others fly")
	Strikes.hunt_step(kharkiv, Strikes.HOT_TIME, RandomNumberGenerator.new())
	check.call(Strikes.hot.is_empty(), "the launcher drives off")
	Strikes.night_passed(kharkiv)
	check.call(String(Strikes.state("s300").st) == "ok", "back the next night")
	Strikes.reset_hunts()
	# the enemy's rear: known from the start, launching nothing, thinning what it feeds
	var fac := Strikes.site(kyiv, "factory")
	check.call(not fac.is_empty() and bool(Strikes.state("factory").known) and (fac.weapons as Array).is_empty(), "the factory is on the map from the start")
	check.call(Strikes.blocker(fac, "lyutyi", true) != "", "the Lyutyi does not reach Alabuga")
	GS.day = 7
	check.call(Strikes.blocker(fac, "flamingo", true) == "", "the Flamingo does")
	GS.sites["factory"] = {"known": true, "st": "destroyed", "n": 2, "def": 0.0}
	check.call(is_equal_approx(Strikes.output(kyiv, "shahed"), 0.6) and is_equal_approx(Strikes.output(kyiv, "cruise"), 1.0) and is_equal_approx(Strikes.output(kyiv, "scout"), 1.0), "no factory: fewer Shaheds, the missiles fly on")
	GS.sites["refinery"] = {"known": true, "st": "damaged", "n": 2, "def": 0.0}
	GS.sites["arsenal"] = {"known": true, "st": "destroyed", "n": 2, "def": 0.0}
	check.call(is_equal_approx(Strikes.output(kyiv, "cruise"), 0.8) and is_equal_approx(Strikes.output(kyiv, "ballistic"), 0.6) and is_equal_approx(Strikes.output(kyiv, "kalibr"), 1.0), "no fuel: fewer bombers; no arsenal: fewer Iskanders; the fleet sails on")
	GS.sites["rail"] = {"known": true, "st": "destroyed", "n": 1, "def": 0.0}
	Strikes.night_passed(kyiv)
	check.call(int(Strikes.state("factory").n) == 2 and String(Strikes.state("rail").st) == "ok", "the rail hub out: nothing is rebuilt but the hub")
	Strikes.night_passed(kyiv)
	check.call(int(Strikes.state("factory").n) == 1, "…then the repairs go on")
	for id in ["factory", "refinery", "arsenal", "rail"]:
		GS.sites.erase(id)
		check.call(GS.t(String(Strikes.KINDS[id].what)) != "" and Strikes.status_text(id) != "", "%s described" % id)
	GS.day = 3
	var m0 := GS.money
	Strikes.launch(drones, "storm")
	check.call(GS.money == m0 - 21000 and Strikes.in_flight("drones") == 1, "a strike is paid and in flight")
	var rng := RandomNumberGenerator.new()
	var hit := false
	for seed in 50:
		rng.seed = seed
		if rng.randf() < Strikes.chance(drones, "storm"):
			rng.seed = seed
			hit = true
			break
	var res := Strikes.resolve(kyiv, rng)
	check.call(hit and res.size() == 1 and bool(res[0].hit) and GS.strikes.is_empty(), "the strike lands at dusk")
	check.call(absf(Strikes.output(kyiv, "shahed") - 0.3) < 0.001 and Strikes.output(kyiv, "cruise") == 1.0, "a destroyed pad leaves only the spare pads, the missiles fly on")
	GS.sites["strategic"] = {"known": true, "st": "destroyed", "n": 1, "def": 0.0}
	check.call(Strikes.output(kyiv, "cruise") == 0.0, "a destroyed airfield is silent")
	GS.sites.erase("strategic")
	check.call(float(Strikes.state("drones").def) > 0.0, "the enemy reinforces a struck site")
	for i in 3:
		Strikes.night_passed(kyiv)
	check.call(Strikes.output(kyiv, "shahed") == 1.0 and String(Strikes.state("drones").st) == "ok", "repaired after its nights")
	GS.sites["iskander"] = {"known": true, "st": "damaged", "n": 2, "def": 0.0}
	check.call(absf(Strikes.output(kyiv, "ballistic") - 0.5) < 0.001, "a damaged site launches half")
	# the world keeps it all
	var keep_id := GS.world_id
	GS.world_id = "striketest_tmp"
	GS.strikes = [{"site": "fleet", "w": "neptune"}]
	GS.save_world()
	GS.sites = {}
	GS.strikes = []
	var loaded := GS.load_world("striketest_tmp")
	GS.delete_world("striketest_tmp")
	GS.world_id = keep_id
	check.call(loaded and String(Strikes.state("iskander").st) == "damaged" and GS.strikes.size() == 1, "saved with the world")
	print("UAD STRIKETEST: %s" % ("OK" if fails.is_empty() else "FAIL " + ", ".join(fails)))


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
		p.base = GS.base_pos + Vector3(1100, 0, 450)
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
		var base_ok: bool = not node.is_empty() and (node.base as Node3D).visible and (node.base as Node3D).position.distance_to(Net.players[_MP_FAKE].base) < 60.0
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
## --shotlist=file.json: [{file, pos: [x, y, z], look: [x, y, z], fov, night, fog, hold, quality}, …]
## taken one after another in the same run, then the game quits. "base": true counts both points
## from the battery, "ll": true gives them as [latitude, longitude, height]. The file's extension
## picks the format (.png, .jpg, .webp); --shot takes --shot-quality.
var _shots: Array = []
var _shot_i := 0
var _shot_t := -1.0
var _shot_settle := 0


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
	print("UAD OFFSCREEN window %s on screens %s visible=%s renderer=%s quality=%d" % [wr, screens, visible_somewhere, RenderingServer.get_current_rendering_method(), int(GS.settings.quality)])
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
	_shot_vp.msaa_3d = Viewport.MSAA_8X if int(GS.settings.quality) >= 4 else Viewport.MSAA_4X
	_shot_vp.positional_shadow_atlas_size = 8192 if int(GS.settings.quality) >= 4 else 4096
	add_child(_shot_vp)
	_shot_cam = Camera3D.new()
	_shot_vp.add_child(_shot_cam)
	_shot_cam.current = true
	_post_shot = _post_rect()
	_post_shot.size = Vector2(size)
	_shot_vp.add_child(_post_shot)
	_update_post()
	if _args.has("photo"):
		set_post_amount(1.0)
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


## By the file's extension: .jpg and .webp at `quality`, anything else as a PNG.
func _save_picture(img: Image, file: String, quality: float) -> void:
	if file.ends_with(".jpg"):
		img.save_jpg(file, quality)
	elif file.ends_with(".webp"):
		img.save_webp(file, true, quality)
	else:
		img.save_png(file)


## One entry of the shot list per call: aim the camera, let the frame settle, save it.
func _shot_list_step() -> void:
	if _shots.is_empty() or _shot_i >= _shots.size() or _clock < float(_args.get("shot-start", "1.5")):
		return
	var s: Dictionary = _shots[_shot_i]
	if game != null and is_instance_valid(game):
		game.rig.set_process(false) # the camera belongs to the shot list now
	var pos: Array = s.get("pos", [900, 300, 900])
	var look: Array = s.get("look", [0, 60, 0])
	# "base": true — both points are offsets from the battery's position
	var origin := GS.base_pos if bool(s.get("base", false)) else Vector3.ZERO
	if bool(s.get("ll", false)):
		# "ll": true — both points are [latitude, longitude, height] on the city's own map
		cam.global_position = map.city.ll3(float(pos[0]), float(pos[1]), float(pos[2]))
		cam.look_at(map.city.ll3(float(look[0]), float(look[1]), float(look[2])), Vector3.UP)
	else:
		cam.global_position = origin + Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		cam.look_at(origin + Vector3(float(look[0]), float(look[1]), float(look[2])), Vector3.UP)
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
	# the streets around the camera are still being made
	if map.stream.busy() and _clock - _shot_t < 25.0:
		return
	if _shot_settle < 3:
		_shot_settle += 1
		return
	_shot_settle = 0
	var file := String(s.get("file", "shot_%d.png" % _shot_i))
	_save_picture(_frame_image(), file, float(s.get("quality", 0.9)))
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
			var spot: Vector3 = map.nearest_base_spot(Vector3(float(hb[0]) + 700.0, 0, float(hb[1])), GS.Loc.FIELD)
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
			err = "avg %.1f m · max %.1f m (%d updates)" % [game.net_err_sum / game.net_err_n, game.net_err_max, game.net_err_n]
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
	if game and game.pvp != null:
		var pv = game.pvp
		print("UAD PVP: side=%d over='%s' hp=%s incoming=%d outgoing=%s stats=%s bot(level=%d money=%d hp=%.1f)" % [pv.side, pv.over, str(pv.hp), pv.incoming.size(),
			str(pv.outgoing.values().map(func(o) -> String: return "%s×%d:%s h%d k%d" % [o.w, int(o.c), o.st, int(o.h), int(o.k)])), str(pv.stats),
			pv.machine.level if pv.machine != null else -1, int(pv.machine.money) if pv.machine != null else -1, pv.machine.hp if pv.machine != null else -1.0])
	if game:
		print("UAD LAUNCHED: ", game.launched)
		print("UAD ALARM: on=%s for=%.1f s sheltered=%s phase=%d" % [game.alarm, game.alarm_t, game.sheltered(), game.director.phase])
		if game.fighter != null and bool(GS.unlocked.get("f16", false)):
			print("UAD F16: state=%s kills=%d aim9_left=%d aim120_left=%d money=%d" % [game.fighter.state, int(GS.stats.kills), int(GS.ammo.get("aim9", 0)) + int(game.fighter.loaded.aim9), int(GS.ammo.get("aim120", 0)) + int(game.fighter.loaded.aim120), GS.money])
			if _args.has("f16input"):
				print("UAD F16IN: mouse_mode=%d seen_kab=%s rmb_presses=%d launched=%d at_kab=%d gun_s=%.1f f16_kills=%d crashes=%d" % [Input.mouse_mode, _in.seen_kab, _in.presses, _in.launched, _in.kab, _in.gun, int(GS.stats.get("f16_kills", 0)), int(GS.stats.get("f16_crashes", 0))])
		if game.mfg != null and game.mfg.unit != null:
			print("UAD MFG: hp=%d wrecked=%s pos=%s kills=%d" % [int(game.mfg.hp), game.mfg.wrecked, game.mfg.pos, int(GS.stats.kills)])
	if game and game.view == "walk":
		print("UAD WALK: pos=%s on_floor=%s" % [str(game.walker.pos), game.walker.on_floor])
	if game and game.rl != null:
		var rl = game.rl
		print("UAD RL: view=%s seat=%s scope=%s track=%s blips=%d locks=%d shots=%d kills=%d misses=%d radio=%d near=%s" % [game.view, game.selected_weapon, rl.scope_on(), rl.track != null, rl.blips.size(), int(_rl.locks), int(_rl.shots), int(GS.stats.kills), int(GS.stats.get("misses", 0)), rl.radio_log.size(), str(rl.near.get("id", "-"))])
		print("UAD RL SUPPLY: on the road=%d owned=%s ammo=%s camo=%s money=%d" % [rl.orders.size(), str(game.owned_weapons()), str(GS.ammo), GS.camo, GS.money])
		for r in rl.radio_log:
			print("   radio: ", r.text)
		if rl.training != null:
			print("UAD TRAIN: lesson %d of %d finished=%s" % [rl.training.step + 1, rl.training.total(), rl.training.finished])
	if game:
		print("UAD RIG: target=%s dist=%.1f pitch=%.2f tdist=%.1f tpitch=%.2f proc=%s" % [str(game.rig.target), game.rig.dist, game.rig.pitch, game.rig._t_dist, game.rig._t_pitch, game.rig.is_processing()])


## Test hooks of a MaxRealism session: --rl-sit=<system|post> takes a seat, --rl-bot works the
## operator's console (the cursor on the nearest echo, lock, two rounds), --train-bot goes through
## the lessons of the training range (--screen=training).
var _rl := {"sat": false, "fired": {}, "locks": 0, "shots": 0, "t": 0.0, "step": -1}


func _realism_hooks(delta: float) -> void:
	var rl = game.rl
	if _args.has("rl-sit") and not bool(_rl.sat) and _clock >= 2.0:
		_rl.sat = true
		var where := String(_args["rl-sit"])
		if where == "post":
			rl.enter_post()
		elif where == "truck":
			game.set_view("mfg")
		else:
			rl.sit(where)
		print("UAD RL sit %s -> view=%s scope=%s scale=%.0f" % [where, game.view, rl.scope_on(), rl.scope_scale])
	if _args.has("rl-order") and _clock >= 3.0:
		# --rl-order=osa,osa:4,camo: a system, four rounds for it and the net are put on the road
		for item in String(_args["rl-order"]).split(","):
			var kv := item.split(":")
			var ok: bool = rl.order("camo", "camo", 1) if kv[0] == "camo" else (rl.order("ammo", kv[0], int(kv[1])) if kv.size() > 1 else rl.order("weapon", kv[0], 1))
			print("UAD RL order %s -> %s money=%d on the road=%d" % [item, ok, GS.money, rl.orders.size()])
		_args.erase("rl-order")
	if _args.has("rl-bot") and rl.scope_on():
		_scope_bot(delta, 2)
	if _args.has("rl-touchtest"):
		_touch_selftest()
	if _args.has("train-bot") and rl.training != null:
		_train_bot(delta)


## The operator: the gate on the nearest echo the seat's system can reach, lock, `rounds` launches,
## and again if the target is still there a while later.
func _scope_bot(delta: float, rounds: int) -> void:
	var rl = game.rl
	_rl.t = float(_rl.t) - delta
	if rl.track == null:
		var w = rl.weapon()
		var best = null
		var bd := INF
		for e in game.enemies:
			if e.dead or not rl.blips.has(e.get_instance_id()):
				continue
			if w != null and (not w.can_engage(e) or not w.in_range(e)):
				continue
			var d: float = e.position.distance_to(GS.base_pos)
			if d < bd:
				bd = d
				best = e
		if best == null:
			return
		var bp: Vector2 = rl.blips[best.get_instance_id()].pos
		rl.scope_az = rl.az_of(bp)
		rl.scope_rng = bp.length()
		rl.lock()
		if rl.track != null:
			_rl.locks = int(_rl.locks) + 1
		return
	if game.view != "base" or rounds <= 0:
		return
	var id: int = rl.track.get_instance_id()
	var n := int(_rl.fired.get(id, 0))
	if n < rounds:
		var before: int = rl.salvo
		rl.fire()
		if rl.salvo > before:
			_rl.fired[id] = n + 1
			_rl.shots = int(_rl.shots) + 1
			_rl.t = 8.0
	elif float(_rl.t) <= 0.0:
		_rl.fired[id] = 0 # they all passed by: another pair


## Stands the walker next to a station, on the inner side.
func _tb_goto(p: Vector3, hull: float) -> void:
	var out := p - GS.base_pos
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else Vector3(0, 0, 1)
	game.walker.pos = p - out * (hull + 0.8)


func _train_bot(delta: float) -> void:
	var rl = game.rl
	var tr = rl.training
	if tr.finished:
		return
	if tr.step != int(_rl.step):
		_rl.step = tr.step
		print("UAD TRAIN lesson %d at t=%.1f view=%s enemies=%d" % [tr.step + 1, _clock, game.view, game.enemies.size()])
	if _args.has("train-stop") and tr.step >= int(_args["train-stop"]):
		game.walker.test_forward = false
		return # --train-stop=N: the bot leaves lesson N (counted from 0) alone, for a look at it
	var near_id := String(rl.near.get("id", ""))
	match int(tr.step):
		0:
			game.walker.test_forward = true
		1:
			game.walker.test_forward = false
			_tb_goto(game.weapons["mg"].global_position, rl._hull("mg"))
		2:
			if near_id == "mg":
				rl.use()
		3:
			if game.view == "base" and not game.enemies.is_empty():
				_aimbot()
		4:
			if game.view == "base" and String(game.selected_weapon) != "igla":
				rl.use()
			elif game.view == "walk":
				_tb_goto(game.weapons["igla"].global_position, rl._hull("igla"))
				if near_id == "igla":
					rl.use()
			elif not game.enemies.is_empty():
				_aimbot()
		5:
			if game.view == "base":
				rl.use()
			elif game.view == "walk":
				game.walker.pos = rl.post_pos() + Vector3(0, 0, -1.0)
				if near_id == "post":
					rl.use()
		6:
			_scope_bot(delta, 0)
		7:
			if game.view == "post":
				rl.use()
			elif game.view == "walk":
				_tb_goto(game.weapons["s300"].global_position, rl._hull("s300"))
				if near_id == "s300":
					rl.use()
		8, 9:
			_scope_bot(delta, 2)


## --touch --rl-touchtest (MaxRealism): fingers fed through the input system — a thumb on the
## stick, a second finger on the seat button, then aiming with one finger while another holds
## the fire button. Every step prints what the game made of it.
var _tt := {"stage": 0, "t": 0.0, "p0": Vector3.ZERO, "yaw0": 0.0}


func _finger(index: int, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = get_viewport().get_final_transform() * at
	ev.pressed = down
	Input.parse_input_event(ev)


func _slide(index: int, at: Vector2, by: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	var xf := get_viewport().get_final_transform()
	ev.position = xf * (at + by)
	ev.relative = xf.basis_xform(by)
	Input.parse_input_event(ev)


func _touch_button(id: String) -> Vector2:
	for b in game.rl.hud._btns:
		if String(b.id) == id:
			if b.has("rect"):
				var rc: Rect2 = b.rect
				return rc.get_center()
			return b.c
	return Vector2(-1, -1)


func _touch_selftest() -> void:
	var rl = game.rl
	var sz := get_viewport().get_visible_rect().size
	var stick := Vector2(160, sz.y - 180)
	if _clock - float(_tt.t) < 0.6 or _clock < 2.0:
		return
	_tt.t = _clock
	match int(_tt.stage):
		0:
			_tt.p0 = game.walker.pos
			_finger(0, stick, true)
			_slide(0, stick, Vector2(0, -60))
		1:
			print("UAD TOUCH stick: walked %.1f m with the thumb down" % game.walker.pos.distance_to(_tt.p0))
			_tb_goto(game.weapons["mg"].global_position, rl._hull("mg"))
		2:
			var b := _touch_button("use")
			print("UAD TOUCH seat button on screen=%s near=%s buttons=%d" % [b.x >= 0.0, str(rl.near.get("id", "-")), rl.hud._btns.size()])
			_finger(1, b, true)
			_finger(1, b, false)
		3:
			print("UAD TOUCH seat taken with a second finger: view=%s (thumb still on the stick)" % game.view)
			_finger(0, stick + Vector2(0, -60), false)
			_tt.yaw0 = game.base_view.yaw
			_finger(0, sz * 0.5, true)
			_slide(0, sz * 0.5, Vector2(80, 0))
		4:
			var f := _touch_button("fire")
			_finger(1, f, true)
		5:
			print("UAD TOUCH aim %.2f rad with one finger, fire held by another: trigger=%s" % [absf(game.base_view.yaw - float(_tt.yaw0)), game.base_view.trigger])
			_finger(1, _touch_button("fire"), false)
			_finger(0, sz * 0.5 + Vector2(80, 0), false)
		6:
			print("UAD TOUCH fire released: trigger=%s" % game.base_view.trigger)
			var u := _touch_button("use")
			_finger(0, u, true)
			_finger(0, u, false)
		7:
			print("UAD TOUCH up again: view=%s" % game.view)
	_tt.stage = int(_tt.stage) + 1


## --touch --twisttest (the usual game, the map view): two fingers turn about each other, slide
## down together, then pinch. Prints how the camera answered and which way the picture turned.
func _twist_selftest() -> void:
	var rig = game.rig
	var a := Vector2(480, 330)
	var b := Vector2(760, 330)
	var east: Vector3 = rig.target + Vector3(400, 0, 0)
	if _clock - float(_tt.t) < 0.9:
		return
	_tt.t = _clock
	var on_screen := (cam.unproject_position(east) - cam.unproject_position(rig.target)).angle()
	match int(_tt.stage):
		0:
			_tt.yaw0 = on_screen
			_tt.p0 = Vector3(rig._t_yaw, rig._t_pitch, rig._t_dist)
			_finger(0, a, true)
			_finger(1, b, true)
			for i in 8:
				var from := a + (b - a).rotated(0.05 * i)
				var to := a + (b - a).rotated(0.05 * (i + 1))
				_slide(1, from, to - from)
			b = a + (b - a).rotated(0.4)
			_finger(1, b, false)
			_finger(0, a, false)
		1:
			print("UAD TWIST fingers turned 0.40 rad clockwise: camera yaw %+.2f, the picture turned %+.2f rad" % [rig._t_yaw - _tt.p0.x, angle_difference(float(_tt.yaw0), on_screen)])
			_tt.p0 = Vector3(rig._t_yaw, rig._t_pitch, rig._t_dist)
			_finger(0, a, true)
			_finger(1, b, true)
			for i in 6:
				_slide(0, a + Vector2(0, 10 * i), Vector2(0, 10))
				_slide(1, b + Vector2(0, 10 * i), Vector2(0, 10))
			_finger(0, a + Vector2(0, 60), false)
			_finger(1, b + Vector2(0, 60), false)
		2:
			print("UAD TWIST both fingers slid 60 px down: pitch %+.2f, yaw %+.2f, distance x%.2f" % [rig._t_pitch - _tt.p0.y, rig._t_yaw - _tt.p0.x, rig._t_dist / _tt.p0.z])
			_tt.p0 = Vector3(rig._t_yaw, rig._t_pitch, rig._t_dist)
			_finger(0, a, true)
			_finger(1, b, true)
			for i in 6:
				_slide(1, b + Vector2(20 * i, 0), Vector2(20, 0))
			_finger(0, a, false)
			_finger(1, b + Vector2(120, 0), false)
		3:
			print("UAD TWIST fingers spread apart: distance x%.2f, pitch %+.2f, yaw %+.2f" % [rig._t_dist / _tt.p0.z, rig._t_pitch - _tt.p0.y, rig._t_yaw - _tt.p0.x])
			game.hud.turn_box.get_child(1).button_down.emit()
		4:
			print("UAD TWIST rotate button held 0.9 s: yaw %+.2f, shown=%s" % [rig._t_yaw - _tt.p0.x, game.hud.turn_box.visible])
			game.hud.turn_box.get_child(1).button_up.emit()
	_tt.stage = int(_tt.stage) + 1
