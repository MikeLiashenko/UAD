extends "res://scripts/world/city_def.gd"
## Kyiv at its real size (30 × 30 km around the Maidan). The Dnipro with the Desenka and the
## Rusanivka channel, Trukhaniv island, Muromets and Hydropark, the Harbour behind the Rybalskyi
## peninsula, the Desna, the Rusanivka canal and the lakes of both banks; the historic right bank
## on its green slopes, the panel districts of Obolon, Troieshchyna and the left bank, the forests
## around the city. Eight bridges, two railways, and the landmarks where they really stand — the
## Lavra, the Motherland, St Sophia, the Maidan, the Rada, the 385 m TV tower.

const L = preload("res://scripts/world/landmarks.gd")
const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

const PUB := 2
const IND := 1

## The main channel of the Dnipro: [lat, lon, half width].
const DNIPRO := [
	[50.590, 30.508, 380], [50.570, 30.512, 360], [50.550, 30.520, 330], [50.530, 30.528, 300], [50.510, 30.533, 280],
	[50.4936, 30.5355, 260], [50.480, 30.5345, 240], [50.4725, 30.5330, 230], [50.463, 30.5310, 220], [50.4562, 30.5360, 210],
	[50.4490, 30.5480, 230], [50.4418, 30.5640, 300], [50.4345, 30.5745, 320], [50.4275, 30.5810, 330], [50.4200, 30.5860, 340],
	[50.4155, 30.5890, 340], [50.4050, 30.5900, 350], [50.3950, 30.5880, 380], [50.3800, 30.5800, 420], [50.3600, 30.5720, 450],
	[50.3400, 30.5750, 480], [50.3200, 30.5850, 500], [50.3050, 30.5950, 500],
]
var _bank: Array = []


func _init() -> void:
	id = "kyiv"
	name = "Киев"
	version = 3
	seed = 1482
	accent = Color(0.35, 0.8, 1.0)
	blurb = "Столица на Днепре: восемь мостов, острова и пляжи, Лавра и правительственный квартал. Налёты со всех сторон."
	half = 15000.0
	lat0 = 50.45
	lon0 = 30.53
	map_focus = ll3(50.4475, 30.5300)
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
	city_center = ll(50.445, 30.52)
	city_radii = Vector2(12500, 11500)
	park_threshold = 0.5
	hook_reach = 600.0
	_geography()
	_districts()
	_routes()
	_labels()


# --- The Dnipro ------------------------------------------------------------------------------------
## The right (western) bank of the main channel at a given z.
func bank(z: float) -> float:
	for i in _bank.size() - 1:
		var a: Vector3 = _bank[i]
		var b: Vector3 = _bank[i + 1]
		if z <= b.z or i == _bank.size() - 2:
			var t := clampf((z - a.z) / maxf(b.z - a.z, 0.001), 0.0, 1.0)
			return lerpf(a.x, b.x, t) - lerpf(a.y, b.y, t)
	return 0.0


func _geography() -> void:
	for p in DNIPRO:
		var q := ll(float(p[0]), float(p[1]))
		_bank.append(Vector3(q.x, float(p[2]), q.y))
	add_river_ll("Днепр", DNIPRO)
	# the Desenka (Chortoryi): the eastern arm around Muromets and Trukhaniv island
	add_river_ll("Десёнка", [[50.5450, 30.5600, 120], [50.5200, 30.5660, 110], [50.5000, 30.5700, 100], [50.4850, 30.5720, 100], [50.4720, 30.5700, 95],
		[50.4620, 30.5660, 95], [50.4545, 30.5640, 95], [50.4490, 30.5570, 100]])
	# the Rusanivka channel behind Hydropark
	add_river_ll("Русановская протока", [[50.4575, 30.5690, 70], [50.4520, 30.5760, 80], [50.4437, 30.5825, 85], [50.4360, 30.5875, 85], [50.4290, 30.5895, 80], [50.4225, 30.5885, 80]])
	# the Rusanivka canal around the "island" district
	add_river_ll("Русановский канал", [[50.4490, 30.5850, 20], [50.4505, 30.5930, 22], [50.4480, 30.6020, 22], [50.4410, 30.6050, 22], [50.4350, 30.6010, 22], [50.4330, 30.5920, 20]], 25.0)
	# the Desna joins from the north-east
	add_river_ll("Десна", [[50.6000, 30.7000, 120], [50.5850, 30.6600, 120], [50.5700, 30.6200, 125], [50.5550, 30.5850, 130], [50.5450, 30.5580, 130], [50.5380, 30.5330, 130]])
	# the Harbour: its mouth is at the south tip of the Rybalskyi peninsula
	add_river_ll("Гавань", [[50.4850, 30.5210, 70], [50.4780, 30.5225, 90], [50.4720, 30.5245, 90], [50.4672, 30.5275, 60], [50.4655, 30.5300, 50]], 30.0)
	# the bays of Obolon and its chain of lakes
	lake_ll(50.5015, 30.5200, 520.0, 130.0, 8.0)
	lake_ll(50.5270, 30.5130, 600.0, 180.0, -30.0)
	for q in [[50.4935, 30.4960], [50.4990, 30.4930], [50.5040, 30.4900], [50.5090, 30.4880]]:
		lake_ll(q[0], q[1], 230.0, 110.0, 70.0)
	lake_ll(50.4965, 30.5085, 180.0, 120.0, 0.0)      # Verbne
	# left-bank lakes
	lake_ll(50.4255, 30.6090, 400.0, 190.0, 20.0)     # Telbin
	lake_ll(50.4780, 30.5890, 330.0, 140.0, 80.0)     # Raiduzhne
	lake_ll(50.5120, 30.6600, 560.0, 330.0, 30.0)     # Almazne
	lake_ll(50.3960, 30.6640, 560.0, 330.0, -20.0)    # Vyrlytsia
	lake_ll(50.4010, 30.6230, 280.0, 130.0, 10.0)     # Soniachne
	lake_ll(50.3850, 30.6020, 650.0, 170.0, 60.0)     # Nebrezh
	lake_ll(50.3930, 30.5090, 190.0, 80.0, 30.0)      # the Holosiiv ponds
	lake_ll(50.4560, 30.3530, 280.0, 110.0, 10.0)     # the Sviatoshyn ponds
	# Zhukiv island in the wide southern Dnipro
	island_ll(50.3450, 30.5760, 200.0, 900.0, 5.0, Z_FOREST)
	# the land between the channels: woods and beaches
	park_ll(50.4680, 30.5530, 1100.0, 2300.0, 4.0, Z_FOREST)     # Trukhaniv island
	park_ll(50.5080, 30.5545, 1150.0, 2300.0, 8.0, Z_FOREST)     # Muromets
	park_ll(50.4440, 30.5745, 480.0, 1000.0, -22.0, Z_FOREST)   # Hydropark
	park_ll(50.4540, 30.5625, 330.0, 600.0, -30.0, Z_FOREST)    # Dolobetskyi island
	park_ll(50.4270, 30.5875, 120.0, 520.0, -8.0, Z_FOREST)     # the spit under the Paton bridge
	forest_ll(50.5300, 30.3700, 4500.0, 3500.0, 0.0, 0.25)   # Pushcha-Vodytsia
	forest_ll(50.4860, 30.3350, 2200.0, 2000.0, 0.0, 0.25)   # the Sviatoshyn woods
	forest_ll(50.5750, 30.4400, 3200.0, 1800.0, 0.0, 0.3)    # Mezhyhiria
	forest_ll(50.3750, 30.5100, 2500.0, 2300.0, 0.0, 0.22)   # Holosiiv forest
	forest_ll(50.3400, 30.4800, 1800.0, 1500.0, 0.0, 0.25)   # Feofaniia
	forest_ll(50.3180, 30.5400, 2600.0, 1800.0, 0.0, 0.25)   # Koncha-Zaspa
	forest_ll(50.4770, 30.7000, 3000.0, 4200.0, 0.0, 0.22)   # Bykivnia
	forest_ll(50.4150, 30.7000, 2000.0, 1700.0, 0.0, 0.25)   # the Darnytsia forest
	forest_ll(50.3650, 30.6300, 1700.0, 1100.0, 20.0, 0.3)   # the Osokorky meadows
	forest_ll(50.4740, 30.4450, 850.0, 650.0, 0.0, 0.2)      # Babyn Yar and the Syrets grove
	forest_ll(50.4135, 30.5630, 650.0, 600.0, 0.0, 0.15)     # the Hryshko botanical garden
	forest_ll(50.3950, 30.5480, 560.0, 480.0, 0.0, 0.15)     # Lysa Hora
	forest_ll(50.4580, 30.4150, 480.0, 380.0, 0.0, 0.15)     # Nyvky park
	forest_ll(50.4590, 30.6080, 480.0, 380.0, 0.0, 0.15)     # Victory park
	forest_ll(50.3790, 30.4760, 700.0, 600.0, 0.0, 0.15)     # the Expocentre
	forest_ll(50.4545, 30.4630, 430.0, 330.0, 0.0, 0.12)     # the zoo
	forest_ll(50.4170, 30.5060, 560.0, 460.0, 0.0, 0.12)     # Baikove
	forest_ll(50.4880, 30.3900, 800.0, 600.0, 0.0, 0.2)      # Berkovtsi


func zone_hook(map, x: float, z: float, wd: float, n: float) -> int:
	# the green right-bank Dnipro slopes from Podil down to Vydubychi (Volodymyrska hill,
	# Mariinsky park, the Lavra slopes)
	if z > -1350.0 and z < 4300.0 and wd < 420.0 + n * 90.0 and wd > 0.0 and x < bank(z) + 40.0:
		return Z_FOREST
	return -1


func _districts() -> void:
	# name, lat, lon, grid angle, block size, character, radius
	# --- the right bank
	district("Центр", 50.4470, 30.5220, 45.0, 150.0, "historic", 900.0)
	district("Старый Киев", 50.4545, 30.5130, 12.0, 140.0, "historic", 850.0)
	district("Подол", 50.4660, 30.5160, -22.0, 120.0, "podil", 1100.0)
	district("Липки", 50.4440, 30.5345, 32.0, 150.0, "pechersk", 800.0)
	district("Печерск", 50.4280, 30.5400, 20.0, 160.0, "pechersk", 1300.0)
	district("Зверинец", 50.4175, 30.5540, 10.0, 160.0, "mixed", 850.0)
	district("Лукьяновка", 50.4640, 30.4830, -10.0, 160.0, "mixed", 1300.0)
	district("Татарка", 50.4720, 30.4990, 5.0, 140.0, "khrush", 800.0)
	district("Шулявка", 50.4530, 30.4520, 5.0, 170.0, "west", 1300.0)
	district("Соломенка", 50.4310, 30.4830, -12.0, 160.0, "khrush", 1400.0)
	district("Чоколовка", 50.4270, 30.4520, 15.0, 170.0, "khrush", 1300.0)
	district("Отрадный", 50.4330, 30.4180, 0.0, 180.0, "khrush", 1400.0)
	district("Борщаговка", 50.4250, 30.3830, -18.0, 200.0, "panel", 2200.0)
	district("Южная Борщаговка", 50.4050, 30.4000, 10.0, 200.0, "panel", 1500.0)
	district("Святошин", 50.4570, 30.3700, 0.0, 190.0, "panel", 1700.0)
	district("Академгородок", 50.4670, 30.3520, 8.0, 190.0, "panel", 1200.0)
	district("Нивки", 50.4610, 30.4000, 8.0, 180.0, "khrush", 1400.0)
	district("Сырец", 50.4800, 30.4230, -5.0, 170.0, "mixed", 1300.0)
	district("Виноградарь", 50.5080, 30.4250, -8.0, 200.0, "panel", 1600.0)
	district("Куренёвка", 50.4860, 30.4690, 20.0, 150.0, "mixed", 1300.0)
	district("Приорка", 50.5010, 30.4560, 5.0, 130.0, "private", 1300.0)
	district("Минский массив", 50.5190, 30.4600, 0.0, 200.0, "panel", 1400.0)
	district("Оболонь", 50.5080, 30.4980, 30.0, 220.0, "panel", 2400.0)
	district("Петровка", 50.4860, 30.5030, 10.0, 220.0, "industrial", 1300.0)
	district("Рыбальский", 50.4770, 30.5290, 5.0, 180.0, "industrial", 650.0)
	district("Демиевка", 50.4050, 30.5200, 16.0, 170.0, "mixed", 1400.0)
	district("Голосеево", 50.3930, 30.4900, 0.0, 180.0, "panel", 1300.0)
	district("Теремки", 50.3690, 30.4530, -10.0, 210.0, "panel", 1700.0)
	district("Корчеватое", 50.3780, 30.5560, 25.0, 150.0, "mixed", 1200.0)
	district("Выдубичи", 50.4020, 30.5620, 20.0, 230.0, "industrial", 950.0)
	district("Жуляны", 50.3850, 30.4330, 0.0, 140.0, "private", 1400.0)
	district("Совки", 50.4120, 30.4750, 5.0, 140.0, "private", 1000.0)
	district("Пирогов", 50.3500, 30.5150, 0.0, 140.0, "private", 1300.0)
	# --- the left bank
	district("Левобережная", 50.4530, 30.5990, 0.0, 180.0, "new", 1100.0)
	district("Русановка", 50.4420, 30.5960, 0.0, 150.0, "panel", 700.0)
	district("Березняки", 50.4250, 30.6040, 10.0, 200.0, "panel", 1300.0)
	district("Дарница", 50.4460, 30.6300, -8.0, 170.0, "khrush", 1500.0)
	district("ДВРЗ", 50.4480, 30.6750, 0.0, 160.0, "khrush", 1100.0)
	district("Старая Дарница", 50.4330, 30.6400, 12.0, 160.0, "mixed", 1200.0)
	district("Новая Дарница", 50.4250, 30.6560, 5.0, 170.0, "khrush", 1200.0)
	district("Рембаза", 50.4160, 30.6750, 0.0, 230.0, "industrial", 1300.0)
	district("Харьковский массив", 50.4040, 30.6520, 12.0, 210.0, "panel", 1700.0)
	district("Позняки", 50.3980, 30.6300, 22.0, 210.0, "new", 1300.0)
	district("Осокорки", 50.3950, 30.6080, 10.0, 200.0, "new", 1200.0)
	district("Нижние Сады", 50.3780, 30.6200, 10.0, 140.0, "private", 1500.0)
	district("Бортничи", 50.3700, 30.6750, 5.0, 140.0, "private", 1800.0)
	district("Красный Хутор", 50.4040, 30.6900, 0.0, 150.0, "private", 1200.0)
	district("Воскресенка", 50.4780, 30.6060, 0.0, 180.0, "khrush", 1500.0)
	district("Радужный", 50.4810, 30.5890, 0.0, 200.0, "panel", 800.0)
	district("Троещина", 50.5150, 30.6050, 18.0, 230.0, "panel", 2700.0)
	district("Лесной массив", 50.4680, 30.6430, 0.0, 200.0, "panel", 1500.0)
	district("Комсомольский массив", 50.4600, 30.6250, 0.0, 190.0, "panel", 1000.0)
	district("Дарницкая промзона", 50.4520, 30.6560, -5.0, 240.0, "industrial", 1300.0)
	district("Троещина (село)", 50.5320, 30.5900, 10.0, 140.0, "private", 1200.0)
	# --- the suburbs
	district("Вишнёвое", 50.3880, 30.3700, 0.0, 170.0, "mixed", 1600.0)
	district("Софиевская Борщаговка", 50.4080, 30.3650, 0.0, 150.0, "private", 1400.0)
	district("Коцюбинское", 50.4880, 30.3330, 0.0, 170.0, "panel", 900.0)
	district("Чабаны", 50.3400, 30.4300, 0.0, 140.0, "private", 1500.0)
	district("Крюковщина", 50.3700, 30.3700, 0.0, 140.0, "private", 1300.0)
	district("Петропавловская Борщаговка", 50.4350, 30.3400, 0.0, 140.0, "private", 1300.0)
	district("Счастливое", 50.3350, 30.6800, 0.0, 140.0, "private", 1400.0)


func _routes() -> void:
	add_road_ll("проспект Победы", [[50.4425, 30.5210], [50.4440, 30.5100], [50.4475, 30.4940], [50.4510, 30.4700], [50.4545, 30.4500], [50.4575, 30.4250],
		[50.4585, 30.4000], [50.4572, 30.3700], [50.4560, 30.3400], [50.4550, 30.3100]], 14.0)
	add_road_ll("Северный мост", [[50.4880, 30.4700], [50.4890, 30.4950], [50.4925, 30.5150], [50.4936, 30.5355], [50.4945, 30.5560], [50.4960, 30.5780],
		[50.5000, 30.6000], [50.5040, 30.6250], [50.5080, 30.6500], [50.5150, 30.7000], [50.5200, 30.7500]], 13.0,
		[{"name": "Северный мост", "style": "cable_a", "target": true}, {"name": "мост через Десёнку", "style": "girder"}])
	add_road_ll("Подольский мост", [[50.4690, 30.5050], [50.4712, 30.5180], [50.4722, 30.5250], [50.4725, 30.5330], [50.4735, 30.5480], [50.4750, 30.5650],
		[50.4765, 30.5800], [50.4790, 30.6000], [50.4810, 30.6200]], 12.0,
		[{"name": "Гаванский мост", "style": "girder"}, {"name": "Подольский мост", "style": "arch", "target": true}, {"name": "мост через Десёнку", "style": "girder"}])
	add_road_ll("Броварской проспект", [[50.4408, 30.5565], [50.4418, 30.5640], [50.4425, 30.5740], [50.4437, 30.5825], [50.4480, 30.5920], [50.4518, 30.5985],
		[50.4560, 30.6130], [50.4610, 30.6300], [50.4650, 30.6460], [50.4700, 30.6650], [50.4780, 30.6900], [50.4900, 30.7300], [50.4950, 30.7500]], 14.0,
		[{"name": "Мост Метро", "style": "metro", "target": true}, {"name": "Русановский метромост", "style": "metro"}])
	add_road_ll("Мост Патона", [[50.4150, 30.5200], [50.4170, 30.5350], [50.4215, 30.5550], [50.4255, 30.5700], [50.4275, 30.5810], [50.4300, 30.5920],
		[50.4330, 30.6050], [50.4365, 30.6200], [50.4390, 30.6320]], 13.0,
		[{"name": "Мост Патона", "style": "girder", "target": true}])
	add_road_ll("Дарницкий мост", [[50.4120, 30.5640], [50.4145, 30.5770], [50.4155, 30.5890], [50.4175, 30.6010], [50.4215, 30.6130], [50.4260, 30.6260]], 12.0,
		[{"name": "Дарницкий мост", "style": "arch", "target": true}])
	add_road_ll("Южный мост", [[50.4020, 30.5350], [50.3990, 30.5500], [50.3962, 30.5700], [50.3950, 30.5880], [50.3960, 30.6060], [50.3975, 30.6200],
		[50.3985, 30.6400], [50.3960, 30.6700], [50.3900, 30.7000], [50.3850, 30.7500]], 14.0,
		[{"name": "Южный мост", "style": "cable", "target": true}])
	add_road_ll("Набережное шоссе", [[50.4640, 30.5262], [50.4590, 30.5285], [50.4530, 30.5318], [50.4470, 30.5430], [50.4415, 30.5560], [50.4340, 30.5670],
		[50.4270, 30.5735], [50.4180, 30.5785], [50.4080, 30.5790], [50.3990, 30.5760], [50.3850, 30.5650], [50.3650, 30.5600], [50.3400, 30.5600], [50.3100, 30.5650]], 12.0)
	add_road_ll("Голосеевский проспект", [[50.4330, 30.5170], [50.4200, 30.5200], [50.4060, 30.5190], [50.3950, 30.5080], [50.3850, 30.4850], [50.3700, 30.4600],
		[50.3550, 30.4400], [50.3300, 30.4150], [50.3100, 30.3950]], 13.0)
	add_road_ll("Окружная дорога", [[50.5100, 30.3700], [50.4950, 30.3650], [50.4680, 30.3560], [50.4500, 30.3600], [50.4300, 30.3700], [50.4100, 30.3850],
		[50.3920, 30.4150], [50.3750, 30.4400], [50.3660, 30.4580], [50.3640, 30.4900], [50.3620, 30.5200], [50.3650, 30.5500], [50.3680, 30.5600]], 13.0)
	add_road_ll("проспект Лобановского", [[50.4170, 30.5180], [50.4210, 30.4950], [50.4230, 30.4700], [50.4210, 30.4450], [50.4180, 30.4200], [50.4150, 30.3950]], 12.0)
	add_road_ll("Воздухофлотский проспект", [[50.4480, 30.4880], [50.4350, 30.4720], [50.4230, 30.4580], [50.4130, 30.4500]], 12.0)
	add_road_ll("Оболонский проспект", [[50.4890, 30.4950], [50.5000, 30.4960], [50.5150, 30.4930], [50.5300, 30.4850], [50.5500, 30.4700], [50.5800, 30.4500], [50.5900, 30.4450]], 12.0)
	add_road_ll("проспект Маяковского", [[50.4960, 30.5950], [50.5100, 30.6000], [50.5250, 30.6030], [50.5380, 30.6050]], 12.0)
	add_road_ll("Харьковское шоссе", [[50.4390, 30.6320], [50.4300, 30.6480], [50.4180, 30.6680], [50.4050, 30.6900], [50.3950, 30.7100], [50.3900, 30.7500]], 12.0)
	add_road_ll("улица Телиги", [[50.4590, 30.4480], [50.4720, 30.4500], [50.4800, 30.4600], [50.4880, 30.4700]], 12.0)
	add_road_ll("Гостомельское шоссе", [[50.4680, 30.3560], [50.4850, 30.3500], [50.5100, 30.3400], [50.5350, 30.3200]], 11.0)
	add_road_ll("Лесной проспект", [[50.4518, 30.5985], [50.4620, 30.6020], [50.4750, 30.6050], [50.4900, 30.6000], [50.4960, 30.5950]], 12.0)
	add_rail_ll("Юго-Западная железная дорога", [[50.3850, 30.3100], [50.3900, 30.3700], [50.4100, 30.4050], [50.4290, 30.4350], [50.4370, 30.4650],
		[50.4405, 30.4890], [50.4330, 30.5050], [50.4240, 30.5120], [50.4130, 30.5300], [50.4085, 30.5500], [50.4110, 30.5720], [50.4170, 30.5890],
		[50.4210, 30.6020], [50.4330, 30.6480], [50.4450, 30.6800], [50.4600, 30.7200], [50.4750, 30.7500]], 3, 10,
		{"name": "Дарницкий железнодорожный мост", "target": false})
	add_rail_ll("Северное кольцо", [[50.4290, 30.4350], [50.4420, 30.4130], [50.4560, 30.3960], [50.4680, 30.4060], [50.4790, 30.4330], [50.4860, 30.4700],
		[50.4862, 30.4980], [50.4868, 30.5380], [50.4880, 30.5700], [50.4850, 30.5900], [50.4700, 30.6020], [50.4520, 30.6120], [50.4400, 30.6350], [50.4330, 30.6480]], 2, 8,
		{"name": "Петровский железнодорожный мост", "target": false})
	bridges.append({"a": ll(50.4562, 30.5318), "b": ll(50.4562, 30.5405), "name": "Пешеходный мост", "style": "pedestrian"})


func _labels() -> void:
	var blue := Color(0.6, 0.85, 1.0, 0.85)
	var green := Color(0.6, 1.0, 0.7, 0.8)
	var isle := Color(0.7, 1.0, 0.8, 0.8)
	label_ll("ДНЕПР", 50.5200, 30.5310, 72, blue)
	label_ll("ДНЕПР", 50.3700, 30.5760, 72, blue)
	label_ll("Десна", 50.5700, 30.6200, 52, blue)
	label_ll("Гавань", 50.4780, 30.5225, 40, blue)
	label_ll("Труханов остров", 50.4680, 30.5510, 48, isle)
	label_ll("Гидропарк", 50.4440, 30.5745, 44, isle)
	label_ll("Муромец", 50.5080, 30.5540, 44, isle)
	label_ll("Жуков остров", 50.3450, 30.5760, 40, isle)
	label_ll("Пуща-Водица", 50.5300, 30.3700, 60, green)
	label_ll("Голосеевский лес", 50.3750, 30.5100, 60, green)
	label_ll("Быковня", 50.4770, 30.7000, 60, green)
	label_ll("Феофания", 50.3400, 30.4800, 44, green)
	label_ll("Ботанический сад", 50.4135, 30.5630, 36, green)


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
	L.lattice_tower(map, ll3(50.4712, 30.4532), "Киевская телебашня", 385.0)
	L.station(map, ll3(50.4405, 30.4890), 8.0, "Центральный вокзал", Color(0.95, 0.86, 0.6), 46.0)
	L.station(map, ll3(50.4330, 30.6480), 20.0, "вокзал Дарница", Color(0.82, 0.86, 0.9), 30.0)
	L.airport(map, ll3(50.4017, 30.4497), 190.0, "Аэропорт Жуляны", 2300.0)
	# the cargo port in the Harbour, barges at its quay
	var hp := ll3(50.4775, 30.5247)
	L.port(map, hp, -92.0, "Речной порт", 5, "")
	L.ship(map, ll3(50.4800, 30.5222), 94.0, 86.0, "barge", "баржа")
	L.ship(map, ll3(50.4745, 30.5238), 100.0, 96.0, "bulk", "речной сухогруз")
	# the River Station on Poshtova square
	var rs := L.group(ll3(50.4595, 30.5268), 62.0)
	L.block(map, rs, Vector3.ZERO, Vector2(46, 12), 14.0, 1, Color(0.95, 0.95, 0.92), "Речной вокзал")
	L.box(rs, Vector3(8, 26, 8), Vector3(0, 13, 0), L.lit(Color(0.95, 0.95, 0.92), 0.2))
	L.cyl(rs, 0.0, 1.2, 9.0, Vector3(0, 30.5, 0), L.gold(), 8)
	map.reserve(rs.position.x, rs.position.z, 52.0)
	L.ferris_wheel(map, ll3(50.4660, 30.5170), 20.0, 21.5, "колесо обозрения на Подоле")
	_new_landmarks(map)


func _power_plants(map) -> void:
	L.power_plant(map, ll3(50.3925, 30.5690), 20.0, "ТЭЦ-5", 2, 3, 180.0)
	L.power_plant(map, ll3(50.5320, 30.6630), -10.0, "ТЭЦ-6", 2, 2, 270.0)
	L.power_plant(map, ll3(50.4480, 30.6450), -8.0, "Дарницкая ТЭЦ", 1, 2, 120.0)
	L.power_plant(map, ll3(50.4330, 30.4340), 5.0, "ТЭЦ-4", 1, 2, 150.0)


## The Motherland: a 62 m steel figure on a 40 m pedestal over the Dnipro slopes (102 m in all).
func _motherland(map) -> void:
	var p := ll3(50.4266, 30.5630)
	var g := L.group(p, -20.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.85, 0.88)
	steel.metallic = 0.9
	steel.roughness = 0.22
	steel.emission_enabled = true
	steel.emission = Color(0.75, 0.82, 0.95)
	steel.emission_energy_multiplier = 0.22
	var stone := L.lit(Color(0.62, 0.6, 0.58), 0.08)
	# the museum under the monument and the conical pedestal
	L.cyl(g, 34.0, 38.0, 10.0, Vector3(0, 5, 0), stone, 32)
	L.cyl(g, 15.0, 24.0, 18.0, Vector3(0, 19, 0), stone, 28)
	L.cyl(g, 7.0, 11.0, 12.0, Vector3(0, 34, 0), stone, 20)
	# figure: gown, torso, head
	L.cyl(g, 3.6, 7.0, 27.0, Vector3(0, 53.5, 0), steel, 18)
	L.cyl(g, 2.9, 3.6, 11.0, Vector3(0, 72.5, 0), steel, 14)
	L.sph(g, 2.5, Vector3(0, 80.0, 0), steel)
	# raised sword arm and shield arm
	L.beam(g, Vector3(2.0, 75, 0), Vector3(6.2, 86, 0.6), 1.7, steel)
	L.beam(g, Vector3(6.2, 86, 0.6), Vector3(7.6, 102, 0.9), 0.8, steel)
	L.beam(g, Vector3(-2.0, 75, 0), Vector3(-6.8, 82, 0.6), 1.7, steel)
	var shield := L.cyl(g, 6.5, 6.5, 0.7, Vector3(-8.2, 86, 0.7), steel, 22)
	shield.rotation_degrees = Vector3(0, 0, 80)
	L.fp(map, g, Vector3.ZERO, Vector2(24, 24), 40.0, "монумент «Родина-мать»")
	L.fp(map, g, Vector3.ZERO, Vector2(6, 6), 92.0, "монумент «Родина-мать»")
	L.light(map, g, Vector3(7.6, 103, 0.9))
	map.reserve(p.x, p.z, 70.0)


## The Kyiv Pechersk Lavra: the walled Upper Lavra with the Dormition Cathedral and the 96.5 m
## Great Bell Tower; Vydubychi monastery further south.
func _lavra(map) -> void:
	var p := ll3(50.4346, 30.5573)
	var g := L.group(p, -15.0)
	var white := L.lit(Color(0.95, 0.94, 0.9), 0.16)
	var green := L.lit(Color(0.35, 0.62, 0.5), 0.1)
	for s in [Vector3(0, 3.5, -120), Vector3(0, 3.5, 120)]:
		L.box(g, Vector3(300, 7, 2.4), s, white)
	for s in [Vector3(-150, 3.5, 0), Vector3(150, 3.5, 0)]:
		L.box(g, Vector3(2.4, 7, 240), s, white)
	# Dormition Cathedral with seven golden domes
	L.box(g, Vector3(40, 24, 34), Vector3(20, 12, 10), white)
	L.domed_drum(g, Vector3(20, 24, 10), 6.0, 9.0, white, L.gold())
	for s in [Vector3(8, 24, -1), Vector3(32, 24, -1), Vector3(8, 24, 21), Vector3(32, 24, 21), Vector3(3, 24, 10), Vector3(37, 24, 10)]:
		L.domed_drum(g, s, 2.8, 4.6, white, L.gold())
	L.fp(map, g, Vector3(20, 0, 10), Vector2(20, 17), 44.0, "Успенский собор Лавры")
	# the Great Lavra Bell Tower: four tiers and a golden dome
	var bt := Vector3(-34, 0, 2)
	L.cyl(g, 14.0, 14.5, 26.0, bt + Vector3(0, 13, 0), white, 24)
	L.cyl(g, 11.5, 12.0, 22.0, bt + Vector3(0, 37, 0), green, 24)
	L.cyl(g, 9.5, 10.0, 18.0, bt + Vector3(0, 57, 0), white, 24)
	L.cyl(g, 7.5, 8.0, 12.0, bt + Vector3(0, 72, 0), green, 20)
	L.onion(g, bt + Vector3(0, 78, 0), 7.0, L.gold())
	L.fp(map, g, bt, Vector2(14, 14), 90.0, "Большая Лаврская колокольня")
	L.light(map, g, bt + Vector3(0, 98, 0))
	# Trinity Gate church, the Refectory and the monastery buildings
	L.box(g, Vector3(18, 14, 12), Vector3(-146, 7, 0), white)
	L.domed_drum(g, Vector3(-146, 14, 0), 3.0, 4.0, white, L.gold())
	L.box(g, Vector3(46, 14, 24), Vector3(40, 7, 70), white)
	L.sph(g, 11.0, Vector3(40, 14, 70), L.gold(), Vector3(1, 0.6, 1))
	L.fp(map, g, Vector3(40, 0, 70), Vector2(23, 12), 22.0, "Трапезная церковь Лавры")
	for s in [Vector3(-90, 0, 80), Vector3(-80, 0, -80), Vector3(90, 0, -70), Vector3(110, 0, 40)]:
		L.box(g, Vector3(60, 11, 14), s + Vector3(0, 5.5, 0), white)
		L.fp(map, g, s, Vector2(30, 7), 11.0, "корпус Лавры")
	map.reserve(p.x, p.z, 205.0)
	# Vydubychi monastery further south along the river
	var vp := ll3(50.4165, 30.5672)
	var vg := L.group(vp, 10.0)
	L.box(vg, Vector3(18, 16, 24), Vector3(0, 8, 0), white)
	var vdome := Fx.solid(Color(0.25, 0.5, 0.35), 0.35, 0.6)
	L.domed_drum(vg, Vector3(0, 16, 0), 3.4, 5.0, white, vdome)
	L.box(vg, Vector3(8, 30, 8), Vector3(0, 15, -24), white)
	L.onion(vg, Vector3(0, 30, -24), 2.8, vdome)
	L.fp(map, vg, Vector3(0, 0, -6), Vector2(10, 20), 30.0, "Выдубицкий монастырь")
	map.reserve(vp.x, vp.z, 40.0)


# --- Maidan, Khreshchatyk, Arch of Freedom -----------------------------------------------------------
func _center(map) -> void:
	var white := L.lit(Color(0.94, 0.94, 0.92), 0.25)
	# Independence Monument: a 61 m column with the golden Berehynia
	var mp := ll3(50.4501, 30.5241)
	var g := L.column(map, mp, "монумент Независимости", 46.0)
	g.rotation_degrees.y = 45.0
	# glass domes of the underground mall + fountains
	for s in [Vector3(-24, 0, 20), Vector3(24, 0, 20), Vector3(0, 0, 34)]:
		L.sph(g, 5.0, s, Fx.glow(Color(0.5, 0.8, 1.0), 0.5), Vector3(1, 0.5, 1))
	map.reserve(mp.x, mp.z, 95.0)
	L.target(map, mp + Vector3(0, 2, 0), "Центр (Майдан)", "center")
	# Hotel Ukraina: the stepped Stalinist high-rise on the hill above the Maidan (66 m)
	var hpos := ll3(50.4488, 30.5271)
	var h := L.group(hpos, 45.0)
	var cream := Color(0.9, 0.86, 0.76)
	for spec in [[Vector2(42, 12), 34.0], [Vector2(26, 11), 48.0], [Vector2(12, 10), 58.0]]:
		L.block(map, h, Vector3.ZERO, spec[0], spec[1], 1, cream, "гостиница «Украина»")
	L.cyl(h, 0.0, 1.8, 9.0, Vector3(0, 62.5, 0), L.gold(), 8)
	L.light(map, h, Vector3(0, 67.5, 0))
	map.reserve(hpos.x, hpos.z, 46.0)
	# Trade Unions House with the LED ticker and clock tower, the City Council on Khreshchatyk
	var tpos := ll3(50.4508, 30.5253)
	var tu := L.group(tpos, 45.0)
	L.block(map, tu, Vector3.ZERO, Vector2(36, 12), 30.0, 1, Color(0.85, 0.82, 0.74), "Дом профсоюзов")
	L.box(tu, Vector3(60, 2.6, 0.3), Vector3(0, 32, 12.2), Fx.glow(Color(1.0, 0.25, 0.2), 1.6))
	L.box(tu, Vector3(8, 18, 8), Vector3(-28, 39, 0), white)
	map.reserve(tpos.x, tpos.z, 40.0)
	var cpos := ll3(50.4465, 30.5207)
	var cc := L.group(cpos, 45.0)
	L.block(map, cc, Vector3.ZERO, Vector2(50, 12), 38.0, 1, Color(0.92, 0.9, 0.84), "Киевсовет")
	L.box(cc, Vector3(10, 14, 10), Vector3(0, 45, 0), white)
	L.box(cc, Vector3(5.5, 5.5, 0.3), Vector3(0, 47, 5.1), Fx.glow(Color(1.0, 0.95, 0.8), 1.4))
	map.reserve(cpos.x, cpos.z, 54.0)
	# the Arch of Freedom of the Ukrainian People over the Dnipro slopes (35 m, titanium)
	var ap := ll3(50.4543, 30.5300)
	var ag := L.group(ap, 90.0)
	var arch := MeshInstance3D.new()
	arch.mesh = Fx.ring_mesh(30.0, 2.6)
	arch.material_override = Fx.glow(Color(0.65, 0.8, 1.0), 0.9)
	arch.rotation_degrees = Vector3(90, 0, 0)
	arch.position = Vector3(0, 5, 0)
	ag.add_child(arch)
	L.box(ag, Vector3(5, 8, 4), Vector3(0, 4, 0), Fx.solid(Color(0.55, 0.45, 0.35), 0.4, 0.7))
	L.fp(map, ag, Vector3.ZERO, Vector2(31, 3), 35.0, "Арка Свободы")
	map.reserve(ap.x, ap.z, 40.0)


# --- Cathedrals of Old Kyiv ---------------------------------------------------------------------------
func _cathedrals(map) -> void:
	var white := L.lit(Color(0.96, 0.96, 0.92), 0.2)
	var green_dome := Fx.solid(Color(0.26, 0.52, 0.38), 0.35, 0.6)
	var blue_wall := L.lit(Color(0.36, 0.64, 0.86), 0.18)
	# St Sophia Cathedral: 13 domes, the big one golden; its 76 m bell tower
	var sp := ll3(50.4529, 30.5143)
	var s := L.group(sp, 12.0)
	L.box(s, Vector3(40, 16, 32), Vector3(0, 8, 0), white)
	L.box(s, Vector3(54, 9, 26), Vector3(0, 4.5, 0), white)
	L.domed_drum(s, Vector3(0, 16, 0), 4.6, 8.0, white, L.gold())
	for p in [Vector3(-10, 16, -8), Vector3(10, 16, -8), Vector3(-10, 16, 8), Vector3(10, 16, 8), Vector3(-17, 16, 0), Vector3(17, 16, 0), Vector3(0, 16, -12), Vector3(0, 16, 12)]:
		L.domed_drum(s, p, 2.1, 3.4, white, green_dome)
	for p in [Vector3(-23, 9, -10), Vector3(23, 9, -10), Vector3(-23, 9, 10), Vector3(23, 9, 10)]:
		L.domed_drum(s, p, 1.6, 2.2, white, green_dome)
	L.fp(map, s, Vector3.ZERO, Vector2(27, 16), 29.0, "Софийский собор")
	var bt := L.group(sp + Vector3(110, 0, 18).rotated(Vector3.UP, deg_to_rad(12.0)), 12.0)
	for spec in [[Vector3(18, 22, 18), 11.0, white], [Vector3(15, 18, 15), 31.0, blue_wall], [Vector3(12, 14, 12), 47.0, white], [Vector3(9, 10, 9), 59.0, blue_wall]]:
		L.box(bt, spec[0], Vector3(0, spec[1], 0), spec[2])
	L.onion(bt, Vector3(0, 64, 0), 4.2, L.gold())
	L.fp(map, bt, Vector3.ZERO, Vector2(9, 9), 74.0, "колокольня Софии")
	L.light(map, bt, Vector3(0, 78, 0))
	map.reserve(sp.x + 40.0, sp.z, 120.0)
	# Bohdan Khmelnytsky monument on Sofiiska square
	var bk := L.group(ll3(50.4535, 30.5165), 30.0)
	L.box(bk, Vector3(6, 5, 10), Vector3(0, 2.5, 0), Fx.solid(Color(0.4, 0.38, 0.36)))
	L.box(bk, Vector3(2.2, 4, 7), Vector3(0, 7, 0), Fx.solid(Color(0.2, 0.3, 0.26), 0.4, 0.7))
	L.box(bk, Vector3(1.2, 4, 1.2), Vector3(0, 10.5, 0.5), Fx.solid(Color(0.2, 0.3, 0.26), 0.4, 0.7))
	# St Michael's Golden-Domed Monastery: sky-blue walls, golden domes
	L.cathedral(map, ll3(50.4557, 30.5228), 12.0, "Михайловский Златоверхий монастырь", Color(0.36, 0.64, 0.86), L.gold(), 1.25, 6, true)
	# St Andrew's Church on its hill above Podil (46 m with the stylobate)
	var apos := ll3(50.4590, 30.5179)
	var a := L.group(apos, -20.0)
	L.box(a, Vector3(30, 14, 30), Vector3(0, 7, 0), Fx.solid(Color(0.5, 0.48, 0.46), 0.9))
	var aw := L.lit(Color(0.62, 0.8, 0.9), 0.2)
	L.box(a, Vector3(12, 16, 24), Vector3(0, 22, 0), aw)
	L.box(a, Vector3(24, 16, 12), Vector3(0, 22, 0), aw)
	L.domed_drum(a, Vector3(0, 30, 0), 4.2, 6.0, aw, green_dome)
	for p in [Vector3(-9, 14, -9), Vector3(9, 14, -9), Vector3(-9, 14, 9), Vector3(9, 14, 9)]:
		L.cyl(a, 1.6, 1.6, 16.0, p + Vector3(0, 8, 0), aw, 10)
		L.onion(a, p + Vector3(0, 16, 0), 1.8, green_dome)
	L.fp(map, a, Vector3.ZERO, Vector2(15, 15), 44.0, "Андреевская церковь")
	map.reserve(apos.x, apos.z, 34.0)
	# St Volodymyr's Cathedral: yellow walls, dark domes (49 m)
	L.cathedral(map, ll3(50.4447, 30.5088), 8.0, "Владимирский собор", Color(0.96, 0.84, 0.5), Fx.solid(Color(0.1, 0.16, 0.3), 0.3, 0.7), 1.4, 6, false)
	# the Golden Gate
	var gpos := ll3(50.4488, 30.5133)
	var gg := L.group(gpos, 12.0)
	var brick := Fx.solid(Color(0.62, 0.42, 0.32), 0.9)
	L.box(gg, Vector3(8, 15, 16), Vector3(-8, 7.5, 0), brick)
	L.box(gg, Vector3(8, 15, 16), Vector3(8, 7.5, 0), brick)
	L.box(gg, Vector3(24, 5, 16), Vector3(0, 17.5, 0), brick)
	L.box(gg, Vector3(11, 7, 10), Vector3(0, 23.5, 0), L.lit(Color(0.95, 0.94, 0.9), 0.2))
	L.onion(gg, Vector3(0, 27, 0), 2.8, L.gold())
	L.fp(map, gg, Vector3.ZERO, Vector2(12, 8), 27.0, "Золотые ворота")
	map.reserve(gpos.x, gpos.z, 26.0)
	# the National Opera
	var opos := ll3(50.4467, 30.5123)
	var op := L.group(opos, 12.0)
	var opc := L.lit(Color(0.93, 0.87, 0.74), 0.2)
	L.box(op, Vector3(62, 24, 84), Vector3(0, 12, 0), opc)
	L.box(op, Vector3(40, 12, 40), Vector3(0, 30, 8), opc)
	L.sph(op, 17.0, Vector3(0, 36, 8), Fx.solid(Color(0.3, 0.45, 0.4), 0.4, 0.6), Vector3(1.1, 0.45, 1.1))
	L.fp(map, op, Vector3.ZERO, Vector2(31, 42), 38.0, "Национальная опера")
	map.reserve(opos.x, opos.z, 56.0)
	# the red building of Shevchenko University
	L.classical(map, ll3(50.4419, 30.5112), 12.0, "Красный корпус университета", Vector3(144, 22, 34), Color(0.72, 0.16, 0.12))


# --- Government quarter (Lypky) ---------------------------------------------------------------------------
func _government(map) -> void:
	# the Verkhovna Rada with its glass dome
	var rp := ll3(50.4474, 30.5366)
	var r := L.group(rp, 32.0)
	L.block(map, r, Vector3.ZERO, Vector2(38, 30), 22.0, 1, Color(0.86, 0.84, 0.78), "Верховная Рада")
	L.sph(r, 18.0, Vector3(0, 22, 0), Fx.glow(Color(0.55, 0.75, 0.9), 0.35), Vector3(1, 0.5, 1))
	L.box(r, Vector3(0.25, 10, 0.25), Vector3(0, 35, 0), Fx.solid(Color(0.3, 0.3, 0.3)))
	L.box(r, Vector3(5, 1.6, 0.1), Vector3(2.5, 38.8, 0), Fx.glow(Color(0.0, 0.36, 0.73), 0.8))
	L.box(r, Vector3(5, 1.6, 0.1), Vector3(2.5, 37.2, 0), Fx.glow(Color(1.0, 0.84, 0.0), 0.8))
	map.reserve(rp.x, rp.z, 56.0)
	# Mariinsky Palace: turquoise baroque
	var mpos := ll3(50.4484, 30.5378)
	var mp := L.group(mpos + Vector3(60, 0, -60), 32.0)
	var turq := L.lit(Color(0.34, 0.72, 0.7), 0.2)
	L.box(mp, Vector3(100, 15, 22), Vector3(0, 7.5, 0), turq)
	L.box(mp, Vector3(100.6, 1.2, 22.6), Vector3(0, 15, 0), L.lit(Color(0.95, 0.95, 0.92), 0.2))
	for sx in [-42.0, 42.0]:
		L.box(mp, Vector3(16, 15, 44), Vector3(sx, 7.5, 16), turq)
	L.sph(mp, 5.0, Vector3(0, 16, 0), Fx.solid(Color(0.3, 0.55, 0.45), 0.4, 0.6), Vector3(1, 0.8, 1))
	L.fp(map, mp, Vector3(0, 0, 10), Vector2(50, 24), 19.0, "Мариинский дворец")
	map.reserve(mp.position.x, mp.position.z, 62.0)
	# the Cabinet of Ministers: a huge concave Stalinist block (58 m)
	var cpos := ll3(50.4477, 30.5340)
	var cm := L.group(cpos, 32.0)
	for spec in [[Vector3(0, 0, 0), Vector2(60, 12), 58.0], [Vector3(-66, 0, 22), Vector2(12, 30), 46.0], [Vector3(66, 0, 22), Vector2(12, 30), 46.0]]:
		L.block(map, cm, spec[0], spec[1], spec[2], 1, Color(0.72, 0.7, 0.64), "Кабинет Министров")
	map.reserve(cpos.x, cpos.z, 86.0)
	L.target(map, cpos + Vector3(0, 28, 0), "Правительственный квартал", "gov")
	# the Office of the President (Bankova)
	var bp := ll3(50.4455, 30.5282)
	var bk := L.group(bp, 45.0)
	L.block(map, bk, Vector3.ZERO, Vector2(46, 16), 30.0, 1, Color(0.68, 0.68, 0.66), "Офис Президента")
	map.reserve(bp.x, bp.z, 52.0)


# --- Stadium and skyscrapers ------------------------------------------------------------------------
func _towers_and_stadium(map) -> void:
	L.stadium(map, ll3(50.4334, 30.5217), 16.0, "НСК «Олимпийский»", 150.0, 125.0, 42.0)
	var t := func(lat: float, lon: float, hs: Vector2, rot: float, h: float, style: int, col: Color, tname: String) -> void:
		L.tower(map, ll(lat, lon), hs, rot, h, style, col, tname)
	t.call(50.4388, 30.5233, Vector2(24, 20), 20.0, 141.0, 2, Color(0.28, 0.38, 0.5), "БЦ «Гулливер»")
	t.call(50.4368, 30.5176, Vector2(20, 20), 20.0, 136.0, 2, Color(0.32, 0.36, 0.42), "БЦ «Парус»")
	t.call(50.4380, 30.5380, Vector2(22, 16), 20.0, 168.0, 0, Color(0.9, 0.88, 0.82), "Кловский небоскрёб")
	t.call(50.4380, 30.4880, Vector2(18, 18), 5.0, 116.0, 2, Color(0.26, 0.34, 0.44), "БЦ «101 Tower»")
	t.call(50.4270, 30.5370, Vector2(18, 16), 20.0, 123.0, 2, Color(0.3, 0.36, 0.42), "ЖК «Jack House»")
	t.call(50.4330, 30.5130, Vector2(18, 16), 45.0, 110.0, 0, Color(0.86, 0.62, 0.42), "ЖК «Chicago Central House»")
	t.call(50.4460, 30.5060, Vector2(18, 16), 12.0, 100.0, 2, Color(0.3, 0.4, 0.48), "отель «Хилтон»")
	for k in 3:
		t.call(50.4165 + k * 0.0006, 30.5500 + k * 0.0009, Vector2(16, 16), 10.0, 125.0 + k * 6.0, 0, Color(0.92, 0.9, 0.86), "ЖК «Taryan Towers»")
	t.call(50.4350, 30.5960, Vector2(18, 16), 0.0, 112.0, 2, Color(0.3, 0.4, 0.5), "ЖК «Silver Breeze»")
	t.call(50.4505, 30.4865, Vector2(20, 18), -10.0, 128.0, 2, Color(0.24, 0.32, 0.42), "«Sky Towers»")
	# the Gulliver mall at the foot of its tower
	var gp := L.group(ll3(50.4388, 30.5233), 20.0)
	L.box(gp, Vector3(90, 22, 56), Vector3(0, 11, 44), L.lit(Color(0.4, 0.45, 0.55), 0.15))
	L.fp(map, gp, Vector3(0, 0, 44), Vector2(45, 28), 22.0, "ТРЦ «Гулливер»")
	map.reserve(gp.position.x, gp.position.z + 30.0, 70.0)


func _new_landmarks(map) -> void:
	# the Palace of Sports near Bessarabka
	L.classical(map, ll3(50.4375, 30.5220), 45.0, "Дворец спорта", Vector3(138, 24, 78), Color(0.72, 0.76, 0.8), null, false)
	# Hotel "Salut": the round tower on a column above the Glory park
	var sp := ll3(50.4410, 30.5480)
	var sl := L.group(sp, 0.0)
	var sc := L.lit(Color(0.85, 0.85, 0.82), 0.2)
	L.cyl(sl, 8.0, 9.0, 16.0, Vector3(0, 8, 0), sc, 16)
	L.cyl(sl, 17.0, 14.0, 20.0, Vector3(0, 26, 0), sc, 24)
	L.cyl(sl, 17.3, 17.3, 1.6, Vector3(0, 30, 0), Fx.glow(Color(1.0, 0.85, 0.6), 1.0), 24)
	L.fp(map, sl, Vector3.ZERO, Vector2(16, 16), 36.0, "гостиница «Салют»")
	map.reserve(sp.x, sp.z, 24.0)
	# the International Exhibition Centre on the Brovarskyi avenue
	var ep := ll(50.4520, 30.5950)
	map.add_building(ep, Vector2(110, 60), 0.0, 24.0, 2, Color(0.28, 0.38, 0.5), PUB, 0.0, Color(), "Международный выставочный центр")
	for i in 8:
		map.add_light(Vector3(ep.x - 98.0 + i * 28.0, 24.8, ep.y), Color(0.4, 0.8, 1.0), false, 2.2, 0.003)
	map.reserve(ep.x, ep.y, 130.0)
	# the Expocentre (VDNH): the main pavilion with its spire at the end of the alley
	var vp := ll3(50.3800, 30.4780)
	var vd := L.classical(map, vp, 0.0, "ВДНХ", Vector3(110, 26, 40), Color(0.94, 0.9, 0.8), Fx.solid(Color(0.8, 0.7, 0.4), 0.4, 0.5))
	L.cyl(vd, 0.0, 2.2, 30.0, Vector3(0, 50, 0), L.gold(), 8)
	L.light(map, vd, Vector3(0, 66, 0))
