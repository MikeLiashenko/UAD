extends RefCounted
## A server: two cities drawn by its creator (CustomCity) that fire at each other, and the rules
## of the match (scripts/game/pvp.gd). A server starts as a draft on its creator's device
## (user://servers/<id>.json), is tried there against the machine, and is then published to the
## database for everybody (Net: servers/…).
##
##   {"v": 1, "id": "K7MQ4XRT", "name": "Северск — Южный", "owner": friend code, "nick": owner's nick,
##    "created": unix, "edited": unix,
##    "rules": {"money", "income", "armor", "dist", "team", "arsenal": [weapon, …], "nights"},
##    "cities": [city, city]}        (the drafts on disk also keep "published" and "dirty": changed
##                                    since it was last sent to the database)
##
## A duel (`"duel": true`) is a server of two friends, one a side, that lasts DUEL_NIGHTS nights
## on a clock both games share (scripts/game/pvp.gd): it is published under its challenger's code,
## kept out of the list of servers, and a city of it may be one of the game's own ({"b": "kharkiv"}).
##
## A published server comes from another player: clean() trusts nothing in it.

const CustomCity = preload("res://scripts/world/custom_city.gd")
const Cities = preload("res://scripts/world/cities.gd")

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

## A duel: how many nights, and the length of its days and nights, seconds. The first day is
## longer — the battery is bought and set up then.
const DUEL_NIGHTS := 3
const DUEL_FIRST_DAY := 150.0
const DUEL_DAY := 100.0
const DUEL_NIGHT := 180.0
## After the last night the strikes still in the air are waited for, at most this long.
const DUEL_TAIL := 120.0
## Integrity closer than this (percent) after the last night is a draw.
const DUEL_DRAW := 1.0
## Test runs: the duel's clock runs this many times faster.
static var duel_speed := 1.0


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


## A duel between two friends: `cities` are [the challenger's, the friend's] — a city of the game
## ({"b": id}) or one the challenger drew. Its id is the challenger's code: a new duel replaces
## the one before it.
static func duel(owner: String, nick: String, cities: Array) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var rules := default_rules()
	rules.team = 1
	rules.nights = DUEL_NIGHTS
	var d := {"v": VERSION, "id": owner, "name": "", "owner": owner, "nick": nick, "created": now, "edited": now,
		"rules": rules, "cities": cities, "duel": true}
	d = clean(d)
	if not d.is_empty():
		d.name = CustomCity.clean_name("%s — %s" % [city_name(d, 0), city_name(d, 1)], NAME_MAX)
	return d


## A city of the game itself as a city of a duel.
static func builtin_city(id: String) -> Dictionary:
	return {"b": id}


## The id of the game's own city a server's city is ("" when it was drawn).
static func builtin(city) -> String:
	if city is Dictionary and city.get("b") is String and Cities.IDS.has(String(city.b)):
		return String(city.b)
	return ""


## The schedule of a duel: [length of a phase, night (1…) or 0 for a day], in order.
static func duel_phases() -> Array:
	var out := []
	for n in DUEL_NIGHTS:
		out.append([(DUEL_FIRST_DAY if n == 0 else DUEL_DAY) / duel_speed, 0])
		out.append([DUEL_NIGHT / duel_speed, n + 1])
	return out


## Where a duel stands `sec` seconds after its start: {"i": index of the phase (-1 before the
## start, the size of the schedule after the last night), "night": 1… or 0, "day": 1…, "left", "len"}.
static func duel_at(sec: float) -> Dictionary:
	var ph := duel_phases()
	if sec < 0.0:
		return {"i": -1, "night": 0, "day": 1, "left": 0.0, "len": 0.0}
	var t := sec
	for i in ph.size():
		var l := float(ph[i][0])
		if t < l:
			return {"i": i, "night": int(ph[i][1]), "day": i / 2 + 1, "left": l - t, "len": l}
		t -= l
	return {"i": ph.size(), "night": 0, "day": DUEL_NIGHTS, "left": 0.0, "len": 0.0, "after": t}


## Seconds from the start of a duel to the dusk of night `n` (1…); past the last night, its dawn.
static func duel_dusk(n: int) -> float:
	var t := 0.0
	var ph := duel_phases()
	for i in ph.size():
		if int(ph[i][1]) == n:
			return t
		t += float(ph[i][0])
	return t


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
	var duel: bool = d.get("duel") == true
	var owner := String(d.get("owner", "")) if d.get("owner") is String else ""
	return {"v": VERSION, "id": id, "name": sname if sname != "" else "Сервер", "owner": owner if valid_id(owner) else "",
		"nick": CustomCity.clean_name(d.get("nick", ""), 16),
		"created": int(_num(d.get("created"), 0.0, 9.0e12, 0.0)), "edited": int(_num(d.get("edited"), 0.0, 9.0e12, 0.0)),
		"rules": {"money": int(_num(r.get("money"), 5000.0, 500000.0, 60000.0)), "income": int(_num(r.get("income"), 0.0, 60000.0, 8000.0)),
			"armor": _num(r.get("armor"), 0.25, 8.0, 1.0), "dist": int(_num(r.get("dist"), 50.0, 2000.0, 300.0)),
			"team": 1 if duel else int(_num(r.get("team"), 1.0, float(TEAM_MAX), float(TEAM_MAX))), "arsenal": arsenal,
			"nights": DUEL_NIGHTS if duel else 0},
		"cities": [_city(cs[0], duel), _city(cs[1], duel)], "published": bool(d.get("published", false)), "dirty": bool(d.get("dirty", false)),
		"duel": duel}


## One of the two cities: a drawn one is cleaned, one of the game's own (a duel's) is kept by its id.
static func _city(c, duel: bool) -> Dictionary:
	var b := builtin(c) if duel else ""
	if b != "":
		var cd = Cities.get_def(b)
		return {"b": b, "name": String(cd.name), "size": float(cd.half)}
	return CustomCity.clean(c)


## The id the city of one side is registered under (Cities.register) and goes by in the game.
static func city_id(def: Dictionary, side: int) -> String:
	var b := builtin(def.cities[clampi(side, 0, 1)])
	return b if b != "" else "srv_%s_%d" % [String(def.id), side]


static func city_name(def: Dictionary, side: int) -> String:
	var c: Dictionary = def.cities[clampi(side, 0, 1)]
	return GS.t(String(c.name)) if builtin(c) != "" else String(c.name)


static var _plans := {}


## The city as the flat plan draws it (scripts/ui/city_plan.gd): a drawn city is that already; one
## of the game's own is turned into the same kind of data — its water, woods, districts and roads.
static func plan(city: Dictionary) -> Dictionary:
	var b := builtin(city)
	if b == "":
		return city
	if _plans.has(b):
		return _plans[b]
	var cd = Cities.get_def(b)
	var h := float(cd.half)
	var out := {"name": GS.t(String(cd.name)), "size": h, "rivers": [], "lakes": [], "forests": [], "districts": [], "roads": [], "rails": [], "objects": []}
	for r in cd.rivers:
		out.rivers.append({"n": GS.t(String(r.get("name", ""))), "p": _thin(r.pts, r.get("w", PackedFloat32Array()), 40)})
	for l in cd.lakes:
		out.lakes.append([l[0], l[1], l[2], l[3], l[4]])
	for f in cd.forests:
		out.forests.append([f[0], f[1], f[2], f[3], f[4]])
	for d in cd.districts:
		out.districts.append([GS.t(String(d[0])), d[1], d[2], d[3], String(d[5]), d[6]])
	for r in cd.roads:
		out.roads.append({"n": GS.t(String(r.get("name", ""))), "p": _thin(r.pts, null, 30)})
	for r in cd.rails:
		out.rails.append({"n": GS.t(String(r.get("name", ""))), "p": _thin(r.pts, null, 30)})
	if cd.has_sea:
		# the open sea east of the shore, as one shape
		var sea := []
		var n := 60
		for i in n + 1:
			var z := -h + 2.0 * h * i / n
			sea.append([minf(cd.coast_x(z), h), z])
		sea.append([h, h])
		sea.append([h, -h])
		out["sea"] = sea
	_plans[b] = out
	return out


## A dense line of the city's own as at most about `most` control points ([x, z(, half width)]).
static func _thin(pts: PackedVector2Array, ws, most: int) -> Array:
	var out := []
	if pts.is_empty():
		return out
	var step := maxi(1, pts.size() / most)
	var idx := range(0, pts.size(), step)
	if idx[idx.size() - 1] != pts.size() - 1:
		idx.append(pts.size() - 1)
	for i in idx:
		if ws is PackedFloat32Array:
			out.append([pts[i].x, pts[i].y, (ws as PackedFloat32Array)[mini(i, ws.size() - 1)] if not ws.is_empty() else 20.0])
		else:
			out.append([pts[i].x, pts[i].y])
	return out


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
