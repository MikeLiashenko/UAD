extends Object
## One playable city at its real size: the geography (rivers, lakes, the sea, islands, forests),
## the districts with their own street grids, avenues and railways, the unique landmarks and the
## words the interface uses for it. CityMap (scripts/world/city_map.gd) builds the 3D world from
## this description; every city lives in scripts/world/cities/<id>.gd.
##
## (A plain Object, not RefCounted: the generator calls into it from many threads at once and
## reference counting would make them wait for each other. Cities live as long as the game.)
##
## Coordinates are metres: x grows to the east, z to the south (−z is north), the origin is the
## geographic point (lat0, lon0). The playable area is the square ±half. City files give most of
## their points as latitude / longitude (ll(), the *_ll helpers), so everything stands where it
## stands in the real city.

const Landmarks = preload("res://scripts/world/landmarks.gd")

## The zones (GS.Zone) as plain constants for the city files.
const Z_FIELD := 0
const Z_FOREST := 1
const Z_WATER := 2
const Z_CITY := 3
const Z_SAND := 4

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
## Where the map screen starts looking and what the menu camera circles.
var map_focus := Vector3.ZERO

## The city has its own zone rule (zone_hook below) for land closer than this to water.
var hook_reach := 0.0
## Half of the playable square, metres (the real city is 25–35 km across).
var half := 15000.0
## The geographic point at x = 0, z = 0.
var lat0 := 50.45
var lon0 := 30.53

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
## The sea, when the city has one: x of the water's edge every coast_step metres of z, from coast_z0
## (the sea lies to the east of the line). The table covers z from -(half + 1000) to half + 1000.
var has_sea := false
var coast := PackedFloat32Array()
var coast_z0 := 0.0
var coast_step := 20.0
## The open sea beyond the map, for the land drawn out to the horizon: two shore lines running on
## from where the coast leaves the map, [x, z, nx, nz] each (n points to the sea). The first holds
## east of the map, the second south of it.
var outer_sea: Array = []
## Named woods and parks, ellipses: [x, z, rx, rz, rot_deg, wobble]. The wobble bends the edge with
## the zone noise (0.25 = a quarter of the radius).
var forests: Array = []
## A rough ellipse around the built-up area (where the suburbs end and the open country begins).
var city_center := Vector2.ZERO
var city_radii := Vector2(11000, 11000)
## How much of the city turns into small random parks (higher = fewer parks).
var park_threshold := 0.45
## Beaches: water closer than this turns the bank into sand (0 = none).
var beach_width := 0.0

## Districts: [name, x, z, grid angle (deg), block size, character, radius]. Every district is the
## part of the Voronoi cell around its seed that lies within its radius — beyond it the land is
## open (fields, woods, water). The characters are listed in CityGen.fill_block.
var districts: Array = []
## Avenues and highways: {"name", "pts": PackedVector2Array, "w": half width, "bridges": [{"name", "style", "target"}]}.
## Where one crosses water it gets a bridge (styles: girder, cable, cable_a, arch, metro, truss).
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
## x of the sea shore at z.
func coast_x(z: float) -> float:
	var f := clampf((z - coast_z0) / coast_step, 0.0, coast.size() - 1.001)
	var i := int(f)
	return lerpf(coast[i], coast[i + 1], f - i)


## Signed distance to the sea (negative = at sea), 1e6 when the city has none.
func sea_dist(x: float, z: float) -> float:
	if coast.size() < 3:
		return 1e6
	var f := clampf((z - coast_z0) / coast_step, 1.0, coast.size() - 2.001)
	var i := int(f)
	var slope := (coast[i + 1] - coast[i - 1]) / (2.0 * coast_step)
	return (lerpf(coast[i], coast[i + 1], f - i) - x) / sqrt(1.0 + slope * slope)


## A city-specific zone rule that runs before the generic ones (−1 = no opinion). Only asked for
## land within hook_reach of water (`wd` = distance to it, `n` = the zone noise there).
func zone_hook(_map, _x: float, _z: float, _wd: float, _n: float) -> int:
	return -1


## < 1 inside the rough ellipse of the built-up area.
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


# --- Geographic helpers ------------------------------------------------------------------------------
## Latitude / longitude → map metres (x east, z south).
func ll(lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)), -(lat - lat0) * 111200.0)


## Same, as a point on the ground.
func ll3(lat: float, lon: float, y := 0.0) -> Vector3:
	var p := ll(lat, lon)
	return Vector3(p.x, y, p.y)


## [[lat, lon, extra...], ...] → [[x, z, extra...], ...].
func pts_ll(list: Array) -> Array:
	var out := []
	for p in list:
		var q := ll(float(p[0]), float(p[1]))
		var row := [q.x, q.y]
		for k in range(2, (p as Array).size()):
			row.append(p[k])
		out.append(row)
	return out


# --- Helpers for the city files ----------------------------------------------------------------------
## A smooth line through control points [x, z, half width]: Catmull-Rom, one point per ~step metres.
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


## A river through [x, z, half width] points. Wide rivers get longer segments (a chain of wide
## capsules stays smooth), narrow ones shorter.
func add_river(rname: String, ctrl: Array, step := 0.0) -> void:
	if step <= 0.0:
		var w := 0.0
		for p in ctrl:
			w = maxf(w, float(p[2]))
		step = clampf(w * 0.45, 20.0, 140.0)
	var s := smooth(ctrl, step)
	rivers.append({"name": rname, "pts": s[0], "w": s[1]})


## A river through [lat, lon, half width] points.
func add_river_ll(rname: String, ctrl: Array, step := 0.0) -> void:
	add_river(rname, pts_ll(ctrl), step)


## An avenue or highway through control points [x, z] (smoothed a little so curves are not jagged).
func add_road(rname: String, ctrl: Array, half_w := 12.0, bridges_on_it := []) -> void:
	var c := []
	for p in ctrl:
		c.append([p[0], p[1], half_w])
	var s := smooth(c, 40.0)
	roads.append({"name": rname, "pts": s[0], "w": half_w, "bridges": bridges_on_it})


func add_road_ll(rname: String, ctrl: Array, half_w := 12.0, bridges_on_it := []) -> void:
	add_road(rname, pts_ll(ctrl), half_w, bridges_on_it)


func add_rail(rname: String, ctrl: Array, trains := 1, cars := 7, bridge := {}) -> void:
	var c := []
	for p in ctrl:
		c.append([p[0], p[1], 3.0])
	var s := smooth(c, 40.0)
	rails.append({"name": rname, "pts": s[0], "trains": trains, "cars": cars, "bridge": bridge})


func add_rail_ll(rname: String, ctrl: Array, trains := 1, cars := 7, bridge := {}) -> void:
	add_rail(rname, pts_ll(ctrl), trains, cars, bridge)


## A district seeded at a geographic point: grid angle in degrees, block size and radius in metres.
func district(dname: String, lat: float, lon: float, angle: float, block: float, kind: String, radius: float) -> void:
	var p := ll(lat, lon)
	districts.append([dname, p.x, p.y, angle, block, kind, radius])


## A wood or a park: an ellipse around a geographic point (radii in metres).
func forest_ll(lat: float, lon: float, rx: float, rz: float, rot := 0.0, wobble := 0.25) -> void:
	var p := ll(lat, lon)
	forests.append([p.x, p.y, rx, rz, rot, wobble])


func lake_ll(lat: float, lon: float, rx: float, rz: float, rot := 0.0) -> void:
	var p := ll(lat, lon)
	lakes.append([p.x, p.y, rx, rz, rot])


## Land of a given zone inside water (an island) around a geographic point.
func island_ll(lat: float, lon: float, rx: float, rz: float, rot := 0.0, zone := 1) -> void:
	var p := ll(lat, lon)
	islands.append([p.x, p.y, rx, rz, rot, zone])


## A zone-only area (does not change the water): the woods of an island between two channels.
func park_ll(lat: float, lon: float, rx: float, rz: float, rot := 0.0, zone := 1) -> void:
	var p := ll(lat, lon)
	parks.append([p.x, p.y, rx, rz, rot, zone])


func label(t: String, x: float, z: float, size := 60, col := Color(0.8, 1.0, 0.9, 0.85)) -> void:
	labels.append([t, Vector3(x, 60, z), size, col])


func label_ll(t: String, lat: float, lon: float, size := 60, col := Color(0.8, 1.0, 0.9, 0.85)) -> void:
	var p := ll(lat, lon)
	label(t, p.x, p.y, size, col)
