extends RefCounted
## A server: two cities drawn by its creator (CustomCity) that fire at each other, and the rules
## of the match (scripts/game/pvp.gd). A server starts as a draft on its creator's device
## (user://servers/<id>.json), is tried there against the machine, and is then published to the
## database for everybody (Net: servers/…).
##
##   {"v": 1, "id": "K7MQ4XRT", "name": "Северск — Южный", "owner": friend code, "nick": owner's nick,
##    "created": unix, "edited": unix,
##    "rules": {"money", "income", "armor", "dist", "team", "arsenal": [weapon, …]},
##    "cities": [city, city]}        (the drafts on disk also keep "published" and "dirty": changed
##                                    since it was last sent to the database)
##
## A published server comes from another player: clean() trusts nothing in it.

const CustomCity = preload("res://scripts/world/custom_city.gd")

const DIR := "user://servers/"
const VERSION := 1
const NAME_MAX := 32
## The most players on one side.
const TEAM_MAX := 8
const ID_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ID_LEN := 8

## What the cities fire at each other: weapon (a key of GS.ENEMIES), price of one, the most in
## one salvo, the short name for a button. Shooting one down pays the defender about what it cost
## the attacker.
const ARSENAL := [
	["shahed", 1500, 8, "Шахед"],
	["gerbera", 500, 8, "Гербера"],
	["geran3", 3500, 4, "Герань-3"],
	["cruise", 7000, 4, "Х-101"],
	["kalibr", 7500, 4, "Калибр"],
	["ballistic", 16000, 2, "Искандер-М"],
	["kinzhal", 26000, 2, "Кинжал"],
	["zircon", 30000, 1, "Циркон"],
]
## Choices of the server screen: [value, label].
const MONEY := [[30000, "$30 000"], [60000, "$60 000"], [100000, "$100 000"], [200000, "$200 000"]]
const INCOME := [[4000, "$4 000"], [8000, "$8 000"], [15000, "$15 000"], [30000, "$30 000"]]
const ARMOR := [[0.5, "Хрупкий"], [1.0, "Обычный"], [2.0, "Крепкий"], [4.0, "Крепость"]]
const DIST := [[100, "100 км"], [300, "300 км"], [600, "600 км"], [1200, "1200 км"]]
const TEAM := [[1, "1 × 1"], [2, "2 × 2"], [4, "4 × 4"], [8, "8 × 8"]]
## An hour of flight between the cities passes in a minute; the final leg over the target city
## is flown in full, like any raid.
const TRANSIT_MIN := 6.0
const TRANSIT_MAX := 180.0
## Part of a weapon's price its owner gets back for every one that reaches the enemy city.
const HIT_BONUS := 0.5
## Self-test and picture runs: drafts are never written to the player's disk.
static var dry := false


static func new_id() -> String:
	var c := ""
	for i in ID_LEN:
		c += ID_CHARS[randi() % ID_CHARS.length()]
	return c


static func valid_id(id: String) -> bool:
	if id.length() != ID_LEN:
		return false
	for ch in id:
		if not ID_CHARS.contains(ch):
			return false
	return true


static func default_rules() -> Dictionary:
	return {"money": 60000, "income": 8000, "armor": 1.0, "dist": 300, "team": TEAM_MAX, "arsenal": ARSENAL.map(func(a) -> String: return String(a[0]))}


## A new draft with two ready-made cities to start from.
static func blank(owner: String, nick: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {"v": VERSION, "id": new_id(), "name": GS.t("Новый сервер"), "owner": owner, "nick": nick, "created": now, "edited": now,
		"rules": default_rules(), "cities": [CustomCity.sample(GS.t("Город А"), false), CustomCity.sample(GS.t("Город Б"), true)], "published": false}


static func _num(v, lo: float, hi: float, fallback: float) -> float:
	if not (v is float or v is int) or not is_finite(float(v)):
		return fallback
	return clampf(float(v), lo, hi)


## The server as the game may take it, whatever came in ({} when it is no server at all).
static func clean(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var id := String(d.get("id", "")) if d.get("id") is String else ""
	var cs = d.get("cities")
	if not valid_id(id) or not (cs is Array) or (cs as Array).size() != 2:
		return {}
	var r: Dictionary = d.get("rules") if d.get("rules") is Dictionary else {}
	var arsenal := []
	var asked = r.get("arsenal")
	for a in ARSENAL:
		if not (asked is Array) or (asked as Array).has(String(a[0])):
			arsenal.append(String(a[0]))
	if arsenal.is_empty():
		arsenal = ["shahed"]
	var sname := CustomCity.clean_name(d.get("name", ""), NAME_MAX)
	var owner := String(d.get("owner", "")) if d.get("owner") is String else ""
	return {"v": VERSION, "id": id, "name": sname if sname != "" else "Сервер", "owner": owner if valid_id(owner) else "",
		"nick": CustomCity.clean_name(d.get("nick", ""), 16),
		"created": int(_num(d.get("created"), 0.0, 9.0e12, 0.0)), "edited": int(_num(d.get("edited"), 0.0, 9.0e12, 0.0)),
		"rules": {"money": int(_num(r.get("money"), 5000.0, 500000.0, 60000.0)), "income": int(_num(r.get("income"), 0.0, 60000.0, 8000.0)),
			"armor": _num(r.get("armor"), 0.25, 8.0, 1.0), "dist": int(_num(r.get("dist"), 50.0, 2000.0, 300.0)),
			"team": int(_num(r.get("team"), 1.0, float(TEAM_MAX), float(TEAM_MAX))), "arsenal": arsenal},
		"cities": [CustomCity.clean(cs[0]), CustomCity.clean(cs[1])], "published": bool(d.get("published", false)), "dirty": bool(d.get("dirty", false))}


## The id the city of one side is registered under (Cities.register) and goes by in the game.
static func city_id(def: Dictionary, side: int) -> String:
	return "srv_%s_%d" % [String(def.id), side]


static func city_name(def: Dictionary, side: int) -> String:
	return String(def.cities[clampi(side, 0, 1)].name)


## Side 0 lies to the west of side 1: the bearing (degrees) its raids arrive from.
static func bearing_from_enemy(side: int) -> float:
	return 90.0 if side == 0 else 270.0


static func price(weapon: String) -> int:
	for a in ARSENAL:
		if String(a[0]) == weapon:
			return int(a[1])
	return 0


## The weapon's short name for a button (a translation key).
static func short_name(weapon: String) -> String:
	for a in ARSENAL:
		if String(a[0]) == weapon:
			return String(a[3])
	return weapon


static func salvo_max(weapon: String) -> int:
	for a in ARSENAL:
		if String(a[0]) == weapon:
			return int(a[2])
	return 1


## Seconds a weapon spends between the two cities before the defenders' radars pick it up.
static func transit(weapon: String, dist_km: float) -> float:
	var wd: Dictionary = GS.ENEMIES.get(weapon, GS.ENEMIES.shahed)
	var kmh := float(wd.speed) * 3.6 if float(wd.speed) > 0.0 else 6000.0
	return clampf(dist_km / kmh * 60.0, TRANSIT_MIN, TRANSIT_MAX)


# --- Drafts on this device -------------------------------------------------------------------------
static func _path(id: String) -> String:
	return DIR + id + ".json"


static func save(def: Dictionary) -> void:
	if not valid_id(String(def.get("id", ""))):
		return
	def["edited"] = int(Time.get_unix_time_from_system())
	if dry:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(String(def.id)), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(def))
		f.close()


static func read(id: String) -> Dictionary:
	if not valid_id(id):
		return {}
	var f := FileAccess.open(_path(id), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return clean(parsed)


## The creator's own servers, the one edited last first.
static func list() -> Array:
	var out := []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			var d := read(fname.trim_suffix(".json"))
			if not d.is_empty():
				out.append(d)
	out.sort_custom(func(a, b) -> bool: return int(a.edited) > int(b.edited))
	return out


static func remove(id: String) -> void:
	if valid_id(id) and not dry:
		DirAccess.remove_absolute(_path(id))
