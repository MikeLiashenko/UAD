extends RefCounted
## One playable city: its geography (rivers, lakes, the sea, islands, forests and where the built-up
## area ends), the districts with their own street grids, highways and railways, the unique landmarks
## and the words the interface uses for it. CityMap (scripts/world/city_map.gd) builds the 3D world
## from this description; every city lives in scripts/world/cities/<id>.gd.
##
## Coordinates: x grows to the east, z to the south (−z is north). The playable area is ±1000.

const Landmarks = preload("res://scripts/world/landmarks.gd")

var id := ""
## Name in the source language (Russian), translated through GS.t().
var name := ""
## Bumped whenever the layout changes: building indices saved by an older layout are dropped.
var version := 1
## RNG seed of the city generator and the seeds of the two zone noises.
var seed := 1482
var noise_seed := 31
var noise2_seed := 77
## Accent colour of the city card on the "create world" screen.
var accent := Color(0.3, 0.9, 1.0)
## One-line description on the city card.
var blurb := ""
## Where the map screen starts looking.
var map_focus := Vector3(60, 0, 0)

## Phrases shown in the interface (all of them are translation keys).
var texts := {}
var video_channel := "@kyiv_cuts"
var video_authors: Array = []
## Bearings the raids come from (degrees, 0 = north, 90 = east).
var threat_sectors: Array = [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 270.0]

# --- What the enemy launches at this city (the director builds every night from it) ----------------
## Slot → [[weapon (GS.ENEMIES key), weight, first night], ...]. Slots: drone, cruise, ballistic.
var raid := {
	"drone": [["shahed", 1.0, 1]],
	"cruise": [["cruise", 1.0, 1]],
	"ballistic": [["ballistic", 1.0, 1]],
}
## First night of the missile slots (near the border the ballistics come early).
var raid_start := {"cruise": 3, "ballistic": 5}
## Bearings of the weapons launched from one area (the sea, over the border); others use threat_sectors.
var raid_sectors := {}
## Launches on top of the waves: [{"weapon", "from" (night), "count": [min, max], "base": bool, "at": 0..1}].
var raid_extra: Array = []
## Extraordinary strikes on given nights: night → {"weapon", "count", "aim" (target name), "alert", "note"}.
var raid_events := {}
## One line about the enemy's arsenal for the city card and the night briefing.
var raid_note := ""

# --- Geography -----------------------------------------------------------------------------------
## Rivers and canals: {"name", "pts": PackedVector2Array, "w": PackedFloat32Array (half widths)}.
var rivers: Array = []
## Open water ellipses (lakes, bays, reservoirs): [x, z, rx, rz, rot_deg].
var lakes: Array = []
## Land inside water: [x, z, rx, rz, rot_deg, zone]. zone: GS.Zone.FOREST or GS.Zone.SAND.
var islands: Array = []
## Zone-only areas (they do not change the water), same format: woods between two channels, beaches.
var parks: Array = []
## True when sea_dist() describes a sea coast.
var has_sea := false
## Named woods and parks: [x, z, radius, wobble]. The wobble bends the edge with the zone noise.
var forests: Array = []
## The built-up area is the ellipse (city_center, city_radii), frayed by noise.
var city_center := Vector2(60, 0)
var city_radii := Vector2(780, 720)
## How much of the city turns into small random parks (higher = fewer parks).
var park_threshold := 0.45
## Beaches: water closer than this turns the bank into sand (0 = none).
var beach_width := 0.0

## Districts: [name, x, z, grid angle (deg), block size, character]. Every district is the Voronoi
## cell around its seed; the characters are listed in CityGen._fill_block.
var districts: Array = []
## Highways: {"name", "pts": PackedVector2Array, "w": half width, "bridges": [{"name", "style", "target"}]}.
## Where a highway crosses water it gets a bridge (styles: girder, cable, cable_a, arch, metro, truss).
var roads: Array = []
## Railways: {"name", "pts", "trains": count, "cars": per train, "bridge": {"name", "style", "target"}}.
var rails: Array = []
## Stand-alone bridges without a highway: {"a", "b", "name", "style", "target"}.
var bridges: Array = []
## Boat lanes (each boat goes back and forth along one of them).
var boat_lanes: Array = []
## Map captions: [text, Vector3, font size, Color].
var labels: Array = []


# --- Hooks a city overrides ------------------------------------------------------------------------
## Signed distance to the sea (negative = at sea). Only used when has_sea is true.
func sea_dist(_x: float, _z: float) -> float:
	return 1e6


## A city-specific zone rule that runs before the generic ones (−1 = no opinion).
func zone_hook(_map, _x: float, _z: float, _wd: float, _n: float) -> int:
	return -1


## < 1 inside the built-up area.
func city_norm(x: float, z: float) -> float:
	return Vector2((x - city_center.x) / city_radii.x, (z - city_center.y) / city_radii.y).length()


## Unique buildings. Runs before the city blocks are generated, so their plots stay free.
func build_landmarks(_map) -> void:
	pass


## Water beyond the edge of the map (the open sea), drawn by the city itself.
func build_outer(_map) -> void:
	pass


## Coastline for the radar (the rivers are added automatically).
func radar_coast() -> Array:
	return []


func text(key: String) -> String:
	return String(texts.get(key, key))


# --- Helpers for the city files ----------------------------------------------------------------------
## A smooth river through control points [x, z, half width]: Catmull-Rom, one point per ~step metres.
static func smooth(ctrl: Array, step := 25.0) -> Array:
	var pts := PackedVector2Array()
	var ws := PackedFloat32Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector3 = _v3(ctrl[maxi(i - 1, 0)])
		var p1: Vector3 = _v3(ctrl[i])
		var p2: Vector3 = _v3(ctrl[i + 1])
		var p3: Vector3 = _v3(ctrl[mini(i + 2, n - 1)])
		var seg := Vector2(p2.x - p1.x, p2.y - p1.y).length()
		var k := maxi(1, int(ceil(seg / step)))
		for j in k:
			var t := float(j) / float(k)
			var q := _catmull(p0, p1, p2, p3, t)
			pts.append(Vector2(q.x, q.y))
			ws.append(maxf(q.z, 1.0))
	var last: Vector3 = _v3(ctrl[n - 1])
	pts.append(Vector2(last.x, last.y))
	ws.append(last.z)
	return [pts, ws]


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]) if (a as Array).size() > 2 else 0.0)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func add_river(rname: String, ctrl: Array, step := 25.0) -> void:
	var s := smooth(ctrl, step)
	rivers.append({"name": rname, "pts": s[0], "w": s[1]})


## A highway through control points [x, z] (smoothed a little so curves are not jagged).
func add_road(rname: String, ctrl: Array, half_w := 8.0, bridges_on_it := []) -> void:
	var c := []
	for p in ctrl:
		c.append([p[0], p[1], half_w])
	var s := smooth(c, 30.0)
	roads.append({"name": rname, "pts": s[0], "w": half_w, "bridges": bridges_on_it})


func add_rail(rname: String, ctrl: Array, trains := 1, cars := 7, bridge := {}) -> void:
	var c := []
	for p in ctrl:
		c.append([p[0], p[1], 3.0])
	var s := smooth(c, 30.0)
	rails.append({"name": rname, "pts": s[0], "trains": trains, "cars": cars, "bridge": bridge})


func label(t: String, x: float, z: float, size := 60, col := Color(0.8, 1.0, 0.9, 0.85)) -> void:
	labels.append([t, Vector3(x, 40, z), size, col])
