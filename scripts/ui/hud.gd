extends CanvasLayer
## In-game HUD: budget, day/night status, radar, flashing launch alerts, event log,
## AA weapon panel, debris-fall prediction and modal overlays (pause, shop, reports).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Radar = preload("res://scripts/ui/radar.gd")
const Shop = preload("res://scripts/ui/shop.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const Reticle = preload("res://scripts/ui/reticle.gd")
const FpvOsd = preload("res://scripts/ui/fpv_osd.gd")
const VideoUi = preload("res://scripts/ui/video_ui.gd")
const VideoExport = preload("res://scripts/game/video_export.gd")
const Shaders = preload("res://scripts/world/shaders.gd")
const PlayerList = preload("res://scripts/ui/player_list.gd")
const RemotePlayers = preload("res://scripts/game/remote_players.gd")

var game
var reticle
var fpv_osd
var nv_rect: ColorRect
var flash_rect: ColorRect
var fire_btn: Button
var view_btn: Button
var _weapons_panel: Control
var _weapons_row: HBoxContainer
var _tabs_row: HBoxContainer
## Which systems the panel was last built for, so it is only rebuilt after a purchase.
var _owned_sig := ""
var _walk_ui: Control
var _fpv_ui: Control
var zoom_box: VBoxContainer

var root: Control
var money_lbl: Label
var phase_lbl: Label
var loc_lbl: Label
var city_bar: ProgressBar
var base_bar: ProgressBar
var detect_lbl: Label
var fire_lbl: Label
var alert_lbl: Label
var log_box: VBoxContainer
var target_lbl: Label
var predict_lbl: Label
var target_panel: PanelContainer
var auto_btn: Button
var weapon_btns := {}
var group_btns := {}

var _alerts: Array = []
var _alert_t := 0.0
var _t := 0.0
var _overlay: Control
var _victory_seen := false
## Highlight-reel playback: the overlay and what to reopen when the video ends.
var _video: Control
var _video_after := Callable()
## Running while the cut on screen is being written to a file.
var _recorder
## Where to go back to once the saved-video notice is closed (usually the city feed).
var _record_back := Callable()
var _style_sel: StyleBoxFlat
var _style_norm: StyleBoxFlat
## Multiplayer: the player list (Tab), join requests waiting for the host's answer
## (code -> {panel, bar, left}), the "watching a friend" banner and the players button.
var _players: Control
var _requests_box: VBoxContainer
var _req_cards := {}
var _watch_lbl: Label
var _players_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	root = UiKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_style_sel = UiKit.sbox(Color(0.06, 0.3, 0.18, 0.95), Color(0.4, 1.0, 0.7), 3, 6, 6)
	_style_norm = UiKit.sbox(Color(0.02, 0.1, 0.07, 0.88), UiKit.NEON_DIM, 2, 6, 6)
	# night-vision filter sits under every other HUD element (it filters only the 3D view)
	nv_rect = UiKit.full_rect(ColorRect.new()) as ColorRect
	nv_rect.material = Shaders.canvas_material(Shaders.NIGHT_VISION)
	nv_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv_rect.visible = false
	root.add_child(nv_rect)
	reticle = Reticle.new()
	reticle.game = game
	reticle.bv = game.base_view
	root.add_child(reticle)
	fpv_osd = FpvOsd.new()
	fpv_osd.game = game
	fpv_osd.fv = game.fpv_view
	game.fpv_view.osd = fpv_osd
	root.add_child(fpv_osd)
	_build_status()
	_build_radar()
	_build_alert()
	_build_weapons()
	_build_target_info()
	_build_touch_buttons()
	flash_rect = UiKit.full_rect(ColorRect.new()) as ColorRect
	flash_rect.color = Color(1.0, 0.92, 0.8, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_build_walk_ui()
	_build_fpv_ui()
	_build_multiplayer()
	GS.money_changed.connect(_on_money)
	GS.state_changed.connect(refresh)
	on_view_changed()
	refresh()


## White flash for nearby explosions in the gunner view.
func flash(alpha: float) -> void:
	flash_rect.color.a = maxf(flash_rect.color.a, alpha)
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _build_walk_ui() -> void:
	_walk_ui = UiKit.full_rect(Control.new())
	_walk_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_walk_ui)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.7)
	dot.size = Vector2(4, 4)
	dot.anchor_left = 0.5
	dot.anchor_top = 0.5
	dot.anchor_right = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -2
	dot.offset_top = -2
	dot.offset_right = 2
	dot.offset_bottom = 2
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walk_ui.add_child(dot)
	var hint := UiKit.label(GS.t("ПРОГУЛКА · WASD — идти · Shift — бегом · Пробел — прыжок · мышь — осмотреться · %s — назад к ПВО · %s — пауза") % [GS.key_label("walk"), GS.key_label("pause")], 14, Color(0.75, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	if DisplayServer.is_touchscreen_available():
		hint.text = GS.t("ПРОГУЛКА · левая половина экрана — идти · правая — осмотреться")
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 5)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.anchor_right = 1.0
	hint.offset_top = -44
	hint.offset_bottom = -16
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walk_ui.add_child(hint)
	var back := Button.new()
	back.text = GS.t("⟵ К ПВО [%s]") % GS.key_label("walk")
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 16)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_left = -90
	back.offset_right = 90
	back.offset_top = 70
	back.offset_bottom = 108
	back.pressed.connect(func() -> void: game.toggle_walk())
	_walk_ui.add_child(back)


## Console bar of the FPV view: the same orders as the keyboard shortcuts, for touch screens
## (and for a mouse with Alt held, which frees the cursor).
func _build_fpv_ui() -> void:
	var p := UiKit.panel()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -52
	p.visible = false
	root.add_child(p)
	var h := UiKit.hbox(8)
	p.add_child(h)
	_small_btn(h, GS.t("⟵ ВЫЙТИ [%s]") % GS.key_label("fpv"), func() -> void: game.leave_fpv()).custom_minimum_size = Vector2(150, 38)
	_small_btn(h, GS.t("СЛЕД. ДРОН [%s]") % GS.key_label("fpv_next"), _next_drone).custom_minimum_size = Vector2(190, 38)
	_small_btn(h, GS.t("НА БАЗУ [%s]") % GS.key_label("fpv_home"), _drone_home).custom_minimum_size = Vector2(150, 38)
	_small_btn(h, GS.t("ЗАПУСК ЕЩЁ"), _launch_more).custom_minimum_size = Vector2(150, 38)
	_fpv_ui = p


func _next_drone() -> void:
	if not game.fpv_view.next_drone():
		alert(GS.t("В воздухе больше нет дронов"), Color(1.0, 0.7, 0.3))


func _drone_home() -> void:
	var d = game.fpv_view.drone
	if d != null and is_instance_valid(d):
		d.order_home()
	game.leave_fpv()


## Another drone off the rail, straight onto the console.
func _launch_more() -> void:
	var d = game.launch_drone()
	if d != null:
		game.fpv_view.adopt(d)


func on_view_changed() -> void:
	var base: bool = game.view == "base"
	var walk: bool = game.view == "walk"
	var fpv: bool = game.view == "fpv"
	var watch: bool = game.view == "watch"
	if view_btn:
		var vname := GS.t("СВЕРХУ")
		if base:
			vname = GS.t("БАЗА")
		elif fpv:
			vname = GS.t("FPV")
		elif watch:
			vname = GS.t("ДРУГ")
		view_btn.text = GS.t("ВИД [%s]: %s") % [GS.key_label("view"), vname]
	if fire_btn:
		fire_btn.visible = (base or fpv) and DisplayServer.is_touchscreen_available()
		fire_btn.text = GS.t("РАЗГОН") if fpv else GS.t("ОГОНЬ")
	if target_panel:
		target_panel.visible = false
	if _weapons_panel:
		_weapons_panel.visible = not walk and not fpv and not watch
	if _watch_lbl:
		_watch_lbl.visible = watch
	if _walk_ui:
		_walk_ui.visible = walk
	if _fpv_ui:
		_fpv_ui.visible = fpv
	if zoom_box:
		zoom_box.visible = not walk
	refresh()


# --- Construction -------------------------------------------------------------------
func _build_status() -> void:
	var p := UiKit.panel(Vector2(290, 0))
	p.position = Vector2(12, 12)
	root.add_child(p)
	var v := UiKit.vbox(4)
	p.add_child(v)
	v.add_child(UiKit.label(GS.t("БЮДЖЕТ"), 13, Color(0.5, 0.8, 0.65)))
	money_lbl = UiKit.glow_label("$0", 34, UiKit.NEON)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(money_lbl)
	phase_lbl = UiKit.label("", 18, UiKit.AMBER)
	v.add_child(phase_lbl)
	loc_lbl = UiKit.label("", 13, Color(0.6, 0.85, 0.75))
	v.add_child(loc_lbl)
	city_bar = _bar(v, GS.t("ГОРОД"))
	base_bar = _bar(v, GS.t("БАЗА"))
	detect_lbl = UiKit.label("", 14)
	v.add_child(detect_lbl)
	fire_lbl = UiKit.label("", 14, Color(1.0, 0.6, 0.3))
	fire_lbl.visible = false
	v.add_child(fire_lbl)


func _bar(parent: Control, title: String) -> ProgressBar:
	var h := UiKit.hbox(8)
	parent.add_child(h)
	var l := UiKit.label(title, 13, Color(0.6, 0.85, 0.75))
	l.custom_minimum_size = Vector2(52, 0)
	h.add_child(l)
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.custom_minimum_size = Vector2(200, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	h.add_child(b)
	return b


func _build_radar() -> void:
	var radar := Radar.new()
	radar.game = game
	radar.anchor_left = 1.0
	radar.anchor_right = 1.0
	radar.offset_left = -266
	radar.offset_right = -12
	radar.offset_top = 12
	radar.offset_bottom = 266
	root.add_child(radar)
	log_box = UiKit.vbox(2)
	log_box.anchor_left = 1.0
	log_box.anchor_right = 1.0
	log_box.offset_left = -380
	log_box.offset_right = -12
	log_box.offset_top = 276
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)


func _build_alert() -> void:
	alert_lbl = UiKit.glow_label("", 30, UiKit.RED)
	alert_lbl.anchor_left = 0.5
	alert_lbl.anchor_right = 0.5
	alert_lbl.offset_left = -330
	alert_lbl.offset_right = 330
	alert_lbl.offset_top = 22
	alert_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alert_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(alert_lbl)


## Battery panel: four tabs — hand-aimed, automatic, SAM launchers and the Patriot — and the
## systems of the open tab under them. Only what is bought gets a button; the rest is in the shop.
func _build_weapons() -> void:
	var p := UiKit.panel()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -10
	root.add_child(p)
	var h := UiKit.hbox(8)
	p.add_child(h)
	var left := UiKit.vbox(5)
	h.add_child(left)
	_tabs_row = UiKit.hbox(5)
	left.add_child(_tabs_row)
	for spec in GS.WEAPON_GROUPS:
		var g := String(spec[0])
		var b := Button.new()
		b.custom_minimum_size = Vector2(122, 30)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_group_btn.bind(g))
		_tabs_row.add_child(b)
		group_btns[g] = b
	_weapons_row = UiKit.hbox(6)
	left.add_child(_weapons_row)
	var side := UiKit.vbox(6)
	h.add_child(side)
	auto_btn = _small_btn(side, GS.t("АВТО [%s]") % GS.key_label("auto"), func() -> void: game.toggle_auto())
	_small_btn(side, GS.t("МАГАЗИН [%s]") % GS.key_label("shop"), open_shop)
	var side2 := UiKit.vbox(6)
	h.add_child(side2)
	_small_btn(side2, GS.t("❚❚ ПАУЗА"), toggle_pause)
	_small_btn(side2, GS.t("⌂ К БАЗЕ [%s]") % GS.key_label("home"), func() -> void: game.rig.focus(GS.base_pos))
	_players_btn = _small_btn(side2, GS.t("👥 ИГРОКИ [%s]") % GS.key_label("players"), toggle_players)
	_players_btn.visible = Net.is_online()
	var side3 := UiKit.vbox(6)
	h.add_child(side3)
	view_btn = _small_btn(side3, GS.t("ВИД [%s]") % GS.key_label("view"), func() -> void: game.toggle_view())
	view_btn.custom_minimum_size = Vector2(132, 24)
	_small_btn(side3, GS.t("🚶 ГУЛЯТЬ [%s]") % GS.key_label("walk"), func() -> void: game.toggle_walk()).custom_minimum_size = Vector2(132, 24)
	_small_btn(side3, GS.t("🛩 ДРОН FPV [%s]") % GS.key_label("fpv"), func() -> void: game.enter_fpv()).custom_minimum_size = Vector2(132, 24)
	_weapons_panel = p
	_rebuild_weapon_buttons()


func _on_group_btn(g: String) -> void:
	SFX.play("click", -8.0)
	if game.owned_in_group(g).is_empty():
		alert(GS.t("В этой группе пока ничего не куплено — магазин [B]"), Color(1.0, 0.7, 0.3))
		open_shop()
		return
	game.select_group(g)


## Rebuilt when the open tab changes or something new is bought, not every frame.
func _rebuild_weapon_buttons() -> void:
	var own: Array = game.owned_in_group(game.weapon_group)
	_owned_sig = String(game.weapon_group) + ":" + ",".join(PackedStringArray(own))
	for c in _weapons_row.get_children():
		_weapons_row.remove_child(c)
		c.queue_free()
	weapon_btns.clear()
	for i in own.size():
		var id: String = String(own[i])
		var b := Button.new()
		b.custom_minimum_size = Vector2(128, 74)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_weapon_btn.bind(id))
		_weapons_row.add_child(b)
		weapon_btns[id] = b
	if own.is_empty():
		var hint := UiKit.label(GS.t("Ничего не куплено — откройте магазин [B]"), 14, Color(0.6, 0.85, 0.75))
		hint.custom_minimum_size = Vector2(300, 74)
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_weapons_row.add_child(hint)


func _small_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(116, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: SFX.play("click", -8.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_target_info() -> void:
	target_panel = UiKit.panel(Vector2(320, 0))
	target_panel.anchor_top = 1.0
	target_panel.anchor_bottom = 1.0
	target_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	target_panel.offset_left = 12
	target_panel.offset_bottom = -112
	target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(target_panel)
	var v := UiKit.vbox(2)
	target_panel.add_child(v)
	target_lbl = UiKit.label("", 15)
	v.add_child(target_lbl)
	predict_lbl = UiKit.label("", 17)
	v.add_child(predict_lbl)
	var hint := UiKit.label(GS.t("ЛКМ по цели — огонь выбранной ПВО · ЛКМ по небу — отбой\nПКМ — поворот · колесо — зум · 1-9 или %s/%s — ПВО · %s — пульт FPV") % [GS.key_label("weapon_prev"), GS.key_label("weapon_next"), GS.key_label("fpv")], 11, Color(0.5, 0.7, 0.6))
	v.add_child(hint)


func _build_touch_buttons() -> void:
	var v := UiKit.vbox(8)
	v.anchor_left = 1.0
	v.anchor_right = 1.0
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -64
	v.offset_right = -12
	v.offset_top = 90
	root.add_child(v)
	zoom_box = v
	for spec in [["+", 0.8], ["−", 1.25]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(52, 52)
		b.add_theme_font_size_override("font_size", 26)
		b.focus_mode = Control.FOCUS_NONE
		var f: float = spec[1]
		b.pressed.connect(func() -> void: game.zoom_view(f))
		v.add_child(b)
	# hold-to-fire button for touch screens in the gunner view
	fire_btn = Button.new()
	fire_btn.text = GS.t("ОГОНЬ")
	fire_btn.add_theme_font_size_override("font_size", 24)
	fire_btn.custom_minimum_size = Vector2(130, 130)
	fire_btn.focus_mode = Control.FOCUS_NONE
	fire_btn.add_theme_stylebox_override("normal", UiKit.sbox(Color(0.4, 0.05, 0.03, 0.75), Color(1.0, 0.3, 0.2), 3, 65, 6))
	fire_btn.add_theme_stylebox_override("pressed", UiKit.sbox(Color(0.8, 0.15, 0.08, 0.9), Color(1.0, 0.6, 0.4), 3, 65, 6))
	fire_btn.anchor_left = 1.0
	fire_btn.anchor_right = 1.0
	fire_btn.anchor_top = 1.0
	fire_btn.anchor_bottom = 1.0
	fire_btn.offset_left = -170
	fire_btn.offset_right = -30
	fire_btn.offset_top = -290
	fire_btn.offset_bottom = -150
	fire_btn.button_down.connect(func() -> void: game.set_trigger(true))
	fire_btn.button_up.connect(func() -> void: game.set_trigger(false))
	fire_btn.visible = false
	root.add_child(fire_btn)


# --- Updates --------------------------------------------------------------------------
func _on_money(_v: int) -> void:
	refresh()


func refresh() -> void:
	if money_lbl == null:
		return
	money_lbl.text = GS.fmt_money(GS.money)
	money_lbl.add_theme_color_override("font_color", UiKit.NEON if GS.money >= 0 else UiKit.RED)
	city_bar.value = GS.city
	base_bar.value = GS.base_hp
	loc_lbl.text = GS.t("Позиция: ") + GS.loc_name(GS.base_loc)
	if GS.won:
		loc_lbl.text += GS.t("  ·  кампания пройдена ★")
	else:
		loc_lbl.text += GS.t("  ·  ночь %d из %d") % [GS.day, GS.CAMPAIGN_NIGHTS]
	var own: Array = game.owned_in_group(game.weapon_group)
	if String(game.weapon_group) + ":" + ",".join(PackedStringArray(own)) != _owned_sig:
		_rebuild_weapon_buttons()
	for spec in GS.WEAPON_GROUPS:
		var g := String(spec[0])
		var gb: Button = group_btns.get(g)
		if gb == null:
			continue
		var have: int = game.owned_in_group(g).size()
		var total: int = _group_total(g)
		gb.text = "%s %d/%d" % [GS.t(String(spec[1])), have, total]
		var open_tab: bool = g == String(game.weapon_group)
		gb.add_theme_stylebox_override("normal", _style_sel if open_tab else _style_norm)
		gb.add_theme_color_override("font_color", Color(1, 1, 1) if open_tab else (Color(0.7, 1.0, 0.85) if have > 0 else Color(0.5, 0.6, 0.55)))
	for i in own.size():
		var id: String = String(own[i])
		var b: Button = weapon_btns.get(id)
		if b == null:
			continue
		var def: Dictionary = GS.WEAPONS[id]
		var ammo := "∞" if def.kind == "gun" else "×%d" % int(GS.ammo.get(id, 0))
		if def.kind == "drone" and not game.drones.is_empty():
			ammo += GS.t(" · в небе %d") % game.drones.size()
		var w = game.weapons.get(id)
		var status: String = w.status_text() if w != null else ""
		var r: float = w.effective_range() if w != null else float(def.range)
		var key := "%d · " % (i + 1) if i < 9 else ""
		b.text = GS.t("%s%s\n%s · %d м\n%s") % [key, GS.t(String(def.short)), ammo, int(r * 5.0), status]
		b.tooltip_text = GS.t(String(def.name))
		var sel: bool = id == game.selected_weapon
		b.add_theme_stylebox_override("normal", _style_sel if sel else _style_norm)
		b.add_theme_color_override("font_color", Color(1, 1, 1) if sel else Color(0.7, 1.0, 0.85))
	auto_btn.text = GS.t("АВТО [%s]: %s") % [GS.key_label("auto"), game.auto_mode_name()]


## How many systems the group has in total, bought or not — shown on the tab as "have/total".
func _group_total(g: String) -> int:
	var n := 0
	for id in GS.WEAPON_ORDER:
		if String(GS.WEAPONS[id].get("group", "manual")) == g:
			n += 1
	return n


func _on_weapon_btn(id: String) -> void:
	SFX.play("click", -8.0)
	if GS.unlocked.get(id, false):
		game.select_weapon(id)
	else:
		open_shop()


func alert(text: String, color := UiKit.RED) -> void:
	if _alerts.size() > 3:
		_alerts.pop_front()
	_alerts.append([text, color])
	if _alert_t <= 0.0:
		_next_alert()


func _next_alert() -> void:
	if _alerts.is_empty():
		alert_lbl.text = ""
		_alert_t = 0.0
		return
	var a: Array = _alerts.pop_front()
	alert_lbl.text = a[0]
	alert_lbl.add_theme_color_override("font_color", a[1])
	alert_lbl.add_theme_color_override("font_shadow_color", Color(a[1].r, a[1].g, a[1].b, 0.6))
	_alert_t = 3.2


func log_event(text: String, color := Color(0.7, 1.0, 0.85)) -> void:
	var l := UiKit.label(text, 14, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	log_box.add_child(l)
	while log_box.get_child_count() > 6:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 1.5).set_delay(8.0)


func _process(delta: float) -> void:
	_t += delta
	_process_multiplayer(delta)
	if _alert_t > 0.0:
		_alert_t -= delta
		alert_lbl.modulate.a = 0.35 + 0.65 * absf(sin(_t * 6.0))
		if _alert_t <= 0.0:
			_next_alert()
	var d = game.director
	if d != null:
		var secs := int(d.time_left())
		phase_lbl.text = GS.t("ДЕНЬ %d · %s · %d:%02d") % [GS.day, d.phase_name(), secs / 60, secs % 60]
		if d.is_night() and d.time_left() <= 0.0:
			phase_lbl.text = GS.t("ДЕНЬ %d · НОЧЬ · добейте цели: %d") % [GS.day, game.enemies.size()]
	if GS.base_found:
		detect_lbl.text = GS.t("⚠ БАЗА ОБНАРУЖЕНА — ожидайте удар")
		detect_lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 0.5 + 0.5 * absf(sin(_t * 5.0))))
	else:
		var hidden := 100.0 - clampf(GS.detection / 14.0 * 100.0, 0.0, 100.0)
		detect_lbl.text = GS.t("Маскировка базы: %d%%%s") % [int(hidden), GS.t(" · сеть") if GS.camo else ""]
		detect_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	_update_fires()
	nv_rect.visible = (game.view == "base" and game.base_view.nv) or (game.view == "fpv" and game.fpv_view.nv)
	_update_target_info()
	if int(_t * 4.0) != int((_t - delta) * 4.0):
		refresh()


## Fire service status: only on screen while something is burning or being rebuilt.
func _update_fires() -> void:
	var fs = game.fire_service
	if fs == null:
		return
	var burning: int = fs.active_fires()
	var building: int = fs.repairs.size()
	fire_lbl.visible = burning > 0 or building > 0
	if not fire_lbl.visible:
		return
	fire_lbl.text = GS.t("🔥 Пожаров: %d · расчётов: %d/%d · стройка: %d") % [burning, fs.free_crews(), fs.crew_limit(), building]
	var hot: bool = burning > fs.crew_limit()
	fire_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25) if hot else Color(1.0, 0.7, 0.35))


func _update_target_info() -> void:
	var info: Dictionary = game.predict_info
	if info.is_empty() or game.view != "top":
		target_panel.visible = false
		return
	target_panel.visible = true
	var e = info.enemy
	var dist := Vector2(e.position.x - GS.base_pos.x, e.position.z - GS.base_pos.z).length()
	var w = game.weapons.get(game.selected_weapon)
	var in_r := ""
	if w != null:
		if not w.can_engage(e):
			in_r = GS.t(" · %s НЕ ПОРАЖАЕТ") % GS.t(String(w.def.short))
		else:
			in_r = GS.t(" · В ЗОНЕ ПОРАЖЕНИЯ") if w.in_range(e) else GS.t(" · вне зоны")
	target_lbl.text = GS.t("ЦЕЛЬ: %s → %s\nДальность %.1f км · высота %d м · %d%%%s") % [GS.t(String(e.def.name)), GS.t(e.target_name), dist * 0.005, int(e.position.y * 5.0), int(100.0 * e.hp / e.max_hp), in_r]
	predict_lbl.text = GS.t("Падение обломков: ") + String(info.text)
	predict_lbl.add_theme_color_override("font_color", info.color)


# --- Overlays ---------------------------------------------------------------------------
func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _set_paused(p: bool) -> void:
	if _live():
		# a shared raid does not stop for anybody's window: only the mouse is let go
		game.overlay_open = p
		get_tree().paused = false
	else:
		get_tree().paused = p
	if p:
		game.base_view.trigger = false
	game.refresh_capture()


func toggle_pause() -> void:
	if game.game_over:
		return
	if _overlay != null:
		if _overlay.has_meta("pause"):
			_close_overlay()
			_set_paused(false)
		return
	_show_pause()


func _show_pause() -> void:
	_close_overlay()
	_set_paused(true)
	var m := UiKit.modal(root, Vector2(420, 0))
	_overlay = m[0]
	_overlay.set_meta("pause", true)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ПАУЗА"), 40, UiKit.NEON))
	v.add_child(UiKit.button(GS.t("Продолжить"), toggle_pause))
	v.add_child(UiKit.button(GS.t("Магазин"), open_shop))
	v.add_child(UiKit.button(GS.t("Лента города [%s]") % GS.key_label("feed"), open_feed))
	v.add_child(UiKit.button(GS.t("Настройки"), _show_settings))
	var note := GS.t("Мир «%s». Автосохранение — каждое утро.") % GS.world_name
	if Net.role == "guest":
		v.add_child(UiKit.button(GS.t("Отключиться"), func() -> void: game.main.leave_session()))
		var hn := String(Net.world.get("n", "?"))
		note = GS.t("Вы в гостях у %s. Здесь ничего не сохраняется — ваши миры остаются как были.") % hn
		note += GS.t("\nСетевая игра не останавливается: пока вы в паузе, друзья продолжают.")
	else:
		if GS.world_id != "":
			if Net.role == "host":
				v.add_child(UiKit.button(GS.t("Закрыть мир для друзей"), _close_world))
			else:
				v.add_child(UiKit.button(GS.t("Открыть для друзей"), _open_world))
		v.add_child(UiKit.button(GS.t("Сохранить и выйти в меню"), func() -> void: game.main.exit_to_menu()))
		if Net.role == "host":
			note += GS.t("\nМир открыт для друзей · ваш код %s · игроков %d/%d") % [Net.fmt_code(Net.code()), Net.players.size(), Net.MAX_PLAYERS]
			if Net.players.size() > 1:
				note += GS.t("\nСетевая игра не останавливается: пока вы в паузе, друзья продолжают.")
		if game.director.is_night():
			note += GS.t("\nНочь не сохраняется: при выходе вы продолжите с утра дня %d.") % GS.day
	var nl := UiKit.label(note, 13, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(380, 0)
	v.add_child(nl)


# --- Multiplayer ------------------------------------------------------------------------------
func _build_multiplayer() -> void:
	_requests_box = UiKit.vbox(8)
	_requests_box.anchor_left = 0.5
	_requests_box.anchor_right = 0.5
	_requests_box.offset_left = -280
	_requests_box.offset_right = 280
	_requests_box.offset_top = 96
	_requests_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_requests_box)
	_watch_lbl = UiKit.label("", 19, UiKit.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_watch_lbl.anchor_left = 0.0
	_watch_lbl.anchor_right = 1.0
	_watch_lbl.anchor_top = 1.0
	_watch_lbl.anchor_bottom = 1.0
	_watch_lbl.offset_top = -64
	_watch_lbl.offset_bottom = -30
	_watch_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_watch_lbl.add_theme_constant_override("outline_size", 6)
	_watch_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watch_lbl.visible = false
	root.add_child(_watch_lbl)
	Net.join_requested.connect(_on_join_request)
	Net.request_closed.connect(_drop_request_card)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	# the HUD is rebuilt after a language change: bring back requests still waiting
	for c in Net.pending:
		_on_join_request(String(c), String(Net.pending[c].nick))


func _process_multiplayer(delta: float) -> void:
	if _players_btn:
		_players_btn.visible = Net.is_online()
	if players_open() and not Net.is_online():
		toggle_players()
	if players_open():
		# join requests stay readable above the list: it moves down under them
		var below := 64.0
		if not _req_cards.is_empty():
			below = _requests_box.position.y + _requests_box.size.y + 12.0
		_players.offset_top = below
	# a knock at the door stays on top of whatever window is open (pause, shop, morning report)
	if not _req_cards.is_empty() and _requests_box.get_index() != root.get_child_count() - 1:
		_requests_box.move_to_front()
	for c in _req_cards.keys():
		var card: Dictionary = _req_cards[c]
		card.left = float(card.left) - delta / maxf(Engine.time_scale, 0.001)
		(card.bar as ProgressBar).value = maxf(float(card.left), 0.0)
	if _watch_lbl and _watch_lbl.visible and Net.players.has(game.watch_code):
		var p: Dictionary = Net.players[game.watch_code]
		_watch_lbl.text = GS.t("👁 Вы смотрите глазами %s — %s · Esc или %s — вернуться") % [String(p.nick), RemotePlayers.view_name(String(p.view)), GS.key_label("view")]
		_watch_lbl.add_theme_color_override("font_color", p.color)


func players_open() -> bool:
	return _players != null and is_instance_valid(_players)


## Tab: the list of everyone in the session (opens only in a multiplayer game).
func toggle_players() -> void:
	if players_open():
		_players.queue_free()
		_players = null
	elif Net.is_online():
		_players = PlayerList.new()
		_players.game = game
		root.add_child(_players)
		SFX.play("click", -10.0)
	game.ui_cursor = players_open()
	game.refresh_capture()


func _on_join_request(c: String, nick: String) -> void:
	if _req_cards.has(c):
		return
	var p := UiKit.panel(Vector2(560, 0))
	p.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.0, 0.07, 0.1, 0.95), UiKit.CYAN, 2, 8, 10))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(8)
	p.add_child(v)
	var t := UiKit.label(GS.t("📡 %s хочет присоединиться к вашему миру") % nick, 19, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var h := UiKit.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var yes := UiKit.button(GS.t("Принять [Y]"), _answer_request.bind(c, true), 220, 17)
	yes.focus_mode = Control.FOCUS_NONE
	yes.add_theme_color_override("font_color", UiKit.NEON)
	h.add_child(yes)
	var no := UiKit.button(GS.t("Отклонить [N]"), _answer_request.bind(c, false), 220, 17)
	no.focus_mode = Control.FOCUS_NONE
	h.add_child(no)
	var bar := ProgressBar.new()
	bar.max_value = Net.REQUEST_TIMEOUT
	bar.value = Net.REQUEST_TIMEOUT
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	v.add_child(bar)
	_requests_box.add_child(p)
	_req_cards[c] = {"panel": p, "bar": bar, "left": Net.REQUEST_TIMEOUT}
	SFX.play("alert", -8.0)
	log_event(GS.t("%s просится в ваш мир: Y — принять, N — отклонить") % nick, UiKit.CYAN)


func _answer_request(c: String, ok: bool) -> void:
	if ok:
		Net.accept(c)
	else:
		Net.decline(c)
	_drop_request_card(c)


func _drop_request_card(c: String) -> void:
	if _req_cards.has(c):
		(_req_cards[c].panel as Control).queue_free()
		_req_cards.erase(c)


## A shared raid is running: a guest, or a host with friends in the world.
func _live() -> bool:
	return Net.role == "guest" or (Net.role == "host" and Net.players.size() > 1)


func _on_player_joined(nick: String) -> void:
	if get_tree().paused:
		# the first friend is in: the raid cannot wait for our menu any more
		get_tree().paused = false
		game.overlay_open = _overlay != null
		game.refresh_capture()
	log_event(GS.t("%s присоединился к обороне") % nick, UiKit.CYAN)
	SFX.play("click", -4.0)


func _on_player_left(nick: String) -> void:
	log_event(GS.t("%s покинул мир") % nick, UiKit.AMBER)


func _open_world() -> void:
	Net.open_world()
	log_event(GS.t("Мир открыт для друзей. Ваш код: %s") % Net.fmt_code(Net.code()), UiKit.CYAN)
	_show_pause()


func _close_world() -> void:
	Net.close()
	log_event(GS.t("Мир закрыт для друзей"), UiKit.AMBER)
	_show_pause()


## Y / N answer the oldest join request (checked before the game's own keys: N is night vision).
func _input(event: InputEvent) -> void:
	if _req_cards.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc := (event as InputEventKey).keycode
	if kc == KEY_Y or kc == KEY_N:
		get_viewport().set_input_as_handled()
		_answer_request(String(_req_cards.keys()[0]), kc == KEY_Y)


func _show_settings() -> void:
	_close_overlay()
	var s := SettingsMenu.new()
	var lang_before := String(GS.settings.lang)
	var keys_before := str(GS.settings.get("keys", {}))
	var after := func() -> void:
		_overlay = null
		if String(GS.settings.lang) != lang_before or str(GS.settings.get("keys", {})) != keys_before:
			game.rebuild_hud() # labels carry the language and the bound keys
		else:
			_show_pause()
	s.closed.connect(after)
	root.add_child(s)
	_overlay = s


## Plays one published compilation: the HUD gets out of the way, the session pauses and the
## reel re-stages the night over the real city.
func open_video(v: Dictionary, after := Callable(), record := false) -> void:
	if _video != null:
		return
	if Net.is_online():
		# the reel re-stages the night with the session paused — not while friends play on
		alert(GS.t("Ролики можно смотреть после сетевой игры"), UiKit.AMBER)
		if after.is_valid():
			after.call()
		return
	_video_after = after
	_close_overlay()
	_set_paused(true)
	game.enemy_root.visible = false
	root.visible = false
	var ui := VideoUi.new()
	ui.game = game
	ui.reel = game.reel
	ui.closed.connect(close_video)
	ui.record_requested.connect(func() -> void: _restart_recording(v))
	add_child(ui)
	_video = ui
	if not game.reel.finished.is_connected(close_video):
		game.reel.finished.connect(close_video)
	if not game.reel.clip_started.is_connected(ui.on_clip):
		game.reel.clip_started.connect(ui.on_clip)
	game.reel.play(v)
	if record:
		_start_recording(v, ui)


## Writes the cut to a file while it plays. Everything is captured off the screen, so the
## compilation simply runs once from the top.
func _start_recording(v: Dictionary, ui: Control) -> void:
	var rec = VideoExport.new()
	rec.game = game
	rec.reel = game.reel
	rec.ui = ui
	add_child(rec)
	rec.done.connect(_on_recorded)
	if not rec.start(int(v.get("day", GS.day))):
		rec.queue_free()
		alert(GS.t("Не удалось создать файл видео"), Color(1.0, 0.5, 0.4))
		return
	_recorder = rec
	_record_back = _video_after
	ui.recorder = rec


## The save button on an already playing cut: start it over, this time recording.
func _restart_recording(v: Dictionary) -> void:
	if _recorder != null and is_instance_valid(_recorder) and _recorder.recording:
		return
	var after := _video_after
	close_video()
	open_video(v, after, true)


func _on_recorded(saved: String, ok: bool) -> void:
	if _recorder != null and is_instance_valid(_recorder):
		_recorder.queue_free()
	_recorder = null
	if not ok:
		alert(GS.t("Запись отменена"), Color(1.0, 0.7, 0.3))
		return
	log_event(GS.t("Видео сохранено: %s") % saved, Color(0.6, 0.9, 1.0))
	# the cut is still closing around us, and closing it reopens whatever we came from —
	# so the notice waits until that has settled and then puts itself on top
	_saved_video_dialog.call_deferred(saved)


## Where the file landed, with a button that opens the folder.
func _saved_video_dialog(saved: String) -> void:
	_close_overlay()
	var m := UiKit.modal(root, Vector2(560, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ВИДЕО СОХРАНЕНО"), 30, UiKit.NEON))
	var l := UiKit.label(saved, 15, Color(0.75, 0.95, 0.9))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	v.add_child(UiKit.label(GS.t("Формат AVI (Motion JPEG) со звуком — открывается любым плеером."), 14, UiKit.CYAN))
	var h := UiKit.hbox(12)
	v.add_child(h)
	h.add_child(UiKit.button(GS.t("Открыть папку"), func() -> void:
		OS.shell_open(saved.get_base_dir()), 240, 18))
	h.add_child(UiKit.button(GS.t("Закрыть"), _leave_saved_dialog, 240, 18))


## Back to the feed the export was started from, or back to the game if it was started from
## the morning report.
func _leave_saved_dialog() -> void:
	_close_overlay()
	var back := _record_back
	_record_back = Callable()
	if back.is_valid():
		back.call()
	else:
		_set_paused(false)


func close_video() -> void:
	if _video == null:
		return
	if game.reel.playing:
		game.reel.stop()
		return # stop() emits finished, which lands back here
	if _recorder != null and is_instance_valid(_recorder) and _recorder.recording:
		# a cut watched to the end is a finished file; one closed early is thrown away
		_recorder.finish(String(game.reel.phase) == "outro")
	if game.reel.finished.is_connected(close_video):
		game.reel.finished.disconnect(close_video)
	_video.queue_free()
	_video = null
	game.enemy_root.visible = true
	root.visible = true
	game.refresh_capture()
	var after := _video_after
	_video_after = Callable()
	if after.is_valid():
		after.call()
	else:
		_set_paused(false)


## Archive of the published nights: one card per compilation, newest first.
func open_feed() -> void:
	if game.game_over or _video != null:
		return
	_close_overlay()
	_set_paused(true)
	var m := UiKit.modal(root, Vector2(560, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ЛЕНТА ГОРОДА"), 34, UiKit.NEON))
	v.add_child(UiKit.label(GS.t("%s склеивает то, что горожане сняли ночью, в один ролик на 30 секунд.") % GS.video_channel(),
		15, Color(0.65, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	if GS.videos.is_empty():
		v.add_child(UiKit.label(GS.t("Роликов пока нет — переживите первую ночь."), 18, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(520, 330)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(scroll)
		var list := UiKit.vbox(6)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for i in range(GS.videos.size() - 1, -1, -1):
			_feed_row(list, GS.videos[i])
	v.add_child(UiKit.button(GS.t("Закрыть"), func() -> void:
		_close_overlay()
		_set_paused(false)))


func _feed_row(list: Control, v: Dictionary) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.02, 0.08, 0.06, 0.8), UiKit.NEON_DIM, 1, 6, 8))
	list.add_child(p)
	var h := UiKit.hbox(12)
	p.add_child(h)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var clips: Array = v.get("clips", [])
	info.add_child(UiKit.label(GS.t("Ночь %d · %d роликов · 0:%02d") % [int(v.get("day", 0)), clips.size(), int(clips.size()) * int(GS.VIDEO_CLIP_LEN)], 19, Color(0.9, 1.0, 0.95)))
	var top := String(clips[0].get("caption", "")) if not clips.is_empty() else ""
	var l := UiKit.label(top, 13, Color(0.6, 0.85, 0.75))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(l)
	info.add_child(UiKit.label(GS.t("%s просмотров · %s лайков") % [_short_count(int(v.get("views", 0))), _short_count(int(v.get("likes", 0)))], 13, UiKit.CYAN))
	var b := Button.new()
	b.text = GS.t("▶ Смотреть")
	b.custom_minimum_size = Vector2(150, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var day_n := int(v.get("day", 0))
	b.pressed.connect(func() -> void:
		SFX.play("click", -8.0)
		_close_overlay()
		open_video(GS.video_for_day(day_n), open_feed))
	h.add_child(b)
	var save := Button.new()
	save.text = GS.t("⤓ Сохранить")
	save.custom_minimum_size = Vector2(150, 44)
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(func() -> void:
		SFX.play("click", -8.0)
		_close_overlay()
		open_video(GS.video_for_day(day_n), open_feed, true))
	h.add_child(save)


static func _short_count(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (float(n) / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)


func open_shop(on_close := Callable()) -> void:
	if game.game_over:
		return
	if _overlay != null and _overlay is Shop:
		return
	_close_overlay()
	_set_paused(true)
	var s := Shop.new()
	s.game = game
	var after := func() -> void:
		_overlay = null
		if on_close.is_valid():
			on_close.call()
		else:
			_set_paused(false)
	s.closed.connect(after)
	root.add_child(s)
	_overlay = s


func show_morning(r: Dictionary) -> void:
	if bool(r.get("victory", false)) and not _victory_seen:
		_victory_seen = true
		show_victory(r)
		return
	_close_overlay()
	_set_paused(true)
	var m := UiKit.modal(root, Vector2(560, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("УТРО · ИТОГИ НОЧИ %d") % int(r.day), 34, UiKit.AMBER))
	var lines := [
		[GS.t("Сбито целей"), str(r.kills), UiKit.NEON],
		[GS.t("Прилёты по городу"), str(r.impacts), UiKit.RED if int(r.impacts) > 0 else UiKit.NEON],
		[GS.t("Шахеды упали на дома"), str(r.get("homes", 0)), UiKit.RED if int(r.get("homes", 0)) > 0 else UiKit.NEON],
		[GS.t("Повреждено крыш обломками"), str(r.roofs), UiKit.RED if int(r.roofs) > 0 else UiKit.NEON],
		[GS.t("Награды за ночь"), "+" + GS.fmt_money(int(r.earned)), UiKit.NEON],
		[GS.t("Штрафы и ремонт"), "−" + GS.fmt_money(int(r.penalties)), UiKit.RED],
		[GS.t("Госфинансирование"), "+" + GS.fmt_money(int(r.funding)), UiKit.CYAN],
		[GS.t("Бонус «чистое небо»"), "+" + GS.fmt_money(int(r.bonus)), UiKit.CYAN],
	]
	if int(r.get("repaired", 0)) > 0:
		lines.append([GS.t("Восстановлено городом за день"), "+%d%%" % int(r.repaired), UiKit.CYAN])
	if int(r.get("misses", 0)) > 0:
		lines.insert(4, [GS.t("Промахи ракет"), str(r.misses), UiKit.AMBER])
	if int(r.get("fires_out", 0)) > 0 or int(r.get("rebuilt", 0)) > 0:
		lines.append([GS.t("Потушено пожаров · восстановлено зданий"), "%d · %d" % [int(r.get("fires_out", 0)), int(r.get("rebuilt", 0))], UiKit.CYAN])
	if int(r.get("drones", 0)) > 0:
		lines.insert(4, [GS.t("Вылетов дронов · таранов"), "%d · %d" % [int(r.drones), int(r.get("rams", 0))], UiKit.CYAN])
	if int(r.get("relief", 0)) > 0:
		lines.append([GS.t("Экстренная помощь (списание долга)"), "+" + GS.fmt_money(int(r.relief)), UiKit.AMBER])
	for ln in lines:
		var h := UiKit.hbox()
		var a := UiKit.label(ln[0], 18)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UiKit.label(ln[1], 18, ln[2]))
		v.add_child(h)
	v.add_child(UiKit.label(GS.t("Бюджет: ") + GS.fmt_money(GS.money), 22, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER))
	var next := func() -> void:
		_close_overlay()
		_set_paused(false)
		game.director.next_day()
	var shop_then_next := func() -> void:
		open_shop(next)
	var vid: Dictionary = GS.video_for_day(int(r.day))
	if not vid.is_empty():
		var clips: Array = vid.get("clips", [])
		var watch := func() -> void:
			open_video(vid, func() -> void: show_morning(r))
		v.add_child(UiKit.button(GS.t("▶ Нарезка ночи (0:%02d)") % (clips.size() * int(GS.VIDEO_CLIP_LEN)), watch))
	v.add_child(UiKit.button(GS.t("Магазин"), shop_then_next))
	v.add_child(UiKit.button(GS.t("Следующий день ▶"), next))
	if game.autotest and not game.main._args.has("opened"):
		print("UAD: morning report ", r)
		get_tree().create_timer(0.5, true).timeout.connect(next)


## Campaign finale held: the city survived. The defense may continue afterwards.
func show_victory(r: Dictionary) -> void:
	_close_overlay()
	_set_paused(true)
	var m := UiKit.modal(root, Vector2(620, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ПОБЕДА"), 46, UiKit.NEON))
	v.add_child(UiKit.label(GS.ctext("held") % GS.CAMPAIGN_NIGHTS, 22, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var s := GS.stats
	var txt := GS.t("Сбито целей: %d\nПрилётов по городу: %d\nЦелей упало на дома: %d\nКрыш повреждено обломками: %d\nОбломков упало %s: %d\nГород цел на: %d%%\nЗаработано: %s · Штрафы: %s") % [
		int(s.kills), int(s.impacts), int(s.get("homes", 0)), int(s.roofs), GS.ctext("water_into"), int(s.splash), int(GS.city),
		GS.fmt_money(int(s.earned)), GS.fmt_money(int(s.penalties))]
	v.add_child(UiKit.label(txt, 18, Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
	if int(r.get("award", 0)) > 0:
		v.add_child(UiKit.label(GS.t("Награда за операцию: +%s") % GS.fmt_money(int(r.award)), 22, UiKit.CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(GS.t("Налёты не прекращаются — оборону можно продолжать сколько угодно."), 16, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER))
	var to_report := func() -> void: show_morning(r)
	v.add_child(UiKit.button(GS.t("Продолжить оборону ▶"), to_report))
	v.add_child(UiKit.button(GS.t("Главное меню"), func() -> void: game.main.show_menu()))
	if game.autotest and not game.main._args.has("opened"):
		print("UAD: VICTORY ", r)
		get_tree().create_timer(0.5, true).timeout.connect(to_report)


func show_game_over(reason: String) -> void:
	_close_overlay()
	_set_paused(true)
	var m := UiKit.modal(root, Vector2(560, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ОБОРОНА ПРОРВАНА"), 40, UiKit.RED))
	v.add_child(UiKit.label(reason, 20, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var s := GS.stats
	var txt := GS.t("Продержались дней: %d\nСбито целей: %d\nПрилётов по городу: %d\nШахедов упало на дома: %d\nКрыш повреждено обломками: %d\nОбломков упало %s: %d\nЗаработано: %s · Штрафы: %s") % [
		GS.day, int(s.kills), int(s.impacts), int(s.get("homes", 0)), int(s.roofs), GS.ctext("water_into"), int(s.splash), GS.fmt_money(int(s.earned)), GS.fmt_money(int(s.penalties))]
	v.add_child(UiKit.label(txt, 18, Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
	if GS.world_id != "":
		v.add_child(UiKit.button(GS.t("Повторить с последнего утра"), func() -> void: game.main.play_world(GS.world_id)))
	v.add_child(UiKit.button(GS.t("Главное меню"), func() -> void: game.main.show_menu()))
