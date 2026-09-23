extends RefCounted
## Neon "air-defense console" theme and small UI builders, all created in code.

const NEON := Color(0.2, 1.0, 0.65)
const NEON_DIM := Color(0.2, 1.0, 0.65, 0.35)
const AMBER := Color(1.0, 0.75, 0.25)
const RED := Color(1.0, 0.25, 0.25)
const CYAN := Color(0.35, 0.85, 1.0)
const BG := Color(0.0, 0.05, 0.04, 0.84)


static func sbox(bg: Color, border: Color, width := 2, radius := 6, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.shadow_color = Color(border.r, border.g, border.b, 0.18)
	s.shadow_size = 6
	return s


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = GS.font
	th.default_font_size = 18
	var normal := sbox(Color(0.02, 0.1, 0.07, 0.88), NEON_DIM, 2, 6, 8)
	var hover := sbox(Color(0.04, 0.22, 0.14, 0.95), NEON, 2, 6, 8)
	var pressed := sbox(Color(0.1, 0.4, 0.25, 0.95), NEON, 2, 6, 8)
	var disabled := sbox(Color(0.03, 0.05, 0.05, 0.7), Color(0.3, 0.4, 0.35, 0.3), 2, 6, 8)
	for t in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		th.set_stylebox("normal", t, normal)
		th.set_stylebox("hover", t, hover)
		th.set_stylebox("pressed", t, pressed)
		th.set_stylebox("hover_pressed", t, pressed)
		th.set_stylebox("disabled", t, disabled)
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_color("font_color", t, Color(0.7, 1.0, 0.85))
		th.set_color("font_hover_color", t, Color(1, 1, 1))
		th.set_color("font_pressed_color", t, Color(1, 1, 1))
		th.set_color("font_hover_pressed_color", t, Color(1, 1, 1))
		th.set_color("font_disabled_color", t, Color(0.45, 0.55, 0.5))
	th.set_stylebox("panel", "PanelContainer", sbox(BG, NEON_DIM, 2, 8, 12))
	th.set_stylebox("panel", "Panel", sbox(BG, NEON_DIM, 2, 8, 12))
	th.set_stylebox("panel", "PopupMenu", sbox(Color(0.01, 0.08, 0.06, 0.97), NEON, 2, 4, 6))
	th.set_color("font_color", "PopupMenu", Color(0.7, 1.0, 0.85))
	th.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	th.set_stylebox("hover", "PopupMenu", sbox(Color(0.05, 0.3, 0.2, 1), NEON, 1, 3, 4))
	th.set_color("font_color", "Label", Color(0.78, 1.0, 0.88))
	var bar_bg := sbox(Color(0.02, 0.06, 0.05, 0.9), NEON_DIM, 1, 3, 0)
	var bar_fill := sbox(NEON, NEON, 0, 3, 0)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	th.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	th.set_stylebox("slider", "HSlider", sbox(Color(0.05, 0.2, 0.14), NEON_DIM, 1, 3, 3))
	th.set_stylebox("grabber_area", "HSlider", sbox(NEON, NEON, 0, 3, 3))
	th.set_stylebox("grabber_area_highlight", "HSlider", sbox(Color(1, 1, 1), NEON, 0, 3, 3))
	th.set_stylebox("normal", "LineEdit", sbox(Color(0.01, 0.06, 0.04, 0.95), NEON_DIM, 2, 5, 8))
	th.set_stylebox("focus", "LineEdit", sbox(Color(0.02, 0.1, 0.07, 0.95), NEON, 2, 5, 8))
	th.set_color("font_color", "LineEdit", Color(0.9, 1.0, 0.95))
	th.set_color("caret_color", "LineEdit", NEON)
	th.set_color("selection_color", "LineEdit", Color(0.2, 0.6, 0.4, 0.6))
	th.set_stylebox("panel", "TooltipPanel", sbox(Color(0.01, 0.08, 0.06, 0.97), NEON, 1, 4, 6))
	th.set_stylebox("scroll", "VScrollBar", sbox(Color(0.02, 0.08, 0.06, 0.6), NEON_DIM, 1, 3, 2))
	th.set_stylebox("grabber", "VScrollBar", sbox(NEON_DIM, NEON_DIM, 0, 3, 2))
	th.set_stylebox("grabber_highlight", "VScrollBar", sbox(NEON, NEON, 0, 3, 2))
	return th


static func label(text: String, size := 18, color := Color(0.78, 1.0, 0.88), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func glow_label(text: String, size: int, color: Color) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(color.r, color.g, color.b, 0.25))
	l.add_theme_constant_override("outline_size", int(size * 0.18))
	l.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", int(size * 0.5))
	return l


static func button(text: String, cb: Callable, min_w := 260, font_size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 0)
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func() -> void: SFX.play("click", -6.0))
	b.pressed.connect(cb)
	return b


static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Controls under a CanvasLayer don't inherit the Window theme, so the neon theme is
## merged into the engine default theme once at startup.
static func install_theme() -> void:
	var th := make_theme()
	var def := ThemeDB.get_default_theme()
	def.merge_with(th)
	def.default_font = GS.font
	def.default_font_size = 18
	ThemeDB.fallback_font = GS.font
	ThemeDB.fallback_font_size = 18


## Dimmed full-screen overlay with a centered panel. Returns [overlay_root, content_vbox].
static func modal(parent: Node, min_size: Vector2) -> Array:
	var root := Control.new()
	full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.02, 0.65)
	full_rect(dim)
	root.add_child(dim)
	var center := CenterContainer.new()
	full_rect(center)
	root.add_child(center)
	var p := panel(min_size)
	center.add_child(p)
	var v := vbox(12)
	p.add_child(v)
	parent.add_child(root)
	return [root, v]
