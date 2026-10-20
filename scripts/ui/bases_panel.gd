extends Control
## "Bases" [U]: the main base and the outposts, and where every bought system stands. A new
## outpost is set up from here (the panel closes and the next tap on the map places it); a system
## is driven to another base with one button (it is on the road for GS.RELOCATE_TIME seconds);
## an outpost can be shown on the map or taken down (its systems drive back to the main base).
## In the map view a tapped target goes to the base nearest to it (game_controller.shooter_for).

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal closed

var game
var _list: VBoxContainer
var _money: Label
var _tick := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.75)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(980, 0))
	center.add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var top := UiKit.hbox()
	v.add_child(top)
	var title := UiKit.glow_label(GS.t("БАЗЫ И РАССТАНОВКА СИСТЕМ"), 28, UiKit.NEON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = UiKit.label("", 24, UiKit.NEON)
	top.add_child(_money)
	var help := UiKit.label(GS.t("В виде сверху по выбранной цели стреляет ближайшая к ней база: выбранная система, если она там и может, иначе та система этой базы, что справится лучше. Разведка ищет и бьёт главную базу."), 13, Color(0.6, 0.85, 0.75))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(960, 0)
	v.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(960, minf(480.0, get_viewport_rect().size.y - 230.0))
	v.add_child(scroll)
	_list = UiKit.vbox(6)
	_list.custom_minimum_size = Vector2(940, 0)
	scroll.add_child(_list)
	var close_b := UiKit.button(GS.t("Закрыть [%s]") % GS.key_label("bases") if not GS.touch() else GS.t("✕ Закрыть"), close, 300, 18)
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close_b)
	GS.state_changed.connect(_refresh)
	_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or GS.action_of(k) in ["bases", "pause"]:
			get_viewport().set_input_as_handled()
			close()


## The seconds on the road tick on behind a shared world's panel.
func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 0.5:
		_tick = 0.0
		if not get_tree().paused:
			_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_money.text = GS.fmt_money(GS.money)
	for c in _list.get_children():
		c.queue_free()
	# a new outpost
	var price := GS.outpost_price()
	var why := ""
	if price <= 0:
		why = GS.t("Больше опорных пунктов не поставить")
	elif GS.money < price:
		why = GS.t("Не хватает денег")
	var add := UiKit.button(GS.t("＋ Новый опорный пункт · %s") % GS.fmt_money(price) if price > 0 else GS.t("＋ Новый опорный пункт"), func() -> void:
		close()
		game.start_place_base(), 460, 17)
	add.disabled = why != ""
	add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.add_child(add)
	_note(why if why != "" else GS.t("Панель закроется — коснитесь места на карте (не вода, не дорога, не застройка, от 400 м до другой базы). Esc — отмена."), UiKit.RED if why != "" else Color(0.55, 0.8, 0.7))
	# the bases
	_list.add_child(UiKit.label(GS.t("БАЗЫ"), 15, UiKit.AMBER))
	for i in GS.base_count():
		_list.add_child(_base_row(i))
	# the systems
	_list.add_child(UiKit.label(GS.t("СИСТЕМЫ — ГДЕ СТОЯТ"), 15, UiKit.AMBER))
	var owned: Array = game.owned_weapons()
	if owned.is_empty():
		_note(GS.t("Пока ничего не куплено."), Color(0.55, 0.8, 0.7))
	for id in owned:
		_list.add_child(_unit_row(String(id)))


func _base_row(i: int) -> Control:
	var h := UiKit.hbox(8)
	var pos := GS.base_at(i)
	var n := 0
	for id in game.owned_weapons():
		if GS.base_of(String(id)) == i:
			n += 1
	var txt := "%s · %s · %s" % [GS.base_name(i), GS.loc_name(GS.base_loc_of(i)), GS.t("систем: %d") % n]
	if i > 0:
		txt += GS.t(" · %.1f км от главной") % (Vector2(pos.x - GS.base_pos.x, pos.z - GS.base_pos.z).length() / 1000.0)
	var l := UiKit.label(txt, 16, Color(0.6, 1.0, 0.8) if i == 0 else Color(0.6, 0.9, 1.0))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UiKit.button(GS.t("📍 Показать"), func() -> void:
		close()
		if game.view != "top":
			game.set_view("top")
		game.rig.focus(pos), 150, 14))
	if i > 0:
		h.add_child(UiKit.button(GS.t("Свернуть"), func() -> void:
			game.remove_outpost(i)
			_refresh(), 130, 14))
	return h


func _unit_row(id: String) -> Control:
	var h := UiKit.hbox(6)
	var w = game.weapons.get(id)
	var at := GS.base_of(id)
	var name_l := UiKit.label(GS.t(String(GS.WEAPONS[id].short)), 15, Color(0.85, 1.0, 0.92))
	name_l.custom_minimum_size = Vector2(130, 0)
	h.add_child(name_l)
	var where := GS.base_name(at)
	if w != null and not w.ready_to_fire():
		where = GS.t("→ %s · в пути %d с") % [GS.base_name(at), int(ceil(w.relocating))]
	var wl := UiKit.label(where, 14, UiKit.CYAN if w != null and not w.ready_to_fire() else Color(0.6, 0.85, 0.75))
	wl.custom_minimum_size = Vector2(300, 0)
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(wl)
	if GS.base_count() <= 1:
		return h
	for b in GS.base_count():
		if b == at:
			continue
		var why: String = game.move_blocker(id, b)
		var bt := UiKit.button(GS.t("→ %s") % _short_base(b), func() -> void:
			if game.move_blocker(id, b) == "":
				game.move_weapon(id, b)
				SFX.play("click", -6.0)
				_refresh(), 120, 13)
		bt.disabled = why != ""
		bt.tooltip_text = why
		h.add_child(bt)
	return h


## "Главная" / "ОП 2" for the narrow buttons.
func _short_base(i: int) -> String:
	return GS.t("Главная") if i == 0 else GS.t("ОП %d") % (i + 1)


func _note(text: String, col: Color) -> void:
	var l := UiKit.label(text, 13, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(940, 0)
	_list.add_child(l)
