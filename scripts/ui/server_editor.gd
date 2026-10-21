extends Control
## The screen of one of the player's own servers: its name, the rules of the match, its two
## cities (each opens in the city editor), a test against the bot and publishing. Everything is
## kept as a draft on this device (ServerDef) the moment it changes; a published server is sent
## to the database again with "Update".

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const ServerDef = preload("res://scripts/core/server_def.gd")
const CityPlan = preload("res://scripts/ui/city_plan.gd")
const CitiesMenu = preload("res://scripts/ui/cities_menu.gd")

var main
var def := {}
var _name: LineEdit
var _status: Label
var _pub_btn: Button
var _unpub_btn: Button
var _arsenal_btns := {}
var _confirm: Control
var _busy := false


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.bleed(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.03, 0.6)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(1160, 0))
	center.add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var head := UiKit.hbox(12)
	v.add_child(head)
	var title := UiKit.glow_label(GS.t("СЕРВЕР"), 30, UiKit.NEON)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_name = LineEdit.new()
	_name.max_length = ServerDef.NAME_MAX
	_name.text = String(def.name)
	_name.add_theme_font_size_override("font_size", 22)
	_name.custom_minimum_size = Vector2(0, 44)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.select_all_on_focus = true
	_name.text_submitted.connect(func(_t: String) -> void: _name.release_focus())
	_name.focus_exited.connect(_save_name)
	head.add_child(_name)
	var h := UiKit.hbox(14)
	v.add_child(h)
	# --- the two cities
	for side in 2:
		h.add_child(_city_card(side))
		if side == 0:
			var vs := UiKit.glow_label("⚔", 40, UiKit.AMBER)
			vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(vs)
	# --- the rules
	var rules := UiKit.vbox(6)
	rules.custom_minimum_size = Vector2(430, 0)
	h.add_child(rules)
	rules.add_child(UiKit.label(GS.t("ПРАВИЛА МАТЧА"), 16, UiKit.AMBER))
	_choice(rules, GS.t("Стартовый бюджет"), "money", ServerDef.MONEY)
	_choice(rules, GS.t("Доход в минуту"), "income", ServerDef.INCOME)
	_choice(rules, GS.t("Прочность городов"), "armor", ServerDef.ARMOR)
	_choice(rules, GS.t("Между городами"), "dist", ServerDef.DIST)
	_choice(rules, GS.t("Игроков"), "team", ServerDef.TEAM)
	rules.add_child(UiKit.label(GS.t("Чем можно бить"), 14, Color(0.6, 0.85, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	rules.add_child(grid)
	for a in ServerDef.ARSENAL:
		var w := String(a[0])
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(103, 38)
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		b.text = GS.t(ServerDef.short_name(w))
		b.tooltip_text = "%s · %s" % [GS.t(String(GS.ENEMIES[w].name)), GS.fmt_money(int(a[1]))]
		b.button_pressed = (def.rules.arsenal as Array).has(w)
		b.pressed.connect(_toggle_weapon.bind(w))
		grid.add_child(b)
		_arsenal_btns[w] = b
	_status = UiKit.label("", 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1100, 40)
	v.add_child(_status)
	var row := UiKit.hbox(8)
	v.add_child(row)
	_pub_btn = UiKit.button("", _publish, 330, 20)
	row.add_child(_pub_btn)
	_unpub_btn = UiKit.button(GS.t("Снять с публикации"), _unpublish, 260, 18)
	row.add_child(_unpub_btn)
	row.add_child(UiKit.button(GS.t("Удалить сервер"), _ask_delete, 240, 18))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	row.add_child(UiKit.button(GS.t("К списку серверов"), _back, 260, 18))
	_update_status()


func _city_card(side: int) -> Control:
	var v := UiKit.vbox(6)
	var city: Dictionary = def.cities[side]
	var nl := UiKit.label(String(city.name), 21, UiKit.NEON if side == 0 else UiKit.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	nl.custom_minimum_size = Vector2(290, 0)
	nl.clip_text = true
	v.add_child(nl)
	var plan := CityPlan.new()
	plan.custom_minimum_size = Vector2(290, 290)
	plan.movable = false
	plan.names = false
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(plan)
	plan.set_data(city)
	var info := UiKit.label(GS.t("%d × %d км · районов %d · объектов %d") % [int(float(city.size) / 500.0), int(float(city.size) / 500.0), (city.districts as Array).size(), (city.objects as Array).size()], 13, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(info)
	v.add_child(UiKit.button(GS.t("Редактор города"), func() -> void: _leave_to(func() -> void: main.show_city_editor(def, side)), 290, 18))
	v.add_child(UiKit.button(GS.t("Взять из моих городов"), _take_city.bind(side), 290, 16))
	v.add_child(UiKit.button(GS.t("▶ Тест с ботом"), func() -> void: _leave_to(func() -> void: main.start_server(def, side, true)), 290, 18))
	return v


## One rule: its name and the choices in a row.
func _choice(parent: Control, title: String, key: String, options: Array) -> void:
	var row := UiKit.hbox(5)
	parent.add_child(row)
	var l := UiKit.label(title, 14, Color(0.7, 1.0, 0.85))
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var btns := []
	for o in options:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.text = GS.t(String(o[1]))
		b.button_pressed = is_equal_approx(float(def.rules[key]), float(o[0]))
		row.add_child(b)
		btns.append(b)
	for i in btns.size():
		(btns[i] as Button).pressed.connect(func() -> void:
			SFX.play("click", -8.0)
			def.rules[key] = options[i][0]
			for k in btns.size():
				(btns[k] as Button).button_pressed = k == i
			_changed())


## One of the cities drawn in the map editor becomes the city of this side (a copy of it).
func _take_city(side: int) -> void:
	_save_name()
	_confirm = CitiesMenu.pick(self, func(e: Dictionary) -> void:
		def.cities[side] = (e.city as Dictionary).duplicate(true)
		_changed()
		main.show_server(def))


func _toggle_weapon(w: String) -> void:
	SFX.play("click", -8.0)
	var list := []
	for a in ServerDef.ARSENAL:
		if (_arsenal_btns[String(a[0])] as Button).button_pressed:
			list.append(String(a[0]))
	if list.is_empty():
		# a match with nothing to fire is no match
		(_arsenal_btns[w] as Button).button_pressed = true
		return
	def.rules.arsenal = list
	_changed()


func _save_name() -> void:
	var n := ServerDef.CustomCity.clean_name(_name.text, ServerDef.NAME_MAX)
	if n == "":
		n = String(def.name)
	_name.text = n
	if n != String(def.name):
		def.name = n
		_changed()


## The draft is written at once; what is in the database stays as it was until "Update".
func _changed() -> void:
	def["dirty"] = bool(def.get("published", false))
	ServerDef.save(def)
	_update_status()


func _update_status() -> void:
	var published := bool(def.get("published", false))
	_unpub_btn.visible = published
	_pub_btn.disabled = _busy
	if not published:
		_pub_btn.text = GS.t("Опубликовать сервер")
		_status.text = GS.t("Черновик: сервер виден только вам. Нарисуйте города, сыграйте тест с ботом за каждую сторону — и публикуйте. Серверы пока бесплатны.")
		_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.75))
	elif bool(def.get("dirty", false)):
		_pub_btn.text = GS.t("Обновить на сервере")
		_status.text = GS.t("Опубликован, но изменён: игроки видят прежнюю версию, пока вы не нажмёте «Обновить на сервере».")
		_status.add_theme_color_override("font_color", UiKit.AMBER)
	else:
		_pub_btn.text = GS.t("Обновить на сервере")
		_status.text = GS.t("Опубликован: сервер в общем списке, код %s. До %d игроков на город.") % [Net.fmt_code(String(def.id)), int(def.rules.team)]
		_status.add_theme_color_override("font_color", UiKit.NEON)


func _note(text: String, col: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", col)


func _publish() -> void:
	if _busy:
		return
	_save_name()
	_busy = true
	_pub_btn.disabled = true
	_note(GS.t("Отправляем сервер…"), Color(0.7, 1.0, 0.85))
	Net.srv_publish(def, func(ok: bool, why: String) -> void:
		if not is_instance_valid(self):
			return
		_busy = false
		if ok:
			def["published"] = true
			def["dirty"] = false
			ServerDef.save(def)
			SFX.play("cash", -6.0)
			_update_status()
		else:
			_pub_btn.disabled = false
			_note(why, UiKit.RED))


func _unpublish() -> void:
	if _busy:
		return
	_busy = true
	_note(GS.t("Снимаем с публикации…"), Color(0.7, 1.0, 0.85))
	Net.srv_unpublish(String(def.id), func(ok: bool, why: String) -> void:
		if not is_instance_valid(self):
			return
		_busy = false
		if ok:
			def["published"] = false
			def["dirty"] = false
			ServerDef.save(def)
			_update_status()
		else:
			_note(why, UiKit.RED))


func _ask_delete() -> void:
	var m := UiKit.modal(self, Vector2(480, 0))
	_confirm = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Удалить сервер?"), 30, UiKit.RED))
	var t := UiKit.label(GS.t("«%s» и оба его города будут удалены навсегда. Это нельзя отменить.") % String(def.name), 17, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 0)
	v.add_child(t)
	v.add_child(UiKit.button(GS.t("Удалить"), _do_delete))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _confirm.queue_free()))


func _do_delete() -> void:
	if bool(def.get("published", false)):
		Net.srv_unpublish(String(def.id), func(_ok: bool, _why: String) -> void: pass)
	ServerDef.remove(String(def.id))
	_back()


func _leave_to(go: Callable) -> void:
	_save_name()
	go.call()


func _back() -> void:
	_save_name()
	main.show_servers()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _confirm != null and is_instance_valid(_confirm):
			_confirm.queue_free()
		else:
			_back()
