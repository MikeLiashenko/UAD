extends RefCounted
## Achievements: twenty marks of what the player has done, kept for good across every world in
## user://achievements.cfg — the first target brought down, a hundred of them, a week of nights, the
## campaign held, the first strike on target, a launcher caught in the act, the Alabuga plant
## stopped, all four cities defended and so on. The HUD scans for new ones once a second
## (scan()); the morning report brings the night-long ones (night_done()); a new one is announced
## with a toast. The main menu's "Achievements" screen lists them all.
##
## Test runs never write the player's file: `dry` (set by main for every run with --quit-at)
## keeps everything in memory.

const Strikes = preload("res://scripts/game/strikes.gd")
const PATH := "user://achievements.cfg"

## [id, icon, name, how it is earned]
const LIST := [
	["first_blood", "🎯", "Первый сбитый", "Сбейте первую цель."],
	["kills_100", "💯", "Сотня", "Сбейте 100 целей в одном мире."],
	["kills_500", "🛡", "Небесный щит", "Сбейте 500 целей в одном мире."],
	["clean_night", "✨", "Чистое небо", "Ночь без единого прилёта по городу, сбито не меньше 10 целей."],
	["week", "📅", "Неделя обороны", "Доживите до 8-го дня."],
	["campaign", "🏅", "Выстояли", "Пройдите кампанию — все 15 ночей."],
	["first_strike", "🚀", "Ответный ход", "Первый удар по точке пуска в цель."],
	["strikes_25", "🛰", "Дальняя рука", "25 ударов по противнику в одном мире."],
	["hunter", "🔥", "Охотник за пусковыми", "Накройте пусковую в момент пуска."],
	["hunter_10", "⚡", "Гроза «Искандеров»", "Накройте 10 пусковых в одном мире."],
	["alabuga", "🏭", "Стоп, «Алабуга»", "Выведите из строя завод шахедов."],
	["rear", "🔥", "Тыл в огне", "Все четыре цели в тылу противника выведены одновременно."],
	["silence", "🔇", "Тишина в эфире", "Сила налёта по прогнозу — половина или меньше."],
	["orders_5", "📋", "На хорошем счету", "Выполните 5 заданий командования."],
	["intel_3", "👁", "Глаза с орбиты", "Три снимка со спутника."],
	["rams_10", "🛩", "Таран", "10 таранов дронами-перехватчиками."],
	["fires_20", "🚒", "Пожарные — герои", "Потушите 20 пожаров."],
	["rich", "💰", "Бюджет обороны", "Накопите $500 000."],
	["realism", "🎖", "MaxRealism", "Переживите три ночи в мире MaxRealism."],
	["all_cities", "🗺", "Все четыре города", "Доживите до 5-го дня в Киеве, Харькове, Днепре и Одессе."],
]
const CITIES := ["kyiv", "kharkiv", "dnipro", "odesa"]

static var dry := false
## Where they are kept (the self-test points it at a file of its own).
static var path := PATH
## {id: unix time it was earned}
static var got := {}
## {city id: the furthest day reached there}
static var best_day := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	got = {}
	best_day = {}
	if dry:
		return
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for id in cf.get_section_keys("got") if cf.has_section("got") else []:
		got[String(id)] = int(cf.get_value("got", id, 0))
	for c in cf.get_section_keys("cities") if cf.has_section("cities") else []:
		best_day[String(c)] = int(cf.get_value("cities", c, 0))


static func _save() -> void:
	if dry:
		return
	var cf := ConfigFile.new()
	for id in got:
		cf.set_value("got", id, got[id])
	for c in best_day:
		cf.set_value("cities", c, best_day[c])
	cf.save(path)


static func has(id: String) -> bool:
	_load()
	return got.has(id)


static func count() -> int:
	_load()
	return got.size()


## Earns `id` if it is not earned yet; true when it is new.
static func earn(id: String) -> bool:
	_load()
	if got.has(id):
		return false
	got[id] = int(Time.get_unix_time_from_system())
	_save()
	return true


static func info(id: String) -> Array:
	for a in LIST:
		if String(a[0]) == id:
			return a
	return [id, "🏆", id, ""]


## Looks at the world as it stands: returns the ids earned just now.
static func scan(city) -> Array:
	_load()
	var s: Dictionary = GS.stats
	var out := []
	var want := {
		"first_blood": int(s.get("kills", 0)) >= 1,
		"kills_100": int(s.get("kills", 0)) >= 100,
		"kills_500": int(s.get("kills", 0)) >= 500,
		"week": GS.day >= 8,
		"campaign": GS.won,
		"first_strike": int(s.get("strike_hits", 0)) >= 1,
		"strikes_25": int(s.get("strikes", 0)) >= 25,
		"hunter": int(s.get("hunts", 0)) >= 1,
		"hunter_10": int(s.get("hunts", 0)) >= 10,
		"alabuga": String(Strikes.state("factory").st) == "destroyed",
		"rear": ["refinery", "factory", "arsenal", "rail"].all(func(id) -> bool: return String(Strikes.state(id).st) != "ok"),
		"orders_5": int(s.get("orders", 0)) >= 5,
		"intel_3": int(s.get("intel", 0)) >= 3,
		"rams_10": int(s.get("rams", 0)) >= 10,
		"fires_20": int(s.get("fires_out", 0)) >= 20,
		"rich": GS.money >= 500000,
		"realism": GS.realism and GS.day >= 4,
	}
	if city != null and GS.day >= 3 and float(Strikes.raid_strength(city)) <= 0.5:
		want["silence"] = true
	# the furthest day in each of the four cities (a drawn city is not one of them)
	if CITIES.has(GS.city_id) and GS.day > int(best_day.get(GS.city_id, 0)):
		best_day[GS.city_id] = GS.day
		_save()
	want["all_cities"] = CITIES.all(func(c) -> bool: return int(best_day.get(c, 0)) >= 5)
	for id in want:
		if bool(want[id]) and earn(String(id)):
			out.append(String(id))
	return out


## The morning report of a night: the achievements a whole night earns.
static func night_done(report: Dictionary) -> Array:
	var out := []
	if int(report.get("impacts", 0)) == 0 and int(report.get("homes", 0)) == 0 and int(report.get("kills", 0)) >= 10 and earn("clean_night"):
		out.append("clean_night")
	return out
