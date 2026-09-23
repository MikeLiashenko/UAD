extends RefCounted
## Registry of the playable cities, in the order the "create world" screen shows them.

const IDS := ["kyiv", "kharkiv", "dnipro", "odesa"]
const DEFAULT := "kyiv"

const SCRIPTS := {
	"kyiv": preload("res://scripts/world/cities/kyiv.gd"),
	"kharkiv": preload("res://scripts/world/cities/kharkiv.gd"),
	"dnipro": preload("res://scripts/world/cities/dnipro.gd"),
	"odesa": preload("res://scripts/world/cities/odesa.gd"),
}

static var _cache := {}


static func has(id: String) -> bool:
	return SCRIPTS.has(id)


## The description of a city (built once and shared). Unknown ids fall back to Kyiv.
static func get_def(id: String):
	if not SCRIPTS.has(id):
		id = DEFAULT
	if not _cache.has(id):
		_cache[id] = SCRIPTS[id].new()
	return _cache[id]
