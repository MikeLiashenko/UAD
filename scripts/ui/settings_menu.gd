extends Control
## Settings: volume, fullscreen, graphics, target markers, gunner-sight controls.
## Saved to user://settings.cfg. (Difficulty is chosen per world when it is created.)

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const I18n = preload("res://scripts/i18n/i18n.gd")

signal closed

## Action waiting for a new key ("" = not rebinding right now).
var _capturing := ""
var _key_rows := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _set_language(idx: int) -> void:
	GS.set_language(String(I18n.LANGS[idx][0]))
	GS.save_settings()
	# rebuild in the new language
	for c in get_children():
		c.queue_free()
	_build.call_deferred()


func _build() -> void:
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.6)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(620, 0))
	center.add_child(p)
	# the list is long (controls included), so the whole panel scrolls inside the screen
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(600, minf(760.0, get_viewport_rect().size.y - 120.0))
	p.add_child(scroll)
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UiKit.glow_label(GS.t("НАСТРОЙКИ"), 38, UiKit.NEON))
	var lang := OptionButton.new()
	for l in I18n.LANGS:
		lang.add_item(String(l[1]))
	lang.selected = I18n.index_of(String(GS.settings.lang))
	lang.item_selected.connect(_set_language)
	lang.custom_minimum_size = Vector2(240, 0)
	_row(v, "🌐 " + GS.t("Язык") + " / Language", lang)

	v.add_child(UiKit.label(GS.t("ЗВУК И ЭКРАН"), 15, UiKit.AMBER))
	_row(v, GS.t("Общая громкость"), _slider(0.0, 1.0, 0.05, float(GS.settings.volume), "volume"))
	_row(v, GS.t("Музыка"), _slider(0.0, 1.0, 0.05, float(GS.settings.music), "music"))
	if OS.has_feature("pc"):
		_row(v, GS.t("Полноэкранный режим"), _check(bool(GS.settings.fullscreen), "fullscreen"))
	var q := OptionButton.new()
	q.add_item(GS.t("Низкое (без теней, свечения и трафика)"))
	q.add_item(GS.t("Высокое"))
	q.add_item(GS.t("Ультра (облака, интерьеры окон, отражения в воде)"))
	q.selected = int(GS.settings.quality)
	q.item_selected.connect(_set_setting.bind("quality"))
	_row(v, GS.t("Качество графики"), q)

	v.add_child(UiKit.label(GS.t("ЦЕЛИ"), 15, UiKit.AMBER))
	_row(v, GS.t("Метки целей (Ш, КР, БР, Р)"), _check(bool(GS.settings.markers), "markers"))
	var mh := UiKit.label(GS.t("Выключено — в небе только модели и огни двигателей, как в реальности."), 12, Color(0.55, 0.8, 0.7))
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(mh)

	v.add_child(UiKit.label(GS.t("ВИД С БАЗЫ (ПРИЦЕЛ)"), 15, UiKit.AMBER))
	_row(v, GS.t("Чувствительность мыши"), _slider(0.3, 2.5, 0.05, float(GS.settings.sens), "sens"))
	_row(v, GS.t("Инверсия оси Y"), _check(bool(GS.settings.invert_y), "invert_y"))
	_row(v, GS.t("Замедление при эффектном сбитии"), _check(bool(GS.settings.slowmo), "slowmo"))

	_build_keys(v)
	v.add_child(UiKit.button(GS.t("Назад"), _close))


## Rebindable controls: every action gets a row with its key; clicking waits for the next press.
func _build_keys(v: Control) -> void:
	v.add_child(UiKit.label(GS.t("УПРАВЛЕНИЕ"), 15, UiKit.AMBER))
	var note := UiKit.label(GS.t("Нажмите на клавишу справа и нажмите новую. Esc — отмена. Движение (WASD / стрелки), прицел мышью, Shift (бег и разгон) и 1-9 (выбор ПВО) не меняются."), 12, Color(0.55, 0.8, 0.7))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	v.add_child(note)
	var list := UiKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	_key_rows.clear()
	for spec in GS.KEY_ACTIONS:
		var id := String(spec[0])
		var h := UiKit.hbox(12)
		var l := UiKit.label(GS.t(String(spec[1])), 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_size_override("font_size", 15)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_start_capture.bind(id))
		h.add_child(b)
		list.add_child(h)
		_key_rows[id] = b
	_refresh_keys()
	v.add_child(UiKit.button(GS.t("Сбросить управление"), _reset_keys, 260, 18))


func _refresh_keys() -> void:
	for id in _key_rows:
		var b: Button = _key_rows[id]
		if String(id) == _capturing:
			b.text = GS.t("нажмите клавишу…")
			b.add_theme_color_override("font_color", UiKit.AMBER)
		else:
			b.text = GS.key_label(String(id))
			b.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))


func _start_capture(action: String) -> void:
	_capturing = action
	_refresh_keys()


func _reset_keys() -> void:
	GS.reset_keys()
	_capturing = ""
	_refresh_keys()


func _slider(lo: float, hi: float, step: float, val: float, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(240, 24)
	s.value_changed.connect(_set_setting.bind(key))
	return s


func _check(on: bool, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(_set_setting.bind(key))
	return c


func _set_setting(value: Variant, key: String) -> void:
	GS.settings[key] = value
	GS.apply_settings()


func _row(parent: Control, title: String, ctl: Control) -> void:
	var h := UiKit.hbox(16)
	var l := UiKit.label(title, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctl)
	parent.add_child(h)


func _close() -> void:
	GS.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or (event as InputEventKey).echo:
		return
	var kc: int = (event as InputEventKey).keycode
	if _capturing != "":
		get_viewport().set_input_as_handled()
		if kc != KEY_ESCAPE:
			GS.set_key(_capturing, kc)
		_capturing = ""
		_refresh_keys()
		return
	if kc == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
