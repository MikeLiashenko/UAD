extends RefCounted
## Orders of the command: every morning from the second day the staff gives the battery one task
## for the day and the night ahead, with a bonus for doing it — strike that site, catch a launcher
## in the act, keep the city clean of hits, bring down so many targets, find a new launch area.
## The next morning the order is checked (before the enemy has mended anything overnight) and
## the bonus paid; then the next one comes.
##
## State: GS.order (saved with the world) — {kind, site, n, reward, day, base: {hunts, known}}, or {}.

const Strikes = preload("res://scripts/game/strikes.gd")

const KINDS := ["strike", "hunt", "clean", "kills", "intel"]


## The day's order (and GS.order set to it), or {} when there is nothing to order.
static func issue(city, rng: RandomNumberGenerator) -> Dictionary:
	if not GS.order.is_empty() and int(GS.order.get("day", 0)) == GS.day:
		return GS.order # the world was saved during this day: the order stands
	GS.order = {}
	if GS.day < Strikes.FIRST_DAY:
		return {}
	var options := []
	var known := []
	var unknown := 0
	var huntable := false
	for s in Strikes.sites(city):
		var st := Strikes.state(String(s.id))
		if not bool(st.known):
			unknown += 1
		elif String(st.st) == "ok" and _reachable(s):
			known.append(s)
		if Strikes.can_hunt(s):
			huntable = true
	if not known.is_empty():
		options.append_array(["strike", "strike"])
	if huntable:
		options.append("hunt")
	if unknown > 0:
		options.append("intel")
	options.append_array(["clean", "kills"])
	var kind := String(options[rng.randi() % options.size()])
	var m := GS.income_mult()
	var o := {"kind": kind, "site": "", "n": 0, "day": GS.day, "base": {"hunts": int(GS.stats.get("hunts", 0)), "known": _known()}}
	match kind:
		"strike":
			var s: Dictionary = known[rng.randi() % known.size()]
			o.site = String(s.id)
			o.reward = int((10000 + 1000 * GS.day) * m)
		"hunt":
			o.reward = int(9000 * m)
		"intel":
			o.reward = int(5000 * m)
		"clean":
			o.reward = int((7000 + 500 * GS.day) * m)
		"kills":
			o.n = clampi(4 + GS.day * 2, 6, 30)
			o.reward = int((6000 + 400 * GS.day) * m)
	GS.order = o
	return o


## Some weapon of ours gets there once it is in service (money aside).
static func _reachable(s: Dictionary) -> bool:
	for w in Strikes.WEAPONS:
		var wd: Dictionary = Strikes.WEAPONS[w]
		if float(s.km) <= float(wd.range) and (not bool(s.naval) or bool(wd.naval)):
			return true
	return false


static func _known() -> int:
	var n := 0
	for id in GS.sites:
		if bool(GS.sites[id].get("known", false)) and not Strikes.KINDS.get(String(id), {}).has("supply"):
			n += 1
	return n


## The order as one line: "Поразите «Искандеры» · +$12 000".
static func text(o: Dictionary) -> String:
	if o.is_empty():
		return ""
	var what := ""
	match String(o.kind):
		"strike":
			what = GS.t("Поразите цель «%s»") % GS.t(String(Strikes.KINDS.get(String(o.site), {}).get("short", o.site)))
		"hunt":
			what = GS.t("Накройте пусковую в момент пуска")
		"intel":
			what = GS.t("Найдите новый район пуска")
		"clean":
			what = GS.t("Ни одного прилёта по городу этой ночью")
		"kills":
			what = GS.t("Сбейте за ночь не меньше %d целей") % int(o.n)
	return "%s · +%s" % [what, GS.fmt_money(int(o.reward))]


## Morning: was the order carried out? `report` is the night's morning report (kills, impacts,
## homes). Pays the bonus and clears GS.order; returns {done, reward, text} or {} without an order.
static func check(report: Dictionary) -> Dictionary:
	var o: Dictionary = GS.order
	if o.is_empty():
		return {}
	var done := false
	var base: Dictionary = o.get("base", {})
	match String(o.kind):
		"strike":
			done = String(Strikes.state(String(o.site)).st) != "ok"
		"hunt":
			done = int(GS.stats.get("hunts", 0)) > int(base.get("hunts", 0))
		"intel":
			done = _known() > int(base.get("known", 0))
		"clean":
			done = int(report.get("impacts", 0)) == 0 and int(report.get("homes", 0)) == 0
		"kills":
			done = int(report.get("kills", 0)) >= int(o.n)
	var out := {"done": done, "reward": int(o.reward) if done else 0, "text": text(o)}
	if done:
		GS.add_money(int(o.reward))
		GS.stats["orders"] = int(GS.stats.get("orders", 0)) + 1
	GS.order = {}
	return out
