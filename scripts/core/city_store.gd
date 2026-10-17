extends RefCounted
## The cities a player has drawn for themselves in the map editor (scripts/ui/cities_menu.gd,
## scripts/ui/city_editor.gd): each is a file on this device, user://cities/<id>.json —
##   {"id": "K7MQ4XRT", "edited": unix, "city": CustomCity data}.
## A world can be created in one of them (the "create world" screen) and a server can take one
## as one of its two cities. In the game such a city goes by the id "my_<id>" (Cities.register).

const Cities = preload("res://scripts/world/cities.gd")
const CustomCity = preload("res://scripts/world/custom_city.gd")
const ServerDef = preload("res://scripts/core/server_def.gd")

const DIR := "user://cities/"
const PREFIX := "my_"
## The most cities kept on a device (the list is read whole whenever it is shown).
const LIMIT := 60

## Self-test and picture runs: the cities live in memory, nothing is written to the player's disk.
static var dry := false
static var _mem := {}


static func new_id() -> String:
	return ServerDef.new_id()


## The id a drawn city goes by in the game (GS.city_id, the saves).
static func city_id(id: String) -> String:
	return PREFIX + id


## The id is that of one of the player's own cities.
static func is_mine(cid: String) -> bool:
	return cid.begins_with(PREFIX)


static func _path(id: String) -> String:
	return DIR + id + ".json"


static func _entry(d) -> Dictionary:
	if not (d is Dictionary) or not (d.get("id") is String) or not ServerDef.valid_id(String(d.id)):
		return {}
	var edited = d.get("edited", 0)
	return {"id": String(d.id), "edited": int(edited) if (edited is float or edited is int) else 0, "city": CustomCity.clean(d.get("city"))}


static func read(id: String) -> Dictionary:
	if not ServerDef.valid_id(id):
		return {}
	if dry:
		return _entry(_mem.get(id))
	var f := FileAccess.open(_path(id), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return _entry(parsed)


## The player's cities, the one edited last first.
static func list() -> Array:
	var out := []
	if dry:
		for id in _mem:
			out.append(_entry(_mem[id]))
	else:
		var dir := DirAccess.open(DIR)
		if dir != null:
			for fname in dir.get_files():
				if fname.ends_with(".json"):
					var e := read(fname.trim_suffix(".json"))
					if not e.is_empty():
						out.append(e)
	out.sort_custom(func(a, b) -> bool: return int(a.edited) > int(b.edited) if int(a.edited) != int(b.edited) else String(a.id) < String(b.id))
	return out


## Writes a city and makes the game know it as it is now (a map of it is rebuilt when next shown).
static func save(id: String, city: Dictionary) -> void:
	if not ServerDef.valid_id(id):
		return
	var e := {"id": id, "edited": int(Time.get_unix_time_from_system()), "city": CustomCity.clean(city)}
	Cities.register(city_id(id), e.city)
	if dry:
		_mem[id] = e
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e))
		f.close()


## A new city: its id.
static func create(city: Dictionary) -> String:
	var id := new_id()
	save(id, city)
	return id


## Deletes the file. Worlds created in the city keep playing: each save carries its own copy.
static func remove(id: String) -> void:
	if not ServerDef.valid_id(id):
		return
	if dry:
		_mem.erase(id)
	else:
		DirAccess.remove_absolute(_path(id))


## At the start of the game: every city of the player is known by its id.
static func register_all() -> void:
	for e in list():
		Cities.register(city_id(String(e.id)), e.city)


## One line about a city for the lists: its size and what is drawn in it.
static func summary(city: Dictionary) -> String:
	var km := int(float(city.size) / 500.0)
	return GS.t("%d × %d км · районов %d · объектов %d") % [km, km, (city.districts as Array).size(), (city.objects as Array).size()]
