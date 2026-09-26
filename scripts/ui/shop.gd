extends Control
## Military shop: unlock AA systems, buy interceptor missiles, camouflage and repairs.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal closed

var game
var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.7)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(820, 560))
	center.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var top := UiKit.hbox()
	v.add_child(top)
	var title := UiKit.glow_label(GS.t("ВОЕННЫЙ МАГАЗИН"), 32, UiKit.NEON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = UiKit.label("", 26, UiKit.NEON)
	top.add_child(_money)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = UiKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	v.add_child(UiKit.button(GS.t("Закрыть [%s]") % GS.key_label("shop"), close))
	_rebuild()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or GS.action_of(k) in ["shop", "pause"]:
			get_viewport().set_input_as_handled()
			close()


func _section(text: String) -> void:
	var l := UiKit.label(text, 16, UiKit.AMBER)
	_list.add_child(l)


func _row(title: String, desc: String, price_text: String, buttons: Array) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.02, 0.08, 0.06, 0.8), UiKit.NEON_DIM, 1, 6, 8))
	_list.add_child(p)
	var h := UiKit.hbox(12)
	p.add_child(h)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(UiKit.label(title, 19, Color(0.9, 1.0, 0.95)))
	var d := UiKit.label(desc, 13, Color(0.6, 0.85, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	var price := UiKit.label(price_text, 18, UiKit.AMBER)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(price)
	for b in buttons:
		(b as Button).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)


func _buy_btn(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 40)
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _eff_text(def: Dictionary) -> String:
	var parts := []
	for t in ["shahed", "cruise", "ballistic"]:
		var e: float = def.eff[t]
		var mark := "✔" if e >= 0.8 else ("±" if e > 0.2 else "✖")
		parts.append("%s %s" % [GS.t(String(GS.ENEMIES[t].name)), mark])
	return " · ".join(parts)


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_money.text = GS.fmt_money(GS.money)
	# the roster is long, so it is split into the four classes of the battery
	for spec in GS.WEAPON_GROUPS:
		_section(GS.t(String(spec[1])))
		for id in GS.WEAPON_ORDER:
			var def: Dictionary = GS.WEAPONS[id]
			if String(def.get("group", "manual")) != String(spec[0]):
				continue
			var owned: bool = GS.unlocked.get(id, false)
			var desc := GS.t("%s\nДальность %.1f км · %s") % [GS.t(String(def.desc)), float(def.range) * 0.005, _eff_text(def)]
			if owned:
				_row(def.name, desc, GS.t("В строю"), [])
			else:
				var price := int(def.unlock)
				_row(def.name, desc, GS.fmt_money(price), [_buy_btn(GS.t("Купить"), GS.money >= price, _buy_weapon.bind(id))])
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
		_row(title, GS.t("В наличии: %d шт.") % int(GS.ammo.get(id, 0)), GS.fmt_money(price) + GS.t(" / шт."), [
			_buy_btn("+1", GS.money >= price, _buy_ammo.bind(id, 1)),
			_buy_btn("+%d" % bulk, GS.money >= price * bulk, _buy_ammo.bind(id, bulk)),
		])
	if not any_ammo:
		_row(GS.t("Боекомплект"), GS.t("Купите ЗРК или дроны — их ракеты появятся здесь."), "", [])
	_section(GS.t("АВИАЦИЯ"))
	if not GS.unlocked.get("f16", false):
		_row(GS.t("Звено F-16"), GS.t("Истребитель-перехватчик для вылетов над городом [%s]: пушка M61, ракеты AIM-9X и AIM-120. Бейте крылатые ракеты и шахеды на подлёте — и следите, куда падают обломки.") % GS.key_label("fighter"), GS.fmt_money(GS.F16_PRICE), [_buy_btn(GS.t("Купить"), GS.money >= GS.F16_PRICE, _buy_f16)])
	else:
		_row(GS.t("Звено F-16"), GS.t("В строю. Вылет — %s, между вылетами заправка и подвеска.") % GS.key_label("fighter"), GS.t("В строю"), [])
		for id in ["aim9", "aim120"]:
			var def: Dictionary = GS.WEAPONS[id]
			var price := int(def.missile_price)
			_row(GS.t("Ракета %s") % String(def.short), GS.t("%s В наличии: %d шт.") % [GS.t(String(def.desc)), int(GS.ammo.get(id, 0))], GS.fmt_money(price) + GS.t(" / шт."), [
				_buy_btn("+1", GS.money >= price, _buy_ammo.bind(id, 1)),
				_buy_btn("+4", GS.money >= price * 4, _buy_ammo.bind(id, 4)),
			])
	_section(GS.t("УСИЛЕНИЕ БАЗЫ"))
	if GS.camo:
		_row(GS.t("Маскировочная сеть"), GS.t("Установлена: разведчикам заметно труднее найти базу."), GS.t("Есть"), [])
	else:
		_row(GS.t("Маскировочная сеть"), GS.t("Снижает заметность базы для разведчиков на 45%."), GS.fmt_money(GS.CAMO_PRICE), [_buy_btn(GS.t("Купить"), GS.money >= GS.CAMO_PRICE, _buy_camo)])
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


func _bought() -> void:
	SFX.play("cash", -4.0)
	_rebuild.call_deferred()


func _buy_weapon(id: String) -> void:
	if game.purchase_weapon(id):
		_bought()


func _buy_ammo(id: String, n: int) -> void:
	if GS.buy_ammo(id, n):
		_bought()


func _buy_f16() -> void:
	if GS.spend(GS.F16_PRICE):
		GS.unlocked["f16"] = true
		GS.ammo["aim9"] = int(GS.ammo.get("aim9", 0)) + 4
		GS.ammo["aim120"] = int(GS.ammo.get("aim120", 0)) + 2
		GS.state_changed.emit()
		_bought()


func _buy_camo() -> void:
	if GS.spend(GS.CAMO_PRICE):
		GS.camo = true
		GS.state_changed.emit()
		_bought()


func _buy_repair() -> void:
	if GS.spend(GS.REPAIR_PRICE):
		GS.base_hp = minf(100.0, GS.base_hp + 30.0)
		GS.state_changed.emit()
		_bought()


func _buy_crew() -> void:
	if GS.crews < GS.CREW_MAX and GS.spend(GS.CREW_PRICE):
		GS.crews += 1
		GS.state_changed.emit()
		_bought()


func _buy_city_repair() -> void:
	if GS.spend(GS.CITY_REPAIR_PRICE):
		GS.city = minf(100.0, GS.city + GS.CITY_REPAIR_GAIN)
		GS.state_changed.emit()
		_bought()
