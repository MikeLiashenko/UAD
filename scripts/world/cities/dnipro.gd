extends "res://scripts/world/city_def.gd"
## Dnipro at its real size (30 × 30 km). The widest reach of the Dnipro — more than a kilometre
## across in the centre, three below the Southern bridge — with Monastyrskyi island in the middle,
## the long embankment of the right bank, the Samara joining from the north-east; Yavornytskyi
## avenue and the Transfiguration Cathedral, the unfinished "Parus", the Menorah centre; Pivdenmash
## and the steelworks in the west, the left-bank panel districts.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")

const PUB := 2
const IND := 1


func _init() -> void:
	id = "dnipro"
	name = "Днепр"
	version = 2
	seed = 9120
	noise_seed = 57
	noise2_seed = 13
	accent = Color(0.45, 1.0, 0.6)
	blurb = "Город на самом широком Днепре: длинная набережная, Монастырский остров, заводы Южмаш и ДМЗ. Много воды — есть куда ронять обломки."
	half = 15000.0
	lat0 = 48.46
	lon0 = 35.03
	map_focus = ll3(48.4650, 35.0500)
	texts = {
		"defense": "Оборона Днепра",
		"title": "ДНЕПР",
		"over": "Ночное дежурство над Днепром",
		"duty": "%s РАДАР АКТИВЕН · ПВО ДНЕПРА НА ДЕЖУРСТВЕ",
		"raid": "НОЧЬ %d — МАССИРОВАННЫЙ НАЛЁТ НА ДНЕПР!",
		"held": "Днепр выстоял. %d ночей обороны позади.",
		"water_into": "в Днепр",
		"water_safe": "в Днепр — без ущерба",
		"water_label": "ДНЕПР — безопасно",
		"shore": "Берег Днепра",
		"shore_desc": "Самое широкое место Днепра: обломки, сбитые над рекой, падают в воду.\nОткрытый обзор над рекой: дальность ствольной ПВО +10%.",
		"rec": "REC ● 60 км/ч · ДНЕПР",
	}
	video_channel = "@dnipro_cuts"
	video_authors = ["@naberezhna_live", "@dnipro.night", "@pobeda_cam", "@menorah_view", "@lb_dnipro",
		"@nightwatch_ua", "@taxi_2am", "@rooftop_dnipro", "@topol_balcony", "@yavornytskoho"]
	threat_sectors = [0.0, 30.0, 60.0, 90.0, 110.0, 130.0, 150.0, 180.0]
	raid = {
		"drone": [["shahed", 0.7, 1], ["gerbera", 0.3, 2], ["geran3", 0.12, 8], ["geran4", 0.1, 10], ["geran5", 0.1, 12]],
		"cruise": [["cruise", 0.55, 3], ["kalibr", 0.45, 4]],
		"ballistic": [["ballistic", 0.6, 5], ["kh22", 0.3, 6], ["s400", 0.25, 7], ["zircon", 0.12, 11], ["s500", 0.1, 13]],
	}
	raid_sectors = {
		"ballistic": [80.0, 100.0, 120.0, 140.0],
		"s400": [120.0, 140.0, 160.0],
		"s500": [90.0, 110.0, 130.0],
		"zircon": [170.0, 190.0, 210.0],
		"kalibr": [150.0, 170.0, 190.0, 210.0],
		"kh22": [100.0, 130.0, 160.0],
	}
	raid_events = {10: {"weapon": "oreshnik", "count": 6, "aim": "завод «Южмаш»",
		"alert": "⚠ УГРОЗА: БАЛЛИСТИКА СРЕДНЕЙ ДАЛЬНОСТИ «ОРЕШНИК» ПО ЮЖМАШУ! Всем в укрытия"}}
	raid_note = "По Днепру летят «Искандеры» из-под Таганрога, Х-101, «Калибры», Х-22 и С-400 по земле. На десятую ночь ждите «Орешник» по Южмашу: шесть боевых блоков почти не перехватить."
	city_center = ll(48.46, 35.03)
	city_radii = Vector2(13000, 10500)
	_geography()
	_districts()
	_routes()
	_labels()


func _geography() -> void:
	add_river_ll("Днепр", [[48.5400, 34.8100, 700], [48.5150, 34.9000, 650], [48.4950, 34.9550, 600], [48.4830, 35.0000, 540], [48.4790, 35.0380, 500],
		[48.4750, 35.0650, 540], [48.4630, 35.0900, 650], [48.4450, 35.1100, 800], [48.4200, 35.1250, 950], [48.3900, 35.1300, 1100],
		[48.3500, 35.1400, 1300], [48.3150, 35.1500, 1500]])
	add_river_ll("Самара", [[48.5600, 35.2300, 250], [48.5200, 35.2050, 300], [48.4900, 35.1750, 400], [48.4680, 35.1480, 480], [48.4500, 35.1280, 500], [48.4400, 35.1130, 500]])
	# Monastyrskyi island right in front of the centre, the little islands downstream
	island_ll(48.4668, 35.0765, 420.0, 150.0, 22.0, Z_FOREST)
	island_ll(48.4350, 35.1220, 260.0, 600.0, 10.0, Z_FOREST)
	lake_ll(48.5150, 35.0400, 420.0, 180.0, 20.0)
	lake_ll(48.5250, 35.1000, 300.0, 500.0, 20.0)
	lake_ll(48.4950, 34.9000, 260.0, 160.0, -15.0)
	forest_ll(48.4600, 35.0710, 420.0, 300.0, 0.0, 0.12)     # Shevchenko park
	forest_ll(48.4720, 35.0300, 260.0, 220.0, 0.0, 0.1)      # Globa park
	forest_ll(48.4350, 35.0420, 600.0, 520.0, 0.0, 0.15)     # the botanical garden and the gullies
	forest_ll(48.4420, 35.0700, 500.0, 900.0, 20.0, 0.2)     # Tunelna gully
	forest_ll(48.4900, 35.2000, 2400.0, 2000.0, 0.0, 0.25)   # the Samara woods
	forest_ll(48.5550, 34.9500, 3000.0, 1800.0, 0.0, 0.3)
	forest_ll(48.5500, 35.1300, 2600.0, 1600.0, 0.0, 0.3)
	forest_ll(48.3700, 34.9300, 2400.0, 1800.0, 0.0, 0.3)
	forest_ll(48.3800, 35.2200, 2200.0, 2400.0, 0.0, 0.3)


func _districts() -> void:
	# --- the right bank
	district("Центр", 48.4640, 35.0450, -5.0, 150.0, "stalin", 1000.0)
	district("Нагорный", 48.4540, 35.0580, 0.0, 150.0, "historic", 950.0)
	district("Победа", 48.4280, 35.0650, 12.0, 210.0, "panel", 1500.0)
	district("Сокол", 48.4050, 35.0350, 15.0, 200.0, "panel", 1300.0)
	district("Тополь", 48.4120, 35.0050, 10.0, 210.0, "panel", 1400.0)
	district("Двенадцатый квартал", 48.4350, 35.0200, 0.0, 170.0, "khrush", 1100.0)
	district("Чечеловский", 48.4560, 35.0080, 5.0, 170.0, "mixed", 1200.0)
	district("Новокодацкий", 48.4780, 34.9650, -10.0, 170.0, "khrush", 1600.0)
	district("Красный Камень", 48.4880, 34.9150, 0.0, 210.0, "panel", 1400.0)
	district("Кайдаки", 48.4850, 34.9400, 0.0, 140.0, "private", 900.0)
	district("Диёвка", 48.4980, 34.8950, 0.0, 140.0, "private", 1500.0)
	district("Таромское", 48.5050, 34.8450, 0.0, 140.0, "private", 1000.0)
	district("Западный", 48.4650, 34.9200, -5.0, 220.0, "industrial", 1400.0)
	district("Южмаш", 48.4400, 34.9850, 0.0, 240.0, "industrial", 1500.0)
	district("Краснополье", 48.4350, 34.9400, 0.0, 140.0, "private", 1400.0)
	district("Лоцманская Каменка", 48.4230, 35.0900, 10.0, 140.0, "private", 900.0)
	district("Аэропорт", 48.3700, 35.0700, 0.0, 140.0, "private", 1300.0)
	# --- the left bank
	district("Амур", 48.4980, 35.0300, -10.0, 170.0, "khrush", 1500.0)
	district("Левобережный", 48.4950, 35.0850, 10.0, 210.0, "panel", 1600.0)
	district("Солнечный", 48.5150, 35.0650, 0.0, 200.0, "panel", 1300.0)
	district("Клочко", 48.5150, 35.0100, 0.0, 170.0, "khrush", 1100.0)
	district("Индустриальный", 48.5050, 35.1200, 0.0, 230.0, "industrial", 1500.0)
	district("Игрень", 48.4650, 35.1950, 0.0, 140.0, "private", 1400.0)
	district("Самарский", 48.4050, 35.1650, 0.0, 180.0, "mixed", 1400.0)
	district("Подгородное", 48.5450, 35.0900, 0.0, 140.0, "private", 1500.0)


func _routes() -> void:
	add_road_ll("Сичеславская набережная", [[48.4900, 34.9300], [48.4770, 34.9900], [48.4725, 35.0300], [48.4690, 35.0550], [48.4590, 35.0800],
		[48.4400, 35.0960], [48.4200, 35.1030]], 12.0)
	add_road_ll("проспект Яворницкого", [[48.4750, 35.0150], [48.4650, 35.0420], [48.4570, 35.0650]], 13.0)
	add_road_ll("проспект Гагарина", [[48.4560, 35.0640], [48.4350, 35.0500], [48.4100, 35.0350], [48.3700, 35.0300], [48.3200, 35.0300]], 12.0)
	add_road_ll("Центральный мост", [[48.4690, 35.0330], [48.4790, 35.0380], [48.4890, 35.0420], [48.5100, 35.0480], [48.5500, 35.0550]], 13.0,
		[{"name": "Центральный мост", "style": "girder", "target": true}])
	add_road_ll("Новый мост", [[48.4640, 35.0600], [48.4750, 35.0650], [48.4860, 35.0700], [48.5000, 35.0760], [48.5300, 35.0900]], 13.0,
		[{"name": "Новый мост", "style": "cable_a", "target": true}])
	add_road_ll("Кайдацкий мост", [[48.4650, 34.9450], [48.4800, 34.9500], [48.4950, 34.9550], [48.5100, 34.9620], [48.5500, 34.9700]], 12.0,
		[{"name": "Кайдацкий мост", "style": "cable", "target": true}])
	add_road_ll("Южный мост", [[48.4300, 35.0750], [48.4240, 35.0950], [48.4180, 35.1250], [48.4130, 35.1550], [48.4050, 35.2300]], 12.0,
		[{"name": "Южный мост", "style": "girder", "target": true}])
	add_road_ll("Донецкое шоссе", [[48.5000, 35.0760], [48.5020, 35.1200], [48.4900, 35.1800], [48.4800, 35.2300]], 12.0,
		[{"name": "мост через Самару", "style": "girder"}])
	add_road_ll("проспект Нигояна", [[48.4750, 35.0150], [48.4800, 34.9600], [48.4950, 34.9000], [48.5100, 34.8250]], 12.0)
	add_rail_ll("Приднепровская железная дорога", [[48.5150, 34.8250], [48.4880, 34.9500], [48.4772, 35.0140], [48.4680, 35.0500], [48.4590, 35.0850],
		[48.4700, 35.1050], [48.4800, 35.1700], [48.4850, 35.2300]], 2, 8, {"name": "Мерефо-Херсонский мост", "target": true})
	bridges.append({"a": ll(48.4625, 35.0738), "b": ll(48.4662, 35.0762), "name": "пешеходный мост на Монастырский остров", "style": "pedestrian"})


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	label_ll("ДНЕПР", 48.5000, 34.9400, 72, blue)
	label_ll("ДНЕПР", 48.3900, 35.1300, 72, blue)
	label_ll("Самара", 48.5000, 35.1850, 48, blue)
	label_ll("Монастырский остров", 48.4668, 35.0765, 40, Color(0.7, 1.0, 0.8, 0.8))
	label_ll("парк Глобы", 48.4720, 35.0300, 36, green)


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	L.power_plant(map, ll3(48.4047, 35.1380), -10.0, "Приднепровская ТЭС", 2, 3, 250.0)
	L.power_plant(map, ll3(48.5080, 35.1250), 10.0, "Днепровская ТЭЦ", 1, 2, 150.0)
	L.lattice_tower(map, ll3(48.4380, 35.0420), "Днепровская телебашня", 180.0)
	L.station(map, ll3(48.4772, 35.0140), 15.0, "Главный вокзал", Color(0.92, 0.86, 0.7), 38.0)
	L.airport(map, ll3(48.3570, 35.1000), 190.0, "Аэропорт Днепр", 2850.0)
	L.stadium(map, ll3(48.4603, 35.0325), 0.0, "«Днепр-Арена»", 120.0, 95.0, 34.0)
	var pp := ll3(48.4735, 35.0260)
	L.port(map, pp, 190.0, "Речной порт", 4, "Речной вокзал")
	L.ship(map, ll3(48.4770, 35.0270), 12.0, 96.0, "bulk", "речной сухогруз")
	L.ship(map, ll3(48.4735, 35.0520), -8.0, 80.0, "barge", "баржа")
	var dz := ll3(48.4800, 34.9900)
	L.factory(map, dz, 10.0, "Днепровский металлургический завод", 5, 3, true)
	for i in 3:
		# blast furnaces of the steelworks
		var p := dz + Vector3(200, 0, -90 + i * 70)
		map.add_cyl(p, 9.0, 46.0, Color(0.4, 0.36, 0.34))
		map.add_cyl(p + Vector3(0, 46, 0), 3.0, 22.0, Color(0.5, 0.45, 0.42))
		map.add_footprint(Vector2(p.x, p.z), Vector2(9, 9), 0.0, 68.0, IND, "доменная печь")
		map.add_light(p + Vector3(0, 69, 0), Color(1.0, 0.08, 0.05), true, 1.4, 0.005)
		map.add_light(p + Vector3(0, 10, 0), Color(1.0, 0.45, 0.15), false, 3.4, 0.003)
	map.reserve(dz.x + 200.0, dz.z, 130.0)
	var ym := ll3(48.4420, 34.9900)
	L.factory(map, ym, 0.0, "завод «Южмаш»", 6, 2, true)
	_rocket(map, ll3(48.4612, 35.0385))
	_cathedral(map)
	_parus(map)
	_towers(map)
	# the church on Monastyrskyi island
	var mi := ll3(48.4668, 35.0765)
	L.small_church(map, mi, 0.4, map.rng)
	map.reserve(mi.x, mi.z, 28.0)
	L.target(map, ll3(48.4650, 35.0450, 10.0), "Центр (проспект Яворницкого)", "center")
	var op := ll3(48.4620, 35.0400)
	var oda := L.group(op, -20.0)
	L.block(map, oda, Vector3.ZERO, Vector2(60, 16), 32.0, 1, Color(0.84, 0.8, 0.7), "Днепропетровская ОГА")
	map.reserve(op.x, op.z, 66.0)
	L.target(map, op + Vector3(0, 15, 0), "Днепропетровская ОГА", "gov")


## The rocket in the park beside the regional office.
func _rocket(map, p: Vector3) -> void:
	var g := L.group(p, 0.0)
	var white := L.lit(Color(0.94, 0.94, 0.92), 0.3)
	L.box(g, Vector3(10, 3, 10), Vector3(0, 1.5, 0), Fx.solid(Color(0.4, 0.4, 0.42)))
	L.cyl(g, 1.8, 1.8, 30.0, Vector3(0, 18, 0), white, 12)
	L.cyl(g, 0.0, 1.8, 6.0, Vector3(0, 36, 0), white, 12)
	for i in 4:
		var a := TAU * i / 4.0
		L.box(g, Vector3(0.3, 5.0, 2.6), Vector3(cos(a) * 2.2, 5.5, sin(a) * 2.2), Fx.solid(Color(0.3, 0.3, 0.35)))
	L.fp(map, g, Vector3.ZERO, Vector2(5, 5), 39.0, "ракета у Южмаша")
	L.light(map, g, Vector3(0, 40, 0))
	map.reserve(p.x, p.z, 16.0)


## Transfiguration Cathedral on Cathedral square: yellow classical, a big dome and a bell tower.
func _cathedral(map) -> void:
	var p := ll3(48.4590, 35.0660)
	var g := L.group(p, 0.0)
	var yellow := L.lit(Color(0.96, 0.86, 0.55), 0.2)
	var dome := Fx.solid(Color(0.2, 0.42, 0.32), 0.35, 0.6)
	L.box(g, Vector3(34, 20, 34), Vector3(0, 10, 0), yellow)
	L.box(g, Vector3(46, 15, 16), Vector3(0, 7.5, 0), yellow)
	L.box(g, Vector3(16, 15, 46), Vector3(0, 7.5, 0), yellow)
	L.cyl(g, 9.0, 9.0, 9.0, Vector3(0, 24.5, 0), yellow, 20)
	L.sph(g, 9.4, Vector3(0, 29, 0), dome, Vector3(1, 0.9, 1))
	L.cyl(g, 0.0, 1.3, 9.0, Vector3(0, 41, 0), L.gold(), 8)
	L.box(g, Vector3(10, 34, 10), Vector3(0, 17, 30), yellow)
	L.sph(g, 4.6, Vector3(0, 35, 30), dome, Vector3(1, 1.3, 1))
	L.fp(map, g, Vector3.ZERO, Vector2(23, 23), 38.0, "Преображенский собор")
	L.fp(map, g, Vector3(0, 0, 30), Vector2(5, 5), 40.0, "колокольня Преображенского собора")
	L.light(map, g, Vector3(0, 46, 0))
	map.reserve(p.x, p.z + 12.0, 46.0)


## "Parus": the unfinished 28-floor sail-shaped hotel on the embankment (dark, no windows lit).
func _parus(map) -> void:
	var p := ll3(48.4705, 35.0410)
	var g := L.group(p, -8.0)
	for i in 7:
		var a := deg_to_rad(-45.0 + i * 15.0)
		var q := Vector3(sin(a) * 46.0, 0, -cos(a) * 46.0 + 46.0)
		var h := 100.0 - absf(i - 3.0) * 12.0
		L.block(map, g, q, Vector2(9.0, 10), h, 6, Color(0.46, 0.46, 0.48), "гостиница «Парус»")
	for s in [-1.0, 1.0]:
		L.light(map, g, Vector3(s * 6.0, 101.0, 0), Color(1.0, 0.08, 0.05))
	map.reserve(p.x, p.z, 64.0)


func _towers(map) -> void:
	# the twin "Towers" above the embankment
	L.tower(map, ll(48.4648, 35.0570), Vector2(15, 15), -8.0, 123.0, 2, Color(0.3, 0.4, 0.52), "БЦ «Башня-1»", Color(0.4, 0.8, 1.0))
	L.tower(map, ll(48.4652, 35.0582), Vector2(15, 15), -8.0, 106.0, 2, Color(0.3, 0.4, 0.52), "БЦ «Башня-2»", Color(0.4, 0.8, 1.0))
	# the Menorah centre: seven towers in an arc, the middle one the tallest (77 m)
	var mc := ll(48.4635, 35.0535)
	for i in 7:
		var a := deg_to_rad(-60.0 + i * 20.0)
		var c := mc + Vector2(sin(a) * 52.0, -cos(a) * 30.0)
		var h := 77.0 - absf(i - 3.0) * 11.0
		map.add_building(c, Vector2(10, 10), 0.0, h, 2, Color(0.82, 0.78, 0.66), PUB, 0.0, Color(), "центр «Менора»")
		map.add_light(Vector3(c.x, h + 0.6, c.y), Color(0.5, 0.8, 1.0), false, 2.2, 0.003)
	map.reserve(mc.x, mc.y - 10.0, 76.0)
