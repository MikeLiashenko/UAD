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

# --- Tempo ---------------------------------------------------------------------
## Time compression of everything that flies. The tables below are life-size — metres, real
## ranges and ceilings, real speeds in m/s — and a night flown at those speeds over a 30 km city
## is a long wait for a Shahed that takes minutes to arrive. So the clock of the air picture runs
## TEMPO times faster: threats, interceptors, tracers, the drones and the F-16 all cover the
## ground TEMPO times as fast and turn TEMPO times as quick, so every geometry stays what it is
## in life (who catches whom, the lead in the sight, where an intercept happens) — only the wait
## is shorter. Instruments show the real speed (see real_kmh).
const TEMPO := 3.0


## Muzzle or flight speed of a weapon's shot as it moves in the game, m/s.
func shot_speed(wid: String) -> float:
	return float(WEAPONS[wid].speed) * TEMPO


## A speed of the game world as the real number for an instrument, km/h.
func real_kmh(v: float) -> float:
	return v / TEMPO * 3.6


# --- Air-defense systems ------------------------------------------------------
# eff = damage multiplier against each target type (0 = cannot engage).
# "fcs" = fire-control computer: shows a lead indicator in the gunner sight.
# "class" groups the roster in the shop and sets the unit's ring around the base:
#   gun — barrels, short / medium / long — missiles by reach.
const WEAPONS := {
	"mg": {
		"name": "Пикап с пулемётом", "short": "ПИКАП", "kind": "gun", "class": "gun", "group": "manual", "unlock": 0, "fcs": false,
		"range": 1800.0, "ceil": 1500.0, "rate": 0.085, "damage": 8.0, "spread": 0.0045, "speed": 850.0, "eye": 4.2,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.3, "ballistic": 0.0},
		"desc": "Мобильная огневая группа с ДШК. Дёшево, эффективно против шахедов до 1,8 км. Прицел без СУО — упреждение на глаз.",
	},
	"zu23": {
		"name": "ЗУ-23-2 (23 мм)", "short": "ЗУ-23", "kind": "gun", "class": "gun", "group": "manual", "unlock": 3500, "fcs": false,
		"range": 2500.0, "ceil": 1500.0, "rate": 0.055, "damage": 11.0, "spread": 0.004, "speed": 970.0, "eye": 3.6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.45, "ballistic": 0.0},
		"desc": "Буксируемая спарка на позиции. Плотный огонь по шахедам до 2,5 км, наводится вручную — упреждение на глаз.",
	},
	"shilka": {
		"name": "ЗСУ-23-4 «Шилка»", "short": "ШИЛКА", "kind": "gun", "class": "gun", "group": "auto", "unlock": 12000, "fcs": true,
		"range": 2500.0, "ceil": 1500.0, "rate": 0.04, "damage": 12.0, "spread": 0.003, "speed": 970.0, "eye": 4.6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.7, "ballistic": 0.0},
		"desc": "Четыре ствола и радар: сплошная стена трассеров на малой высоте, до 2,5 км. Быстро съедает цель, если та в зоне.",
	},
	"gepard": {
		"name": "Gepard 35 мм", "short": "GEPARD", "kind": "gun", "class": "gun", "group": "auto", "unlock": 9000, "fcs": true,
		"range": 4000.0, "ceil": 3000.0, "rate": 0.085, "damage": 16.0, "spread": 0.0028, "speed": 1175.0, "eye": 5.2,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.85, "ballistic": 0.0},
		"desc": "Спаренная 35-мм зенитка с радаром и вычислителем: бьёт до 4 км, прицел показывает точку упреждения.",
	},
	"igla": {
		"name": "ПЗРК «Игла» (расчёт)", "short": "ИГЛА", "kind": "missile", "class": "short", "group": "manual", "unlock": 5000, "fcs": true,
		"range": 5200.0, "ceil": 3500.0, "rate": 2.2, "damage": 90.0, "speed": 570.0, "turn": 3.8, "eye": 2.2,
		"missile_price": 500, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.7, "ballistic": 0.0},
		"desc": "Переносной комплекс на позиции: дешёвые ракеты с тепловой головкой, до 5,2 км. Долгая перезарядка между пусками.",
	},
	"avenger": {
		"name": "Avenger (Stinger)", "short": "AVENGER", "kind": "missile", "class": "short", "group": "auto", "unlock": 13000, "fcs": true,
		"range": 4800.0, "ceil": 3800.0, "rate": 1.0, "damage": 115.0, "speed": 700.0, "turn": 4.0, "eye": 4.0,
		"missile_price": 800, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.85, "ballistic": 0.0},
		"desc": "Восемь «Стингеров» на вездеходе: быстрый пуск, дешёвая ракета, до 4,8 км. Рабочая лошадка против шахедов и крылатых.",
	},
	"drone": {
		"name": "Дрон-перехватчик «Шершень»", "short": "ШЕРШЕНЬ", "kind": "drone", "class": "short", "group": "auto", "unlock": 16000, "fcs": true,
		"range": 12000.0, "ceil": 4000.0, "rate": 0.85, "damage": 130.0, "speed": 90.0, "turn": 2.8, "eye": 3.4,
		"missile_price": 700, "start_ammo": 12, "link": 20000.0, "battery": 420.0,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.4, "ballistic": 0.0},
		"desc": "Рой дешёвых дронов-камикадзе против «Шахедов»: 320 км/ч, до 12 км от базы. Сами догоняют цель и таранят её; неизрасходованные возвращаются на базу и снова идут в бой. [C] — сесть за пульт FPV и вести дрон вручную.",
	},
	"osa": {
		"name": "ЗРК «Оса-АКМ»", "short": "ОСА", "kind": "missile", "class": "medium", "group": "missile", "unlock": 19000, "fcs": true,
		"range": 10000.0, "range_bm": 5000.0, "ceil": 5000.0, "rate": 1.3, "damage": 165.0, "speed": 500.0, "turn": 3.4, "eye": 5.0,
		"missile_price": 1200, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.9, "ballistic": 0.15},
		"desc": "Советский комплекс малой дальности с собственным радаром: до 10 км. Дешёвые ракеты, но по баллистике почти бесполезен.",
	},
	# by reach the NASAMS comes before the IRIS-T, and costs less
	"nasams": {
		"name": "NASAMS (AMRAAM)", "short": "NASAMS", "kind": "missile", "class": "medium", "group": "missile", "unlock": 23000, "fcs": true,
		"range": 25000.0, "range_bm": 12000.0, "ceil": 15000.0, "rate": 1.2, "damage": 220.0, "speed": 900.0, "turn": 3.0, "eye": 4.4,
		"missile_price": 1800, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.25},
		"desc": "Батарея пусковых контейнеров с ракетами AMRAAM: до 25 км. Большая зона и надёжность по крылатым ракетам.",
	},
	"iris": {
		"name": "IRIS-T SLM", "short": "IRIS-T", "kind": "missile", "class": "medium", "group": "missile", "unlock": 28000, "fcs": true,
		"range": 40000.0, "range_bm": 15000.0, "ceil": 20000.0, "rate": 1.1, "damage": 250.0, "speed": 1000.0, "turn": 3.2, "eye": 5.5,
		"missile_price": 2200, "start_ammo": 8,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.35},
		"desc": "ЗРК средней дальности: до 40 км по любым аэродинамическим целям, по баллистике — две-три ракеты вблизи.",
	},
	"buk": {
		"name": "«Бук-М1» (ЗРК)", "short": "БУК", "kind": "missile", "class": "long", "group": "missile", "unlock": 34000, "fcs": true,
		"range": 35000.0, "range_bm": 20000.0, "ceil": 22000.0, "rate": 1.5, "damage": 300.0, "speed": 850.0, "turn": 3.6, "eye": 5.6,
		"missile_price": 2800, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.55},
		"desc": "Самоходная установка с четырьмя тяжёлыми ракетами: до 35 км, по баллистике нужна пара пусков с 20 км.",
	},
	"s300": {
		"name": "С-300ПС", "short": "С-300", "kind": "missile", "class": "long", "group": "missile", "unlock": 45000, "fcs": true,
		"range": 75000.0, "range_bm": 30000.0, "ceil": 27000.0, "rate": 1.7, "damage": 360.0, "speed": 1700.0, "turn": 4.0, "eye": 6.2,
		"missile_price": 4200, "start_ammo": 5,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.8},
		"desc": "Дальний рубеж: до 75 км по самолётам и ракетам, до 30 км по баллистике — но не так надёжно, как Patriot. Низколетящие цели видит только из-за радиогоризонта.",
	},
	"patriot": {
		"name": "Patriot PAC-3", "short": "PATRIOT", "kind": "missile", "class": "long", "group": "patriot", "unlock": 55000, "fcs": true,
		"range": 60000.0, "range_bm": 35000.0, "ceil": 24000.0, "rate": 1.6, "damage": 450.0, "speed": 1500.0, "turn": 4.5, "eye": 6.0,
		"missile_price": 6000, "start_ammo": 6,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 1.0},
		"desc": "Самое надёжное средство против баллистики: одна ракета — одна цель, до 35 км (по аэродинамическим целям до 60 км).",
	},
	"s400": {
		"name": "С-400 «Триумф»", "short": "С-400", "kind": "missile", "class": "long", "group": "patriot", "unlock": 80000, "fcs": true,
		"range": 250000.0, "range_bm": 60000.0, "ceil": 30000.0, "rate": 1.5, "damage": 420.0, "speed": 2000.0, "turn": 4.2, "eye": 6.4,
		"missile_price": 7500, "start_ammo": 4,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.9},
		"desc": "Трофейный дивизион: до 250 км по самолётам и ракетам, до 60 км по баллистике. «Кинжал» и «Циркон» встречает ещё на подлёте, но двумя ракетами. Низколетящие цели видит только из-за радиогоризонта.",
	},
	"s500": {
		"name": "С-500 «Прометей»", "short": "С-500", "kind": "missile", "class": "long", "group": "patriot", "unlock": 130000, "fcs": true,
		"range": 500000.0, "range_bm": 200000.0, "ceil": 200000.0, "rate": 1.8, "damage": 520.0, "speed": 3600.0, "turn": 4.5, "eye": 6.6,
		"missile_price": 12000, "start_ammo": 4,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 1.0},
		"desc": "Трофейный комплекс стратегической ПРО: до 500 км, потолок — ближний космос. Одной ракетой берёт любую баллистику и гиперзвук, и только он достаёт боевые блоки «Орешника». Ракеты очень дороги.",
	},
	# --- the F-16's own weapons (scripts/game/fighter.gd): not systems of the battery, so they are
	# in neither WEAPON_ORDER nor AMMO_ORDER; the missiles are bought in the shop's aviation section
	"f16gun": {
		"name": "Пушка M61 Vulcan", "short": "M61", "kind": "gun", "class": "air", "group": "air", "unlock": 0, "fcs": false,
		"range": 1100.0, "ceil": 99999.0, "rate": 0.03, "damage": 7.0, "spread": 0.004, "speed": 1050.0, "eye": 0.0,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 0.8, "ballistic": 0.0},
		"desc": "20-мм шестиствольная пушка: 510 снарядов, бить с 500–900 м.",
	},
	"aim9": {
		"name": "AIM-9X Sidewinder", "short": "AIM-9X", "kind": "missile", "class": "air", "group": "air", "unlock": 0, "fcs": true,
		"range": 18000.0, "ceil": 99999.0, "rate": 0.8, "damage": 220.0, "speed": 850.0, "turn": 7.0, "eye": 0.0,
		"missile_price": 2500, "start_ammo": 0,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.0},
		"desc": "Тепловая ракета ближнего боя: захват в конусе перед носом, до 18 км.",
	},
	"aim120": {
		"name": "AIM-120 AMRAAM", "short": "AIM-120", "kind": "missile", "class": "air", "group": "air", "unlock": 0, "fcs": true,
		"range": 50000.0, "ceil": 99999.0, "rate": 1.2, "damage": 260.0, "speed": 1300.0, "turn": 4.5, "eye": 0.0,
		"missile_price": 4500, "start_ammo": 0,
		"eff": {"scout": 1.0, "shahed": 1.0, "cruise": 1.0, "ballistic": 0.0},
		"desc": "Ракета средней дальности с радиолокационным наведением: до 50 км.",
	},
}
## An F-16 flight for interceptor sorties over the city (scripts/game/fighter.gd).
const F16_PRICE := 40000
## Panel and shop order: barrels, then short range, then medium, then long.
const WEAPON_ORDER := ["mg", "zu23", "gepard", "shilka", "igla", "avenger", "drone", "osa", "nasams", "iris", "buk", "s300", "patriot", "s400", "s500"]
## Systems whose shots are bought as ammunition.
const AMMO_ORDER := ["igla", "avenger", "drone", "osa", "nasams", "iris", "buk", "s300", "patriot", "s400", "s500"]
## Control groups: how the battery panel and the shop are split up.
const WEAPON_GROUPS := [
	["manual", "РУЧНОЕ"],
	["auto", "МАШИННОЕ"],
	["missile", "РАКЕТНОЕ"],
	["patriot", "ПРО"],
]
## Shop sections, in order.
const WEAPON_CLASSES := [
	["gun", "СТВОЛЬНАЯ ПВО"],
	["short", "БЛИЖНИЙ РУБЕЖ"],
	["medium", "СРЕДНЯЯ ДАЛЬНОСТЬ"],
	["long", "ДАЛЬНИЙ РУБЕЖ"],
]

# --- Threats -----------------------------------------------------------------
# Everything is in real units: speed in m/s (flown TEMPO times faster, like everything in the air),
# alt_min / alt_max = the flight altitude band in metres.
# "kind" is the flight model and the column of the weapons' "eff" table (scout / shahed / cruise /
# ballistic); the rest are the real weapons each city is attacked with (CityDef.raid):
#   flight = [min, max] real seconds of the last, visible leg of a ballistic arc; launch_dist /
#   launch_alt = where the radar picks it up (metres from the target and above the ground; a
#   cruise missile without one shows up CRUISE_PICKUP out),
#   glide = a glide bomb falling straight at its target, decoy = no warhead,
#   swarm = how many come in a wave (× the usual: decoys in crowds, the jets in pairs),
#   own_alt = keeps to its own altitude band instead of the Shahed layers,
#   crush = how much of a house the warhead takes down (× the kind's), mirv = splits on impact,
#   eff_mult = per weapon (or "*") multiplier of the weapons' efficiency against it.
const ENEMIES := {
	"scout": {
		"name": "Разведчик «Орлан»", "plural": "РАЗВЕДЧИК", "abbr": "Р", "hp": 24.0, "speed": 33.0,
		"alt_min": 500.0, "alt_max": 1300.0,
		"reward": 2000, "debris": 4, "debris_penalty": 350, "hit_damage": 0.0, "hit_cost": 0,
		"radius": 4.5, "color": Color(0.35, 0.9, 1.0),
	},
	"shahed": {
		"name": "Шахед", "plural": "ШАХЕДЫ", "abbr": "Ш", "hp": 28.0, "speed": 51.0,
		"alt_min": 120.0, "alt_max": 3000.0,
		"reward": 1300, "debris": 5, "debris_penalty": 500, "hit_damage": 2.5, "hit_cost": 2200,
		"radius": 4.0, "color": Color(1.0, 0.8, 0.2),
	},
	"cruise": {
		"name": "Крылатая ракета Х-101", "plural": "КРЫЛАТЫЕ РАКЕТЫ Х-101", "abbr": "КР", "hp": 60.0, "speed": 200.0,
		"alt_min": 50.0, "alt_max": 400.0,
		"reward": 5000, "debris": 7, "debris_penalty": 1000, "hit_damage": 4.0, "hit_cost": 6000,
		"radius": 4.5, "color": Color(1.0, 0.45, 0.15),
	},
	"ballistic": {
		"kind": "ballistic", "flight": [42.0, 52.0], "launch_dist": 62000.0, "launch_alt": [36000.0, 44000.0],
		"name": "Баллистическая ракета", "plural": "БАЛЛИСТИКА «ИСКАНДЕР-М»", "abbr": "БР", "hp": 90.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 11000, "debris": 8, "debris_penalty": 1400, "hit_damage": 6.0, "hit_cost": 11000,
		"radius": 7.5, "color": Color(1.0, 0.15, 0.2),
	},
	# --- drones -------------------------------------------------------------------
	"gerbera": {
		"kind": "shahed", "decoy": true, "swarm": 1.5,
		"name": "Ложная цель «Гербера»", "plural": "ЛОЖНЫЕ ЦЕЛИ «ГЕРБЕРА»", "abbr": "Л", "hp": 12.0, "speed": 44.0,
		"alt_min": 300.0, "alt_max": 2500.0,
		"reward": 400, "debris": 2, "debris_penalty": 150, "hit_damage": 0.2, "hit_cost": 300,
		"radius": 3.5, "color": Color(0.85, 0.85, 0.6),
	},
	"geran3": {
		"kind": "shahed", "swarm": 0.5,
		"name": "Реактивный шахед «Герань-3»", "plural": "РЕАКТИВНЫЕ «ГЕРАНЬ-3»", "abbr": "Ш3", "hp": 32.0, "speed": 155.0,
		"alt_min": 300.0, "alt_max": 2500.0,
		"reward": 2600, "debris": 5, "debris_penalty": 600, "hit_damage": 3.0, "hit_cost": 3000,
		"radius": 4.0, "color": Color(1.0, 0.6, 0.1),
	},
	"geran4": {
		# a new airframe built for the jet: slower than the Geran-3 but far above the guns and the
		# shoulder-launched missiles, and too fast for an interceptor drone to run down
		"kind": "shahed", "swarm": 0.5, "own_alt": true,
		"name": "Реактивный дрон «Герань-4»", "plural": "ВЫСОТНЫЕ «ГЕРАНЬ-4»", "abbr": "Ш4", "hp": 34.0, "speed": 110.0,
		"alt_min": 2500.0, "alt_max": 5000.0,
		"reward": 3200, "debris": 5, "debris_penalty": 600, "hit_damage": 3.2, "hit_cost": 3400,
		"radius": 4.0, "color": Color(1.0, 0.7, 0.35),
		"eff_mult": {"drone": 0.4},
	},
	"geran5": {
		# not a flying wing any more: a six-metre fuselage with straight wings and a 90 kg warhead
		"kind": "shahed", "swarm": 0.5, "own_alt": true, "crush": 1.4,
		"name": "Дрон-ракета «Герань-5»", "plural": "ДРОНЫ-РАКЕТЫ «ГЕРАНЬ-5»", "abbr": "Ш5", "hp": 46.0, "speed": 150.0,
		"alt_min": 200.0, "alt_max": 3000.0,
		"reward": 4200, "debris": 6, "debris_penalty": 800, "hit_damage": 4.0, "hit_cost": 4800,
		"radius": 4.5, "color": Color(1.0, 0.5, 0.05),
		"eff_mult": {"mg": 0.6, "zu23": 0.7, "drone": 0.25},
	},
	"molniya": {
		"kind": "shahed", "crush": 0.5, "swarm": 1.5, "own_alt": true,
		"name": "Дрон «Молния»", "plural": "ДРОНЫ «МОЛНИЯ»", "abbr": "М", "hp": 10.0, "speed": 30.0,
		"alt_min": 80.0, "alt_max": 350.0,
		"reward": 450, "debris": 2, "debris_penalty": 200, "hit_damage": 0.8, "hit_cost": 800,
		"radius": 3.0, "color": Color(0.9, 0.9, 0.3),
	},
	# --- cruise missiles and glide bombs ----------------------------------------------------
	"kalibr": {
		"kind": "cruise",
		"name": "Крылатая ракета «Калибр»", "plural": "КРЫЛАТЫЕ РАКЕТЫ «КАЛИБР»", "abbr": "К", "hp": 55.0, "speed": 240.0,
		"alt_min": 40.0, "alt_max": 300.0,
		"reward": 5000, "debris": 7, "debris_penalty": 1000, "hit_damage": 4.0, "hit_cost": 6000,
		"radius": 4.5, "color": Color(1.0, 0.5, 0.2),
	},
	"oniks": {
		"kind": "cruise", "crush": 1.2, "launch_dist": 45000.0,
		"name": "Противокорабельная ракета «Оникс»", "plural": "ПКР «ОНИКС»", "abbr": "О", "hp": 55.0, "speed": 680.0,
		"alt_min": 20.0, "alt_max": 60.0,
		"reward": 8000, "debris": 7, "debris_penalty": 1100, "hit_damage": 4.5, "hit_cost": 7000,
		"radius": 5.0, "color": Color(1.0, 0.35, 0.6),
		"eff_mult": {"mg": 0.2, "zu23": 0.3, "gepard": 0.5, "shilka": 0.5, "igla": 0.4, "drone": 0.0},
	},
	"kh31p": {
		"kind": "cruise", "launch_dist": 40000.0,
		"name": "Противорадарная ракета Х-31П", "plural": "ПРОТИВОРАДАРНЫЕ Х-31П", "abbr": "31П", "hp": 40.0, "speed": 600.0,
		"alt_min": 200.0, "alt_max": 1500.0,
		"reward": 6000, "debris": 5, "debris_penalty": 800, "hit_damage": 3.0, "hit_cost": 5000,
		"radius": 4.0, "color": Color(0.9, 0.4, 1.0),
		"eff_mult": {"drone": 0.0, "mg": 0.3},
	},
	"banderol": {
		# S8000 "Banderol": a small cruise missile dropped by Orion drones near the border — five
		# metres, a 114 kg warhead, a Chinese model-jet engine, 550–650 km/h just over the roofs;
		# the Orions drop them two or three at a time
		"kind": "cruise", "swarm": 1.5, "crush": 0.8,
		"name": "Ракета «Бандероль» S8000", "plural": "КРЫЛАТЫЕ РАКЕТЫ «БАНДЕРОЛЬ»", "abbr": "БН", "hp": 42.0, "speed": 165.0,
		"alt_min": 30.0, "alt_max": 160.0,
		"reward": 4200, "debris": 5, "debris_penalty": 800, "hit_damage": 3.0, "hit_cost": 4500,
		"radius": 3.8, "color": Color(0.9, 0.68, 0.4),
		"eff_mult": {"drone": 0.5},
	},
	"kab": {
		"kind": "cruise", "glide": true, "launch_dist": 45000.0, "crush": 1.4,
		"name": "Управляемая авиабомба КАБ", "plural": "КАБ С УМПК", "abbr": "КАБ", "hp": 110.0, "speed": 240.0,
		"alt_min": 9500.0, "alt_max": 11500.0,
		"reward": 7000, "debris": 6, "debris_penalty": 1200, "hit_damage": 6.5, "hit_cost": 9000,
		"radius": 5.0, "color": Color(1.0, 0.25, 0.1),
		"eff_mult": {"mg": 0.05, "zu23": 0.1, "gepard": 0.25, "shilka": 0.25, "igla": 0.3, "avenger": 0.4, "drone": 0.0, "*": 0.8},
	},
	# --- ballistic and aeroballistic ------------------------------------------------------------
	"s300": {
		"kind": "ballistic", "flight": [38.0, 46.0], "launch_dist": 38000.0, "launch_alt": [14000.0, 20000.0],
		"name": "Ракета С-300 по земле", "plural": "С-300 ПО НАЗЕМНЫМ ЦЕЛЯМ", "abbr": "С3", "hp": 60.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 8000, "debris": 7, "debris_penalty": 1100, "hit_damage": 4.5, "hit_cost": 8000,
		"radius": 6.0, "color": Color(1.0, 0.3, 0.3),
	},
	"kinzhal": {
		"kind": "ballistic", "flight": [30.0, 36.0], "launch_dist": 80000.0, "launch_alt": [40000.0, 50000.0],
		"name": "Аэробаллистическая «Кинжал»", "plural": "«КИНЖАЛ» Х-47М2", "abbr": "КН", "hp": 100.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 16000, "debris": 8, "debris_penalty": 1500, "hit_damage": 7.0, "hit_cost": 13000,
		"radius": 7.0, "color": Color(1.0, 0.1, 0.5),
		"eff_mult": {"patriot": 1.0, "s500": 1.0, "s400": 0.6, "s300": 0.35, "*": 0.15},
	},
	"kh22": {
		"kind": "ballistic", "flight": [48.0, 58.0], "launch_dist": 55000.0, "launch_alt": [21000.0, 24000.0], "crush": 1.3,
		"name": "Ракета Х-22", "plural": "Х-22 С ТУ-22М3", "abbr": "Х22", "hp": 95.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 13000, "debris": 9, "debris_penalty": 1500, "hit_damage": 8.0, "hit_cost": 14000,
		"radius": 7.5, "color": Color(1.0, 0.2, 0.1),
		"eff_mult": {"patriot": 1.0, "s500": 1.0, "s400": 1.0, "*": 0.6},
	},
	"oreshnik": {
		"kind": "ballistic", "flight": [20.0, 24.0], "mirv": 6, "crush": 0.6,
		"name": "Боевой блок «Орешника»", "plural": "БАЛЛИСТИКА СРЕДНЕЙ ДАЛЬНОСТИ «ОРЕШНИК»", "abbr": "ОР", "hp": 200.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 0, "debris": 3, "debris_penalty": 500, "hit_damage": 1.5, "hit_cost": 4000,
		"radius": 6.0, "color": Color(1.0, 0.9, 0.5),
		"eff_mult": {"patriot": 0.12, "s500": 0.5, "s400": 0.08, "*": 0.0},
	},
	"zircon": {
		# a hypersonic cruise missile: Mach 7 in the stratosphere, then a shallow dive on the target
		"kind": "ballistic", "flight": [34.0, 40.0], "launch_dist": 90000.0, "launch_alt": [28000.0, 34000.0],
		"name": "Гиперзвуковая ракета «Циркон»", "plural": "ГИПЕРЗВУКОВЫЕ «ЦИРКОН» 3М22", "abbr": "ЦР", "hp": 95.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 18000, "debris": 8, "debris_penalty": 1500, "hit_damage": 7.5, "hit_cost": 14000,
		"radius": 7.0, "color": Color(0.6, 0.8, 1.0),
		"eff_mult": {"patriot": 0.85, "s500": 1.0, "s400": 0.55, "s300": 0.25, "*": 0.1},
	},
	"s400": {
		# a 48N6 of the S-400 fired at the ground: further and faster than the old S-300 rounds
		"kind": "ballistic", "flight": [32.0, 40.0], "launch_dist": 60000.0, "launch_alt": [22000.0, 28000.0],
		"name": "Ракета С-400 по земле", "plural": "С-400 ПО НАЗЕМНЫМ ЦЕЛЯМ", "abbr": "С4", "hp": 70.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 9500, "debris": 7, "debris_penalty": 1200, "hit_damage": 5.0, "hit_cost": 9000,
		"radius": 6.0, "color": Color(1.0, 0.4, 0.4),
	},
	"s500": {
		# the heavy round of the S-500 lobbed at a city: it comes down from the edge of space
		"kind": "ballistic", "flight": [36.0, 44.0], "launch_dist": 100000.0, "launch_alt": [55000.0, 70000.0], "crush": 1.2,
		"name": "Ракета С-500 по земле", "plural": "С-500 ПО НАЗЕМНЫМ ЦЕЛЯМ", "abbr": "С5", "hp": 110.0, "speed": 0.0,
		"alt_min": 0.0, "alt_max": 0.0,
		"reward": 15000, "debris": 8, "debris_penalty": 1500, "hit_damage": 7.0, "hit_cost": 13000,
		"radius": 7.0, "color": Color(1.0, 0.2, 0.35),
		"eff_mult": {"patriot": 1.0, "s500": 1.0, "s400": 0.8, "s300": 0.4, "*": 0.2},
	},
}
## Where the radars pick up a cruise missile that names no launch_dist, metres from its target.
const CRUISE_PICKUP := 30000.0


## Efficiency of a weapon against a threat: the weapon's column for the flight model, times the
## threat's own resistance to that weapon (e is an enemy node or a threat id).
func eff(wid: String, e) -> float:
	var id := String(e) if e is String else String(e.variant)
	var ed: Dictionary = ENEMIES.get(id, ENEMIES.shahed)
	var kind := String(ed.get("kind", id))
	var base := float(WEAPONS[wid].eff.get(kind, 0.0))
	var m: Dictionary = ed.get("eff_mult", {})
	return base * float(m.get(wid, m.get("*", 1.0)))


## Height of a battery's radar above the ground, for the radio horizon.
const RADAR_MAST := 12.0


## How far a system reaches a threat (an enemy node), metres: its range for aerodynamic targets or
## the shorter one for ballistic missiles; the long-range complexes are also held by the radio
## horizon — a cruise missile at 50 m shows up only from about 40 km.
func reach(wid: String, e) -> float:
	var wd: Dictionary = WEAPONS[wid]
	var ballistic: bool = String(e.type) == "ballistic"
	var r := float(wd.get("range_bm", wd.range)) if ballistic else float(wd.range)
	if not ballistic and String(wd.kind) == "missile" and r > 12000.0:
		r = minf(r, 4120.0 * (sqrt(RADAR_MAST) + sqrt(maxf(float(e.position.y), 0.0))))
	return r


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
## Outposts: how many beside the main base, the price of the first (each next one costs that much
## more), and the seconds a system is on the road when it moves between bases.
const OUTPOSTS_MAX := 3
const OUTPOST_PRICE := 12000
const RELOCATE_TIME := 20.0
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
const BuildInfo = preload("res://scripts/build_info.gd")


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
	["strikes", "Удары по точкам пуска", KEY_K],
	["bases", "Базы: новый опорный пункт и перевозка систем", KEY_U],
	["mfg", "Мобильная огневая группа (пикап)", KEY_M],
	["fighter", "Вылет истребителя F-16", KEY_J],
	["warp", "Ускорение времени ×1 / ×2 / ×4 / ×8", KEY_BRACKETRIGHT],
	["photo", "Фото без интерфейса", KEY_F12],
	["use", "MaxRealism: занять место / встать", KEY_E],
	["alarm", "Воздушная тревога: объявить / отбой", KEY_L],
]


## Test switch (-- --touch): the interface of a touch screen on a computer without one.
var force_touch := false


## The game is played with fingers: on-screen sticks and buttons instead of keys and a mouse.
func touch() -> bool:
	return force_touch or DisplayServer.is_touchscreen_available()


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
	# punctuation keys by the sign printed on them, not "BracketRight"
	var signs := {KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/",
		KEY_BACKSLASH: "\\", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_QUOTELEFT: "`", KEY_MINUS: "-", KEY_EQUAL: "="}
	return signs.get(kc, OS.get_keycode_string(kc))


# --- Settings ------------------------------------------------------------------
var settings := {
	"lang": "en", "volume": 0.8, "music": 0.6, "fullscreen": false, "quality": 2 if OS.has_feature("pc") else 1, "gfx_v2": false, "photo": true, "film": true,
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
## MaxRealism world (scripts/game/realism.gd): the ground view only, the player walks from one
## system to the next and works each by hand, the radar is a scope and a missile may miss.
var realism := false
## The training range of the MaxRealism mode (scripts/game/training.gd): never saved.
var training := false
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
## Launch sites the raids come from (scripts/game/strikes.gd): {kind: {known, st, n, def}},
## and our strikes in flight [{site, w}] that land at dusk.
var sites := {}
var strikes: Array = []
## The order of the command for this day (scripts/game/orders.gd), {} when there is none.
var order := {}
## Strike weapons the partners have delivered, {weapon: count} (Strikes.aid): spent before money.
var arsenal := {}
## The strikes that have landed, newest last (Strikes.record): [{d, w, s, h, st, hunt}], 40 at most.
var strike_log: Array = []
## How much our strikes have angered the enemy (Strikes.ANGER_*): at RETALIATE it answers with a
## salvo of its own the next night. revenge_night: the night that salvo flies (0 = none).
var anger := 0.0
var revenge_night := 0
## Outposts: bases of ours beside the main one (GS.base_pos), [{x, z, loc}], OUTPOSTS_MAX at most.
## The main base is index 0, outpost i is index i + 1. unit_base: {system id: base index} — where
## each bought system stands (0 when not listed).
var outposts: Array = []
var unit_base := {}
## The clock of the day the world was saved in (seconds into it, and the day's length): a world
## loaded mid-day goes on from there instead of starting the day over. 0 = from the start.
var day_clock := 0.0
var day_len := 0.0
## A match on a server (scripts/game/pvp.gd): {"def": ServerDef, "side": 0 | 1, "bot": bool}; {} in
## the usual game. Never saved: main sets it after new_world.
var pvp := {}
## How well the city stands a hit (a rule of the server; 1 in the usual game).
var city_armor := 1.0

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


func new_world(wname: String, diff: int, pos: Vector3, loc: int, cid := "kyiv", real := false) -> void:
	world_id = "w%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	world_name = wname
	realism = real
	training = false
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
	sites = {}
	strikes = []
	order = {}
	arsenal = {}
	strike_log = []
	anger = 0.0
	revenge_night = 0
	outposts = []
	unit_base = {}
	day_clock = 0.0
	day_len = 0.0
	pvp = {}
	city_armor = 1.0
	money_changed.emit(money)
	state_changed.emit()


# --- Bases ---------------------------------------------------------------------------------
## The main base and the outposts: 1 + outposts.
func base_count() -> int:
	return 1 + outposts.size()


## Where base `i` stands (0 — the main base).
func base_at(i: int) -> Vector3:
	if i <= 0 or i > outposts.size():
		return base_pos
	return Vector3(float(outposts[i - 1].x), 0, float(outposts[i - 1].z))


func base_loc_of(i: int) -> int:
	return base_loc if i <= 0 or i > outposts.size() else int(outposts[i - 1].loc)


## The base a bought system stands at.
func base_of(id: String) -> int:
	var i := int(unit_base.get(id, 0))
	return i if i <= outposts.size() else 0


## "Главная база" / "Опорный пункт 2".
func base_name(i: int) -> String:
	return t("Главная база") if i <= 0 else t("Опорный пункт %d") % (i + 1)


## What the next outpost costs (0 when no more can be set up).
func outpost_price() -> int:
	return 0 if outposts.size() >= OUTPOSTS_MAX else OUTPOST_PRICE * (outposts.size() + 1)


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
	return float(DIFFICULTY[difficulty].enemies) * (REALISM_ENEMIES if realism else 1.0)


## MaxRealism: one person on foot cannot be at every system at once, so the raids are thinner.
const REALISM_ENEMIES := 0.7
## MaxRealism: the chance of one interceptor against a target it is fully effective against.
const REALISM_PK := 0.8


## MaxRealism: the chance that one interceptor brings its target down. Missiles deal no hit
## points there — a round either kills or passes by, which is why they are fired in pairs.
func kill_chance(wid: String, e) -> float:
	return clampf(eff(wid, e) * REALISM_PK, 0.0, 0.95)


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
		"realism": realism, "difficulty": difficulty, "money": money, "unlocked": unlocked, "ammo": ammo,
		"city": city, "base_hp": base_hp, "day": day, "base_found": base_found,
		"detection": detection, "camo": camo, "crews": crews, "base_pos": [base_pos.x, base_pos.z],
		"base_loc": base_loc, "stats": stats, "damaged": damaged, "crushed": crushed, "won": won,
		"videos": videos, "sites": sites, "strikes": strikes, "order": order, "arsenal": arsenal, "strike_log": strike_log, "anger": anger, "revenge_night": revenge_night,
		"outposts": outposts, "unit_base": unit_base, "day_t": day_clock, "day_len": day_len,
	}
	if Cities.is_custom(city_id):
		# a city drawn in the map editor: the world keeps its own copy and plays on without the editor's
		d["city_data"] = city_def().data
	# Written beside the save and only then put in its place, the last good save kept as .bak: a
	# game killed in the middle of writing (a crash, a phone that ran out of memory) used to leave a
	# cut-off file, and the whole world was gone from the list.
	var path := _world_path(world_id)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()
	if not (_parse_world(path + ".tmp") is Dictionary):
		return # the disk is full or failing: the save there now stays
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	DirAccess.rename_absolute(path + ".tmp", path)


## A save file as a Dictionary, or null when it is missing, cut off or not a world.
func _parse_world(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	var ok := j.parse(f.get_as_text()) == OK
	f.close()
	return j.data if ok and j.data is Dictionary and (j.data as Dictionary).has("id") else null


func read_world(id: String) -> Dictionary:
	var path := _world_path(id)
	var parsed = _parse_world(path)
	if parsed == null:
		# the game went down while it was saving: the new file or the one before it is whole
		for p in [path + ".tmp", path + ".bak"]:
			parsed = _parse_world(p)
			if parsed != null:
				break
	if parsed == null:
		return {}
	# a world of a drawn city the map editor no longer has: the copy in the save is the city
	var cid = parsed.get("city_id")
	if cid is String and String(cid).begins_with("my_") and not Cities.has(String(cid)) and parsed.get("city_data") is Dictionary:
		Cities.register(String(cid), parsed.city_data)
	return parsed


func list_worlds() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	var ids := {}
	for fname in dir.get_files():
		# a world whose save was being replaced when the game went down lives on in its .tmp / .bak
		for ext in [".json", ".json.tmp", ".json.bak"]:
			if String(fname).ends_with(ext):
				ids[String(fname).trim_suffix(ext)] = true
	for id in ids:
		var d := read_world(String(id))
		if not d.is_empty() and d.has("id"):
			out.append(d)
	out.sort_custom(func(a, b) -> bool: return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	return out


func load_world(id: String) -> bool:
	var d := read_world(id)
	if d.is_empty():
		return false
	world_id = String(d.id)
	pvp = {}
	city_armor = 1.0
	world_name = String(d.get("name", "Мир"))
	city_id = String(d.get("city_id", Cities.DEFAULT))
	if not Cities.has(city_id):
		city_id = Cities.DEFAULT
	# a world saved on an older layout of its city: building indices point elsewhere now
	var same_map: bool = int(d.get("map_ver", 1)) == int(city_def().version)
	world_created = int(d.get("created", 0))
	realism = bool(d.get("realism", false))
	training = false
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
	if not same_map and int(d.get("map_ver", 1)) < 3:
		# a world from before the cities were made life-size: the old map was ±1000
		base_pos *= float(city_def().half) / 1000.0
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
	sites = {}
	var ss = d.get("sites", {})
	if ss is Dictionary:
		for k in ss:
			var v = ss[k]
			if v is Dictionary:
				sites[String(k)] = {"known": bool(v.get("known", false)), "st": String(v.get("st", "ok")), "n": int(v.get("n", 0)), "def": float(v.get("def", 0.0))}
	strikes = []
	for x in d.get("strikes", []):
		if x is Dictionary and x.has("site") and x.has("w"):
			strikes.append({"site": String(x.site), "w": String(x.w)})
	order = {}
	arsenal = {}
	strike_log = []
	anger = 0.0
	revenge_night = 0
	outposts = []
	unit_base = {}
	var o = d.get("order", {})
	if o is Dictionary and o.has("kind") and o.has("reward"):
		var ob = o.get("base", {})
		order = {"kind": String(o.kind), "site": String(o.get("site", "")), "n": int(o.get("n", 0)), "reward": int(o.reward), "day": int(o.get("day", day)),
			"base": {"hunts": int(ob.get("hunts", 0)), "known": int(ob.get("known", 0))} if ob is Dictionary else {}}
	var ars = d.get("arsenal", {})
	if ars is Dictionary:
		for k in ars:
			if int(ars[k]) > 0:
				arsenal[String(k)] = int(ars[k])
	anger = float(d.get("anger", 0.0))
	revenge_night = int(d.get("revenge_night", 0))
	day_clock = maxf(float(d.get("day_t", 0.0)), 0.0)
	day_len = maxf(float(d.get("day_len", 0.0)), 0.0)
	for op in d.get("outposts", []):
		if op is Dictionary and op.has("x") and op.has("z") and outposts.size() < OUTPOSTS_MAX:
			outposts.append({"x": float(op.x), "z": float(op.z), "loc": int(op.get("loc", Loc.FIELD))})
	var ub = d.get("unit_base", {})
	if ub is Dictionary:
		for k in ub:
			if int(ub[k]) > 0 and int(ub[k]) <= outposts.size():
				unit_base[String(k)] = int(ub[k])
	for x in d.get("strike_log", []):
		if x is Dictionary and x.has("w") and x.has("s"):
			strike_log.append({"d": int(x.get("d", 0)), "w": String(x.w), "s": String(x.s), "h": bool(x.get("h", false)), "st": String(x.get("st", "ok")), "hunt": bool(x.get("hunt", false))})
	money_changed.emit(money)
	state_changed.emit()
	return true


func delete_world(id: String) -> void:
	for ext in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(_world_path(id) + ext)


# --- A world as a file to carry elsewhere (export / import) ------------------------------------
## One world in one file, «<name>.uadworld»: the save itself (a world of a drawn city carries its
## city) wrapped in {"uad_world": WORLD_FILE_VERSION, "game", "build", "exported", "world"}.
const WORLD_EXT := "uadworld"
const WORLD_FILE_VERSION := 1


## Where exported worlds go and where the import looks first: Documents/UAD/Worlds (on Windows
## «Документы\UAD\Worlds», on Android the shared Documents folder), the game's own folder failing that.
func worlds_dir() -> String:
	var base := String(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	if base == "" or not DirAccess.dir_exists_absolute(base):
		base = "user://"
	return base.path_join("UAD").path_join("Worlds")


## Writes the world into dir (worlds_dir() when empty). Returns the file's path, "" on failure.
func export_world(id: String, dir := "") -> String:
	var d := read_world(id)
	if d.is_empty():
		return ""
	var cid := String(d.get("city_id", ""))
	if Cities.is_custom(cid) and not (d.get("city_data") is Dictionary) and Cities.has(cid):
		d["city_data"] = city_def(cid).data # an old save of a drawn city: the city goes with it
	if dir == "":
		dir = worlds_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := String(d.get("name", "")).strip_edges()
	for c in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		stem = stem.replace(c, "_")
	stem = stem.left(60).strip_edges()
	if stem == "":
		stem = "world"
	var path := dir.path_join("%s.%s" % [stem, WORLD_EXT])
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s (%d).%s" % [stem, n, WORLD_EXT])
		n += 1
	var file := {"uad_world": WORLD_FILE_VERSION, "game": BuildInfo.label(), "build": BuildInfo.BUILD,
		"exported": int(Time.get_unix_time_from_system()), "world": d}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(file, "\t"))
	f.close()
	return path


## World files found in the usual places (the export folder, Downloads), newest first:
## [{path, name, day, city, time}]. Files that are not worlds are left out.
func world_files() -> Array:
	var out := []
	var seen := {}
	for dir in [worlds_dir(), String(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))]:
		if dir == "" or not DirAccess.dir_exists_absolute(dir):
			continue
		for fname in DirAccess.get_files_at(dir):
			if String(fname).get_extension().to_lower() != WORLD_EXT:
				continue
			var path: String = dir.path_join(fname)
			if seen.has(path):
				continue
			seen[path] = true
			var r := read_world_file(path)
			if not r.has("world"):
				continue
			var w: Dictionary = r.world
			out.append({"path": path, "name": String(w.get("name", fname.get_basename())), "day": int(w.get("day", 1)),
				"city": String(w.get("city_id", "")), "time": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b) -> bool: return int(a.time) > int(b.time))
	return out


## A world file read and checked: {"world": Dictionary} when it can be played here, otherwise
## {"error": a sentence for the player (Russian source, through GS.t)}. A bare save (saves/*.json)
## is taken too.
func read_world_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path) and not path.begins_with("content://"):
		return {"error": "Файл не найден."}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "Файл не открывается."}
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if text.length() > 8 * 1024 * 1024 or j.parse(text) != OK or not (j.data is Dictionary):
		return {"error": "Это не файл мира UAD или он повреждён."}
	var data: Dictionary = j.data
	var w = data.get("world") if data.has("uad_world") else data
	if not (w is Dictionary) or not (w as Dictionary).has("city_id") or not (w as Dictionary).has("day"):
		return {"error": "Это не файл мира UAD или он повреждён."}
	if int(data.get("uad_world", 1)) > WORLD_FILE_VERSION or int(w.get("version", 1)) > SAVE_VERSION:
		return {"error": "Мир сохранён более новой версией игры — обновите игру и попробуйте снова."}
	var cid := String(w.city_id)
	if not Cities.has(cid) and not (cid.begins_with("my_") and w.get("city_data") is Dictionary):
		return {"error": "Город этого мира неизвестен этой версии игры."}
	return {"world": w}


## Adds the world of a file to the player's worlds under a new id (an import never replaces a
## world); a name already taken gets a number. Returns {"id", "name"} or {"error"}.
func import_world(path: String) -> Dictionary:
	var r := read_world_file(path)
	if not r.has("world"):
		return r
	var w: Dictionary = (r.world as Dictionary).duplicate(true)
	var names := {}
	for x in list_worlds():
		names[String(x.get("name", ""))] = true
	var wname := String(w.get("name", t("Мир"))).strip_edges().left(40)
	if wname == "":
		wname = t("Мир")
	var base_name := wname
	var n := 2
	while names.has(wname):
		wname = "%s (%d)" % [base_name, n]
		n += 1
	var id := "w%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	w["id"] = id
	w["name"] = wname
	w["last_played"] = int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(_world_path(id), FileAccess.WRITE)
	if f == null:
		return {"error": "Не удалось записать мир в папку игры."}
	f.store_string(JSON.stringify(w))
	f.close()
	if read_world(id).is_empty():
		delete_world(id)
		return {"error": "Это не файл мира UAD или он повреждён."}
	return {"id": id, "name": wname}


# --- Graphics levels ------------------------------------------------------------
## 0 low, 1 high, 2 ultra, 3 max, 4 ultramax. Max and UltraMax need the Forward+ renderer (real
## lamp light, ambient occlusion, reflections on wet asphalt, volumetric haze); the engine picks
## its renderer when it starts, so the choice is written to RENDERER_PATH (the project reads it
## as a settings override) and the game restarts.
const QUALITY_MAX := 3
const RENDERER_PATH := "user://renderer.cfg"


## Highest level this device can run (phones and the web stay on the compatibility renderer).
func quality_cap() -> int:
	return 4 if OS.has_feature("pc") else 2


func renderer_now() -> String:
	return RenderingServer.get_current_rendering_method()


## Renderer the chosen graphics level asks for.
func renderer_wanted() -> String:
	return "forward_plus" if int(settings.quality) >= QUALITY_MAX and OS.has_feature("pc") else "gl_compatibility"


## The chosen level only shows in full after a restart.
func needs_restart() -> bool:
	return renderer_wanted() == "forward_plus" and renderer_now() != "forward_plus"


## Writes (or removes) the renderer override the engine reads at the next start.
func store_renderer() -> void:
	if renderer_wanted() == "forward_plus":
		var f := FileAccess.open(RENDERER_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string("[rendering]\n\nrenderer/rendering_method=\"forward_plus\"\n")
	elif FileAccess.file_exists(RENDERER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_PATH))


## Starts the game again (with the same command line) so the new renderer takes over. It leaves
## the way a normal quit does, the world saved first: a restart from the settings in the middle of
## a day used to lose everything since the last autosave.
func restart_game() -> void:
	save_settings()
	store_renderer()
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	var main := get_tree().current_scene
	if main != null and main.has_method("quit_game"):
		main.quit_game()
	else:
		get_tree().quit()


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
	settings["quality"] = clampi(int(settings.quality), 0, quality_cap())


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
