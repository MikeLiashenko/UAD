extends "res://scripts/world/city_def.gd"
## Odesa at its real size (28 × 28 km). The Black Sea fills the east of the map: the bay with
## Luzanivka in the north, the port with its moles under the Primorsky boulevard, the cape of
## Lanzheron, then twelve kilometres of beaches under the green slopes — Otrada, Arkadia, the
## Fontan — down to Chornomorka. Behind the Peresyp sand bar lie the Kuyalnik and Khadzhibey
## estuaries. The old centre keeps its strict grid: the Opera, the Potemkin Stairs, the cathedral.
## Raids come in from the sea.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")

const PUB := 2
const IND := 1

## The quays of the port run between these two z: no beach, no wobble of the shore there.
var _port_z0 := 0.0
var _port_z1 := 0.0
## North of this z lies Luzanivka; south of the next one the beaches under the slopes begin.
var _luz_z := 0.0
var _slope_z := 0.0


func _init() -> void:
	id = "odesa"
	name = "Одесса"
	version = 2
	seed = 3301
	noise_seed = 21
	noise2_seed = 64
	accent = Color(0.35, 0.65, 1.0)
	blurb = "Море, порт и Потёмкинская лестница: шахеды и ракеты заходят с моря. Сбитое над акваторией падает в воду, но исторический центр хрупок."
	half = 14000.0
	lat0 = 46.47
	lon0 = 30.71
	map_focus = ll3(46.4853, 30.7411)
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
		"drone": [["shahed", 0.7, 1], ["gerbera", 0.3, 2], ["geran3", 0.12, 8], ["geran4", 0.1, 10], ["geran5", 0.1, 12]],
		"cruise": [["kalibr", 0.55, 3], ["oniks", 0.45, 4]],
		"ballistic": [["ballistic", 0.5, 5], ["kh22", 0.35, 6], ["s400", 0.2, 7], ["zircon", 0.25, 8], ["s500", 0.1, 13]],
	}
	raid_sectors = {
		"zircon": [120.0, 135.0, 150.0],
		"s400": [110.0, 130.0, 150.0],
		"s500": [110.0, 130.0, 150.0],
		"kalibr": [100.0, 130.0, 160.0, 190.0],
		"oniks": [120.0, 135.0, 150.0],
		"kh31p": [120.0, 135.0, 150.0],
		"ballistic": [110.0, 130.0, 150.0],
		"kh22": [100.0, 130.0, 160.0, 190.0],
	}
	# from night 4 the Su-24s from Crimea hunt the battery's radar with Kh-31P
	raid_extra = [{"weapon": "kh31p", "from": 4, "count": [1, 2], "base": true, "at": 0.6}]
	raid_note = "Одессу бьют с моря и из Крыма: «Калибры» с кораблей, сверхзвуковые «Ониксы» над самой водой, Х-22, «Искандеры», позже — гиперзвуковые «Цирконы». С четвёртой ночи Х-31П охотятся за радаром вашей базы."
	city_center = ll(46.47, 30.72)
	city_radii = Vector2(9000, 12500)
	hook_reach = 460.0
	_port_z0 = ll(46.5085, 30.73).y
	_port_z1 = ll(46.4795, 30.76).y
	_luz_z = ll(46.5400, 30.75).y
	_slope_z = ll(46.4770, 30.76).y
	_build_coast()
	_geography()
	_districts()
	_routes()
	_labels()


# --- The sea ----------------------------------------------------------------------------------------------
## The shore from the Fontanka cape in the north-east round the bay, the port and Lanzheron and
## down the Fontan to Chornomorka: [lat, lon] of the water's edge.
const SHORE := [[46.6100, 30.9600], [46.5800, 30.9350], [46.5720, 30.9000], [46.5690, 30.8700], [46.5670, 30.8400], [46.5650, 30.8150],
	[46.5620, 30.7990], [46.5580, 30.7880], [46.5520, 30.7750], [46.5450, 30.7625], [46.5370, 30.7530], [46.5280, 30.7460],
	[46.5180, 30.7400], [46.5080, 30.7360], [46.5000, 30.7375], [46.4950, 30.7405], [46.4910, 30.7440], [46.4875, 30.7480],
	[46.4840, 30.7530], [46.4810, 30.7580], [46.4780, 30.7630], [46.4750, 30.7665], [46.4700, 30.7680], [46.4640, 30.7690],
	[46.4570, 30.7700], [46.4500, 30.7690], [46.4400, 30.7660], [46.4320, 30.7640], [46.4200, 30.7610], [46.4050, 30.7590],
	[46.3900, 30.7570], [46.3780, 30.7530], [46.3680, 30.7410], [46.3580, 30.7260], [46.3500, 30.7130], [46.3440, 30.7030],
	[46.3300, 30.6800]]


func _build_coast() -> void:
	# the table is x of the shore for every z: smooth the points as (z, x) pairs and resample
	var ctrl := []
	for p in SHORE:
		var q := ll(float(p[0]), float(p[1]))
		ctrl.append([q.y, q.x, 0.0])
	var pts: PackedVector2Array = smooth(ctrl, 60.0)[0]
	has_sea = true
	coast_step = 50.0
	coast_z0 = -(half + 1000.0)
	var n := int((half + 1000.0) * 2.0 / coast_step) + 1
	coast.resize(n)
	var i := 0
	for k in n:
		var z := coast_z0 + k * coast_step
		while i < pts.size() - 2 and pts[i + 1].x < z:
			i += 1
		var a := pts[i]
		var b := pts[i + 1]
		var t := clampf((z - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		var x := lerpf(a.y, b.y, t)
		# little capes and coves outside the port
		var wild := 1.0 - smoothstep(_port_z0 - 400.0, _port_z0, z) * (1.0 - smoothstep(_port_z1, _port_z1 + 400.0, z))
		x += (16.0 * sin(z * 0.0113) + 9.0 * sin(z * 0.0271 + 1.0) + 5.0 * sin(z * 0.061 + 2.0)) * wild
		coast[k] = x
	# the open sea beyond the map: east of it south of where the shore leaves the map, and east
	# of the shore that runs on south-south-west past Chornomorsk
	var za := coast_z0
	for k in n:
		if coast[k] < half:
			za = coast_z0 + k * coast_step
			break
	var da := Vector2(1.0, -0.29).normalized()
	var db := Vector2(-0.63, 1.0).normalized()
	outer_sea = [half, za, -da.y, da.x, coast_x(half), half, db.y, -db.x]


func zone_hook(_map, x: float, z: float, _wd: float, n: float) -> int:
	var sd := sea_dist(x, z)
	if sd > 600.0:
		# the flat salty shores of the estuaries
		return Z_SAND if _wd < 26.0 + n * 10.0 else -1
	if z > _port_z0 and z < _port_z1:
		return -1 # the port: the quays go straight into the sea
	if z < _port_z0:
		if z < _luz_z:
			# Luzanivka: a wide beach and the park behind it
			if sd < 80.0 + n * 20.0:
				return Z_SAND
			if sd < 330.0 + n * 90.0:
				return Z_FOREST
		return -1
	if sd < 48.0 + n * 14.0:
		return Z_SAND
	if z > _slope_z and sd < 250.0 + n * 90.0:
		return Z_FOREST # the green slopes over the beaches: Otrada, the Health Track, Arkadia
	return -1


func radar_coast() -> Array:
	var line := PackedVector2Array()
	var z := -half
	while z <= half:
		var x := coast_x(z)
		if x < half:
			line.append(Vector2(x, z))
		z += 250.0
	return [line]


func _geography() -> void:
	# the estuaries behind Peresyp (they run on to the north far beyond the map)
	add_river_ll("Куяльницкий лиман", [[46.5630, 30.7330, 450], [46.5800, 30.7230, 1000], [46.6000, 30.7080, 1300], [46.6100, 30.7000, 1350]])
	add_river_ll("Хаджибейский лиман", [[46.5500, 30.6720, 500], [46.5650, 30.6600, 1100], [46.5850, 30.6400, 1500], [46.6100, 30.6200, 1600]])
	lake_ll(46.3930, 30.7230, 160.0, 110.0, 0.0)             # a pond in the Kyivskyi district
	forest_ll(46.4790, 30.7560, 430.0, 380.0, 0.0, 0.1)      # Shevchenko park
	forest_ll(46.4420, 30.7480, 330.0, 260.0, 0.0, 0.1)      # Victory park
	forest_ll(46.4930, 30.7120, 300.0, 260.0, 0.0, 0.1)      # Dyukivskyi garden
	forest_ll(46.4710, 30.7260, 220.0, 200.0, 0.0, 0.1)      # Preobrazhenskyi park
	forest_ll(46.4250, 30.7230, 260.0, 240.0, 0.0, 0.1)      # Gorky park
	forest_ll(46.5050, 30.5800, 2000.0, 1200.0, 20.0, 0.3)   # the belts of wood in the steppe
	forest_ll(46.3950, 30.5900, 1700.0, 1300.0, 0.0, 0.3)
	forest_ll(46.5750, 30.5700, 1500.0, 1100.0, 0.0, 0.3)
	for k in 2:
		var lane := PackedVector2Array()
		var z := -9000.0
		while z <= 12500.0:
			lane.append(Vector2(minf(coast_x(z) + 900.0 + k * 1400.0, half - 300.0), z))
			z += 400.0
		boat_lanes.append(lane)


func _districts() -> void:
	# --- the old city on its grid (Deribasivska runs east-north-east)
	district("Центр", 46.4830, 30.7370, -16.0, 150.0, "odesa", 1150.0)
	district("Привоз", 46.4690, 30.7360, -16.0, 150.0, "historic", 800.0)
	district("Молдаванка", 46.4760, 30.7150, -28.0, 140.0, "podil", 1300.0)
	district("Порт", 46.4960, 30.7345, -32.0, 200.0, "docks", 700.0)
	district("Отрада", 46.4640, 30.7580, -10.0, 160.0, "villas", 900.0)
	district("Французский бульвар", 46.4490, 30.7600, 0.0, 160.0, "villas", 1000.0)
	district("Аркадия", 46.4340, 30.7570, 10.0, 180.0, "new", 800.0)
	district("Большой Фонтан", 46.4080, 30.7500, 0.0, 140.0, "villas", 1500.0)
	district("Дача Ковалевского", 46.3740, 30.7350, 10.0, 140.0, "villas", 1200.0)
	district("Черноморка", 46.3540, 30.7030, 0.0, 140.0, "private", 900.0)
	# --- the Soviet districts of the south-west
	district("Черёмушки", 46.4420, 30.7220, 0.0, 200.0, "khrush", 1500.0)
	district("Таирова", 46.3980, 30.7150, 10.0, 220.0, "panel", 1900.0)
	district("Юго-Западный массив", 46.4450, 30.6920, 0.0, 210.0, "panel", 1400.0)
	district("Ближние Мельницы", 46.4590, 30.7080, 0.0, 150.0, "private", 1000.0)
	district("Застава", 46.4620, 30.6760, 0.0, 220.0, "industrial", 1200.0)
	district("Ленпосёлок", 46.4800, 30.6620, 0.0, 140.0, "private", 1200.0)
	district("Лиманка", 46.3800, 30.6900, 0.0, 190.0, "new", 1000.0)
	district("Таирово", 46.3650, 30.6600, 0.0, 140.0, "private", 1000.0)
	# --- the north: Peresyp between the estuaries and the sea, the big estate beyond it
	district("Слободка", 46.4900, 30.7000, 10.0, 160.0, "khrush", 1100.0)
	district("Пересыпь", 46.5170, 30.7300, 10.0, 200.0, "industrial", 1200.0)
	district("Шкодова гора", 46.5150, 30.6950, 0.0, 220.0, "industrial", 1000.0)
	district("Лузановка", 46.5500, 30.7560, 30.0, 150.0, "private", 600.0)
	district("Посёлок Котовского", 46.5780, 30.7900, 25.0, 220.0, "panel", 2000.0)
	district("Крыжановка", 46.5700, 30.8150, 20.0, 180.0, "new", 800.0)
	district("Усатово", 46.5330, 30.6600, 0.0, 140.0, "private", 1200.0)
	district("Нерубайское", 46.5460, 30.6250, 0.0, 140.0, "private", 1000.0)


func _routes() -> void:
	add_road_ll("Николаевская дорога", [[46.4960, 30.7300], [46.5100, 30.7330], [46.5250, 30.7400], [46.5400, 30.7520], [46.5520, 30.7700],
		[46.5650, 30.8000], [46.5800, 30.8400], [46.5990, 30.8800]], 12.0)
	add_road_ll("Французский бульвар", [[46.4690, 30.7540], [46.4570, 30.7620], [46.4420, 30.7610], [46.4330, 30.7590]], 9.0)
	add_road_ll("Фонтанская дорога", [[46.4640, 30.7470], [46.4400, 30.7520], [46.4150, 30.7510], [46.3880, 30.7460], [46.3760, 30.7430]], 10.0)
	add_road_ll("Люстдорфская дорога", [[46.4560, 30.7260], [46.4200, 30.7150], [46.3850, 30.7110], [46.3530, 30.7100]], 11.0)
	add_road_ll("Киевское шоссе", [[46.4840, 30.7050], [46.4950, 30.6500], [46.5100, 30.6000], [46.5300, 30.5250]], 12.0)
	add_road_ll("Овидиопольская дорога", [[46.4480, 30.7060], [46.4200, 30.6700], [46.3900, 30.6200], [46.3600, 30.5600], [46.3420, 30.5250]], 11.0)
	add_road_ll("Объездная дорога", [[46.3900, 30.6200], [46.4500, 30.6150], [46.5000, 30.6330], [46.5400, 30.6650], [46.5450, 30.7000],
		[46.5520, 30.7400], [46.5520, 30.7700]], 11.0)
	add_rail_ll("Одесская железная дорога", [[46.4666, 30.7385], [46.4640, 30.7250], [46.4620, 30.7000], [46.4640, 30.6600], [46.4680, 30.6000],
		[46.4720, 30.5250]], 2, 9)
	add_rail_ll("ветка на Сортировочную", [[46.4620, 30.7000], [46.4850, 30.7020], [46.5100, 30.7120], [46.5350, 30.7120], [46.5600, 30.7050],
		[46.5990, 30.6800]], 1, 8)


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var sand := Color(1.0, 0.95, 0.7, 0.85)
	label_ll("ЧЁРНОЕ МОРЕ", 46.4400, 30.8300, 80, blue)
	label_ll("Одесский залив", 46.5200, 30.7900, 52, blue)
	label_ll("Куяльницкий лиман", 46.5850, 30.7200, 44, blue)
	label_ll("Хаджибейский лиман", 46.5800, 30.6450, 44, blue)
	label_ll("Ланжерон", 46.4760, 30.7720, 36, sand)
	label_ll("Аркадия", 46.4310, 30.7700, 40, sand)
	label_ll("Лузановка", 46.5460, 30.7700, 40, sand)


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	_port(map)
	_stairs(map)
	_centre(map)
	L.power_plant(map, ll3(46.5105, 30.7250), 10.0, "Одесская ТЭЦ", 1, 2, 120.0)
	L.power_plant(map, ll3(46.5660, 30.7720), 0.0, "ТЭЦ-2", 1, 2, 100.0)
	L.lattice_tower(map, ll3(46.4517, 30.7460), "Одесская телебашня", 199.0)
	L.station(map, ll3(46.4672, 30.7405), 0.0, "Главный вокзал", Color(0.94, 0.88, 0.72), 40.0)
	L.airport(map, ll3(46.4268, 30.6765), 110.0, "Аэропорт Одесса", 2800.0)
	L.stadium(map, ll3(46.4804, 30.7556), -16.0, "стадион «Черноморец»", 115.0, 95.0, 30.0)
	L.ferris_wheel(map, ll3(46.4772, 30.7590), 40.0, 21.0, "колесо обозрения в парке Шевченко")
	_refinery(map)
	# the "Seventh kilometre": a market town of shipping containers on the Ovidiopol road
	L.containers(map, ll(46.4040, 30.6400), 35.0, 300.0, 180.0, map.rng)
	L.target(map, ll3(46.4040, 30.6400, 6.0), "промрынок «7-й километр»", "plant")
	# the towers of Arkadia
	L.tower(map, ll(46.4352, 30.7590), Vector2(15, 15), 10.0, 106.0, 2, Color(0.3, 0.42, 0.55), "ЖК «Аркадийский дворец»")
	L.tower(map, ll(46.4338, 30.7575), Vector2(14, 14), 10.0, 96.0, 0, Color(0.92, 0.9, 0.86), "ЖК «Гагарин Плаза»")
	L.tower(map, ll(46.4322, 30.7592), Vector2(14, 13), 10.0, 88.0, 2, Color(0.28, 0.36, 0.44), "ЖК «Жемчужина»")
	L.tower(map, ll(46.4366, 30.7570), Vector2(13, 13), 10.0, 84.0, 2, Color(0.5, 0.56, 0.6), "ЖК «Кандинский»")
	L.tower(map, ll(46.4308, 30.7570), Vector2(13, 14), 10.0, 78.0, 0, Color(0.88, 0.84, 0.78), "ЖК «Море»")


## The port: the passenger pier with the hotel at its end, the grain and container moles, the
## breakwater with the Vorontsov lighthouse, ships at the quays and at anchor in the bay.
func _port(map) -> void:
	# the New mole: the Marine Station and the hotel "Odesa"
	var ma := ll(46.4900, 30.7444)
	var mb := ll(46.4938, 30.7492)
	L.pier(map, ma, mb, 90.0, "Новый мол")
	var md := (mb - ma).normalized()
	var mrot := rad_to_deg(atan2(-md.y, md.x))
	var mid := ma.lerp(mb, 0.45)
	var mv := L.group(Vector3(mid.x, 0, mid.y), mrot)
	L.block(map, mv, Vector3.ZERO, Vector2(75, 22), 16.0, 2, Color(0.8, 0.84, 0.86), "Морской вокзал")
	var hp := ma.lerp(mb, 0.86)
	L.tower(map, hp, Vector2(22, 17), -mrot, 75.0, 2, Color(0.28, 0.4, 0.5), "гостиница «Одесса»", Color(0.4, 0.8, 1.0))
	L.target(map, Vector3(mid.x, 8, mid.y), "Морской вокзал", "port")
	# the grain mole: silos and the working tower of the elevator
	var ga := ll(46.4938, 30.7412)
	var gb := ll(46.4972, 30.7456)
	L.pier(map, ga, gb, 70.0, "Военный мол")
	var gd := (gb - ga).normalized()
	var gg := L.group(Vector3((ga.x + gb.x) * 0.5, 0, (ga.y + gb.y) * 0.5), rad_to_deg(atan2(-gd.y, gd.x)))
	var conc := Fx.solid(Color(0.74, 0.73, 0.7), 0.85)
	for i in 9:
		for s in [-1.0, 1.0]:
			L.cyl(gg, 8.5, 8.5, 42.0, Vector3(-120.0 + i * 18.0, 21.0, s * 9.5), conc, 14)
	L.fp(map, gg, Vector3(-48, 0, 0), Vector2(82, 19), 42.0, "зерновой элеватор", IND)
	L.block(map, gg, Vector3(50, 0, 0), Vector2(9, 8), 64.0, 6, Color(0.7, 0.69, 0.66), "зерновой элеватор", IND)
	L.light(map, gg, Vector3(50, 65.5, 0))
	L.target(map, Vector3((ga.x + gb.x) * 0.5, 20, (ga.y + gb.y) * 0.5), "зерновой терминал", "port")
	# the Quarantine mole: the container terminal with its ship-to-shore cranes
	var qa := ll(46.4832, 30.7548)
	var qb := ll(46.4905, 30.7600)
	L.pier(map, qa, qb, 130.0, "Карантинный мол")
	var qd := (qb - qa).normalized()
	var qmid := qa.lerp(qb, 0.5)
	L.containers(map, qmid + Vector2(-qd.y, qd.x) * 22.0, rad_to_deg(atan2(qd.y, qd.x)), qa.distance_to(qb) * 0.8, 70.0, map.rng)
	var qg := L.group(Vector3(qmid.x, 0, qmid.y), rad_to_deg(atan2(-qd.y, qd.x)))
	for i in 4:
		_sts(map, qg, Vector3(-260.0 + i * 150.0, 2.0, -44.0))
	L.target(map, Vector3(qmid.x, 10, qmid.y), "контейнерный терминал", "port")
	# the breakwater and the lighthouse at its head
	var ba := ll(46.4912, 30.7606)
	var bb := ll(46.4975, 30.7583)
	L.pier(map, ba, bb, 12.0, "Рейдовый мол")
	L.lighthouse(map, Vector3(bb.x, 2.0, bb.y), "Воронцовский маяк", 27.0)
	# the oil harbour in the north
	var oa := ll(46.5052, 30.7358)
	var ob := ll(46.5078, 30.7440)
	L.pier(map, oa, ob, 16.0, "Нефтяной мол")
	L.tanks(map, ll3(46.5060, 30.7320), 20.0, 10, 14.0, "нефтегавань", true)
	# portal cranes along the quays between the moles
	var cg := L.group(Vector3.ZERO, 0.0)
	for spec in [[46.4925, 30.7424], [46.4917, 30.7431], [46.4887, 30.7463], [46.4879, 30.7473], [46.4868, 30.7487], [46.4858, 30.7502],
			[46.4985, 30.7381], [46.4996, 30.7374], [46.5010, 30.7368], [46.5025, 30.7362]]:
		var p := ll(float(spec[0]), float(spec[1]))
		_crane(map, cg, Vector3(coast_x(p.y) - 14.0, 0, p.y), -0.5)
	L.port(map, ll3(46.4878, 30.7462), 58.0, "Одесский морской порт", 0, "")
	# ships at the quays and on the roads
	L.ship(map, Vector3(qmid.x + qd.y * 92.0, 0, qmid.y - qd.x * 92.0), rad_to_deg(atan2(-qd.y, qd.x)), 260.0, "container", "контейнеровоз")
	var gs := ga.lerp(gb, 0.5) + Vector2(-gd.y, gd.x) * 52.0
	L.ship(map, Vector3(gs.x, 0, gs.y), rad_to_deg(atan2(-gd.y, gd.x)), 190.0, "bulk", "зерновоз")
	var ms := ma.lerp(mb, 0.5) - Vector2(-md.y, md.x) * 64.0
	L.ship(map, Vector3(ms.x, 0, ms.y), mrot, 150.0, "bulk", "сухогруз")
	for spec in [[46.5200, 30.7900, 60.0, "bulk", 180.0], [46.5050, 30.8100, 110.0, "container", 230.0], [46.4780, 30.8050, 35.0, "bulk", 170.0],
			[46.4550, 30.8200, 80.0, "container", 250.0], [46.4300, 30.8000, 20.0, "bulk", 200.0], [46.5350, 30.8300, 140.0, "bulk", 160.0]]:
		L.ship(map, ll3(float(spec[0]), float(spec[1])), float(spec[2]), float(spec[4]), String(spec[3]), "судно на рейде")


## A portal crane of the port: a gantry on four legs, the machinery house and a luffing jib.
func _crane(map, g: Node3D, c: Vector3, yaw: float, h := 26.0) -> void:
	var m := Fx.solid(Color(0.85, 0.55, 0.15), 0.6, 0.3)
	for sx in [-5.0, 5.0]:
		for sz in [-5.0, 5.0]:
			L.box(g, Vector3(1.2, h, 1.2), c + Vector3(sx, h * 0.5, sz), m)
	L.box(g, Vector3(12, 1.6, 12), c + Vector3(0, h, 0), m)
	L.box(g, Vector3(8, 6, 7), c + Vector3(0, h + 3.8, 0), Fx.solid(Color(0.8, 0.8, 0.78), 0.7))
	var out := Vector3(cos(yaw), 0, sin(yaw))
	var tip := c + out * 34.0 + Vector3(0, h + 27.0, 0)
	var back := c - out * 7.0 + Vector3(0, h + 17.0, 0)
	L.beam(g, c + Vector3(0, h + 6.0, 0), tip, 1.2, m)
	L.beam(g, c + Vector3(0, h + 6.0, 0), back, 0.9, m)
	L.beam(g, back, tip, 0.4, m)
	L.light(map, g, tip + Vector3(0, 1, 0))
	L.light(map, g, c + Vector3(0, h + 8.0, 0), Color(1.0, 0.85, 0.6), false, 1.6, 0.0024)
	L.fp(map, g, c, Vector2(6, 6), h + 7.0, "портовый кран", IND)


## A ship-to-shore container crane (local -z faces the water): the portal, the boom far out over
## the ship, the A-frame with its stays.
func _sts(map, g: Node3D, c: Vector3) -> void:
	var m := Fx.solid(Color(0.16, 0.36, 0.72), 0.6, 0.3)
	for sx in [-13.0, 13.0]:
		for sz in [-14.0, 14.0]:
			L.box(g, Vector3(1.8, 48, 1.8), c + Vector3(sx, 24, sz), m)
		L.box(g, Vector3(2.0, 2.0, 28), c + Vector3(sx, 47, 0), m)
		L.box(g, Vector3(2.0, 2.0, 28), c + Vector3(sx, 22, 0), m)
	for sz in [-14.0, 14.0]:
		L.box(g, Vector3(28, 2.0, 2.0), c + Vector3(0, 47, sz), m)
	L.box(g, Vector3(3.0, 2.4, 112), c + Vector3(0, 49.4, -24), m)
	L.box(g, Vector3(7, 5, 10), c + Vector3(0, 53, 9), Fx.solid(Color(0.85, 0.85, 0.84), 0.7))
	L.box(g, Vector3(1.6, 26, 1.6), c + Vector3(0, 63, -10), m)
	L.beam(g, c + Vector3(0, 76, -10), c + Vector3(0, 50.6, -78), 0.5, m)
	L.beam(g, c + Vector3(0, 76, -10), c + Vector3(0, 50.6, 30), 0.5, m)
	L.light(map, g, c + Vector3(0, 77, -10))
	L.light(map, g, c + Vector3(0, 51.5, -78))
	for sz in [-40.0, 0.0]:
		L.light(map, g, c + Vector3(0, 47.0, sz), Color(1.0, 0.9, 0.7), false, 2.2, 0.0026)
	L.fp(map, g, c, Vector2(14, 15), 50.0, "контейнерный кран", IND)


## Potemkin Stairs: ten flights from the port up to the Duke on the Primorsky boulevard (142 m
## long, wider at the foot than at the top).
func _stairs(map) -> void:
	var top := ll(46.4882, 30.7409)
	var foot := ll(46.4893, 30.7421)
	var d := (top - foot).normalized()
	var run := top.distance_to(foot)
	var g := L.group(Vector3(foot.x, 0, foot.y), rad_to_deg(atan2(-d.y, d.x)))
	var stone := L.lit(Color(0.78, 0.76, 0.7), 0.18)
	var rise := 20.0
	var fl := run / 10.0
	for i in 10:
		var x := (i + 0.5) * fl
		var w := lerpf(21.7, 12.5, i / 9.0)
		var h := rise * (i + 1) / 10.0
		L.box(g, Vector3(fl + 0.2, h, w), Vector3(x, h * 0.5, 0), stone)
		for s in [-1.0, 1.0]:
			L.box(g, Vector3(fl + 0.2, h + 1.1, 1.0), Vector3(x, (h + 1.1) * 0.5, s * (w * 0.5 + 0.5)), stone)
		L.fp(map, g, Vector3(x, 0, 0), Vector2(fl * 0.5, w * 0.5 + 1.0), h, "Потёмкинская лестница")
	# the landing on top and the Duke de Richelieu
	L.box(g, Vector3(34, rise, 64), Vector3(run + 17.0, rise * 0.5, 0), stone)
	L.fp(map, g, Vector3(run + 17.0, 0, 0), Vector2(17, 32), rise, "Приморский бульвар")
	L.box(g, Vector3(3.0, 4.6, 3.0), Vector3(run + 12.0, rise + 2.3, 0), Fx.solid(Color(0.45, 0.32, 0.3)))
	L.cyl(g, 0.7, 0.9, 4.2, Vector3(run + 12.0, rise + 6.7, 0), Fx.solid(Color(0.25, 0.35, 0.3), 0.4, 0.7), 8)
	for s in [-1.0, 1.0]:
		L.light(map, g, Vector3(run + 14.0, rise + 1.5, s * 20.0), Color(1.0, 0.85, 0.6), false, 1.6, 0.0022)
		L.light(map, g, Vector3(run * 0.5, rise * 0.5 + 2.0, s * 12.0), Color(1.0, 0.85, 0.6), false, 1.4, 0.0022)
	var c := foot + d * (run * 0.5 + 14.0)
	map.reserve(c.x, c.y, run * 0.5 + 34.0)
	L.target(map, Vector3(top.x, rise, top.y), "Потёмкинская лестница", "center")


func _centre(map) -> void:
	var green := Fx.solid(Color(0.3, 0.45, 0.42), 0.4, 0.6)
	# the Opera and Ballet Theatre: a baroque horseshoe with a dome
	var op := L.classical(map, ll3(46.4853, 30.7411), 16.0, "Оперный театр", Vector3(64, 25, 78), Color(0.93, 0.87, 0.72), green)
	for s in [-1.0, 1.0]:
		L.cyl(op, 9.0, 9.0, 23.0, Vector3(s * 32.0, 11.5, 18), L.lit(Color(0.93, 0.87, 0.72), 0.2), 16)
	L.target(map, ll3(46.4853, 30.7411, 10.0), "Оперный театр", "center")
	# Transfiguration Cathedral on Cathedral square (the bell tower is 77 m)
	L.cathedral(map, ll3(46.4832, 30.7312), 16.0, "Спасо-Преображенский собор", Color(0.95, 0.92, 0.84), L.gold(), 1.7, 4, true, "колокольня Спасо-Преображенского собора")
	L.cathedral(map, ll3(46.4727, 30.7350), 16.0, "Успенский собор", Color(0.86, 0.9, 0.94), Fx.solid(Color(0.16, 0.3, 0.55), 0.35, 0.6), 1.2, 4, true, "колокольня Успенского собора")
	# the Vorontsov palace with its colonnade over the port
	var vp := L.classical(map, ll3(46.4898, 30.7372), 16.0, "Воронцовский дворец", Vector3(56, 15, 24), Color(0.94, 0.92, 0.86))
	for i in 10:
		var a := deg_to_rad(-90.0 + i * 20.0)
		L.cyl(vp, 0.9, 1.0, 9.0, Vector3(50.0 + cos(a) * 9.0, 4.5, -20.0 + sin(a) * 9.0), L.lit(Color(0.95, 0.94, 0.9), 0.3), 8)
	# the City Hall at the end of the Primorsky boulevard, the Privoz market
	L.classical(map, ll3(46.4862, 30.7446), 16.0, "Одесская мэрия", Vector3(58, 19, 30), Color(0.92, 0.86, 0.72), green)
	L.target(map, ll3(46.4862, 30.7446, 10.0), "Одесская мэрия", "gov")
	var pvp := ll3(46.4690, 30.7330)
	var pv := L.group(pvp, 16.0)
	for i in 3:
		L.block(map, pv, Vector3(0, 0, -44.0 + i * 44.0), Vector2(60, 16), 11.0, 3, Color(0.7, 0.66, 0.6), "рынок «Привоз»", PUB, 4.0, Color(0.3, 0.4, 0.45))
	map.reserve(pvp.x, pvp.z, 96.0)
	# the obelisk to the Unknown Sailor above the sea in Shevchenko park
	var ob := ll3(46.4760, 30.7625)
	var og := L.group(ob, 0.0)
	L.cyl(og, 0.6, 1.6, 21.0, Vector3(0, 10.5, 0), L.lit(Color(0.62, 0.3, 0.26), 0.25), 4)
	L.fp(map, og, Vector3.ZERO, Vector2(2, 2), 21.0, "памятник Неизвестному матросу")
	map.reserve(ob.x, ob.z, 14.0)


## The refinery on Shkodova hill: the tank farm, distillation columns and the flare.
func _refinery(map) -> void:
	var rc := ll3(46.5120, 30.6980)
	L.tanks(map, rc, 0.0, 12, 16.0, "Одесский НПЗ", true)
	for i in 4:
		var p := rc + Vector3(150.0 + i * 26.0, 0, -60.0)
		var h := 58.0 - i * 7.0
		map.add_cyl(p, 3.4, h, Color(0.7, 0.7, 0.72))
		map.add_footprint(Vector2(p.x, p.z), Vector2(3.4, 3.4), 0.0, h, IND, "Одесский НПЗ")
		map.add_light(p + Vector3(0, h + 1.0, 0), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)
	var fl := rc + Vector3(290.0, 0, 30.0)
	map.add_cyl(fl, 1.4, 70.0, Color(0.6, 0.6, 0.62))
	map.add_footprint(Vector2(fl.x, fl.z), Vector2(1.5, 1.5), 0.0, 70.0, IND, "факел НПЗ")
	map.add_light(fl + Vector3(0, 73, 0), Color(1.0, 0.55, 0.15), true, 5.0, 0.003)
	map.reserve(rc.x + 200.0, rc.z - 20.0, 130.0)
