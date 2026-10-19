extends "res://scripts/world/city_def.gd"
## Kharkiv at its real size (26 × 26 km). The historic centre on the hill between the Lopan and the
## Kharkiv rivers, the Nemyshlia and the Udy, the Lisopark forest in the north; Derzhprom on
## Freedom Square, Saltivka's panel blocks in the north-east, the tractor plant in the east.
## Thirty kilometres from the border: the raids come from the north and the east, there is little
## water to drop the debris into.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")

const PUB := 2
const IND := 1


func _init() -> void:
	id = "kharkiv"
	name = "Харьков"
	version = 2
	seed = 5731
	noise_seed = 44
	noise2_seed = 91
	accent = Color(1.0, 0.72, 0.3)
	blurb = "В 30 км от границы: налёты идут с севера и востока, времени на перехват мало. Реки узкие — обломкам почти некуда падать. Госпром и площадь Свободы."
	half = 13000.0
	lat0 = 49.99
	lon0 = 36.25
	map_focus = ll3(50.0030, 36.2330)
	texts = {
		"defense": "Оборона Харькова",
		"title": "ХАРЬКОВ",
		"over": "Ночное дежурство над Харьковом",
		"duty": "%s РАДАР АКТИВЕН · ПВО ХАРЬКОВА НА ДЕЖУРСТВЕ",
		"raid": "НОЧЬ %d — МАССИРОВАННЫЙ НАЛЁТ НА ХАРЬКОВ!",
		"held": "Харьков выстоял. %d ночей обороны позади.",
		"water_into": "в реку",
		"water_safe": "в реку — без ущерба",
		"water_label": "РЕКА — безопасно",
		"shore": "Берег реки",
		"shore_desc": "Лопань, Харьков и Уды узкие: над водой падает немного обломков.\nОткрытый обзор вдоль русла: дальность ствольной ПВО +10%.",
		"rec": "REC ● 60 км/ч · ХАРЬКОВ",
	}
	video_channel = "@kharkiv_cuts"
	video_authors = ["@saltivka_night", "@kharkiv.live", "@derzhprom_view", "@olha_khtz", "@lopan_side",
		"@nightwatch_ua", "@taxi_2am", "@rooftop_kharkiv", "@pavlove_pole", "@sumska_cam"]
	# Belgorod is due north: most of the raids come in from the north and the north-east
	threat_sectors = [340.0, 0.0, 10.0, 20.0, 35.0, 50.0, 65.0, 80.0, 100.0]
	raid = {
		"drone": [["shahed", 0.55, 1], ["molniya", 0.3, 2], ["geran3", 0.15, 6], ["geran4", 0.12, 8], ["geran5", 0.12, 10]],
		"cruise": [["kab", 0.65, 2], ["cruise", 0.35, 5], ["banderol", 0.25, 4], ["kalibr", 0.15, 7]],
		"ballistic": [["s300", 0.6, 3], ["ballistic", 0.4, 5], ["s400", 0.35, 6], ["s500", 0.1, 12]],
	}
	# glide bombs every night, from the Su-34s over Belgorod
	raid_extra = [{"weapon": "kab", "from": 2, "count": [1, 3], "at": 0.2}, {"weapon": "kab", "from": 6, "count": [2, 3], "at": 0.7}]
	# the launchers stand across the border: the missiles fly for seconds, not minutes
	raid_start = {"cruise": 2, "ballistic": 3}
	raid_sectors = {
		"kab": [345.0, 0.0, 15.0, 30.0],
		"s300": [350.0, 0.0, 10.0, 25.0],
		"s400": [350.0, 0.0, 10.0, 25.0],
		"s500": [0.0, 20.0, 40.0],
		"kalibr": [150.0, 170.0, 190.0],
		"ballistic": [0.0, 15.0, 30.0, 60.0],
		"molniya": [0.0, 20.0, 40.0, 70.0],
		"banderol": [340.0, 0.0, 20.0, 45.0],
	}
	raid_note = "Харьков в 30 км от Белгорода: КАБ с УМПК сбрасывают из-за границы, С-300 и С-400 по земле и «Искандеры» долетают за секунды. Против КАБ стволы почти бесполезны — нужны ЗРК."
	city_center = ll(49.99, 36.26)
	city_radii = Vector2(10500, 10000)
	park_threshold = 0.5
	_geography()
	_districts()
	_routes()
	_labels()


func _geography() -> void:
	add_river_ll("Лопань", [[50.1150, 36.1600, 14], [50.0700, 36.1850, 15], [50.0400, 36.2000, 16], [50.0150, 36.2120, 17], [49.9950, 36.2220, 18],
		[49.9835, 36.2325, 20], [49.9700, 36.2250, 20], [49.9550, 36.2080, 20], [49.9330, 36.1950, 20], [49.9250, 36.1950, 20]], 22.0)
	add_river_ll("Харьков", [[50.0900, 36.3700, 14], [50.0550, 36.3200, 15], [50.0300, 36.2850, 16], [50.0120, 36.2680, 18], [49.9950, 36.2500, 18], [49.9840, 36.2340, 18]], 22.0)
	add_river_ll("Немышля", [[49.9950, 36.4300, 8], [49.9880, 36.3700, 8], [49.9830, 36.3200, 9], [49.9800, 36.2800, 9], [49.9830, 36.2520, 10], [49.9850, 36.2440, 10]], 18.0)
	add_river_ll("Уды", [[49.9550, 36.0500, 18], [49.9400, 36.1100, 19], [49.9260, 36.1900, 20], [49.9150, 36.2600, 20], [49.8950, 36.3300, 20], [49.8750, 36.4300, 20]], 24.0)
	# the Zhuravlivka reservoir on the Kharkiv river
	lake_ll(50.0125, 36.2690, 130.0, 420.0, 30.0)
	lake_ll(50.0560, 36.1880, 260.0, 130.0, 10.0)     # the Oleksiivka ponds
	lake_ll(49.9560, 36.2700, 300.0, 160.0, -20.0)    # Komsomolske lake
	lake_ll(50.0250, 36.3300, 220.0, 120.0, 0.0)      # a pond in Saltivka
	lake_ll(50.1050, 36.2200, 500.0, 220.0, 20.0)     # the Lozovenky reservoir
	forest_ll(50.0650, 36.2650, 3200.0, 2600.0, 0.0, 0.22)   # Lisopark
	forest_ll(50.0225, 36.2450, 520.0, 420.0, 0.0, 0.12)     # Gorky park
	forest_ll(50.0038, 36.2290, 180.0, 260.0, 0.0, 0.1)      # Shevchenko garden
	forest_ll(50.0250, 36.2200, 260.0, 620.0, 10.0, 0.15)    # Sarzhyn Yar
	forest_ll(50.0130, 36.2740, 520.0, 480.0, 0.0, 0.15)     # the Zhuravlivka hydropark
	forest_ll(49.9750, 36.1700, 950.0, 700.0, 0.0, 0.2)      # Hryhorivskyi wood
	forest_ll(49.9200, 36.1200, 2000.0, 1500.0, 0.0, 0.25)   # Zhykhor forest
	forest_ll(49.9300, 36.3450, 1500.0, 1100.0, 0.0, 0.25)   # Zelenyi Hai
	forest_ll(50.1000, 36.3000, 2600.0, 1500.0, 0.0, 0.3)    # the woods beyond Piatykhatky
	forest_ll(50.0400, 36.1300, 2000.0, 1700.0, 0.0, 0.3)    # the forest behind Oleksiivka


func _districts() -> void:
	district("Центр", 49.9930, 36.2320, 0.0, 150.0, "stalin", 950.0)
	district("Нагорный", 50.0080, 36.2400, 8.0, 150.0, "historic", 950.0)
	district("Павлово Поле", 50.0260, 36.2200, 5.0, 180.0, "panel", 1100.0)
	district("Алексеевка", 50.0550, 36.2050, -10.0, 210.0, "panel", 1700.0)
	district("Шатиловка", 50.0200, 36.2350, 20.0, 130.0, "private", 600.0)
	district("Журавлёвка", 50.0080, 36.2600, 30.0, 140.0, "mixed", 800.0)
	district("Салтовка", 50.0080, 36.3200, 15.0, 220.0, "panel", 2300.0)
	district("Северная Салтовка", 50.0350, 36.3500, 15.0, 230.0, "panel", 1900.0)
	district("Холодная Гора", 49.9850, 36.1900, -8.0, 160.0, "khrush", 1500.0)
	district("Новожаново", 49.9600, 36.2000, -12.0, 150.0, "private", 1300.0)
	district("Левада", 49.9750, 36.2420, 5.0, 180.0, "industrial", 800.0)
	district("Москалёвка", 49.9770, 36.2200, -10.0, 140.0, "khrush", 800.0)
	district("ХТЗ", 49.9500, 36.3800, 0.0, 200.0, "industrial", 1800.0)
	district("Новые Дома", 49.9620, 36.3200, 10.0, 180.0, "khrush", 1500.0)
	district("Одесская", 49.9520, 36.2600, 20.0, 170.0, "panel", 1200.0)
	district("Основа", 49.9400, 36.2250, -10.0, 140.0, "private", 1400.0)
	district("Лысая Гора", 50.0000, 36.1950, 0.0, 140.0, "private", 900.0)
	district("Рогань", 49.9300, 36.4100, 5.0, 220.0, "new", 1300.0)
	district("Жуковского", 50.0450, 36.2880, 10.0, 170.0, "new", 900.0)
	district("Большая Даниловка", 50.0500, 36.3050, 0.0, 140.0, "private", 1000.0)
	district("Пятихатки", 50.0950, 36.2650, 0.0, 180.0, "panel", 900.0)
	district("Залютино", 49.9900, 36.1500, 0.0, 140.0, "private", 1300.0)
	district("Песочин", 49.9620, 36.1050, 0.0, 140.0, "private", 1500.0)
	district("Немышля", 49.9800, 36.3100, 0.0, 140.0, "private", 1200.0)
	district("Сабурова дача", 49.9950, 36.2850, 5.0, 170.0, "mixed", 900.0)
	district("Плиточный", 49.9650, 36.2900, 0.0, 220.0, "industrial", 1100.0)


func _routes() -> void:
	add_road_ll("Сумская — проспект Науки", [[49.9930, 36.2320], [50.0050, 36.2350], [50.0250, 36.2330], [50.0500, 36.2250], [50.0800, 36.2500], [50.1150, 36.2700]], 12.0)
	add_road_ll("Московский проспект", [[49.9900, 36.2380], [49.9850, 36.2700], [49.9700, 36.3200], [49.9520, 36.3800], [49.9400, 36.4350]], 13.0,
		[{"name": "Московский мост", "style": "girder", "target": true}])
	add_road_ll("проспект Гагарина", [[49.9850, 36.2400], [49.9600, 36.2550], [49.9300, 36.2800], [49.8750, 36.3000]], 12.0,
		[{"name": "мост через Уды", "style": "girder"}])
	add_road_ll("Полтавский шлях", [[49.9900, 36.2250], [49.9870, 36.1900], [49.9800, 36.1500], [49.9750, 36.0650]], 12.0,
		[{"name": "мост через Лопань", "style": "girder", "target": true}])
	add_road_ll("проспект Героев Харькова", [[49.9950, 36.2650], [50.0050, 36.3000], [50.0150, 36.3400], [50.0300, 36.3900], [50.0400, 36.4350]], 13.0,
		[{"name": "Салтовский мост", "style": "cable_a", "target": true}])
	add_road_ll("Клочковская улица", [[49.9960, 36.2272], [50.0150, 36.2172], [50.0400, 36.2062], [50.0600, 36.2005], [50.0720, 36.1985]], 11.0)
	add_road_ll("Окружная дорога", [[50.0900, 36.2000], [50.1000, 36.3000], [50.0700, 36.4000], [50.0000, 36.4250], [49.9200, 36.4200], [49.8900, 36.3300],
		[49.9000, 36.2000], [49.9400, 36.1000], [50.0200, 36.1000], [50.0900, 36.2000]], 12.0,
		[{"name": "мост через Уды", "style": "girder"}])
	add_rail_ll("Южная железная дорога", [[49.9700, 36.0650], [49.9850, 36.1500], [49.9895, 36.2055], [49.9750, 36.2250], [49.9720, 36.2500],
		[49.9600, 36.3000], [49.9480, 36.3600], [49.9300, 36.4350]], 2, 8, {"name": "железнодорожный мост", "target": false})
	add_rail_ll("Белгородская линия", [[49.9895, 36.2055], [50.0200, 36.1900], [50.0600, 36.1700], [50.1150, 36.1500]], 1, 7)


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	label_ll("Лопань", 50.0500, 36.1950, 48, blue)
	label_ll("р. Харьков", 50.0450, 36.3050, 48, blue)
	label_ll("Немышля", 49.9860, 36.3500, 40, blue)
	label_ll("Уды", 49.9330, 36.1500, 48, blue)
	label_ll("Лесопарк", 50.0650, 36.2650, 60, green)
	label_ll("Парк Горького", 50.0225, 36.2450, 40, green)
	label_ll("Журавлёвский гидропарк", 50.0130, 36.2740, 38, green)
	label_ll("площадь Свободы", 50.0048, 36.2330, 40, Color(1.0, 0.9, 0.6, 0.85))


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	_freedom_square(map)
	_cathedrals(map)
	L.power_plant(map, ll3(49.9680, 36.2980), 5.0, "ТЭЦ-3", 1, 2, 150.0)
	L.power_plant(map, ll3(49.9700, 36.0850), -15.0, "ТЭЦ-5", 2, 2, 330.0)
	L.lattice_tower(map, ll3(50.0395, 36.2390), "Харьковская телебашня", 240.7)
	L.station(map, ll3(49.9895, 36.2055), -10.0, "Южный вокзал", Color(0.9, 0.84, 0.66), 42.0)
	L.airport(map, ll3(49.9248, 36.2900), 15.0, "Аэропорт Харьков", 2500.0)
	L.stadium(map, ll3(49.9808, 36.2617), 0.0, "стадион «Металлист»", 125.0, 100.0, 36.0)
	L.factory(map, ll3(49.9520, 36.3920), 0.0, "Харьковский тракторный завод", 5, 3, true)
	L.factory(map, ll3(49.9650, 36.2850), 20.0, "завод «Турбоатом»", 3, 2)
	L.factory(map, ll3(49.9760, 36.2720), -10.0, "завод им. Малышева", 3, 2, true)
	L.ferris_wheel(map, ll3(50.0225, 36.2440), 0.0, 27.0, "колесо обозрения в парке Горького")
	# the opera (a brutalist block) and the Mirror Stream fountain on Sumska
	L.classical(map, ll3(50.0000, 36.2360), 0.0, "Харьковский оперный театр", Vector3(120, 30, 90), Color(0.82, 0.8, 0.76), null, false)
	var mp := ll3(50.0018, 36.2350)
	var ms := L.group(mp, 0.0)
	L.cyl(ms, 9.0, 9.5, 0.8, Vector3(0, 0.4, 0), Fx.glow(Color(0.4, 0.8, 1.0), 0.8), 20)
	for i in 6:
		var a := TAU * i / 6.0
		L.cyl(ms, 0.4, 0.4, 6.0, Vector3(cos(a) * 3.6, 3.0, sin(a) * 3.6), L.lit(Color(0.95, 0.95, 0.9), 0.3), 6)
	L.sph(ms, 4.2, Vector3(0, 6.5, 0), L.lit(Color(0.95, 0.95, 0.9), 0.3), Vector3(1, 0.4, 1))
	L.fp(map, ms, Vector3.ZERO, Vector2(5, 5), 8.0, "«Зеркальная струя»")
	map.reserve(mp.x, mp.z, 22.0)
	# new towers of the centre
	L.tower(map, ll(49.9960, 36.2440), Vector2(18, 16), 0.0, 102.0, 2, Color(0.28, 0.36, 0.46), "ЖК «Павловский квартал»")
	L.tower(map, ll(49.9990, 36.2200), Vector2(16, 16), 8.0, 86.0, 0, Color(0.9, 0.86, 0.8), "бизнес-центр «Ривьера»")


## Derzhprom and Freedom Square: the constructivist giant, the university tower, the regional office.
func _freedom_square(map) -> void:
	var sq := ll3(50.0048, 36.2330)
	# the square itself stays open: 750 m long, a ring of lamps around it
	for k in 5:
		map.reserve(sq.x - 260.0 + k * 130.0, sq.z, 95.0)
	for i in 28:
		var a := TAU * i / 28.0
		map.add_light(sq + Vector3(cos(a) * 330.0, 10.0, sin(a) * 70.0), Color(1.0, 0.85, 0.6), false, 1.3, 0.0022)
	L.target(map, sq + Vector3(0, 2, 0), "площадь Свободы", "center")
	# Derzhprom: three stepped blocks on an arc, joined by sky bridges (63 m, 108 m with the mast)
	var dp := ll3(50.0068, 36.2272)
	var d := L.group(dp, 100.0)
	var grey := Color(0.78, 0.78, 0.76)
	var parts := [[Vector3(-105, 0, 16), Vector2(30, 24), 42.0], [Vector3(-105, 0, -22), Vector2(22, 20), 58.0],
		[Vector3(0, 0, -6), Vector2(38, 24), 48.0], [Vector3(0, 0, -36), Vector2(26, 16), 63.0],
		[Vector3(105, 0, 16), Vector2(30, 24), 42.0], [Vector3(105, 0, -22), Vector2(22, 20), 58.0]]
	for p in parts:
		L.block(map, d, p[0], p[1], p[2], 1, grey, "Госпром")
	var glass := L.lit(Color(0.6, 0.7, 0.75), 0.2)
	for s in [-1.0, 1.0]:
		L.box(d, Vector3(66, 7, 10), Vector3(s * 52.0, 30.0, 8.0), glass)
		L.box(d, Vector3(66, 6, 8), Vector3(s * 52.0, 44.0, -14.0), glass)
	L.beam(d, Vector3(0, 63, -36), Vector3(0, 108, -36), 0.8, Fx.solid(Color(0.4, 0.4, 0.42)))
	L.light(map, d, Vector3(0, 109, -36))
	map.reserve(dp.x, dp.z, 150.0)
	L.target(map, dp + Vector3(0, 20, 0), "Госпром", "gov")
	# Karazin University: the Stalinist tower on the north side of the square
	var up := ll3(50.0045, 36.2285)
	var u := L.group(up + Vector3(0, 0, -150), 0.0)
	L.block(map, u, Vector3.ZERO, Vector2(70, 18), 36.0, 1, Color(0.9, 0.86, 0.74), "Каразинский университет")
	L.block(map, u, Vector3(0, 0, -4), Vector2(20, 16), 66.0, 1, Color(0.9, 0.86, 0.74), "Каразинский университет")
	L.cyl(u, 0.0, 1.8, 16.0, Vector3(0, 74, -4), L.gold(), 8)
	L.light(map, u, Vector3(0, 83, -4))
	map.reserve(u.position.x, u.position.z, 78.0)
	# the regional administration at the east end
	var op := ll3(50.0043, 36.2385)
	var o := L.group(op, 90.0)
	L.block(map, o, Vector3.ZERO, Vector2(60, 16), 34.0, 1, Color(0.82, 0.8, 0.72), "Харьковская ОГА")
	map.reserve(op.x, op.z, 66.0)
	L.target(map, op + Vector3(0, 16, 0), "Харьковская ОГА", "gov")
	# hotel "Kharkiv" on the south side
	var hp := sq + Vector3(-60, 0, 150)
	L.block(map, L.group(hp, 0.0), Vector3.ZERO, Vector2(70, 14), 44.0, 1, Color(0.86, 0.82, 0.72), "гостиница «Харьков»")
	map.reserve(hp.x, hp.z, 76.0)


func _cathedrals(map) -> void:
	# Annunciation Cathedral: red-and-white stripes, the 80 m bell tower, on the bank of the Lopan
	var an := L.cathedral(map, ll3(49.9905, 36.2218), 0.0, "Благовещенский собор", Color(0.78, 0.3, 0.26), Fx.solid(Color(0.3, 0.4, 0.3), 0.35, 0.6), 1.7, 4, true, "колокольня Благовещенского собора")
	for i in 5:
		L.box(an, Vector3(51.6, 1.0, 38.0), Vector3(0, 4.0 + i * 4.6, 0), L.lit(Color(0.95, 0.94, 0.9), 0.2))
	# Dormition Cathedral with its white 89.5 m bell tower on University hill
	var dp := ll3(49.9895, 36.2300)
	var dm := L.group(dp, 0.0)
	var white := L.lit(Color(0.95, 0.94, 0.9), 0.2)
	L.box(dm, Vector3(26, 18, 26), Vector3(0, 9, 0), L.lit(Color(0.95, 0.88, 0.62), 0.18))
	L.domed_drum(dm, Vector3(0, 18, 0), 4.4, 5.0, white, L.gold())
	for spec in [[Vector3(14, 26, 14), 13.0], [Vector3(12, 20, 12), 36.0], [Vector3(10, 16, 10), 54.0], [Vector3(7, 12, 7), 68.0]]:
		L.box(dm, spec[0], Vector3(0, spec[1], 30), white)
	L.cyl(dm, 0.0, 3.4, 15.0, Vector3(0, 81.5, 30), L.gold(), 8)
	L.fp(map, dm, Vector3(0, 0, 12), Vector2(13, 26), 74.0, "Успенский собор")
	L.light(map, dm, Vector3(0, 90, 30))
	map.reserve(dp.x, dp.z + 12.0, 44.0)
