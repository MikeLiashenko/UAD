extends RefCounted
## Counter-strikes on the places the raids come from. Every city has its launch sites — the
## drone launch pads, the bomber airfields, the ships with Kalibrs, the Iskander positions … —
## on the bearings its threats really arrive from. A site is unknown until one of its weapons
## has flown at the city (the radar tracks the launch back). By day the player sends long-range
## drones and missiles at the known ones; they arrive at dusk: a damaged site launches half as
## much for a couple of nights, a destroyed one stays silent until the enemy has rebuilt it —
## and every strike makes it defend itself better next time.
##
## State lives in GS (saved with the world): GS.sites {kind: {known, st, n, def}} and the
## strikes in flight GS.strikes [{site, w}]. The director reads output() while it builds a night.

const FIRST_DAY := 2

## What we strike with. range: km; hit: chance against an undefended site; effect on a hit;
## nights it lasts; naval: can hit ships; from: the day it comes into service; pierce: the share
## of the site's air defence it gets through regardless (a ballistic missile is seldom caught);
## swarm: a drone that draws the site's fire off the others; fast: seconds of flight when it goes
## at a launcher caught in the act (a hunt, any hour) instead of waiting for dusk.
const WEAPONS := {
	"lyutyi": {"name": "Дальний дрон «Лютый»", "short": "«ЛЮТЫЙ»", "price": 4500, "range": 1100.0, "hit": 0.6,
		"effect": "damaged", "nights": 2, "naval": false, "swarm": true,
		"desc": "Дёшево и далеко — достаёт даже до аэродромов стратегической авиации, но чаще повреждает, чем уничтожает."},
	"himars": {"name": "РСЗО HIMARS (ракеты GMLRS)", "short": "HIMARS", "price": 7000, "range": 85.0, "hit": 0.86,
		"effect": "destroyed", "nights": 2, "naval": false, "fast": 12.0,
		"desc": "Высокоточные ракеты GMLRS: только ближние позиции у границы — до 85 км, зато дёшево и почти наверняка."},
	"palianytsia": {"name": "Ракета-дрон «Паляница»", "short": "«ПАЛЯНИЦА»", "price": 9000, "range": 650.0, "hit": 0.7,
		"effect": "damaged", "nights": 3, "naval": false, "from": 3, "swarm": true,
		"desc": "Реактивный дрон-ракета до 650 км: прорывается чаще «Лютого», а подожжённая точка горит дольше."},
	"neptune": {"name": "Ракета «Нептун»", "short": "«НЕПТУН»", "price": 12000, "range": 400.0, "hit": 0.72,
		"effect": "destroyed", "nights": 2, "naval": true,
		"desc": "Крылатая ракета: бьёт и по кораблям, и по наземным позициям до 400 км."},
	"storm": {"name": "Ракета Storm Shadow", "short": "STORM SHADOW", "price": 21000, "range": 260.0, "hit": 0.88,
		"effect": "destroyed", "nights": 3, "naval": false,
		"desc": "Малозаметная и точная — почти наверняка уничтожает наземную цель в пределах 260 км."},
	"atacms": {"name": "Баллистическая ракета ATACMS", "short": "ATACMS", "price": 26000, "range": 300.0, "hit": 0.86,
		"effect": "destroyed", "nights": 3, "naval": false, "from": 5, "pierce": 0.6, "fast": 20.0,
		"desc": "Баллистика до 300 км: ПВО точки почти не успевает её перехватить — лучшая по сильно защищённым позициям."},
	"flamingo": {"name": "Крылатая ракета FP-5 «Фламинго»", "short": "«ФЛАМИНГО»", "price": 34000, "range": 3000.0, "hit": 0.8,
		"effect": "destroyed", "nights": 4, "naval": false, "from": 7,
		"desc": "Тяжёлая крылатая ракета на 3000 км и тонна взрывчатки: уничтожает даже аэродромы стратегической авиации."},
}
const WEAPON_ORDER := ["lyutyi", "himars", "palianytsia", "neptune", "storm", "atacms", "flamingo"]

## Launch-site kinds: which threats start there, how far (km) from each city, and the site's
## own air defence (0..1, it grows after every strike). reserve: the share that still flies with
## the site knocked out (drones also start from spare pads; an airfield or a ship has no spare).
## hunt: the launchers stand in the open while they fire — for HOT_TIME seconds after a launch
## they can be hit at once (an airfield's bombers or the ships fire from far away and leave).
const KINDS := {
	"recon": {"hunt": true, "short": "Пункт разведки БПЛА", "name": "Пункт управления разведывательными БПЛА", "icon": "drone", "weapons": ["scout"],
		"km": {"kyiv": 140.0, "kharkiv": 60.0, "dnipro": 120.0, "odesa": 150.0}, "def": 0.15},
	"drones": {"hunt": true, "short": "Площадка шахедов", "name": "Стартовая площадка ударных БПЛА", "icon": "drone", "weapons": ["shahed", "gerbera", "geran3", "geran4", "geran5"],
		"km": {"kyiv": 470.0, "kharkiv": 190.0, "dnipro": 360.0, "odesa": 300.0}, "def": 0.25, "reserve": 0.3},
	"molniya": {"hunt": true, "short": "Операторы «Молний»", "name": "Позиции операторов «Молний»", "icon": "drone", "weapons": ["molniya"],
		"km": {"kharkiv": 45.0}, "def": 0.15},
	"strategic": {"short": "Аэродром Ту-95МС", "name": "Аэродром стратегической авиации (Ту-95МС)", "icon": "plane", "weapons": ["cruise"],
		"km": {"kyiv": 980.0, "kharkiv": 690.0, "dnipro": 900.0, "odesa": 1050.0}, "def": 0.45},
	"fleet": {"short": "Флот «Калибров»", "name": "Корабли-носители «Калибров»", "icon": "ship", "weapons": ["kalibr"], "naval": true,
		"km": {"kyiv": 650.0, "kharkiv": 600.0, "dnipro": 520.0, "odesa": 330.0}, "def": 0.5},
	"bastion": {"hunt": true, "short": "«Бастион»", "name": "Береговой комплекс «Бастион»", "icon": "missile", "weapons": ["oniks", "zircon"],
		"km": {"kyiv": 640.0, "dnipro": 420.0, "odesa": 260.0}, "def": 0.4},
	"iskander": {"hunt": true, "short": "«Искандеры»", "name": "Позиции «Искандеров»", "icon": "missile", "weapons": ["ballistic"],
		"km": {"kyiv": 320.0, "kharkiv": 110.0, "dnipro": 260.0, "odesa": 250.0}, "def": 0.35},
	"kinzhal": {"short": "Аэродром МиГ-31К", "name": "Аэродром МиГ-31К («Кинжалы»)", "icon": "plane", "weapons": ["kinzhal"],
		"km": {"kyiv": 820.0}, "def": 0.45},
	"kh22": {"short": "Аэродром Ту-22М3", "name": "Аэродром дальней авиации (Ту-22М3)", "icon": "plane", "weapons": ["kh22"],
		"km": {"dnipro": 760.0, "odesa": 700.0}, "def": 0.45},
	"s300": {"hunt": true, "short": "Позиции С-300", "name": "Позиции С-300 у границы", "icon": "missile", "weapons": ["s300"],
		"km": {"kharkiv": 55.0}, "def": 0.3},
	"s400": {"hunt": true, "short": "Дивизион С-400", "name": "Дивизион С-400 (бьёт по земле)", "icon": "missile", "weapons": ["s400"],
		"km": {"kyiv": 190.0, "kharkiv": 70.0, "dnipro": 130.0, "odesa": 170.0}, "def": 0.55},
	"s500": {"hunt": true, "short": "Дивизион С-500", "name": "Дивизион С-500 «Прометей»", "icon": "missile", "weapons": ["s500"],
		"km": {"kyiv": 330.0, "kharkiv": 180.0, "dnipro": 260.0, "odesa": 230.0}, "def": 0.6},
	"kab": {"short": "Аэродром Су-34", "name": "Аэродром фронтовой авиации (Су-34, КАБ)", "icon": "plane", "weapons": ["kab"],
		"km": {"kharkiv": 140.0}, "def": 0.4},
	"su24": {"short": "Аэродром Су-24", "name": "Аэродром Су-24 в Крыму (Х-31П)", "icon": "plane", "weapons": ["kh31p"],
		"km": {"odesa": 240.0}, "def": 0.4},
}


## Every weapon the city is attacked with (the director's slots, extras and events) plus the scouts.
static func city_weapons(city) -> Array:
	var out := ["scout"]
	for slot in city.raid:
		for o in city.raid[slot]:
			if not out.has(String(o[0])):
				out.append(String(o[0]))
	for x in city.raid_extra:
		if not out.has(String(x.weapon)):
			out.append(String(x.weapon))
	return out


## The launch sites of a city: [{id, name, icon, weapons, bearing (deg), km, def, naval}].
static func sites(city) -> Array:
	var used := city_weapons(city)
	var out := []
	var where := String(city.sites_as) if String(city.sites_as) != "" else String(city.id)
	for id in KINDS:
		var k: Dictionary = KINDS[id]
		var km: Dictionary = k.km
		if not km.has(where):
			continue
		var ws := []
		for w in k.weapons:
			if used.has(String(w)):
				ws.append(String(w))
		if ws.is_empty():
			continue
		out.append({"id": id, "name": String(k.name), "short": String(k.get("short", k.name)), "icon": String(k.icon), "weapons": ws,
			"bearing": _bearing(city, ws), "km": float(km[where]), "def": float(k.def),
			"naval": bool(k.get("naval", false))})
	return out


## Mean bearing of the sectors the site's weapons come in on (the city's own sectors for drones).
static func _bearing(city, ws: Array) -> float:
	var v := Vector2.ZERO
	for w in ws:
		var sec: Array = city.raid_sectors.get(w, city.threat_sectors)
		for a in sec:
			v += Vector2(sin(deg_to_rad(float(a))), cos(deg_to_rad(float(a))))
	return fposmod(rad_to_deg(atan2(v.x, v.y)), 360.0)


static func site(city, id: String) -> Dictionary:
	for s in sites(city):
		if String(s.id) == id:
			return s
	return {}


## Saved state of a site: known, st ("ok" | "damaged" | "destroyed"), n (nights left), def (added).
static func state(id: String) -> Dictionary:
	var s = GS.sites.get(id)
	if s is Dictionary:
		return s
	return {"known": false, "st": "ok", "n": 0, "def": 0.0}


static func _put(id: String, s: Dictionary) -> void:
	GS.sites[id] = s


## Share of its usual launches a site manages now.
static func site_output(id: String) -> float:
	var reserve := float(KINDS.get(id, {}).get("reserve", 0.0))
	match String(state(id).st):
		"damaged":
			return maxf(0.5, reserve)
		"destroyed":
			return reserve
	return 1.0


## Share of the usual number of `weapon` the enemy can launch tonight (1 when no site of ours
## launches it — the Oreshnik is out of reach).
static func output(city, weapon: String) -> float:
	var n := 0
	var sum := 0.0
	for s in sites(city):
		if (s.weapons as Array).has(weapon):
			n += 1
			sum += site_output(String(s.id))
	return sum / n if n > 0 else 1.0


## The radar tracked `weapon` back to where it came from: the site becomes known. Returns the
## site when it is discovered just now, otherwise {}.
static func seen(city, weapon: String) -> Dictionary:
	for s in sites(city):
		if (s.weapons as Array).has(weapon):
			var st := state(String(s.id))
			if not bool(st.known):
				st.known = true
				_put(String(s.id), st)
				return s
	return {}


## Why `weapon` cannot go at the site now, or "" when it can.
static func blocker(s: Dictionary, weapon: String, is_day: bool) -> String:
	var w: Dictionary = WEAPONS[weapon]
	if GS.day < FIRST_DAY:
		return GS.t("Удары — со второго дня")
	if GS.day < int(w.get("from", FIRST_DAY)):
		return GS.t("Поступит на вооружение на %d-й день") % int(w.from)
	if not bool(state(String(s.id)).known):
		return GS.t("Район пуска ещё не установлен")
	if float(s.km) > float(w.range):
		return GS.t("Не достаёт: %d км") % int(w.range)
	if bool(s.naval) and not bool(w.naval):
		return GS.t("Не бьёт по кораблям")
	if not is_day and not is_hunt(s, weapon):
		return GS.t("Удары наносятся днём")
	if GS.money < int(w.price):
		return GS.t("Не хватает денег")
	return ""


# --- Hunting the launchers ------------------------------------------------------------------
## Seconds a launcher stays in the open after it has fired: the radar has its position, HIMARS or
## ATACMS (the `fast` weapons) can go at it at once, by day or by night. A hit silences the rest
## of the site's launches tonight (and longer, by the weapon's nights).
const HOT_TIME := 40.0
## {site id: seconds the launcher is still where it fired from}. Not saved: a night is not.
static var hot := {}
## Hunts in flight: [{site, w, t (seconds left), flight, p (chance, fixed at the launch)}].
static var hunts: Array = []


static func reset_hunts() -> void:
	hot = {}
	hunts = []


## A launcher of this site is in the open and `weapon` is one that can be sent at it right now.
static func is_hunt(s: Dictionary, weapon: String) -> bool:
	return hot.has(String(s.id)) and WEAPONS[weapon].has("fast")


## Some fast weapon in service reaches the site.
static func can_hunt(s: Dictionary) -> bool:
	if GS.day < FIRST_DAY or not bool(KINDS.get(String(s.id), {}).get("hunt", false)):
		return false
	for w in WEAPONS:
		var wd: Dictionary = WEAPONS[w]
		if wd.has("fast") and GS.day >= int(wd.get("from", FIRST_DAY)) and float(s.km) <= float(wd.range):
			return true
	return false


## The radar saw `weapon` launched: the launchers of its sites that fire in the open are exposed
## for HOT_TIME. Returns the site that has just come into the open and can be hunted, else {}.
static func heat(city, weapon: String) -> Dictionary:
	var out := {}
	for s in sites(city):
		var id := String(s.id)
		if not (s.weapons as Array).has(weapon) or not bool(KINDS[id].get("hunt", false)) or not bool(state(id).known):
			continue
		if not hot.has(id) and out.is_empty() and can_hunt(s):
			out = s
		hot[id] = HOT_TIME
	return out


## The launcher drives off while the missile flies: the later the strike, the poorer its chance.
static func hunt_chance(s: Dictionary, weapon: String) -> float:
	var left := clampf(float(hot.get(String(s.id), 0.0)) / HOT_TIME, 0.0, 1.0)
	return chance(s, weapon) * (0.55 + 0.45 * left)


## Sends `weapon` at the site: at the launcher in the open now, or at dusk like every strike.
static func send(s: Dictionary, weapon: String) -> void:
	if not is_hunt(s, weapon):
		launch(s, weapon)
		return
	var f := float(WEAPONS[weapon].fast)
	hunts.append({"site": String(s.id), "w": weapon, "t": f, "flight": f, "p": hunt_chance(s, weapon)})
	GS.add_money(-int(WEAPONS[weapon].price))
	GS.state_changed.emit()


## Hunts in flight at this site.
static func hunting(id: String) -> int:
	return hunts.filter(func(h) -> bool: return String(h.site) == id).size()


## Time passes: the launchers drive off, the hunts fly. Returns the hunts that arrived just now as
## [{site, name, w, hit, st, n}]; a hit puts the site out at once, for the rest of tonight (n = the
## weapon's nights, this one counted).
static func hunt_step(city, delta: float, rng: RandomNumberGenerator) -> Array:
	for id in hot.keys():
		hot[id] = float(hot[id]) - delta
		if float(hot[id]) <= 0.0:
			hot.erase(id)
	var out := []
	for h in hunts.duplicate():
		h.t = float(h.t) - delta
		if float(h.t) > 0.0:
			continue
		hunts.erase(h)
		var s := site(city, String(h.site))
		if s.is_empty():
			continue
		var w: Dictionary = WEAPONS[String(h.w)]
		var st := state(String(s.id))
		var hit := rng.randf() < float(h.p)
		if hit:
			st.st = "destroyed" if String(w.effect) == "destroyed" or String(st.st) != "ok" else "damaged"
			st.n = maxi(int(st.n), maxi(int(w.nights) - 1, 1))
			hot.erase(String(s.id)) # nothing left standing there to strike
		st.def = minf(float(st.def) + 0.04, 0.35)
		_put(String(s.id), st)
		out.append({"site": String(s.id), "name": String(s.name), "w": String(h.w), "hit": hit, "st": String(st.st), "n": int(st.n)})
	return out


## The launches still to come tonight after a site went out: each entry of a weapon the site
## launched shrinks by what is left of that weapon's output (before: {weapon: output before}).
## Returns how many launches were called off.
static func thin(schedule: Array, city, before: Dictionary, rng: RandomNumberGenerator) -> int:
	var gone := 0
	for e in schedule.duplicate():
		if not e.has("type") or not before.has(String(e.type)):
			continue
		var b := float(before[String(e.type)])
		var k := output(city, String(e.type)) / b if b > 0.0 else 1.0
		if k >= 1.0:
			continue
		var c := int(e.count)
		var left := int(floor(c * k + rng.randf()))
		gone += c - left
		if left <= 0:
			schedule.erase(e)
		else:
			e.count = left
	return gone


## A combined strike: every drone (the swarm weapons) flying at a site together with the others
## keeps its air defence busy — each takes ESCORT_STEP off it, ESCORT_MAX at most.
const ESCORT_STEP := 0.1
const ESCORT_MAX := 0.3


## Chance that `weapon` gets through the site's air defence; `escort` is what the drones flying
## with it take off that defence.
static func chance(s: Dictionary, weapon: String, escort := 0.0) -> float:
	var w: Dictionary = WEAPONS[weapon]
	var d := maxf(clampf(float(s.def) + float(state(String(s.id)).def), 0.0, 0.9) - escort, 0.0) * (1.0 - float(w.get("pierce", 0.0)))
	return clampf(float(w.hit) * (1.0 - d * 0.75), 0.05, 0.95)


## The cover the drones already in flight at this site give one more strike sent there now.
static func escort(id: String) -> float:
	return minf(swarm_in_flight(id) * ESCORT_STEP, ESCORT_MAX)


## Drones (swarm weapons) in flight at this site.
static func swarm_in_flight(id: String) -> int:
	var n := 0
	for x in GS.strikes:
		if String(x.site) == id and bool(WEAPONS.get(String(x.w), {}).get("swarm", false)):
			n += 1
	return n


## Pays and sends the strike; it lands at dusk.
static func launch(s: Dictionary, weapon: String) -> void:
	GS.add_money(-int(WEAPONS[weapon].price))
	GS.strikes.append({"site": String(s.id), "w": weapon})
	GS.state_changed.emit()


## Strikes in flight at this site.
static func in_flight(id: String) -> int:
	var n := 0
	for x in GS.strikes:
		if String(x.site) == id:
			n += 1
	return n


## Dusk: every strike in flight arrives. Returns [{site, name, w, hit, st, n, escort}] for the
## briefing. At each site the drones come in first and draw the fire; the missiles behind them
## meet an air defence that is busy with them (escort). The enemy reinforces a struck site once a
## dusk, however many came at it.
static func resolve(city, rng: RandomNumberGenerator) -> Array:
	var out := []
	var groups := {}
	for x in GS.strikes:
		if WEAPONS.has(String(x.w)):
			if not groups.has(String(x.site)):
				groups[String(x.site)] = []
			groups[String(x.site)].append(String(x.w))
	for id in groups:
		var s := site(city, String(id))
		if s.is_empty():
			continue
		var ws: Array = groups[id]
		ws.sort_custom(func(a, b) -> bool: return bool(WEAPONS[a].get("swarm", false)) and not bool(WEAPONS[b].get("swarm", false)))
		var drones := 0
		for wid in ws:
			if bool(WEAPONS[wid].get("swarm", false)):
				drones += 1
		var st := state(String(s.id))
		for wid in ws:
			var w: Dictionary = WEAPONS[wid]
			# a drone is covered by the other drones, a missile by all of them
			var cover := minf((drones - (1 if bool(w.get("swarm", false)) else 0)) * ESCORT_STEP, ESCORT_MAX)
			var hit := rng.randf() < chance(s, String(wid), cover)
			if hit:
				var eff := String(w.effect)
				if eff == "destroyed" or String(st.st) == "destroyed":
					st.st = "destroyed"
				elif String(st.st) == "damaged":
					st.st = "destroyed" # a second blow on a damaged site finishes it
				else:
					st.st = "damaged"
				st.n = maxi(int(st.n), int(w.nights))
			out.append({"site": String(s.id), "name": String(s.name), "w": String(wid), "hit": hit, "st": String(st.st), "n": int(st.n), "escort": cover})
		# struck or not, the enemy brings in more air defence — once for the whole raid on it
		st.def = minf(float(st.def) + 0.08, 0.35)
		_put(String(s.id), st)
	GS.strikes = []
	return out


## Morning: a night has passed — the enemy repairs. Returns the names of sites back in service.
static func night_passed(city) -> Array:
	var back := []
	for s in sites(city):
		var id := String(s.id)
		var st := state(id)
		if String(st.st) != "ok" and int(st.n) > 0:
			st.n = int(st.n) - 1
			if int(st.n) <= 0:
				st.st = "ok"
				back.append(String(s.name))
			_put(id, st)
	return back


## "Повреждена — ещё 2 ночи вполсилы" and the like.
static func status_text(id: String) -> String:
	var st := state(id)
	if not bool(st.known):
		return GS.t("Не обнаружена")
	match String(st.st):
		"damaged":
			return GS.t("Повреждена — вполсилы ещё %d ноч.") % int(st.n)
		"destroyed":
			if float(KINDS.get(id, {}).get("reserve", 0.0)) > 0.0:
				return GS.t("Уничтожена — ещё %d ноч. пуски только с запасных площадок") % int(st.n)
			return GS.t("Уничтожена — молчит ещё %d ноч.") % int(st.n)
	return GS.t("Действует")


## A bearing as a compass word for the briefings.
static func compass(deg: float) -> String:
	var names := ["с севера", "с северо-востока", "с востока", "с юго-востока", "с юга", "с юго-запада", "с запада", "с северо-запада"]
	return GS.t(names[int(round(fposmod(deg, 360.0) / 45.0)) % 8])
