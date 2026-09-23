extends "res://scripts/world/city_def.gd"
## Kharkiv: the historic centre on the hill between the Lopan and the Kharkiv rivers, the
## Nemyshlia and the Udy, the Lisopark forest in the north; Derzhprom on Freedom Square,
## Saltivka's panel blocks in the north-east, the tractor plant in the east. Thirty kilometres
## from the border: the raids come from the north and the east, there is little water to drop
## the debris into.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")

const PUB := 2
const IND := 1


func _init() -> void:
	id = "kharkiv"
	name = "Харьков"
	version = 1
	seed = 5731
	noise_seed = 44
	noise2_seed = 91
	accent = Color(1.0, 0.72, 0.3)
	blurb = "В 30 км от границы: налёты идут с севера и востока, времени на перехват мало. Реки узкие — обломкам почти некуда падать. Госпром и площадь Свободы."
	map_focus = Vector3(-60, 0, -120)
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
		"drone": [["shahed", 0.55, 1], ["molniya", 0.3, 2], ["geran3", 0.15, 6]],
		"cruise": [["kab", 0.65, 2], ["cruise", 0.35, 5]],
		"ballistic": [["s300", 0.6, 3], ["ballistic", 0.4, 5]],
	}
	# glide bombs every night, from the Su-34s over Belgorod
	raid_extra = [{"weapon": "kab", "from": 2, "count": [1, 3], "at": 0.2}, {"weapon": "kab", "from": 6, "count": [2, 3], "at": 0.7}]
	# the launchers stand across the border: the missiles fly for seconds, not minutes
	raid_start = {"cruise": 2, "ballistic": 3}
	raid_sectors = {
		"kab": [345.0, 0.0, 15.0, 30.0],
		"s300": [350.0, 0.0, 10.0, 25.0],
		"ballistic": [0.0, 15.0, 30.0, 60.0],
		"molniya": [0.0, 20.0, 40.0, 70.0],
	}
	raid_note = "Харьков в 30 км от Белгорода: КАБ с УМПК сбрасывают из-за границы, С-300 по земле и «Искандеры» долетают за секунды. Против КАБ стволы почти бесполезны — нужны ЗРК."
	city_center = Vector2(0, -60)
	city_radii = Vector2(850, 850)
	park_threshold = 0.5
	_geography()
	_districts()
	_routes()
	_labels()


func _geography() -> void:
	add_river("Лопань", [[-380, -1150, 11], [-300, -800, 12], [-200, -450, 13], [-110, -160, 14], [-70, 60, 15], [-90, 300, 15], [-170, 500, 16], [-250, 690, 16]])
	add_river("Харьков", [[560, -1150, 11], [420, -760, 12], [300, -480, 13], [160, -230, 13], [60, -40, 14], [-70, 60, 15]])
	add_river("Немышля", [[1150, 160, 8], [820, 90, 8], [520, 20, 9], [320, -60, 9], [200, -170, 10], [165, -215, 10]])
	add_river("Уды", [[-1150, 280, 14], [-760, 460, 15], [-460, 620, 16], [-250, 690, 17], [0, 860, 17], [280, 1150, 16]])
	# the Zhuravlivka reservoir on the Kharkiv river
	lakes.append([318.0, -520.0, 32.0, 78.0, 25.0])
	lakes.append([700.0, -250.0, 26.0, 18.0, 0.0])      # a pond in Saltivka
	lakes.append([-520.0, -740.0, 30.0, 20.0, 10.0])    # Alekseevka ponds
	lakes.append([420.0, 560.0, 34.0, 22.0, -20.0])     # Novi Budynky lake
	forests = [
		[20.0, -720.0, 250.0, 60.0],     # Lisopark
		[-10.0, -455.0, 80.0, 15.0],     # Gorky park
		[-160.0, -200.0, 42.0, 10.0],    # Shevchenko garden
		[-250.0, -410.0, 50.0, 15.0],    # Sarzhyn Yar
		[330.0, -520.0, 110.0, 25.0],    # Zhuravlivka hydropark
		[-620.0, 820.0, 190.0, 60.0],    # Zhykhar forest
		[900.0, 250.0, 150.0, 40.0],     # the Rohan woods
		[-880.0, -500.0, 150.0, 40.0],   # forest behind Alekseevka
	]


func _districts() -> void:
	districts = [
		# name, x, z, grid angle (deg), block size, character
		["Центр", -40.0, -60.0, 0.0, 56.0, "stalin"],
		["Нагорный", -80.0, -300.0, 8.0, 56.0, "historic"],
		["Павлово Поле", -300.0, -600.0, 5.0, 62.0, "panel"],
		["Алексеевка", -560.0, -560.0, -10.0, 66.0, "panel"],
		["Шатиловка", -140.0, -560.0, 20.0, 50.0, "private"],
		["Журавлёвка", 230.0, -330.0, 30.0, 54.0, "mixed"],
		["Салтовка", 560.0, -380.0, 15.0, 72.0, "panel"],
		["Северная Салтовка", 650.0, -680.0, 15.0, 74.0, "panel"],
		["Холодная Гора", -440.0, 30.0, -8.0, 58.0, "khrush"],
		["Новожаново", -760.0, 140.0, -12.0, 60.0, "private"],
		["Левада", 110.0, 230.0, 5.0, 56.0, "industrial"],
		["Москалёвка", -120.0, 200.0, -10.0, 54.0, "khrush"],
		["ХТЗ", 620.0, 280.0, 0.0, 66.0, "industrial"],
		["Новые Дома", 420.0, 420.0, 10.0, 64.0, "khrush"],
		["Одесская", 240.0, 640.0, 20.0, 62.0, "panel"],
		["Основа", -60.0, 620.0, -10.0, 56.0, "private"],
		["Лысая Гора", -360.0, 440.0, 0.0, 58.0, "private"],
		["Рогань", 800.0, -60.0, 5.0, 64.0, "new"],
		["Жуковского", -300.0, -250.0, 10.0, 58.0, "new"],
	]


func _routes() -> void:
	add_road("Сумская — проспект Науки", [[30, -110], [70, -220], [78, -340], [40, -470], [-40, -640], [-150, -1000]], 8.0)
	add_road("Московский проспект", [[-10, -45], [100, 20], [300, 130], [500, 210], [750, 290], [1000, 360]], 9.0,
		[{"name": "Московский мост", "style": "girder", "target": true}])
	add_road("проспект Гагарина", [[-30, 90], [-10, 300], [40, 560], [80, 740]], 8.0,
		[{"name": "мост через Уды", "style": "girder"}])
	add_road("Полтавский шлях", [[-40, -20], [-300, 20], [-600, 60], [-1000, 120]], 8.0,
		[{"name": "мост через Лопань", "style": "girder", "target": true}])
	add_road("проспект Героев Харькова", [[60, -175], [170, -240], [450, -360], [750, -480], [1000, -560]], 9.0,
		[{"name": "Салтовский мост", "style": "cable_a", "target": true}])
	add_road("Окружная дорога", [[-620, -1000], [-900, -400], [-880, 300], [-620, 820], [-100, 1000]], 8.0,
		[{"name": "мост через Уды", "style": "girder"}])
	add_rail("Южная железная дорога", [[-1000, -110], [-640, 20], [-460, 128], [-240, 168], [-110, 250], [100, 330], [350, 385], [700, 420], [1000, 450]], 2, 8,
		{"name": "железнодорожный мост", "target": false})
	add_rail("Белгородская линия", [[-470, 90], [-500, -200], [-540, -500], [-620, -1000]], 1, 7)
	bridges.append({"a": Vector2(-150, 380), "b": Vector2(-30, 395), "name": "пешеходный мост", "style": "pedestrian"})


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	label("Лопань", -250.0, -620.0, 48, blue)
	label("р. Харьков", 380.0, -680.0, 48, blue)
	label("Немышля", 620.0, 50.0, 40, blue)
	label("Уды", -600.0, 540.0, 48, blue)
	label("Лесопарк", 20.0, -760.0, 60, green)
	label("Парк Горького", -10.0, -470.0, 40, green)
	label("Журавлёвский гидропарк", 330.0, -560.0, 38, green)
	label("площадь Свободы", 0.0, -250.0, 40, Color(1.0, 0.9, 0.6, 0.85))


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	_freedom_square(map)
	_cathedrals(map)
	L.power_plant(map, Vector3(330, 0, 190), 5.0, "ТЭЦ-3")
	L.power_plant(map, Vector3(850, 0, -200), -15.0, "ТЭЦ-5", 2, 2)
	L.lattice_tower(map, Vector3(-330, 0, -520), "Харьковская телебашня", 120.0)
	L.station(map, Vector3(-360, 0, 98), -10.0, "Южный вокзал", Color(0.9, 0.84, 0.66), 40.0)
	L.airport(map, Vector3(200, 0, 760), 10.0, "Аэропорт Харьков")
	L.stadium(map, Vector3(300, 0, 55), 0.0, "стадион «Металлист»")
	L.factory(map, Vector3(620, 0, 330), 0.0, "Харьковский тракторный завод", 5, 3, true)
	L.factory(map, Vector3(430, 0, 272), 20.0, "завод «Турбоатом»", 3, 2)
	L.factory(map, Vector3(170, 0, 270), -10.0, "завод им. Малышева", 3, 2, true)
	L.ferris_wheel(map, Vector3(-30, 0, -470), 0.0, 20.0, "колесо обозрения в парке Горького")
	# the opera (a brutalist block) and the Mirror Stream fountain on Sumska
	L.classical(map, Vector3(-30, 0, -160), 0.0, "Харьковский оперный театр", Vector3(50, 24, 40), Color(0.82, 0.8, 0.76), null, false)
	var ms := L.group(Vector3(0, 0, -112), 0.0)
	L.cyl(ms, 7.0, 7.5, 0.8, Vector3(0, 0.4, 0), Fx.glow(Color(0.4, 0.8, 1.0), 0.8), 20)
	for i in 6:
		var a := TAU * i / 6.0
		L.cyl(ms, 0.35, 0.35, 5.0, Vector3(cos(a) * 3.0, 2.5, sin(a) * 3.0), L.lit(Color(0.95, 0.95, 0.9), 0.3), 6)
	L.sph(ms, 3.4, Vector3(0, 5.5, 0), L.lit(Color(0.95, 0.95, 0.9), 0.3), Vector3(1, 0.4, 1))
	L.fp(map, ms, Vector3.ZERO, Vector2(4, 4), 7.0, "«Зеркальная струя»")
	map.reserve(0, -112, 14.0)
	# new towers of the centre
	L.tower(map, Vector2(150, -60), Vector2(13, 11), 0.0, 92.0, 2, Color(0.28, 0.36, 0.46), "ЖК «Павловский квартал»")
	L.tower(map, Vector2(-230, -120), Vector2(12, 12), 8.0, 78.0, 0, Color(0.9, 0.86, 0.8), "бизнес-центр «Ривьера»")


## Derzhprom and Freedom Square: the constructivist giant, the university tower, the regional office.
func _freedom_square(map) -> void:
	var sq := Vector3(0, 0, -250)
	# the square itself stays open: a long oval with lamps around it
	map.reserve(sq.x, sq.z, 48.0)
	map.reserve(sq.x - 40.0, sq.z, 40.0)
	map.reserve(sq.x + 40.0, sq.z, 40.0)
	for i in 16:
		var a := TAU * i / 16.0
		map.add_light(sq + Vector3(cos(a) * 70.0, 8.0, sin(a) * 32.0), Color(1.0, 0.85, 0.6), false, 1.2, 0.0022)
	L.target(map, sq + Vector3(0, 2, 0), "площадь Свободы", "center")
	# Derzhprom: three stepped blocks on an arc, joined by sky bridges
	var d := L.group(Vector3(sq.x, 0, sq.z - 80.0), 0.0)
	var grey := Color(0.78, 0.78, 0.76)
	var parts := [[Vector3(-46, 0, 8), Vector2(14, 12), 40.0], [Vector3(-46, 0, -10), Vector2(10, 10), 58.0],
		[Vector3(0, 0, -4), Vector2(18, 12), 48.0], [Vector3(0, 0, -18), Vector2(12, 8), 64.0],
		[Vector3(46, 0, 8), Vector2(14, 12), 40.0], [Vector3(46, 0, -10), Vector2(10, 10), 58.0]]
	for p in parts:
		L.block(map, d, p[0], p[1], p[2], 1, grey, "Госпром")
	var glass := L.lit(Color(0.6, 0.7, 0.75), 0.2)
	for s in [-1.0, 1.0]:
		L.box(d, Vector3(30, 6, 6), Vector3(s * 23.0, 30.0, 4.0), glass)
		L.box(d, Vector3(30, 5, 5), Vector3(s * 23.0, 42.0, -6.0), glass)
	L.beam(d, Vector3(0, 64, -18), Vector3(0, 82, -18), 0.5, Fx.solid(Color(0.4, 0.4, 0.42)))
	L.light(map, d, Vector3(0, 83, -18))
	map.reserve(sq.x, sq.z - 80.0, 60.0)
	L.target(map, Vector3(sq.x, 20, sq.z - 80.0), "Госпром", "gov")
	# Karazin University: the Stalinist tower on the east side of the square
	var u := L.group(Vector3(sq.x + 125.0, 0, sq.z - 10.0), 0.0)
	L.block(map, u, Vector3.ZERO, Vector2(30, 12), 34.0, 1, Color(0.9, 0.86, 0.74), "Каразинский университет")
	L.block(map, u, Vector3(0, 0, -2), Vector2(12, 10), 66.0, 1, Color(0.9, 0.86, 0.74), "Каразинский университет")
	L.cyl(u, 0.0, 1.4, 14.0, Vector3(0, 73, -2), L.gold(), 8)
	L.light(map, u, Vector3(0, 81, -2))
	map.reserve(sq.x + 125.0, sq.z - 10.0, 34.0)
	# the regional administration on the west side
	var o := L.group(Vector3(sq.x - 85.0, 0, sq.z + 20.0), 0.0)
	L.block(map, o, Vector3.ZERO, Vector2(26, 12), 32.0, 1, Color(0.82, 0.8, 0.72), "Харьковская ОГА")
	map.reserve(sq.x - 85.0, sq.z + 20.0, 30.0)
	L.target(map, Vector3(sq.x - 85.0, 16, sq.z + 20.0), "Харьковская ОГА", "gov")
	# hotel "Kharkiv" on the south side
	L.block(map, L.group(Vector3(sq.x, 0, sq.z + 64.0), 0.0), Vector3.ZERO, Vector2(34, 10), 30.0, 1, Color(0.86, 0.82, 0.72), "гостиница «Харьков»")
	map.reserve(sq.x, sq.z + 64.0, 36.0)


func _cathedrals(map) -> void:
	# Annunciation Cathedral: red-and-white stripes, the tall bell tower, on the bank of the Lopan
	var an := L.cathedral(map, Vector3(40, 0, 110), 0.0, "Благовещенский собор", Color(0.78, 0.3, 0.26), Fx.solid(Color(0.3, 0.4, 0.3), 0.35, 0.6), 1.1, 4, true, "колокольня Благовещенского собора")
	for i in 4:
		L.box(an, Vector3(33.4, 0.8, 24.6), Vector3(0, 3.0 + i * 3.4, 0), L.lit(Color(0.95, 0.94, 0.9), 0.2))
	# Dormition Cathedral with its white bell tower on University hill
	var dm := L.group(Vector3(-60, 0, -110), 0.0)
	var white := L.lit(Color(0.95, 0.94, 0.9), 0.2)
	L.box(dm, Vector3(20, 14, 20), Vector3(0, 7, 0), L.lit(Color(0.95, 0.88, 0.62), 0.18))
	L.domed_drum(dm, Vector3(0, 14, 0), 3.4, 4.0, white, L.gold())
	for spec in [[Vector3(12, 22, 12), 11.0], [Vector3(10, 16, 10), 30.0], [Vector3(8, 14, 8), 45.0], [Vector3(6, 12, 6), 58.0]]:
		L.box(dm, spec[0], Vector3(0, spec[1], 24), white)
	L.cyl(dm, 0.0, 3.0, 16.0, Vector3(0, 72, 24), L.gold(), 8)
	L.fp(map, dm, Vector3(0, 0, 10), Vector2(10, 22), 80.0, "Успенский собор")
	L.light(map, dm, Vector3(0, 81, 24))
	map.reserve(-60, -100, 32.0)
