extends Node
## Global game state (autoload "GS"): balance tables, settings, run economy and
## Minecraft-style "worlds" (save slots in user://saves/*.json).

signal money_changed(value: int)
signal state_changed

enum Zone { FIELD, FOREST, WATER, CITY, SAND }
enum Loc { FOREST, RIVER, CITY, FIELD }
enum Kind { RESIDENTIAL, INDUSTRIAL, PUBLIC }

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 4

# --- Base locations (chosen on the city map) -------------------------------
## The riverside type is named after the city's water (loc_name / loc_desc): the Dnipro in Kyiv
## and Dnipro, the rivers of Kharkiv, the sea in Odesa.
const LOCATIONS := {
	Loc.FOREST: {
		"name": "Лес (окраины)", "detect": 0.35, "gun_range": 0.7, "reward": 1.0,
		"color": Color(0.3, 0.95, 0.45),
		"desc": "Высокая маскировка: разведчики ищут базу очень долго.\nДеревья закрывают обзор: дальность пулемётов и зениток −30%.",
	},
	Loc.RIVER: {
		"name": "Берег Днепра", "detect": 1.0, "gun_range": 1.1, "reward": 1.0,
		"color": Color(0.3, 0.75, 1.0),
		"desc": "Безопасная зона: обломки, сбитые над водой, падают в Днепр.\nОткрытый обзор над рекой: дальность ствольной ПВО +10%.",
	},
	Loc.CITY: {
		"name": "Городская застройка", "detect": 1.6, "gun_range": 1.0, "reward": 1.25,
		"color": Color(1.0, 0.4, 0.3),
		"desc": "Высокий риск: обломки падают на крыши — огромные штрафы.\nБазу легко найти. Поддержка горожан: награда за цели +25%.",
	},
	Loc.FIELD: {
		"name": "Поле (пригород)", "detect": 1.3, "gun_range": 1.0, "reward": 1.0,
		"color": Color(0.95, 0.85, 0.35),
		"desc": "Открытая местность: хороший обзор, но рядом частные дома.\nБазу сравнительно легко заметить с воздуха.",
	},
}

# --- Air-defense systems ------------------------------------------------------
# eff = damage multiplier against each target type (0 = cannot engage).
# "fcs" = fire-control computer: shows a lead indicator in the gunner sight.
# "class" groups the roster in the shop and sets the unit's ring around the base:
#   gun — barrels, short / medium / long — missiles by reach.
const WEAPONS := {
	"mg": {
		"name": "Пикап с пулемётом", "short": "ПИКАП", "kind": "gun", "class": "gun", "group": "manual", "unlock": 0, "fcs": false,
		"range": 400.0, "rate": 0.07, "damage": 8.0, "spread": 0.012, "speed": 560.0, "eye": 4.2,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.3, "ballistic": 0.0},
		"desc": "Мобильная огневая группа. Дёшево, эффективно против шахедов. Прицел без СУО — упреждение на глаз.",
	},
	"zu23": {
		"name": "ЗУ-23-2 (23 мм)", "short": "ЗУ-23", "kind": "gun", "class": "gun", "group": "manual", "unlock": 3500, "fcs": false,
		"range": 450.0, "rate": 0.055, "damage": 11.0, "spread": 0.011, "speed": 620.0, "eye": 3.6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.45, "ballistic": 0.0},
		"desc": "Буксируемая спарка на позиции. Плотный огонь по шахедам, наводится вручную — упреждение на глаз.",
	},
	"shilka": {
		"name": "ЗСУ-23-4 «Шилка»", "short": "ШИЛКА", "kind": "gun", "class": "gun", "group": "auto", "unlock": 12000, "fcs": true,
		"range": 520.0, "rate": 0.04, "damage": 12.0, "spread": 0.0075, "speed": 660.0, "eye": 4.6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.7, "ballistic": 0.0},
		"desc": "Четыре ствола и радар: сплошная стена трассеров на малой высоте. Быстро съедает цель, если та в зоне.",
	},
	"gepard": {
		"name": "Gepard 35 мм", "short": "GEPARD", "kind": "gun", "class": "gun", "group": "auto", "unlock": 9000, "fcs": true,
		"range": 500.0, "rate": 0.085, "damage": 16.0, "spread": 0.008, "speed": 760.0, "eye": 5.2,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.85, "ballistic": 0.0},
		"desc": "Спаренная зенитка с радаром и вычислителем: прицел показывает точку упреждения.",
	},
	"igla": {
		"name": "ПЗРК «Игла» (расчёт)", "short": "ИГЛА", "kind": "missile", "class": "short", "group": "manual", "unlock": 5000, "fcs": true,
		"range": 600.0, "rate": 2.2, "damage": 90.0, "speed": 320.0, "turn": 3.8, "eye": 2.2,
		"missile_price": 500, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.7, "ballistic": 0.0},
		"desc": "Переносной комплекс на позиции: дешёвые ракеты с тепловой головкой. Долгая перезарядка между пусками.",
	},
	"avenger": {
		"name": "Avenger (Stinger)", "short": "AVENGER", "kind": "missile", "class": "short", "group": "auto", "unlock": 13000, "fcs": true,
		"range": 700.0, "rate": 1.0, "damage": 115.0, "speed": 360.0, "turn": 4.0, "eye": 4.0,
		"missile_price": 800, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.85, "ballistic": 0.0},
		"desc": "Восемь «Стингеров» на вездеходе: быстрый пуск, дешёвая ракета. Рабочая лошадка против шахедов и крылатых.",
	},
	"drone": {
		"name": "Дрон-перехватчик «Шершень»", "short": "ШЕРШЕНЬ", "kind": "drone", "class": "short", "group": "auto", "unlock": 16000, "fcs": true,
		"range": 950.0, "rate": 0.85, "damage": 130.0, "speed": 175.0, "turn": 2.8, "eye": 3.4,
		"missile_price": 700, "start_ammo": 12, "link": 1500.0, "battery": 46.0,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.4, "ballistic": 0.0},
		"desc": "Рой дешёвых дронов-камикадзе против «Шахедов». Сами догоняют цель и таранят её; неизрасходованные возвращаются на базу и снова идут в бой. [C] — сесть за пульт FPV и вести дрон вручную.",
	},
	"osa": {
		"name": "ЗРК «Оса-АКМ»", "short": "ОСА", "kind": "missile", "class": "medium", "group": "missile", "unlock": 19000, "fcs": true,
		"range": 850.0, "rate": 1.3, "damage": 165.0, "speed": 380.0, "turn": 3.4, "eye": 5.0,
		"missile_price": 1200, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.9, "ballistic": 0.15},
		"desc": "Советский комплекс малой-средней дальности с собственным радаром. Дешёвые ракеты, но по баллистике почти бесполезен.",
	},
	"iris": {
		"name": "IRIS-T SLM", "short": "IRIS-T", "kind": "missile", "class": "medium", "group": "missile", "unlock": 22000, "fcs": true,
		"range": 1000.0, "rate": 1.1, "damage": 220.0, "speed": 300.0, "turn": 3.2, "eye": 5.5,
		"missile_price": 1800, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.35},
		"desc": "ЗРК средней дальности. Любые аэродинамические цели, по баллистике — две-три ракеты.",
	},
	"nasams": {
		"name": "NASAMS (AMRAAM)", "short": "NASAMS", "kind": "missile", "class": "medium", "group": "missile", "unlock": 27000, "fcs": true,
		"range": 1150.0, "rate": 1.2, "damage": 240.0, "speed": 340.0, "turn": 3.0, "eye": 4.4,
		"missile_price": 2000, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.3},
		"desc": "Батарея пусковых контейнеров с ракетами AMRAAM. Большая зона и надёжность по крылатым ракетам.",
	},
	"buk": {
		"name": "«Бук-М1» (ЗРК)", "short": "БУК", "kind": "missile", "class": "long", "group": "missile", "unlock": 34000, "fcs": true,
		"range": 1250.0, "rate": 1.5, "damage": 300.0, "speed": 430.0, "turn": 3.6, "eye": 5.6,
		"missile_price": 2800, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.55},
		"desc": "Самоходная установка с четырьмя тяжёлыми ракетами. Достаёт далеко, по баллистике нужна пара пусков.",
	},
	"s300": {
		"name": "С-300ПС", "short": "С-300", "kind": "missile", "class": "long", "group": "missile", "unlock": 45000, "fcs": true,
		"range": 1500.0, "rate": 1.7, "damage": 360.0, "speed": 500.0, "turn": 4.0, "eye": 6.2,
		"missile_price": 4200, "start_ammo": 5,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.8},
		"desc": "Дальний рубеж: четыре вертикальные пусковые. Держит крылатые на подходе и достаёт баллистику — но не так надёжно, как Patriot.",
	},
	"patriot": {
		"name": "Patriot PAC-3", "short": "PATRIOT", "kind": "missile", "class": "long", "group": "patriot", "unlock": 55000, "fcs": true,
		"range": 1500.0, "rate": 1.6, "damage": 450.0, "speed": 520.0, "turn": 4.5, "eye": 6.0,
		"missile_price": 6000, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 1.0},
		"desc": "Самое надёжное средство против баллистики: одна ракета — одна цель.",
	},
}
## Panel and shop order: barrels, then short range, then medium, then long.
const WEAPON_ORDER := ["mg", "zu23", "gepard", "shilka", "igla", "avenger", "drone", "osa", "iris", "nasams", "buk", "s300", "patriot"]
## Systems whose shots are bought as ammunition.
const AMMO_ORDER := ["igla", "avenger", "drone", "osa", "iris", "nasams", "buk", "s300", "patriot"]
## Control groups: how the battery panel and the shop are split up.
const WEAPON_GROUPS := [
	["manual", "РУЧНОЕ"],
	["auto", "МАШИННОЕ"],
	["missile", "РАКЕТНОЕ"],
	["patriot", "PATRIOT"],
]
## Shop sections, in order.
const WEAPON_CLASSES := [
	["gun", "СТВОЛЬНАЯ ПВО"],
	["short", "БЛИЖНИЙ РУБЕЖ"],
	["medium", "СРЕДНЯЯ ДАЛЬНОСТЬ"],
	["long", "ДАЛЬНИЙ РУБЕЖ"],
]

# --- Threats -----------------------------------------------------------------
# alt_min/alt_max: flight altitude band in world units (1 unit ≈ 5 m on the HUD).
# "kind" is the flight model and the column of the weapons' "eff" table (scout / shahed / cruise /
# ballistic); the rest are the real weapons each city is attacked with (CityDef.raid):
#   flight = [min, max] seconds of a ballistic arc, launch_dist / launch_alt = where it starts,
#   glide = a glide bomb falling straight at its target, decoy = no warhead,
#   crush = how much of a house the warhead takes down (× the kind's), mirv = splits on impact,
#   eff_mult = per weapon (or "*") multiplier of the weapons' efficiency against it.
const ENEMIES := {
	"scout": {
		"name": "Разведчик «Орлан»", "plural": "РАЗВЕДЧИК", "abbr": "Р", "hp": 24.0, "speed": 30.0,
		"alt_min": 110.0, "alt_max": 260.0,
		"reward": 2000, "debris": 4, "debris_penalty": 350, "hit_damage": 0.0, "hit_cost": 0,
		"radius": 4.5, "color": Color(0.35, 0.9, 1.0),
	},
	"shahed": {
		"name": "Шахед", "plural": "ШАХЕДЫ", "abbr": "Ш", "hp": 28.0, "speed": 40.0,
		"alt_min": 35.0, "alt_max": 320.0,
		"reward": 1300, "debris": 5, "debris_penalty": 500, "hit_damage": 2.5, "hit_cost": 2200,
		"radius": 4.0, "color": Color(1.0, 0.8, 0.2),
	},
	"cruise": {
		"name": "Крылатая ракета Х-101", "plural": "КРЫЛАТЫЕ РАКЕТЫ Х-101", "abbr": "КР", "hp": 60.0, "speed": 115.0,
		"alt_min": 22.0, "alt_max": 110.0,
		"reward": 5000, "debris": 7, "debris_penalty": 1000, "hit_damage": 4.0, "hit_cost": 6000,
		"radius": 4.5, "color": Color(1.0, 0.45, 0.15),
	},
	"ballistic": {
		"name": "Баллистическая ракета", "plural": "БАЛЛИСТИКА «ИСКАНДЕР-М»", "abbr": "БР", "hp": 90.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 11000, "debris": 8, "debris_penalty": 1400, "hit_damage": 6.0, "hit_cost": 11000,
		"radius": 7.5, "color": Color(1.0, 0.15, 0.2),
	},
	# --- drones -------------------------------------------------------------------
	"gerbera": {
		"kind": "shahed", "decoy": true,
		"name": "Ложная цель «Гербера»", "plural": "ЛОЖНЫЕ ЦЕЛИ «ГЕРБЕРА»", "abbr": "Л", "hp": 12.0, "speed": 42.0,
		"alt_min": 60.0, "alt_max": 300.0,
		"reward": 400, "debris": 2, "debris_penalty": 150, "hit_damage": 0.2, "hit_cost": 300,
		"radius": 3.5, "color": Color(0.85, 0.85, 0.6),
	},
	"geran3": {
		"kind": "shahed",
		"name": "Реактивный шахед «Герань-3»", "plural": "РЕАКТИВНЫЕ «ГЕРАНЬ-3»", "abbr": "Ш3", "hp": 32.0, "speed": 92.0,
		"alt_min": 50.0, "alt_max": 260.0,
		"reward": 2600, "debris": 5, "debris_penalty": 600, "hit_damage": 3.0, "hit_cost": 3000,
		"radius": 4.0, "color": Color(1.0, 0.6, 0.1),
	},
	"molniya": {
		"kind": "shahed", "crush": 0.5,
		"name": "Дрон «Молния»", "plural": "ДРОНЫ «МОЛНИЯ»", "abbr": "М", "hp": 10.0, "speed": 30.0,
		"alt_min": 20.0, "alt_max": 70.0,
		"reward": 450, "debris": 2, "debris_penalty": 200, "hit_damage": 0.8, "hit_cost": 800,
		"radius": 3.0, "color": Color(0.9, 0.9, 0.3),
	},
	# --- cruise missiles and glide bombs ----------------------------------------------------
	"kalibr": {
		"kind": "cruise",
		"name": "Крылатая ракета «Калибр»", "plural": "КРЫЛАТЫЕ РАКЕТЫ «КАЛИБР»", "abbr": "К", "hp": 55.0, "speed": 120.0,
		"alt_min": 18.0, "alt_max": 90.0,
		"reward": 5000, "debris": 7, "debris_penalty": 1000, "hit_damage": 4.0, "hit_cost": 6000,
		"radius": 4.5, "color": Color(1.0, 0.5, 0.2),
	},
	"oniks": {
		"kind": "cruise", "crush": 1.2,
		"name": "Противокорабельная ракета «Оникс»", "plural": "ПКР «ОНИКС»", "abbr": "О", "hp": 55.0, "speed": 230.0,
		"alt_min": 10.0, "alt_max": 24.0,
		"reward": 8000, "debris": 7, "debris_penalty": 1100, "hit_damage": 4.5, "hit_cost": 7000,
		"radius": 5.0, "color": Color(1.0, 0.35, 0.6),
		"eff_mult": {"mg": 0.2, "zu23": 0.3, "gepard": 0.5, "shilka": 0.5, "igla": 0.4, "drone": 0.0},
	},
	"kh31p": {
		"kind": "cruise",
		"name": "Противорадарная ракета Х-31П", "plural": "ПРОТИВОРАДАРНЫЕ Х-31П", "abbr": "31П", "hp": 40.0, "speed": 190.0,
		"alt_min": 60.0, "alt_max": 120.0,
		"reward": 6000, "debris": 5, "debris_penalty": 800, "hit_damage": 3.0, "hit_cost": 5000,
		"radius": 4.0, "color": Color(0.9, 0.4, 1.0),
		"eff_mult": {"drone": 0.0, "mg": 0.3},
	},
	"kab": {
		"kind": "cruise", "glide": true, "launch_dist": 1350.0, "crush": 1.4,
		"name": "Управляемая авиабомба КАБ", "plural": "КАБ С УМПК", "abbr": "КАБ", "hp": 110.0, "speed": 58.0,
		"alt_min": 560.0, "alt_max": 700.0,
		"reward": 7000, "debris": 6, "debris_penalty": 1200, "hit_damage": 6.5, "hit_cost": 9000,
		"radius": 5.0, "color": Color(1.0, 0.25, 0.1),
		"eff_mult": {"mg": 0.05, "zu23": 0.1, "gepard": 0.25, "shilka": 0.25, "igla": 0.3, "avenger": 0.4, "drone": 0.0, "*": 0.8},
	},
	# --- ballistic and aeroballistic ------------------------------------------------------------
	"s300": {
		"kind": "ballistic", "flight": [8.0, 10.0], "launch_dist": 1250.0, "launch_alt": [150.0, 260.0],
		"name": "Ракета С-300 по земле", "plural": "С-300 ПО НАЗЕМНЫМ ЦЕЛЯМ", "abbr": "С3", "hp": 60.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 8000, "debris": 7, "debris_penalty": 1100, "hit_damage": 4.5, "hit_cost": 8000,
		"radius": 6.0, "color": Color(1.0, 0.3, 0.3),
	},
	"kinzhal": {
		"kind": "ballistic", "flight": [9.0, 11.0], "launch_dist": 1900.0, "launch_alt": [700.0, 900.0],
		"name": "Аэробаллистическая «Кинжал»", "plural": "«КИНЖАЛ» Х-47М2", "abbr": "КН", "hp": 100.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 16000, "debris": 8, "debris_penalty": 1500, "hit_damage": 7.0, "hit_cost": 13000,
		"radius": 7.0, "color": Color(1.0, 0.1, 0.5),
		"eff_mult": {"patriot": 1.0, "s300": 0.35, "*": 0.15},
	},
	"kh22": {
		"kind": "ballistic", "flight": [12.0, 15.0], "launch_dist": 1900.0, "launch_alt": [800.0, 1000.0], "crush": 1.3,
		"name": "Ракета Х-22", "plural": "Х-22 С ТУ-22М3", "abbr": "Х22", "hp": 95.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 13000, "debris": 9, "debris_penalty": 1500, "hit_damage": 8.0, "hit_cost": 14000,
		"radius": 7.5, "color": Color(1.0, 0.2, 0.1),
		"eff_mult": {"patriot": 1.0, "*": 0.6},
	},
	"oreshnik": {
		"kind": "ballistic", "flight": [5.5, 6.5], "mirv": 6, "crush": 0.6,
		"name": "Боевой блок «Орешника»", "plural": "БАЛЛИСТИКА СРЕДНЕЙ ДАЛЬНОСТИ «ОРЕШНИК»", "abbr": "ОР", "hp": 200.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 0, "debris": 3, "debris_penalty": 500, "hit_damage": 1.5, "hit_cost": 4000,
		"radius": 6.0, "color": Color(1.0, 0.9, 0.5),
		"eff_mult": {"patriot": 0.12, "*": 0.0},
	},
}


## Efficiency of a weapon against a threat: the weapon's column for the flight model, times the
## threat's own resistance to that weapon (e is an enemy node or a threat id).
func eff(wid: String, e) -> float:
	var id := String(e) if e is String else String(e.variant)
	var ed: Dictionary = ENEMIES.get(id, ENEMIES.shahed)
	var kind := String(ed.get("kind", id))
	var base := float(WEAPONS[wid].eff.get(kind, 0.0))
	var m: Dictionary = ed.get("eff_mult", {})
	return base * float(m.get(wid, m.get("*", 1.0)))


## Flight model of a threat id (scout / shahed / cruise / ballistic).
func kind_of(id: String) -> String:
	return String(ENEMIES.get(id, {}).get("kind", id))

## Penalty multiplier for debris / impacts by building kind.
const KIND_PENALTY := {Kind.RESIDENTIAL: 1.0, Kind.INDUSTRIAL: 0.3, Kind.PUBLIC: 1.25}
const KIND_NAME := {Kind.RESIDENTIAL: "жилой дом", Kind.INDUSTRIAL: "промздание", Kind.PUBLIC: "памятник архитектуры"}
const HOME_HIT_COST := 3500

## enemies = wave size, penalty = fines and repair costs, income = rewards and state funding.
const DIFFICULTY := [
	{"name": "Лёгкая", "enemies": 0.55, "money": 45000, "penalty": 0.45, "income": 1.35,
		"desc": "Мало целей, щадящие штрафы, щедрое финансирование."},
	{"name": "Нормальная", "enemies": 0.85, "money": 32000, "penalty": 0.7, "income": 1.15,
		"desc": "Сбалансированная оборона: ошибки прощаются, но не все."},
	{"name": "Сложная", "enemies": 1.25, "money": 22000, "penalty": 1.0, "income": 1.0,
		"desc": "Массированные налёты, полные штрафы, скупое финансирование."},
]

## Campaign length: night 15 is the final massed raid. Surviving it wins the world,
## after which the defense can go on indefinitely.
const CAMPAIGN_NIGHTS := 15

## An extra crew of the fire service: faster response and faster reconstruction.
const CREW_PRICE := 9000
const CREW_MAX := 6
const CAMO_PRICE := 6000
const REPAIR_PRICE := 5000
## Rebuilding the districts: the late game has money to spare and a worn-down city.
const CITY_REPAIR_PRICE := 14000
const CITY_REPAIR_GAIN := 15.0
const DEBT_LIMIT := -80000
## Debt written off each morning so a single bad night cannot end the run.
const RELIEF_LIMIT := 20000

# --- Nightly highlight reels --------------------------------------------------
## Every morning a local channel cuts the clips the city filmed that night into one short video.
const VIDEO_CLIPS := 6
const VIDEO_CLIP_LEN := 5.0
const VIDEO_KEEP := 20

const Cities = preload("res://scripts/world/cities.gd")


## The channel that publishes the compilation (every city has its own).
func video_channel() -> String:
	return String(city_def().video_channel)


## Handles of the people filming from their balconies.
func video_authors() -> Array:
	return city_def().video_authors

# --- Controls ------------------------------------------------------------------------
## Every action the player can rebind in Settings → Управление: id, label, default key.
## Movement (WASD / arrows), aiming and Shift for run / boost are fixed to keep the sight
## and the walker predictable; everything discrete goes through this table.
const KEY_ACTIONS := [
	["view", "Сменить вид (сверху / с базы)", KEY_V],
	["walk", "Прогулка по городу", KEY_G],
	["fpv", "Пульт FPV дрона", KEY_C],
	["weapon_prev", "Предыдущая ПВО", KEY_Z],
	["weapon_next", "Следующая ПВО", KEY_X],
	["auto", "Автоогонь (выкл / стволы / всё)", KEY_F],
	["night", "Ночной прицел", KEY_N],
	["home", "Камера к базе", KEY_H],
	["shop", "Магазин", KEY_B],
	["feed", "Лента города (нарезка ночи)", KEY_T],
	["pause", "Пауза / закрыть окно", KEY_ESCAPE],
	["players", "Список игроков (сетевая игра)", KEY_TAB],
	["fpv_next", "FPV: следующий дрон", KEY_SPACE],
	["fpv_home", "FPV: отправить дрон на базу", KEY_R],
]


## Keycode currently bound to an action (falls back to the default).
func key_of(action: String) -> int:
	var bound: Dictionary = settings.get("keys", {})
	if bound.has(action):
		return int(bound[action])
	for a in KEY_ACTIONS:
		if String(a[0]) == action:
			return int(a[2])
	return 0


## Which action a pressed key triggers, or "" when the key is not bound to anything.
func action_of(keycode: int) -> String:
	for a in KEY_ACTIONS:
		var id := String(a[0])
		if key_of(id) == keycode:
			return id
	return ""


## Binds a key, taking it away from whatever held it before (no silent duplicates).
func set_key(action: String, keycode: int) -> void:
	var bound: Dictionary = settings.get("keys", {}).duplicate()
	for a in KEY_ACTIONS:
		var id := String(a[0])
		if id != action and key_of(id) == keycode:
			bound[id] = 0
	bound[action] = keycode
	settings["keys"] = bound
	save_settings()
	state_changed.emit()


func reset_keys() -> void:
	settings["keys"] = {}
	save_settings()
	state_changed.emit()


## Human-readable name of the key bound to an action, for the HUD and the settings list.
func key_label(action: String) -> String:
	var kc := key_of(action)
	if kc == 0:
		return t("—")
	return OS.get_keycode_string(kc)


# --- Settings ------------------------------------------------------------------
var settings := {
	"lang": "en", "volume": 0.8, "music": 0.6, "fullscreen": false, "quality": 2 if OS.has_feature("pc") else 1, "gfx_v2": false,
	"markers": true, "sens": 1.0, "invert_y": false, "slowmo": true, "keys": {},
	# Multiplayer (Net): switched on once used, friend code, the name friends see, friends [{code, name}],
	# the signed-in account (Account: uid, email, refresh token, nick, code, friends — never the password).
	"mp": false, "mp_code": "", "nick": "", "friends": [], "account": {},
}

# --- Run / world state ---------------------------------------------------------------
var world_id := ""
var world_name := ""
## Which city the world defends (scripts/world/cities.gd).
var city_id := "kyiv"
var world_created := 0
var difficulty := 1
var money := 0
var unlocked := {}
var ammo := {}
var city := 100.0
var base_hp := 100.0
var day := 1
var base_found := false
var detection := 0.0
var camo := false
## Fire-service crews bought on top of the two the city already has.
var crews := 0
var base_pos := Vector3.ZERO
var base_loc: int = Loc.FIELD
## True once the final night of the campaign has been held.
var won := false
var stats := {}
var damaged: Array = []
## Collapsed buildings: [index, percent] pairs, rebuilt by the fire service.
var crushed: Array = []
## Published compilations: [{day, clips, views, likes, title}], oldest first.
var videos: Array = []

var font: Font


signal language_changed

const I18n = preload("res://scripts/i18n/i18n.gd")

## Strings seen at runtime that have no translation for the current language (i18n test).
var missing := {}
var track_missing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = _make_font()
	I18n.install()
	load_settings()
	apply_settings()


## Translates a UI string. Source strings in code are Russian; English / Ukrainian come from
## scripts/i18n/*.gd. Unknown strings pass through unchanged.
func t(s: String) -> String:
	var r := String(TranslationServer.translate(s))
	if track_missing:
		_note_missing(s)
	return r


## Records a source string the current locale has no entry for (runtime i18n test). Comparing
## the translation with the source would not do: many words are spelled the same in Russian and
## Ukrainian ("БАЗА", "ПУСК", "ПРОМАХ") and are translated all the same.
func _note_missing(s: String) -> void:
	var loc := TranslationServer.get_locale()
	if loc != "ru" and I18n.has_cyrillic(s) and not I18n.has_entry(loc, s):
		missing[s] = true


func set_language(code: String) -> void:
	settings.lang = code
	TranslationServer.set_locale(code)
	language_changed.emit()


func _make_font() -> Font:
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Noto Sans Symbols 2", "Noto Color Emoji", "sans-serif"])
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Noto Sans", "Arial", "sans-serif"])
	var fb: Array[Font] = [emoji]
	f.fallbacks = fb
	return f


func new_world(wname: String, diff: int, pos: Vector3, loc: int, cid := "kyiv") -> void:
	world_id = "w%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	world_name = wname
	city_id = cid if Cities.has(cid) else Cities.DEFAULT
	world_created = int(Time.get_unix_time_from_system())
	difficulty = diff
	money = int(DIFFICULTY[diff].money)
	unlocked = {"mg": true}
	ammo = _empty_ammo()
	city = 100.0
	base_hp = 100.0
	day = 1
	base_found = false
	detection = 0.0
	camo = false
	crews = 0
	base_pos = pos
	base_loc = loc
	won = false
	stats = {"kills": 0, "roofs": 0, "impacts": 0, "penalties": 0, "earned": 0, "splash": 0, "homes": 0, "misses": 0, "drones": 0, "rams": 0, "fires_out": 0, "rebuilt": 0}
	damaged = []
	crushed = []
	videos = []
	money_changed.emit(money)
	state_changed.emit()


## Zeroed ammunition counters for every system that fires bought rounds.
func _empty_ammo() -> Dictionary:
	var d := {}
	for id in AMMO_ORDER:
		d[id] = 0
	return d


func loc_def() -> Dictionary:
	return LOCATIONS[base_loc]


## The city of the current world (or of cid).
func city_def(cid := ""):
	return Cities.get_def(cid if cid != "" else city_id)


## A phrase about the current city, translated ("Оборона Киева", "в Днепр — без ущерба" …).
func ctext(key: String, cid := "") -> String:
	return t(city_def(cid).text(key))


## Translated name of a base location type in a city.
func loc_name(loc: int, cid := "") -> String:
	if loc == Loc.RIVER:
		return ctext("shore", cid)
	return t(String(LOCATIONS[loc].name)) if LOCATIONS.has(loc) else "?"


func loc_desc(loc: int, cid := "") -> String:
	if loc == Loc.RIVER:
		return ctext("shore_desc", cid)
	return t(String(LOCATIONS[loc].desc)) if LOCATIONS.has(loc) else ""


func add_money(amount: int) -> void:
	money += amount
	if amount > 0:
		stats.earned = int(stats.get("earned", 0)) + amount
	else:
		stats.penalties = int(stats.get("penalties", 0)) - amount
	money_changed.emit(money)


func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func unlock_weapon(id: String) -> bool:
	if unlocked.get(id, false):
		return false
	if not spend(int(WEAPONS[id].unlock)):
		return false
	unlocked[id] = true
	if WEAPONS[id].has("start_ammo"):
		ammo[id] = int(ammo.get(id, 0)) + int(WEAPONS[id].start_ammo)
	state_changed.emit()
	return true


func buy_ammo(id: String, count: int) -> bool:
	if not spend(int(WEAPONS[id].missile_price) * count):
		return false
	ammo[id] = int(ammo.get(id, 0)) + count
	state_changed.emit()
	return true


## Stores one published compilation, keeping only the most recent nights.
func add_video(v: Dictionary) -> void:
	# replaying a night replaces its cut instead of publishing a second one
	for i in videos.size():
		if int(videos[i].get("day", -1)) == int(v.get("day", 0)):
			videos[i] = v
			state_changed.emit()
			return
	videos.append(v)
	while videos.size() > VIDEO_KEEP:
		videos.pop_front()
	state_changed.emit()


func video_for_day(day_n: int) -> Dictionary:
	for v in videos:
		if int(v.get("day", 0)) == day_n:
			return v
	return {}


func latest_video() -> Dictionary:
	return videos[videos.size() - 1] if not videos.is_empty() else {}


func detect_multiplier() -> float:
	return float(loc_def().detect) * (0.55 if camo else 1.0)


func enemy_mult() -> float:
	return float(DIFFICULTY[difficulty].enemies)


## Fines and repair costs are scaled down on the easier settings.
func penalty_mult() -> float:
	return float(DIFFICULTY[difficulty].get("penalty", 1.0))


## Rewards for kills and the morning state funding.
func income_mult() -> float:
	return float(DIFFICULTY[difficulty].get("income", 1.0))


# --- Worlds (save slots) ------------------------------------------------------------------
func _world_path(id: String) -> String:
	return SAVE_DIR + id + ".json"


func save_world() -> void:
	if world_id == "":
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var d := {
		"version": SAVE_VERSION, "id": world_id, "name": world_name,
		"city_id": city_id, "map_ver": int(city_def().version),
		"created": world_created, "last_played": int(Time.get_unix_time_from_system()),
		"difficulty": difficulty, "money": money, "unlocked": unlocked, "ammo": ammo,
		"city": city, "base_hp": base_hp, "day": day, "base_found": base_found,
		"detection": detection, "camo": camo, "crews": crews, "base_pos": [base_pos.x, base_pos.z],
		"base_loc": base_loc, "stats": stats, "damaged": damaged, "crushed": crushed, "won": won,
		"videos": videos,
	}
	var f := FileAccess.open(_world_path(world_id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


func read_world(id: String) -> Dictionary:
	var f := FileAccess.open(_world_path(id), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func list_worlds() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			var d := read_world(fname.trim_suffix(".json"))
			if not d.is_empty() and d.has("id"):
				out.append(d)
	out.sort_custom(func(a, b) -> bool: return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	return out


func load_world(id: String) -> bool:
	var d := read_world(id)
	if d.is_empty():
		return false
	world_id = String(d.id)
	world_name = String(d.get("name", "Мир"))
	city_id = String(d.get("city_id", Cities.DEFAULT))
	if not Cities.has(city_id):
		city_id = Cities.DEFAULT
	# a world saved on an older layout of its city: building indices point elsewhere now
	var same_map: bool = int(d.get("map_ver", 1)) == int(city_def().version)
	world_created = int(d.get("created", 0))
	difficulty = clampi(int(d.get("difficulty", 1)), 0, 2)
	money = int(d.get("money", 0))
	unlocked = {}
	for k in d.get("unlocked", {"mg": true}):
		unlocked[String(k)] = true
	ammo = _empty_ammo()
	var am: Dictionary = d.get("ammo", {})
	for k in am:
		ammo[String(k)] = int(am[k])
	city = float(d.get("city", 100.0))
	base_hp = float(d.get("base_hp", 100.0))
	day = int(d.get("day", 1))
	base_found = bool(d.get("base_found", false))
	detection = float(d.get("detection", 0.0))
	camo = bool(d.get("camo", false))
	crews = clampi(int(d.get("crews", 0)), 0, CREW_MAX)
	var bp: Array = d.get("base_pos", [0, 0])
	base_pos = Vector3(float(bp[0]), 0, float(bp[1]))
	base_loc = int(d.get("base_loc", Loc.FIELD))
	won = bool(d.get("won", false))
	stats = {"kills": 0, "roofs": 0, "impacts": 0, "penalties": 0, "earned": 0, "splash": 0, "homes": 0, "misses": 0, "drones": 0, "rams": 0, "fires_out": 0, "rebuilt": 0}
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[String(k)] = int(st[k])
	damaged = []
	for v in (d.get("damaged", []) if same_map else []):
		damaged.append(int(v))
	videos = []
	for v in d.get("videos", []):
		if v is Dictionary and (v as Dictionary).has("clips"):
			videos.append(v)
	crushed = []
	for v in (d.get("crushed", []) if same_map else []):
		if v is Array and (v as Array).size() == 2:
			crushed.append([int(v[0]), int(v[1])])
	money_changed.emit(money)
	state_changed.emit()
	return true


func delete_world(id: String) -> void:
	DirAccess.remove_absolute(_world_path(id))


# --- Settings persistence ------------------------------------------------------
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		settings["gfx_v2"] = true # a fresh install starts with the new defaults already
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])
	# the new graphics (sky, window interiors, reflections) arrive switched on on computers
	if OS.has_feature("pc") and not bool(settings.get("gfx_v2", false)):
		settings["gfx_v2"] = true
		settings["quality"] = 2


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


func apply_settings() -> void:
	if TranslationServer.get_locale() != String(settings.lang):
		TranslationServer.set_locale(String(settings.lang))
	var vol: float = clampf(float(settings.volume), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	if has_node("/root/SFX"):
		get_node("/root/SFX").set_music_volume(clampf(float(settings.music), 0.0, 1.0))
	# an off-screen capture run (--offscreen) keeps its tiny hidden window whatever the settings say
	if OS.has_feature("pc") and not OS.get_cmdline_user_args().has("--offscreen"):
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	state_changed.emit()


static func fmt_money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + "$" + s + out


static func fmt_date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var t := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d.%02d.%04d %02d:%02d" % [t.day, t.month, t.year, t.hour, t.minute]
