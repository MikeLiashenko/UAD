extends Control
## The mod workshop: projects of mods (Python) and picture mods (shaders), a code editor with
## highlighting, completion and a reference of the "uad" module, a check that runs the mod, a test
## in a world of its own, and the export to a .uadmod / .uadshader file that the "create world"
## screen then offers.
## A project is user://mod_projects/<id>.json: {id, kind: "mod" | "shader", name, author, version,
## description, files: {"main.py": text, …}, edited}.

signal closed

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Mods = preload("res://scripts/mods/mods.gd")
const Parser = preload("res://scripts/mods/py_parser.gd")
const Ref = preload("res://scripts/ui/mod_reference.gd")

const DIR := "user://mod_projects/"
const LIMIT := 80

var main
## The project open in the editor ({} on the list of projects).
var project := {}
var _file := "main.py"
var _code: CodeEdit
var _files_box: VBoxContainer
var _console: RichTextLabel
var _title: Label
var _list_view: Control
var _edit_view: Control
var _modal: Control
var _dirty := false
var _save_t := -1.0
var _preview_t := -1.0
var _font := 17
var _error_line := -1
var _peek := false
var _peek_bar: Control
## Self-test runs keep their projects in memory.
static var dry := false
static var _mem := {}


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.bleed(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.03, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_font = int(GS.settings.get("code_font", 17))
	_build_list()
	_build_editor()
	_show_list()


func _exit_tree() -> void:
	_save_now()
	Mods.preview("", null)


# --- the list of projects -------------------------------------------------------------------
func _build_list() -> void:
	_list_view = UiKit.full_rect(MarginContainer.new())
	for s in ["left", "right", "top", "bottom"]:
		_list_view.add_theme_constant_override("margin_" + s, 24)
	add_child(_list_view)
	var v := UiKit.vbox(10)
	_list_view.add_child(v)
	var top := UiKit.hbox(12)
	v.add_child(top)
	var t := UiKit.glow_label(GS.t("МАСТЕРСКАЯ МОДОВ"), 34, UiKit.NEON)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(t)
	top.add_child(UiKit.button(GS.t("Назад"), _close, 160, 20))
	var hint := UiKit.label(GS.t("Моды пишутся на Python: новые системы ПВО и угрозы, налёты, свои правила через события игры. Графика — шейдер поверх картинки. Готовый мод экспортируется в файл и выбирается при создании мира."), 15, Color(0.65, 0.88, 0.78))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var row := UiKit.hbox(10)
	v.add_child(row)
	row.add_child(UiKit.button(GS.t("＋ Новый мод"), func() -> void: _ask_template(), 240, 20))
	row.add_child(UiKit.button(GS.t("Править установленный…"), _ask_open_installed, 300, 18))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)


func _show_list() -> void:
	_save_now()
	Mods.preview("", null)
	project = {}
	_list_view.visible = true
	_edit_view.visible = false
	var grid: GridContainer = _list_view.find_child("Grid", true, false)
	for c in grid.get_children():
		c.queue_free()
	var all := list_projects()
	if all.is_empty():
		var e := UiKit.label(GS.t("Проектов пока нет. Нажмите «Новый мод» и выберите заготовку — в ней уже есть работающий пример."), 16, Color(0.6, 0.85, 0.75))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(600, 80)
		grid.add_child(e)
	for p in all:
		var card := UiKit.panel(Vector2(590, 0))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UiKit.vbox(4)
		card.add_child(cv)
		cv.add_child(UiKit.label("%s  %s" % ["🧩" if String(p.kind) == "mod" else "🎨", String(p.name)], 20, Color(0.9, 1, 0.95)))
		var info := UiKit.label(GS.t("v%s · изменён %s") % [String(p.get("version", "1.0")), GS.fmt_date(int(p.get("edited", 0)))], 13, Color(0.55, 0.8, 0.7))
		cv.add_child(info)
		var h := UiKit.hbox(8)
		cv.add_child(h)
		var id := String(p.id)
		h.add_child(UiKit.button(GS.t("Открыть"), func() -> void: open_project(id), 160, 17))
		h.add_child(UiKit.button(GS.t("Удалить"), func() -> void: _ask_delete(id, String(p.name)), 140, 17))
		grid.add_child(card)


func _ask_template() -> void:
	SFX.play("click", -8.0)
	var m := UiKit.modal(self, Vector2(620, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Новый мод: заготовка"), 30, UiKit.NEON))
	for t in Ref.TEMPLATES:
		var b := UiKit.button("%s  %s" % [String(t.icon), Ref.tr3(t.title)], func() -> void:
			_modal.queue_free()
			new_project(String(t.id)), 580, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(580, 46)
		v.add_child(b)
		var d := UiKit.label(Ref.tr3(t.desc), 13, Color(0.6, 0.82, 0.74))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(580, 0)
		v.add_child(d)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _modal.queue_free()))


func _ask_open_installed() -> void:
	SFX.play("click", -8.0)
	var m := UiKit.modal(self, Vector2(560, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Править установленный мод"), 28, UiKit.NEON))
	var all := Mods.installed()
	if all.is_empty():
		v.add_child(UiKit.label(GS.t("Установленных модов нет."), 16, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, mini(all.size(), 5) * 56)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for p in all:
		list.add_child(UiKit.button("%s  %s  v%s" % ["🧩" if String(p.kind) == "mod" else "🎨", String(p.name), String(p.version)], func() -> void:
			_modal.queue_free()
			var proj := _from_package(p)
			save_project(proj)
			open_project(String(proj.id)), 500, 17))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _modal.queue_free()))


func _ask_delete(id: String, pname: String) -> void:
	var m := UiKit.modal(self, Vector2(480, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Удалить проект?"), 28, UiKit.RED))
	v.add_child(UiKit.label("«%s»" % pname, 18, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.button(GS.t("Удалить"), func() -> void:
		_modal.queue_free()
		delete_project(id)
		_show_list()))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _modal.queue_free()))


# --- projects on disk -----------------------------------------------------------------------
static func list_projects() -> Array:
	var out := []
	if dry:
		out = _mem.values()
	else:
		var dir := DirAccess.open(DIR)
		if dir != null:
			for f in dir.get_files():
				if String(f).ends_with(".json"):
					var p := read_project(String(f).get_basename())
					if not p.is_empty():
						out.append(p)
	out.sort_custom(func(a, b) -> bool: return int(a.get("edited", 0)) > int(b.get("edited", 0)))
	return out


static func read_project(id: String) -> Dictionary:
	if dry:
		return (_mem.get(id, {}) as Dictionary).duplicate(true)
	var text := FileAccess.get_file_as_string(DIR + id + ".json")
	var j := JSON.new()
	if text == "" or j.parse(text) != OK or not (j.data is Dictionary) or not (j.data.get("files") is Dictionary):
		return {}
	return j.data


static func save_project(p: Dictionary) -> void:
	p["edited"] = int(Time.get_unix_time_from_system())
	if dry:
		_mem[String(p.id)] = p.duplicate(true)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + String(p.id) + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(p, "\t"))
		f.close()


static func delete_project(id: String) -> void:
	if dry:
		_mem.erase(id)
		return
	DirAccess.remove_absolute(DIR + id + ".json")


func new_project(template: String) -> void:
	var t: Dictionary = Ref.template(template)
	var n := list_projects().size() + 1
	var p := {"id": "p%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000], "kind": String(t.kind),
		"name": Ref.tr3(t.title) + " %d" % n, "author": String(Net.nick()) if Net.has_method("nick") else "",
		"version": "1.0", "description": Ref.tr3(t.desc), "files": Ref.template_files(template)}
	if list_projects().size() >= LIMIT:
		_say(GS.t("Слишком много проектов: удалите ненужные."), UiKit.RED)
		return
	save_project(p)
	open_project(String(p.id))


func _from_package(pkg: Dictionary) -> Dictionary:
	var files := {}
	if String(pkg.kind) == "shader":
		files["shader.uadshader"] = String(pkg.code)
	else:
		files = (pkg.files as Dictionary).duplicate()
	return {"id": "p%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000], "kind": String(pkg.kind), "name": String(pkg.name),
		"author": String(pkg.get("author", "")), "version": String(pkg.get("version", "1.0")), "description": String(pkg.get("description", "")),
		"mod_id": String(pkg.id), "files": files}


## The package the project makes (what export writes and a test plays with).
func package() -> Dictionary:
	var mid := String(project.get("mod_id", Mods.safe_id(String(project.name))))
	if String(project.kind) == "shader":
		var code := String(project.files.values()[0]) if not project.files.is_empty() else ""
		var sp := Mods.shader_package(code, mid)
		if not sp.has("error"):
			sp.id = mid
			sp.name = String(project.name)
			sp.author = String(project.get("author", ""))
			sp.version = String(project.get("version", "1.0"))
			sp.description = String(project.get("description", ""))
		return sp
	return Mods.mod_package({"id": mid, "name": project.name, "author": project.get("author", ""), "version": project.get("version", "1.0"),
		"description": project.get("description", "")}, project.files, mid)


# --- the editor -----------------------------------------------------------------------------
func _build_editor() -> void:
	_edit_view = UiKit.full_rect(MarginContainer.new())
	for s in ["left", "right", "top", "bottom"]:
		_edit_view.add_theme_constant_override("margin_" + s, 10)
	add_child(_edit_view)
	var v := UiKit.vbox(6)
	_edit_view.add_child(v)
	# the bar: the project's name, check / test / export, back
	var top := UiKit.hbox(8)
	v.add_child(top)
	_title = UiKit.label("", 22, UiKit.NEON)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	top.add_child(_title)
	for spec in [[GS.t("▶ Проверить"), _check], [GS.t("⚔ Испытать"), _test], [GS.t("📦 Экспорт"), _export], [GS.t("⟵ Проекты"), _show_list]]:
		var b := UiKit.button(spec[0], spec[1], 150, 17)
		b.custom_minimum_size = Vector2(150, 44)
		b.name = "Bar%d" % top.get_child_count()
		top.add_child(b)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# left: the files and the project's details
	var left := UiKit.vbox(6)
	left.custom_minimum_size = Vector2(190, 0)
	body.add_child(left)
	left.add_child(UiKit.label(GS.t("Файлы"), 15, UiKit.AMBER))
	_files_box = UiKit.vbox(4)
	left.add_child(_files_box)
	var nf := UiKit.button(GS.t("＋ Файл"), _ask_new_file, 180, 15)
	nf.name = "NewFile"
	left.add_child(nf)
	left.add_child(UiKit.button(GS.t("Сведения"), _ask_details, 180, 15))
	var fs := UiKit.hbox(4)
	left.add_child(fs)
	fs.add_child(UiKit.button("A−", func() -> void: _set_font(_font - 2), 60, 16))
	fs.add_child(UiKit.button("A+", func() -> void: _set_font(_font + 2), 60, 16))
	var peek := UiKit.button(GS.t("👁 Смотреть"), _toggle_peek, 180, 15)
	peek.name = "Peek"
	left.add_child(peek)
	# middle: the code and the console under it
	var mid := VSplitContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	var code_box := UiKit.vbox(4)
	code_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(code_box)
	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.indent_automatic = true
	_code.indent_use_spaces = true
	_code.indent_size = 4
	_code.auto_brace_completion_enabled = true
	_code.code_completion_enabled = true
	_code.code_completion_prefixes = [".", "@"]
	_code.highlight_current_line = true
	_code.draw_tabs = false
	_code.scroll_past_end_of_file = true
	_code.minimap_draw = false
	_code.caret_blink = true
	_code.text_changed.connect(_on_text_changed)
	_code.code_completion_requested.connect(_complete)
	_style_code()
	code_box.add_child(_code)
	if GS.touch():
		code_box.add_child(_key_bar())
	_console = RichTextLabel.new()
	_console.bbcode_enabled = true
	_console.scroll_following = true
	_console.selection_enabled = true
	_console.custom_minimum_size = Vector2(0, 120)
	_console.add_theme_font_size_override("normal_font_size", 14)
	_console.add_theme_stylebox_override("normal", UiKit.sbox(Color(0.0, 0.03, 0.03, 0.92), UiKit.NEON_DIM, 1, 4, 6))
	mid.add_child(_console)
	# right: the reference — a tap puts the example at the caret
	var right := UiKit.vbox(4)
	right.custom_minimum_size = Vector2(290, 0)
	body.add_child(right)
	right.add_child(UiKit.label(GS.t("Справочник — нажмите, чтобы вставить"), 14, UiKit.AMBER))
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rs)
	var rl := UiKit.vbox(4)
	rl.name = "RefList"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(rl)
	# the bar shown while looking at the picture without the editor
	_peek_bar = UiKit.hbox(8)
	_peek_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_peek_bar.offset_top = -70
	_peek_bar.offset_bottom = -16
	_peek_bar.offset_left = -160
	_peek_bar.offset_right = 160
	_peek_bar.visible = false
	add_child(_peek_bar)
	var back := UiKit.button(GS.t("⟵ Назад к коду"), _toggle_peek, 320, 20)
	back.custom_minimum_size = Vector2(320, 52)
	_peek_bar.add_child(back)


func _fill_reference() -> void:
	var rl: VBoxContainer = _edit_view.find_child("RefList", true, false)
	for c in rl.get_children():
		c.queue_free()
	var kind := String(project.get("kind", "mod"))
	for sec in Ref.sections(kind):
		rl.add_child(UiKit.label(Ref.tr3(sec.title), 15, UiKit.CYAN))
		for e in sec.items:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = String(e.sig)
			b.tooltip_text = Ref.tr3(e.doc)
			b.add_theme_font_size_override("font_size", 14)
			b.clip_text = true
			b.custom_minimum_size = Vector2(270, 34)
			b.pressed.connect(_insert.bind(String(e.get("ins", e.sig))))
			rl.add_child(b)
			var d := UiKit.label(Ref.tr3(e.doc), 12, Color(0.58, 0.78, 0.7))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(270, 0)
			rl.add_child(d)


func open_project(id: String) -> void:
	var p := read_project(id)
	if p.is_empty():
		_show_list()
		return
	project = p
	_list_view.visible = false
	_edit_view.visible = true
	_title.text = "%s  %s" % ["🧩" if String(p.kind) == "mod" else "🎨", String(p.name)]
	(_edit_view.find_child("NewFile", true, false) as Control).visible = String(p.kind) == "mod"
	(_edit_view.find_child("Peek", true, false) as Control).visible = String(p.kind) == "shader"
	_file = "main.py" if p.files.has("main.py") else String(p.files.keys()[0])
	_refresh_files()
	_load_file(_file)
	_fill_reference()
	_console.clear()
	_out(GS.t("Проект открыт. «Проверить» запускает мод и показывает, что он добавил; «Испытать» — бой с этим модом; «Экспорт» — файл для «Создания мира»."), Color(0.6, 0.85, 0.75))
	if String(p.kind) == "shader":
		_preview_now()


func _refresh_files() -> void:
	for c in _files_box.get_children():
		c.queue_free()
	var names: Array = project.files.keys()
	names.sort()
	if names.has("main.py"):
		names.erase("main.py")
		names.push_front("main.py")
	for nm in names:
		var b := Button.new()
		b.text = String(nm)
		b.toggle_mode = true
		b.button_pressed = nm == _file
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(180, 38)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void:
			_store_file()
			_file = String(nm)
			_load_file(_file)
			_refresh_files())
		_files_box.add_child(b)


func _load_file(nm: String) -> void:
	_code.text = String(project.files.get(nm, ""))
	_code.clear_undo_history()
	_code.set_caret_line(0)
	_clear_error()
	_style_code()


func _store_file() -> void:
	if project.is_empty() or _code == null:
		return
	project.files[_file] = _code.text


func _on_text_changed() -> void:
	_dirty = true
	_save_t = 1.5
	_clear_error()
	if String(project.get("kind", "")) == "shader":
		_preview_t = 0.8
	# completion pops up by itself after "uad." and while a name is being typed
	var line := _code.get_line(_code.get_caret_line()).left(_code.get_caret_column())
	if line.ends_with(".") or RegEx.create_from_string("[A-Za-z_]{2,}$").search(line) != null:
		_code.request_code_completion()


func _process(delta: float) -> void:
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_now()
	if _preview_t > 0.0:
		_preview_t -= delta
		if _preview_t <= 0.0:
			_preview_now()


func _save_now() -> void:
	if project.is_empty() or not _dirty:
		return
	_store_file()
	save_project(project)
	_dirty = false


func _set_font(n: int) -> void:
	_font = clampi(n, 11, 30)
	GS.settings["code_font"] = _font
	_code.add_theme_font_size_override("font_size", _font)


func _style_code() -> void:
	_code.add_theme_font_size_override("font_size", _font)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Roboto Mono", "Droid Sans Mono", "Menlo", "monospace"])
	_code.add_theme_font_override("font", mono)
	_code.add_theme_color_override("background_color", Color(0.01, 0.04, 0.04, 0.95))
	_code.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
	_code.add_theme_color_override("current_line_color", Color(0.1, 0.25, 0.18, 0.35))
	_code.add_theme_color_override("caret_color", UiKit.NEON)
	_code.add_theme_color_override("line_number_color", Color(0.35, 0.55, 0.48))
	_code.add_theme_color_override("selection_color", Color(0.2, 0.55, 0.4, 0.5))
	var h := CodeHighlighter.new()
	h.number_color = Color(0.95, 0.75, 0.45)
	h.symbol_color = Color(0.7, 0.85, 0.95)
	h.function_color = Color(0.5, 0.85, 1.0)
	h.member_variable_color = Color(0.75, 0.9, 0.8)
	if String(project.get("kind", "mod")) == "shader":
		for k in ["shader_type", "uniform", "void", "float", "vec2", "vec3", "vec4", "int", "bool", "if", "else", "for", "return", "const", "in", "out", "sampler2D", "mat3", "mat4", "true", "false"]:
			h.add_keyword_color(k, Color(1.0, 0.55, 0.65))
		for k in ["COLOR", "UV", "SCREEN_UV", "TIME", "FRAGCOORD", "SCREEN_PIXEL_SIZE", "TEXTURE"]:
			h.add_keyword_color(k, Color(0.95, 0.85, 0.4))
		h.add_color_region("//", "", Color(0.45, 0.6, 0.55), true)
		h.add_color_region("/*", "*/", Color(0.45, 0.6, 0.55))
	else:
		for k in Parser.KEYWORDS:
			h.add_keyword_color(k, Color(1.0, 0.55, 0.65))
		for k in ["self", "print", "len", "range", "int", "float", "str", "list", "dict", "min", "max", "sum", "round", "abs", "sorted", "enumerate", "zip", "isinstance", "super"]:
			h.add_keyword_color(k, Color(0.6, 0.8, 1.0))
		h.add_keyword_color("uad", Color(0.35, 1.0, 0.65))
		h.add_color_region("#", "", Color(0.45, 0.6, 0.55), true)
		h.add_color_region("\"\"\"", "\"\"\"", Color(0.9, 0.85, 0.5))
		h.add_color_region("\"", "\"", Color(0.9, 0.85, 0.5), false)
		h.add_color_region("'", "'", Color(0.9, 0.85, 0.5), false)
	_code.syntax_highlighter = h


## Completion: the "uad" names after "uad.", Python's words and the file's own names otherwise.
func _complete() -> void:
	var line := _code.get_line(_code.get_caret_line()).left(_code.get_caret_column())
	var shader := String(project.get("kind", "mod")) == "shader"
	if line.ends_with("uad.") or RegEx.create_from_string("uad\\.[A-Za-z_]*$").search(line) != null:
		for e in Ref.api_names():
			_code.add_code_completion_option(CodeEdit.KIND_FUNCTION, String(e[0]), String(e[1]), Color(0.35, 1.0, 0.65))
	elif line.ends_with("@"):
		_code.add_code_completion_option(CodeEdit.KIND_FUNCTION, "uad.on(\"…\")", "uad.on(\"kill\")", Color(0.35, 1.0, 0.65))
	else:
		var words := {}
		for w in (Ref.SHADER_WORDS if shader else Parser.KEYWORDS + Ref.PY_BUILTINS):
			words[w] = true
		for m in RegEx.create_from_string("\\b[A-Za-z_][A-Za-z0-9_]{2,}\\b").search_all(_code.text):
			words[m.get_string()] = true
		for w in words:
			_code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, String(w), String(w))
	_code.update_code_completion_options(false)


func _insert(text: String) -> void:
	SFX.play("click", -10.0)
	var line := _code.get_caret_line()
	var indent := ""
	var cur := _code.get_line(line)
	for c in cur:
		if c == " " or c == "\t":
			indent += c
		else:
			break
	var lines := text.split("\n")
	for i in range(1, lines.size()):
		lines[i] = indent + lines[i]
	_code.insert_text_at_caret("\n".join(lines))
	_code.grab_focus()


## A row of the keys a touch keyboard hides: Tab, brackets, quotes, colon, undo.
func _key_bar() -> Control:
	var h := UiKit.hbox(4)
	for k in [["⇥", "    "], [":", ":"], ["( )", "()"], ["[ ]", "[]"], ["\" \"", "\"\""], ["=", "="], ["_", "_"], [".", "."], ["#", "# "], ["↶", "undo"], ["↷", "redo"]]:
		var b := Button.new()
		b.text = String(k[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(54, 44)
		b.add_theme_font_size_override("font_size", 18)
		var what := String(k[1])
		b.pressed.connect(func() -> void:
			if what == "undo":
				_code.undo()
			elif what == "redo":
				_code.redo()
			else:
				_code.insert_text_at_caret(what)
				if what.length() == 2 and what[0] != " ":
					_code.set_caret_column(_code.get_caret_column() - 1)
			_code.grab_focus())
		h.add_child(b)
	return h


func _out(text: String, color := Color(0.8, 0.95, 0.88)) -> void:
	_console.push_color(color)
	_console.add_text(text + "\n")
	_console.pop()


func _say(text: String, color: Color) -> void:
	_out(text, color)


func _clear_error() -> void:
	if _error_line >= 0 and _error_line < _code.get_line_count():
		_code.set_line_background_color(_error_line, Color(0, 0, 0, 0))
	_error_line = -1


func _mark_error(file: String, line: int) -> void:
	if file != "" and project.files.has(file) and file != _file:
		_store_file()
		_file = file
		_load_file(file)
		_refresh_files()
	if line > 0 and line <= _code.get_line_count():
		_error_line = line - 1
		_code.set_line_background_color(_error_line, Color(0.6, 0.1, 0.1, 0.45))
		_code.set_caret_line(_error_line)
		_code.center_viewport_to_caret()


# --- check, test, export --------------------------------------------------------------------
## Runs the mod on the game's tables (put back right after) and tells what it added and changed.
func _check() -> void:
	_store_file()
	_save_now()
	_console.clear()
	if String(project.kind) == "shader":
		await _check_shader()
		return
	var pkg := package()
	if pkg.has("error"):
		_out(GS.t(String(pkg.error)), UiKit.RED)
		return
	var lines := []
	var w0 := GS.WEAPONS.duplicate(true)
	var e0 := GS.ENEMIES.duplicate(true)
	var raid0: Dictionary = GS.city_def(GS.city_id).raid.duplicate(true)
	var hist := Mods.history.size()
	var errs := Mods.activate([pkg])
	for h in Mods.history.slice(hist):
		if not bool(h.error):
			lines.append(["print", String(h.text)])
	if errs.is_empty():
		for id in GS.WEAPONS:
			if not w0.has(id):
				lines.append(["add", GS.t("Новая система: %s (%s)") % [GS.t(String(GS.WEAPONS[id].name)), id]])
			elif str(w0[id]) != str(GS.WEAPONS[id]):
				lines.append(["chg", GS.t("Изменена система: %s") % id])
		for id in GS.ENEMIES:
			if not e0.has(id):
				lines.append(["add", GS.t("Новая угроза: %s (%s)") % [GS.t(String(GS.ENEMIES[id].name)), id]])
			elif str(e0[id]) != str(GS.ENEMIES[id]):
				lines.append(["chg", GS.t("Изменена угроза: %s") % id])
		if str(raid0) != str(GS.city_def(GS.city_id).raid):
			lines.append(["chg", GS.t("Налёты на город изменены")])
		for ev in Mods.handlers:
			lines.append(["ev", GS.t("Событие «%s»: обработчиков %d") % [ev, Mods.handlers[ev].size()]])
	Mods.deactivate()
	for l in lines:
		var col: Color = {"print": Color(0.85, 0.95, 0.9), "add": UiKit.NEON, "chg": UiKit.AMBER, "ev": UiKit.CYAN}[l[0]]
		_out(String(l[1]), col)
	if not errs.is_empty():
		var e: Dictionary = errs[0]
		_out(String(e.text), UiKit.RED)
		_mark_error(String(e.file), int(e.line))
		return
	if lines.is_empty():
		_out(GS.t("Мод запустился, но ничего не добавил."), UiKit.AMBER)
	_out(GS.t("✔ Ошибок нет."), UiKit.NEON)


func _check_shader() -> void:
	var pkg := package()
	if pkg.has("error"):
		_out(GS.t(String(pkg.error)), UiKit.RED)
		return
	if DisplayServer.get_name() == "headless":
		_out(GS.t("✔ Ошибок нет."), UiKit.NEON)
		return
	# the check compiles the shader by itself (the preview takes a broken one off on its own)
	Mods.preview("", null)
	var mark := Mods.shader_mark()
	# drawn (a shader is compiled when it is first drawn), but only a pixel in the corner
	var probe := ColorRect.new()
	probe.size = Vector2(1, 1)
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = Mods.shader_code(String(pkg.code))
	var mat := ShaderMaterial.new()
	mat.shader = sh
	probe.material = mat
	add_child(probe)
	for i in 4:
		await get_tree().process_frame
	var errs := Mods.shader_errors(mark)
	probe.queue_free()
	if errs.is_empty():
		Mods.preview(String(pkg.code), self)
		_out(GS.t("✔ Ошибок нет. Картинка за редактором — с этим шейдером; «Смотреть» убирает редактор."), UiKit.NEON)
		return
	var offset := 0 if String(pkg.code).contains("shader_type") else 1
	for e in errs:
		_out(GS.t("Строка %d: %s") % [int(e[0]) - offset, String(e[1])], UiKit.RED)
	_mark_error("", int(errs[0][0]) - offset)


func _preview_now() -> void:
	if String(project.get("kind", "")) != "shader" or DisplayServer.get_name() == "headless":
		return
	_store_file()
	var pkg := package()
	Mods.preview("" if pkg.has("error") else String(pkg.code), self)


func _toggle_peek() -> void:
	_peek = not _peek
	_edit_view.visible = not _peek
	_peek_bar.visible = _peek
	var dim: Control = get_child(0)
	dim.visible = not _peek


## A battle with the mod: a new world that is never saved, money to try things with.
func _test() -> void:
	_store_file()
	_save_now()
	var pkg := package()
	if pkg.has("error"):
		_console.clear()
		_out(GS.t(String(pkg.error)), UiKit.RED)
		return
	main.start_mod_test(Mods.for_world(pkg), String(project.id))


func _export() -> void:
	_store_file()
	_save_now()
	var pkg := package()
	if pkg.has("error"):
		_console.clear()
		_out(GS.t(String(pkg.error)), UiKit.RED)
		return
	if String(pkg.kind) == "mod":
		var p := Parser.parse(String(pkg.files["main.py"]))
		if p.has("error"):
			_console.clear()
			_out("%s (main.py, %s %d)" % [p.error, GS.t("строка"), int(p.line)], UiKit.RED)
			_mark_error("main.py", int(p.line))
			return
	var installed := Mods.install(pkg)
	var dir := Mods.share_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(Mods.file_name(pkg))
	var wrote := Mods.write_package(pkg, path) if not Mods.dry else true
	var m := UiKit.modal(self, Vector2(560, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Мод экспортирован"), 30, UiKit.NEON))
	var shown := ProjectSettings.globalize_path(path) if wrote else GS.t("(файл не записан: папка недоступна)")
	var l := UiKit.label(shown, 15, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	v.add_child(l)
	var hint := UiKit.label(GS.t("Мод уже установлен: он есть в разделе «Моды» при создании мира. Файл можно отправить другу — он импортирует его там же."), 14, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	v.add_child(hint)
	if installed.has("error"):
		v.add_child(UiKit.label(GS.t(String(installed.error)), 14, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER))
	if OS.has_feature("pc") and wrote:
		v.add_child(UiKit.button(GS.t("Открыть папку"), func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))))
	v.add_child(UiKit.button(GS.t("Готово"), func() -> void: _modal.queue_free()))


func _ask_new_file() -> void:
	var m := UiKit.modal(self, Vector2(460, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Новый файл"), 28, UiKit.NEON))
	v.add_child(UiKit.label(GS.t("Имя модуля (его подключают так: import имя)"), 14, Color(0.65, 0.88, 0.78)))
	var e := LineEdit.new()
	e.max_length = 24
	e.placeholder_text = "helpers"
	e.custom_minimum_size = Vector2(420, 44)
	v.add_child(e)
	var err := UiKit.label("", 14, UiKit.RED)
	v.add_child(err)
	v.add_child(UiKit.button(GS.t("Создать"), func() -> void:
		var n := e.text.strip_edges().to_lower().trim_suffix(".py")
		if RegEx.create_from_string("^[a-z_][a-z0-9_]{0,23}$").search(n) == null or n == "main" or n == "uad":
			err.text = GS.t("Только латинские буквы, цифры и _.")
			return
		if project.files.size() >= Mods.MAX_FILES:
			err.text = GS.t("Слишком много файлов.")
			return
		_store_file()
		project.files[n + ".py"] = "# %s.py\nimport uad\n\n" % n
		_file = n + ".py"
		_dirty = true
		_save_now()
		_refresh_files()
		_load_file(_file)
		_modal.queue_free()))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _modal.queue_free()))
	e.grab_focus.call_deferred()


func _ask_details() -> void:
	var m := UiKit.modal(self, Vector2(560, 0))
	_modal = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Сведения о моде"), 28, UiKit.NEON))
	var fields := {}
	for spec in [["name", GS.t("Название"), 48], ["author", GS.t("Автор"), 48], ["version", GS.t("Версия"), 16], ["description", GS.t("Описание"), 600]]:
		v.add_child(UiKit.label(String(spec[1]), 14, UiKit.AMBER))
		var e := LineEdit.new()
		e.max_length = int(spec[2])
		e.text = String(project.get(spec[0], ""))
		e.custom_minimum_size = Vector2(520, 42)
		v.add_child(e)
		fields[spec[0]] = e
	v.add_child(UiKit.button(GS.t("Сохранить"), func() -> void:
		for k in fields:
			var t: String = (fields[k] as LineEdit).text.strip_edges()
			if k == "name" and t == "":
				continue
			project[k] = t
		_dirty = true
		_save_now()
		_title.text = "%s  %s" % ["🧩" if String(project.kind) == "mod" else "🎨", String(project.name)]
		_modal.queue_free()))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: _modal.queue_free()))


func _close() -> void:
	_save_now()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _modal != null and is_instance_valid(_modal):
			_modal.queue_free()
		elif _peek:
			_toggle_peek()
		elif not project.is_empty():
			_show_list()
		else:
			_close()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F5 and not project.is_empty():
		get_viewport().set_input_as_handled()
		_check()
