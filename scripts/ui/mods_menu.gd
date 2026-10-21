extends RefCounted
## The choice of a world's mods on the "create world" screen (scripts/ui/create_world.gd): the installed
## mods (.uadmod) and picture mods (.uadshader) to tick, their import, the way to the mod workshop.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Mods = preload("res://scripts/mods/mods.gd")


## The window over `parent`. `chosen` is the current choice (packages); on_change gets the new one,
## on_workshop opens the workshop.
static func pick(parent: Control, chosen: Array, on_change: Callable, on_workshop: Callable) -> Control:
	var m := UiKit.modal(parent, Vector2(700, 0))
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	var sel: Array = chosen.duplicate()
	v.add_child(UiKit.glow_label(GS.t("МОДЫ МИРА"), 32, UiKit.NEON))
	var hint := UiKit.label(GS.t("Отметьте моды (.uadmod) и графику (.uadshader), с которыми будет играться этот мир. Мир хранит их копию."), 14, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(660, 0)
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var warn := UiKit.label("", 13, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(660, 0)
	var refresh := func() -> void: pass
	refresh = func() -> void:
		for c in list.get_children():
			c.queue_free()
		var all := Mods.installed()
		if all.is_empty():
			var e := UiKit.label(GS.t("Модов пока нет. Импортируйте файл мода или сделайте свой в мастерской."), 15, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
			e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			e.custom_minimum_size = Vector2(640, 60)
			list.add_child(e)
		for p in all:
			list.add_child(_row(p, sel, func() -> void:
				on_change.call(sel.duplicate())
				warn.text = GS.t("С модами-кодом достижения в этом мире не засчитываются, и его нельзя открыть друзьям.") if Mods.has_code(sel) else ""))
		warn.text = GS.t("С модами-кодом достижения в этом мире не засчитываются, и его нельзя открыть друзьям.") if Mods.has_code(sel) else ""
	refresh.call()
	v.add_child(warn)
	var row := UiKit.hbox(8)
	v.add_child(row)
	var imp := UiKit.button(GS.t("Импорт мода…"), func() -> void: ask_import(parent, refresh), 210, 18)
	var ws := UiKit.button(GS.t("Мастерская модов"), func() -> void:
		root.queue_free()
		on_workshop.call(), 210, 18)
	var done := UiKit.button(GS.t("Готово"), func() -> void: root.queue_free(), 210, 18)
	for b in [imp, ws, done]:
		b.custom_minimum_size = Vector2(214, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return root


## One mod: a toggle with its name, kind and author, the description under it, "remove" beside it.
static func _row(p: Dictionary, sel: Array, changed: Callable) -> Control:
	var box := UiKit.vbox(2)
	var h := UiKit.hbox(6)
	box.add_child(h)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(560, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 17)
	var icon := "🧩" if String(p.kind) == "mod" else "🎨"
	var by := (" · " + String(p.author)) if String(p.get("author", "")) != "" else ""
	var idx := _index_of(sel, p)
	b.button_pressed = idx >= 0
	b.text = "%s  %s  v%s%s" % [icon, String(p.name), String(p.version), by]
	b.toggled.connect(func(on: bool) -> void:
		SFX.play("click", -8.0)
		var i := _index_of(sel, p)
		if on and i < 0:
			sel.append(Mods.for_world(p))
		elif not on and i >= 0:
			sel.remove_at(i)
		changed.call())
	h.add_child(b)
	var del := Button.new()
	del.text = "🗑"
	del.tooltip_text = GS.t("Удалить мод с устройства")
	del.focus_mode = Control.FOCUS_NONE
	del.custom_minimum_size = Vector2(52, 46)
	del.pressed.connect(func() -> void:
		var i := _index_of(sel, p)
		if i >= 0:
			sel.remove_at(i)
		Mods.uninstall(p)
		box.queue_free()
		changed.call())
	h.add_child(del)
	if String(p.get("description", "")) != "":
		var d := UiKit.label(String(p.description), 13, Color(0.6, 0.82, 0.74))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(620, 0)
		box.add_child(d)
	return box


static func _index_of(sel: Array, p: Dictionary) -> int:
	for i in sel.size():
		if String(sel[i].id) == String(p.id) and String(sel[i].kind) == String(p.kind):
			return i
	return -1


## The import window: mod files found in Documents/UAD/Mods and Downloads, the system's file picker,
## and (on a computer) dragging a file onto the window. `done` runs after a file is installed.
static func ask_import(parent: Control, done: Callable) -> void:
	var m := UiKit.modal(parent, Vector2(560, 0))
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Импорт мода"), 30, UiKit.NEON))
	var dir := ProjectSettings.globalize_path(Mods.share_dir())
	var l := UiKit.label(GS.t("Файлы модов (.uadmod, .uadshader) в папке %s и в «Загрузках»:") % dir, 14, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	v.add_child(l)
	var status := UiKit.label("", 15, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(520, 0)
	var take := func(path: String) -> void:
		var r := Mods.install_file(path)
		if r.has("error"):
			status.add_theme_color_override("font_color", UiKit.RED)
			status.text = GS.t("Не удалось импортировать: %s") % GS.t(String(r.error))
			return
		SFX.play("click", -6.0, 1.3)
		status.add_theme_color_override("font_color", UiKit.NEON)
		status.text = GS.t("Установлено: %s") % String(r.name)
		done.call()
	var files := Mods.found_files()
	if files.is_empty():
		var e := UiKit.label(GS.t("Здесь пока нет файлов модов. Положите файл в эту папку или выберите его вручную."), 15, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(520, 0)
		v.add_child(e)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(520, mini(files.size(), 4) * 58)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(scroll)
		var list := UiKit.vbox(6)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for f in files:
			var b := UiKit.button("%s  %s  v%s" % ["🧩" if String(f.kind) == "mod" else "🎨", String(f.name), String(f.version)], take.bind(String(f.path)), 500, 17)
			b.custom_minimum_size = Vector2(500, 50)
			list.add_child(b)
	v.add_child(status)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		v.add_child(UiKit.button(GS.t("Выбрать файл…"), func() -> void:
			var filters := PackedStringArray() if OS.has_feature("mobile") else PackedStringArray(["*.%s, *.%s ; %s" % [Mods.MOD_EXT, Mods.SHADER_EXT, GS.t("Мод UAD")]])
			DisplayServer.file_dialog_show(GS.t("Выберите файл мода"), dir, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
				func(ok: bool, paths: PackedStringArray, _f: int) -> void:
					if ok and paths.size() > 0:
						take.call_deferred(String(paths[0])))))
	if OS.has_feature("pc"):
		v.add_child(UiKit.label(GS.t("Можно и просто перетащить файл мода в окно игры."), 13, Color(0.55, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
		var w := parent.get_window()
		var on_drop := func(paths: PackedStringArray) -> void:
			for p in paths:
				if String(p).get_extension().to_lower() in [Mods.MOD_EXT, Mods.SHADER_EXT]:
					take.call(String(p))
		w.files_dropped.connect(on_drop)
		root.tree_exiting.connect(func() -> void:
			if w.files_dropped.is_connected(on_drop):
				w.files_dropped.disconnect(on_drop))
	v.add_child(UiKit.button(GS.t("Готово"), func() -> void: root.queue_free()))
