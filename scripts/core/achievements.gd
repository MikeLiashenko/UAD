extends RefCounted
## Achievements: marks of what the player has done, kept for good across every world in
## user://achievements.cfg. About a hundred and fifty of them in eight sections — the fight, every
## kind of target, every air defence system, days and cities, strikes on the enemy, the city's own
## services, the budget and the arsenal, special ones (a match on a server, the training range …).
## Most are written once as a family (the first kill of each target, the first kill of each
## system, each strike weapon on target, …) and laid out by all(); the rest are made by hand.
## The HUD scans for new ones once a second (scan()); the morning report brings the night-long ones
## (night_done()); a few are earned by the code where they happen (earn()). A new one is
## announced with a toast; the main menu's "Achievements" screen lists them all by section.
##
## Test runs never write the player's file: `dry` (set by main for every run with --quit-at or
## --autotest) keeps everything in memory.

const Strikes = preload("res://scripts/game/strikes.gd")
const PATH := "user://achievements.cfg"

## Sections of the screen, in order: [id, title].
const CATS := [["battle", "БОЙ"], ["targets", "ЦЕЛИ"], ["systems", "СИСТЕМЫ ПВО"], ["campaign", "ДНИ, КАМПАНИЯ И ГОРОДА"],
	["strikes", "УДАРЫ ПО ПРОТИВНИКУ"], ["service", "ГОРОД И СЛУЖБЫ"], ["economy", "БЮДЖЕТ И АРСЕНАЛ"], ["special", "ОСОБЫЕ"]]
const CITIES := ["kyiv", "kharkiv", "dnipro", "odesa"]
const CITY_NAMES := {"kyiv": "Киев", "kharkiv": "Харьков", "dnipro": "Днепр", "odesa": "Одесса"}

## Made by hand: [id, icon, section, name, how it is earned, condition]. A condition is
## [kind, …]: stat (GS.stats key ≥ n), day, money, units (systems owned), unit (one owned), site
## (struck: state not ok), rear_all, silence, realism_day, won, won_hard, city_day (furthest day
## in a city, any world), city_won, all_cities, own_city, crews_full, camo, intact (city whole on
## that day), online (players), host, videos, meta (achievements earned), event (earned in code).
const HAND := [
	["first_blood", "🎯", "battle", "Первый сбитый", "Сбейте первую цель.", ["stat", "kills", 1]],
	["kills_10", "🔟", "battle", "Десятка", "", ["stat", "kills", 10]],
	["kills_50", "🎖", "battle", "Полсотни", "", ["stat", "kills", 50]],
	["kills_100", "💯", "battle", "Сотня", "", ["stat", "kills", 100]],
	["kills_250", "🥉", "battle", "Четверть тысячи", "", ["stat", "kills", 250]],
	["kills_500", "🛡", "battle", "Небесный щит", "", ["stat", "kills", 500]],
	["kills_1000", "🥈", "battle", "Тысяча", "", ["stat", "kills", 1000]],
	["kills_2500", "🥇", "battle", "Легенда ПВО", "", ["stat", "kills", 2500]],
	["clean_night", "✨", "battle", "Чистое небо", "Ночь без единого прилёта по городу, сбито не меньше 10 целей.", ["event"]],
	["clean_5", "🌙", "battle", "Пять спокойных ночей", "Пять ночей без единого прилёта по городу в одном мире.", ["stat", "clean_nights", 5]],
	["clean_10", "🌌", "battle", "Купол", "Десять ночей без единого прилёта по городу в одном мире.", ["stat", "clean_nights", 10]],
	["night_30", "🔥", "battle", "Жаркая ночь", "Сбейте 30 целей за одну ночь.", ["event"]],
	["night_50", "☄", "battle", "Огненный шторм", "Сбейте 50 целей за одну ночь.", ["event"]],
	["rams_1", "🛩", "battle", "Первый таран", "Дрон-перехватчик таранит цель.", ["stat", "rams", 1]],
	["rams_10", "🛩", "battle", "Таран", "10 таранов дронами-перехватчиками.", ["stat", "rams", 10]],
	["rams_50", "🛩", "battle", "Рой перехватчиков", "50 таранов дронами-перехватчиками.", ["stat", "rams", 50]],
	["drones_50", "📡", "battle", "Пилот смены", "50 вылетов дронов-перехватчиков.", ["stat", "drones", 50]],
	["f16_1", "✈", "battle", "Воздушный бой", "Сбейте цель с F-16.", ["stat", "f16_kills", 1]],
	["f16_10", "✈", "battle", "Ас", "Сбейте 10 целей с F-16.", ["stat", "f16_kills", 10]],
	["f16_25", "✈", "battle", "Призрак Киева", "Сбейте 25 целей с F-16.", ["stat", "f16_kills", 25]],
	["splash_50", "🌊", "battle", "Обломки — в реку", "50 обломков упали в воду, а не на дома.", ["stat", "splash", 50]],
	["splash_200", "🌊", "battle", "Лоцман обломков", "200 обломков упали в воду.", ["stat", "splash", 200]],

	["week", "📅", "campaign", "Неделя обороны", "", ["day", 8]],
	["day_2", "🌅", "campaign", "Первая ночь позади", "", ["day", 2]],
	["day_3", "☕", "campaign", "Втянулись", "", ["day", 3]],
	["day_5", "🗓", "campaign", "Пятидневка", "", ["day", 5]],
	["day_10", "🔟", "campaign", "Декада", "", ["day", 10]],
	["day_20", "🏰", "campaign", "Двадцать ночей", "", ["day", 20]],
	["day_30", "🌕", "campaign", "Месяц в небе", "", ["day", 30]],
	["day_50", "🏛", "campaign", "Полсотни ночей", "", ["day", 50]],
	["campaign", "🏅", "campaign", "Выстояли", "Пройдите кампанию — все 15 ночей.", ["won"]],
	["won_hard", "💀", "campaign", "Железный купол", "Пройдите кампанию на высокой сложности.", ["won_hard"]],
	["all_cities", "🗺", "campaign", "Все четыре города", "Доживите до 5-го дня в Киеве, Харькове, Днепре и Одессе.", ["all_cities"]],
	["all_won", "👑", "campaign", "Хранитель городов", "Пройдите кампанию во всех четырёх городах.", ["all_won"]],
	["own_city", "✏", "campaign", "Свой город", "Доживите до 5-го дня в городе, нарисованном в редакторе.", ["own_city", 5]],
	["realism", "🎖", "campaign", "MaxRealism", "Переживите три ночи в мире MaxRealism.", ["realism_day", 4]],
	["realism_7", "🎖", "campaign", "Неделя на позиции", "Переживите семь ночей в мире MaxRealism.", ["realism_day", 8]],
	["realism_won", "🎗", "campaign", "Всё по-настоящему", "Пройдите кампанию в мире MaxRealism.", ["realism_won"]],
	["intact_10", "🏙", "campaign", "Ни царапины", "Город цел на 100 % на 10-й день.", ["intact", 10]],

	["first_strike", "🚀", "strikes", "Ответный ход", "Первый удар по точке пуска в цель.", ["stat", "strike_hits", 1]],
	["strike_hits_10", "🎯", "strikes", "Меткая рука", "10 ударов по противнику в цель.", ["stat", "strike_hits", 10]],
	["strike_hits_50", "🎯", "strikes", "Снайпер дальнего действия", "50 ударов по противнику в цель.", ["stat", "strike_hits", 50]],
	["strikes_25", "🛰", "strikes", "Дальняя рука", "25 ударов по противнику в одном мире.", ["stat", "strikes", 25]],
	["strikes_100", "🛰", "strikes", "Глубокий удар", "100 ударов по противнику в одном мире.", ["stat", "strikes", 100]],
	["sites_5", "💥", "strikes", "Тишина на площадках", "Уничтожьте 5 точек пуска.", ["stat", "sites_out", 5]],
	["sites_25", "💥", "strikes", "Выжженная земля", "Уничтожьте 25 точек пуска.", ["stat", "sites_out", 25]],
	["hunter", "🔥", "strikes", "Охотник за пусковыми", "Накройте пусковую в момент пуска.", ["stat", "hunts", 1]],
	["hunter_10", "⚡", "strikes", "Гроза «Искандеров»", "Накройте 10 пусковых в одном мире.", ["stat", "hunts", 10]],
	["hunter_25", "⚡", "strikes", "Контрбатарея", "Накройте 25 пусковых в одном мире.", ["stat", "hunts", 25]],
	["hunter_50", "⚡", "strikes", "Ни одного пуска безнаказанно", "Накройте 50 пусковых в одном мире.", ["stat", "hunts", 50]],
	["covered", "🐝", "strikes", "Комбинированный удар", "Ракета попала под прикрытием дронов.", ["stat", "covered_hits", 1]],
	["covered_10", "🐝", "strikes", "Мастер отвлечения", "10 попаданий ракет под прикрытием дронов.", ["stat", "covered_hits", 10]],
	["alabuga", "🏭", "strikes", "Стоп, «Алабуга»", "Выведите из строя завод шахедов.", ["site", "factory"]],
	["rear", "🔥", "strikes", "Тыл в огне", "Все четыре цели в тылу противника выведены одновременно.", ["rear_all"]],
	["silence", "🔇", "strikes", "Тишина в эфире", "Сила налёта по прогнозу — половина или меньше.", ["silence"]],
	["intel_1", "🛰", "strikes", "Первый снимок", "Найдите точку пуска снимком со спутника.", ["stat", "intel", 1]],
	["intel_3", "👁", "strikes", "Глаза с орбиты", "Три снимка со спутника.", ["stat", "intel", 3]],
	["intel_10", "👁", "strikes", "Своя спутниковая группировка", "Десять снимков со спутника.", ["stat", "intel", 10]],
	["revenge", "🧱", "strikes", "Не дождётесь", "Отразите ответный удар противника без единого прилёта по городу.", ["event"]],
	["revenge_3", "🧱", "strikes", "Нас не запугать", "Отразите три ответных удара без прилётов в одном мире.", ["stat", "revenge_held", 3]],
	["orders_1", "📋", "strikes", "Приказ выполнен", "Выполните задание командования.", ["stat", "orders", 1]],
	["orders_5", "📋", "strikes", "На хорошем счету", "Выполните 5 заданий командования.", ["stat", "orders", 5]],
	["orders_20", "📋", "strikes", "Любимчик штаба", "Выполните 20 заданий командования.", ["stat", "orders", 20]],
	["orders_50", "📋", "strikes", "Правая рука командующего", "Выполните 50 заданий командования.", ["stat", "orders", 50]],
	["stock_10", "📦", "strikes", "Спасибо, партнёры", "10 ударов со склада помощи партнёров.", ["stat", "from_stock", 10]],

	["fires_1", "🚒", "service", "Первый пожар потушен", "Пожарные потушили пожар.", ["stat", "fires_out", 1]],
	["fires_20", "🚒", "service", "Пожарные — герои", "Потушите 20 пожаров.", ["stat", "fires_out", 20]],
	["fires_100", "🚒", "service", "Сто пожаров", "Потушите 100 пожаров.", ["stat", "fires_out", 100]],
	["rebuilt_10", "🏗", "service", "Отстроим", "Восстановите 10 зданий.", ["stat", "rebuilt", 10]],
	["rebuilt_50", "🏗", "service", "Город возрождается", "Восстановите 50 зданий.", ["stat", "rebuilt", 50]],
	["crews_full", "👷", "service", "Полный штат", "Наберите все пожарные расчёты.", ["crews_full"]],
	["camo", "🌿", "service", "Невидимка", "Накройте позицию маскировочной сетью.", ["camo"]],
	["videos_1", "🎬", "service", "Нарезка ночи", "Первая нарезка ночи в ленте города.", ["videos", 1]],
	["videos_10", "🎬", "service", "Хроника обороны", "Десять нарезок ночей в ленте города.", ["videos", 10]],

	["rich", "💰", "economy", "Бюджет обороны", "Накопите $500 000.", ["money", 500000]],
	["money_100k", "💵", "economy", "Подушка", "Накопите $100 000.", ["money", 100000]],
	["money_250k", "💵", "economy", "Запас прочности", "Накопите $250 000.", ["money", 250000]],
	["money_1m", "💎", "economy", "Миллион на оборону", "Накопите $1 000 000.", ["money", 1000000]],
	["earned_100k", "📈", "economy", "Награды за сбитых", "Заработайте $100 000 наградами за сбитые цели.", ["stat", "earned", 100000]],
	["earned_1m", "📈", "economy", "Миллион за небо", "Заработайте $1 000 000 наградами.", ["stat", "earned", 1000000]],
	["earned_5m", "📈", "economy", "Пять миллионов", "Заработайте $5 000 000 наградами.", ["stat", "earned", 5000000]],
	["units_5", "🧰", "economy", "Батарея растёт", "5 систем ПВО на позиции.", ["units", 5]],
	["units_10", "🧰", "economy", "Эшелонированная оборона", "10 систем ПВО на позиции.", ["units", 10]],
	["units_all", "🏰", "economy", "Весь арсенал", "Все системы ПВО на позиции.", ["units", 15]],
	["unit_patriot", "🛡", "economy", "Patriot на дежурстве", "Поставьте Patriot.", ["unit", "patriot"]],
	["unit_s500", "🛡", "economy", "«Прометей»", "Поставьте С-500.", ["unit", "s500"]],
	["unit_drone", "🛩", "economy", "Своя эскадрилья", "Купите дроны-перехватчики.", ["unit", "drone"]],

	["training", "🎓", "special", "Курс молодого бойца", "Пройдите учебный полигон.", ["event"]],
	["online", "👥", "special", "Вместе", "Играйте с другом в одном мире.", ["online", 2]],
	["online_4", "👥", "special", "Полный расчёт", "Четыре игрока в одном мире.", ["online", 4]],
	["host", "🏠", "special", "Гостеприимный", "Примите друга в своём мире.", ["host"]],
	["server_bot", "🤖", "special", "Тест пройден", "Победите бота в черновике сервера.", ["event"]],
	["server_win", "⚔", "special", "Город против города", "Победите в матче на сервере.", ["event"]],
	["duel_win", "⚔", "special", "Три ночи", "Победите друга в дуэли.", ["event"]],
	["meta_10", "🏆", "special", "Коллекционер", "Получите 10 достижений.", ["meta", 10]],
	["meta_25", "🏆", "special", "Знаток", "Получите 25 достижений.", ["meta", 25]],
	["meta_50", "🏆", "special", "Ветеран", "Получите 50 достижений.", ["meta", 50]],
	["meta_100", "🏆", "special", "Живая легенда", "Получите 100 достижений.", ["meta", 100]],
]

## Families: the first kill of every kind of target, a hundred of the common ones, the first kill
## of every air defence system and the masters of a few, every strike weapon on target, every
## target in the enemy's rear.
const TARGET_TIERS := {"scout": 25, "shahed": 100, "gerbera": 100, "cruise": 50, "kalibr": 50, "ballistic": 25, "kab": 50, "molniya": 100, "geran3": 50, "banderol": 50}
const SYSTEM_TIERS := {"mg": 100, "gepard": 250, "shilka": 100, "igla": 50, "drone": 100, "iris": 100, "patriot": 50}
const TARGET_ICON := {"shahed": "🛩", "cruise": "🚀", "ballistic": "☄"}

static var dry := false
## A world played with code mods (scripts/mods/mods.gd): nothing is earned in it.
static var off := false
## Where they are kept (the self-test points it at a file of its own).
static var path := PATH
## {id: unix time it was earned}
static var got := {}
## {city id: the furthest day reached there}
static var best_day := {}
## {city id: 1 once its campaign was won}
static var wins := {}
static var _loaded := false
static var _all: Array = []
static var _by_id := {}


## Every achievement: [{id, icon, cat, name: [template, args], desc: [template, args], cond}].
static func all() -> Array:
	if not _all.is_empty():
		return _all
	for a in HAND:
		var desc: Array = [String(a[4]), []]
		var c: Array = a[5]
		if String(a[4]) == "":
			# the plain thresholds share their wording
			match String(c[0]):
				"stat":
					desc = ["Сбейте %d целей в одном мире.", [int(c[2])]]
				"day":
					desc = ["Доживите до %d-го дня.", [int(c[1])]]
		_add(String(a[0]), String(a[1]), String(a[2]), [String(a[3]), []], desc, c)
	# the built-in roster only: what a mod adds earns nothing here
	for t in GS.BASE_ENEMIES:
		var kind := GS.kind_of(String(t))
		var icon := String(TARGET_ICON.get(kind, "🎯"))
		var nm := String(GS.BASE_ENEMIES[t].name)
		_add("first_" + String(t), icon, "targets", ["Сбит: %s", [nm]], ["Впервые сбейте цель «%s».", [nm]], ["stat", "k_" + String(t), 1])
		if TARGET_TIERS.has(t):
			var n := int(TARGET_TIERS[t])
			_add("many_" + String(t), icon, "targets", ["%s ×%d", [String(GS.BASE_ENEMIES[t].plural), n]], ["Сбейте %d целей «%s» в одном мире.", [n, nm]], ["stat", "k_" + String(t), n])
	for w in GS.BASE_WEAPON_ORDER:
		var wn := String(GS.BASE_WEAPONS[w].name)
		_add("first_w_" + String(w), "🎯", "systems", ["%s: первая цель", [wn]], ["Сбейте цель системой «%s».", [wn]], ["stat", "w_" + String(w), 1])
		if SYSTEM_TIERS.has(w):
			var n := int(SYSTEM_TIERS[w])
			_add("master_" + String(w), "⭐", "systems", ["Мастер: %s", [wn]], ["Сбейте %d целей системой «%s» в одном мире.", [n, wn]], ["stat", "w_" + String(w), n])
	for w in Strikes.WEAPON_ORDER:
		var sn := String(Strikes.WEAPONS[w].short)
		_add("sh_" + String(w), "🚀", "strikes", ["%s в цель", [sn]], ["Удар «%s» поразил цель.", [String(Strikes.WEAPONS[w].name)]], ["stat", "sh_" + String(w), 1])
	for id in ["refinery", "arsenal", "rail"]:
		_add("rear_" + id, "🏭", "strikes", ["Выведен: %s", [String(Strikes.KINDS[id].short)]], ["Выведите из строя цель в тылу: %s.", [String(Strikes.KINDS[id].name)]], ["site", id])
	for c in CITIES:
		_add("won_" + c, "🏅", "campaign", ["Выстоял: %s", [String(CITY_NAMES[c])]], ["Пройдите кампанию в городе %s.", [String(CITY_NAMES[c])]], ["city_won", c])
	return _all


static func _add(id: String, icon: String, cat: String, name: Array, desc: Array, cond: Array) -> void:
	var e := {"id": id, "icon": icon, "cat": cat, "name": name, "desc": desc, "cond": cond}
	_all.append(e)
	_by_id[id] = e


## A template with its arguments, in the player's language (string arguments are translated too).
static func _say(t: Array) -> String:
	var args := []
	for x in t[1]:
		args.append(GS.t(x) if x is String else x)
	return GS.t(String(t[0])) % args if not args.is_empty() else GS.t(String(t[0]))


static func title(id: String) -> String:
	return _say(entry(id).name)


static func how(id: String) -> String:
	return _say(entry(id).desc)


static func entry(id: String) -> Dictionary:
	all()
	return _by_id.get(id, {"id": id, "icon": "🏆", "cat": "special", "name": [id, []], "desc": ["", []], "cond": ["event"]})


static func total() -> int:
	return all().size()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	got = {}
	best_day = {}
	wins = {}
	if dry:
		return
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for id in cf.get_section_keys("got") if cf.has_section("got") else []:
		got[String(id)] = int(cf.get_value("got", id, 0))
	for c in cf.get_section_keys("cities") if cf.has_section("cities") else []:
		best_day[String(c)] = int(cf.get_value("cities", c, 0))
	for c in cf.get_section_keys("wins") if cf.has_section("wins") else []:
		wins[String(c)] = int(cf.get_value("wins", c, 0))


static func _save() -> void:
	if dry:
		return
	var cf := ConfigFile.new()
	for id in got:
		cf.set_value("got", id, got[id])
	for c in best_day:
		cf.set_value("cities", c, best_day[c])
	for c in wins:
		cf.set_value("wins", c, wins[c])
	cf.save(path)


static func has(id: String) -> bool:
	_load()
	return got.has(id)


static func count() -> int:
	_load()
	return got.size()


## Earned in a section: [got, of].
static func count_in(cat: String) -> Array:
	_load()
	var n := 0
	var of := 0
	for e in all():
		if String(e.cat) == cat:
			of += 1
			if got.has(String(e.id)):
				n += 1
	return [n, of]


## Earns `id` if it is not earned yet; true when it is new.
static func earn(id: String) -> bool:
	if off:
		return false
	_load()
	if got.has(id):
		return false
	got[id] = int(Time.get_unix_time_from_system())
	_save()
	return true


## Is the condition of an achievement met by the world as it stands?
static func _met(c: Array, city) -> bool:
	var s: Dictionary = GS.stats
	match String(c[0]):
		"stat":
			return int(s.get(String(c[1]), 0)) >= int(c[2])
		"day":
			return GS.day >= int(c[1])
		"money":
			return GS.money >= int(c[1])
		"units":
			var n := 0
			for w in GS.WEAPON_ORDER:
				if GS.unlocked.has(w):
					n += 1
			return n >= int(c[1])
		"unit":
			return GS.unlocked.has(String(c[1]))
		"site":
			return String(Strikes.state(String(c[1])).st) != "ok"
		"rear_all":
			return ["refinery", "factory", "arsenal", "rail"].all(func(id) -> bool: return String(Strikes.state(id).st) != "ok")
		"silence":
			return city != null and GS.day >= 3 and float(Strikes.raid_strength(city)) <= 0.5
		"realism_day":
			return GS.realism and GS.day >= int(c[1])
		"realism_won":
			return GS.realism and GS.won
		"won":
			return GS.won
		"won_hard":
			return GS.won and GS.difficulty >= 2
		"city_won":
			return int(wins.get(String(c[1]), 0)) > 0
		"all_won":
			return CITIES.all(func(x) -> bool: return int(wins.get(x, 0)) > 0)
		"all_cities":
			return CITIES.all(func(x) -> bool: return int(best_day.get(x, 0)) >= 5)
		"own_city":
			return GS.city_id.begins_with("my_") and GS.day >= int(c[1])
		"crews_full":
			return GS.crews >= GS.CREW_MAX
		"camo":
			return GS.camo
		"intact":
			return GS.day >= int(c[1]) and GS.city >= 99.5
		"videos":
			return GS.videos.size() >= int(c[1])
		"online":
			return Net.players.size() >= int(c[1])
		"host":
			return Net.role == "host" and Net.players.size() >= 2
		"meta":
			return got.size() >= int(c[1])
	return false


## Looks at the world as it stands: returns the ids earned just now.
static func scan(city) -> Array:
	_load()
	# the furthest day and the campaigns won in each of the four cities (a drawn one is not one)
	if CITIES.has(GS.city_id):
		var dirty := false
		if GS.day > int(best_day.get(GS.city_id, 0)):
			best_day[GS.city_id] = GS.day
			dirty = true
		if GS.won and int(wins.get(GS.city_id, 0)) == 0:
			wins[GS.city_id] = 1
			dirty = true
		if dirty:
			_save()
	var out := []
	# twice: the collector's marks count what this very scan has just earned
	for pass_n in 2:
		for e in all():
			var id := String(e.id)
			if got.has(id) or String(e.cond[0]) == "event":
				continue
			if _met(e.cond, city) and earn(id):
				out.append(id)
	return out


## The morning report of a night: the achievements a whole night earns.
static func night_done(report: Dictionary) -> Array:
	var out := []
	var clean := int(report.get("impacts", 0)) == 0 and int(report.get("homes", 0)) == 0
	if clean:
		GS.stats["clean_nights"] = int(GS.stats.get("clean_nights", 0)) + 1
	var want := {
		"clean_night": clean and int(report.get("kills", 0)) >= 10,
		"night_30": int(report.get("kills", 0)) >= 30,
		"night_50": int(report.get("kills", 0)) >= 50,
		"revenge": bool(report.get("revenge", {}).get("held", false)),
	}
	for id in want:
		if bool(want[id]) and earn(String(id)):
			out.append(String(id))
	return out
