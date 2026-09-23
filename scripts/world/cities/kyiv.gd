extends "res://scripts/world/city_def.gd"
## Kyiv: the Dnipro with Trukhaniv island and Hydropark behind the Rusanivka channel, the Harbour,
## the Desna, Zhukiv island, the Rusanivka canal and the left-bank lakes; the historic right bank
## on its green slopes, Soviet panel districts on the left bank; eight road bridges, a railway over
## the Darnytskyi rail bridge, and the landmarks — Lavra, Motherland, St Sophia, Maidan, the Rada.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

const PUB := 2
const IND := 1


func _init() -> void:
	id = "kyiv"
	name = "Киев"
	version = 2
	seed = 1482
	accent = Color(0.35, 0.8, 1.0)
	blurb = "Столица на Днепре: восемь мостов, острова и пляжи, Лавра и правительственный квартал. Налёты со всех сторон."
	map_focus = Vector3(60, 0, 0)
	texts = {
		"defense": "Оборона Киева",
		"title": "КИЕВ",
		"over": "Ночное дежурство над Киевом",
		"duty": "%s РАДАР АКТИВЕН · ПВО КИЕВА НА ДЕЖУРСТВЕ",
		"raid": "НОЧЬ %d — МАССИРОВАННЫЙ НАЛЁТ НА КИЕВ!",
		"held": "Киев выстоял. %d ночей обороны позади.",
		"water_into": "в Днепр",
		"water_safe": "в Днепр — без ущерба",
		"water_label": "ДНЕПР — безопасно",
		"shore": "Берег Днепра",
		"shore_desc": "Безопасная зона: обломки, сбитые над водой, падают в Днепр.\nОткрытый обзор над рекой: дальность ствольной ПВО +10%.",
		"rec": "REC ● 60 км/ч · КИЕВ",
		"never_sleeps": "Киев не спит!",
	}
	video_channel = "@kyiv_cuts"
	video_authors = ["@olena.kyiv", "@serhii_obolon", "@nightwatch_ua", "@darnytsia_live", "@pechersk_cam",
		"@vika.balcony", "@taxi_2am", "@rooftop_kyiv", "@oksana_news", "@dnipro_view"]
	threat_sectors = [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 270.0]
	# the combined strikes on the capital: drone swarms with decoys to saturate the air defence,
	# Kh-101 from the strategic bombers, Kalibrs from the Black Sea, Iskanders and Kinzhals
	raid = {
		"drone": [["shahed", 0.6, 1], ["gerbera", 0.3, 2], ["geran3", 0.15, 7]],
		"cruise": [["cruise", 0.65, 3], ["kalibr", 0.35, 4]],
		"ballistic": [["ballistic", 0.7, 5], ["kinzhal", 0.3, 8]],
	}
	raid_sectors = {
		"kalibr": [150.0, 165.0, 180.0, 195.0, 210.0],
		"cruise": [30.0, 60.0, 90.0, 120.0, 0.0],
		"ballistic": [0.0, 20.0, 90.0, 120.0, 150.0],
		"kinzhal": [90.0, 120.0, 150.0, 180.0],
	}
	raid_note = "Киев бьют комбинированно: рои шахедов с ложными целями «Гербера», Х-101 с Ту-95, «Калибры» с моря, «Искандеры» и «Кинжалы» — последних берёт только Patriot."
	city_center = Vector2(60, 0)
	city_radii = Vector2(780, 720)
	_geography()
	_districts()
	_routes()
	_labels()


# --- The Dnipro ------------------------------------------------------------------------------------
func river_x(z: float) -> float:
	return 170.0 + 120.0 * sin(z * 0.0023 + 0.6) - 50.0 * cos(z * 0.0061)


func river_w(z: float) -> float:
	var w := 58.0 + 16.0 * sin(z * 0.0047 + 1.3)
	# the Obolon reach is wider, and so is the southern Dnipro below the South bridge
	w += 12.0 * clampf((-450.0 - z) / 200.0, 0.0, 1.0)
	w += 22.0 * clampf((z - 700.0) / 120.0, 0.0, 1.0)
	return w


## The right (western, hilly) bank.
func bank(z: float) -> float:
	return river_x(z) - river_w(z)


## The left (eastern) bank of the main channel.
func bank_r(z: float) -> float:
	return river_x(z) + river_w(z)


func _geography() -> void:
	var dn := []
	var z := -1150.0
	while z <= 1150.0:
		dn.append([river_x(z), z, river_w(z)])
		z += 50.0
	add_river("Днепр", dn)
	# the Rusanivka channel: Trukhaniv island and Hydropark lie between it and the main stream
	add_river("Русановская протока", [[215, -370, 10], [265, -330, 16], [305, -260, 18], [318, -150, 18], [330, -50, 18], [345, 20, 18], [355, 70, 16], [330, 115, 12], [300, 125, 10]])
	# the narrow strait between Trukhaniv island and Hydropark
	add_river("пролив", [[240, -48, 8], [280, -47, 8], [318, -45, 8]])
	# the Rusanivka canal around the "island" district
	var ring := []
	for i in 41:
		var a := TAU * i / 40.0
		ring.append([470.0 + cos(a) * 55.0, 60.0 + sin(a) * 100.0, 8.0])
	add_river("Русановский канал", ring, 20.0)
	# the Desna joins from the north-east
	add_river("Десна", [[1150, -1010, 20], [820, -1010, 22], [560, -965, 24], [330, -935, 24], [140, -915, 26], [30, -905, 30]])
	# the Harbour (Havan) with its mouth into the Dnipro, the Rybalskyi peninsula between them
	lakes.append([40.0, -540.0, 24.0, 70.0, -10.0])
	add_river("Гавань", [[42, -480, 12], [70, -462, 12], [110, -450, 12]])
	lakes.append([610.0, -10.0, 40.0, 26.0, 30.0])     # Telbin lake
	lakes.append([560.0, 290.0, 28.0, 40.0, 0.0])      # Berezniaky lake
	lakes.append([680.0, 700.0, 30.0, 60.0, 15.0])     # Vyrlytsia
	lakes.append([-330.0, -560.0, 30.0, 60.0, 20.0])   # Opechen lakes of Obolon
	lakes.append([-330.0, 620.0, 20.0, 14.0, 0.0])     # Holosiiv ponds
	# Zhukiv island in the wide southern Dnipro
	islands.append([river_x(830.0) + 4.0, 830.0, 22.0, 85.0, 8.0, GS.Zone.FOREST])
	# land between the channels: woods and beaches
	parks.append([270.0, -200.0, 45.0, 150.0, 0.0, GS.Zone.FOREST])   # Trukhaniv island
	parks.append([300.0, 30.0, 42.0, 75.0, 0.0, GS.Zone.FOREST])      # Hydropark
	forests = [
		[-660.0, -640.0, 330.0, 90.0],   # Pushcha-Vodytsia
		[-360.0, 690.0, 200.0, 70.0],    # Holosiiv forest
		[740.0, -660.0, 230.0, 70.0],    # Bykivnia
		[-420.0, 940.0, 120.0, 40.0],    # Feofaniia
		[80.0, 380.0, 55.0, 15.0],       # Hryshko botanical garden
		[-150.0, 700.0, 50.0, 15.0],     # Lysa Hora
		[920.0, 260.0, 130.0, 40.0],     # Darnytsia forest
	]


func zone_hook(_map, x: float, z: float, _wd: float, n: float) -> int:
	# the green right-bank Dnipro slopes (Mariinsky park, Volodymyrska hill)
	var slope := bank(z) - x
	if slope > 0.0 and slope < 55.0 + n * 25.0 and z > -300.0 and z < 460.0:
		return GS.Zone.FOREST
	return -1


func _districts() -> void:
	districts = [
		# name, x, z, grid angle (deg), block size, character
		["Центр", -130.0, 40.0, 45.0, 56.0, "historic"],
		["Старый Киев", -280.0, -60.0, 12.0, 54.0, "historic"],
		["Подол", -40.0, -300.0, -22.0, 48.0, "podil"],
		["Печерск", -10.0, 190.0, 32.0, 56.0, "pechersk"],
		["Лукьяновка", -300.0, -200.0, -10.0, 50.0, "khrush"],
		["Шулявка", -450.0, -40.0, 5.0, 54.0, "west"],
		["Нивки", -640.0, -230.0, 8.0, 60.0, "panel"],
		["Святошин", -860.0, -110.0, 0.0, 60.0, "panel"],
		["Соломенка", -380.0, 260.0, -12.0, 56.0, "khrush"],
		["Отрадный", -600.0, 250.0, 0.0, 58.0, "khrush"],
		["Демиевка", -140.0, 480.0, 16.0, 58.0, "mixed"],
		["Корчеватое", 90.0, 690.0, 25.0, 56.0, "mixed"],
		["Теремки", -620.0, 760.0, -10.0, 66.0, "panel"],
		["Оболонь", -170.0, -590.0, 30.0, 70.0, "panel"],
		["Виноградарь", -480.0, -370.0, -8.0, 64.0, "panel"],
		["Борщаговка", -700.0, 60.0, -18.0, 66.0, "panel"],
		["Левобережная", 520.0, -150.0, 0.0, 62.0, "new"],
		["Русановка", 470.0, 60.0, 0.0, 50.0, "panel"],
		["Троещина", 470.0, -560.0, 18.0, 74.0, "panel"],
		["Воскресенка", 650.0, -330.0, 0.0, 64.0, "mixed"],
		["Березняки", 460.0, 320.0, 10.0, 60.0, "panel"],
		["Дарница", 720.0, 150.0, -8.0, 62.0, "industrial"],
		["Позняки", 470.0, 620.0, 22.0, 70.0, "new"],
		["Харьковский", 800.0, 520.0, 12.0, 68.0, "new"],
		["Осокорки", 560.0, 870.0, 10.0, 60.0, "private"],
	]


func _routes() -> void:
	add_road("Северный мост", [[-620, -690], [-320, -652], [0, -640], [300, -630], [600, -605], [1000, -600]], 8.0,
		[{"name": "Северный мост", "style": "cable_a", "target": true}])
	add_road("Подольский мост", [[-200, -440], [0, -432], [160, -426], [360, -418], [620, -400], [1000, -390]], 8.0,
		[{"name": "Подольский мост", "style": "arch", "target": true}])
	add_road("Броварской проспект", [[-20, -5], [120, -10], [360, -30], [500, -78], [700, -118], [1000, -160]], 9.0,
		[{"name": "Мост Метро", "style": "metro", "target": true}])
	add_road("Мост Патона", [[-80, 165], [100, 172], [330, 188], [480, 216], [700, 244], [1000, 270]], 9.0,
		[{"name": "Мост Патона", "style": "girder", "target": true}])
	add_road("Дарницкий мост", [[80, 395], [200, 382], [420, 372], [560, 332], [640, 262]], 8.0,
		[{"name": "Дарницкий мост", "style": "girder", "target": true}])
	add_road("Южный мост", [[-120, 660], [100, 640], [300, 626], [500, 620], [750, 600], [1000, 590]], 9.0,
		[{"name": "Южный мост", "style": "cable", "target": true}])
	add_road("проспект Победы", [[-360, -80], [-450, -105], [-600, -140], [-800, -170], [-1000, -195]], 9.0)
	add_road("проспект Бандеры", [[-60, -360], [-80, -520], [-110, -700], [-150, -900], [-170, -1000]], 8.0)
	add_road("Голосеевский проспект", [[-95, 210], [-110, 420], [-150, 620], [-195, 820], [-225, 1000]], 8.0)
	add_road("Окружная дорога", [[-560, -1000], [-900, -700], [-930, -300], [-915, 100], [-850, 450], [-750, 800], [-620, 1000]], 8.0)
	add_rail("Юго-Западная железная дорога", [[-1000, 335], [-750, 295], [-520, 259], [-340, 233], [-305, 272], [-300, 340], [-250, 420], [-120, 455],
		[40, 440], [200, 415], [330, 408], [480, 402], [650, 388], [820, 372], [1000, 360]], 2, 8,
		{"name": "Дарницкий железнодорожный мост", "target": false})
	bridges.append({"a": Vector2(bank(-100.0) - 20.0, -100.0), "b": Vector2(bank_r(-100.0) + 26.0, -100.0), "name": "Пешеходный мост", "style": "pedestrian"})
	bridges.append({"a": Vector2(-20.0, -540.0), "b": Vector2(82.0, -540.0), "name": "Гаванский мост", "style": "girder"})


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	label("ДНЕПР", river_x(-760.0), -760.0, 72, blue)
	label("ДНЕПР", river_x(760.0), 760.0, 72, blue)
	label("Десна", 500.0, -955.0, 52, blue)
	label("Гавань", 40.0, -540.0, 40, blue)
	label("Труханов остров", 270.0, -200.0, 48, Color(0.7, 1.0, 0.8, 0.8))
	label("Гидропарк", 300.0, 30.0, 44, Color(0.7, 1.0, 0.8, 0.8))
	label("Жуков остров", river_x(830.0), 830.0, 40, Color(0.7, 1.0, 0.8, 0.8))
	label("Пуща-Водица", -660.0, -640.0, 60, green)
	label("Голосеевский лес", -360.0, 690.0, 60, green)
	label("Быковня", 740.0, -660.0, 60, green)
	label("Феофания", -420.0, 940.0, 44, green)
	label("Ботанический сад", 80.0, 380.0, 36, green)


func radar_coast() -> Array:
	return []


# --- Landmarks -----------------------------------------------------------------------------------------
func build_landmarks(map) -> void:
	_power_plants(map)
	_motherland(map)
	_lavra(map)
	_center(map)
	_cathedrals(map)
	_government(map)
	_towers_and_stadium(map)
	L.lattice_tower(map, Vector3(-440, 0, -250), "Киевская телебашня", 100.0)
	L.station(map, Vector3(-430, 0, 196), 8.0, "Центральный вокзал")
	L.station(map, Vector3(660, 0, 345), 0.0, "вокзал Дарница", Color(0.82, 0.86, 0.9), 24.0)
	L.airport(map, Vector3(-640, 0, 470), -25.0, "Аэропорт Жуляны")
	L.port(map, Vector3(bank(-260.0) - 26.0, 0, -260.0), 90.0, "Речной порт", 4, "Речной вокзал")
	L.ship(map, Vector3(bank(-235.0) + 14.0, 0, -235.0), 90.0, 56.0, "barge", "баржа")
	L.ship(map, Vector3(bank(-315.0) + 16.0, 0, -318.0), 94.0, 62.0, "bulk", "речной сухогруз")
	L.ferris_wheel(map, Vector3(-60, 0, -250), 20.0, 16.0, "колесо обозрения на Подоле")
	_new_landmarks(map)


func _power_plants(map) -> void:
	L.power_plant(map, Vector3(560, 0, 520), 20.0, "ТЭЦ-5")
	L.power_plant(map, Vector3(500, 0, -520), -10.0, "ТЭЦ-6")
	L.power_plant(map, Vector3(-520, 0, -10), 5.0, "ТЭЦ-4")
	L.power_plant(map, Vector3(660, 0, 110), -8.0, "Дарницкая ТЭЦ")


func _motherland(map) -> void:
	var z := 330.0
	var x := bank(z) - 72.0
	var g := L.group(Vector3(x, 0, z), -20.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.85, 0.88)
	steel.metallic = 0.9
	steel.roughness = 0.22
	steel.emission_enabled = true
	steel.emission = Color(0.75, 0.82, 0.95)
	steel.emission_energy_multiplier = 0.22
	var stone := L.lit(Color(0.62, 0.6, 0.58), 0.08)
	L.cyl(g, 16.0, 19.0, 6.0, Vector3(0, 3, 0), stone, 28)
	L.cyl(g, 11.0, 13.0, 12.0, Vector3(0, 12, 0), stone, 24)
	L.cyl(g, 5.0, 7.0, 4.0, Vector3(0, 20, 0), stone, 16)
	# figure: gown, torso, head
	L.cyl(g, 3.2, 6.2, 24.0, Vector3(0, 34, 0), steel, 16)
	L.cyl(g, 2.6, 3.2, 10.0, Vector3(0, 51, 0), steel, 14)
	L.sph(g, 2.2, Vector3(0, 58, 0), steel)
	# raised sword arm and shield arm
	L.beam(g, Vector3(1.8, 54, 0), Vector3(5.5, 66, 0.5), 1.5, steel)
	L.beam(g, Vector3(5.5, 66, 0.5), Vector3(6.8, 92, 0.8), 0.7, steel)
	L.beam(g, Vector3(-1.8, 54, 0), Vector3(-6.0, 60, 0.5), 1.5, steel)
	var shield := L.cyl(g, 5.2, 5.2, 0.6, Vector3(-7.2, 61, 0.6), steel, 20)
	shield.rotation_degrees = Vector3(0, 0, 80)
	L.fp(map, g, Vector3.ZERO, Vector2(12, 12), 58.0, "монумент «Родина-мать»")
	L.light(map, g, Vector3(6.8, 93, 0.8))
	map.reserve(x, z, 34.0)


func _lavra(map) -> void:
	var z := 245.0
	var x := bank(z) - 120.0
	var g := L.group(Vector3(x, 0, z), -15.0)
	var white := L.lit(Color(0.95, 0.94, 0.9), 0.16)
	var green := L.lit(Color(0.35, 0.62, 0.5), 0.1)
	for s in [Vector3(0, 3, -40), Vector3(0, 3, 40)]:
		L.box(g, Vector3(96, 6, 2), s, white)
	for s in [Vector3(-48, 3, 0), Vector3(48, 3, 0)]:
		L.box(g, Vector3(2, 6, 80), s, white)
	# Dormition Cathedral with seven golden domes
	L.box(g, Vector3(26, 16, 20), Vector3(0, 8, 4), white)
	L.domed_drum(g, Vector3(0, 16, 4), 4.0, 6.0, white, L.gold())
	for s in [Vector3(-8, 16, -3), Vector3(8, 16, -3), Vector3(-8, 16, 11), Vector3(8, 16, 11), Vector3(-11, 16, 4), Vector3(11, 16, 4)]:
		L.domed_drum(g, s, 1.8, 3.0, white, L.gold())
	L.fp(map, g, Vector3(0, 0, 4), Vector2(13, 10), 30.0, "Успенский собор Лавры")
	# Great Lavra Bell Tower
	var bt := Vector3(-30, 0, -22)
	L.box(g, Vector3(15, 20, 15), bt + Vector3(0, 10, 0), white)
	L.box(g, Vector3(12, 16, 12), bt + Vector3(0, 28, 0), green)
	L.box(g, Vector3(10, 14, 10), bt + Vector3(0, 43, 0), white)
	L.cyl(g, 4.2, 4.2, 10.0, bt + Vector3(0, 55, 0), green, 16)
	L.onion(g, bt + Vector3(0, 60, 0), 4.2, L.gold())
	L.fp(map, g, bt, Vector2(8, 8), 68.0, "Большая Лаврская колокольня")
	L.light(map, g, bt + Vector3(0, 76, 0))
	# Trinity Gate church and a few monastery buildings
	L.box(g, Vector3(14, 10, 10), Vector3(20, 5, -34), white)
	L.domed_drum(g, Vector3(20, 10, -34), 2.2, 3.0, white, L.gold())
	for s in [Vector3(-30, 0, 24), Vector3(30, 0, 20)]:
		L.box(g, Vector3(20, 9, 10), s + Vector3(0, 4.5, 0), white)
	map.reserve(x, z, 58.0)
	# Vydubychi monastery further south along the river
	var vz := 540.0
	var vg := L.group(Vector3(bank(vz) - 40.0, 0, vz), 10.0)
	L.box(vg, Vector3(14, 12, 18), Vector3(0, 6, 0), white)
	L.domed_drum(vg, Vector3(0, 12, 0), 2.6, 4.0, white, Fx.solid(Color(0.25, 0.5, 0.35), 0.35, 0.6))
	L.box(vg, Vector3(6, 22, 6), Vector3(0, 11, -16), white)
	L.onion(vg, Vector3(0, 22, -16), 2.0, Fx.solid(Color(0.25, 0.5, 0.35), 0.35, 0.6))
	L.fp(map, vg, Vector3(0, 0, -4), Vector2(8, 14), 22.0, "Выдубицкий монастырь")
	map.reserve(vg.position.x, vz, 26.0)


# --- Maidan, Khreshchatyk, Arch of Freedom -----------------------------------------------------------
func _center(map) -> void:
	var white := L.lit(Color(0.94, 0.94, 0.92), 0.25)
	# Independence Monument: column with the golden Berehynia
	var g := L.group(Vector3(-112, 0, 38), 45.0)
	L.cyl(g, 8.0, 9.0, 1.2, Vector3(0, 0.6, 0), Fx.solid(Color(0.5, 0.48, 0.46)), 24)
	L.box(g, Vector3(9, 6, 9), Vector3(0, 3.6, 0), white)
	L.cyl(g, 1.7, 2.0, 44.0, Vector3(0, 28.6, 0), white, 16)
	L.cyl(g, 2.8, 1.8, 3.0, Vector3(0, 52, 0), white, 16)
	L.cyl(g, 0.7, 1.4, 5.0, Vector3(0, 56, 0), L.gold(), 10)
	L.sph(g, 0.8, Vector3(0, 59.2, 0), L.gold())
	L.beam(g, Vector3(-0.6, 57.5, 0), Vector3(-3.2, 60.5, 0), 0.45, L.gold())
	L.beam(g, Vector3(0.6, 57.5, 0), Vector3(3.2, 60.5, 0), 0.45, L.gold())
	L.fp(map, g, Vector3.ZERO, Vector2(5, 5), 58.0, "монумент Независимости")
	# glass domes of the underground mall + fountains
	for s in [Vector3(-14, 0, 12), Vector3(14, 0, 12), Vector3(0, 0, 18)]:
		L.sph(g, 3.5, s, Fx.glow(Color(0.5, 0.8, 1.0), 0.5), Vector3(1, 0.5, 1))
	map.add_light(Vector3(-112, 1.5, 38), Color(1.0, 0.9, 0.7), false, 6.0, 0.003)
	map.reserve(-118, 44, 36.0)
	L.target(map, Vector3(-118, 2, 44), "Центр (Майдан)", "center")
	# Hotel Ukraina: stepped Stalinist high-rise on the hill above Maidan
	var h := L.group(Vector3(-150, 0, 88), 45.0)
	var cream := Color(0.9, 0.86, 0.76)
	for spec in [[Vector2(30, 11), 42.0], [Vector2(20, 9), 58.0], [Vector2(9, 8), 72.0]]:
		L.block(map, h, Vector3.ZERO, spec[0], spec[1], 1, cream, "гостиница «Украина»")
	L.cyl(h, 0.0, 1.6, 16.0, Vector3(0, 80, 0), L.gold(), 8)
	L.light(map, h, Vector3(0, 88.5, 0))
	map.reserve(-150, 88, 30.0)
	# Trade Unions House with the LED ticker, City Council with its clock tower
	var tu := L.group(Vector3(-86, 0, 24), 45.0)
	L.block(map, tu, Vector3.ZERO, Vector2(24, 10), 28.0, 1, Color(0.85, 0.82, 0.74), "Дом профсоюзов")
	L.box(tu, Vector3(40, 2.2, 0.3), Vector3(0, 30, 10.2), Fx.glow(Color(1.0, 0.25, 0.2), 1.6))
	L.box(tu, Vector3(6, 14, 6), Vector3(-20, 35, 0), white)
	map.reserve(-86, 24, 22.0)
	# on the north-west side of Khreshchatyk (the avenue itself stays open)
	var cc := L.group(Vector3(-88, 0, -38), 45.0)
	L.block(map, cc, Vector3.ZERO, Vector2(26, 11), 26.0, 1, Color(0.92, 0.9, 0.84), "Киевсовет")
	L.box(cc, Vector3(8, 14, 8), Vector3(0, 33, 0), white)
	L.box(cc, Vector3(4.5, 4.5, 0.3), Vector3(0, 35, 4.1), Fx.glow(Color(1.0, 0.95, 0.8), 1.4))
	L.cyl(cc, 0.0, 3.0, 8.0, Vector3(0, 44, 0), Fx.solid(Color(0.3, 0.35, 0.38), 0.4, 0.6), 8)
	map.reserve(-88, -38, 24.0)
	# Arch of Freedom of the Ukrainian People over the Dnipro slopes
	var az := -60.0
	var ax := bank(az) - 62.0
	var ag := L.group(Vector3(ax, 0, az), 90.0)
	var arch := MeshInstance3D.new()
	arch.mesh = Fx.ring_mesh(30.0, 2.4)
	arch.material_override = Fx.glow(Color(0.65, 0.8, 1.0), 0.9)
	arch.rotation_degrees = Vector3(90, 0, 0)
	ag.add_child(arch)
	L.box(ag, Vector3(4, 7, 3), Vector3(0, 3.5, 0), Fx.solid(Color(0.55, 0.45, 0.35), 0.4, 0.7))
	L.fp(map, ag, Vector3.ZERO, Vector2(31, 3), 30.0, "Арка Свободы")
	map.reserve(ax, az, 34.0)


# --- Cathedrals of Old Kyiv ---------------------------------------------------------------------------
func _cathedrals(map) -> void:
	var white := L.lit(Color(0.96, 0.96, 0.92), 0.2)
	var green_dome := Fx.solid(Color(0.26, 0.52, 0.38), 0.35, 0.6)
	var blue_wall := L.lit(Color(0.36, 0.64, 0.86), 0.18)
	# St Sophia Cathedral: 13 domes, the big one golden
	var s := L.group(Vector3(-250, 0, -52), 12.0)
	L.box(s, Vector3(36, 14, 28), Vector3(0, 7, 0), white)
	L.box(s, Vector3(44, 8, 20), Vector3(0, 4, 0), white)
	L.domed_drum(s, Vector3(0, 14, 0), 4.2, 7.0, white, L.gold())
	for p in [Vector3(-9, 14, -7), Vector3(9, 14, -7), Vector3(-9, 14, 7), Vector3(9, 14, 7), Vector3(-15, 14, 0), Vector3(15, 14, 0), Vector3(0, 14, -11), Vector3(0, 14, 11)]:
		L.domed_drum(s, p, 1.9, 3.0, white, green_dome)
	for p in [Vector3(-20, 8, -8), Vector3(20, 8, -8), Vector3(-20, 8, 8), Vector3(20, 8, 8)]:
		L.domed_drum(s, p, 1.4, 2.0, white, green_dome)
	L.fp(map, s, Vector3.ZERO, Vector2(22, 14), 34.0, "Софийский собор")
	var bt := L.group(Vector3(-236, 0, -8), 12.0)
	for spec in [[Vector3(12, 16, 12), 8.0, white], [Vector3(10, 14, 10), 23.0, blue_wall], [Vector3(8, 12, 8), 36.0, white], [Vector3(6, 8, 6), 46.0, blue_wall]]:
		L.box(bt, spec[0], Vector3(0, spec[1], 0), spec[2])
	L.onion(bt, Vector3(0, 50, 0), 3.4, L.gold())
	L.fp(map, bt, Vector3.ZERO, Vector2(6, 6), 60.0, "колокольня Софии")
	L.light(map, bt, Vector3(0, 63, 0))
	map.reserve(-248, -40, 42.0)
	# Bohdan Khmelnytsky monument on Sofiiska square
	var bk := L.group(Vector3(-208, 0, -58), 30.0)
	L.box(bk, Vector3(6, 5, 10), Vector3(0, 2.5, 0), Fx.solid(Color(0.4, 0.38, 0.36)))
	L.box(bk, Vector3(2.2, 4, 7), Vector3(0, 7, 0), Fx.solid(Color(0.2, 0.3, 0.26), 0.4, 0.7))
	L.box(bk, Vector3(1.2, 4, 1.2), Vector3(0, 10.5, 0.5), Fx.solid(Color(0.2, 0.3, 0.26), 0.4, 0.7))
	# St Michael's Golden-Domed Monastery: sky-blue walls, golden domes
	L.cathedral(map, Vector3(-170, 0, -86), 12.0, "Михайловский Златоверхий монастырь", Color(0.36, 0.64, 0.86), L.gold(), 1.0, 6, true)
	# St Andrew's Church on its hill above Podil
	var a := L.group(Vector3(-150, 0, -172), -20.0)
	L.box(a, Vector3(22, 9, 22), Vector3(0, 4.5, 0), Fx.solid(Color(0.5, 0.48, 0.46), 0.9))
	var aw := L.lit(Color(0.62, 0.8, 0.9), 0.2)
	L.box(a, Vector3(10, 12, 18), Vector3(0, 15, 0), aw)
	L.box(a, Vector3(18, 12, 10), Vector3(0, 15, 0), aw)
	L.domed_drum(a, Vector3(0, 21, 0), 3.4, 5.0, aw, green_dome)
	for p in [Vector3(-7, 9, -7), Vector3(7, 9, -7), Vector3(-7, 9, 7), Vector3(7, 9, 7)]:
		L.cyl(a, 1.4, 1.4, 12.0, p + Vector3(0, 6, 0), aw, 10)
		L.onion(a, p + Vector3(0, 12, 0), 1.5, green_dome)
	L.fp(map, a, Vector3.ZERO, Vector2(11, 11), 32.0, "Андреевская церковь")
	map.reserve(-150, -172, 24.0)
	# St Volodymyr's Cathedral: yellow walls, dark domes
	L.cathedral(map, Vector3(-340, 0, 150), 8.0, "Владимирский собор", Color(0.96, 0.84, 0.5), Fx.solid(Color(0.1, 0.16, 0.3), 0.3, 0.7), 1.0, 6, false)
	# Golden Gate
	var gg := L.group(Vector3(-292, 0, 36), 12.0)
	var brick := Fx.solid(Color(0.62, 0.42, 0.32), 0.9)
	L.box(gg, Vector3(7, 14, 14), Vector3(-7, 7, 0), brick)
	L.box(gg, Vector3(7, 14, 14), Vector3(7, 7, 0), brick)
	L.box(gg, Vector3(21, 5, 14), Vector3(0, 16.5, 0), brick)
	L.box(gg, Vector3(10, 7, 9), Vector3(0, 22.5, 0), L.lit(Color(0.95, 0.94, 0.9), 0.2))
	L.onion(gg, Vector3(0, 26, 0), 2.6, L.gold())
	L.fp(map, gg, Vector3.ZERO, Vector2(11, 7), 26.0, "Золотые ворота")
	map.reserve(-292, 36, 20.0)
	# National Opera
	var op := L.group(Vector3(-318, 0, 90), 12.0)
	var opc := L.lit(Color(0.93, 0.87, 0.74), 0.2)
	L.box(op, Vector3(44, 20, 54), Vector3(0, 10, 0), opc)
	L.box(op, Vector3(30, 10, 30), Vector3(0, 25, 4), opc)
	L.sph(op, 12.0, Vector3(0, 30, 4), Fx.solid(Color(0.3, 0.45, 0.4), 0.4, 0.6), Vector3(1.1, 0.45, 1.1))
	L.fp(map, op, Vector3.ZERO, Vector2(22, 27), 32.0, "Национальная опера")
	map.reserve(-318, 90, 34.0)
	# the red building of Shevchenko University
	L.classical(map, Vector3(-272, 0, 168), 12.0, "Красный корпус университета", Vector3(62, 20, 22), Color(0.72, 0.16, 0.12))


# --- Government quarter (Pechersk) --------------------------------------------------------------------
func _government(map) -> void:
	# Verkhovna Rada with its glass dome
	var r := L.group(Vector3(10, 0, 100), 32.0)
	L.block(map, r, Vector3.ZERO, Vector2(22, 22), 20.0, 1, Color(0.86, 0.84, 0.78), "Верховная Рада")
	L.sph(r, 13.0, Vector3(0, 20, 0), Fx.glow(Color(0.55, 0.75, 0.9), 0.35), Vector3(1, 0.55, 1))
	L.box(r, Vector3(0.2, 8, 0.2), Vector3(0, 30, 0), Fx.solid(Color(0.3, 0.3, 0.3)))
	L.box(r, Vector3(4, 1.3, 0.1), Vector3(2, 33.2, 0), Fx.glow(Color(0.0, 0.36, 0.73), 0.8))
	L.box(r, Vector3(4, 1.3, 0.1), Vector3(2, 31.9, 0), Fx.glow(Color(1.0, 0.84, 0.0), 0.8))
	map.reserve(10, 100, 34.0)
	# Mariinsky Palace: turquoise baroque
	var mp := L.group(Vector3(48, 0, 74), 32.0)
	var turq := L.lit(Color(0.34, 0.72, 0.7), 0.2)
	L.box(mp, Vector3(34, 13, 14), Vector3(0, 6.5, 0), turq)
	L.box(mp, Vector3(34.4, 1.0, 14.4), Vector3(0, 13, 0), L.lit(Color(0.95, 0.95, 0.92), 0.2))
	L.sph(mp, 4.0, Vector3(0, 14, 0), Fx.solid(Color(0.3, 0.55, 0.45), 0.4, 0.6), Vector3(1, 0.8, 1))
	L.fp(map, mp, Vector3.ZERO, Vector2(17, 7), 17.0, "Мариинский дворец")
	map.reserve(48, 74, 22.0)
	# Cabinet of Ministers: huge Stalinist block
	var cm := L.group(Vector3(-24, 0, 58), 32.0)
	for spec in [[Vector3(0, 0, 0), Vector2(32, 10), 42.0], [Vector3(-26, 0, 16), Vector2(8, 18), 30.0], [Vector3(26, 0, 16), Vector2(8, 18), 30.0]]:
		L.block(map, cm, spec[0], spec[1], spec[2], 1, Color(0.72, 0.7, 0.64), "Кабинет Министров")
	map.reserve(-24, 64, 36.0)
	L.target(map, Vector3(-24, 20, 58), "Правительственный квартал", "gov")
	# Office of the President (Bankova)
	var bk := L.group(Vector3(-66, 0, 96), 45.0)
	L.block(map, bk, Vector3.ZERO, Vector2(22, 12), 28.0, 1, Color(0.68, 0.68, 0.66), "Офис Президента")
	map.reserve(-66, 96, 24.0)


# --- Stadium and skyscrapers ------------------------------------------------------------------------
func _towers_and_stadium(map) -> void:
	L.stadium(map, Vector3(-236, 0, 300), 16.0, "НСК «Олимпийский»")
	L.tower(map, Vector2(-160, 238), Vector2(14, 12), 20.0, 112.0, 2, Color(0.28, 0.38, 0.5), "БЦ «Гулливер»")
	L.tower(map, Vector2(-208, 176), Vector2(12, 12), 20.0, 86.0, 2, Color(0.32, 0.36, 0.42), "БЦ «Парус»")
	L.tower(map, Vector2(-30, 236), Vector2(13, 11), 20.0, 126.0, 0, Color(0.9, 0.88, 0.82), "Кловский небоскрёб")
	var gp := L.group(Vector3(-160, 0, 238), 20.0)
	L.box(gp, Vector3(64, 18, 40), Vector3(0, 9, 26), L.lit(Color(0.4, 0.45, 0.55), 0.15))
	L.fp(map, gp, Vector3(0, 0, 26), Vector2(32, 20), 18.0, "ТРЦ «Гулливер»")


func _new_landmarks(map) -> void:
	# Palace of Sports near Bessarabka
	L.classical(map, Vector3(-120, 0, 150), 45.0, "Дворец спорта", Vector3(54, 22, 38), Color(0.72, 0.76, 0.8), null, false)
	# Hotel "Salut": the round tower on a column above the Glory park
	var sl := L.group(Vector3(60, 0, 125), 0.0)
	var sc := L.lit(Color(0.85, 0.85, 0.82), 0.2)
	L.cyl(sl, 6.0, 7.0, 18.0, Vector3(0, 9, 0), sc, 16)
	L.cyl(sl, 13.0, 11.0, 16.0, Vector3(0, 26, 0), sc, 20)
	L.cyl(sl, 13.2, 13.2, 1.4, Vector3(0, 28, 0), Fx.glow(Color(1.0, 0.85, 0.6), 1.0), 20)
	L.fp(map, sl, Vector3.ZERO, Vector2(12, 12), 34.0, "гостиница «Салют»")
	map.reserve(60, 125, 18.0)
	# International Exhibition Centre on the Brovarskyi avenue
	map.add_building(Vector2(560, -148), Vector2(40, 24), 0.0, 18.0, 2, Color(0.28, 0.38, 0.5), PUB, 0.0, Color(), "Международный выставочный центр")
	for i in 5:
		map.add_light(Vector3(530 + i * 15, 18.6, -148), Color(0.4, 0.8, 1.0), false, 2.0, 0.003)
	map.reserve(560, -148, 50.0)
	# VDNH: the main pavilion with its spire at the end of the alley
	var vd := L.classical(map, Vector3(-40, 0, 860), 0.0, "ВДНХ", Vector3(46, 20, 24), Color(0.94, 0.9, 0.8), Fx.solid(Color(0.8, 0.7, 0.4), 0.4, 0.5))
	L.cyl(vd, 0.0, 1.6, 22.0, Vector3(0, 40, 0), L.gold(), 8)
	L.light(map, vd, Vector3(0, 52, 0))
