extends Control
## The achievements screen (main menu → "Achievements"): all twenty, earned ones lit with the date,
## the rest dim with what it takes to earn them (scripts/core/achievements.gd).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Achievements = preload("res://scripts/core/achievements.gd")

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.6)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(900, 0))
	center.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.glow_label(GS.t("ДОСТИЖЕНИЯ"), 38, UiKit.NEON))
	v.add_child(UiKit.label(GS.t("Получено: %d из %d · во всех мирах") % [Achievements.count(), Achievements.LIST.size()], 16, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(880, minf(500.0, get_viewport_rect().size.y - 230.0))
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for a in Achievements.LIST:
		grid.add_child(_card(a))
	var back := UiKit.button(GS.t("Назад"), func() -> void:
		closed.emit()
		queue_free(), 300, 20)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)


func _card(a: Array) -> Control:
	var id := String(a[0])
	var on := Achievements.has(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 74)
	card.add_theme_stylebox_override("panel", UiKit.sbox(Color(0.05, 0.16, 0.12, 0.92) if on else Color(0.03, 0.06, 0.06, 0.8), UiKit.NEON if on else Color(0.25, 0.35, 0.32), 2, 6, 8))
	var h := UiKit.hbox(10)
	card.add_child(h)
	var icon := UiKit.label(String(a[1]) if on else "🔒", 30, Color(1, 1, 1, 1.0 if on else 0.45))
	icon.custom_minimum_size = Vector2(44, 0)
	h.add_child(icon)
	var t := UiKit.vbox(2)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	t.add_child(UiKit.label(GS.t(String(a[2])), 17, UiKit.NEON if on else Color(0.6, 0.7, 0.66)))
	var d := UiKit.label(GS.t(String(a[3])), 13, Color(0.7, 0.88, 0.8) if on else Color(0.5, 0.6, 0.56))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(350, 0)
	t.add_child(d)
	if on:
		t.add_child(UiKit.label(GS.fmt_date(int(Achievements.got[id])), 11, Color(0.5, 0.75, 0.65)))
	return card


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
