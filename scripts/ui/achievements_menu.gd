extends Control
## The achievements screen (main menu → "Achievements"): every one of them by section — a tab a
## section (and "All"), each with how many of it are earned; earned ones lit with the date, the
## rest dim with what it takes to earn them (scripts/core/achievements.gd).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Achievements = preload("res://scripts/core/achievements.gd")

signal closed

## The section shown ("" = all of them).
var cat := ""
var _grid: GridContainer
var _tabs: HFlowContainer
var _scroll: ScrollContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.6)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(960, 0))
	center.add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.glow_label(GS.t("ДОСТИЖЕНИЯ"), 36, UiKit.NEON))
	var bar := ProgressBar.new()
	bar.max_value = Achievements.total()
	bar.value = Achievements.count()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(940, 10)
	v.add_child(bar)
	v.add_child(UiKit.label(GS.t("Получено: %d из %d · во всех мирах") % [Achievements.count(), Achievements.total()], 15, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	_tabs.custom_minimum_size = Vector2(940, 0)
	v.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(940, minf(470.0, get_viewport_rect().size.y - 290.0))
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)
	var back := UiKit.button(GS.t("Назад"), func() -> void:
		closed.emit()
		queue_free(), 300, 20)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	_fill()


## The tabs and the cards of the section shown.
func _fill() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for c in _grid.get_children():
		c.queue_free()
	_tab("", GS.t("Все · %d/%d") % [Achievements.count(), Achievements.total()])
	for sc in Achievements.CATS:
		var n: Array = Achievements.count_in(String(sc[0]))
		_tab(String(sc[0]), "%s · %d/%d" % [GS.t(String(sc[1])), int(n[0]), int(n[1])])
	# earned first in each section, then the rest in their own order
	var shown := []
	for e in Achievements.all():
		if cat == "" or String(e.cat) == cat:
			shown.append(e)
	var lit := shown.filter(func(e) -> bool: return Achievements.has(String(e.id)))
	var dim := shown.filter(func(e) -> bool: return not Achievements.has(String(e.id)))
	for e in lit + dim:
		_grid.add_child(_card(e))
	_scroll.scroll_vertical = 0


func _tab(id: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 34)
	if id == cat:
		b.add_theme_stylebox_override("normal", UiKit.sbox(Color(0.1, 0.35, 0.25, 0.95), UiKit.NEON, 2, 6, 6))
		b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.pressed.connect(func() -> void:
		SFX.play("click", -8.0)
		cat = id
		_fill())
	_tabs.add_child(b)


func _card(e: Dictionary) -> Control:
	var id := String(e.id)
	var on := Achievements.has(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 70)
	card.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.05, 0.16, 0.12, 0.92) if on else Color(0.03, 0.06, 0.06, 0.8), UiKit.NEON if on else Color(0.25, 0.35, 0.32), 2, 6, 8))
	var h := UiKit.hbox(10)
	card.add_child(h)
	var icon := UiKit.label(String(e.icon) if on else "🔒", 28, Color(1, 1, 1, 1.0 if on else 0.45))
	icon.custom_minimum_size = Vector2(42, 0)
	h.add_child(icon)
	var t := UiKit.vbox(2)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var nl := UiKit.label(Achievements.title(id), 16, UiKit.NEON if on else Color(0.6, 0.7, 0.66))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(380, 0)
	t.add_child(nl)
	var d := UiKit.label(Achievements.how(id), 13, Color(0.7, 0.88, 0.8) if on else Color(0.5, 0.6, 0.56))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	t.add_child(d)
	if on:
		t.add_child(UiKit.label(GS.fmt_date(int(Achievements.got[id])), 11, Color(0.5, 0.75, 0.65)))
	return card


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
