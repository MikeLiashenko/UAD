extends "res://scripts/world/city_def.gd"
## A city drawn by a player in the city editor (scripts/ui/city_editor.gd) for a server: two of
## them fire at each other (scripts/game/pvp.gd). Where Kyiv or Odesa are written out in code,
## this one is built from plain data that fits in a JSON file and in the database:
##
##   {"name": "Северск", "size": 8000 (half of the square, metres), "seed": 4711,
##    "rivers":    [{"n": name, "p": [[x, z, half width], …]}],
##    "lakes":     [[x, z, rx, rz, rot]],
##    "forests":   [[x, z, rx, rz, rot]],
##    "districts": [[name, x, z, grid angle, kind, radius]],
##    "roads":     [{"n": name, "p": [[x, z], …]}],
##    "rails":     [{"n": name, "p": [[x, z], …]}],
##    "objects":   [{"k": kind, "x": x, "z": z, "r": rot, "n": name}]}
##
## The data may come from another player (a published server), so clean() trusts nothing in it:
## every number is clamped, every list cut to its limit and every name to plain short text.

const L = preload("res://scripts/world/landmarks.gd")

const SIZE_MIN := 3000.0
const SIZE_MAX := 12000.0
const SIZES := [[4000.0, "8 × 8 км"], [7000.0, "14 × 14 км"], [10000.0, "20 × 20 км"]]
const NAME_MAX := 28
const MAX_RIVERS := 6
const MAX_LAKES := 16
const MAX_FORESTS := 24
const MAX_DISTRICTS := 40
const MAX_ROADS := 16
const MAX_RAILS := 4
const MAX_OBJECTS := 40
const MAX_POINTS := 24

## District characters offered by the editor: kind (CityGen.PROFILES), name, block size, colour on the plan.
const DISTRICT_KINDS := [
	["stalin", "Центр", 150.0, Color(0.95, 0.8, 0.5)],
	["historic", "Старый город", 140.0, Color(0.9, 0.6, 0.45)],
	["panel", "Панельные кварталы", 210.0, Color(0.7, 0.75, 0.85)],
	["khrush", "Хрущёвки", 170.0, Color(0.75, 0.7, 0.6)],
	["new", "Новостройки", 220.0, Color(0.55, 0.85, 0.95)],
	["mixed", "Смешанная застройка", 180.0, Color(0.8, 0.8, 0.7)],
	["industrial", "Промзона", 230.0, Color(0.6, 0.55, 0.65)],
	["private", "Частный сектор", 140.0, Color(0.6, 0.8, 0.55)],
]

## Objects of the editor's palette: kind, name, the radius kept free around it (metres).
## All of them are strike targets, so the enemy has something to aim at.
const OBJECT_KINDS := [
	["tpp", "Электростанция", 200.0],
	["plant", "Завод", 200.0],
	["oil", "Нефтебаза", 110.0],
	["rail", "Вокзал", 240.0],
	["airport", "Аэропорт", 1300.0],
	["port", "Порт", 60.0],
	["tv", "Телебашня", 80.0],
	["gov", "Администрация", 70.0],
	["stadium", "Стадион", 160.0],
	["tower", "Небоскрёб", 40.0],
]

var data := {}


func _init(d := {}, cid := "custom") -> void:
	data = clean(d)
	id = cid
	name = String(data.name)
	half = float(data.size)
	seed = int(data.seed)
	noise_seed = seed % 97 + 3
	noise2_seed = seed % 89 + 5
	# a redrawn city is another layout: what a save remembers of its buildings is dropped (GS.load_world)
	version = 1000 + (JSON.stringify(data).hash() & 0x3FFFFFFF)
	accent = Color(0.4, 0.95, 0.8)
	lat0 = 49.0
	lon0 = 32.0
	video_channel = "@city_cuts"
	video_authors = ["@balcony_cam", "@night_roof", "@taxi_2am", "@nightwatch", "@rooftop_live", "@yard_view"]
	# a world in a drawn city is raided like a city in the middle of the country (a server's match
	# brings its own raids, from the other city)
	threat_sectors = [0.0, 30.0, 60.0, 90.0, 110.0, 130.0, 150.0, 180.0]
	raid = {
		"drone": [["shahed", 0.7, 1], ["gerbera", 0.3, 2], ["geran3", 0.12, 8]],
		"cruise": [["cruise", 0.55, 3], ["kalibr", 0.45, 4], ["banderol", 0.25, 6]],
		"ballistic": [["ballistic", 0.7, 5], ["kh22", 0.3, 7]],
	}
	raid_sectors = {"ballistic": [80.0, 100.0, 120.0, 140.0], "kalibr": [150.0, 170.0, 190.0, 210.0], "kh22": [100.0, 130.0, 160.0], "banderol": [60.0, 80.0, 100.0]}
	sites_as = "dnipro"
	for r in data.rivers:
		add_river(String(r.n), r.p)
	for l in data.lakes:
		lakes.append(l)
	for f in data.forests:
		forests.append([f[0], f[1], f[2], f[3], f[4], 0.2])
	var centre := Vector2.ZERO
	var reach := 0.0
	for d2 in data.districts:
		districts.append([String(d2[0]), float(d2[1]), float(d2[2]), float(d2[3]), block_of(String(d2[4])), String(d2[4]), float(d2[5])])
		centre += Vector2(float(d2[1]), float(d2[2]))
	if districts.is_empty():
		# the generator needs a district to start from: an empty field still has a hamlet in the middle
		districts.append([name, 0.0, 0.0, 0.0, block_of("private"), "private", 300.0])
	else:
		centre /= districts.size()
		for d2 in data.districts:
			reach = maxf(reach, Vector2(float(d2[1]), float(d2[2])).distance_to(centre) + float(d2[5]))
	city_center = centre
	city_radii = Vector2.ONE * clampf(reach * 1.15, 1500.0, half * 1.2)
	map_focus = Vector3(centre.x, 0.0, centre.y)
	for r in data.roads:
		add_road(String(r.n), r.p) # a bridge of its own wherever it crosses water
	for r in data.rails:
		add_rail(String(r.n), r.p)
	for r in data.rivers:
		if String(r.n) != "" and (r.p as Array).size() >= 2:
			var mid: Array = r.p[(r.p as Array).size() / 2]
			label(String(r.n), float(mid[0]), float(mid[1]), 56, Color(0.6, 0.85, 1.0, 0.85))


## Phrases of the interface. A drawn city has no declension tables: the wording is general.
func text(key: String) -> String:
	match key:
		"defense":
			return GS.t("Оборона: %s") % name
		"title":
			return name.to_upper()
		"over":
			return "Ночное дежурство над городом"
		"duty":
			return "%s РАДАР АКТИВЕН · ПВО НА ДЕЖУРСТВЕ"
		"raid":
			return "НОЧЬ %d — МАССИРОВАННЫЙ НАЛЁТ!"
		"held":
			return "Город выстоял. %d ночей обороны позади."
		"water_into":
			return "в воду"
		"water_safe":
			return "в воду — без ущерба"
		"water_label":
			return "ВОДА — безопасно"
		"shore":
			return "Берег"
		"shore_desc":
			return "Безопасная зона: обломки, сбитые над водой, падают в воду.\nОткрытый обзор над водой: дальность ствольной ПВО +10%."
		"rec":
			return "REC ● 60 км/ч"
	return key


## The objects of the palette, each a strike target.
func build_landmarks(map) -> void:
	var n := 0
	for o in data.objects:
		var p := Vector3(float(o.x), 0.0, float(o.z))
		var rot := float(o.r)
		var oname := String(o.n)
		if oname == "":
			oname = GS.t(object_name(String(o.k)))
		n += 1
		match String(o.k):
			"tpp":
				L.power_plant(map, p, rot, oname, 1, 2, 160.0)
			"plant":
				L.factory(map, p, rot, oname, 4, 2, true)
			"oil":
				L.tanks(map, p, rot, 4, 16.0, oname, true)
			"rail":
				L.station(map, p, rot, oname)
			"airport":
				L.airport(map, p, rot, oname, 2000.0)
			"port":
				L.port(map, p, rot, oname, 3)
			"tv":
				L.lattice_tower(map, p, oname, 220.0)
			"stadium":
				L.stadium(map, p, rot, oname, 110.0, 90.0, 30.0)
				L.target(map, p + Vector3(0, 12, 0), oname, "stadium")
			"tower":
				L.tower(map, Vector2(p.x, p.z), Vector2(16, 16), rot, 110.0, 2, Color(0.3, 0.4, 0.52), oname)
				L.target(map, p + Vector3(0, 50, 0), oname, "tower")
			_:
				L.classical(map, p, rot, oname, Vector3(60, 22, 26), Color(0.86, 0.82, 0.72))
				L.target(map, p + Vector3(0, 12, 0), oname, "gov")
	# a city nobody put an object into is still aimed at: the heart of every district
	if map.targets.is_empty():
		for d in districts:
			L.target(map, Vector3(float(d[1]), 10.0, float(d[2])), String(d[0]), "center")
	if map.targets.is_empty():
		L.target(map, Vector3(0, 10, 0), name, "center")


# --- The data ------------------------------------------------------------------------------------
static func object_name(kind: String) -> String:
	for o in OBJECT_KINDS:
		if String(o[0]) == kind:
			return String(o[1])
	return "Объект"


static func object_radius(kind: String) -> float:
	for o in OBJECT_KINDS:
		if String(o[0]) == kind:
			return float(o[2])
	return 60.0


static func district_spec(kind: String) -> Array:
	for k in DISTRICT_KINDS:
		if String(k[0]) == kind:
			return k
	return DISTRICT_KINDS[2]


static func block_of(kind: String) -> float:
	return float(district_spec(kind)[2])


## An empty city of the editor: a name and a square of open country.
static func blank(cname: String, size := 7000.0) -> Dictionary:
	return {"name": cname, "size": size, "seed": randi() % 90000 + 1000, "rivers": [], "lakes": [], "forests": [],
		"districts": [], "roads": [], "rails": [], "objects": []}


## A small ready-made city, so a new server can be tried at once: a river, a centre, housing, a
## works and a power station. `flip` mirrors it, so the two cities of a server differ.
static func sample(cname: String, flip := false) -> Dictionary:
	var s := -1.0 if flip else 1.0
	var d := blank(cname, 7000.0)
	d.rivers = [{"n": "", "p": [[-7000.0 * s, -2600.0, 160.0], [-3000.0 * s, -1500.0, 190.0], [600.0 * s, -1900.0, 210.0], [3600.0 * s, -700.0, 230.0], [7000.0 * s, -900.0, 260.0]]}]
	d.lakes = [[2600.0 * s, 3300.0, 420.0, 260.0, 20.0]]
	d.forests = [[-4300.0 * s, 3600.0, 1500.0, 1100.0, 0.0], [4600.0 * s, -4300.0, 1600.0, 1200.0, 15.0]]
	d.districts = [
		[GS.t("Центр"), 0.0, 300.0, 0.0, "stalin", 900.0],
		[GS.t("Старый город"), -900.0 * s, -700.0, 12.0, "historic", 650.0],
		[GS.t("Заречье"), 1200.0 * s, -3300.0, -8.0, "khrush", 1000.0],
		[GS.t("Северный"), -2200.0 * s, 1500.0, 5.0, "panel", 1200.0],
		[GS.t("Восточный"), 2500.0 * s, 1300.0, -10.0, "panel", 1200.0],
		[GS.t("Новый"), 300.0 * s, 2700.0, 0.0, "new", 1000.0],
		[GS.t("Промзона"), -3500.0 * s, -200.0, 0.0, "industrial", 1100.0],
		[GS.t("Посёлок"), 4300.0 * s, 3100.0, 0.0, "private", 900.0],
	]
	d.roads = [
		{"n": GS.t("Главный проспект"), "p": [[-6500.0 * s, 900.0], [-2400.0 * s, 600.0], [0.0, 300.0], [2600.0 * s, 700.0], [6500.0 * s, 1500.0]]},
		{"n": GS.t("Речной мост"), "p": [[200.0 * s, 2800.0], [100.0 * s, 500.0], [700.0 * s, -1900.0], [1200.0 * s, -3600.0], [1500.0 * s, -6500.0]]},
	]
	d.rails = [{"n": "", "p": [[-7000.0 * s, 2300.0], [-2600.0 * s, 2100.0], [900.0 * s, 1700.0], [4200.0 * s, 2300.0], [7000.0 * s, 2600.0]]}]
	d.objects = [
		{"k": "tpp", "x": -4300.0 * s, "z": -900.0, "r": 0.0, "n": ""},
		{"k": "plant", "x": -3200.0 * s, "z": 500.0, "r": 10.0, "n": ""},
		{"k": "rail", "x": 900.0 * s, "z": 1700.0, "r": 5.0, "n": ""},
		{"k": "gov", "x": 100.0 * s, "z": 200.0, "r": 0.0, "n": ""},
		{"k": "tv", "x": 2900.0 * s, "z": 2300.0, "r": 0.0, "n": ""},
		{"k": "oil", "x": 3400.0 * s, "z": -2500.0, "r": 0.0, "n": ""},
	]
	return d


## Short plain text: no line breaks, no control characters, no "%" (names go into format strings).
static func clean_name(v, limit := NAME_MAX) -> String:
	var s := String(v) if v is String or v is StringName else ""
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 32 and c != 37 and c != 127:
			out += s[i]
	return out.strip_edges().substr(0, limit)


static func _num(v, lo: float, hi: float, fallback := 0.0) -> float:
	if not (v is float or v is int):
		return clampf(fallback, lo, hi)
	var f := float(v)
	return clampf(f, lo, hi) if is_finite(f) else clampf(fallback, lo, hi)


static func _list(v) -> Array:
	return v if v is Array else []


## Control points [[x, z, extra…], …] inside the square; fewer than two make no line.
static func _points(v, half_size: float, extra_lo := 0.0, extra_hi := 0.0) -> Array:
	var out := []
	for p in _list(v):
		if not (p is Array) or (p as Array).size() < 2 or out.size() >= MAX_POINTS:
			continue
		var row := [_num(p[0], -half_size, half_size), _num(p[1], -half_size, half_size)]
		if extra_hi > 0.0:
			row.append(_num(p[2] if (p as Array).size() > 2 else extra_lo, extra_lo, extra_hi, extra_lo))
		# two points on one spot would make a segment of no length
		if out.is_empty() or Vector2(row[0] - out[-1][0], row[1] - out[-1][1]).length() > 20.0:
			out.append(row)
	return out if out.size() >= 2 else []


static func _ellipses(v, half_size: float, limit: int, rmin: float, rmax: float) -> Array:
	var out := []
	for e in _list(v):
		if not (e is Array) or (e as Array).size() < 4 or out.size() >= limit:
			continue
		out.append([_num(e[0], -half_size, half_size), _num(e[1], -half_size, half_size), _num(e[2], rmin, rmax, rmin), _num(e[3], rmin, rmax, rmin),
			_num(e[4] if (e as Array).size() > 4 else 0.0, -360.0, 360.0)])
	return out


static func _lines(v, half_size: float, limit: int, wmin := 0.0, wmax := 0.0) -> Array:
	var out := []
	for r in _list(v):
		if not (r is Dictionary) or out.size() >= limit:
			continue
		var pts := _points(r.get("p"), half_size, wmin, wmax)
		if not pts.is_empty():
			out.append({"n": clean_name(r.get("n", "")), "p": pts})
	return out


## The data as the generator may take it, whatever came in.
static func clean(d) -> Dictionary:
	var src: Dictionary = d if d is Dictionary else {}
	var size := _num(src.get("size", 7000.0), SIZE_MIN, SIZE_MAX, 7000.0)
	var cname := clean_name(src.get("name", ""))
	var out := {"name": cname if cname != "" else "Город", "size": size, "seed": int(_num(src.get("seed", 1482), 1.0, 999999.0, 1482.0)),
		"rivers": _lines(src.get("rivers"), size, MAX_RIVERS, 20.0, 900.0),
		"lakes": _ellipses(src.get("lakes"), size, MAX_LAKES, 60.0, 3000.0),
		"forests": _ellipses(src.get("forests"), size, MAX_FORESTS, 100.0, 5000.0),
		"districts": [], "roads": _lines(src.get("roads"), size, MAX_ROADS), "rails": _lines(src.get("rails"), size, MAX_RAILS), "objects": []}
	for e in _list(src.get("districts")):
		if not (e is Array) or (e as Array).size() < 6 or out.districts.size() >= MAX_DISTRICTS:
			continue
		var kind := String(e[4]) if e[4] is String else "panel"
		var dname := clean_name(e[0])
		out.districts.append([dname if dname != "" else "Район", _num(e[1], -size, size), _num(e[2], -size, size), _num(e[3], -90.0, 90.0),
			String(district_spec(kind)[0]), _num(e[5], 300.0, 2500.0, 900.0)])
	for o in _list(src.get("objects")):
		if not (o is Dictionary) or out.objects.size() >= MAX_OBJECTS:
			continue
		var kind := String(o.get("k", "gov")) if o.get("k") is String else "gov"
		if not OBJECT_KINDS.any(func(k) -> bool: return String(k[0]) == kind):
			kind = "gov"
		out.objects.append({"k": kind, "x": _num(o.get("x"), -size, size), "z": _num(o.get("z"), -size, size), "r": _num(o.get("r"), -360.0, 360.0),
			"n": clean_name(o.get("n", ""))})
	return out
