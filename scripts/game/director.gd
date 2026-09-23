extends Node
## Day / night cycle and attack scheduling.
##  DAY   — recon drones search for the base; lighting fades to dusk at the end.
##  NIGHT — air-raid siren, Shahed swarms at different altitude layers, cruise and ballistic
##          missiles; a precise strike on the base if a scout found it during the day.
##          What exactly flies depends on the city (CityDef.raid): decoys and Kinzhals over Kyiv,
##          glide bombs and S-300s over Kharkiv, Kalibrs and Oniks from the sea over Odesa …
##  After the night is cleared the morning report + shop opens (handled by the HUD); the world
##  is autosaved at the start of every day.

enum Phase { DAY, NIGHT, MORNING }

var game
var phase := Phase.DAY
var phase_time := 0.0
var phase_len := 50.0
var night_blend := 1.0
var schedule: Array = []
var night_start_stats := {}
var _rng := RandomNumberGenerator.new()
## Multiplayer guest: the host runs the raid. The clock and the phases follow its snapshots
## (net_follow) and nothing is launched here; the morning report is still our own.
var follower := false
var _followed := false


func _ready() -> void:
	_rng.randomize()
	follower = Net.role == "guest"
	if follower:
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
	phase_len = 40.0 if GS.day == 1 else 55.0
	SFX.play_music("day")
	schedule.clear()
	var scouts := 1 + GS.day / 3
	for i in scouts:
		schedule.append({"t": 4.0 + i * 11.0, "type": "scout", "count": 1})
	game.hud.alert(GS.t("ДЕНЬ %d — разведка противника в воздухе") % GS.day, Color(0.5, 0.9, 1.0))
	game.hud.log_event(GS.t("Утро дня %d. Ищите и сбивайте разведчиков!") % GS.day, Color(0.5, 0.9, 1.0))


## One weapon for a slot of the raid, by the city's weights, among those already in service.
func _weapon(slot: String, d: int) -> String:
	var fallback := {"drone": "shahed", "cruise": "cruise", "ballistic": "ballistic"}
	var opts: Array = game.map.city.raid.get(slot, [])
	var avail := []
	var total := 0.0
	for o in opts:
		if d >= int(o[2]):
			avail.append(o)
			total += float(o[1])
	if avail.is_empty():
		return String(fallback.get(slot, slot))
	var roll := _rng.randf() * total
	for o in avail:
		roll -= float(o[1])
		if roll <= 0.0:
			return String(o[0])
	return String(avail[avail.size() - 1][0])


## Altitude layer for a wave (world units; ×5 = metres on the HUD).
func _layer(type: String) -> float:
	var r := _rng.randf()
	if type == "shahed":
		if GS.day >= 4 and r < 0.16:
			return _rng.randf_range(220.0, 320.0) # high: out of reach of machine guns
		if r < 0.6:
			return _rng.randf_range(90.0, 180.0)
		return _rng.randf_range(35.0, 70.0) # low: between the tower blocks
	if type == "cruise":
		return _rng.randf_range(22.0, 45.0) if r < 0.6 else _rng.randf_range(55.0, 110.0)
	return -1.0


func start_night() -> void:
	phase = Phase.NIGHT
	phase_time = 0.0
	var d := GS.day
	var m := GS.enemy_mult()
	var final := d == GS.CAMPAIGN_NIGHTS and not GS.won
	phase_len = minf(75.0 + 12.0 * d, 170.0) + (45.0 if final else 0.0)
	night_start_stats = GS.stats.duplicate()
	schedule.clear()
	var span := phase_len * 0.75
	# The raid grows slowly and then plateaus: past a point more targets than the player can
	# physically engage is not difficulty, it is a scripted loss. Shaheds come first, cruise
	# missiles once a second system is affordable, ballistics only when a Patriot is in reach.
	var boss := 1.3 if final else 1.0
	var city = game.map.city
	var waves := clampi(2 + (d - 1) / 3, 2, 5) + (1 if final else 0)
	for i in waves:
		var c := clampi(int(round(clampf(2.4 + d * 0.8, 3.0, 9.0) * m * boss)) + _rng.randi_range(-1, 1), 2, 13)
		var w := _weapon("drone", d)
		# decoys and the little Molniyas come in swarms, the jet Gerans in pairs
		if GS.ENEMIES[w].get("decoy", false) or w == "molniya":
			c = int(c * 1.5)
		elif w == "geran3":
			c = maxi(2, c / 2)
		schedule.append({"t": 5.0 + span * float(i) / waves + _rng.randf_range(0.0, 6.0), "type": w, "count": c, "alt": _layer("shahed") if GS.ENEMIES[w].alt_min < 100.0 and w != "molniya" else -1.0})
	var cruise_from := int(city.raid_start.get("cruise", 3))
	var ball_from := int(city.raid_start.get("ballistic", 5))
	if d >= cruise_from:
		var total := clampi(int(round((d - cruise_from + 1) * 0.8 * m * boss)), 1, 6)
		var salvos := 1 if total < 3 else 2
		for i in salvos:
			var w := _weapon("cruise", d)
			var glide: bool = GS.ENEMIES[w].get("glide", false)
			schedule.append({"t": span * (0.3 + 0.4 * i) + _rng.randf_range(0.0, 8.0), "type": w, "count": maxi(1, total / salvos) + (1 if glide else 0), "alt": -1.0 if glide or GS.ENEMIES[w].alt_max < 30.0 else _layer("cruise")})
	if d >= ball_from or (d >= ball_from - 1 and GS.difficulty == 2):
		var n := clampi(int(round((d - ball_from + 1) * 0.7 * m * boss)), 1, 3)
		for i in n:
			schedule.append({"t": span * _rng.randf_range(0.35, 0.95), "type": _weapon("ballistic", d), "count": 1})
	for x in city.raid_extra:
		if d >= int(x.get("from", 1)):
			var cr: Array = x.get("count", [1, 1])
			schedule.append({"t": span * float(x.get("at", 0.5)) + _rng.randf_range(0.0, 8.0), "type": String(x.weapon), "count": _rng.randi_range(int(cr[0]), int(cr[1])), "base": bool(x.get("base", false)), "keep": true})
	if city.raid_events.has(d):
		var ev: Dictionary = city.raid_events[d]
		schedule.append({"t": span * 0.42, "alert": String(ev.get("alert", ""))})
		schedule.append({"t": span * 0.5, "type": String(ev.weapon), "count": int(ev.get("count", 1)), "aim": String(ev.get("aim", ""))})
	if GS.base_found:
		schedule.append({"t": span * 0.45, "type": _weapon("cruise", maxi(d, cruise_from)) if d >= cruise_from else "cruise", "count": 1 if d < 4 else 2, "base": true, "alt": 30.0})
		if d >= 5:
			schedule.append({"t": span * 0.5, "type": _weapon("ballistic", maxi(d, ball_from)), "count": 1, "base": true})
	schedule.sort_custom(func(a, b) -> bool: return float(a.t) < float(b.t))
	SFX.play_music("night")
	SFX.play_siren()
	_briefing(d)
	if final:
		game.hud.alert(GS.ctext("raid") % d, Color(1.0, 0.2, 0.25))
		game.hud.log_event(GS.t("Это решающая ночь. Выстоять — значит победить."), Color(1.0, 0.5, 0.3))
	else:
		game.hud.alert(GS.t("НОЧЬ %d — ВОЗДУШНАЯ ТРЕВОГА!") % d, Color(1.0, 0.3, 0.3))
		game.hud.log_event(GS.t("Воздушная тревога. Ночь %d.") % d, Color(1.0, 0.3, 0.3))


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
	var note: String = game.map.city.raid_note
	if d <= 2 and note != "":
		game.hud.log_event(GS.t(note), Color(1.0, 0.85, 0.55))


func _process(delta: float) -> void:
	phase_time += delta
	var want := 0.0
	match phase:
		Phase.DAY:
			want = clampf((phase_time - (phase_len - 12.0)) / 12.0, 0.0, 1.0)
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

	while not schedule.is_empty() and float(schedule[0].t) <= phase_time:
		var s: Dictionary = schedule.pop_front()
		if s.has("alert"):
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
			if phase_time >= phase_len and schedule.is_empty() and game.enemies.is_empty():
				_morning()


func _morning() -> void:
	phase = Phase.MORNING
	phase_time = 0.0
	SFX.stop_siren()
	SFX.play_music("day")
	var s := GS.stats
	var ns := night_start_stats
	var report := {
		"day": GS.day,
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
	if ph != phase or not _followed:
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
