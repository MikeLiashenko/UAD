extends Control
## Title screen over a slowly orbiting night view of the city (the one last played).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const BuildInfo = preload("res://scripts/build_info.gd")

const SPLASHES := [
	"Небо под защитой!", "Обломки — в Днепр!", "Шахеды не пройдут!", "Слава ПВО!",
	"Ночь будет долгой", "Кофе и радар!", "Теперь с видом с базы!", "Город не спит!",
	"Смотри на прогноз падения!", "Patriot — не для шахедов!",
]

var main
var _status: Label
var _splash: Label
var _t := 0.0
## Update offer: the corner button, the dialog, and whether it was already shown this launch.
var _update_btn: Button
var _update_box: Control
static var _offered := false


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vignette := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.1, 1.1)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0.02, 0.03, 0.85))
	g.gradient = grad
	vignette.texture = g
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(vignette)
	add_child(vignette)

	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var v := UiKit.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	if ResourceLoader.exists("res://icon.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://icon.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(170, 170)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(logo)

	var title := UiKit.glow_label("UKRAINE AIR DEFENSE", 64, UiKit.NEON)
	v.add_child(title)
	# Minecraft-style splash text
	_splash = UiKit.label(GS.t(SPLASHES[randi() % SPLASHES.size()]), 24, Color(1.0, 0.92, 0.2))
	_splash.add_theme_color_override("font_outline_color", Color(0.25, 0.2, 0.0))
	_splash.add_theme_constant_override("outline_size", 6)
	_splash.rotation_degrees = -14.0
	_splash.position = Vector2(640, 62)
	title.add_child(_splash)
	v.add_child(UiKit.label(GS.ctext("over"), 20, Color(0.7, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	v.add_child(spacer)
	for spec in [[GS.t("Играть"), func() -> void: main.show_worlds()], [GS.t("Настройки"), func() -> void: main.show_settings()], [GS.t("Выход"), func() -> void: main.quit_game()]]:
		var b := UiKit.button(spec[0], spec[1], 340, 26)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(340, 56)
		v.add_child(b)

	_status = UiKit.label("", 15, UiKit.NEON)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 20
	_status.offset_top = -40
	add_child(_status)
	var ver := UiKit.label(GS.t("v%s · сборка %d · процедурная графика · Godot %s") % [ProjectSettings.get_setting("application/config/version", "1.0"), BuildInfo.BUILD, Engine.get_version_info().string], 13, Color(0.5, 0.7, 0.6))
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -520
	ver.offset_right = -20
	ver.offset_top = -38
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	# a newer build published: a button in the corner, and once per launch the offer itself
	_update_btn = UiKit.button("", _open_update, 360, 16)
	_update_btn.anchor_left = 1.0
	_update_btn.anchor_right = 1.0
	_update_btn.offset_left = -380
	_update_btn.offset_right = -20
	_update_btn.offset_top = 20
	_update_btn.offset_bottom = 64
	_update_btn.add_theme_color_override("font_color", UiKit.AMBER)
	_update_btn.visible = false
	add_child(_update_btn)
	Net.release_checked.connect(_on_release)
	if not Net.release.is_empty():
		_on_release(Net.release)


func _on_release(_info: Dictionary) -> void:
	if not Net.update_available():
		return
	_update_btn.text = GS.t("⬆ Доступна сборка %d — обновить") % int(float(Net.release.build))
	_update_btn.visible = true
	if not _offered:
		_offered = true
		_show_update()


func _open_update() -> void:
	_show_update()


## The offer: what is new and where to get it (the .exe / .apk of the newest release).
func _show_update() -> void:
	if _update_box != null and is_instance_valid(_update_box):
		return
	var m := UiKit.modal(self, Vector2(520, 0))
	_update_box = m[0]
	var v: VBoxContainer = m[1]
	var r: Dictionary = Net.release
	v.add_child(UiKit.glow_label(GS.t("ДОСТУПНО ОБНОВЛЕНИЕ"), 32, UiKit.AMBER))
	v.add_child(UiKit.label(GS.t("Сборка %d · версия %s · от %s") % [int(float(r.get("build", 0))), String(r.get("version", "")), String(r.get("date", ""))], 18, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(GS.t("У вас сборка %d") % BuildInfo.BUILD, 15, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	var notes := String(r.get("notes", "")).strip_edges()
	if notes != "":
		var nl := UiKit.label(notes, 15, Color(0.8, 1.0, 0.9))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(480, 0)
		v.add_child(nl)
	var hint := UiKit.label(GS.t("Скачайте новую сборку и запустите её вместо этой — миры и настройки сохранятся."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(480, 0)
	v.add_child(hint)
	v.add_child(UiKit.button(GS.t("Скачать обновление"), func() -> void:
		OS.shell_open(Net.update_url())
		_update_box.queue_free()))
	v.add_child(UiKit.button(GS.t("Открыть сайт игры"), func() -> void: OS.shell_open(Net.site_url()), 260, 16))
	v.add_child(UiKit.button(GS.t("Позже"), func() -> void: _update_box.queue_free(), 260, 16))


func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + 0.06 * absf(sin(_t * 5.0))
	_splash.pivot_offset = _splash.size * 0.5
	_splash.scale = Vector2(s, s)
	var dot := "●" if int(_t * 2.0) % 2 == 0 else "○"
	_status.text = GS.ctext("duty") % dot
