extends Node
## A match on a server (ServerDef): two cities fire at each other. Every player defends the city
## of their side with the usual battery and, on the attack screen (scripts/ui/attack_map.gd),
## buys drones and missiles and sends them at a point of the other city. A strike spends a while
## between the cities (the defenders are warned), then comes in over the target city as a raid
## like any other; whoever's city falls to zero has lost.
##
## One machine per city flies the raid on it — the `authority`: in a draft's test this one (the
## other city is played by the Bot below, as numbers only), on a published server the captain of
## the side (Net, the host of its session). Strikes and their outcomes travel as small records:
##   strike  {id, w: weapon, c: count, x, z: aim point, by: code, n: nick, t: launch (ms), d: transit (s)}
##   result  {id, h: reached the city, k: shot down}

const ServerDef = preload("res://scripts/core/server_def.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

## Strikes, the cities' integrity or the outcome changed (the HUD strip, the attack screen).
signal changed

## Income is paid in parts this often, seconds.
const PAY_EVERY := 10.0
## A strike that is over stays on the attack screen this long.
const KEEP_DONE := 25.0
## A raid still unresolved this long after it arrived is closed as it stands.
const FIGHT_LIMIT := 240.0

var game
var def := {}
var side := 0
## The other city is played by the machine (a draft's test, nothing goes over the network).
var bot := false
## Integrity of both cities, percent; our own follows GS.city.
var hp := [100.0, 100.0]
## Our side's strikes: id -> strike + {st: "fly" | "fight" | "done", h, k, done_t}.
var outgoing := {}
## Strikes at our city: id -> strike + {st: "fly" | "fight", left, h, k, at}.
var incoming := {}
## "" while the match runs, then "won" or "lost".
var over := ""
## This player's own score of the match.
var stats := {"strikes": 0, "units": 0, "hits": 0, "spent": 0, "bonus": 0}
var machine: Bot

var _clock := 0.0
var _pay_t := 0.0
var _seq := 0
var _closed := {}
var _rng := RandomNumberGenerator.new()
## A server: the first news from the database has been read (the city's state is taken over once).
var _synced := false


func _ready() -> void:
	_rng.randomize()
	def = GS.pvp.get("def", {})
	side = int(GS.pvp.get("side", 0))
	bot = bool(GS.pvp.get("bot", false))
	if bot:
		machine = Bot.new()
		machine.pvp = self
		machine.setup()
	else:
		Net.srv_changed.connect(_on_cross)
		_on_cross.call_deferred() # what arrived while the position was being picked


func rules() -> Dictionary:
	return def.get("rules", {})


func my_name() -> String:
	return ServerDef.city_name(def, side)


func enemy_name() -> String:
	return ServerDef.city_name(def, 1 - side)


## This machine flies the raid on our city.
func authority() -> bool:
	return bot or Net.role != "guest"


## The clock strikes are timed by, ms: the database's on a server (the same for both sides).
func now_ms() -> int:
	return int(_clock * 1000.0) if bot else Net.server_now()


## Seconds until a strike reaches the target city's radars (negative once it has).
func eta(s: Dictionary) -> float:
	return (float(s.t) + float(s.d) * 1000.0 - float(now_ms())) / 1000.0


func transit(weapon: String) -> float:
	return ServerDef.transit(weapon, float(rules().get("dist", 300)))


func allowed(weapon: String) -> bool:
	return (rules().get("arsenal", []) as Array).has(weapon)


## Why a strike cannot be launched now ("" when it can).
func blocker(weapon: String, count: int) -> String:
	if over != "":
		return GS.t("Матч окончен")
	if not allowed(weapon):
		return GS.t("Запрещено правилами сервера")
	if not bot and Net.srv_enemy_count() == 0:
		return GS.t("В городе противника нет защитников — по пустому городу не бьют")
	if GS.money < ServerDef.price(weapon) * count:
		return GS.t("Не хватает денег")
	return ""


## Buys `count` of a weapon and sends them at a point of the other city.
func launch_strike(weapon: String, count: int, target: Vector2) -> bool:
	count = clampi(count, 1, ServerDef.salvo_max(weapon))
	if blocker(weapon, count) != "":
		return false
	var cost := ServerDef.price(weapon) * count
	if not GS.spend(cost):
		return false
	_seq += 1
	var s := {"id": "%s_%d_%d" % [Net.code(), int(Time.get_unix_time_from_system()) % 100000, _seq], "w": weapon, "c": count,
		"x": snappedf(target.x, 1.0), "z": snappedf(target.y, 1.0), "by": Net.code(), "n": Net.nick(), "t": now_ms(), "d": snappedf(transit(weapon), 0.1)}
	stats.strikes = int(stats.strikes) + 1
	stats.units = int(stats.units) + count
	stats.spent = int(stats.spent) + cost
	_note_outgoing(s)
	if bot:
		machine.receive(s)
	else:
		Net.srv_send_strike(1 - side, s)
	SFX.play("launch", -6.0)
	game.hud.log_event(GS.t("Пуск по городу %s: %s ×%d — подлёт через %s") % [enemy_name(), GS.t(String(GS.ENEMIES[weapon].name)), count, fmt_time(float(s.d))], UiKit.CYAN)
	return true


## A strike of our side (ours or a team-mate's) is on its way.
func _note_outgoing(s: Dictionary) -> void:
	var id := String(s.id)
	if outgoing.has(id) or _closed.has(id):
		return
	var o := s.duplicate()
	o["st"] = "fly"
	o["h"] = 0
	o["k"] = 0
	outgoing[id] = o
	changed.emit()


## A team-mate's strike seen in the database (a server): listed with ours.
func note_team_strike(s: Dictionary) -> void:
	if _valid(s):
		_note_outgoing(s)


static func _valid(s) -> bool:
	return s is Dictionary and s.get("id") is String and s.get("w") is String and GS.ENEMIES.has(String(s.w)) \
		and ServerDef.price(String(s.w)) > 0 and (s.get("c") is float or s.get("c") is int) and (s.get("t") is float or s.get("t") is int)


## A strike aimed at our city, from the machine or from the other side's players.
func receive(s) -> void:
	if not _valid(s) or over != "":
		return
	var id := String(s.id)
	if incoming.has(id) or _closed.has(id):
		return
	var w := String(s.w)
	if not allowed(w):
		return
	var half := float(def.cities[side].size)
	var i := {"id": id, "w": w, "c": clampi(int(s.c), 1, ServerDef.salvo_max(w)), "x": clampf(float(s.get("x", 0.0)), -half, half),
		"z": clampf(float(s.get("z", 0.0)), -half, half), "by": String(s.get("by", "")), "n": String(s.get("n", "")).substr(0, 16),
		"t": float(s.t), "d": clampf(float(s.get("d", 30.0)), ServerDef.TRANSIT_MIN, ServerDef.TRANSIT_MAX), "st": "fly", "h": 0, "k": 0, "at": 0.0}
	i["left"] = int(i.c)
	if eta(i) < -60.0:
		# launched long before we were here (the city stood empty): it is not flown now
		_closed[id] = true
		return
	incoming[id] = i
	var label: String = GS.t(String(GS.ENEMIES[w].plural))
	if int(i.c) > 1:
		label += " ×%d" % int(i.c)
	var left := maxf(eta(i), 0.0)
	game.hud.alert(GS.t("⚠ %s ЗАПУСТИЛ %s — подлёт через %s") % [enemy_name().to_upper(), label, fmt_time(left)], Color(1.0, 0.6, 0.25))
	game.hud.log_event(GS.t("Разведка: пуск из города %s — %s, подлёт через %s") % [enemy_name(), label, fmt_time(left)], Color(1.0, 0.7, 0.4))
	SFX.play("alert", -8.0)
	changed.emit()


## The strike has crossed the distance: its weapons come in over our city.
func _arrive(i: Dictionary) -> void:
	i.st = "fight"
	i.at = _clock
	if authority():
		game.launch_at(String(i.w), int(i.c), Vector3(float(i.x), 0.0, float(i.z)), ServerDef.bearing_from_enemy(side), String(i.id))
	changed.emit()


## Authority: one weapon of a strike is down or has come in (`hit`: it took something off the city).
func unit_done(e, hit: bool, killed: bool) -> void:
	var i = incoming.get(String(e.strike_id))
	if i == null or not authority():
		return
	i.left = int(i.left) - 1
	if hit:
		i.h = int(i.h) + 1
	elif killed:
		i.k = int(i.k) + 1
	if int(i.left) <= 0:
		_close_incoming(i)


func _close_incoming(i: Dictionary) -> void:
	incoming.erase(String(i.id))
	_closed[String(i.id)] = true
	if authority() and not bot:
		Net.srv_send_result(side, {"id": String(i.id), "h": int(i.h), "k": int(i.k)})
	changed.emit()


## The outcome of a strike of our side.
func result(r) -> void:
	if not (r is Dictionary) or not outgoing.has(String(r.get("id", ""))):
		return
	var o: Dictionary = outgoing[String(r.id)]
	if String(o.st) == "done":
		return
	o.st = "done"
	o.h = clampi(int(r.get("h", 0)), 0, int(o.c))
	o.k = clampi(int(r.get("k", 0)), 0, int(o.c) - int(o.h))
	o["done_t"] = _clock
	if String(o.by) == Net.code():
		var bonus := int(ServerDef.price(String(o.w)) * ServerDef.HIT_BONUS) * int(o.h)
		stats.hits = int(stats.hits) + int(o.h)
		stats.bonus = int(stats.bonus) + bonus
		if bonus > 0:
			GS.add_money(bonus)
		var wname: String = GS.t(String(GS.ENEMIES[String(o.w)].name))
		if int(o.h) > 0:
			game.hud.alert(GS.t("УДАР ПО ГОРОДУ %s: %d из %d в цель  +%s") % [enemy_name().to_upper(), int(o.h), int(o.c), GS.fmt_money(bonus)], Color(0.5, 1.0, 0.6))
			SFX.play("cash", -6.0)
		game.hud.log_event(GS.t("Итог удара (%s ×%d): в цель %d, сбито %d") % [wname, int(o.c), int(o.h), int(o.k)], Color(0.5, 1.0, 0.6) if int(o.h) > 0 else Color(1.0, 0.6, 0.35))
	changed.emit()


## A server: the strikes, outcomes and the other city's state as the database has them now.
## Everything here may be read again and again: a strike or an outcome is taken only once.
func _on_cross() -> void:
	if bot or over != "":
		return
	var x: Dictionary = Net.srv_x()
	var at_us = x.get("in%d" % side)
	if at_us is Dictionary:
		for id in at_us:
			receive(at_us[id])
	var from_us = x.get("in%d" % (1 - side))
	if from_us is Dictionary:
		for id in from_us:
			note_team_strike(from_us[id])
	var res = x.get("res")
	if res is Dictionary:
		for id in res:
			if res[id] is Dictionary and outgoing.has(String(id)):
				var r: Dictionary = (res[id] as Dictionary).duplicate()
				r["id"] = String(id)
				result(r)
	var hps = x.get("hp")
	if hps is Dictionary:
		var mine = (hps as Dictionary).get("s%d" % side)
		if not _synced and authority() and Net.players.size() <= 1 and mine is Dictionary and float(mine.get("v", 0.0)) > 0.0:
			# the city stood empty for a while: it is as its last defenders left it
			GS.city = clampf(float(mine.v), 1.0, 100.0)
			GS.state_changed.emit()
		var theirs = (hps as Dictionary).get("s%d" % (1 - side))
		if theirs is Dictionary:
			set_enemy_hp(float(theirs.get("v", 100.0)))
	if Net.srv_synced():
		_synced = true
	changed.emit()


## We are the captain now (the one before us left): the raids that were over the city when the
## snapshots stopped are flown again from the edge of the map.
func take_over() -> void:
	for id in incoming:
		var i: Dictionary = incoming[id]
		if String(i.st) == "fight":
			i.left = int(i.c)
			i.h = 0
			i.k = 0
			_arrive(i)


## The other city's integrity as its own side reports it.
func set_enemy_hp(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
	if absf(v - float(hp[1 - side])) > 0.01:
		hp[1 - side] = v
		changed.emit()
	if v <= 0.0:
		finish("won")


## The match is over for this player: the window with the outcome.
func finish(how: String) -> void:
	if over != "":
		return
	over = how
	game.game_over = true
	SFX.stop_siren()
	if game.view != "top" and game.rl == null:
		game.set_view("top")
	changed.emit()
	game.hud.show_pvp_end(how == "won")
	if not bot:
		# the session is left at once: whoever joins next starts a new match
		if how == "lost" and authority():
			Net.srv_send_end(side)
		Net.close()


func _process(delta: float) -> void:
	_clock += delta
	if over != "":
		return
	hp[side] = GS.city
	_pay_t += delta
	if _pay_t >= PAY_EVERY:
		_pay_t -= PAY_EVERY
		var part := int(float(rules().get("income", 0)) * PAY_EVERY / 60.0)
		if part > 0:
			GS.add_money(part)
	for id in incoming.keys():
		var i: Dictionary = incoming[id]
		if String(i.st) == "fly":
			if eta(i) <= 0.0:
				_arrive(i)
		elif _clock - float(i.at) > FIGHT_LIMIT:
			_close_incoming(i)
	for id in outgoing.keys():
		var o: Dictionary = outgoing[id]
		match String(o.st):
			"fly":
				if eta(o) <= 0.0:
					o.st = "fight"
					o["at"] = _clock
					changed.emit()
			"fight":
				if _clock - float(o.get("at", _clock)) > FIGHT_LIMIT + 30.0:
					outgoing.erase(id) # its outcome never came (the other side's captain left)
					_closed[id] = true
					changed.emit()
			"done":
				if _clock - float(o.get("done_t", _clock)) > KEEP_DONE:
					outgoing.erase(id)
					_closed[id] = true
					changed.emit()
	if machine != null:
		machine.tick(delta)
	if GS.city <= 0.0:
		finish("lost")


## Strikes still on their way to us and the seconds until the first of them.
func inbound() -> Array:
	var n := 0
	var first := INF
	for id in incoming:
		if String(incoming[id].st) == "fly":
			n += 1
			first = minf(first, eta(incoming[id]))
	return [n, maxf(first, 0.0) if n > 0 else 0.0]


static func fmt_time(sec: float) -> String:
	var s := int(ceil(maxf(sec, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


## The other city in a draft's test: it earns what a player earns, spends it on strikes at our
## city and on its own air defence, and takes our strikes as dice rolls — every weapon that
## arrives is met by a ready interceptor (they run out under a big salvo: decoys work) or passes.
class Bot:
	const Def = preload("res://scripts/core/server_def.gd")
	## Chance of an interception by the kind of the weapon: [at level 0, per level, the most].
	const PK := {"shahed": [0.45, 0.08, 0.85], "cruise": [0.25, 0.1, 0.75], "ballistic": [0.05, 0.11, 0.6]}
	const LEVEL_MAX := 5
	const LEVEL_PRICE := 15000
	## Seconds a weapon needs over the city after the transit, by kind.
	const FINAL_LEG := {"shahed": 45.0, "cruise": 30.0, "ballistic": 35.0}

	var pvp
	var money := 0.0
	var level := 0
	var hp := 100.0
	## Interceptors ready to fire and the most there can be.
	var ready := 4.0
	var _think := 25.0
	var _pending: Array = []
	var _rng := RandomNumberGenerator.new()

	func setup() -> void:
		_rng.randomize()
		money = float(pvp.rules().get("money", 60000)) * 0.6 # the rest went into its first battery

	func cap() -> float:
		return 4.0 + 2.0 * level

	## A strike of the players' side: it will be met when it arrives.
	func receive(s: Dictionary) -> void:
		var kind := GS.kind_of(String(s.w))
		_pending.append({"s": s, "at": pvp._clock + float(s.d) + float(FINAL_LEG.get(kind, 40.0))})

	func tick(delta: float) -> void:
		money += float(pvp.rules().get("income", 0)) * delta / 60.0
		ready = minf(cap(), ready + delta / 4.0)
		for p in _pending.duplicate():
			if pvp._clock >= float(p.at):
				_pending.erase(p)
				_meet(p.s)
		_think -= delta
		if _think <= 0.0:
			_think = _rng.randf_range(14.0, 26.0)
			_act()

	func _meet(s: Dictionary) -> void:
		var w := String(s.w)
		var wd: Dictionary = GS.ENEMIES[w]
		var kind := GS.kind_of(w)
		var pk: Array = PK.get(kind, PK.shahed)
		var p := minf(float(pk[0]) + float(pk[1]) * level, float(pk[2]))
		# what no gun and few missiles reach in the game is hard for the machine too
		var em: Dictionary = wd.get("eff_mult", {})
		if em.has("*"):
			p *= clampf(float(em["*"]) + 0.5, 0.3, 1.0)
		var h := 0
		var k := 0
		for i in int(s.c):
			if ready >= 1.0:
				ready -= 1.0
				if _rng.randf() < p:
					k += 1
					continue
			if wd.get("decoy", false):
				continue
			h += 1
			hp = maxf(0.0, hp - float(wd.hit_damage) / maxf(float(pvp.rules().get("armor", 1.0)), 0.01))
		pvp.result({"id": String(s.id), "h": h, "k": k})
		pvp.set_enemy_hp(hp)

	## Spends on a strike, or now and then on a level of its own defence.
	func _act() -> void:
		if level < LEVEL_MAX and money >= LEVEL_PRICE * (level + 1) and _rng.randf() < 0.3:
			money -= LEVEL_PRICE * (level + 1)
			level += 1
			return
		var opts := []
		for a in Def.ARSENAL:
			if pvp.allowed(String(a[0])) and money >= float(a[1]):
				opts.append(a)
		if opts.is_empty():
			return
		var a: Array = opts[_rng.randi() % opts.size()]
		var most := mini(int(a[2]), int(money / float(a[1])))
		var count := _rng.randi_range(maxi(1, most / 2), most)
		money -= float(a[1]) * count
		var targets: Array = pvp.game.map.targets
		var aim := Vector2.ZERO
		if not targets.is_empty():
			var t: Dictionary = targets[_rng.randi() % targets.size()]
			aim = Vector2(t.pos.x, t.pos.z) + Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-120, 120))
		pvp._seq += 1
		pvp.receive({"id": "BOT_%d" % pvp._seq, "w": String(a[0]), "c": count, "x": aim.x, "z": aim.y, "by": "", "n": pvp.enemy_name(),
			"t": pvp.now_ms(), "d": pvp.transit(String(a[0]))})
