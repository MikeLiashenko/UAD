extends Control
## The "Play" screen, Minecraft-style, with two tabs:
##   Главная     — your own worlds: every defence is a save slot in local storage;
##   Мультиплеер — friends added by code (Net): who is online and which world they opened. A
##                 join request goes to the host, who accepts or declines it in their game.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Cities = preload("res://scripts/world/cities.gd")
const PingBars = preload("res://scripts/ui/ping_bars.gd")

## The tab shown when the screen opens again (back from creating a world, a declined request…).
static var last_tab := "home"

var main
var _tab_btns := {}
var _pages := {}

# --- Главная ---
var _list: VBoxContainer
var _selected := ""
var _rows := {}
var _play_btn: Button
var _del_btn: Button
var _confirm: Control
var _last_click := {}

# --- Мультиплеер ---
var _mp_list: VBoxContainer
var _mp_rows := {}
var _mp_entries := {}
var _mp_sel := ""
## What the list was last built from; rebuilt only when a world, its players or ping change.
var _mp_sig := "-"
var _mp_click := {}
var _scan_lbl: Label
var _nick: LineEdit
var _join_btn: Button
var _unfriend_btn: Button
var _t := 0.0
## Join request dialog: [root, status label, spinner, button].
var _req: Array = []
var _req_host := ""


## Radar sweep turning while the request waits for the host.
class Spinner extends Control:
	var spinning := true
	var _a := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(72, 72)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if spinning:
			_a = fmod(_a + delta * 3.0, TAU)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := 32.0
		var neon := Color(0.2, 1.0, 0.65)
		draw_circle(c, r, Color(0.0, 0.09, 0.05, 0.9))
		draw_arc(c, r, 0, TAU, 48, neon, 2.0)
		draw_arc(c, r * 0.5, 0, TAU, 32, Color(neon.r, neon.g, neon.b, 0.3), 1.0)
		if not spinning:
			return
		for i in 16:
			var a0 := _a - 0.9 * i / 16.0
			var a1 := _a - 0.9 * (i + 1) / 16.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r]), Color(neon.r, neon.g, neon.b, 0.4 * (1.0 - i / 16.0)))
		draw_line(c, c + Vector2.from_angle(_a) * r, Color(0.7, 1.0, 0.85), 2.0)


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.03, 0.55)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(780, 600))
	center.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var tabs := UiKit.hbox(8)
	v.add_child(tabs)
	for spec in [["home", GS.t("Главная")], ["mp", GS.t("Мультиплеер")]]:
		var b := Button.new()
		b.text = spec[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func() -> void:
			SFX.play("click", -8.0)
			_show_tab(spec[0]))
		tabs.add_child(b)
		_tab_btns[spec[0]] = b
	_pages["home"] = _build_home()
	_pages["mp"] = _build_mp()
	for k in _pages:
		v.add_child(_pages[k])
	Net.friends_changed.connect(_rebuild_mp)
	Net.request_sent.connect(_on_req_sent)
	Net.join_answered.connect(_on_req_answer)
	Net.connect_failed.connect(_on_req_failed)
	_rebuild()
	_show_tab(last_tab)


func _exit_tree() -> void:
	Net.watch_friends(false)
	_save_nick()


func _show_tab(t: String) -> void:
	last_tab = t
	for k in _pages:
		(_pages[k] as Control).visible = k == t
		(_tab_btns[k] as Button).button_pressed = k == t
	if t == "mp":
		Net.watch_friends(true)
		_rebuild_mp()
	else:
		Net.watch_friends(false)


# --- Главная: own worlds -----------------------------------------------------------------
func _build_home() -> Control:
	var v := UiKit.vbox(10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sub := UiKit.label(GS.t("Каждая оборона — отдельный мир. Прогресс сохраняется каждое утро."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = UiKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var grid := _grid()
	v.add_child(grid)
	_play_btn = UiKit.button(GS.t("Играть в выбранном мире"), _play, 370, 20)
	grid.add_child(_play_btn)
	grid.add_child(UiKit.button(GS.t("Создать новый мир"), func() -> void: main.show_create_world(), 370, 20))
	_del_btn = UiKit.button(GS.t("Удалить"), _ask_delete, 370, 18)
	grid.add_child(_del_btn)
	grid.add_child(UiKit.button(GS.t("Отмена"), func() -> void: main.show_menu(), 370, 18))
	return v


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var worlds := GS.list_worlds()
	if worlds.is_empty():
		_list.add_child(_empty_note(GS.t("Миров пока нет — создайте новый!")))
		_selected = ""
	else:
		if _selected == "" or not worlds.any(func(w) -> bool: return String(w.id) == _selected):
			_selected = String(worlds[0].id)
		for w in worlds:
			_list.add_child(_row(w))
	_update_buttons()


func _empty_note(text: String) -> Label:
	var e := UiKit.label(text, 20, Color(0.7, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	e.custom_minimum_size = Vector2(0, 120)
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return e


## A list row: a toggle button holding an icon and a column of text lines. Returns [button, hbox, column].
func _row_shell(icon_color: Color, letter: String) -> Array:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 78)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UiKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	b.add_child(h)
	var icon := ColorRect.new()
	icon.color = icon_color
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	if letter != "":
		var il := UiKit.label(letter, 28, Color(0, 0.08, 0.05), HORIZONTAL_ALIGNMENT_CENTER)
		il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		il.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		il.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(il)
	var col := UiKit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	return [b, h, col]


func _row(w: Dictionary) -> Control:
	var id := String(w.id)
	var loc := int(w.get("base_loc", GS.Loc.FIELD))
	var shell := _row_shell(GS.LOCATIONS[loc].color if GS.LOCATIONS.has(loc) else Color(0.5, 0.5, 0.5), "")
	var b: Button = shell[0]
	var col: VBoxContainer = shell[2]
	var wname := String(w.get("name", GS.t("Мир")))
	if bool(w.get("won", false)):
		wname += "  ★"
	col.add_child(UiKit.label(wname, 21, UiKit.NEON if bool(w.get("won", false)) else Color(1, 1, 1)))
	var diff := int(w.get("difficulty", 1))
	var cid := String(w.get("city_id", "kyiv"))
	var loc_name: String = GS.loc_name(loc, cid) if GS.LOCATIONS.has(loc) else "?"
	col.add_child(UiKit.label(GS.t("%s · День %d · %s · %s · %s") % [GS.t(String(GS.city_def(cid).name)), int(w.get("day", 1)), GS.fmt_money(int(w.get("money", 0))), loc_name, GS.t(String(GS.DIFFICULTY[clampi(diff, 0, 2)].name))], 14, Color(0.7, 1.0, 0.85)))
	col.add_child(UiKit.label(GS.t("Последняя игра: %s") % GS.fmt_date(int(w.get("last_played", 0))), 12, Color(0.5, 0.75, 0.65)))
	for c in col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_on_row.bind(id))
	_rows[id] = b
	return b


func _on_row(id: String) -> void:
	SFX.play("click", -8.0)
	var now := Time.get_ticks_msec()
	if _selected == id and now - int(_last_click.get(id, 0)) < 400:
		_play()
		return
	_last_click[id] = now
	_selected = id
	_update_buttons()


func _update_buttons() -> void:
	for id in _rows:
		(_rows[id] as Button).button_pressed = id == _selected
	_play_btn.disabled = _selected == ""
	_del_btn.disabled = _selected == ""


func _play() -> void:
	if _selected != "":
		main.play_world(_selected)


func _ask_delete() -> void:
	if _selected == "":
		return
	var w := GS.read_world(_selected)
	var m := UiKit.modal(self, Vector2(460, 0))
	_confirm = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Удалить мир?"), 30, UiKit.RED))
	var t := UiKit.label(GS.t("«%s» будет удалён навсегда. Это нельзя отменить.") % String(w.get("name", "")), 17, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(420, 0)
	v.add_child(t)
	v.add_child(UiKit.button(GS.t("Удалить"), _do_delete))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _confirm.queue_free()))


func _do_delete() -> void:
	GS.delete_world(_selected)
	_selected = ""
	_confirm.queue_free()
	_rebuild()


# --- Мультиплеер: friends' worlds ------------------------------------------------------------
func _build_mp() -> Control:
	var v := UiKit.vbox(10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sub := UiKit.label(GS.t("Добавьте друга по его коду — увидите, когда он в сети и какой мир открыл. Свой мир откройте в игре: пауза → «Открыть для друзей»."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(740, 0)
	v.add_child(sub)
	var idr := UiKit.hbox(10)
	v.add_child(idr)
	var nl := UiKit.label(GS.t("Ваш ник"), 16, UiKit.AMBER)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idr.add_child(nl)
	_nick = LineEdit.new()
	_nick.max_length = 16
	_nick.text = String(GS.settings.get("nick", ""))
	_nick.placeholder_text = Net.nick()
	_nick.custom_minimum_size = Vector2(230, 40)
	_nick.add_theme_font_size_override("font_size", 18)
	_nick.select_all_on_focus = true
	_nick.text_submitted.connect(func(_t: String) -> void:
		_save_nick()
		_nick.release_focus())
	_nick.focus_exited.connect(_save_nick)
	idr.add_child(_nick)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idr.add_child(gap)
	var cl := UiKit.label(GS.t("Ваш код: %s") % Net.fmt_code(Net.code()), 18, UiKit.NEON)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idr.add_child(cl)
	var copy := UiKit.button(GS.t("Копировать"), func() -> void: pass, 150, 16)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Net.fmt_code(Net.code()))
		copy.text = GS.t("Скопировано ✓")
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(copy):
				copy.text = GS.t("Копировать")))
	idr.add_child(copy)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 290)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_mp_list = UiKit.vbox(6)
	_mp_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mp_list)
	_scan_lbl = UiKit.label("", 14, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_scan_lbl)
	var grid := _grid()
	v.add_child(grid)
	_join_btn = UiKit.button(GS.t("Запросить подключение"), _request, 370, 20)
	grid.add_child(_join_btn)
	grid.add_child(UiKit.button(GS.t("Добавить друга"), _ask_add_friend, 370, 20))
	_unfriend_btn = UiKit.button(GS.t("Удалить из друзей"), _remove_friend, 370, 18)
	grid.add_child(_unfriend_btn)
	grid.add_child(UiKit.button(GS.t("Отмена"), func() -> void: main.show_menu(), 370, 18))
	return v


func _save_nick() -> void:
	if _nick == null:
		return
	var n := _nick.text.strip_edges()
	if n != String(GS.settings.get("nick", "")):
		GS.settings["nick"] = n
		GS.save_settings()


## Friends with an open world first, then the ones online, then the rest.
func _entries() -> Array:
	var out := []
	for f in Net.friends():
		var c := String(f.code)
		var info: Dictionary = Net.friend_info.get(c, {})
		var rank := 3
		if not info.is_empty():
			rank = 0 if not (info.w as Dictionary).is_empty() else (1 if bool(info.online) else 2)
		out.append({"key": c, "friend": f, "info": info, "rank": rank})
	out.sort_custom(func(a, b) -> bool:
		if int(a.rank) != int(b.rank):
			return int(a.rank) < int(b.rank)
		return String(a.friend.name).naturalnocasecmp_to(String(b.friend.name)) < 0)
	return out


func _bars(ping: int) -> int:
	return PingBars.for_ping(ping)


func _rebuild_mp() -> void:
	if _mp_list == null or not _pages["mp"].visible:
		return
	var entries := _entries()
	var sig := ""
	for e in entries:
		var info: Dictionary = e.info
		var w: Dictionary = info.get("w", {})
		sig += "%s|%s|%s|%s|%s|%s|%s|%s|%s;" % [e.key, e.friend.name, info.get("online", "?"), info.get("s", ""), w.get("world", ""), w.get("players", ""), w.get("day", ""), w.get("night", ""), _bars(int(info.get("ping", 0)))]
	if sig == _mp_sig:
		return
	_mp_sig = sig
	for c in _mp_list.get_children():
		c.queue_free()
	_mp_rows.clear()
	_mp_entries.clear()
	if entries.is_empty():
		_mp_list.add_child(_empty_note(GS.t("Друзей пока нет. Попросите у друга его код (он на этой же вкладке) и нажмите «Добавить друга».")))
	for e in entries:
		_mp_entries[e.key] = e
		_mp_list.add_child(_mp_row(e))
	if not _mp_entries.has(_mp_sel):
		_mp_sel = String(entries[0].key) if not entries.is_empty() else ""
	_update_mp_buttons()


func _mp_row(e: Dictionary) -> Control:
	var f: Dictionary = e.friend
	var info: Dictionary = e.info
	var w: Dictionary = info.get("w", {})
	var online := bool(info.get("online", false))
	var fnick := String(info.get("nick", f.name))
	var cid := String(w.get("city", "kyiv"))
	var icon_col := Color(0.3, 0.35, 0.33)
	if not w.is_empty():
		icon_col = Cities.get_def(cid).accent if Cities.has(cid) else UiKit.NEON
	elif online:
		icon_col = Color(0.2, 0.55, 0.4)
	var shell := _row_shell(icon_col, fnick.substr(0, 1).to_upper())
	var b: Button = shell[0]
	var hb: HBoxContainer = shell[1]
	var col: VBoxContainer = shell[2]
	var code_line := GS.t("Друг · код %s") % Net.fmt_code(String(f.code))
	if not w.is_empty():
		col.add_child(UiKit.label(String(w.get("world", GS.t("Мир"))), 21, Color(1, 1, 1)))
		var phase := GS.t("ночь, идёт налёт") if bool(w.get("night", false)) else GS.t("день")
		if not Cities.has(cid):
			cid = Cities.DEFAULT
		col.add_child(UiKit.label(GS.t("Хост: %s · %s · День %d · %s") % [fnick, GS.t(String(GS.city_def(cid).name)), int(w.get("day", 1)), phase], 14, Color(0.7, 1.0, 0.85)))
		col.add_child(UiKit.label(code_line, 12, Color(0.5, 0.75, 0.65)))
	elif online:
		col.add_child(UiKit.label(fnick, 21, Color(0.85, 1.0, 0.92)))
		var what := GS.t("в меню")
		match String(info.get("s", "")):
			"game":
				what = GS.t("играет один, мир не открыт")
			"guest":
				what = GS.t("в гостях у другого игрока")
		col.add_child(UiKit.label(GS.t("В сети · %s") % what, 14, Color(0.6, 0.9, 0.75)))
		col.add_child(UiKit.label(code_line, 12, Color(0.5, 0.7, 0.62)))
	else:
		col.add_child(UiKit.label(fnick, 21, Color(0.6, 0.66, 0.63)))
		col.add_child(UiKit.label(GS.t("Проверяем…") if info.is_empty() else GS.t("Не в сети"), 14, Color(0.55, 0.6, 0.58)))
		col.add_child(UiKit.label(code_line, 12, Color(0.45, 0.5, 0.48)))
	var right := UiKit.vbox(4)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(right)
	var pb := PingBars.new()
	pb.bars = _bars(int(info.get("ping", 0))) if online else -1
	pb.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(pb)
	if not w.is_empty():
		var full := int(w.get("players", 1)) >= int(w.get("max", Net.MAX_PLAYERS))
		right.add_child(UiKit.label("%d/%d" % [int(w.get("players", 1)), int(w.get("max", Net.MAX_PLAYERS))], 15, UiKit.AMBER if full else Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_RIGHT))
	for c in col.get_children() + right.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_on_mp_row.bind(String(e.key)))
	_mp_rows[e.key] = b
	return b


func _on_mp_row(key: String) -> void:
	SFX.play("click", -8.0)
	var now := Time.get_ticks_msec()
	if _mp_sel == key and now - int(_mp_click.get(key, 0)) < 400:
		_request()
		return
	_mp_click[key] = now
	_mp_sel = key
	_update_mp_buttons()


func _selected_world() -> Dictionary:
	var e: Dictionary = _mp_entries.get(_mp_sel, {})
	var info: Dictionary = e.get("info", {})
	return info.get("w", {})


func _update_mp_buttons() -> void:
	for k in _mp_rows:
		(_mp_rows[k] as Button).button_pressed = k == _mp_sel
	var w := _selected_world()
	_join_btn.disabled = w.is_empty() or int(w.get("players", 1)) >= int(w.get("max", Net.MAX_PLAYERS))
	_unfriend_btn.disabled = not _mp_entries.has(_mp_sel)


# --- Join request -------------------------------------------------------------------------------
func _request() -> void:
	var w := _selected_world()
	if w.is_empty() or not _req.is_empty():
		return
	_save_nick()
	_req_host = String(w.get("n", "?"))
	var m := UiKit.modal(self, Vector2(480, 0))
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ЗАПРОС НА ПОДКЛЮЧЕНИЕ"), 28, UiKit.NEON))
	v.add_child(UiKit.label(GS.t("«%s» · хост %s") % [String(w.get("world", "")), _req_host], 17, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	var sp := Spinner.new()
	v.add_child(sp)
	var st := UiKit.label(GS.t("Отправляем запрос…"), 16, Color(0.7, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(440, 48)
	v.add_child(st)
	var btn := UiKit.button(GS.t("Отмена"), _close_request)
	v.add_child(btn)
	_req = [m[0], st, sp, btn]
	Net.request_join(_mp_sel)


func _close_request() -> void:
	if Net.role == "joining":
		Net.close()
	if not _req.is_empty():
		(_req[0] as Control).queue_free()
	_req = []


func _on_req_sent() -> void:
	if _req.is_empty():
		return
	(_req[1] as Label).text = GS.t("Запрос отправлен. Ждём, пока %s его примет…") % _req_host


func _on_req_answer(ok: bool, info: Dictionary) -> void:
	if _req.is_empty():
		return
	if ok:
		(_req[1] as Label).text = GS.t("%s принял запрос! Загружаем мир…") % _req_host
		(_req[1] as Label).add_theme_color_override("font_color", UiKit.NEON)
		(_req[3] as Button).disabled = true
		SFX.play("click", -2.0)
		get_tree().create_timer(0.6).timeout.connect(func() -> void: main.join_world(info))
	else:
		_req_failed(Net.reason_text(String(info.get("reason", "no")), _req_host))


func _on_req_failed(reason: String) -> void:
	if not _req.is_empty():
		_req_failed(reason)


func _req_failed(text: String) -> void:
	SFX.play("alert", -10.0)
	(_req[1] as Label).text = text
	(_req[1] as Label).add_theme_color_override("font_color", UiKit.RED)
	(_req[2] as Spinner).spinning = false
	(_req[3] as Button).text = GS.t("Назад")


# --- Friends -----------------------------------------------------------------------------------
func _ask_add_friend() -> void:
	var m := UiKit.modal(self, Vector2(480, 0))
	_confirm = m[0]
	var box := _confirm
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ДОБАВИТЬ ДРУГА"), 28, UiKit.NEON))
	var hint := UiKit.label(GS.t("Введите код друга — он показан у него на вкладке «Мультиплеер»."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(440, 0)
	v.add_child(hint)
	var a := LineEdit.new()
	a.max_length = 12
	a.placeholder_text = "ABCD-EFGH"
	a.alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.custom_minimum_size = Vector2(440, 50)
	a.add_theme_font_size_override("font_size", 26)
	v.add_child(a)
	var st := UiKit.label("", 15, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(440, 0)
	v.add_child(st)
	var add_btn := UiKit.button(GS.t("Добавить"), func() -> void: pass)
	var add := func() -> void:
		add_btn.disabled = true
		st.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))
		st.text = GS.t("Ищем игрока…")
		Net.add_friend(a.text, func(ok: bool, text: String) -> void:
			if not is_instance_valid(box):
				return
			if ok:
				_mp_sel = Net.parse_code(a.text)
				_mp_sig = "-"
				box.queue_free()
				_rebuild_mp()
			else:
				add_btn.disabled = false
				st.add_theme_color_override("font_color", UiKit.RED)
				st.text = text)
	add_btn.pressed.connect(add)
	a.text_submitted.connect(func(_t: String) -> void:
		if not add_btn.disabled:
			add.call())
	v.add_child(add_btn)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: box.queue_free()))
	a.grab_focus.call_deferred()


func _remove_friend() -> void:
	if not _mp_entries.has(_mp_sel):
		return
	Net.remove_friend(_mp_sel)
	_mp_sig = "-"
	_rebuild_mp()


func _process(delta: float) -> void:
	_t += delta
	if _scan_lbl != null and _pages["mp"].visible:
		var dots: String = ["◜", "◝", "◞", "◟"][int(_t * 6.0) % 4]
		var list := Net.friends()
		var online := 0
		for f in list:
			if bool(Net.friend_info.get(String(f.code), {}).get("online", false)):
				online += 1
		_scan_lbl.text = GS.t("%s Друзей в сети: %d из %d") % [dots, online, list.size()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not _req.is_empty():
			_close_request()
		elif _confirm != null and is_instance_valid(_confirm):
			_confirm.queue_free()
		else:
			main.show_menu()
