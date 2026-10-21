extends RefCounted
## The "uad" module a mod's Python imports (scripts/mods/mods.gd runs the mods). Everything a mod can
## do to the game goes through here, checked: ids, field names, value ranges.
##
##   import uad
##   uad.weapon("mistral", base="igla", name={"ru": "ПЗРК Mistral", "en": "Mistral"}, range=6500)
##   uad.enemy("lancet", base="shahed", speed=80, hp=20)
##   uad.raid("lancet", night=3, weight=0.5)
##
##   @uad.on("kill")
##   def bonus(e):
##       if e["type"] == "lancet":
##           uad.give_money(500)
##
## Definitions (weapon, enemy, change_*, raid, clear_raid) belong to the mod's top level, which runs
## when the world opens; the game actions (give_money, launch, message…) work from event handlers.

const VM = preload("res://scripts/mods/py_vm.gd")
const BuildInfo = preload("res://scripts/build_info.gd")

## Events a handler can be put on, with what its dict argument holds.
const EVENTS := {
	"start": "the world opened: {day, night}",
	"day": "a new day began: {day}",
	"night": "the night (the raid) began: {day}",
	"morning": "the night is over: {day, kills, impacts, homes, earned, …}",
	"kill": "a target went down: {type, weapon, reward, x, y, z}",
	"impact": "a target got through: {type, x, z, base}",
	"launch": "the enemy launched: {type, count, at_base}",
	"buy": "a system was bought: {weapon}",
	"tick": "once a second of game time: {t, night}",
}

## Values a weapon / threat field may take; fields not listed take any number from 0 up.
const LIMITS := {
	"range": [50.0, 600000.0], "range_bm": [50.0, 600000.0], "ceil": [20.0, 120000.0], "rate": [0.02, 120.0],
	"damage": [0.1, 20000.0], "spread": [0.0, 0.2], "speed": [0.0, 8000.0], "turn": [0.05, 30.0], "eye": [0.5, 30.0],
	"unlock": [0, 10000000], "missile_price": [0, 2000000], "start_ammo": [0, 5000], "hp": [0.5, 100000.0],
	"alt_min": [0.0, 60000.0], "alt_max": [0.0, 60000.0], "reward": [0, 1000000], "hit_damage": [0.0, 100.0],
	"hit_cost": [0, 10000000], "debris": [0, 40], "debris_penalty": [0, 1000000], "radius": [0.5, 60.0],
	"swarm": [0.1, 8.0], "crush": [0.0, 5.0], "scale": [0.2, 6.0], "launch_dist": [1000.0, 2000000.0],
	"link": [100.0, 200000.0], "battery": [5.0, 7200.0],
}
const WEAPON_CHOICES := {"kind": ["gun", "missile", "drone"], "class": ["gun", "short", "medium", "long"],
	"group": ["manual", "auto", "missile", "patriot"]}
const ENEMY_KINDS := ["scout", "shahed", "cruise", "ballistic"]
## The fields that are names people read: a str, or {"ru": …, "uk": …, "en": …}.
const TEXT_FIELDS := ["name", "short", "desc", "plural", "abbr"]
## Fields every mod may add to a weapon or a threat besides the game's own ones.
const EXTRA_FIELDS := ["model", "tint", "scale", "base"]

## The mods host (scripts/mods/mods.gd) — a class, all static.
static var host


## The module for one mod's interpreter.
static func make(vm, mod: Dictionary) -> VM.PyModule:
	var m := VM.PyModule.new()
	m.name = "uad"
	m.frozen = true
	var names := ["weapon", "change_weapon", "enemy", "change_enemy", "raid", "clear_raid", "weapons", "enemies",
		"weapon_info", "enemy_info", "on", "day", "is_night", "money", "give_money", "city", "city_health",
		"base_health", "heal_city", "stat", "stats", "has_weapon", "give_weapon", "give_ammo", "message", "alert",
		"launch", "targets", "shader_param", "difficulty", "language", "text"]
	for nm in names:
		var b := VM.PyBuiltin.new()
		b.name = "uad." + nm
		b.fn = _call.bind(vm, mod, nm)
		m.attrs[nm] = b
	m.attrs["data"] = host.data_of(String(mod.id))
	m.attrs["events"] = EVENTS.keys()
	m.attrs["game_version"] = BuildInfo.label()
	return m


static func _call(args: Array, kw: Dictionary, vm, mod: Dictionary, nm: String):
	match nm:
		"weapon", "change_weapon":
			return _define(vm, mod, args, kw, true, nm == "weapon")
		"enemy", "change_enemy":
			return _define(vm, mod, args, kw, false, nm == "enemy")
		"raid":
			return _raid(vm, args, kw)
		"clear_raid":
			return _clear_raid(vm, args, kw)
		"weapons":
			return GS.WEAPON_ORDER.duplicate()
		"enemies":
			return GS.ENEMIES.keys()
		"weapon_info", "enemy_info":
			var table: Dictionary = GS.WEAPONS if nm == "weapon_info" else GS.ENEMIES
			var id := _arg(args, kw, 0, "id", "")
			if not table.has(id):
				return vm.throw("KeyError", "no %s called '%s'" % ["weapon" if nm == "weapon_info" else "enemy", id])
			return _to_py(table[id])
		"on":
			var ev := _arg(args, kw, 0, "event", "")
			if not EVENTS.has(ev):
				return vm.throw("ValueError", "unknown event '%s' — the events are: %s" % [ev, ", ".join(PackedStringArray(EVENTS.keys()))])
			var reg := VM.PyBuiltin.new()
			reg.name = "uad.on(%s)" % ev
			reg.fn = func(a: Array, _k: Dictionary):
				if a.is_empty():
					return vm.throw("TypeError", "uad.on(...) is put on a function")
				host.add_handler(vm, mod, ev, a[0])
				return a[0]
			return reg
		"difficulty":
			return GS.difficulty
		"language":
			return String(GS.settings.get("lang", "en"))
		"city":
			return GS.city_id
		"text":
			return _text(vm, args[0] if not args.is_empty() else kw.get("text", ""))
	# --- the game itself: only while it runs ------------------------------------------------
	var game = host.game
	if game == null or not is_instance_valid(game):
		return vm.throw("RuntimeError", "uad.%s() works while the game runs — call it from an event handler (@uad.on)" % nm)
	match nm:
		"day":
			return GS.day
		"is_night":
			return game.director != null and game.director.is_night()
		"money":
			return GS.money
		"give_money":
			var n := int(_num(args, kw, 0, "amount", 0))
			if n > 0:
				GS.add_money(n)
			elif n < 0:
				GS.money = maxi(GS.money + n, 0)
				GS.money_changed.emit(GS.money)
			return GS.money
		"city_health":
			return GS.city
		"base_health":
			return GS.base_hp
		"heal_city":
			GS.city = clampf(GS.city + float(_num(args, kw, 0, "amount", 0)), 0.0, 100.0)
			GS.state_changed.emit()
			return GS.city
		"stat":
			return GS.stats.get(_arg(args, kw, 0, "name", ""), 0)
		"stats":
			return GS.stats.duplicate()
		"has_weapon":
			return GS.unlocked.has(_arg(args, kw, 0, "id", ""))
		"give_weapon":
			var id := _arg(args, kw, 0, "id", "")
			if not GS.WEAPONS.has(id):
				return vm.throw("KeyError", "no weapon called '%s'" % id)
			if GS.unlocked.has(id):
				return false
			GS.unlocked[id] = true
			if GS.WEAPONS[id].has("start_ammo"):
				GS.ammo[id] = int(GS.ammo.get(id, 0)) + int(GS.WEAPONS[id].start_ammo)
			game.add_weapon(id)
			GS.state_changed.emit()
			return true
		"give_ammo":
			var id := _arg(args, kw, 0, "id", "")
			if not GS.AMMO_ORDER.has(id):
				return vm.throw("KeyError", "'%s' takes no ammunition" % id)
			GS.ammo[id] = maxi(int(GS.ammo.get(id, 0)) + int(_num(args, kw, 1, "count", 1)), 0)
			GS.state_changed.emit()
			return GS.ammo[id]
		"message", "alert":
			var text: String = vm._str(args[0]) if not args.is_empty() else String(kw.get("text", ""))
			host.say(text.left(240), _color(kw.get("color", args[1] if args.size() > 1 else null), Color(1.0, 0.85, 0.35)), nm == "alert")
			return null
		"launch":
			var id := _arg(args, kw, 0, "enemy", "")
			if not GS.ENEMIES.has(id):
				return vm.throw("KeyError", "no enemy called '%s'" % id)
			var count := clampi(int(_num(args, kw, 1, "count", 1)), 1, 40)
			if game.enemies.size() + count > 400:
				return vm.throw("RuntimeError", "too many targets in the air")
			host.quiet(func() -> void: game.launch(id, count, bool(kw.get("at_base", false))))
			return count
		"targets":
			var out := []
			for e in game.enemies:
				if is_instance_valid(e) and not e.is_queued_for_deletion():
					out.append({"type": String(e.variant), "x": snappedf(e.position.x, 0.1), "y": snappedf(e.position.y, 0.1),
						"z": snappedf(e.position.z, 0.1), "hp": snappedf(float(e.hp), 0.1)})
			return out
		"shader_param":
			host.shader_param(_arg(args, kw, 0, "name", ""), args[1] if args.size() > 1 else kw.get("value", 0.0))
			return null
	return vm.throw("AttributeError", "module 'uad' has no attribute '%s'" % nm)


static func _arg(args: Array, kw: Dictionary, i: int, key: String, dflt: String) -> String:
	if args.size() > i:
		return String(args[i]) if args[i] is String else str(args[i])
	return String(kw.get(key, dflt))


static func _num(args: Array, kw: Dictionary, i: int, key: String, dflt):
	var v = args[i] if args.size() > i else kw.get(key, dflt)
	return v if (v is int or v is float) else dflt


# --- definitions ------------------------------------------------------------------------------
static var _id_re := RegEx.create_from_string("^[a-z][a-z0-9_]{0,23}$")


## uad.weapon / change_weapon / enemy / change_enemy. Returns the id.
static func _define(vm, mod: Dictionary, args: Array, kw: Dictionary, weapon: bool, new: bool):
	if host.game != null:
		return vm.throw("RuntimeError", "weapons and enemies are defined at the top of the mod, not during the game")
	var what := "weapon" if weapon else "enemy"
	var table: Dictionary = GS.WEAPONS if weapon else GS.ENEMIES
	var base_table: Dictionary = GS.BASE_WEAPONS if weapon else GS.BASE_ENEMIES
	if args.is_empty() or not (args[0] is String):
		return vm.throw("TypeError", "uad.%s() needs an id first, like uad.%s(\"my_%s\", ...)" % [what, what, what])
	var id := String(args[0])
	if args.size() > 1:
		return vm.throw("TypeError", "uad.%s(): give the fields by name, like range=5000" % what)
	var entry: Dictionary
	if new:
		if _id_re.search(id) == null:
			return vm.throw("ValueError", "the id '%s' must be latin small letters, digits and _ (up to 24), starting with a letter" % id)
		if table.has(id):
			return vm.throw("ValueError", "there is already a %s called '%s' — use uad.change_%s() to change it" % [what, id, what])
		var base := String(kw.get("base", "igla" if weapon else "shahed"))
		if not table.has(base):
			return vm.throw("KeyError", "no %s called '%s' to start from" % [what, base])
		entry = (table[base] as Dictionary).duplicate(true)
		if not entry.has("model"):
			entry["model"] = base if base_table.has(base) else String(table[base].get("model", base))
		if not weapon and not entry.has("kind"):
			entry["kind"] = GS.kind_of(base)
	else:
		if not table.has(id):
			return vm.throw("KeyError", "no %s called '%s' to change" % [what, id])
		entry = (table[id] as Dictionary).duplicate(true)
	var known := _known_fields(base_table)
	for k in kw:
		var key := String(k)
		if key == "base":
			continue
		if not known.has(key) and not EXTRA_FIELDS.has(key):
			var hint := _closest(key, known.keys() + EXTRA_FIELDS)
			return vm.throw("ValueError", "a %s has no field '%s'%s" % [what, key, " — did you mean '%s'?" % hint if hint != "" else ""])
		var v = _field(vm, key, kw[k], known.get(key), weapon)
		if vm.failed():
			return null
		entry[key] = v
	if new and kw.has("name"):
		# the short labels of the base would name the wrong thing: made from the new name instead
		for f in (["short"] if weapon else ["plural", "abbr"]):
			if not kw.has(f):
				entry[f] = _short_of(kw.name, 2 if f == "abbr" else 14)
	if weapon:
		for ck in WEAPON_CHOICES:
			if entry.has(ck) and not WEAPON_CHOICES[ck].has(String(entry[ck])):
				return vm.throw("ValueError", "%s must be one of %s" % [ck, WEAPON_CHOICES[ck]])
	elif not ENEMY_KINDS.has(String(entry.get("kind", "shahed"))):
		return vm.throw("ValueError", "kind must be one of %s" % [ENEMY_KINDS])
	if entry.has("alt_min") and entry.has("alt_max") and float(entry.alt_min) > float(entry.alt_max):
		return vm.throw("ValueError", "alt_min is above alt_max")
	var model := String(entry.get("model", id))
	var models: Dictionary = GS.BASE_WEAPONS if weapon else GS.BASE_ENEMIES
	if entry.has("model") and not models.has(model):
		return vm.throw("ValueError", "no built-in model '%s' — the models are the game's own %ss: %s" % [model, what, ", ".join(PackedStringArray(models.keys()))])
	host.put(weapon, id, entry, new)
	return id


## The fields the game's own entries have, with a sample value of each (its type).
static func _known_fields(base_table: Dictionary) -> Dictionary:
	var out := {}
	for id in base_table:
		for k in base_table[id]:
			if not out.has(k):
				out[k] = base_table[id][k]
	return out


static func _field(vm, key: String, v, sample, weapon: bool):
	if TEXT_FIELDS.has(key):
		return _text(vm, v)
	if key == "model":
		if not (v is String):
			return vm.throw("TypeError", "model must be the id of a built-in model, like \"s300\"")
		return v
	if key == "tint" or key == "color" or sample is Color:
		var c := _color(v, Color(-1, 0, 0))
		if c.r < 0.0:
			return vm.throw("ValueError", "%s must be a colour: \"#ff8800\" or [r, g, b] from 0 to 1" % key)
		return c
	if key == "eff" or key == "eff_mult":
		if not (v is Dictionary):
			return vm.throw("TypeError", "%s must be a dict, like {\"shahed\": 1.0, \"cruise\": 0.5}" % key)
		var out := {}
		for k in v:
			if key == "eff" and not ENEMY_KINDS.has(String(k)):
				return vm.throw("ValueError", "eff is by flight model: %s" % [ENEMY_KINDS])
			if key == "eff_mult" and String(k) != "*" and not GS.WEAPONS.has(String(k)):
				return vm.throw("ValueError", "eff_mult keys are weapon ids (or \"*\"), not '%s'" % k)
			if not (v[k] is int or v[k] is float):
				return vm.throw("TypeError", "%s values are numbers" % key)
			out[String(k)] = clampf(float(v[k]), 0.0, 5.0)
		return out
	if sample is bool or key in ["fcs", "decoy", "glide", "own_alt", "mirv"]:
		return vm.truthy(v)
	if sample is Array:
		if not (v is Array) or v.size() != (sample as Array).size():
			return vm.throw("TypeError", "%s must be a list of %d numbers" % [key, (sample as Array).size()])
		var out := []
		for x in v:
			if not (x is int or x is float):
				return vm.throw("TypeError", "%s must be a list of numbers" % key)
			out.append(clampf(float(x), 0.0, 2000000.0))
		return out
	if sample is String:
		return vm._str(v).left(40)
	if not (v is int or v is float) or v is bool:
		return vm.throw("TypeError", "%s must be a number, not %s" % [key, vm._type_name(v)])
	var lim: Array = LIMITS.get(key, [0.0, 10000000.0])
	if sample is int or (lim[0] is int and v is int):
		return clampi(int(v), int(lim[0]), int(lim[1]))
	return clampf(float(v), float(lim[0]), float(lim[1]))


## A text field: the Russian form is what the game keeps (its source language); the other forms
## go into the translation tables.
static func _text(vm, v) -> String:
	if v is String:
		return v.left(400)
	if v is Dictionary:
		var ru := String(v.get("ru", v.get("en", v.get("uk", "")))).left(400)
		host.translate(ru, String(v.get("en", ru)).left(400), String(v.get("uk", v.get("ru", ru))).left(400))
		return ru
	vm.throw("TypeError", "a name is a str or a dict {\"ru\": …, \"uk\": …, \"en\": …}")
	return ""


## The upper-case start of a name (str or {"ru", "uk", "en"}), in every language it is given in.
static func _short_of(v, n: int) -> String:
	if v is Dictionary:
		var forms := {}
		for k in ["ru", "uk", "en"]:
			if v.has(k):
				forms[k] = String(v[k]).to_upper().left(n).strip_edges()
		var ru := String(forms.get("ru", forms.get("en", forms.get("uk", ""))))
		host.translate(ru, String(forms.get("en", ru)), String(forms.get("uk", ru)))
		return ru
	return String(v).to_upper().left(n).strip_edges()


static func _color(v, dflt: Color) -> Color:
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	if v is Array and (v.size() == 3 or v.size() == 4):
		for x in v:
			if not (x is int or x is float):
				return dflt
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() == 4 else 1.0)
	if v is Color:
		return v
	return dflt


static func _closest(word: String, options: Array) -> String:
	var best := ""
	var best_d := 3
	for o in options:
		var d := _distance(word, String(o))
		if d < best_d:
			best_d = d
			best = String(o)
	return best


## Edit distance with swapped neighbours counted as one edit ("rnage" is one step from "range").
static func _distance(a: String, b: String) -> int:
	var d := []
	for i in a.length() + 1:
		var row := []
		row.resize(b.length() + 1)
		row[0] = i
		d.append(row)
	for j in b.length() + 1:
		d[0][j] = j
	for i in range(1, a.length() + 1):
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			d[i][j] = mini(mini(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				d[i][j] = mini(d[i][j], d[i - 2][j - 2] + 1)
	return d[a.length()][b.length()]


# --- raids ------------------------------------------------------------------------------------
const SLOT_OF := {"scout": "drone", "shahed": "drone", "cruise": "cruise", "ballistic": "ballistic"}


## uad.raid(enemy, night=1, weight=1.0, slot=None, cities=None): the threat joins the nightly raid.
static func _raid(vm, args: Array, kw: Dictionary):
	if host.game != null:
		return vm.throw("RuntimeError", "uad.raid() belongs to the top of the mod; during the game use uad.launch()")
	var id := _arg(args, kw, 0, "enemy", "")
	if not GS.ENEMIES.has(id):
		return vm.throw("KeyError", "no enemy called '%s'" % id)
	var slot := String(kw.get("slot", SLOT_OF.get(GS.kind_of(id), "drone")))
	if not ["drone", "cruise", "ballistic"].has(slot):
		return vm.throw("ValueError", "slot is \"drone\", \"cruise\" or \"ballistic\"")
	var cities = kw.get("cities", null)
	if cities is String:
		cities = [cities]
	if cities is Array and not cities.has(GS.city_id):
		return false
	var night := clampi(int(_num(args, kw, 1, "night", 1)), 1, 999)
	var weight := clampf(float(_num(args, kw, 2, "weight", 1.0)), 0.0, 100.0)
	host.add_raid(slot, id, weight, night)
	return true


## uad.clear_raid(slot=None): empties a raid slot (or all three) of the city, for a raid of the mod's own.
static func _clear_raid(vm, args: Array, kw: Dictionary):
	if host.game != null:
		return vm.throw("RuntimeError", "uad.clear_raid() belongs to the top of the mod")
	var slot = args[0] if not args.is_empty() else kw.get("slot", null)
	if slot != null and not ["drone", "cruise", "ballistic"].has(String(slot)):
		return vm.throw("ValueError", "slot is \"drone\", \"cruise\" or \"ballistic\"")
	host.clear_raid("" if slot == null else String(slot))
	return null


## A game value as the mod sees it: colours as "#rrggbb", vectors as lists.
static func _to_py(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[String(k)] = _to_py(v[k])
		return out
	if v is Array:
		var out := []
		for x in v:
			out.append(_to_py(x))
		return out
	if v is Color:
		return "#" + (v as Color).to_html(false)
	if v is Vector3:
		return [v.x, v.y, v.z]
	return v
