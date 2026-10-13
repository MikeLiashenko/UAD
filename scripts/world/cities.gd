extends RefCounted
## Registry of the playable cities, in the order the "create world" screen shows them, and of the
## cities players drew for their servers (CustomCity), registered while such a server is played.

const CustomCity = preload("res://scripts/world/custom_city.gd")

const IDS := ["kyiv", "kharkiv", "dnipro", "odesa"]
const DEFAULT := "kyiv"

const SCRIPTS := {
	"kyiv": preload("res://scripts/world/cities/kyiv.gd"),
	"kharkiv": preload("res://scripts/world/cities/kharkiv.gd"),
	"dnipro": preload("res://scripts/world/cities/dnipro.gd"),
	"odesa": preload("res://scripts/world/cities/odesa.gd"),
}

static var _cache := {}
## Drawn cities by id ("srv_<server>_<side>"); a new drawing under the same id replaces the old.
static var _custom := {}


static func has(id: String) -> bool:
	return SCRIPTS.has(id) or _custom.has(id)


## The description of a city (built once and shared). Unknown ids fall back to Kyiv.
static func get_def(id: String):
	if _custom.has(id):
		return _custom[id]
	if not SCRIPTS.has(id):
		id = DEFAULT
	if not _cache.has(id):
		_cache[id] = SCRIPTS[id].new()
	return _cache[id]


## Registers a drawn city under `id` and returns its description. A drawing registered before
## under the same id is replaced, not freed: a map built from it may still be on screen (cities
## are plain Objects that live as long as the game, see CityDef).
static func register(id: String, data: Dictionary):
	var def := CustomCity.new(data, id)
	_custom[id] = def
	return def


static func is_custom(id: String) -> bool:
	return _custom.has(id)
