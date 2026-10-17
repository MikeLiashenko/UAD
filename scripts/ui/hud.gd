extends CanvasLayer
## In-game HUD: budget, day/night status, radar, flashing launch alerts, event log,
## AA weapon panel, debris-fall prediction and modal overlays (pause, shop, reports).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Radar = preload("res://scripts/ui/radar.gd")
const Shop = preload("res://scripts/ui/shop.gd")
const Supply = preload("res://scripts/ui/supply.gd")
const StrikeMap = preload("res://scripts/ui/strike_map.gd")
const Strikes = preload("res://scripts/game/strikes.gd")
const BdaView = preload("res://scripts/ui/bda_view.gd")
const Orders = preload("res://scripts/game/orders.gd")
const Achievements = preload("res://scripts/core/achievements.gd")
const AttackMap = preload("res://scripts/ui/attack_map.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const Reticle = preload("res://scripts/ui/reticle.gd")
const FpvOsd = preload("res://scripts/ui/fpv_osd.gd")
const MfgHud = preload("res://scripts/ui/mfg_hud.gd")
const FighterHud = preload("res://scripts/ui/fighter_hud.gd")
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
## Touch screens, the map view: hold buttons that rotate and tilt the camera.
var turn_box: GridContainer

var root: Control
var money_lbl: Label
var phase_lbl: Label
var loc_lbl: Label
## The order of the command for the day (scripts/game/orders.gd).
var order_lbl: Label
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
## Buttons of the mobile fire group: out of the truck, swap seats (touch screens, Alt + mouse).
var _mfg_ui: Control
## Buttons of the F-16 sortie (touch screens, Alt + mouse): missiles, afterburner, back home.
var _fighter_ui: Control
## Panels a MaxRealism session never shows (the budget, the round radar, the event feed).
var _status_panel: Control
var _radar: Control
## Frame of the last alert: in MaxRealism the feed line that repeats it is not said twice.
var _alert_frame := -1
## The finger holding the fire button of a touch screen (-1: none).
var _fire_touch := -1
## The air-raid alarm (GameController.toggle_alarm): its button under the status panel, on screen
## in every view, and the line of the panel that says where the people are.
var alarm_btn: Button
var alarm_lbl: Label
## A launcher in the open (scripts/game/strikes.gd, hunts): the button opens the strike map on it.
var hunt_btn: Button
## The footage of our strikes as they land (scripts/ui/bda_view.gd).
var bda: Control
var _alarm_styles: Array = []
## A match on a server: both cities' integrity and the strikes on their way: [bar, percent] × 2, the line under them.
var _pvp_bars: Array = []
var _pvp_line: Label


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
	var mh := MfgHud.new()
	mh.game = game
	mh.mg = game.mfg
	root.add_child(mh)
	var fh := FighterHud.new()
	fh.game = game
	fh.fg = game.fighter
	root.add_child(fh)
	_build_status()
	_build_radar()
	_build_alert()
	if not GS.pvp.is_empty():
		_build_pvp()
	_build_weapons()
	_build_target_info()
	_build_touch_buttons()
	_build_alarm()
	_build_hunt()
	bda = BdaView.new()
	root.add_child(bda)
	flash_rect = UiKit.full_rect(ColorRect.new()) as ColorRect
	flash_rect.color = Color(1.0, 0.92, 0.8, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_build_walk_ui()
	_build_fpv_ui()
	_build_mfg_ui()
	_build_fighter_ui()
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
	if GS.touch():
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


func _build_mfg_ui() -> void:
	var p := UiKit.panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -16
	p.offset_bottom = -52
	p.visible = false
	root.add_child(p)
	var h := UiKit.hbox(8)
	p.add_child(h)
	_small_btn(h, GS.t("⟵ ИЗ МАШИНЫ [%s]") % GS.key_label("mfg"), func() -> void: game.toggle_mfg()).custom_minimum_size = Vector2(170, 38)
	_small_btn(h, GS.t("РУЛЬ ⇄ ПУЛЕМЁТ [Пробел]"), func() -> void: game.mfg.switch_seat()).custom_minimum_size = Vector2(230, 38)
	_mfg_ui = p


func _build_fighter_ui() -> void:
	var p := UiKit.panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -16
	p.offset_bottom = -52
	p.visible = false
	root.add_child(p)
	var h := UiKit.hbox(8)
	p.add_child(h)
	_small_btn(h, GS.t("⟵ НА АЭРОДРОМ [%s]") % GS.key_label("fighter"), func() -> void: game.toggle_fighter()).custom_minimum_size = Vector2(190, 38)
	var mb := _small_btn(h, GS.t("🚀 РАКЕТА"), func() -> void: game.fighter.fire("auto"))
	mb.custom_minimum_size = Vector2(150, 38)
	mb.add_theme_color_override("font_color", UiKit.AMBER)
	_small_btn(h, "AIM-9X", func() -> void: game.fighter.fire("aim9")).custom_minimum_size = Vector2(110, 38)
	_small_btn(h, "AIM-120", func() -> void: game.fighter.fire("aim120")).custom_minimum_size = Vector2(110, 38)
	var ab := _small_btn(h, GS.t("ФОРСАЖ"), func() -> void: pass)
	ab.custom_minimum_size = Vector2(110, 38)
	ab.button_down.connect(func() -> void: game.fighter.burner = true)
	ab.button_up.connect(func() -> void: game.fighter.burner = false)
	_fighter_ui = p


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
	var mfg: bool = game.view == "mfg"
	var air: bool = game.view == "fighter"
	if view_btn:
		var vname := GS.t("СВЕРХУ")
		if base:
			vname = GS.t("БАЗА")
		elif fpv:
			vname = GS.t("FPV")
		elif watch:
			vname = GS.t("ДРУГ")
		elif mfg:
			vname = GS.t("МОГ")
		elif air:
			vname = GS.t("F-16")
		view_btn.text = GS.t("ВИД [%s]: %s") % [GS.key_label("view"), vname]
	if fire_btn:
		fire_btn.visible = (base or fpv or mfg or air) and GS.touch()
		fire_btn.text = GS.t("РАЗГОН") if fpv else (GS.t("ПУШКА") if air else GS.t("ОГОНЬ"))
	if target_panel:
		target_panel.visible = false
	if _weapons_panel:
		_weapons_panel.visible = not walk and not fpv and not watch and not mfg and not air
	if _watch_lbl:
		_watch_lbl.visible = watch
	if _walk_ui:
		_walk_ui.visible = walk
	if _fpv_ui:
		_fpv_ui.visible = fpv
	if _mfg_ui:
		_mfg_ui.visible = mfg
	if _fighter_ui:
		_fighter_ui.visible = air
	if zoom_box:
		zoom_box.visible = not walk and not fpv and not mfg and not air
	if turn_box:
		turn_box.visible = game.view == "top" and GS.touch() and not GS.realism
		if not turn_box.visible and game.rig != null:
			game.rig.turn = 0.0
			game.rig.tilt = 0.0
		# the zoom buttons stand under the camera pad, clear of the battery panel
		zoom_box.offset_top = 214 if turn_box.visible else 90
	if GS.realism:
		# MaxRealism: no budget, no radar in the corner, no battery panel — the picture and the radio
		for c in [_status_panel, _radar, log_box, alert_lbl, _weapons_panel, _walk_ui, _mfg_ui, zoom_box, fire_btn, alarm_btn]:
			if c != null:
				c.visible = false
	refresh()


# --- Construction -------------------------------------------------------------------
func _build_status() -> void:
	var p := UiKit.panel(Vector2(290, 0))
	p.position = Vector2(12, 12)
	root.add_child(p)
	_status_panel = p
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
	order_lbl = UiKit.label("", 13, Color(0.6, 0.9, 1.0))
	order_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_lbl.custom_minimum_size = Vector2(266, 0)
	order_lbl.visible = false
	v.add_child(order_lbl)
	city_bar = _bar(v, GS.t("ГОРОД"))
	base_bar = _bar(v, GS.t("БАЗА"))
	detect_lbl = UiKit.label("", 14)
	v.add_child(detect_lbl)
	fire_lbl = UiKit.label("", 14, Color(1.0, 0.6, 0.3))
	fire_lbl.visible = false
	v.add_child(fire_lbl)
	alarm_lbl = UiKit.label("", 14, Color(1.0, 0.4, 0.35))
	alarm_lbl.visible = false
	v.add_child(alarm_lbl)


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
	_radar = radar
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


## A match on a server: the two cities across the top of the screen — ours on the left, the
## enemy's on the right — and, under them, what is flying between them.
func _build_pvp() -> void:
	alert_lbl.offset_top = 84
	var p := UiKit.panel()
	p.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.0, 0.05, 0.04, 0.8), UiKit.NEON_DIM, 1, 6, 4))
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 8
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var h := UiKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var def: Dictionary = GS.pvp.get("def", {})
	var side := int(GS.pvp.get("side", 0))
	for i in 2:
		var col := UiKit.NEON if i == 0 else UiKit.RED
		var cname := String(def.cities[side if i == 0 else 1 - side].name)
		var nl := UiKit.label(cname, 15, col, HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT)
		nl.custom_minimum_size = Vector2(112, 0)
		nl.clip_text = true
		var b := ProgressBar.new()
		b.max_value = 100
		b.value = 100
		b.show_percentage = false
		b.custom_minimum_size = Vector2(104, 12)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.fill_mode = ProgressBar.FILL_END_TO_BEGIN if i == 0 else ProgressBar.FILL_BEGIN_TO_END
		b.add_theme_stylebox_override("fill", UiKit.sbox(col, col, 0, 3, 0))
		var pc := UiKit.label("100%", 15, col, HORIZONTAL_ALIGNMENT_CENTER)
		pc.custom_minimum_size = Vector2(48, 0)
		var parts: Array = [nl, pc, b] if i == 0 else [b, pc, nl]
		for c in parts:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(c)
		if i == 0:
			h.add_child(UiKit.label("⚔", 18, UiKit.AMBER))
		_pvp_bars.append([b, pc])
	_pvp_line = UiKit.label("", 13, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_pvp_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_pvp_line)


func _update_pvp() -> void:
	var pv = game.pvp
	if pv == null or _pvp_line == null:
		return
	for i in 2:
		var s: int = pv.side if i == 0 else 1 - pv.side
		(_pvp_bars[i][0] as ProgressBar).value = float(pv.hp[s])
		(_pvp_bars[i][1] as Label).text = "%d%%" % int(ceil(float(pv.hp[s])))
	var inb: Array = pv.inbound()
	var flying := 0
	for id in pv.outgoing:
		if String(pv.outgoing[id].st) != "done":
			flying += 1
	var parts := PackedStringArray()
	if int(inb[0]) > 0:
		parts.append(GS.t("⚠ к нам летит ударов: %d · первый через %s") % [int(inb[0]), pv.fmt_time(float(inb[1]))])
	if flying > 0:
		parts.append(GS.t("наших ударов в пути: %d") % flying)
	if parts.is_empty():
		parts.append(GS.t("🎯 удар по противнику — %s") % (GS.t("кнопка «УДАРЫ»") if GS.touch() else "[%s]" % GS.key_label("strikes")))
	_pvp_line.text = " · ".join(parts)
	_pvp_line.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25) if int(inb[0]) > 0 else Color(0.6, 0.9, 0.78))
	detect_lbl.visible = false


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
	_small_btn(side, GS.t("🎯 УДАРЫ [%s]") % GS.key_label("strikes"), open_strikes)
	var side2 := UiKit.vbox(6)
	h.add_child(side2)
	_small_btn(side2, GS.t("❚❚ ПАУЗА"), toggle_pause)
	_small_btn(side2, GS.t("⌂ К БАЗЕ [%s]") % GS.key_label("home"), func() -> void: game.rig.focus(GS.base_pos))
	_small_btn(side2, GS.t("🚙 МОГ [%s]") % GS.key_label("mfg"), func() -> void: game.toggle_mfg())
	_players_btn = _small_btn(side2, GS.t("👥 ИГРОКИ [%s]") % GS.key_label("players"), toggle_players)
	_players_btn.visible = Net.is_online()
	var side3 := UiKit.vbox(6)
	h.add_child(side3)
	view_btn = _small_btn(side3, GS.t("ВИД [%s]") % GS.key_label("view"), func() -> void: game.toggle_view())
	view_btn.custom_minimum_size = Vector2(132, 24)
	_small_btn(side3, GS.t("🚶 ГУЛЯТЬ [%s]") % GS.key_label("walk"), func() -> void: game.toggle_walk()).custom_minimum_size = Vector2(132, 24)
	_small_btn(side3, GS.t("🛩 ДРОН FPV [%s]") % GS.key_label("fpv"), func() -> void: game.enter_fpv()).custom_minimum_size = Vector2(132, 24)
	_small_btn(side3, GS.t("✈ F-16 [%s]") % GS.key_label("fighter"), func() -> void: game.toggle_fighter()).custom_minimum_size = Vector2(132, 24)
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
	# touch screens: the camera of the map view is also turned and tilted with hold buttons
	# (the gestures are two fingers turning about each other and sliding up or down together)
	turn_box = GridContainer.new()
	turn_box.columns = 2
	turn_box.add_theme_constant_override("h_separation", 8)
	turn_box.add_theme_constant_override("v_separation", 8)
	turn_box.anchor_left = 1.0
	turn_box.anchor_right = 1.0
	turn_box.anchor_top = 0.5
	turn_box.anchor_bottom = 0.5
	turn_box.offset_left = -124
	turn_box.offset_right = -12
	turn_box.offset_top = 90
	turn_box.visible = false
	root.add_child(turn_box)
	for spec in [["⟲", "turn", -1.0], ["⟳", "turn", 1.0], ["▲", "tilt", 1.0], ["▼", "tilt", -1.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(52, 52)
		b.add_theme_font_size_override("font_size", 24)
		b.focus_mode = Control.FOCUS_NONE
		var prop: String = spec[1]
		var dir: float = spec[2]
		b.button_down.connect(func() -> void: game.rig.set(prop, dir))
		b.button_up.connect(func() -> void: game.rig.set(prop, 0.0))
		turn_box.add_child(b)
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
	if GS.touch():
		# pressed by whichever finger lands on it (see _fire_input), not by the emulated mouse;
		# and moved clear of the zoom buttons, which it used to reach under
		fire_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fire_btn.offset_left = -250
		fire_btn.offset_right = -110
		fire_btn.offset_top = -330
		fire_btn.offset_bottom = -190
	fire_btn.visible = false
	root.add_child(fire_btn)


## The alarm button stands under the status panel, clear of every view's own controls.
func _build_alarm() -> void:
	alarm_btn = Button.new()
	alarm_btn.custom_minimum_size = Vector2(190, 46) if GS.touch() else Vector2(170, 38)
	alarm_btn.add_theme_font_size_override("font_size", 17 if GS.touch() else 14)
	alarm_btn.focus_mode = Control.FOCUS_NONE
	alarm_btn.position = Vector2(12, 240)
	_alarm_styles = [UiKit.sbox(Color(0.3, 0.05, 0.03, 0.85), Color(1.0, 0.35, 0.25), 2, 6, 6), UiKit.sbox(Color(0.75, 0.12, 0.08, 0.95), Color(1.0, 0.75, 0.6), 3, 6, 6)]
	alarm_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.85))
	# A real mouse presses it here; a finger — whichever lands on it, also while others aim or
	# steer — in _alarm_input. The mouse a finger is turned into is left out, or one tap would count
	# twice; the button still swallows it, so the map under it is not clicked.
	alarm_btn.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != InputEvent.DEVICE_ID_EMULATION:
			_alarm_press())
	alarm_btn.visible = not GS.realism
	root.add_child(alarm_btn)


## Where the left edge of the screen is free again: under the status panel and the alarm button.
func left_column_top() -> float:
	if hunt_btn != null and hunt_btn.visible:
		return hunt_btn.position.y + hunt_btn.size.y
	if alarm_btn != null and alarm_btn.visible:
		return alarm_btn.position.y + alarm_btn.size.y
	return _status_panel.position.y + _status_panel.size.y if _status_panel.visible else 0.0


func _alarm_press() -> void:
	SFX.play("click", -8.0)
	game.toggle_alarm()


func _update_alarm() -> void:
	if alarm_btn == null or GS.realism:
		return
	var on: bool = game.alarm
	alarm_btn.visible = game.view != "watch"
	alarm_btn.position = Vector2(12, _status_panel.position.y + _status_panel.size.y + 8.0)
	var key := "" if GS.touch() else " [%s]" % GS.key_label("alarm")
	alarm_btn.text = (GS.t("🔕 ОТБОЙ ТРЕВОГИ") if on else GS.t("📢 ТРЕВОГА")) + key
	# the button of a declared alarm beats like the siren
	var lit: bool = on and absf(sin(_t * 3.0)) > 0.5
	if alarm_btn.get_meta("lit", -1) != int(lit):
		alarm_btn.set_meta("lit", int(lit))
		for st in ["normal", "hover", "pressed"]:
			alarm_btn.add_theme_stylebox_override(st, _alarm_styles[1 if lit or st == "pressed" else 0])
	alarm_lbl.visible = on
	if on:
		var left := int(ceil(game.shelter_left()))
		alarm_lbl.text = GS.t("📢 ТРЕВОГА · люди в укрытиях") if left <= 0 else GS.t("📢 ТРЕВОГА · в укрытиях через %d с") % left


## Under the alarm button: a launcher the radar has just caught in the act, with the seconds it
## stays there. Pressed like the alarm (any finger), it opens the strike map on that launcher.
func _build_hunt() -> void:
	hunt_btn = Button.new()
	hunt_btn.custom_minimum_size = Vector2(250, 46) if GS.touch() else Vector2(230, 36)
	hunt_btn.add_theme_font_size_override("font_size", 16 if GS.touch() else 13)
	hunt_btn.focus_mode = Control.FOCUS_NONE
	hunt_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	for st in ["normal", "hover"]:
		hunt_btn.add_theme_stylebox_override(st, UiKit.sbox(Color(0.35, 0.2, 0.02, 0.88), Color(1.0, 0.75, 0.25), 2, 6, 6))
	hunt_btn.add_theme_stylebox_override("pressed", UiKit.sbox(Color(0.7, 0.45, 0.05, 0.95), Color(1.0, 0.9, 0.6), 3, 6, 6))
	hunt_btn.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != InputEvent.DEVICE_ID_EMULATION:
			_hunt_press())
	hunt_btn.visible = false
	root.add_child(hunt_btn)


## The launcher in the open that has the most seconds left and can still be hit, else "".
func hunt_target() -> String:
	if GS.realism or game.pvp != null or Net.role == "guest" or GS.training:
		return ""
	var best := ""
	var left := 0.0
	for id in Strikes.hot:
		var s := Strikes.site(GS.city_def(), String(id))
		if not s.is_empty() and Strikes.can_hunt(s) and float(Strikes.hot[id]) > left:
			best = String(id)
			left = float(Strikes.hot[id])
	return best


func _hunt_press() -> void:
	SFX.play("click", -8.0)
	open_strikes(hunt_target())


func _update_hunt() -> void:
	if hunt_btn == null:
		return
	var id := hunt_target()
	hunt_btn.visible = id != "" and game.view != "watch"
	if not hunt_btn.visible:
		return
	hunt_btn.position = Vector2(12, (alarm_btn.position.y + alarm_btn.size.y if alarm_btn.visible else _status_panel.position.y + _status_panel.size.y) + 8.0)
	var key := "" if GS.touch() else " [%s]" % GS.key_label("strikes")
	hunt_btn.text = GS.t("🎯 ПУСКОВАЯ «%s» · %d с") % [GS.t(String(Strikes.KINDS[id].short)), int(ceil(float(Strikes.hot[id])))] + key
	hunt_btn.modulate = Color(1, 1, 1, 0.75 + 0.25 * absf(sin(_t * 5.0)))


## The footage stands in the left column, under the alarm and launcher buttons.
func _place_bda() -> void:
	if bda == null or not bda.visible:
		return
	bda.size = Vector2(336, 189)
	bda.position = Vector2(12, left_column_top() + 10.0)


## The footage of strikes that have just landed — not in MaxRealism, which has no such screen.
func show_bda(results: Array) -> void:
	if bda == null or GS.realism or results.is_empty():
		return
	bda.play(results)
	_place_bda()


## The hunt button under a finger, like the alarm button.
func _hunt_input(event: InputEvent) -> bool:
	if hunt_btn == null or not (event is InputEventScreenTouch):
		return false
	var st := event as InputEventScreenTouch
	if not st.pressed or not hunt_btn.is_visible_in_tree() or get_tree().paused or _overlay != null:
		return false
	if not hunt_btn.get_global_rect().grow(6.0).has_point(st.position):
		return false
	_hunt_press()
	get_viewport().set_input_as_handled()
	return true


## A new achievement (scripts/core/achievements.gd): a toast, or the radio in MaxRealism.
func on_achievement(id: String) -> void:
	var a: Array = Achievements.info(id)
	var txt := GS.t("🏆 ДОСТИЖЕНИЕ: %s") % GS.t(String(a[2]))
	if game.autotest:
		print("UAD ACHIEVEMENT %s" % id)
	SFX.play("cash", -4.0)
	if GS.realism:
		if game.rl != null:
			game.rl.radio(txt + " — " + GS.t(String(a[3])), Color(1.0, 0.85, 0.35))
		return
	alert(txt, Color(1.0, 0.85, 0.35))
	log_event("%s %s — %s" % [String(a[1]), GS.t(String(a[2])), GS.t(String(a[3]))], Color(1.0, 0.85, 0.35))


## The radar caught a launcher in the act (game_controller.launch).
func on_launcher_hot(s: Dictionary) -> void:
	var nm := GS.t(String(s.short))
	if GS.realism:
		if game.rl != null:
			game.rl.radio(GS.t("Засечена пусковая «%s» — %d с на удар HIMARS или ATACMS с командного пункта.") % [nm, int(Strikes.HOT_TIME)], Color(1.0, 0.8, 0.35))
		return
	log_event(GS.t("🎯 Засечена пусковая «%s»: %d с, чтобы накрыть её HIMARS или ATACMS — %s") % [nm, int(Strikes.HOT_TIME), GS.t("кнопка «ПУСКОВАЯ»") if GS.touch() else "[%s]" % GS.key_label("strikes")], Color(1.0, 0.8, 0.35))


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
	if not GS.pvp.is_empty():
		loc_lbl.text += GS.t("  ·  сервер «%s»") % String(GS.pvp.def.name)
	elif GS.won:
		loc_lbl.text += GS.t("  ·  кампания пройдена ★")
	else:
		loc_lbl.text += GS.t("  ·  ночь %d из %d") % [GS.day, GS.CAMPAIGN_NIGHTS]
	order_lbl.visible = not GS.order.is_empty()
	if order_lbl.visible:
		order_lbl.text = "📋 " + Orders.text(GS.order)
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
		b.text = GS.t("%s%s\n%s · %d м\n%s") % [key, GS.t(String(def.short)), ammo, int(r), status]
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
	if game.rl != null:
		# MaxRealism: no banner across the screen, the call comes over the radio
		_alert_frame = Engine.get_process_frames()
		game.rl.radio(text, color.lerp(Color(0.9, 0.92, 0.86), 0.55))
		return
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
	if game.rl != null:
		if _alert_frame != Engine.get_process_frames():
			game.rl.radio(text, color.lerp(Color(0.9, 0.92, 0.86), 0.55))
		return
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
		# the time warp stays on the clock for as long as it runs
		if int(game.warp) > 1:
			phase_lbl.text += "  ▶▶ ×%d" % int(game.warp)
	if GS.base_found:
		detect_lbl.text = GS.t("⚠ БАЗА ОБНАРУЖЕНА — ожидайте удар")
		detect_lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 0.5 + 0.5 * absf(sin(_t * 5.0))))
	else:
		var hidden := 100.0 - clampf(GS.detection / 14.0 * 100.0, 0.0, 100.0)
		detect_lbl.text = GS.t("Маскировка базы: %d%%%s") % [int(hidden), GS.t(" · сеть") if GS.camo else ""]
		detect_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	_update_fires()
	_update_alarm()
	_update_hunt()
	_place_bda()
	_update_pvp()
	nv_rect.visible =(game.view == "base" and game.base_view.nv) or (game.view == "fpv" and game.fpv_view.nv)
	_update_target_info()
	if int(_t) != int(_t - delta) and game.pvp == null and not GS.training:
		for id in Achievements.scan(game.map.city):
			on_achievement(id)
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
	if _weapons_panel != null and _weapons_panel.visible:
		target_panel.offset_bottom = -(_weapons_panel.size.y + 18.0)
	var e = info.enemy
	var dist := Vector2(e.position.x - GS.base_pos.x, e.position.z - GS.base_pos.z).length()
	var w = game.weapons.get(game.selected_weapon)
	var in_r := ""
	if w != null:
		if not w.can_engage(e):
			in_r = GS.t(" · %s НЕ ПОРАЖАЕТ") % GS.t(String(w.def.short))
		else:
			in_r = GS.t(" · В ЗОНЕ ПОРАЖЕНИЯ") if w.in_range(e) else GS.t(" · вне зоны")
	target_lbl.text = GS.t("ЦЕЛЬ: %s → %s\nДальность %.1f км · высота %d м · %d%%%s") % [GS.t(String(e.def.name)), GS.t(e.target_name), dist * 0.001, int(e.position.y), int(100.0 * e.hp / e.max_hp), in_r]
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
	if not GS.realism:
		# MaxRealism: supplies and the feed are at the command post
		v.add_child(UiKit.button(GS.t("Магазин"), open_shop))
		v.add_child(UiKit.button(GS.t("Лента города [%s]") % GS.key_label("feed"), open_feed))
	v.add_child(UiKit.button(GS.t("Настройки"), _show_settings))
	var note := GS.t("Мир «%s». Автосохранение — каждое утро.") % GS.world_name
	if game.pvp != null:
		var pv = game.pvp
		v.add_child(UiKit.button(GS.t("Удар по противнику [%s]") % GS.key_label("strikes"), open_strikes))
		v.add_child(UiKit.button(GS.t("Закончить тест") if pv.bot else GS.t("Покинуть сервер"), func() -> void: game.main.leave_server()))
		note = GS.t("Сервер «%s» · вы защищаете город %s. Здесь ничего не сохраняется.") % [String(pv.def.name), pv.my_name()]
		if pv.bot:
			note += GS.t("\nЧерновик: за город %s играет бот.") % pv.enemy_name()
		else:
			note += GS.t("\nИгра на сервере не останавливается: пока вы в паузе, бой продолжается.")
	elif Net.role == "guest":
		v.add_child(UiKit.button(GS.t("Отключиться"), func() -> void: game.main.leave_session()))
		var hn := String(Net.world.get("n", "?"))
		note = GS.t("Вы в гостях у %s. Здесь ничего не сохраняется — ваши миры остаются как были.") % hn
		note += GS.t("\nСетевая игра не останавливается: пока вы в паузе, друзья продолжают.")
	else:
		if GS.world_id != "" and not GS.realism:
			if Net.role == "host":
				v.add_child(UiKit.button(GS.t("Закрыть мир для друзей"), _close_world))
			else:
				v.add_child(UiKit.button(GS.t("Открыть для друзей"), _open_world))
		v.add_child(UiKit.button(GS.t("Закончить обучение") if GS.training else GS.t("Сохранить и выйти в меню"), func() -> void: game.main.exit_to_menu()))
		if GS.training:
			note = GS.t("Учебный полигон: здесь ничего не сохраняется.")
		elif GS.realism:
			note += " " + GS.t("MaxRealism: %s — занять место или встать. Снабжение, удары и лента города — с командного пункта.") % GS.key_label("use")
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
	return Net.role == "guest" or (Net.role == "host" and (Net.players.size() > 1 or not Net.srv.is_empty()))


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
	if _fire_input(event) or _alarm_input(event) or _hunt_input(event):
		return
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
	if game.autotest and _recorder != null and is_instance_valid(_recorder):
		print("UAD RECORD: ok=%s crop=%s of %s file=%s" % [ok, _recorder.crop, _recorder.source, saved])
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
	# MaxRealism: the supply request of the command post, with deliveries by column
	var s: Shop = Supply.new() if GS.realism else Shop.new()
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


## The operational map of the launch sites (K): toggles. The raid is the host's, so are the strikes.
## It opens on `select`, else on a launcher in the open (a hunt), else where it picks itself.
func open_strikes(select := "") -> void:
	if game.game_over:
		return
	if select == "":
		select = hunt_target()
	if _overlay != null and _overlay is StrikeMap:
		if select != "" and (_overlay as StrikeMap)._sel != select:
			(_overlay as StrikeMap).select(select)
			return
		(_overlay as StrikeMap).close()
		return
	if game.pvp != null:
		# a match on a server: the strikes go at the other city
		if _overlay != null and _overlay is AttackMap:
			(_overlay as AttackMap).close()
			return
		_close_overlay()
		_set_paused(true)
		var am := AttackMap.new()
		am.game = game
		am.closed.connect(func() -> void:
			_overlay = null
			_set_paused(false))
		root.add_child(am)
		_overlay = am
		return
	if Net.role == "guest":
		alert(GS.t("Удары по точкам пуска наносит хозяин мира"), Color(1.0, 0.75, 0.35))
		return
	_close_overlay()
	_set_paused(true)
	var m := StrikeMap.new()
	m.game = game
	m._sel = select
	m.closed.connect(func() -> void:
		_overlay = null
		_set_paused(false))
	root.add_child(m)
	_overlay = m


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
	var landed: Array = r.get("strikes", [0, 0])
	if landed.size() == 2 and int(landed[1]) > 0:
		lines.append([GS.t("Наши удары по точкам пуска"), GS.t("%d из %d в цель") % [int(landed[0]), int(landed[1])], UiKit.NEON if int(landed[0]) > 0 else UiKit.AMBER])
	var rv: Dictionary = r.get("revenge", {})
	if not rv.is_empty():
		lines.append([GS.t("Ответный удар противника"), (GS.t("отражён") + " · +" + GS.fmt_money(int(rv.bonus))) if bool(rv.held) else GS.t("были прилёты"), UiKit.CYAN if bool(rv.held) else UiKit.RED])
	var aid: Array = r.get("aid", [])
	if not aid.is_empty():
		lines.append([GS.t("Помощь партнёров"), Strikes.aid_text(aid), UiKit.CYAN])
	var od: Dictionary = r.get("order", {})
	if not od.is_empty():
		lines.append([GS.t("Задание командования"), "+" + GS.fmt_money(int(od.reward)) if bool(od.done) else GS.t("не выполнено"), UiKit.CYAN if bool(od.done) else UiKit.AMBER])
	for ln in lines:
		var h := UiKit.hbox()
		var a := UiKit.label(ln[0], 18)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UiKit.label(ln[1], 18, ln[2]))
		v.add_child(h)
	if not od.is_empty():
		var ol := UiKit.label("📋 " + String(od.text), 13, Color(0.6, 0.9, 1.0) if bool(od.done) else Color(0.85, 0.75, 0.55))
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ol.custom_minimum_size = Vector2(520, 0)
		v.add_child(ol)
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
	v.add_child(UiKit.button(GS.t("Снабжение") if GS.realism else GS.t("Магазин"), shop_then_next))
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
	if int(s.get("strikes", 0)) > 0:
		var sl := UiKit.label(Strikes.totals(), 15, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(580, 0)
		v.add_child(sl)
	if int(r.get("award", 0)) > 0:
		v.add_child(UiKit.label(GS.t("Награда за операцию: +%s") % GS.fmt_money(int(r.award)), 22, UiKit.CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(GS.t("Налёты не прекращаются — оборону можно продолжать сколько угодно."), 16, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER))
	var to_report := func() -> void: show_morning(r)
	v.add_child(UiKit.button(GS.t("Продолжить оборону ▶"), to_report))
	v.add_child(UiKit.button(GS.t("Главное меню"), func() -> void: game.main.show_menu()))
	if game.autotest and not game.main._args.has("opened"):
		print("UAD: VICTORY ", r)
		get_tree().create_timer(0.5, true).timeout.connect(to_report)


## A match on a server is over: one of the cities has fallen.
func show_pvp_end(won: bool) -> void:
	_close_overlay()
	_set_paused(true)
	var pv = game.pvp
	var m := UiKit.modal(root, Vector2(600, 0))
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ПОБЕДА") if won else GS.t("ГОРОД ПАЛ"), 46, UiKit.NEON if won else UiKit.RED))
	var line := GS.t("Город %s разрушен. %s выстоял!") % [pv.enemy_name(), pv.my_name()] if won else GS.t("%s разрушен ударами города %s.") % [pv.my_name(), pv.enemy_name()]
	var ll := UiKit.label(line, 22, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.custom_minimum_size = Vector2(560, 0)
	v.add_child(ll)
	var s := GS.stats
	var st: Dictionary = pv.stats
	var txt := GS.t("Наш город цел на: %d%% · город противника: %d%%\nСбито целей: %d · прилётов по городу: %d\nВаших ударов: %d (%d ракет и дронов) · в цель: %d\nПотрачено на удары: %s · премии за попадания: %s") % [
		int(ceil(float(pv.hp[pv.side]))), int(ceil(float(pv.hp[1 - pv.side]))), int(s.kills), int(s.impacts), int(st.strikes), int(st.units), int(st.hits),
		GS.fmt_money(int(st.spent)), GS.fmt_money(int(st.bonus))]
	v.add_child(UiKit.label(txt, 18, Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
	if pv.bot:
		v.add_child(UiKit.button(GS.t("Сыграть тест ещё раз"), func() -> void: game.main.restart_server()))
		v.add_child(UiKit.button(GS.t("Вернуться к серверу"), func() -> void: game.main.leave_server()))
	else:
		v.add_child(UiKit.button(GS.t("К списку серверов"), func() -> void: game.main.leave_server()))
	if game.autotest:
		print("UAD PVP END: won=%s hp=%s stats=%s" % [won, str(pv.hp), str(st)])


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


## The hold-to-fire button answers the finger that is on it, whichever it is. As a plain Button it
## heard only the first finger on the screen (controls live on the emulated mouse), so it could
## not be pressed while another finger was already aiming.
func _fire_input(event: InputEvent) -> bool:
	if fire_btn == null or not GS.touch():
		return false
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _fire_touch < 0 and fire_btn.is_visible_in_tree() and not get_tree().paused and fire_btn.get_global_rect().get_center().distance_to(st.position) <= fire_btn.size.x * 0.56:
			_fire_touch = st.index
			fire_btn.modulate = Color(1.5, 1.3, 1.2)
			game.set_trigger(true)
			get_viewport().set_input_as_handled()
			return true
		if not st.pressed and st.index == _fire_touch:
			_fire_touch = -1
			fire_btn.modulate = Color(1, 1, 1)
			game.set_trigger(false)
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _fire_touch:
		get_viewport().set_input_as_handled()
		return true
	return false


## The alarm button under a finger: one tap of any finger, the first on the screen or not.
func _alarm_input(event: InputEvent) -> bool:
	if alarm_btn == null or not (event is InputEventScreenTouch):
		return false
	var st := event as InputEventScreenTouch
	if not st.pressed or not alarm_btn.is_visible_in_tree() or get_tree().paused or _overlay != null:
		return false
	if not alarm_btn.get_global_rect().grow(6.0).has_point(st.position):
		return false
	_alarm_press()
	get_viewport().set_input_as_handled()
	return true
