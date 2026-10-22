extends RefCounted
## Mods: what a world is played with besides the game itself.
##
## Two kinds of files, both carried around like world files:
##   «<name>.uadmod»    — a mod: a zip with mod.json ({id, name, author, version, description}) and
##                        Python files (main.py runs first, the others are `import`-ed by it), and
##                        optionally *.uadshader pictures it always brings along;
##   «<name>.uadshader» — a picture mod: the text of a Godot canvas_item shader laid over the 3D view
##                        (the HUD stays clear), with "// name: …" / "// author: …" / "// description: …"
##                        comment lines at the top.
## Installed ones live in user://mods/. A world is created with a choice of them and keeps a copy of
## each in its save (GS.mods), so it plays the same wherever it goes and whatever is installed.
##
## When a world opens (main._start_session) activate() runs every mod's main.py in its own
## interpreter (py_vm.gd, the "uad" module of mod_api.gd): the definitions change GS.WEAPONS / ENEMIES
## and the city's raid, the handlers wait for the game's events (emit()). deactivate() puts every
## table back when the world closes. A world with code mods earns no achievements and is not opened
## to friends.

const VM = preload("res://scripts/mods/py_vm.gd")
const Api = preload("res://scripts/mods/mod_api.gd")
const Achievements = preload("res://scripts/core/achievements.gd")

const MOD_EXT := "uadmod"
const SHADER_EXT := "uadshader"
## A 3D model of the mod's own (scripts/mods/model3d.gd), inside a .uadmod.
const MODEL_EXT := "uadmodel"
const DIR := "user://mods/"
const MAX_FILE := 2 * 1024 * 1024
const MAX_FILES := 40
const MAX_TEXT := 400000
## Steps a mod's main.py may take when the world opens, and an event handler each time.
const LOAD_STEPS := 1500000
const EVENT_STEPS := 60000
## A handler that fails this many times is switched off for the rest of the session.
const MAX_FAILS := 3

## The session the mods act in (game_controller.gd), null outside the game.
static var game = null
static var main = null
## Running mods: [{"mod": package, "vm": VM, "fails": {}}].
static var running: Array = []
## event → [[vm, mod, fn], …]
static var handlers := {}
## Shaders laid over the view now: [{"id", "name", "code"}].
static var shaders: Array = []
## What the mods printed and the errors they raised, newest last: [{"mod", "text", "error"}].
static var history: Array = []
## Errors of the last activate(), for the HUD to tell.
static var errors: Array = []
static var _busy := false
static var _tick_t := 0.0
static var _clock := 0.0
static var _raid_backup = null
static var _translations: Array = []
static var _tr_pending := {}
static var _layer: CanvasLayer
static var _rects: Array = []
static var _params := {}
## Self-test runs: nothing is written to the player's mods folder.
static var dry := false
static var _mem := {}


# --- packages -----------------------------------------------------------------------------------
## A file read and checked: a package {kind: "mod" | "shader", id, name, author, version,
## description, files: {"main.py": text, …} | code: text, shaders: [...]} or {"error": sentence}.
static func read_package(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == SHADER_EXT:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {"error": "Файл не открывается."}
		if f.get_length() > MAX_TEXT:
			return {"error": "Файл слишком большой."}
		var code := f.get_as_text()
		f.close()
		return shader_package(code, path.get_file().get_basename())
	if ext != MOD_EXT:
		return {"error": "Это не мод UAD (.uadmod или .uadshader)."}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"error": "Файл не открывается."}
	if bytes.size() > MAX_FILE:
		return {"error": "Файл слишком большой."}
	var zip := ZIPReader.new()
	# ZIPReader opens files only: a copy in user:// for one coming from a content:// picker
	# (the bytes are read already: a content:// path of Android's file picker is fine though
	# FileAccess.file_exists() says no to it)
	var tmp := ""
	if zip.open(path) != OK:
		tmp = "user://mod_import.tmp"
		var w := FileAccess.open(tmp, FileAccess.WRITE)
		if w == null:
			return {"error": "Файл не открывается."}
		w.store_buffer(bytes)
		w.close()
		if zip.open(tmp) != OK:
			DirAccess.remove_absolute(tmp)
			return {"error": "Это не мод UAD или он повреждён."}
	var files := {}
	var meta := {}
	var names := zip.get_files()
	if names.size() > MAX_FILES * 2:
		zip.close()
		return {"error": "В моде слишком много файлов."}
	for nm in names:
		var name := String(nm)
		if name.ends_with("/"):
			continue
		var data := zip.read_file(name)
		if data.size() > MAX_TEXT:
			continue
		var text := data.get_string_from_utf8()
		if name.get_file() == "mod.json":
			var j := JSON.new()
			if j.parse(text) == OK and j.data is Dictionary:
				meta = j.data
		elif name.get_extension() in ["py", SHADER_EXT, MODEL_EXT, "txt", "md"]:
			files[name.get_file()] = text
	zip.close()
	if tmp != "":
		DirAccess.remove_absolute(tmp)
	return mod_package(meta, files, path.get_file().get_basename())


## A mod package from its parts (also what a world's save holds), checked.
static func mod_package(meta: Dictionary, files: Dictionary, fallback_id: String) -> Dictionary:
	if not files.has("main.py"):
		return {"error": "В моде нет файла main.py."}
	var clean := {}
	for k in files:
		if clean.size() >= MAX_FILES:
			break
		var name := String(k).get_file()
		if name.get_extension() in ["py", SHADER_EXT, MODEL_EXT, "txt", "md"] and String(files[k]).length() <= MAX_TEXT:
			clean[name] = String(files[k])
	var shaders_in := []
	for k in clean:
		if String(k).get_extension() == SHADER_EXT:
			var sp := shader_package(String(clean[k]), String(k).get_basename())
			if not sp.has("error"):
				shaders_in.append(sp)
	return {"kind": "mod", "id": safe_id(String(meta.get("id", fallback_id))), "name": String(meta.get("name", fallback_id)).left(48),
		"author": String(meta.get("author", "")).left(48), "version": String(meta.get("version", "1.0")).left(16),
		"description": String(meta.get("description", "")).left(600), "files": clean, "shaders": shaders_in}


## A picture mod from its text: the name and the rest from the "// key: value" lines at the top.
static func shader_package(code: String, fallback_id: String) -> Dictionary:
	if code.length() > MAX_TEXT:
		return {"error": "Файл слишком большой."}
	var meta := {}
	for line in code.split("\n"):
		var l := String(line).strip_edges()
		if l == "":
			continue
		if not l.begins_with("//"):
			break
		var kv := l.trim_prefix("//").split(":", true, 1)
		if kv.size() == 2:
			meta[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
	if not code.contains("fragment"):
		return {"error": "В шейдере нет функции fragment()."}
	return {"kind": "shader", "id": safe_id(String(meta.get("id", fallback_id))), "name": String(meta.get("name", fallback_id)).left(48),
		"author": String(meta.get("author", "")).left(48), "version": String(meta.get("version", "1.0")).left(16),
		"description": String(meta.get("description", "")).left(600), "code": code}


static func safe_id(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
		elif c == " ":
			out += "_"
	out = out.left(32)
	return out if out != "" else "mod"


## The package as one file: a zip for a mod, the text for a picture mod.
static func write_package(pkg: Dictionary, path: String) -> bool:
	if String(pkg.get("kind", "")) == "shader":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(String(pkg.code))
		f.close()
		return true
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return false
	var meta := {"id": pkg.id, "name": pkg.name, "author": pkg.get("author", ""), "version": pkg.get("version", "1.0"),
		"description": pkg.get("description", ""), "game": GS.WORLD_FILE_VERSION}
	zip.start_file("mod.json")
	zip.write_file(JSON.stringify(meta, "\t").to_utf8_buffer())
	zip.close_file()
	var files: Dictionary = pkg.get("files", {})
	for k in files:
		zip.start_file(String(k))
		zip.write_file(String(files[k]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return true


static func file_name(pkg: Dictionary) -> String:
	return String(pkg.id) + "." + (SHADER_EXT if String(pkg.kind) == "shader" else MOD_EXT)


# --- installed mods -----------------------------------------------------------------------------
## The installed mods and picture mods, each with "path"; mods first, then by name.
static func installed() -> Array:
	var out := []
	if dry:
		for k in _mem:
			out.append(_mem[k])
	else:
		var dir := DirAccess.open(DIR)
		if dir != null:
			for fname in dir.get_files():
				var ext := String(fname).get_extension().to_lower()
				if ext != MOD_EXT and ext != SHADER_EXT:
					continue
				var p := read_package(DIR + fname)
				if p.has("error"):
					continue
				p["path"] = DIR + fname
				out.append(p)
	out.sort_custom(func(a, b) -> bool:
		if String(a.kind) != String(b.kind):
			return String(a.kind) == "mod"
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


## Installs a package (replacing an older one of the same id and kind). Returns it or {"error"}.
static func install(pkg: Dictionary) -> Dictionary:
	if pkg.has("error"):
		return pkg
	var p := pkg.duplicate(true)
	p.erase("path")
	if dry:
		p["path"] = "mem://" + file_name(p)
		_mem[file_name(p)] = p
		return p
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + file_name(p)
	if not write_package(p, path):
		return {"error": "Папка модов недоступна для записи."}
	p["path"] = path
	return p


static func install_file(path: String) -> Dictionary:
	return install(read_package(path))


static func uninstall(pkg: Dictionary) -> void:
	if dry:
		_mem.erase(file_name(pkg))
		return
	DirAccess.remove_absolute(DIR + file_name(pkg))


## Where mod files are looked for to install, and where the workshop writes them: Documents/UAD/Mods.
static func share_dir() -> String:
	return GS.player_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("UAD").path_join("Mods")


## Mod files lying in Documents/UAD/Mods and in Downloads: [{"path", "name", "kind", "time"}].
static func found_files() -> Array:
	var out := []
	var seen := {}
	for dir in [share_dir(), GS.player_dir(OS.SYSTEM_DIR_DOWNLOADS)]:
		if dir == "" or not DirAccess.dir_exists_absolute(dir):
			continue
		for fname in DirAccess.get_files_at(dir):
			var ext := String(fname).get_extension().to_lower()
			if ext != MOD_EXT and ext != SHADER_EXT:
				continue
			var path: String = dir.path_join(fname)
			if seen.has(path):
				continue
			seen[path] = true
			var p := read_package(path)
			if p.has("error"):
				continue
			out.append({"path": path, "name": String(p.name), "kind": String(p.kind), "version": String(p.version), "time": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b) -> bool: return int(a.time) > int(b.time))
	return out


## The package as a world keeps it (no path) — only what is needed to run it.
static func for_world(pkg: Dictionary) -> Dictionary:
	var p := pkg.duplicate(true)
	p.erase("path")
	return p


## A world's list of packages, checked (a save may come from anywhere).
static func sanitize(list) -> Array:
	var out := []
	if not (list is Array):
		return out
	for x in list:
		if not (x is Dictionary):
			continue
		var p: Dictionary
		if String(x.get("kind", "")) == "shader":
			p = shader_package(String(x.get("code", "")), String(x.get("id", "shader")))
		elif x.get("files") is Dictionary:
			p = mod_package(x, x.files, String(x.get("id", "mod")))
		else:
			continue
		if not p.has("error"):
			out.append(p)
		if out.size() >= 16:
			break
	return out


static func has_code(list := []) -> bool:
	for p in (list if not list.is_empty() else GS.mods):
		if String(p.get("kind", "")) == "mod":
			return true
	return false


static func names_of(list: Array) -> String:
	var n := PackedStringArray()
	for p in list:
		n.append(String(p.name))
	return ", ".join(n)


# --- running ----------------------------------------------------------------------------------
## Puts the game's own tables back and stops every mod.
static func deactivate() -> void:
	for r in running:
		r.vm.dispose()
	running.clear()
	handlers.clear()
	errors.clear()
	game = null
	GS.WEAPONS = GS.BASE_WEAPONS.duplicate(true)
	GS.ENEMIES = GS.BASE_ENEMIES.duplicate(true)
	GS.WEAPON_ORDER = GS.BASE_WEAPON_ORDER.duplicate()
	GS.AMMO_ORDER = GS.BASE_AMMO_ORDER.duplicate()
	if _raid_backup != null:
		var def = _raid_backup[0]
		def.raid = _raid_backup[1]
		_raid_backup = null
	for t in _translations:
		TranslationServer.remove_translation(t)
	_translations.clear()
	_tr_pending.clear()
	_clear_overlay()
	shaders.clear()
	_params.clear()
	Achievements.off = false
	_busy = false


## Runs the world's mods: their definitions take effect now, their handlers wait for begin().
## Returns the errors [{"mod", "text", "line", "file"}] (a failed mod changes nothing).
static func activate(list: Array) -> Array:
	deactivate()
	Api.host = Mods_self()
	for pkg in list:
		if String(pkg.get("kind", "")) == "shader":
			shaders.append(pkg)
			continue
		var snap := [GS.WEAPONS.duplicate(true), GS.ENEMIES.duplicate(true), GS.WEAPON_ORDER.duplicate(), GS.AMMO_ORDER.duplicate(),
			_raid_now().duplicate(true), handlers.duplicate(true)]
		var vm := VM.new()
		var mod_name := String(pkg.name)
		vm.print_hook = func(s: String) -> void: _log(mod_name, s, false)
		for k in pkg.files:
			if String(k).get_extension() == "py":
				vm.sources[String(k).get_basename()] = String(pkg.files[k])
		vm.modules["uad"] = Api.make(vm, pkg)
		vm.budget(LOAD_STEPS)
		var r: Dictionary = vm.run_module("main", String(pkg.files["main.py"]), "main.py")
		if r.has("error"):
			GS.WEAPONS = snap[0]
			GS.ENEMIES = snap[1]
			GS.WEAPON_ORDER = snap[2]
			GS.AMMO_ORDER = snap[3]
			_set_raid(snap[4])
			handlers = snap[5]
			vm.dispose()
			var e := {"mod": mod_name, "text": String(r.error), "line": int(r.get("line", 0)), "file": String(r.get("file", "main.py"))}
			errors.append(e)
			_log(mod_name, String(r.error), true)
			continue
		running.append({"mod": pkg, "vm": vm, "fails": {}})
		for sp in pkg.get("shaders", []):
			shaders.append(sp)
	_flush_translations()
	Achievements.off = not running.is_empty()
	return errors.duplicate() # deactivate() clears the list itself


## The session began: the start event, the pictures over the view, the errors told.
static func begin(g, m) -> void:
	game = g
	main = m
	_clock = 0.0
	_tick_t = 0.0
	_build_overlay()
	for e in errors:
		say(GS.t("Мод «%s» не загрузился: %s") % [e.mod, String(e.text).get_slice("\n", String(e.text).get_slice_count("\n") - 1)], Color(1.0, 0.4, 0.3), false)
	if not running.is_empty():
		var n := PackedStringArray()
		for r in running:
			n.append(String(r.mod.name))
		say(GS.t("Моды: %s") % ", ".join(n), Color(0.6, 0.9, 1.0), false)
	emit("start", {"day": GS.day, "night": game.director != null and game.director.is_night()})


static func add_handler(vm, mod: Dictionary, ev: String, fn) -> void:
	if not handlers.has(ev):
		handlers[ev] = []
	handlers[ev].append([vm, mod, fn])


## Calls the handlers of an event. A handler that raises is told in the log; after MAX_FAILS
## failures it is switched off. Nothing a handler does starts another event (no loops).
static func emit(ev: String, data: Dictionary) -> void:
	if _busy or not handlers.has(ev) or game == null:
		return
	_busy = true
	var list: Array = handlers[ev]
	for h in list.duplicate():
		var vm = h[0]
		var fn = h[2]
		vm.budget(EVENT_STEPS)
		var args := [] if _arity(fn) == 0 else [data.duplicate(true)]
		vm.call_py(fn, args, {})
		if vm.failed():
			var info: Dictionary = vm.error_info()
			var mod_name := String(h[1].name)
			_log(mod_name, String(info.error), true)
			var key := "%s:%s" % [ev, str(fn.get_instance_id()) if fn is Object else ""]
			var fails := 0
			for r in running:
				if r.vm == vm:
					r.fails[key] = int(r.fails.get(key, 0)) + 1
					fails = int(r.fails[key])
			var last := String(info.error).get_slice("\n", String(info.error).get_slice_count("\n") - 1)
			say(GS.t("Ошибка в моде «%s» (строка %d): %s") % [mod_name, int(info.get("line", 0)), last], Color(1.0, 0.4, 0.3), false)
			if fails >= MAX_FAILS:
				list.erase(h)
				say(GS.t("Обработчик мода «%s» отключён до конца игры.") % mod_name, Color(1.0, 0.4, 0.3), false)
	_busy = false


## How many arguments a handler takes (0 or the one dict).
static func _arity(fn) -> int:
	if fn is VM.PyFunc:
		for p in fn.params:
			return 1
		return 0
	if fn is VM.PyBound:
		return 1 if fn.fn is VM.PyFunc and fn.fn.params.size() > 1 else 0
	return 1


## Once a frame from the game: the tick event every game second, the shaders' game uniforms.
static func process(delta: float) -> void:
	if game == null:
		return
	_clock += delta
	_tick_t += delta
	if _tick_t >= 1.0:
		_tick_t -= 1.0
		var night: bool = game.director != null and game.director.is_night()
		emit("tick", {"t": int(_clock), "night": night})
		_feed_shaders(night)


## Runs something of the game's from a handler without its own event firing back into the mods.
static func quiet(f: Callable) -> void:
	var was := _busy
	_busy = true
	f.call()
	_busy = was


static func say(text: String, color: Color, big: bool) -> void:
	if game == null or not is_instance_valid(game):
		return
	if big and game.hud != null and game.rl == null:
		game.hud.alert(text, color)
	elif game.rl != null:
		game.rl.radio(text, color)
	elif game.hud != null:
		game.hud.log_event(text, color)


static func _log(mod_name: String, text: String, is_error: bool) -> void:
	history.append({"mod": mod_name, "text": text, "error": is_error})
	if history.size() > 300:
		history = history.slice(history.size() - 300)
	print("MOD %s%s: %s" % [mod_name, " ERROR" if is_error else "", text])


## A mod's own persistent dict (uad.data), kept in the world's save.
static func data_of(id: String) -> Dictionary:
	if not (GS.mod_data.get(id) is Dictionary):
		GS.mod_data[id] = {}
	return GS.mod_data[id]


# --- what the API changes -----------------------------------------------------------------------
static func put(weapon: bool, id: String, entry: Dictionary, new: bool) -> void:
	if weapon:
		GS.WEAPONS[id] = entry
		if new:
			# into the shop section of its class: after the last system of that class
			var at := GS.WEAPON_ORDER.size()
			for i in GS.WEAPON_ORDER.size():
				if String(GS.WEAPONS[GS.WEAPON_ORDER[i]].get("class", "")) == String(entry.get("class", "")):
					at = i + 1
			GS.WEAPON_ORDER.insert(at, id)
		if entry.has("missile_price") and not GS.AMMO_ORDER.has(id):
			GS.AMMO_ORDER.append(id)
	else:
		GS.ENEMIES[id] = entry


static func _city():
	return GS.city_def(GS.city_id)


static func _raid_now() -> Dictionary:
	return _city().raid


static func _set_raid(r: Dictionary) -> void:
	_backup_raid()
	_city().raid = r


static func _backup_raid() -> void:
	if _raid_backup == null:
		var def = _city()
		_raid_backup = [def, (def.raid as Dictionary).duplicate(true)]


static func add_raid(slot: String, id: String, weight: float, night: int) -> void:
	_backup_raid()
	var r: Dictionary = _city().raid.duplicate(true)
	if not r.has(slot):
		r[slot] = []
	r[slot].append([id, weight, night])
	_city().raid = r


static func clear_raid(slot: String) -> void:
	_backup_raid()
	var r: Dictionary = _city().raid.duplicate(true)
	for k in (["drone", "cruise", "ballistic"] if slot == "" else [slot]):
		r[k] = []
	_city().raid = r


static func translate(ru: String, en: String, uk: String) -> void:
	if ru == "":
		return
	_tr_pending[ru] = [en, uk]


static func _flush_translations() -> void:
	if _tr_pending.is_empty():
		return
	var made := {}
	for loc in ["en", "uk"]:
		var t := Translation.new()
		t.locale = loc
		made[loc] = t
	for ru in _tr_pending:
		(made.en as Translation).add_message(ru, String(_tr_pending[ru][0]))
		(made.uk as Translation).add_message(ru, String(_tr_pending[ru][1]))
	for loc in made:
		TranslationServer.add_translation(made[loc])
		_translations.append(made[loc])
	_tr_pending.clear()


# --- pictures over the view ---------------------------------------------------------------------
## The shader as the engine takes it: shader_type added when the file leaves it out.
static func shader_code(code: String) -> String:
	if not code.contains("shader_type"):
		return "shader_type canvas_item;\n" + code
	return code


static func _build_overlay() -> void:
	_clear_overlay()
	if shaders.is_empty() or main == null or DisplayServer.get_name() == "headless":
		return
	_layer = CanvasLayer.new()
	_layer.layer = 2 # over the camera's own film (1), under the HUD and menus (10)
	main.add_child(_layer)
	_add_checked(shaders.duplicate(), _layer)


## Lays the pictures on one at a time; one the engine refuses to compile (it would paint the whole
## view grey) is taken off again and told about.
static func _add_checked(list: Array, layer: CanvasLayer) -> void:
	for sp in list:
		if layer == null or not is_instance_valid(layer) or layer != _layer:
			return
		var mark := shader_mark()
		var r := _overlay_rect(String(sp.code))
		_rects.append(r)
		layer.add_child(r)
		var tree := layer.get_tree()
		for i in 3:
			await tree.process_frame
		var errs := shader_errors(mark)
		if not is_instance_valid(layer):
			return # taken away meanwhile (the world closed, the preview changed)
		if not errs.is_empty() and is_instance_valid(r):
			_rects.erase(r)
			r.queue_free()
			var offset := 0 if String(sp.code).contains("shader_type") else 1
			say(GS.t("Графика «%s» не включена: строка %d — %s") % [String(sp.name), int(errs[0][0]) - offset, String(errs[0][1])], Color(1.0, 0.4, 0.3), false)


static func _overlay_rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = shader_code(code)
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in _params:
		m.set_shader_parameter(k, _params[k])
	r.material = m
	return r


static func _clear_overlay() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_rects.clear()


static func shader_param(name: String, value) -> void:
	if value is Array and value.size() in [2, 3, 4]:
		value = Vector4(float(value[0]), float(value[1]), float(value[2]) if value.size() > 2 else 0.0, float(value[3]) if value.size() > 3 else 1.0) if value.size() == 4 \
			else (Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector2(float(value[0]), float(value[1])))
	_params[name] = value
	for r in _rects:
		if is_instance_valid(r):
			((r as ColorRect).material as ShaderMaterial).set_shader_parameter(name, value)


## The game's own uniforms every picture mod may read: uad_night (0 / 1), uad_alarm (0 / 1),
## uad_city (city health 0..1).
static func _feed_shaders(night: bool) -> void:
	if _rects.is_empty():
		return
	var alarm := 1.0 if game != null and bool(game.alarm) else 0.0
	for r in _rects:
		if is_instance_valid(r):
			var m := (r as ColorRect).material as ShaderMaterial
			m.set_shader_parameter("uad_night", 1.0 if night else 0.0)
			m.set_shader_parameter("uad_alarm", alarm)
			m.set_shader_parameter("uad_city", GS.city / 100.0)


## A picture laid over whatever is behind the workshop (its preview); "" takes it away.
static func preview(code: String, host: Node) -> void:
	_clear_overlay()
	if code == "" or host == null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 2
	host.add_child(_layer)
	_add_checked([{"code": code, "name": ""}], _layer)


## The engine's complaints about shaders while `listening` (the workshop's check of a shader).
## Every complaint is numbered, so checks running at the same time each read their own:
## mark = shader_mark() before compiling, shader_errors(mark) a few frames after.
class ShaderLog extends Logger:
	var count := 0
	var lines: Array = []
	var _m := Mutex.new()

	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SHADER:
			return
		_m.lock()
		count += 1
		lines.append([count, line, (rationale if rationale != "" else code)])
		if lines.size() > 64:
			lines.pop_front()
		_m.unlock()

	func since(mark: int) -> Array:
		_m.lock()
		var out := []
		for l in lines:
			if int(l[0]) > mark:
				out.append([l[1], l[2]])
		_m.unlock()
		return out


static var shader_log: ShaderLog


static func shader_mark() -> int:
	if shader_log == null:
		shader_log = ShaderLog.new()
		OS.add_logger(shader_log)
	return shader_log.count


## [[line, message], …] the engine reported about shaders since the mark.
static func shader_errors(mark: int) -> Array:
	return shader_log.since(mark) if shader_log != null else []


## The class itself, for the API to call back into (static classes have no instance).
static func Mods_self():
	return load("res://scripts/mods/mods.gd")
