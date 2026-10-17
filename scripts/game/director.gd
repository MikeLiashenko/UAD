extends Node
## Day / night cycle and attack scheduling.
##  DAY   — recon drones search for the base; lighting fades to dusk at the end. Now and then
##          the enemy does not wait for the dark: one or two ballistic missiles or a few cruise
##          missiles in broad daylight, with no siren — that alarm is the player's to declare.
##  NIGHT — air-raid siren, Shahed swarms at different altitude layers, cruise and ballistic
##          missiles; a precise strike on the base if a scout found it during the day. Nothing
##          flies to a timetable: when the waves come, how they are split, how heavy the night
##          is and how long it lasts are rolled anew every night (start_night).
##          What exactly flies depends on the city (CityDef.raid): decoys and Kinzhals over Kyiv,
##          glide bombs and S-300s over Kharkiv, Kalibrs and Oniks from the sea over Odesa …
##  After the night is cleared the morning report + shop opens (handled by the HUD); the world
##  is autosaved at the start of every day.
## Our counter-strikes (scripts/game/strikes.gd) land at dusk: a damaged launch site sends half
## of its usual share, a destroyed one sends nothing until the enemy has rebuilt it.
##  A match on a server (GS.pvp): only the clock is left of all this — day and night follow each
##  other without a morning report, and what flies is what the other city's players launch.

const Strikes = preload("res://scripts/game/strikes.gd")
const Orders = preload("res://scripts/game/orders.gd")
const Achievements = preload("res://scripts/core/achievements.gd")

enum Phase { DAY, NIGHT, MORNING }

## How often a day brings a missile strike of its own (once the city's missiles are in service).
const DAY_STRIKE_CHANCE := 0.35

var game
var phase := Phase.DAY
var phase_time := 0.0
var phase_len := 50.0
var night_blend := 1.0
var schedule: Array = []
var night_start_stats := {}
var _rng := RandomNumberGenerator.new()
## Our strikes that landed since the last morning, [in the target, all] (the morning report).
var _landed := [0, 0]
## Multiplayer guest: the host runs the raid. The clock and the phases follow its snapshots
## (net_follow) and nothing is launched here; the morning report is still our own.
var follower := false
var _followed := false
## A match on a server: the raids are the other city's (scripts/game/pvp.gd).
var pvp := false
## Length of a day and of a night of a match, seconds.
const PVP_PHASE := 150.0


func _ready() -> void:
	_rng.randomize()
	Strikes.reset_hunts()
	follower = Net.role == "guest"
	pvp = not GS.pvp.is_empty()
	if follower:
		SFX.play_music("day")
		return
	if GS.training:
		# the training range: an endless day, the instructor launches the targets
		phase_len = 1.0e9
		SFX.play_music("day")
		return
	start_day()


func phase_name() -> String:
	match phase:
		Phase.DAY:
			return GS.t("ДЕНЬ")
		Phase.NIGHT:
			return GS.t("НОЧЬ")
	return GS.t("УТРО")


func is_night() -> bool:
	return phase == Phase.NIGHT


func time_left() -> float:
	return maxf(0.0, phase_len - phase_time)


func start_day() -> void:
	phase = Phase.DAY
	phase_time = 0.0
	phase_len = 55.0 if GS.day == 1 else _rng.randf_range(68.0, 86.0)
	SFX.play_music("day")
	schedule.clear()
	if pvp:
		phase_len = PVP_PHASE
		return
	# a destroyed recon post sends no scouts, a damaged one fewer; they come when they come, not
	# on the quarter of a minute
	var scouts := int(round((1 + GS.day / 3) * Strikes.output(game.map.city, "scout")))
	for i in scouts:
		schedule.append({"t": _rng.randf_range(3.0, phase_len - 24.0), "type": "scout", "count": 1})
	day_strike(GS.day)
	# the order of the command for this day (a world loaded mid-day keeps the one it had)
	var o := Orders.issue(game.map.city, _rng)
	if not o.is_empty():
		_say(GS.t("📋 Задание командования: %s") % Orders.text(o), Color(0.6, 0.9, 1.0))
	schedule.sort_custom(func(a, b) -> bool: return float(a.t) < float(b.t))
	_print_plan("day %d (%d s)" % [GS.day, int(phase_len)])
	game.hud.alert(GS.t("ДЕНЬ %d — разведка противника в воздухе") % GS.day, Color(0.5, 0.9, 1.0))
	game.hud.log_event(GS.t("Утро дня %d. Ищите и сбивайте разведчиков!") % GS.day, Color(0.5, 0.9, 1.0))


## A strike in the daytime: one or two ballistic missiles, or a salvo of two to four cruise
## missiles — only what the city is already hit with at night, and less of it when our strikes
## have thinned the launch sites. `force` ("ballistic" / "cruise") is the test hook: no dice.
func day_strike(d: int, force := "") -> void:
	var city = game.map.city
	var cruise_from := int(city.raid_start.get("cruise", 3))
	var ball_from := int(city.raid_start.get("ballistic", 5))
	if force == "":
		if d < mini(cruise_from, ball_from) or _rng.randf() >= DAY_STRIKE_CHANCE:
			return
		force = "ballistic" if d >= ball_from and (d < cruise_from or _rng.randf() < 0.4) else "cruise"
	# early enough to come down in daylight; MaxRealism needs the half minute of the early warning
	# before the launch, so there the day is that much longer (its clock is only at the command post)
	var at := _rng.randf_range(5.0, 16.0)
	if GS.realism:
		phase_len += 25.0
		at = _rng.randf_range(29.0, 34.0)
	if force == "ballistic":
		var n := 2 if d >= ball_from + 2 and _rng.randf() < 0.45 else 1
		var warned := not GS.realism
		for i in n:
			var bw := _weapon("ballistic", maxi(d, ball_from))
			if _left(bw, 1) > 0:
				schedule.append({"t": at + i * _rng.randf_range(4.0, 9.0), "type": bw, "count": 1})
				if not warned:
					# the same early warning as at night: the time to walk to a console
					warned = true
					schedule.append({"t": maxf(1.0, at - 28.0), "warn": true})
	else:
		var w := _weapon("cruise", maxi(d, cruise_from))
		if w != "":
			var glide: bool = GS.ENEMIES[w].get("glide", false)
			var cc := _left(w, clampi(int(round(_rng.randf_range(2.0, 4.0) * maxf(GS.enemy_mult(), 0.8))), 2, 4))
			if cc > 0:
				schedule.append({"t": at, "type": w, "count": cc, "alt": -1.0 if glide or GS.ENEMIES[w].alt_max < 100.0 else _layer("cruise")})
	schedule.sort_custom(func(a, b) -> bool: return float(a.t) < float(b.t))


## One weapon for a slot of the raid, by the city's weights, among those already in service.
func _weapon(slot: String, d: int) -> String:
	var fallback := {"drone": "shahed", "cruise": "cruise", "ballistic": "ballistic"}
	var opts: Array = game.map.city.raid.get(slot, [])
	var avail := []
	var total := 0.0
	for o in opts:
		if d >= int(o[2]):
			# what our strikes knocked out is rarer (half) or gone (silent sites)
			var wt := float(o[1]) * Strikes.output(game.map.city, String(o[0]))
			if wt > 0.0:
				avail.append([o[0], wt])
				total += wt
	if avail.is_empty():
		var fb := String(fallback.get(slot, slot))
		return fb if Strikes.output(game.map.city, fb) > 0.0 else ""
	var roll := _rng.randf() * total
	for o in avail:
		roll -= float(o[1])
		if roll <= 0.0:
			return String(o[0])
	return String(avail[avail.size() - 1][0])


## How many of `w` the enemy still manages tonight: `count` scaled by its launch sites.
func _left(w: String, count: int) -> int:
	if w == "":
		return 0
	var k := Strikes.output(game.map.city, w)
	# rounded by chance: on average exactly count × k, even for single launches
	return count if k >= 1.0 else int(floor(count * k + _rng.randf()))


## Dusk: our strikes land. Each result goes to the log, the big alert sums them up.
func _strike_results() -> void:
	var res := Strikes.resolve(game.map.city, _rng)
	if res.is_empty():
		return
	game.hud.show_bda(res)
	var hits := 0
	for r in res:
		Strikes.record(r)
		_landed = [int(_landed[0]) + (1 if bool(r.hit) else 0), int(_landed[1]) + 1]
		var wname := GS.t(String(Strikes.WEAPONS[r.w].short))
		if float(r.get("escort", 0.0)) > 0.0 and not bool(Strikes.WEAPONS[r.w].get("swarm", false)):
			wname += GS.t(" (под прикрытием дронов)")
		if bool(r.hit):
			hits += 1
			var what := GS.t("уничтожена, молчит %d ноч.") % int(r.n) if String(r.st) == "destroyed" else GS.t("повреждена, вполсилы %d ноч.") % int(r.n)
			game.hud.log_event(GS.t("Удар %s по цели «%s»: поражение — %s") % [wname, GS.t(String(r.name)), what], Color(0.5, 1.0, 0.6))
		else:
			game.hud.log_event(GS.t("Удар %s по цели «%s»: сбит ПВО противника") % [wname, GS.t(String(r.name))], Color(1.0, 0.6, 0.35))
	game.hud.alert(GS.t("УДАРЫ ПО ТОЧКАМ ПУСКА: %d из %d в цель") % [hits, res.size()], Color(0.5, 1.0, 0.6) if hits > 0 else Color(1.0, 0.6, 0.35))
	GS.state_changed.emit()


## Launchers in the open and the HIMARS / ATACMS sent at them (scripts/game/strikes.gd): a hit
## calls off what that site still had to launch tonight.
func _hunts(delta: float) -> void:
	var city = game.map.city
	var before := {}
	for e in schedule:
		if e.has("type"):
			before[String(e.type)] = Strikes.output(city, String(e.type))
	for r in Strikes.hunt_step(city, delta, _rng):
		if game.autotest:
			print("UAD HUNT %s at %s: %s" % [r.w, r.site, "HIT" if bool(r.hit) else "miss"])
		game.hud.show_bda([r])
		Strikes.record(r, true)
		_landed = [int(_landed[0]) + (1 if bool(r.hit) else 0), int(_landed[1]) + 1]
		var wname := GS.t(String(Strikes.WEAPONS[r.w].short))
		var sname := GS.t(String(Strikes.KINDS[r.site].short))
		if bool(r.hit):
			var gone := Strikes.thin(schedule, city, before, _rng)
			GS.stats["hunts"] = int(GS.stats.get("hunts", 0)) + 1
			var txt := GS.t("%s накрыл пусковую «%s»: оставшиеся пуски этой ночи сорваны (−%d)") % [wname, sname, gone] if gone > 0 else GS.t("%s накрыл пусковую «%s»") % [wname, sname]
			_say(txt, Color(0.5, 1.0, 0.6))
			if not GS.realism:
				game.hud.alert(GS.t("🎯 ПУСКОВАЯ ПОРАЖЕНА"), Color(0.5, 1.0, 0.6))
			SFX.play("cash", -6.0)
		else:
			_say(GS.t("%s по пусковой «%s»: промах — расчёт успел сменить позицию") % [wname, sname], Color(1.0, 0.6, 0.35))
		GS.state_changed.emit()


## A line for the log, or for the radio in MaxRealism (it has no log on screen).
func _say(text: String, col: Color) -> void:
	if game.rl != null:
		game.rl.radio(text, col)
	else:
		game.hud.log_event(text, col)


## Altitude layer for a wave, metres.
func _layer(type: String) -> float:
	var r := _rng.randf()
	if type == "shahed":
		if GS.day >= 4 and r < 0.16:
			return _rng.randf_range(2000.0, 3200.0) # high: out of reach of machine guns
		if r < 0.6:
			return _rng.randf_range(450.0, 1300.0)
		return _rng.randf_range(120.0, 320.0) # low: just over the tower blocks
	if type == "cruise":
		return _rng.randf_range(50.0, 120.0) if r < 0.6 else _rng.randf_range(150.0, 400.0)
	return -1.0


func start_night() -> void:
	phase = Phase.NIGHT
	phase_time = 0.0
	if pvp:
		phase_len = PVP_PHASE
		schedule.clear()
		SFX.play_music("night")
		return
	var d := GS.day
	var m := GS.enemy_mult()
	var final := d == GS.CAMPAIGN_NIGHTS and not GS.won
	# the waves follow each other closely: with the air picture running GS.TEMPO times faster than
	# life a Shahed is on its target within a minute of the radars picking it up
	phase_len = minf(95.0 + 11.0 * d, 210.0) * _rng.randf_range(0.9, 1.12) + (45.0 if final else 0.0)
	night_start_stats = GS.stats.duplicate()
	schedule.clear()
	_strike_results()
	var span := phase_len * 0.75
	# The raid grows slowly and then plateaus: past a point more targets than the player can
	# physically engage is not difficulty, it is a scripted loss. Shaheds come first, cruise
	# missiles once a second system is affordable, ballistics only when a Patriot is in reach.
	var boss := 1.3 if final else 1.0
	var city = game.map.city
	# No two nights alike. The same weight of raid comes early or late, as a few big waves or as
	# many small groups from several sides at once; some nights are quieter, some heavier, and a
	# lone drone may turn up at any hour. The first nights and the final one swing the least.
	var swing := 0.1 if d <= 2 or final else 0.25
	var heat := _rng.randf_range(1.0 - swing, 1.0 + swing)
	# above 1 the raid leans towards dusk, below 1 towards the morning
	var lean := _rng.randf_range(0.6, 1.7)
	var waves := clampi(2 + (d - 1) / 3 + (_rng.randi_range(-1, 1) if d > 2 else 0), 2, 6) + (1 if final else 0)
	for i in waves:
		var c := clampi(int(round(clampf(2.4 + d * 0.8, 3.0, 9.0) * m * boss * heat)) + _rng.randi_range(-1, 1), 2, 13)
		var w := _weapon("drone", d)
		if w == "":
			continue # every drone launch pad of the city is out
		# decoys and the little Molniyas come in swarms, the jet Gerans in pairs
		var wd: Dictionary = GS.ENEMIES[w]
		c = _left(w, maxi(2, int(c * float(wd.get("swarm", 1.0)))))
		if c <= 0:
			continue
		var at := 4.0 + span * pow(_rng.randf(), lean)
		# a wave may split in two: every launch picks its own side and its own altitude
		var parts := 2 if c >= 4 and _rng.randf() < 0.35 else 1
		for k in parts:
			var ck := c / parts + (c % parts if k == 0 else 0)
			schedule.append({"t": at + k * _rng.randf_range(5.0, 18.0), "type": w, "count": ck, "alt": -1.0 if wd.get("own_alt", false) else _layer("shahed")})
	if d >= 2:
		for i in _rng.randi_range(0, mini(1 + d / 4, 4)):
			var lw := _weapon("drone", d)
			var lc := _left(lw, _rng.randi_range(1, 2))
			if lc > 0:
				schedule.append({"t": phase_len * _rng.randf_range(0.08, 0.92), "type": lw, "count": lc, "alt": -1.0 if GS.ENEMIES[lw].get("own_alt", false) else _layer("shahed")})
	var cruise_from := int(city.raid_start.get("cruise", 3))
	var ball_from := int(city.raid_start.get("ballistic", 5))
	if d >= cruise_from:
		var total := clampi(int(round((d - cruise_from + 1) * 0.8 * m * boss * heat)), 1, 6)
		var salvos := 1 if total < 3 else _rng.randi_range(1, 3)
		for i in salvos:
			var w := _weapon("cruise", d)
			if w == "":
				continue
			var glide: bool = GS.ENEMIES[w].get("glide", false)
			var cc := _left(w, maxi(1, total / salvos) + (1 if glide else 0))
			if cc > 0:
				schedule.append({"t": span * _rng.randf_range(0.12, 0.9), "type": w, "count": cc, "alt": -1.0 if glide or GS.ENEMIES[w].alt_max < 100.0 else _layer("cruise")})
	if d >= ball_from or (d >= ball_from - 1 and GS.difficulty == 2):
		var n := clampi(int(round((d - ball_from + 1) * 0.7 * m * boss)), 1, 3)
		for i in n:
			var bw := _weapon("ballistic", d)
			if _left(bw, 1) > 0:
				schedule.append({"t": span * _rng.randf_range(0.15, 0.95), "type": bw, "count": 1})
	for x in city.raid_extra:
		if d >= int(x.get("from", 1)):
			var cr: Array = x.get("count", [1, 1])
			var xc := _left(String(x.weapon), _rng.randi_range(int(cr[0]), int(cr[1])))
			if xc > 0:
				schedule.append({"t": span * clampf(float(x.get("at", 0.5)) + _rng.randf_range(-0.15, 0.15), 0.05, 0.95), "type": String(x.weapon), "count": xc, "base": bool(x.get("base", false)), "keep": true})
	if city.raid_events.has(d):
		var ev: Dictionary = city.raid_events[d]
		var hour := _rng.randf_range(0.35, 0.7)
		schedule.append({"t": span * (hour - 0.08), "alert": String(ev.get("alert", ""))})
		schedule.append({"t": span * hour, "type": String(ev.weapon), "count": int(ev.get("count", 1)), "aim": String(ev.get("aim", ""))})
	if GS.base_found:
		var bw := _weapon("cruise", maxi(d, cruise_from)) if d >= cruise_from else "cruise"
		var bc := _left(bw, 1 if d < 4 else 2)
		if bc > 0:
			schedule.append({"t": span * _rng.randf_range(0.25, 0.75), "type": bw, "count": bc, "base": true, "alt": 80.0})
		if d >= 5:
			var bb := _weapon("ballistic", maxi(d, ball_from))
			if _left(bb, 1) > 0:
				schedule.append({"t": span * _rng.randf_range(0.3, 0.8), "type": bb, "count": 1, "base": true})
	# the enemy's answer to our strikes: a salvo of its own from what it has left (scripts/game/strikes.gd)
	var rc := Strikes.revenge_count(d)
	if rc > 0:
		var at := span * _rng.randf_range(0.35, 0.65)
		schedule.append({"t": at - span * 0.06, "alert": "⚠ ОТВЕТНЫЙ УДАР: ракетный залп по городу!"})
		for i in rc:
			var slot := "ballistic" if d >= ball_from and _rng.randf() < 0.35 else "cruise"
			var rw := _weapon(slot, maxi(d, cruise_from))
			if rw == "":
				rw = "cruise"
			var glide: bool = GS.ENEMIES[rw].get("glide", false)
			var e := {"t": at + i * _rng.randf_range(0.5, 2.5), "type": rw, "count": 1}
			if GS.kind_of(rw) != "ballistic":
				e["alt"] = -1.0 if glide or GS.ENEMIES[rw].alt_max < 100.0 else _layer("cruise")
			schedule.append(e)
		GS.anger = 0.0
		GS.revenge_night = d
		_say(GS.t("⚠ Разведка: противник готовит ответный удар за наши удары — этой ночью ~%d ракет по городу. Отразите его без прилётов — будет премия.") % rc, Color(1.0, 0.55, 0.3))
	if GS.realism:
		# a ballistic missile leaves seconds; the early warning gives the time to walk to a console
		for s in schedule.duplicate():
			if s.has("type") and GS.kind_of(String(s.type)) == "ballistic":
				schedule.append({"t": maxf(1.0, float(s.t) - 28.0), "warn": true})
	schedule.sort_custom(func(a, b) -> bool: return float(a.t) < float(b.t))
	_print_plan("night %d (%d s, heat %.2f, lean %.2f)" % [d, int(phase_len), heat, lean])
	SFX.play_music("night")
	SFX.play_siren() # howls at dusk even over a city already under an alarm declared in the day
	game.set_alarm(true, false)
	_briefing(d)
	if final:
		game.hud.alert(GS.ctext("raid") % d, Color(1.0, 0.2, 0.25))
		game.hud.log_event(GS.t("Это решающая ночь. Выстоять — значит победить."), Color(1.0, 0.5, 0.3))
	else:
		game.hud.alert(GS.t("НОЧЬ %d — ВОЗДУШНАЯ ТРЕВОГА!") % d, Color(1.0, 0.3, 0.3))
		game.hud.log_event(GS.t("Воздушная тревога. Ночь %d.") % d, Color(1.0, 0.3, 0.3))


## Test runs print what was rolled: second, weapon and count of every launch.
func _print_plan(title: String) -> void:
	if not game.autotest:
		return
	var parts := PackedStringArray()
	for s in schedule:
		if s.has("type"):
			parts.append("%d:%s×%d" % [int(s.t), String(s.type), int(s.count)])
	print("UAD PLAN %s: %s" % [title, " ".join(parts)])


## The intelligence summary at dusk: which weapons are expected tonight.
func _briefing(d: int) -> void:
	var seen := []
	for s in schedule:
		if s.has("type") and not seen.has(String(s.type)):
			seen.append(String(s.type))
	var names := []
	for w in seen:
		names.append(GS.t(String(GS.ENEMIES[w].plural)))
	if not names.is_empty():
		game.hud.log_event(GS.t("Разведка: этой ночью ожидаются %s") % ", ".join(names), Color(1.0, 0.75, 0.4))
	var rear := []
	for id in Strikes.KINDS:
		if Strikes.KINDS[id].has("supply") and String(Strikes.state(id).st) != "ok":
			rear.append(GS.t(String(Strikes.KINDS[id].short)))
	if not rear.is_empty():
		game.hud.log_event(GS.t("Тыл противника подорван (%s): налёт этой ночью слабее") % ", ".join(rear), Color(0.5, 1.0, 0.6))
	var strength := Strikes.raid_strength(game.map.city)
	if strength < 0.99:
		_say(GS.t("Наши удары: налёт этой ночью на %d%% слабее, чем мог бы быть") % int(round((1.0 - strength) * 100.0)), Color(0.5, 1.0, 0.6))
	var note: String = game.map.city.raid_note
	if d <= 2 and note != "":
		game.hud.log_event(GS.t(note), Color(1.0, 0.85, 0.55))


func _process(delta: float) -> void:
	phase_time += delta
	var want := 0.0
	match phase:
		Phase.DAY:
			want = clampf((phase_time - (phase_len - 14.0)) / 14.0, 0.0, 1.0)
		Phase.NIGHT:
			want = 1.0
		Phase.MORNING:
			want = 0.0
	night_blend = move_toward(night_blend, want, delta / 3.0) if phase != Phase.DAY else want
	if phase == Phase.DAY and GS.day > 1 and phase_time < 6.0:
		night_blend = 1.0 - phase_time / 6.0
	game.map.set_night(night_blend)
	if follower:
		return
	if not pvp and (not Strikes.hot.is_empty() or not Strikes.hunts.is_empty()):
		_hunts(delta)

	while not schedule.is_empty() and float(schedule[0].t) <= phase_time:
		var s: Dictionary = schedule.pop_front()
		if s.has("warn"):
			game.hud.alert(GS.t("Угроза баллистики! Займите место за пультом комплекса."), Color(1.0, 0.85, 0.3))
			SFX.play("alert", -4.0)
		elif s.has("alert"):
			game.hud.alert(GS.t(String(s.alert)), Color(1.0, 0.85, 0.3))
			game.hud.log_event(GS.t(String(s.alert)), Color(1.0, 0.85, 0.3))
			SFX.play("alert", 0.0)
		elif s.get("base", false):
			game.launch(String(s.type), int(s.count), true, float(s.get("alt", -1.0)))
			if not s.get("keep", false):
				GS.base_found = false
				GS.detection = 0.0
		else:
			game.launch(String(s.type), int(s.count), false, float(s.get("alt", -1.0)), String(s.get("aim", "")))

	match phase:
		Phase.DAY:
			if phase_time >= phase_len:
				start_night()
		Phase.NIGHT:
			if pvp:
				if phase_time >= phase_len:
					GS.day += 1
					GS.state_changed.emit()
					start_day()
			elif phase_time >= phase_len and schedule.is_empty() and game.enemies.is_empty():
				_morning()


func _morning() -> void:
	phase = Phase.MORNING
	var night_s := int(phase_time)
	phase_time = 0.0
	game.set_alarm(false, false)
	SFX.stop_siren()
	SFX.play_music("day")
	var s := GS.stats
	var ns := night_start_stats
	var report := {
		"day": GS.day,
		"night_s": night_s,
		"kills": int(s.kills) - int(ns.get("kills", 0)),
		"roofs": int(s.roofs) - int(ns.get("roofs", 0)),
		"impacts": int(s.impacts) - int(ns.get("impacts", 0)),
		"homes": int(s.get("homes", 0)) - int(ns.get("homes", 0)),
		"misses": int(s.get("misses", 0)) - int(ns.get("misses", 0)),
		"drones": int(s.get("drones", 0)) - int(ns.get("drones", 0)),
		"rams": int(s.get("rams", 0)) - int(ns.get("rams", 0)),
		"fires_out": int(s.get("fires_out", 0)) - int(ns.get("fires_out", 0)),
		"rebuilt": int(s.get("rebuilt", 0)) - int(ns.get("rebuilt", 0)),
		"earned": int(s.earned) - int(ns.get("earned", 0)),
		"penalties": int(s.penalties) - int(ns.get("penalties", 0)),
	}
	# the order of the command is checked before the enemy has mended anything overnight
	if not follower and not pvp:
		report["order"] = Orders.check(report)
		if GS.revenge_night == GS.day:
			# the enemy's answer flew tonight: held off without a hit on the city, it pays
			GS.revenge_night = 0
			var held := int(report.impacts) == 0 and int(report.homes) == 0
			var rb := int((8000 + 1000 * GS.day) * GS.income_mult()) if held else 0
			GS.add_money(rb)
			report["revenge"] = {"held": held, "bonus": rb}
		for id in Achievements.night_done(report):
			game.hud.on_achievement(id)
		report["aid"] = Strikes.aid(_rng)
		report["strikes"] = _landed
		_landed = [0, 0]
	for name in Strikes.night_passed(game.map.city):
		game.hud.log_event(GS.t("Противник восстановил: %s") % GS.t(String(name)), Color(1.0, 0.7, 0.4))
	if not follower and not pvp:
		for name in Strikes.relocate(game.map.city, _rng):
			game.hud.log_event(GS.t("Мобильная цель сменила позицию: %s — нужен новый снимок со спутника или новый пуск") % GS.t(String(name)), Color(1.0, 0.7, 0.4))
	# Repair crews work through the day: the city is worn down by a bad night, not by attrition.
	var repaired := minf(5.0, 100.0 - GS.city)
	GS.city += repaired
	report["repaired"] = int(round(repaired))
	var funding := int((9000 + 3500 * GS.day) * GS.income_mult())
	var bonus := int(6000 * GS.income_mult()) if report.impacts == 0 and report.homes == 0 else 0
	# Emergency aid: a single ruinous night must not make the run unwinnable.
	var relief := clampi(-(GS.money + funding + bonus), 0, GS.RELIEF_LIMIT)
	report["funding"] = funding
	report["bonus"] = bonus
	report["relief"] = relief
	# Holding the final night wins the campaign — with a reward that funds the endless defense.
	var victory := GS.day >= GS.CAMPAIGN_NIGHTS and not GS.won
	if victory:
		GS.won = true
		report["victory"] = true
		report["award"] = int(60000 * GS.income_mult())
		GS.add_money(int(report.award))
		game.save_progress()
	GS.add_money(funding + bonus + relief)
	game.on_morning(report)


## Multiplayer guest: the host's phase and clock from a raid snapshot. A change of phase plays
## here what it played there: the siren at dusk, our own report in the morning.
func net_follow(r: Dictionary) -> void:
	var ph := int(r.get("ph", phase))
	var d := int(r.get("day", GS.day))
	if d != GS.day:
		GS.day = d
		GS.state_changed.emit()
	if pvp:
		# a match has no dusk siren and no morning report: only the light and the music change
		if ph != phase or not _followed:
			_followed = true
			phase = Phase.NIGHT if ph == Phase.NIGHT else Phase.DAY
			SFX.play_music("night" if phase == Phase.NIGHT else "day")
	elif ph != phase or not _followed:
		var was := phase
		_followed = true
		match ph:
			Phase.DAY:
				phase = Phase.DAY
				SFX.stop_siren()
				SFX.play_music("day")
				game.hud.alert(GS.t("ДЕНЬ %d — разведка противника в воздухе") % GS.day, Color(0.5, 0.9, 1.0))
			Phase.NIGHT:
				phase = Phase.NIGHT
				night_start_stats = GS.stats.duplicate()
				SFX.play_music("night")
				SFX.play_siren()
				game.set_alarm(true, false)
				game.hud.alert(GS.t("НОЧЬ %d — ВОЗДУШНАЯ ТРЕВОГА!") % GS.day, Color(1.0, 0.3, 0.3))
				game.hud.log_event(GS.t("Воздушная тревога. Ночь %d.") % GS.day, Color(1.0, 0.3, 0.3))
			Phase.MORNING:
				if was == Phase.NIGHT:
					_morning() # the report of a night we were there for
				else:
					phase = Phase.MORNING
	var age := clampf(float(Net.server_now() - int(float(r.get("t", 0)))) / 1000.0, 0.0, 3.0)
	phase_time = float(r.get("pt", phase_time)) + age
	phase_len = float(r.get("pl", phase_len))


## Called by the HUD when the player closes the morning report. Autosaves the world.
func next_day() -> void:
	if follower:
		return # the host starts the next day for everybody
	GS.day += 1
	game.save_progress()
	start_day()
	game.hud.log_event(GS.t("Мир «%s» сохранён") % GS.world_name, Color(0.5, 0.8, 0.7))
