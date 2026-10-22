extends RefCounted

const ModelEditor = preload("res://scripts/ui/model_editor.gd")
## What the mod workshop (scripts/ui/mod_workshop.gd) tells and offers: the reference of the "uad"
## module and of picture mods (each entry inserts its example at the caret), and the templates new
## projects start from. Texts are in the three languages of the game, {"ru", "uk", "en"}.


## The text in the game's language.
static func tr3(d) -> String:
	if d is String:
		return d
	var lang := String(GS.settings.get("lang", "en"))
	return String(d.get(lang, d.get("en", "")))


static func _t(ru: String, uk: String, en: String) -> Dictionary:
	return {"ru": ru, "uk": uk, "en": en}


const PY_BUILTINS := ["print", "len", "range", "int", "float", "str", "bool", "list", "dict", "tuple", "abs", "min",
	"max", "sum", "round", "sorted", "reversed", "enumerate", "zip", "map", "filter", "any", "all", "isinstance",
	"hasattr", "getattr", "setattr", "super", "Exception", "ValueError", "KeyError", "math", "random", "uad"]
const SHADER_WORDS := ["shader_type", "canvas_item", "uniform", "sampler2D", "hint_screen_texture", "hint_range",
	"filter_linear", "fragment", "texture", "SCREEN_UV", "COLOR", "TIME", "mix", "smoothstep", "clamp", "length",
	"dot", "fract", "sin", "cos", "vec2", "vec3", "vec4", "float", "uad_night", "uad_alarm", "uad_city", "screen"]


## [name, text to insert] for completion after "uad.".
static func api_names() -> Array:
	var out := []
	for sec in sections("mod"):
		for e in sec.items:
			var sig := String(e.sig)
			if sig.begins_with("uad."):
				var nm := sig.trim_prefix("uad.").get_slice("(", 0)
				out.append([nm + ("(" if sig.contains("(") else ""), nm + ("(" if sig.contains("(") else "")])
	return out


static func sections(kind: String) -> Array:
	return _shader_sections() if kind == "shader" else _mod_sections()


static func _mod_sections() -> Array:
	return [
		{"title": _t("Определения (верх файла)", "Визначення (верх файлу)", "Definitions (top of the file)"), "items": [
			{"sig": "uad.weapon(id, type=…, model=…)", "ins": "uad.weapon(\"my_sam\", type=\"short\", model=\"avenger\",\n    name={\"ru\": \"Мой ЗРК\", \"uk\": \"Мій ЗРК\", \"en\": \"My SAM\"},\n    range=6000, damage=120, unlock=8000, missile_price=900)\n",
				"doc": _t("Новая система ПВО: тип задаёт, как она стреляет и с каких чисел начинается; модель — наша (\"avenger\") или своя (\"имя.uadmodel\"). Появится в магазине в своём разделе.", "Нова система ППО: тип задає, як вона стріляє і з яких чисел починається; модель — наша (\"avenger\") або своя (\"ім'я.uadmodel\"). З'явиться в магазині у своєму розділі.", "A new air defence system: the type sets how it fires and the numbers it starts from; the model is ours (\"avenger\") or your own (\"name.uadmodel\"). It shows up in the shop in its section.")},
			{"sig": "типы ПВО / system types", "ins": "# gun_manual  стволы, наводка вручную (ЗУ-23)\n# gun_auto    стволы с радаром (Gepard)\n# manpads     ПЗРК (Игла)\n# short       ракеты ближнего рубежа (Avenger)\n# drone       дроны-перехватчики (Шершень)\n# medium      ЗРК средней дальности (IRIS-T)\n# long        дальний рубеж (С-300)\n# abm         ПРО, сбивает баллистику (Patriot)\n",
				"doc": _t("Тип системы: стволы, ПЗРК, ракеты, дроны, ПРО.", "Тип системи: стволи, ПЗРК, ракети, дрони, ПРО.", "System type: guns, MANPADS, missiles, drones, missile defence.")},
			{"sig": "uad.change_weapon(id, …)", "ins": "uad.change_weapon(\"mg\", range=2200, damage=10)\n",
				"doc": _t("Меняет поля системы игры (или своей).", "Змінює поля системи гри (або своєї).", "Changes fields of a game's (or your) system.")},
			{"sig": "uad.enemy(id, type=…, model=…)", "ins": "uad.enemy(\"my_drone\", type=\"drone\", model=\"shahed\",\n    name={\"ru\": \"Мой дрон\", \"uk\": \"Мій дрон\", \"en\": \"My drone\"},\n    speed=70, hp=30, reward=1500)\n",
				"doc": _t("Новая угроза: тип задаёт, как она летит; модель — наша или своя (\"имя.uadmodel\").", "Нова загроза: тип задає, як вона летить; модель — наша або своя (\"ім'я.uadmodel\").", "A new threat: the type sets how it flies; the model is ours or your own (\"name.uadmodel\").")},
			{"sig": "типы угроз / threat types", "ins": "# scout       разведчик (Орлан)\n# drone       ударный дрон (Шахед)\n# jet_drone   реактивный дрон (Герань-3)\n# decoy       ложная цель (Гербера)\n# cruise      крылатая ракета (Х-101)\n# glide_bomb  планирующая бомба (КАБ)\n# ballistic   баллистика (Искандер)\n# hypersonic  аэробаллистика (Кинжал)\n",
				"doc": _t("Тип угрозы: дроны, ракеты, бомбы, баллистика.", "Тип загрози: дрони, ракети, бомби, балістика.", "Threat type: drones, missiles, bombs, ballistic.")},
			{"sig": "model=\"имя.uadmodel\"", "ins": "model=\"my_model.uadmodel\"",
				"doc": _t("Своя модель из 3D-редактора: «＋ Файл» → 3D-модель. Башня поворачивается, ствол наклоняется вокруг своих осей.", "Своя модель із 3D-редактора: «＋ Файл» → 3D-модель. Башта повертається, ствол нахиляється навколо своїх осей.", "Your own model from the 3D editor: \"＋ File\" → 3D model. The turret turns and the gun tilts round their pivots.")},
			{"sig": "uad.change_enemy(id, …)", "ins": "uad.change_enemy(\"shahed\", hp=40)\n",
				"doc": _t("Меняет поля угрозы.", "Змінює поля загрози.", "Changes fields of a threat.")},
			{"sig": "uad.raid(enemy, night=1, weight=1.0)", "ins": "uad.raid(\"my_drone\", night=2, weight=1.5)\n",
				"doc": _t("Угроза летит в ночных налётах с этой ночи; weight — как часто по сравнению с другими. cities=[\"kyiv\"] — только эти города.", "Загроза летить у нічних нальотах з цієї ночі; weight — як часто порівняно з іншими. cities=[\"kyiv\"] — лише ці міста.", "The threat flies in the night raids from this night on; weight — how often next to the others. cities=[\"kyiv\"] — only these cities.")},
			{"sig": "uad.clear_raid(slot=None)", "ins": "uad.clear_raid(\"drone\")\n",
				"doc": _t("Очищает налёт: \"drone\", \"cruise\", \"ballistic\" или все. Для налёта целиком из своих угроз.", "Очищає наліт: \"drone\", \"cruise\", \"ballistic\" або всі. Для нальоту цілком зі своїх загроз.", "Empties a raid slot: \"drone\", \"cruise\", \"ballistic\" or all. For a raid of your own threats only.")},
			{"sig": "поля системы / system fields", "ins": "# range, range_bm, ceil, rate, damage, speed, turn, spread,\n# unlock, missile_price, start_ammo, fcs, eye,\n# kind: gun|missile|drone, class: gun|short|medium|long,\n# group: manual|auto|missile|patriot,\n# eff={\"scout\": 1, \"shahed\": 1, \"cruise\": 0.8, \"ballistic\": 0},\n# model=\"s300\", tint=\"#88aaff\", scale=1.2, name, short, desc\n",
				"doc": _t("Дальность (м), урон, перезарядка (с), цена, боезапас, эффективность по типам целей, модель, цвет и размер.", "Дальність (м), шкода, перезаряджання (с), ціна, боєзапас, ефективність за типами цілей, модель, колір і розмір.", "Range (m), damage, reload (s), price, ammo, efficiency by target type, model, colour and size.")},
			{"sig": "поля угрозы / threat fields", "ins": "# hp, speed (m/s), alt_min, alt_max, reward, hit_damage, hit_cost,\n# debris, radius, swarm, crush, decoy, own_alt,\n# kind: scout|shahed|cruise|ballistic, eff_mult={\"mg\": 0.5},\n# color=\"#ffaa00\" (radar), model=\"geran5\", tint, scale,\n# name, plural, abbr\n",
				"doc": _t("Прочность, скорость, высоты, награда, урон городу, рой, ложная цель, стойкость к системам.", "Міцність, швидкість, висоти, нагорода, шкода місту, рій, хибна ціль, стійкість до систем.", "Hit points, speed, altitudes, reward, damage to the city, swarm, decoy, resistance to systems.")},
		]},
		{"title": _t("События", "Події", "Events"), "items": [
			{"sig": "@uad.on(\"start\")", "ins": "@uad.on(\"start\")\ndef on_start(e):\n    uad.message(\"Мод работает!\")\n",
				"doc": _t("Мир открыт. e = {day, night}", "Світ відкрито. e = {day, night}", "The world opened. e = {day, night}")},
			{"sig": "@uad.on(\"night\")", "ins": "@uad.on(\"night\")\ndef on_night(e):\n    uad.alert(f\"Ночь {e['day']}!\")\n",
				"doc": _t("Начался ночной налёт. e = {day}", "Почався нічний наліт. e = {day}", "The night raid began. e = {day}")},
			{"sig": "@uad.on(\"day\")", "ins": "@uad.on(\"day\")\ndef on_day(e):\n    pass\n",
				"doc": _t("Начался день. e = {day}", "Почався день. e = {day}", "A day began. e = {day}")},
			{"sig": "@uad.on(\"morning\")", "ins": "@uad.on(\"morning\")\ndef on_morning(e):\n    if e[\"impacts\"] == 0:\n        uad.give_money(5000)\n",
				"doc": _t("Ночь закончилась: e = {day, kills, impacts, homes, earned, …}", "Ніч скінчилася: e = {day, kills, impacts, homes, earned, …}", "The night is over: e = {day, kills, impacts, homes, earned, …}")},
			{"sig": "@uad.on(\"kill\")", "ins": "@uad.on(\"kill\")\ndef on_kill(e):\n    if e[\"type\"] == \"shahed\":\n        uad.give_money(200)\n",
				"doc": _t("Цель сбита: e = {type, weapon, reward, x, y, z}", "Ціль збито: e = {type, weapon, reward, x, y, z}", "A target went down: e = {type, weapon, reward, x, y, z}")},
			{"sig": "@uad.on(\"impact\")", "ins": "@uad.on(\"impact\")\ndef on_impact(e):\n    uad.message(f\"Прилёт: {e['type']}\", \"#ff5544\")\n",
				"doc": _t("Цель прорвалась: e = {type, x, z, base}", "Ціль прорвалася: e = {type, x, z, base}", "A target got through: e = {type, x, z, base}")},
			{"sig": "@uad.on(\"launch\")", "ins": "@uad.on(\"launch\")\ndef on_launch(e):\n    print(e[\"type\"], e[\"count\"])\n",
				"doc": _t("Противник запустил: e = {type, count, at_base}", "Противник запустив: e = {type, count, at_base}", "The enemy launched: e = {type, count, at_base}")},
			{"sig": "@uad.on(\"buy\")", "ins": "@uad.on(\"buy\")\ndef on_buy(e):\n    uad.give_ammo(e[\"weapon\"], 4) if e[\"weapon\"] in uad.weapons() else None\n",
				"doc": _t("Куплена система: e = {weapon}", "Куплено систему: e = {weapon}", "A system was bought: e = {weapon}")},
			{"sig": "@uad.on(\"tick\")", "ins": "@uad.on(\"tick\")\ndef every_second(e):\n    if e[\"night\"] and e[\"t\"] % 30 == 0:\n        uad.launch(\"shahed\", 2)\n",
				"doc": _t("Каждую секунду игры: e = {t, night}", "Щосекунди гри: e = {t, night}", "Every game second: e = {t, night}")},
		]},
		{"title": _t("Действия (в событиях)", "Дії (у подіях)", "Actions (in events)"), "items": [
			{"sig": "uad.message(text, color)", "ins": "uad.message(\"Текст\", \"#ffcc33\")", "doc": _t("Строка в журнал (в MaxRealism — по радио).", "Рядок у журнал (у MaxRealism — по радіо).", "A line in the log (on the radio in MaxRealism).")},
			{"sig": "uad.alert(text)", "ins": "uad.alert(\"ВНИМАНИЕ!\")", "doc": _t("Большая надпись посреди экрана.", "Великий напис посеред екрана.", "A big caption in the middle of the screen.")},
			{"sig": "uad.give_money(n)", "ins": "uad.give_money(1000)", "doc": _t("Добавить (или отнять, если меньше нуля) деньги.", "Додати (або забрати, якщо менше нуля) гроші.", "Add (or take, if below zero) money.")},
			{"sig": "uad.money()", "ins": "uad.money()", "doc": _t("Сколько денег.", "Скільки грошей.", "How much money there is.")},
			{"sig": "uad.day()", "ins": "uad.day()", "doc": _t("Номер дня.", "Номер дня.", "The day number.")},
			{"sig": "uad.is_night()", "ins": "uad.is_night()", "doc": _t("Идёт ли ночь.", "Чи йде ніч.", "Whether it is night.")},
			{"sig": "uad.launch(enemy, count)", "ins": "uad.launch(\"shahed\", 3)", "doc": _t("Запустить угрозы на город (at_base=True — по базе).", "Запустити загрози на місто (at_base=True — по базі).", "Launch threats at the city (at_base=True — at the base).")},
			{"sig": "uad.targets()", "ins": "for t in uad.targets():\n    print(t[\"type\"], t[\"hp\"])\n", "doc": _t("Цели в воздухе: [{type, x, y, z, hp}].", "Цілі в повітрі: [{type, x, y, z, hp}].", "Targets in the air: [{type, x, y, z, hp}].")},
			{"sig": "uad.give_weapon(id)", "ins": "uad.give_weapon(\"gepard\")", "doc": _t("Дать систему бесплатно.", "Дати систему безкоштовно.", "Give a system for free.")},
			{"sig": "uad.give_ammo(id, n)", "ins": "uad.give_ammo(\"igla\", 4)", "doc": _t("Добавить ракет системе.", "Додати ракет системі.", "Add missiles to a system.")},
			{"sig": "uad.has_weapon(id)", "ins": "uad.has_weapon(\"patriot\")", "doc": _t("Куплена ли система.", "Чи куплено систему.", "Whether a system is bought.")},
			{"sig": "uad.heal_city(n)", "ins": "uad.heal_city(5)", "doc": _t("Город +n% целости (меньше нуля — урон).", "Місто +n% цілості (менше нуля — шкода).", "City +n% health (below zero — damage).")},
			{"sig": "uad.city_health()", "ins": "uad.city_health()", "doc": _t("Целость города, 0–100.", "Цілість міста, 0–100.", "City health, 0–100.")},
			{"sig": "uad.stat(name)", "ins": "uad.stat(\"kills\")", "doc": _t("Счётчик мира: kills, impacts, homes, earned, k_shahed…", "Лічильник світу: kills, impacts, homes, earned, k_shahed…", "A world counter: kills, impacts, homes, earned, k_shahed…")},
			{"sig": "uad.data", "ins": "uad.data[\"score\"] = uad.data.get(\"score\", 0) + 1", "doc": _t("Словарь мода, сохраняется вместе с миром.", "Словник мода, зберігається разом зі світом.", "The mod's dict, saved with the world.")},
			{"sig": "uad.shader_param(name, value)", "ins": "uad.shader_param(\"strength\", 0.8)", "doc": _t("Меняет uniform шейдеров-модов этого мира.", "Змінює uniform шейдерів-модів цього світу.", "Changes a uniform of this world's picture mods.")},
		]},
		{"title": _t("Сведения", "Відомості", "Information"), "items": [
			{"sig": "uad.weapons()", "ins": "uad.weapons()", "doc": _t("Список id систем.", "Список id систем.", "The list of system ids.")},
			{"sig": "uad.enemies()", "ins": "uad.enemies()", "doc": _t("Список id угроз.", "Список id загроз.", "The list of threat ids.")},
			{"sig": "uad.weapon_info(id)", "ins": "print(uad.weapon_info(\"s300\"))", "doc": _t("Все поля системы (словарь).", "Усі поля системи (словник).", "All fields of a system (a dict).")},
			{"sig": "uad.enemy_info(id)", "ins": "print(uad.enemy_info(\"shahed\"))", "doc": _t("Все поля угрозы.", "Усі поля загрози.", "All fields of a threat.")},
			{"sig": "uad.city()", "ins": "uad.city()", "doc": _t("id города мира: kyiv, kharkiv, dnipro, odesa или свой.", "id міста світу: kyiv, kharkiv, dnipro, odesa або свій.", "The world's city id: kyiv, kharkiv, dnipro, odesa or a drawn one.")},
			{"sig": "uad.difficulty()", "ins": "uad.difficulty()", "doc": _t("Сложность: 0, 1, 2.", "Складність: 0, 1, 2.", "Difficulty: 0, 1, 2.")},
			{"sig": "uad.language()", "ins": "uad.language()", "doc": _t("Язык игры: ru, uk, en.", "Мова гри: ru, uk, en.", "The game's language: ru, uk, en.")},
		]},
		{"title": _t("Python", "Python", "Python"), "items": [
			{"sig": "print(…)", "ins": "print(\"x =\", x)", "doc": _t("Вывод в консоль мастерской (и в журнал игры для разработки).", "Виведення в консоль майстерні.", "Output to the workshop console.")},
			{"sig": "class …:", "ins": "class Counter:\n    def __init__(self):\n        self.n = 0\n\n    def add(self, k=1):\n        self.n += k\n        return self.n\n",
				"doc": _t("Классы, наследование, super(), исключения, списки, словари, f-строки, генераторы списков — всё как в Python 3.", "Класи, успадкування, super(), винятки, списки, словники, f-рядки — усе як у Python 3.", "Classes, inheritance, super(), exceptions, lists, dicts, f-strings, comprehensions — as in Python 3.")},
			{"sig": "import helpers", "ins": "import helpers\n", "doc": _t("Подключить другой файл мода («＋ Файл»). Есть и math, random.", "Підключити інший файл мода («＋ Файл»). Є і math, random.", "Use another file of the mod (\"＋ File\"). math and random are there too.")},
			{"sig": "try / except", "ins": "try:\n    pass\nexcept Exception as e:\n    print(\"ошибка:\", e)\n", "doc": _t("Перехват ошибок.", "Перехоплення помилок.", "Catching errors.")},
		]},
	]


static func _shader_sections() -> Array:
	return [
		{"title": _t("Основа", "Основа", "Basics"), "items": [
			{"sig": "texture(screen, SCREEN_UV)", "ins": "vec3 c = texture(screen, SCREEN_UV).rgb;", "doc": _t("Цвет картинки игры в этой точке.", "Колір картинки гри в цій точці.", "The colour of the game's picture at this point.")},
			{"sig": "COLOR = vec4(c, 1.0);", "ins": "COLOR = vec4(c, 1.0);", "doc": _t("Что выводится в этой точке.", "Що виводиться в цій точці.", "What is shown at this point.")},
			{"sig": "uniform float … : hint_range", "ins": "uniform float strength : hint_range(0.0, 1.0) = 0.5;\n", "doc": _t("Параметр; мод на Python меняет его через uad.shader_param().", "Параметр; мод на Python змінює його через uad.shader_param().", "A parameter; a Python mod changes it with uad.shader_param().")},
			{"sig": "TIME", "ins": "float t = TIME;", "doc": _t("Секунды с запуска — для анимации.", "Секунди від запуску — для анімації.", "Seconds since start — for animation.")},
		]},
		{"title": _t("Связь с игрой", "Зв'язок із грою", "Linked to the game"), "items": [
			{"sig": "uniform float uad_night", "ins": "uniform float uad_night = 0.0;\n", "doc": _t("1 ночью, 0 днём (игра обновляет раз в секунду).", "1 вночі, 0 удень (гра оновлює щосекунди).", "1 at night, 0 by day (the game updates it every second).")},
			{"sig": "uniform float uad_alarm", "ins": "uniform float uad_alarm = 0.0;\n", "doc": _t("1, когда объявлена тревога.", "1, коли оголошено тривогу.", "1 while the air raid alarm is on.")},
			{"sig": "uniform float uad_city", "ins": "uniform float uad_city = 1.0;\n", "doc": _t("Целость города 0…1.", "Цілість міста 0…1.", "City health 0…1.")},
		]},
		{"title": _t("Приёмы", "Прийоми", "Recipes"), "items": [
			{"sig": "ч/б · grayscale", "ins": "float g = dot(c, vec3(0.299, 0.587, 0.114));\nc = vec3(g);\n", "doc": _t("Чёрно-белая картинка.", "Чорно-біла картинка.", "Black and white.")},
			{"sig": "виньетка · vignette", "ins": "float v = smoothstep(0.85, 0.3, length(SCREEN_UV - 0.5));\nc *= v;\n", "doc": _t("Затемнение по краям.", "Затемнення по краях.", "Darker edges.")},
			{"sig": "зерно · grain", "ins": "float n = fract(sin(dot(SCREEN_UV * 1000.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);\nc += (n - 0.5) * 0.08;\n", "doc": _t("Шум плёнки.", "Шум плівки.", "Film noise.")},
			{"sig": "строки · scanlines", "ins": "c *= 0.85 + 0.15 * sin(SCREEN_UV.y * 900.0);\n", "doc": _t("Строки старого экрана.", "Рядки старого екрана.", "Old screen lines.")},
			{"sig": "смещение RGB · aberration", "ins": "float r = texture(screen, SCREEN_UV + vec2(0.002, 0.0)).r;\nfloat b = texture(screen, SCREEN_UV - vec2(0.002, 0.0)).b;\nc = vec3(r, c.g, b);\n", "doc": _t("Цветная кайма объектива.", "Кольорова облямівка об'єктива.", "Lens colour fringes.")},
			{"sig": "тревога · alarm tint", "ins": "c = mix(c, c * vec3(1.3, 0.6, 0.6), uad_alarm * (0.5 + 0.5 * sin(TIME * 4.0)));\n", "doc": _t("Красная пульсация во время тревоги.", "Червона пульсація під час тривоги.", "A red pulse during the alarm.")},
		]},
	]


# --- templates ------------------------------------------------------------------------------
const TEMPLATES := [
	{"id": "empty", "kind": "mod", "icon": "🧩", "title": {"ru": "Пустой мод", "uk": "Порожній мод", "en": "Empty mod"},
		"desc": {"ru": "Сообщение в начале игры — с чего начать.", "uk": "Повідомлення на початку гри — з чого почати.", "en": "A message when the game starts — a place to begin."}},
	{"id": "weapon", "kind": "mod", "icon": "🛡", "title": {"ru": "Новая система ПВО", "uk": "Нова система ППО", "en": "New air defence system"},
		"desc": {"ru": "Свой ЗРК ближнего рубежа: дальность, урон, цена, наша модель с цветом.", "uk": "Свій ЗРК ближнього рубежу: дальність, шкода, ціна, наша модель із кольором.", "en": "Your own short range SAM: range, damage, price, our model in a colour."}},
	{"id": "own_model", "kind": "mod", "icon": "🧱", "title": {"ru": "Своя модель (3D)", "uk": "Своя модель (3D)", "en": "Own model (3D)"},
		"desc": {"ru": "Система ПВО и угроза со своими моделями из 3D-редактора.", "uk": "Система ППО і загроза зі своїми моделями з 3D-редактора.", "en": "A system and a threat with models of their own from the 3D editor."}},
	{"id": "enemy", "kind": "mod", "icon": "🛩", "title": {"ru": "Новая угроза и налёт", "uk": "Нова загроза і наліт", "en": "New threat and raid"},
		"desc": {"ru": "Свой дрон: скорость, прочность, награда — и он летит в налётах.", "uk": "Свій дрон: швидкість, міцність, нагорода — і він летить у нальотах.", "en": "Your own drone: speed, toughness, reward — and it flies in the raids."}},
	{"id": "rules", "kind": "mod", "icon": "⚙", "title": {"ru": "Свои правила (события)", "uk": "Свої правила (події)", "en": "Your own rules (events)"},
		"desc": {"ru": "Серии сбитий с премией, класс, сохранение в мире, атака по таймеру.", "uk": "Серії збиттів із премією, клас, збереження у світі, атака за таймером.", "en": "Kill streaks with a bonus, a class, data saved in the world, a timed attack."}},
	{"id": "night_vision", "kind": "shader", "icon": "🎨", "title": {"ru": "Графика: ночное видение", "uk": "Графіка: нічне бачення", "en": "Picture: night vision"},
		"desc": {"ru": "Зелёный прибор ночного видения с шумом — сильнее ночью.", "uk": "Зелений прилад нічного бачення з шумом — сильніше вночі.", "en": "A green night vision scope with noise — stronger at night."}},
	{"id": "film", "kind": "shader", "icon": "🎞", "title": {"ru": "Графика: старая плёнка", "uk": "Графіка: стара плівка", "en": "Picture: old film"},
		"desc": {"ru": "Сепия, зерно, виньетка и красная пульсация при тревоге.", "uk": "Сепія, зерно, віньєтка і червона пульсація під час тривоги.", "en": "Sepia, grain, vignette and a red pulse during the alarm."}},
]


static func template(id: String) -> Dictionary:
	for t in TEMPLATES:
		if String(t.id) == id:
			return t
	return TEMPLATES[0]


static func template_files(id: String) -> Dictionary:
	var c := func(ru: String, uk: String, en: String) -> String: return tr3(_t(ru, uk, en))
	match id:
		"weapon":
			return {"main.py": """# %s
import uad

uad.weapon("my_sam", type="short",
    name={"ru": "ЗРК «Стрела-М»", "uk": "ЗРК «Стріла-М»", "en": "Strela-M SAM"},
    short="СТРЕЛА-М",
    desc={"ru": "Свой комплекс малой дальности.", "uk": "Свій комплекс малої дальності.", "en": "A short range system of our own."},
    range=6500,          # %s
    damage=120,
    rate=1.4,            # %s
    unlock=9000,         # %s
    missile_price=700,
    start_ammo=10,
    eff={"scout": 1.0, "shahed": 1.0, "cruise": 0.8, "ballistic": 0.0},
    model="avenger", tint="#9fc4ff", scale=1.1)

print("my_sam:", uad.weapon_info("my_sam")["range"], "m")
""" % [c.call("Новая система ПВО появится в магазине.", "Нова система ППО з'явиться в магазині.", "The new system shows up in the shop."),
				c.call("метров", "метрів", "metres"), c.call("секунд между пусками", "секунд між пусками", "seconds between launches"),
				c.call("цена", "ціна", "price")]}
		"enemy":
			return {"main.py": """# %s
import uad

uad.enemy("lancet", type="drone", model="shahed",
    name={"ru": "Барражирующий «Ланцет»", "uk": "Баражуючий «Ланцет»", "en": "Lancet loitering munition"},
    plural="ЛАНЦЕТЫ", abbr="Л",
    speed=80, hp=22, alt_min=150, alt_max=900,
    reward=1800, hit_damage=2.0, hit_cost=2500,
    color="#ff6a3d", tint=[1.0, 0.45, 0.35], scale=0.8)

# %s
uad.raid("lancet", night=2, weight=1.5)

@uad.on("kill")
def lancet_down(e):
    if e["type"] == "lancet":
        uad.message("+300: «Ланцет» сбит", "#7dffb0")
        uad.give_money(300)
""" % [c.call("Новая угроза и её место в налётах.", "Нова загроза і її місце в нальотах.", "A new threat and its place in the raids."),
				c.call("Летит в налётах со второй ночи, в полтора раза чаще обычного.", "Летить у нальотах із другої ночі, у півтора раза частіше звичайного.", "Flies in the raids from night two, half again as often as usual.")]}
		"own_model":
			return {"main.py": """# %s
import uad

uad.weapon("my_sam", type="medium", model="my_sam.uadmodel",
    name={"ru": "Мой ЗРК", "uk": "Мій ЗРК", "en": "My SAM"},
    range=9000, damage=150, unlock=12000, missile_price=1000)

uad.enemy("my_drone", type="drone", model="my_drone.uadmodel",
    name={"ru": "Мой дрон", "uk": "Мій дрон", "en": "My drone"},
    speed=60, hp=26, reward=1500)
uad.raid("my_drone", night=1, weight=2)
""" % c.call("Модели — в файлах my_sam.uadmodel и my_drone.uadmodel слева: откройте и меняйте в 3D.", "Моделі — у файлах my_sam.uadmodel і my_drone.uadmodel ліворуч: відкрийте й змінюйте в 3D.", "The models are the files my_sam.uadmodel and my_drone.uadmodel on the left: open and change them in 3D."),
				"my_sam.uadmodel": JSON.stringify(ModelEditor.starter("weapon"), "\t"), "my_drone.uadmodel": JSON.stringify(ModelEditor.starter("enemy"), "\t")}
		"rules":
			return {"main.py": """# %s
import uad
import random


class Streak:
    \"\"\"%s\"\"\"

    def __init__(self):
        self.n = 0
        self.best = 0

    def hit(self):
        self.n += 1
        self.best = max(self.best, self.n)
        return self.n

    def miss(self):
        self.n = 0


streak = Streak()


@uad.on("start")
def start(e):
    uad.data["worlds_opened"] = uad.data.get("worlds_opened", 0) + 1
    uad.message(f"%s {uad.data['worlds_opened']}")


@uad.on("kill")
def kill(e):
    n = streak.hit()
    if n %% 5 == 0:
        bonus = 250 * n
        uad.give_money(bonus)
        uad.alert(f"%s ×{n}: +${bonus}")


@uad.on("impact")
def impact(e):
    streak.miss()


@uad.on("tick")
def tick(e):
    # %s
    if e["night"] and e["t"] %% 45 == 0 and random.random() < 0.5:
        uad.launch(random.choice(["shahed", "gerbera"]), 2)


@uad.on("morning")
def morning(e):
    uad.data["best"] = max(uad.data.get("best", 0), streak.best)
    uad.message(f"%s: {streak.best}")
""" % [c.call("Свои правила: серии сбитий, премии и внезапные атаки.", "Свої правила: серії збиттів, премії і раптові атаки.", "Your own rules: kill streaks, bonuses and sudden attacks."),
				c.call("Серия сбитий без прорывов.", "Серія збиттів без проривів.", "A run of kills with nothing getting through."),
				c.call("Мод правил: открытий мира —", "Мод правил: відкриттів світу —", "Rules mod: times the world opened —"),
				c.call("СЕРИЯ", "СЕРІЯ", "STREAK"),
				c.call("Ночью иногда внезапная пара дронов.", "Уночі часом раптова пара дронів.", "At night now and then a sudden pair of drones."),
				c.call("Лучшая серия ночи", "Найкраща серія ночі", "Best streak of the night")]}
		"night_vision":
			return {"shader.uadshader": """// name: %s
// description: %s
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.85;
uniform float uad_night = 0.0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	g = pow(g, 0.6) * 1.4;
	float n = fract(sin(dot(SCREEN_UV * 900.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 nv = vec3(0.15, 1.0, 0.35) * (g + (n - 0.5) * 0.12);
	nv *= smoothstep(0.75, 0.35, length(SCREEN_UV - 0.5));
	float k = strength * mix(0.35, 1.0, uad_night);
	COLOR = vec4(mix(c, nv, k), 1.0);
}
""" % [c.call("Ночное видение", "Нічне бачення", "Night vision"), c.call("Зелёный ПНВ, ночью сильнее", "Зелений ПНБ, уночі сильніше", "Green scope, stronger at night")]}
		"film":
			return {"shader.uadshader": """// name: %s
// description: %s
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float sepia : hint_range(0.0, 1.0) = 0.7;
uniform float uad_alarm = 0.0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 s = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
	c = mix(c, s, sepia);
	float n = fract(sin(dot(SCREEN_UV * 1000.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * 0.07;
	c *= smoothstep(0.9, 0.3, length(SCREEN_UV - 0.5));
	c = mix(c, c * vec3(1.35, 0.6, 0.55), uad_alarm * (0.5 + 0.5 * sin(TIME * 4.0)) * 0.6);
	COLOR = vec4(c, 1.0);
}
""" % [c.call("Старая плёнка", "Стара плівка", "Old film"), c.call("Сепия, зерно, тревога красным", "Сепія, зерно, тривога червоним", "Sepia, grain, the alarm in red")]}
	return {"main.py": """# %s
import uad


@uad.on("start")
def hello(e):
    uad.message("%s")
    print("start:", e)
""" % [c.call("Мой первый мод. Справочник справа: нажмите строку — она вставится сюда.", "Мій перший мод. Довідник праворуч: натисніть рядок — він вставиться сюди.", "My first mod. The reference is on the right: tap a line to insert it here."),
		c.call("Привет от мода!", "Привіт від мода!", "Hello from the mod!")]}
