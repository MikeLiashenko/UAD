extends "res://scripts/world/city_def.gd"
## Odesa: the Black Sea to the east, the Kuyalnik and Khadzhibey estuaries in the north behind the
## Peresyp isthmus, the port with its moles below the Primorsky boulevard, the beaches of Luzanivka,
## Lanzheron and Arkadia. The historic centre on its strict grid, the Opera, the Potemkin Stairs,
## the Vorontsov lighthouse. Raids come in from the sea.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

const PUB := 2
const IND := 1

## The coastline: x of the water's edge every COAST_STEP metres of z (from COAST_Z0).
const COAST_Z0 := -1300.0
const COAST_STEP := 20.0
var _coast := PackedFloat32Array()


func _init() -> void:
	id = "odesa"
	name = "Одесса"
	version = 1
	seed = 3301
	noise_seed = 21
	noise2_seed = 64
	accent = Color(0.35, 0.65, 1.0)
	blurb = "Море, порт и Потёмкинская лестница: шахеды и ракеты заходят с моря. Сбитое над акваторией падает в воду, но исторический центр хрупок."
	map_focus = Vector3(80, 0, -120)
	texts = {
		"defense": "Оборона Одессы",
		"title": "ОДЕССА",
		"over": "Ночное дежурство над Одессой",
		"duty": "%s РАДАР АКТИВЕН · ПВО ОДЕССЫ НА ДЕЖУРСТВЕ",
		"raid": "НОЧЬ %d — МАССИРОВАННЫЙ НАЛЁТ НА ОДЕССУ!",
		"held": "Одесса выстояла. %d ночей обороны позади.",
		"water_into": "в море",
		"water_safe": "в море — без ущерба",
		"water_label": "МОРЕ — безопасно",
		"shore": "Морское побережье",
		"shore_desc": "Безопасная зона: цели, сбитые над морем, падают в воду.\nОткрытый обзор над морем: дальность ствольной ПВО +10%.",
		"rec": "REC ● 60 км/ч · ОДЕССА",
	}
	video_channel = "@odesa_cuts"
	video_authors = ["@arcadia_night", "@odesa.live", "@moldavanka_cam", "@port_view", "@fontan_balcony",
		"@nightwatch_ua", "@taxi_2am", "@rooftop_odesa", "@deribas_cam", "@lanzheron"]
	# from the sea: the east, the south-east and the south
	threat_sectors = [45.0, 70.0, 90.0, 105.0, 120.0, 135.0, 150.0, 170.0, 200.0]
	raid = {
		"drone": [["shahed", 0.7, 1], ["gerbera", 0.3, 2], ["geran3", 0.12, 8]],
		"cruise": [["kalibr", 0.55, 3], ["oniks", 0.45, 4]],
		"ballistic": [["ballistic", 0.6, 5], ["kh22", 0.4, 6]],
	}
	raid_sectors = {
		"kalibr": [100.0, 130.0, 160.0, 190.0],
		"oniks": [120.0, 135.0, 150.0],
		"kh31p": [120.0, 135.0, 150.0],
		"ballistic": [110.0, 130.0, 150.0],
		"kh22": [100.0, 130.0, 160.0, 190.0],
	}
	# from night 4 the Su-24s from Crimea hunt the battery's radar with Kh-31P
	raid_extra = [{"weapon": "kh31p", "from": 4, "count": [1, 2], "base": true, "at": 0.6}]
	raid_note = "Одессу бьют с моря и из Крыма: «Калибры» с кораблей, сверхзвуковые «Ониксы» над самой водой, Х-22, «Искандеры». С четвёртой ночи Х-31П охотятся за радаром вашей базы."
	city_center = Vector2(-100, 0)
	city_radii = Vector2(750, 950)
	has_sea = true
	_build_coast()
	_geography()
	_districts()
	_routes()
	_labels()


# --- The sea ----------------------------------------------------------------------------------------------
func _build_coast() -> void:
	var ctrl := [[-1350, 360, 0], [-1150, 330, 0], [-900, 240, 0], [-650, 170, 0], [-420, 215, 0], [-250, 270, 0], [-80, 285, 0],
		[150, 300, 0], [450, 390, 0], [750, 470, 0], [1150, 540, 0], [1350, 570, 0]]
	var s := smooth(ctrl, 10.0)
	var pts: PackedVector2Array = s[0]
	# resample to a regular table: pts are (z, x) pairs here
	var z := COAST_Z0
	var i := 0
	while z <= -COAST_Z0:
		while i < pts.size() - 2 and pts[i + 1].x < z:
			i += 1
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var t := clampf((z - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		var x := lerpf(a.y, b.y, t) + 7.0 * sin(z * 0.031) + 4.0 * sin(z * 0.077 + 1.0)
		_coast.append(x)
		z += COAST_STEP


func coast_x(z: float) -> float:
	var f := clampf((z - COAST_Z0) / COAST_STEP, 0.0, _coast.size() - 1.001)
	var i := int(f)
	return lerpf(_coast[i], _coast[i + 1], f - i)


func sea_dist(x: float, z: float) -> float:
	var f := clampf((z - COAST_Z0) / COAST_STEP, 1.0, _coast.size() - 2.001)
	var i := int(f)
	var slope := (_coast[i + 1] - _coast[i - 1]) / (2.0 * COAST_STEP)
	return (coast_x(z) - x) / sqrt(1.0 + slope * slope)


func zone_hook(_map, x: float, z: float, _wd: float, n: float) -> int:
	var sd := sea_dist(x, z)
	if sd < 0.0 or (z > -440.0 and z < -80.0):
		return -1 # the port: the quays go straight into the sea
	if sd < 24.0 + n * 6.0:
		return GS.Zone.SAND
	if sd < 70.0 + n * 25.0 and z > -80.0:
		return GS.Zone.FOREST # the parks on the coastal slopes: Shevchenko park, Arkadia
	return -1


func radar_coast() -> Array:
	var line := PackedVector2Array()
	var z := -1100.0
	while z <= 1100.0:
		line.append(Vector2(coast_x(z), z))
		z += 40.0
	return [line]


## The open sea beyond the edge of the map, out to the horizon.
func build_outer(map) -> void:
	var y := 0.35
	var far := 9000.0
	var e := 1100.0
	var v := PackedVector3Array()
	var quads := [[e, far, -far, far], [coast_x(-e), e, -far, -e], [coast_x(e), e, e, far]]
	for q in quads:
		var x0: float = q[0]
		var x1: float = q[1]
		var z0: float = q[2]
		var z1: float = q[3]
		v.append_array([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)])
	var n := PackedVector3Array()
	n.resize(v.size())
	n.fill(Vector3.UP)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := Meshes.part(map, am, map._water_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _geography() -> void:
	# the estuaries behind Peresyp
	lakes.append([-380.0, -820.0, 45.0, 230.0, 8.0])     # Kuyalnik
	lakes.append([-780.0, -640.0, 60.0, 270.0, -12.0])   # Khadzhibey
	lakes.append([-20.0, 820.0, 26.0, 18.0, 0.0])        # a pond in the Kyivskyi district
	forests = [
		[-560.0, 950.0, 170.0, 50.0],    # the woods towards Chornomorsk
		[-620.0, -1000.0, 120.0, 40.0],
		[-120.0, 450.0, 40.0, 10.0],     # Victory park
		[-300.0, -150.0, 38.0, 10.0],    # Dyukivskyi garden
	]
	for k in 2:
		var lane := PackedVector2Array()
		var z := -1100.0
		while z <= 1100.0:
			lane.append(Vector2(coast_x(z) + 150.0 + k * 170.0, z))
			z += 50.0
		boat_lanes.append(lane)


func _districts() -> void:
	districts = [
		# name, x, z, grid angle (deg), block size, character
		["Центр", 0.0, -150.0, 40.0, 58.0, "odesa"],
		["Молдаванка", -250.0, -40.0, 40.0, 52.0, "podil"],
		["Порт", 185.0, -320.0, 0.0, 60.0, "docks"],
		["Пересыпь", -80.0, -560.0, 10.0, 64.0, "industrial"],
		["Котовского", -120.0, -900.0, 0.0, 70.0, "panel"],
		["Слободка", -450.0, -250.0, 10.0, 56.0, "khrush"],
		["Ближние Мельницы", -420.0, 60.0, 0.0, 60.0, "khrush"],
		["Черёмушки", -220.0, 330.0, 0.0, 62.0, "panel"],
		["Французский бульвар", 130.0, 160.0, 40.0, 56.0, "villas"],
		["Аркадия", 250.0, 470.0, 30.0, 56.0, "new"],
		["Киевский", -80.0, 600.0, 10.0, 62.0, "mixed"],
		["Таирова", -250.0, 800.0, 10.0, 70.0, "panel"],
		["Фонтан", 300.0, 820.0, 20.0, 60.0, "villas"],
		["Малиновский", -620.0, 250.0, 0.0, 64.0, "panel"],
	]


func _routes() -> void:
	add_road("Французский бульвар", [[60, -60], [170, 200], [260, 500], [340, 800], [420, 1000]], 8.0)
	add_road("Николаевская дорога", [[-60, -300], [-80, -600], [-60, -800], [0, -1000]], 9.0)
	add_road("Балковская улица", [[-150, -50], [-300, 200], [-450, 500], [-600, 800], [-700, 1000]], 8.0)
	add_road("Киевское шоссе", [[-250, -120], [-600, -80], [-1000, -40]], 9.0)
	add_rail("Одесская железная дорога", [[-1000, 262], [-700, 248], [-420, 240], [-240, 232], [-60, 230]], 2, 8)


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	label("ЧЁРНОЕ МОРЕ", 700.0, 100.0, 80, blue)
	label("Одесский залив", 420.0, -700.0, 52, blue)
	label("Куяльницкий лиман", -380.0, -820.0, 44, blue)
	label("Хаджибейский лиман", -780.0, -640.0, 44, blue)
	label("Ланжерон", 330.0, -40.0, 36, Color(1.0, 0.95, 0.7, 0.85))
	label("Аркадия", 430.0, 470.0, 40, Color(1.0, 0.95, 0.7, 0.85))
	label("Лузановка", 300.0, -1000.0, 40, Color(1.0, 0.95, 0.7, 0.85))


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	_port(map)
	_stairs(map)
	_centre(map)
	L.power_plant(map, Vector3(-240, 0, -420), 10.0, "Одесская ТЭЦ")
	L.power_plant(map, Vector3(-520, 0, 360), 0.0, "ТЭЦ-2")
	L.lattice_tower(map, Vector3(-380, 0, 560), "Одесская телебашня", 95.0)
	L.station(map, Vector3(-160, 0, 180), 0.0, "Главный вокзал", Color(0.94, 0.88, 0.72), 34.0)
	L.airport(map, Vector3(-720, 0, 560), 30.0, "Аэропорт Одесса")
	L.stadium(map, Vector3(190, 0, 60), 40.0, "стадион «Черноморец»")
	L.ferris_wheel(map, Vector3(228, 0, 135), 40.0, 18.0, "колесо обозрения в парке Шевченко")
	# the refinery of Peresyp: tanks, distillation columns and the flare
	L.tanks(map, Vector3(-200, 0, -700), 0.0, 8, 11.0, "Одесский НПЗ", true)
	for i in 3:
		var p := Vector3(-140, 0, -640 + i * 16)
		map.add_cyl(p, 3.0, 42.0 - i * 6.0, Color(0.7, 0.7, 0.72))
		map.add_footprint(Vector2(p.x, p.z), Vector2(3, 3), 0.0, 42.0 - i * 6.0, IND, "Одесский НПЗ")
		map.add_light(p + Vector3(0, 43.0 - i * 6.0, 0), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)
	map.add_cyl(Vector3(-120, 0, -700), 1.2, 50.0, Color(0.6, 0.6, 0.62))
	map.add_light(Vector3(-120, 52, -700), Color(1.0, 0.55, 0.15), true, 4.0, 0.003)
	map.reserve(-140, -620, 30.0)
	# Arkadia towers
	L.tower(map, Vector2(330, 460), Vector2(12, 12), 30.0, 110.0, 2, Color(0.3, 0.42, 0.55), "ЖК «Аркадийский дворец»")
	L.tower(map, Vector2(350, 500), Vector2(11, 11), 30.0, 95.0, 0, Color(0.92, 0.9, 0.86), "ЖК «Гагарин Плаза»")
	L.tower(map, Vector2(318, 532), Vector2(11, 10), 30.0, 86.0, 2, Color(0.28, 0.36, 0.44), "ЖК «Жемчужина»")


func _port(map) -> void:
	L.port(map, Vector3(coast_x(-330.0) - 30.0, 0, -330.0), 90.0, "Одесский морской порт", 5, "")
	L.containers(map, Vector2(coast_x(-470.0) - 45.0, -470.0), 90.0, 56.0, 40.0, map.rng)
	L.target(map, Vector3(coast_x(-470.0) - 45.0, 6, -470.0), "контейнерный терминал", "port")
	# the moles
	L.pier(map, Vector2(coast_x(-250.0) - 6.0, -250.0), Vector2(coast_x(-250.0) + 150.0, -266.0), 10.0, "Карантинный мол")
	L.pier(map, Vector2(coast_x(-420.0) - 6.0, -420.0), Vector2(coast_x(-420.0) + 130.0, -455.0), 10.0, "Нефтяной мол")
	var lh_a := Vector2(coast_x(-150.0) + 20.0, -140.0)
	var lh_b := Vector2(coast_x(-150.0) + 190.0, -200.0)
	L.pier(map, Vector2(coast_x(-150.0) - 6.0, -150.0), lh_b, 9.0, "Рейдовый мол")
	L.lighthouse(map, Vector3(lh_b.x, 2.2, lh_b.y), "Воронцовский маяк", 28.0)
	# the Marine Station on its pier and the hotel "Odesa" at its end
	var ms_a := Vector2(coast_x(-178.0) - 6.0, -178.0)
	var ms_b := Vector2(coast_x(-178.0) + 95.0, -180.0)
	L.pier(map, ms_a, ms_b, 26.0, "причал Морвокзала")
	var mv := L.group(Vector3((ms_a.x + ms_b.x) * 0.5 - 10.0, 0, -179.0), 0.0)
	L.block(map, mv, Vector3.ZERO, Vector2(28, 10), 14.0, 2, Color(0.8, 0.84, 0.86), "Морской вокзал")
	L.tower(map, Vector2(ms_b.x - 12.0, -180.0), Vector2(10, 10), 0.0, 88.0, 2, Color(0.28, 0.4, 0.5), "гостиница «Одесса»", Color(0.4, 0.8, 1.0))
	L.target(map, Vector3(ms_b.x - 40.0, 6, -179.0), "Морской вокзал", "port")
	map.reserve(lh_a.x, lh_a.y, 10.0)
	# ships at the quays and on the roads outside the harbour
	L.ship(map, Vector3(coast_x(-310.0) + 34.0, 0, -310.0), 90.0, 120.0, "container", "контейнеровоз")
	L.ship(map, Vector3(coast_x(-380.0) + 34.0, 0, -385.0), 90.0, 100.0, "bulk", "зерновоз")
	L.ship(map, Vector3(coast_x(-220.0) + 60.0, 0, -228.0), 95.0, 70.0, "bulk", "сухогруз")
	for spec in [[-650.0, 380.0, 60.0, "bulk"], [-80.0, 430.0, 110.0, "container"], [260.0, 470.0, 35.0, "bulk"], [620.0, 520.0, 80.0, "container"]]:
		L.ship(map, Vector3(coast_x(float(spec[0])) + float(spec[1]), 0, float(spec[0])), float(spec[2]), 110.0, String(spec[3]), "судно на рейде")


## Potemkin Stairs: ten flights from the port up to the Duke on the Primorsky boulevard.
func _stairs(map) -> void:
	var bottom := coast_x(-178.0) - 26.0
	var g := L.group(Vector3(bottom, 0, -178.0), 0.0)
	var stone := L.lit(Color(0.78, 0.76, 0.7), 0.18)
	for i in 10:
		var x := -i * 7.0
		var w := 40.0 - i * 1.6
		var h := 1.8 + i * 1.8
		L.box(g, Vector3(7.2, h, w), Vector3(x, h * 0.5, 0), stone)
		L.fp(map, g, Vector3(x, 0, 0), Vector2(3.6, w * 0.5), h, "Потёмкинская лестница")
	# the landing on top and the Duke de Richelieu
	L.box(g, Vector3(14, 19.8, 26), Vector3(-76, 9.9, 0), stone)
	L.fp(map, g, Vector3(-76, 0, 0), Vector2(7, 13), 19.8, "Потёмкинская лестница")
	L.box(g, Vector3(2.4, 4, 2.4), Vector3(-76, 21.8, 0), Fx.solid(Color(0.4, 0.38, 0.36)))
	L.cyl(g, 0.6, 0.8, 3.6, Vector3(-76, 25.6, 0), Fx.solid(Color(0.25, 0.35, 0.3), 0.4, 0.7), 8)
	for s in [-1.0, 1.0]:
		L.light(map, g, Vector3(-74, 21.0, s * 12.0), Color(1.0, 0.85, 0.6), false, 1.4, 0.0022)
	map.reserve(bottom - 40.0, -178.0, 44.0)


func _centre(map) -> void:
	# the Opera and Ballet Theatre: baroque horseshoe with a dome
	var op := L.classical(map, Vector3(70, 0, -120), 40.0, "Оперный театр", Vector3(46, 24, 36), Color(0.93, 0.87, 0.72), Fx.solid(Color(0.3, 0.45, 0.42), 0.4, 0.6))
	for s in [-1.0, 1.0]:
		L.cyl(op, 5.0, 5.0, 22.0, Vector3(s * 23.0, 11, -10), L.lit(Color(0.93, 0.87, 0.72), 0.2), 16)
	L.target(map, Vector3(70, 10, -120), "Оперный театр", "center")
	# Transfiguration Cathedral on Cathedral square
	L.cathedral(map, Vector3(-40, 0, -40), 40.0, "Спасо-Преображенский собор", Color(0.95, 0.92, 0.84), L.gold(), 1.0, 4, true, "колокольня Спасо-Преображенского собора")
	# the Vorontsov palace with its colonnade over the port
	var vp := L.classical(map, Vector3(118, 0, -300), 0.0, "Воронцовский дворец", Vector3(30, 14, 16), Color(0.94, 0.92, 0.86))
	for i in 9:
		var a := deg_to_rad(-80.0 + i * 20.0)
		L.cyl(vp, 0.8, 0.9, 9.0, Vector3(34.0 + cos(a) * 14.0, 4.5, sin(a) * 14.0), L.lit(Color(0.95, 0.94, 0.9), 0.3), 8)
	# the City Hall on the Primorsky boulevard, the Privoz market
	L.classical(map, Vector3(120, 0, -225), 0.0, "Одесская мэрия", Vector3(34, 18, 22), Color(0.92, 0.86, 0.72), Fx.solid(Color(0.3, 0.45, 0.42), 0.4, 0.6))
	L.target(map, Vector3(120, 10, -225), "Одесская мэрия", "gov")
	var pv := L.group(Vector3(-150, 0, 70), 40.0)
	L.block(map, pv, Vector3.ZERO, Vector2(26, 16), 10.0, 3, Color(0.7, 0.66, 0.6), "рынок «Привоз»", PUB, 3.0, Color(0.3, 0.4, 0.45))
	map.reserve(-150, 70, 32.0)
