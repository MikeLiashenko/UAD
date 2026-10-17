extends Control
## The map editor's own screen (main menu → "Map editor"): the cities the player has drawn
## (CityStore). A city is drawn in the city editor, and then a world can be created in it — here
## or on the "create world" screen — or a server can take it as one of its two cities.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CityPlan = preload("res://scripts/ui/city_plan.gd")
const CityStore = preload("res://scripts/core/city_store.gd")
const CustomCity = preload("res://scripts/world/custom_city.gd")

## The city selected when the screen opens again (back from the editor).
static var last := ""

var main
var _list: VBoxContainer
var _rows := {}
var _entries := {}
var _sel := ""
var _click := {}
var _edit_btn: Button
var _world_btn: Button
var _del_btn: Button
var _confirm: Control


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
	v.add_child(UiKit.glow_label(GS.t("РЕДАКТОР КАРТ"), 34, UiKit.NEON))
	var sub := UiKit.label(GS.t("Нарисуйте свой город: реки, районы, дороги, объекты. Потом в нём можно создать мир и оборонять его — или отдать его серверу."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(740, 0)
	v.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = UiKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_edit_btn = UiKit.button(GS.t("Редактировать"), _edit, 370, 20)
	grid.add_child(_edit_btn)
	grid.add_child(UiKit.button(GS.t("Новый город"), _ask_new, 370, 20))
	_world_btn = UiKit.button(GS.t("Создать мир в этом городе"), _make_world, 370, 18)
	grid.add_child(_world_btn)
	_del_btn = UiKit.button(GS.t("Удалить"), _ask_delete, 370, 18)
	grid.add_child(_del_btn)
	v.add_child(UiKit.button(GS.t("Назад"), func() -> void: main.show_menu(), 750, 18))
	_sel = last
	_rebuild()


## A row of a list of cities: a small plan, the name and what is drawn. Used here and by pick().
static func row(e: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UiKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -12
	b.add_child(h)
	var plan := CityPlan.new()
	plan.custom_minimum_size = Vector2(72, 72)
	plan.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plan.movable = false
	plan.names = false
	plan.compact = true
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(plan)
	plan.set_data(e.city)
	var col := UiKit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(UiKit.label(String(e.city.name), 21, Color(1, 1, 1)))
	col.add_child(UiKit.label(CityStore.summary(e.city), 14, Color(0.7, 1.0, 0.85)))
	col.add_child(UiKit.label(GS.t("Изменён: %s") % GS.fmt_date(int(e.edited)), 12, Color(0.5, 0.75, 0.65)))
	for c in col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_entries.clear()
	var cities := CityStore.list()
	if cities.is_empty():
		var e := UiKit.label(GS.t("Своих городов пока нет — нажмите «Новый город»."), 20, Color(0.7, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
		e.custom_minimum_size = Vector2(0, 120)
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(e)
	for e in cities:
		var id := String(e.id)
		_entries[id] = e
		var b := row(e)
		b.pressed.connect(_on_row.bind(id))
		_list.add_child(b)
		_rows[id] = b
	if not _entries.has(_sel):
		_sel = String(cities[0].id) if not cities.is_empty() else ""
	_update_buttons()


func _on_row(id: String) -> void:
	SFX.play("click", -8.0)
	var now := Time.get_ticks_msec()
	if _sel == id and now - int(_click.get(id, 0)) < 400:
		_edit()
		return
	_click[id] = now
	_sel = id
	_update_buttons()


func _update_buttons() -> void:
	for id in _rows:
		(_rows[id] as Button).button_pressed = id == _sel
	last = _sel
	for b in [_edit_btn, _world_btn, _del_btn]:
		(b as Button).disabled = _sel == ""


func _edit() -> void:
	if _sel != "":
		main.show_map_editor(_sel)


func _make_world() -> void:
	if _sel != "":
		main.show_create_world(false, CityStore.city_id(_sel))


## A new city starts from an empty field or from the ready-made sample.
func _ask_new() -> void:
	if _entries.size() >= CityStore.LIMIT:
		SFX.play("alert", -10.0)
		return
	var m := UiKit.modal(self, Vector2(480, 0))
	_confirm = m[0]
	var box := _confirm
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("НОВЫЙ ГОРОД"), 30, UiKit.NEON))
	var t := UiKit.label(GS.t("С чего начать? Образец — небольшой готовый город, который можно перерисовать."), 16, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 0)
	v.add_child(t)
	var cname := GS.t("Мой город %d") % (_entries.size() + 1)
	var start := func(city: Dictionary) -> void:
		box.queue_free()
		main.show_map_editor(CityStore.create(city))
	v.add_child(UiKit.button(GS.t("Пустое поле"), func() -> void: start.call(CustomCity.blank(cname))))
	v.add_child(UiKit.button(GS.t("Готовый образец"), func() -> void: start.call(CustomCity.sample(cname))))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: box.queue_free()))


func _ask_delete() -> void:
	if _sel == "":
		return
	var m := UiKit.modal(self, Vector2(480, 0))
	_confirm = m[0]
	var box := _confirm
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Удалить город?"), 30, UiKit.RED))
	var t := UiKit.label(GS.t("«%s» будет удалён из редактора. Миры, уже созданные в этом городе, останутся: у каждого своя копия карты.") % String(_entries[_sel].city.name), 16, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 0)
	v.add_child(t)
	v.add_child(UiKit.button(GS.t("Удалить"), func() -> void:
		CityStore.remove(_sel)
		_sel = ""
		box.queue_free()
		_rebuild()))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: box.queue_free()))


## A window with the player's cities to choose one from: on_pick(entry) — {id, edited, city}.
## `on_editor` (optional) is offered when there is nothing to choose yet. Returns the window.
static func pick(parent: Node, on_pick: Callable, on_editor := Callable()) -> Control:
	var m := UiKit.modal(parent, Vector2(600, 0))
	var box: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("МОИ ГОРОДА"), 30, UiKit.NEON))
	var cities := CityStore.list()
	if cities.is_empty():
		var t := UiKit.label(GS.t("Своих городов пока нет. Нарисуйте город в редакторе карт (главное меню → «Редактор карт»)."), 16, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(560, 0)
		v.add_child(t)
		if on_editor.is_valid():
			v.add_child(UiKit.button(GS.t("Открыть редактор карт"), on_editor))
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(560, minf(360.0, cities.size() * 90.0))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(scroll)
		var list := UiKit.vbox(6)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for e in cities:
			var b := row(e)
			b.toggle_mode = false
			b.pressed.connect(func() -> void:
				SFX.play("click", -6.0)
				box.queue_free()
				on_pick.call(e))
			list.add_child(b)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: box.queue_free()))
	return box


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _confirm != null and is_instance_valid(_confirm):
			_confirm.queue_free()
		else:
			main.show_menu()
