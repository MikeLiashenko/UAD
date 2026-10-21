extends Control
## "Create new world": name, city, difficulty and mode (the usual game or MaxRealism), then the
## base position is picked on the city map. The city is one of the game's four or one the player
## has drawn in the map editor ("Свой город…", CityStore).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Cities = preload("res://scripts/world/cities.gd")
const CityStore = preload("res://scripts/core/city_store.gd")
const CitiesMenu = preload("res://scripts/ui/cities_menu.gd")

var main
var _name: LineEdit
var _diff := 1
var _diff_btns: Array = []
var _diff_desc: Label
var _city := "kyiv"
var _city_btns := {}
## "Свой город…": opens the list of the player's cities; shows the chosen one's name.
var _own_btn: Button
var _pick: Control
var _city_desc: Label
## MaxRealism: the ground view only, every system is walked to and worked by hand.
var _real := false
var _mode_btns: Array = []
var _mode_desc: Label
## The name field still holds the suggested name (so switching the city renames the world too).
var _auto_name := true


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.bleed(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.03, 0.55)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(640, 0))
	center.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.glow_label(GS.t("СОЗДАНИЕ МИРА"), 36, UiKit.NEON))
	v.add_child(UiKit.label(GS.t("Название мира"), 16, UiKit.AMBER))
	_name = LineEdit.new()
	_name.max_length = 32
	_name.add_theme_font_size_override("font_size", 22)
	_name.custom_minimum_size = Vector2(0, 46)
	_name.select_all_on_focus = true
	_name.text_changed.connect(func(_t: String) -> void: _auto_name = false)
	v.add_child(_name)
	v.add_child(UiKit.label(GS.t("Город"), 16, UiKit.AMBER))
	var ch := UiKit.hbox(8)
	v.add_child(ch)
	for id in Cities.IDS:
		var def = Cities.get_def(id)
		var b := Button.new()
		b.text = GS.t(String(def.name))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(104, 50)
		b.add_theme_font_size_override("font_size", 19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_city.bind(String(id)))
		ch.add_child(b)
		_city_btns[id] = b
	_own_btn = Button.new()
	_own_btn.toggle_mode = true
	_own_btn.focus_mode = Control.FOCUS_NONE
	_own_btn.custom_minimum_size = Vector2(150, 50)
	_own_btn.add_theme_font_size_override("font_size", 17)
	_own_btn.clip_text = true
	_own_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_own_btn.pressed.connect(_pick_own)
	ch.add_child(_own_btn)
	_city_desc = UiKit.label("", 14, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	_city_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_city_desc.custom_minimum_size = Vector2(600, 40)
	v.add_child(_city_desc)
	v.add_child(UiKit.label(GS.t("Сложность"), 16, UiKit.AMBER))
	var h := UiKit.hbox(8)
	v.add_child(h)
	for i in GS.DIFFICULTY.size():
		var b := Button.new()
		b.text = GS.t(String(GS.DIFFICULTY[i].name))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(180, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_diff.bind(i))
		h.add_child(b)
		_diff_btns.append(b)
	_diff_desc = UiKit.label("", 14, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_diff_desc)
	_set_diff(int(main.pending_world.get("difficulty", 1)))
	v.add_child(UiKit.label(GS.t("Режим"), 16, UiKit.AMBER))
	var mh := UiKit.hbox(8)
	v.add_child(mh)
	for spec in [[false, GS.t("Обычный")], [true, "MaxRealism"]]:
		var b := Button.new()
		b.text = String(spec[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(180, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_mode.bind(bool(spec[0])))
		mh.add_child(b)
		_mode_btns.append(b)
	var tb := Button.new()
	tb.text = GS.t("Обучение")
	tb.tooltip_text = GS.t("Учебный полигон MaxRealism: инструктор проведёт по всем местам — пулемёт, «Игла», радар, пульт С-300")
	tb.focus_mode = Control.FOCUS_NONE
	tb.custom_minimum_size = Vector2(150, 46)
	tb.add_theme_font_size_override("font_size", 18)
	tb.pressed.connect(func() -> void: main.start_training())
	mh.add_child(tb)
	_mode_desc = UiKit.label("", 14, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.custom_minimum_size = Vector2(600, 58)
	v.add_child(_mode_desc)
	_set_mode(bool(main.pending_world.get("realism", false)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	v.add_child(spacer)
	v.add_child(UiKit.button(GS.t("Выбрать позицию на карте ▶"), _next, 580, 22))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: main.show_worlds(), 580, 18))
	# start from the city on screen: the one last played, or the one picked before "Back"
	_set_city(main.create_city if main.create_city != "" else String(main.map.city_id))
	main.create_city = ""
	_name.grab_focus.call_deferred()


func _set_city(id: String) -> void:
	# one of the game's cities or one of the player's own — never a server's (those live in a match)
	if not Cities.has(id) or (Cities.is_custom(id) and not CityStore.is_mine(id)):
		id = Cities.DEFAULT
	_city = id
	var mine := CityStore.is_mine(id)
	_own_btn.button_pressed = mine
	_own_btn.text = String(Cities.get_def(id).name) if mine else GS.t("Свой город…")
	_own_btn.add_theme_color_override("font_color", Cities.get_def(id).accent if mine else Color(0.75, 0.85, 0.8))
	_own_btn.add_theme_color_override("font_pressed_color", Cities.get_def(id).accent)
	for k in _city_btns:
		var b: Button = _city_btns[k]
		b.button_pressed = k == id
		var acc: Color = Cities.get_def(k).accent
		b.add_theme_color_override("font_color", acc if k == id else Color(0.75, 0.85, 0.8))
		b.add_theme_color_override("font_pressed_color", acc)
	_city_desc.text = GS.t(String(Cities.get_def(id).blurb))
	if mine:
		_city_desc.text = GS.t("Ваш город из редактора карт: %s. Налёты — «Шахеды», крылатые ракеты и баллистика.") % CityStore.summary(Cities.get_def(id).data)
	if _auto_name:
		_name.text = "%s %d" % [GS.ctext("defense", id), GS.list_worlds().size() + 1]


## The list of the player's cities; with none drawn yet, the way to the map editor.
func _pick_own() -> void:
	SFX.play("click", -8.0)
	_set_city(_city) # the button shows a choice, not a press
	_pick = CitiesMenu.pick(self, func(e: Dictionary) -> void: _set_city(CityStore.city_id(String(e.id))), func() -> void: main.show_cities())


func _set_diff(i: int) -> void:
	_diff = i
	for k in _diff_btns.size():
		(_diff_btns[k] as Button).button_pressed = k == i
	_diff_desc.text = GS.t("%s · стартовый бюджет %s") % [GS.t(String(GS.DIFFICULTY[i].desc)), GS.fmt_money(int(GS.DIFFICULTY[i].money))]


func _set_mode(real: bool) -> void:
	_real = real
	for k in _mode_btns.size():
		(_mode_btns[k] as Button).button_pressed = (k == 1) == real
	if real:
		_mode_desc.text = GS.t("Только вид с земли. Никаких меток на целях и кнопок систем: к каждой машине нужно подойти и занять место. О пусках сообщает радио, цели — точки на радаре, ракета может промахнуться. Сначала пройдите обучение.")
	else:
		_mode_desc.text = GS.t("Карта сверху, панель батареи, метки целей — игра, как она есть.")


func _next() -> void:
	var n := _name.text.strip_edges()
	if n == "":
		n = GS.ctext("defense", _city)
	main.show_map_select({"name": n, "difficulty": _diff, "city": _city, "realism": _real})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if _pick != null and is_instance_valid(_pick):
			if k == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_pick.queue_free()
			return
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			main.show_worlds()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_next()
