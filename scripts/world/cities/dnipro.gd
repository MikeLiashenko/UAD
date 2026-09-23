extends "res://scripts/world/city_def.gd"
## Dnipro: the widest reach of the Dnipro with Monastyrskyi island in the middle, the long
## embankment of the right bank, the Samara joining from the east; Yavornytskyi avenue and the
## Transfiguration Cathedral, the unfinished "Parus", the Menorah centre; the Pivdenmash and the
## steelworks in the west, the left-bank panel districts.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")

const PUB := 2
const IND := 1


func _init() -> void:
	id = "dnipro"
	name = "Днепр"
	version = 1
	seed = 9120
	noise_seed = 57
	noise2_seed = 13
	accent = Color(0.45, 1.0, 0.6)
	blurb = "Город на самом широком Днепре: длинная набережная, Монастырский остров, заводы Южмаш и ДМЗ. Много воды — есть куда ронять обломки."
	map_focus = Vector3(0, 0, 40)
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
		"drone": [["shahed", 0.7, 1], ["gerbera", 0.3, 2], ["geran3", 0.12, 8]],
		"cruise": [["cruise", 0.55, 3], ["kalibr", 0.45, 4]],
		"ballistic": [["ballistic", 0.7, 5], ["kh22", 0.3, 6]],
	}
	raid_sectors = {
		"ballistic": [80.0, 100.0, 120.0, 140.0],
		"kalibr": [150.0, 170.0, 190.0, 210.0],
		"kh22": [100.0, 130.0, 160.0],
	}
	raid_events = {10: {"weapon": "oreshnik", "count": 6, "aim": "завод «Южмаш»",
		"alert": "⚠ УГРОЗА: БАЛЛИСТИКА СРЕДНЕЙ ДАЛЬНОСТИ «ОРЕШНИК» ПО ЮЖМАШУ! Всем в укрытия"}}
	raid_note = "По Днепру летят «Искандеры» из-под Таганрога, Х-101, «Калибры» и Х-22. На десятую ночь ждите «Орешник» по Южмашу: шесть боевых блоков почти не перехватить."
	city_center = Vector2(0, 50)
	city_radii = Vector2(950, 800)
	_geography()
	_districts()
	_routes()
	_labels()


func _geography() -> void:
	add_river("Днепр", [[-1150, -120, 110], [-700, -200, 120], [-300, -230, 125], [100, -200, 130], [500, -110, 125], [850, 30, 120], [1150, 200, 115]])
	add_river("Самара", [[1150, -560, 26], [1000, -380, 30], [930, -200, 36], [900, -40, 42], [880, 60, 50]])
	# Monastyrskyi island right in front of the centre
	islands.append([60.0, -205.0, 85.0, 34.0, 5.0, GS.Zone.FOREST])
	# the little islands downstream
	islands.append([560.0, -95.0, 60.0, 20.0, 18.0, GS.Zone.FOREST])
	lakes.append([-100.0, -520.0, 35.0, 25.0, 0.0])
	lakes.append([200.0, -600.0, 30.0, 45.0, 20.0])
	lakes.append([-560.0, -380.0, 28.0, 18.0, -15.0])
	forests = [
		[110.0, 40.0, 55.0, 15.0],       # Shevchenko park
		[-150.0, 350.0, 60.0, 15.0],     # Globa park
		[-420.0, 570.0, 55.0, 15.0],     # botanical garden
		[950.0, -300.0, 160.0, 40.0],    # the Samara woods
		[-620.0, -800.0, 210.0, 60.0],
		[600.0, -860.0, 200.0, 60.0],
		[-900.0, 780.0, 160.0, 40.0],
	]


func _districts() -> void:
	districts = [
		# name, x, z, grid angle (deg), block size, character
		["Центр", 0.0, 120.0, -5.0, 56.0, "stalin"],
		["Нагорный", -150.0, 300.0, 0.0, 56.0, "historic"],
		["Набережная", 170.0, 30.0, -8.0, 52.0, "new"],
		["Мандрыковка", 520.0, 150.0, 12.0, 56.0, "new"],
		["Шевченковский", 270.0, 260.0, 0.0, 58.0, "mixed"],
		["Тополь", 480.0, 480.0, 10.0, 70.0, "panel"],
		["Сокол", 240.0, 690.0, 15.0, 64.0, "panel"],
		["Игрень", 850.0, 500.0, 0.0, 60.0, "private"],
		["Чечеловский", -450.0, 330.0, 5.0, 60.0, "industrial"],
		["Победа", -620.0, 60.0, -5.0, 64.0, "panel"],
		["Новокодацкий", -880.0, 200.0, -10.0, 60.0, "khrush"],
		["Кайдаки", -800.0, 520.0, 0.0, 64.0, "private"],
		["Левобережный", 100.0, -520.0, 10.0, 66.0, "panel"],
		["Амур", -300.0, -520.0, -10.0, 60.0, "khrush"],
		["Индустриальный", 480.0, -480.0, 0.0, 66.0, "industrial"],
		["Самарский", 780.0, -420.0, 0.0, 60.0, "private"],
		["Таромское", -760.0, -500.0, 0.0, 60.0, "private"],
	]


func _routes() -> void:
	add_road("Сичеславская набережная", [[-1000, -5], [-700, -55], [-300, -85], [100, -50], [500, 45], [850, 180], [1000, 260]], 8.0)
	add_road("проспект Яворницкого", [[-440, 180], [-200, 165], [0, 150], [110, 140]], 9.0)
	add_road("проспект Гагарина", [[120, 170], [300, 350], [520, 560], [700, 800], [800, 1000]], 8.0)
	add_road("Центральный мост", [[-60, 120], [-75, -60], [-85, -380], [-90, -700], [-100, -1000]], 9.0,
		[{"name": "Центральный мост", "style": "girder", "target": true}])
	add_road("Новый мост", [[270, 300], [290, 60], [300, -150], [305, -450], [320, -1000]], 9.0,
		[{"name": "Новый мост", "style": "cable_a", "target": true}])
	add_road("Кайдацкий мост", [[-780, 300], [-760, -40], [-745, -400], [-730, -1000]], 8.0,
		[{"name": "Кайдацкий мост", "style": "cable", "target": true}])
	add_road("Южный мост", [[620, 500], [640, 200], [655, -50], [670, -300], [690, -1000]], 8.0,
		[{"name": "Южный мост", "style": "girder", "target": true}])
	add_rail("Приднепровская железная дорога", [[-1000, 300], [-700, 262], [-470, 272], [-380, 266], [-335, 200], [-330, 60], [-340, -150],
		[-345, -420], [-320, -700], [-280, -1000]], 2, 8, {"name": "Амурский железнодорожный мост", "target": true})
	bridges.append({"a": Vector2(70, -45), "b": Vector2(70, -192), "name": "пешеходный мост на Монастырский остров", "style": "pedestrian"})


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	label("ДНЕПР", -520.0, -225.0, 72, blue)
	label("ДНЕПР", 700.0, -40.0, 72, blue)
	label("Самара", 960.0, -250.0, 48, blue)
	label("Монастырский остров", 60.0, -205.0, 40, Color(0.7, 1.0, 0.8, 0.8))
	label("парк Глобы", -150.0, 350.0, 36, green)


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	L.power_plant(map, Vector3(820, 0, 330), -10.0, "Приднепровская ТЭС", 2, 2)
	L.power_plant(map, Vector3(-560, 0, -580), 10.0, "Днепровская ТЭЦ")
	L.lattice_tower(map, Vector3(-250, 0, 470), "Днепровская телебашня", 110.0)
	L.station(map, Vector3(-470, 0, 220), 0.0, "Главный вокзал", Color(0.92, 0.86, 0.7), 36.0)
	L.airport(map, Vector3(380, 0, 800), -10.0, "Аэропорт Днепр")
	L.stadium(map, Vector3(-80, 0, 430), 0.0, "«Днепр-Арена»")
	L.port(map, Vector3(450, 0, -283), 0.0, "Речной порт", 4, "Речной вокзал")
	L.ship(map, Vector3(440, 0, -226), 0.0, 80.0, "bulk", "речной сухогруз")
	L.ship(map, Vector3(250, 0, -150), -8.0, 60.0, "barge", "баржа")
	L.factory(map, Vector3(-470, 0, 420), 0.0, "Днепровский металлургический завод", 5, 3, true)
	for i in 3:
		# blast furnaces of the steelworks
		var p := Vector3(-370, 0, 380 + i * 30)
		map.add_cyl(p, 6.0, 34.0, Color(0.4, 0.36, 0.34))
		map.add_cyl(p + Vector3(0, 34, 0), 2.0, 16.0, Color(0.5, 0.45, 0.42))
		map.add_footprint(Vector2(p.x, p.z), Vector2(6, 6), 0.0, 50.0, IND, "доменная печь")
		map.add_light(p + Vector3(0, 51, 0), Color(1.0, 0.08, 0.05), true, 1.2, 0.0045)
		map.add_light(p + Vector3(0, 8, 0), Color(1.0, 0.45, 0.15), false, 3.0, 0.003)
	map.reserve(-370, 410, 36.0)
	L.factory(map, Vector3(-700, 0, 640), 0.0, "завод «Южмаш»", 6, 2, true)
	_rocket(map, Vector3(-610, 0, 555))
	_cathedral(map)
	_parus(map)
	_towers(map)
	# the church on Monastyrskyi island
	L.small_church(map, Vector3(60, 0, -205), 0.0, map.rng)
	map.reserve(60, -205, 20.0)
	L.target(map, Vector3(0, 10, 150), "Центр (проспект Яворницкого)", "center")
	var oda := L.group(Vector3(-230, 0, 130), 0.0)
	L.block(map, oda, Vector3.ZERO, Vector2(28, 12), 30.0, 1, Color(0.84, 0.8, 0.7), "Днепропетровская ОГА")
	map.reserve(-230, 130, 30.0)
	L.target(map, Vector3(-230, 15, 130), "Днепропетровская ОГА", "gov")


## The Pivdenmash rocket in front of the plant.
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
	map.reserve(p.x, p.z, 12.0)


## Transfiguration Cathedral on Cathedral square: yellow classical, a big dome and a bell tower.
func _cathedral(map) -> void:
	var g := L.group(Vector3(170, 0, 130), 0.0)
	var yellow := L.lit(Color(0.96, 0.86, 0.55), 0.2)
	var dome := Fx.solid(Color(0.2, 0.42, 0.32), 0.35, 0.6)
	L.box(g, Vector3(30, 18, 30), Vector3(0, 9, 0), yellow)
	L.box(g, Vector3(40, 14, 14), Vector3(0, 7, 0), yellow)
	L.box(g, Vector3(14, 14, 40), Vector3(0, 7, 0), yellow)
	L.cyl(g, 8.0, 8.0, 8.0, Vector3(0, 22, 0), yellow, 20)
	L.sph(g, 8.4, Vector3(0, 26, 0), dome, Vector3(1, 0.9, 1))
	L.cyl(g, 0.0, 1.2, 8.0, Vector3(0, 37, 0), L.gold(), 8)
	L.box(g, Vector3(9, 30, 9), Vector3(0, 15, 26), yellow)
	L.sph(g, 4.0, Vector3(0, 31, 26), dome, Vector3(1, 1.3, 1))
	L.fp(map, g, Vector3.ZERO, Vector2(20, 20), 34.0, "Преображенский собор")
	L.fp(map, g, Vector3(0, 0, 26), Vector2(5, 5), 36.0, "колокольня Преображенского собора")
	L.light(map, g, Vector3(0, 42, 0))
	map.reserve(170, 140, 34.0)


## "Parus": the unfinished sail-shaped hotel on the embankment (dark, no windows lit).
func _parus(map) -> void:
	var g := L.group(Vector3(0, 0, -8), -8.0)
	for i in 7:
		var a := deg_to_rad(-45.0 + i * 15.0)
		var p := Vector3(sin(a) * 26.0, 0, -cos(a) * 26.0 + 26.0)
		var h := 96.0 - absf(i - 3.0) * 12.0
		L.block(map, g, p, Vector2(5.2, 6), h, 6, Color(0.46, 0.46, 0.48), "гостиница «Парус»")
	for s in [-1.0, 1.0]:
		L.light(map, g, Vector3(s * 4.0, 97.0, 0), Color(1.0, 0.08, 0.05))
	map.reserve(0, -8, 36.0)


func _towers(map) -> void:
	# the twin "Towers" on the embankment
	L.tower(map, Vector2(200, 20), Vector2(11, 11), -8.0, 123.0, 2, Color(0.3, 0.4, 0.52), "БЦ «Башня-1»", Color(0.4, 0.8, 1.0))
	L.tower(map, Vector2(228, 34), Vector2(11, 11), -8.0, 108.0, 2, Color(0.3, 0.4, 0.52), "БЦ «Башня-2»", Color(0.4, 0.8, 1.0))
	# the Menorah centre: seven towers in an arc, the middle one the tallest
	for i in 7:
		var a := deg_to_rad(-60.0 + i * 20.0)
		var c := Vector2(40.0 + sin(a) * 30.0, 310.0 - cos(a) * 18.0)
		var h := 77.0 - absf(i - 3.0) * 11.0
		map.add_building(c, Vector2(6, 6), 0.0, h, 2, Color(0.82, 0.78, 0.66), PUB, 0.0, Color(), "центр «Менора»")
		map.add_light(Vector3(c.x, h + 0.6, c.y), Color(0.5, 0.8, 1.0), false, 2.2, 0.003)
	map.reserve(40, 300, 42.0)
