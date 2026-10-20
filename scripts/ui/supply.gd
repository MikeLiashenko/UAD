extends "res://scripts/ui/shop.gd"
## MaxRealism: the supply request at the command post, in place of the shop. A plain terminal
## — no neon, the arrows and Enter work as well as the mouse — and nothing appears out of thin
## air: a system, missiles or a camouflage net are ordered, paid for and brought by a supply
## column some seconds later (scripts/game/realism.gd: order / orders). Repairs and fire crews
## are work started on the spot. There is no aviation here: the mode is fought from the ground.

const INK := Color(0.9, 0.93, 0.88)
const DIM := Color(0.62, 0.68, 0.62)
const AMBER := Color(1.0, 0.78, 0.35)
const LINE := Color(0.62, 0.68, 0.62, 0.3)

## The first button that can be pressed (the arrows start from it) and the one to give the
## focus back to after the list is rebuilt: "row title|button text".
var _first: Button
var _refocus := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := UiKit.full_rect(ColorRect.new()) as ColorRect
	bg.color = Color(0.035, 0.045, 0.04, 0.985)
	add_child(bg)
	var m := UiKit.full_rect(MarginContainer.new()) as MarginContainer
	m.add_theme_constant_override("margin_left", 70)
	m.add_theme_constant_override("margin_right", 70)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 24)
	add_child(m)
	var v := UiKit.vbox(8)
	m.add_child(v)
	var top := UiKit.hbox()
	v.add_child(top)
	var title := UiKit.label(GS.t("ЗАЯВКА НА СНАБЖЕНИЕ"), 26, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = UiKit.label("", 24, INK)
	top.add_child(_money)
	var rl = game.rl
	var note := UiKit.label(GS.t("Заказанное привозит колонна снабжения: систему — через %d с, ракеты — через %d с. Деньги списываются сразу. Стрелки и Enter — выбрать и заказать.") % [int(rl.DELIVERY.weapon), int(rl.DELIVERY.ammo)], 14, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", UiKit.sbox(Color(0.05, 0.06, 0.055), LINE, 0, 0, 4))
	for sb in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(sb, UiKit.sbox(Color(DIM.r, DIM.g, DIM.b, 0.55 if sb == "grabber" else 0.8), LINE, 0, 0, 4))
	v.add_child(scroll)
	_list = UiKit.vbox(3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var close_btn := _flat(Button.new())
	close_btn.text = GS.t("Закрыть [%s]") % GS.key_label("shop") if not GS.touch() else GS.t("✕ Закрыть")
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(close)
	v.add_child(close_btn)
	_rebuild()


## A button of the terminal: a thin frame, no glow.
func _flat(b: Button) -> Button:
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", UiKit.sbox(Color(0.07, 0.085, 0.075), LINE, 1, 2, 6))
	b.add_theme_stylebox_override("hover", UiKit.sbox(Color(0.1, 0.12, 0.105), DIM, 1, 2, 6))
	b.add_theme_stylebox_override("pressed", UiKit.sbox(Color(0.16, 0.19, 0.16), INK, 1, 2, 6))
	b.add_theme_stylebox_override("disabled", UiKit.sbox(Color(0.05, 0.06, 0.055), Color(LINE.r, LINE.g, LINE.b, 0.15), 1, 2, 6))
	b.add_theme_stylebox_override("focus", UiKit.sbox(Color(0, 0, 0, 0), AMBER, 2, 2, 6))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", Color(DIM.r, DIM.g, DIM.b, 0.5))
	return b


func _section(text: String) -> void:
	var l := UiKit.label(text, 14, AMBER)
	l.custom_minimum_size = Vector2(0, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _row(title: String, desc: String, price_text: String, buttons: Array) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.055, 0.068, 0.06), LINE, 1, 0, 8))
	_list.add_child(p)
	var h := UiKit.hbox(14)
	p.add_child(h)
	var info := UiKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(UiKit.label(title, 17, INK))
	var d := UiKit.label(desc, 13, DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	var price := UiKit.label(price_text, 16, INK if not buttons.is_empty() else AMBER)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(price)
	for b in buttons:
		var btn := b as Button
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(btn)
		var key := title + "|" + btn.text
		btn.pressed.connect(func() -> void: _refocus = key)
		if btn.disabled:
			continue
		if _first == null:
			_first = btn
		if key == _refocus:
			btn.grab_focus.call_deferred()


func _buy_btn(text: String, enabled: bool, cb: Callable) -> Button:
	var b := _flat(Button.new())
	b.text = text
	b.custom_minimum_size = Vector2(118, 36)
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_money.text = GS.t("Бюджет: ") + GS.fmt_money(GS.money)
	_money.add_theme_color_override("font_color", INK if GS.money >= 0 else AMBER)
	_first = null
	var rl = game.rl
	for spec in GS.WEAPON_CLASSES:
		_section(GS.t(String(spec[1])))
		for id in GS.WEAPON_ORDER:
			var def: Dictionary = GS.WEAPONS[id]
			if String(def.get("class", "gun")) != String(spec[0]):
				continue
			var desc := GS.t("%s\nДальность %.1f км · %s") % [GS.t(String(def.desc)), float(def.range) * 0.001, _eff_text(def)]
			if GS.unlocked.get(id, false):
				_row(def.name, desc, GS.t("На позиции"), [])
			elif rl.on_order("weapon", id) > 0:
				_row(def.name, desc, GS.t("В пути · %d с") % int(ceil(rl.order_eta("weapon", id))), [])
			else:
				var price := int(def.unlock)
				_row(def.name, desc, GS.fmt_money(price), [_buy_btn(GS.t("Заказать"), GS.money >= price, _buy_weapon.bind(id))])
	_section(GS.t("РАКЕТЫ И ДРОНЫ"))
	var any_ammo := false
	for id in GS.AMMO_ORDER:
		if not GS.unlocked.get(id, false):
			continue
		any_ammo = true
		var def: Dictionary = GS.WEAPONS[id]
		var price := int(def.missile_price)
		var title := GS.t("Дрон %s") % GS.t(String(def.short)) if String(def.kind) == "drone" else GS.t("Ракета %s") % GS.t(String(def.short))
		var bulk := 4 if String(def.kind) != "drone" else 10
		var stock := GS.t("На позиции: %d шт.") % int(GS.ammo.get(id, 0))
		var coming: int = rl.on_order("ammo", id)
		if coming > 0:
			stock += GS.t(" · в пути: %d, через %d с") % [coming, int(ceil(rl.order_eta("ammo", id)))]
		_row(title, stock, GS.fmt_money(price) + GS.t(" / шт."), [
			_buy_btn("+1", GS.money >= price, _buy_ammo.bind(id, 1)),
			_buy_btn("+%d" % bulk, GS.money >= price * bulk, _buy_ammo.bind(id, bulk)),
		])
	if not any_ammo:
		_row(GS.t("Боекомплект"), GS.t("Ракеты заказывают к тем комплексам, что уже стоят на позиции."), "", [])
	_section(GS.t("УСИЛЕНИЕ БАЗЫ"))
	if GS.camo:
		_row(GS.t("Маскировочная сеть"), GS.t("Установлена: разведчикам заметно труднее найти базу."), GS.t("На позиции"), [])
	elif rl.on_order("camo", "camo") > 0:
		_row(GS.t("Маскировочная сеть"), GS.t("Снижает заметность базы для разведчиков на 45%."), GS.t("В пути · %d с") % int(ceil(rl.order_eta("camo", "camo"))), [])
	else:
		_row(GS.t("Маскировочная сеть"), GS.t("Снижает заметность базы для разведчиков на 45%."), GS.fmt_money(GS.CAMO_PRICE), [_buy_btn(GS.t("Заказать"), GS.money >= GS.CAMO_PRICE, _buy_camo)])
	var hp_txt := GS.t("Состояние базы: %d%%. Ремонт +30%%.") % int(GS.base_hp)
	_row(GS.t("Ремонт базы"), hp_txt, GS.fmt_money(GS.REPAIR_PRICE), [_buy_btn(GS.t("Ремонт"), GS.money >= GS.REPAIR_PRICE and GS.base_hp < 100.0, _buy_repair)])
	var city_txt := GS.t("Состояние города: %d%%. Бригады восстанавливают +%d%%.") % [int(GS.city), int(GS.CITY_REPAIR_GAIN)]
	_row(GS.t("Восстановление кварталов"), city_txt, GS.fmt_money(GS.CITY_REPAIR_PRICE), [_buy_btn(GS.t("Ремонт"), GS.money >= GS.CITY_REPAIR_PRICE and GS.city < 100.0, _buy_city_repair)])
	var crews: int = 2 + int(GS.crews)
	var crew_txt := GS.t("В службе %d расчётов. Тушат пожары и отстраивают разрушенные дома — чем больше расчётов, тем быстрее.") % crews
	if GS.crews >= GS.CREW_MAX:
		_row(GS.t("Пожарный расчёт"), crew_txt, GS.t("Полный штат"), [])
	else:
		_row(GS.t("Пожарный расчёт"), crew_txt, GS.fmt_money(GS.CREW_PRICE), [_buy_btn(GS.t("Нанять"), GS.money >= GS.CREW_PRICE, _buy_crew)])


## The arrows start from the first row that can be ordered; the list opens at its top.
func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventKey and event.pressed and get_viewport().gui_get_focus_owner() == null:
		if (event.is_action("ui_down") or event.is_action("ui_up")) and _first != null and is_instance_valid(_first):
			get_viewport().set_input_as_handled()
			_first.grab_focus()


func _buy_weapon(id: String) -> void:
	if game.rl.order("weapon", id, 1):
		_bought()


func _buy_ammo(id: String, n: int) -> void:
	if game.rl.order("ammo", id, n):
		_bought()


func _buy_camo() -> void:
	if game.rl.order("camo", "camo", 1):
		_bought()
