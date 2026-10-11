extends Node
## The training range of the MaxRealism mode (GS.training): an unsaved position with a pickup,
## an Igla crew and an S-300, and an instructor who takes the player through every kind of seat —
## on foot with the compass, the gun sight, the infrared seeker, the surveillance scope of the
## command post, the operator's console and a ballistic target. The targets are drills: one that
## gets through does no harm and simply comes again.

const Enemy = preload("res://scripts/game/enemy.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

## What stands on the range.
const KIT := ["mg", "igla", "s300"]
const SAM := "s300"
## Seconds the drill warhead takes to come down (a real one gives a third of that).
const WARHEAD_FLIGHT := 34.0

var game
var rl
var step := 0
var finished := false
var _walked := 0.0
var _last := Vector3.INF
## The slow drone over the position (gun and Igla lessons) and the far one (radar lessons).
var _drone = null
var _far = null
var _warhead = null
var _orbits := {}
var _kills := 0
var _need := 0
var _pause := 0.0
## The drill warhead is in the air (a freed node cannot say whether it was ever launched).
var _warhead_out := false


func total() -> int:
	return 10


func _ready() -> void:
	rl.radio(GS.t("Инструктор на связи. Начинаем с простого."))


# --- The lessons ------------------------------------------------------------------------------
## Bearing and distance from where the player stands, as the radio would give them.
func _to(p: Vector3) -> String:
	var me: Vector3 = game.walker.pos
	var rel := Vector2(p.x - me.x, p.z - me.z)
	return GS.t("азимут %03d°, %d м") % [int(rad_to_deg(rl.az_of(rel))) % 360, int(rel.length())]


func _unit_pos(id: String) -> Vector3:
	var w = game.weapons.get(id)
	return w.global_position if w != null else GS.base_pos


## Where a target is as seen from the position: bearing, distance, altitude.
func _where(e) -> String:
	if e == null or not is_instance_valid(e):
		return ""
	var rel := Vector2(e.position.x - GS.base_pos.x, e.position.z - GS.base_pos.z)
	if rel.length() > 3000.0:
		return GS.t("азимут %03d°, удаление %d км, высота %d м") % [int(rad_to_deg(rl.az_of(rel))) % 360, int(rel.length() * 0.001), int(e.position.y / 50.0) * 50]
	return GS.t("азимут %03d°, удаление %d м, высота %d м") % [int(rad_to_deg(rl.az_of(rel))) % 360, int(rel.length() / 50.0) * 50, int(e.position.y / 10.0) * 10]


## The instructor's card: the headline and what is behind it.
func card() -> PackedStringArray:
	var use := GS.key_label("use")
	var seated: bool = game.view == "base"
	var at: String = String(game.selected_weapon) if seated else ""
	if rl.touch:
		var tc := _card_touch(at)
		if not tc.is_empty():
			return tc
	match step:
		0:
			return [GS.t("Осмотритесь мышью и пройдитесь: W A S D, бегом — Shift."),
				GS.t("Здесь нет карты сверху и нет кнопок систем: всё делается ногами и руками. Сверху компас — по радио цели называют азимутом, это градусы от севера по часовой стрелке.")]
		1:
			return [GS.t("Подойдите вплотную к пикапу с пулемётом: %s.") % _to(_unit_pos("mg")),
				GS.t("Повернитесь так, чтобы на компасе был этот азимут, и идите прямо.")]
		2:
			return [GS.t("Нажмите %s — встаньте за пулемёт.") % use,
				GS.t("Той же клавишей с любого места встают.")]
		3:
			return [GS.t("Сбейте учебный дрон: %s.") % _where(_drone),
				GS.t("Меток на целях нет — ищите глазами и по звуку мотора. Стреляйте с упреждением: целиться надо впереди дрона, по его курсу. ЛКМ — огонь, ПКМ или колесо — кратность прицела, %s — ночной прицел.") % GS.key_label("night")]
		4:
			if at == "igla":
				return [GS.t("«Игла»: держите дрон в кольце прицела и ждите тон: %s.") % _where(_drone),
					GS.t("Редкий тон — головка ищет тепло, частый высокий — захват. Тогда ЛКМ — пуск. Ракета может промахнуться: посмотрите, попала ли, и пускайте вторую.")]
			return [GS.t("Встаньте (%s) и идите к расчёту ПЗРК «Игла»: %s. Там снова %s.") % [use, _to(_unit_pos("igla")), use],
				GS.t("«Игла» наводится на тепло двигателя: у неё нет радара, цель нужно видеть самому.")]
		5:
			return [GS.t("Теперь к командному пункту: зелёная кабина у мачты с красным огнём, %s. У экрана — %s.") % [_to(rl.post_pos()), use],
				GS.t("Командный пункт — это обзорный радар, состояние города и снабжение.")]
		6:
			return [GS.t("На экране отметка — учебная цель. Наведите на неё строб и нажмите ПКМ."),
				GS.t("Мышь влево-вправо — азимут, вверх-вниз — дальность, колесо — шкала. Радар не знает, что летит: об этом говорят высота и скорость. До 200 км/ч — «Шахед», 700–900 — крылатая ракета, тысячи км/ч и пикирует — баллистика.")]
		7:
			return [GS.t("Встаньте (%s) и идите к пусковой С-300: %s. Займите место оператора — %s.") % [use, _to(_unit_pos(SAM)), use],
				GS.t("С командного пункта не стреляют: к каждой машине нужно подойти. Отсюда же: %s — снабжение (покупка систем и ракет), %s — приказ расчётам стволов.") % [GS.key_label("shop"), GS.key_label("auto")]]
		8:
			return [GS.t("Сбейте цель с пульта: строб на отметку, ПКМ — захват, ЛКМ — пуск."),
				GS.t("Пускать можно, когда горит «В ЗОНЕ». Одна ракета может пройти мимо — в жизни по цели пускают две. Сейчас цель: %s.") % _where(_far)]
		9:
			if not _warhead_out or not is_instance_valid(_warhead):
				return [GS.t("Приготовьтесь: по радио объявят пуск баллистической ракеты."),
					GS.t("Останьтесь за пультом С-300. Шкалу лучше поставить на 50 км.")]
			return [GS.t("Баллистика! Отметка идёт быстро: захват и сразу две-три ракеты."),
				GS.t("Цель: %s. У настоящей ракеты на всё уходит секунд пятнадцать — к ней надо уже сидеть за пультом.") % _where(_warhead)]
	return PackedStringArray()


## The lessons that name keys and the mouse, told for a touch screen (the rest are the same).
func _card_touch(at: String) -> PackedStringArray:
	match step:
		0:
			return [GS.t("Осмотритесь и пройдитесь: левая половина экрана — идти, правая — смотреть."),
				GS.t("Здесь нет карты сверху и нет кнопок систем: к каждой машине нужно подойти. Сверху компас — по радио цели называют азимутом, это градусы от севера по часовой стрелке. Палец до края круга — бегом.")]
		2:
			return [GS.t("Нажмите «МЕСТО» — встаньте за пулемёт."),
				GS.t("С любого места встают кнопкой «ВСТАТЬ».")]
		3:
			return [GS.t("Сбейте учебный дрон: %s.") % _where(_drone),
				GS.t("Меток на целях нет — ищите глазами и по звуку мотора. Ведите прицел пальцем и держите «ОГОНЬ»: целиться надо впереди дрона, по его курсу. «+» и «−» — кратность прицела, «НОЧЬ» — ночной прицел.")]
		4:
			if at == "igla":
				return [GS.t("«Игла»: держите дрон в кольце прицела и ждите тон: %s.") % _where(_drone),
					GS.t("Редкий тон — головка ищет тепло, частый высокий — захват. Тогда «ПУСК». Ракета может промахнуться: посмотрите, попала ли, и пускайте вторую.")]
			return [GS.t("Нажмите «ВСТАТЬ» и идите к расчёту ПЗРК «Игла»: %s. Там снова «МЕСТО».") % _to(_unit_pos("igla")),
				GS.t("«Игла» наводится на тепло двигателя: у неё нет радара, цель нужно видеть самому.")]
		5:
			return [GS.t("Теперь к командному пункту: зелёная кабина у мачты с красным огнём, %s. У экрана — «МЕСТО».") % _to(rl.post_pos()),
				GS.t("Командный пункт — это обзорный радар, состояние города и снабжение.")]
		6:
			return [GS.t("На экране отметка — учебная цель. Наведите на неё строб и нажмите «ЗАХВАТ»."),
				GS.t("Ведите пальцем по экрану: влево-вправо — азимут, вверх-вниз — дальность; «+» и «−» — шкала. Радар не знает, что летит: об этом говорят высота и скорость. До 200 км/ч — «Шахед», 700–900 — крылатая ракета, тысячи км/ч и пикирует — баллистика.")]
		7:
			return [GS.t("Нажмите «ВСТАТЬ» и идите к пусковой С-300: %s. Займите место оператора — «МЕСТО».") % _to(_unit_pos(SAM)),
				GS.t("С командного пункта не стреляют: к каждой машине нужно подойти. Здесь же кнопки «СНАБЖЕНИЕ» (покупка систем и ракет) и «РАСЧЁТЫ» (приказ расчётам стволов).")]
		8:
			return [GS.t("Сбейте цель с пульта: строб на отметку, «ЗАХВАТ», затем «ПУСК»."),
				GS.t("Пускать можно, когда горит «В ЗОНЕ». Одна ракета может пройти мимо — в жизни по цели пускают две. Сейчас цель: %s.") % _where(_far)]
	return PackedStringArray()


func _next() -> void:
	step += 1
	_pause = 0.0
	_need = _kills
	SFX.play("cash", -10.0)
	match step:
		3:
			rl.radio(GS.t("Инструктор: учебный дрон над позицией. Огонь по готовности."))
		4:
			rl.radio(GS.t("Инструктор: цель поражена. Второй дрон — для «Иглы»."))
		5:
			rl.radio(GS.t("Инструктор: хорошо. Теперь на командный пункт."))
		7:
			rl.radio(GS.t("Инструктор: цель на сопровождении. Её будем сбивать с С-300."))
		9:
			rl.radio(GS.t("Инструктор: цель поражена. Последнее упражнение — баллистика."))
			_pause = 7.0
		10:
			_finish()


func _process(delta: float) -> void:
	if finished or get_tree().paused:
		return
	_keep_orbit(_drone, 520.0, 240.0, 1.0)
	_keep_orbit(_far, 9000.0, 1500.0, 0.5)
	var seated: bool = game.view == "base"
	var at: String = String(game.selected_weapon) if seated else ""
	match step:
		0:
			var p: Vector3 = game.walker.pos
			if _last != Vector3.INF and game.view == "walk":
				_walked += Vector2(p.x - _last.x, p.z - _last.z).length()
			_last = p
			if _walked > 10.0:
				_next()
		1:
			if (not rl.near.is_empty() and String(rl.near.id) == "mg") or at == "mg":
				_next()
		2:
			if at == "mg":
				_next()
		3:
			if _need_target("_drone") and _kills > _need:
				_next()
		4:
			if _need_target("_drone") and _kills > _need:
				_next()
		5:
			if game.view == "post":
				_next()
		6:
			_need_target("_far")
			if game.view == "post" and rl.track != null:
				_next()
		7:
			_need_target("_far")
			if at == SAM:
				_next()
		8:
			if _need_target("_far") and _kills > _need:
				_next()
		9:
			_ballistic(delta)


## Keeps the drill target of a lesson in the air; false on the frame a new one was launched.
func _need_target(which: String) -> bool:
	var e = get(which)
	if e != null and is_instance_valid(e) and not e.dead:
		return true
	if _kills > _need:
		return true # brought down: the lesson is passed
	_need = _kills
	if which == "_drone":
		_drone = _spawn("molniya", 520.0, 240.0)
	else:
		_far = _spawn("shahed", 9000.0, 1500.0)
	return false


## A drill target circling the position at the given radius and altitude.
func _spawn(variant: String, radius: float, alt: float):
	var a := randf() * TAU
	var start := GS.base_pos + Vector3(cos(a) * radius, alt, sin(a) * radius)
	var e := Enemy.new()
	e.setup(game, variant, start, GS.base_pos + Vector3(cos(a + 0.6) * radius, alt, sin(a + 0.6) * radius), GS.t("Учебная цель"), alt)
	game.enemy_root.add_child(e)
	game.enemies.append(e)
	e.missed = false
	e.waypoints.clear()
	_orbits[e.get_instance_id()] = a
	_keep_orbit(e, radius, alt, 1.0 if radius < 2000.0 else 0.5)
	return e


## Feeds the target the next points of its circle so that it never reaches a last waypoint.
## `arc` is the step between two points, radians: wide enough that the target does not reach
## the next one the moment it gets it.
func _keep_orbit(e, radius: float, alt: float, arc: float) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	var id: int = e.get_instance_id()
	while e.waypoints.size() < 3:
		_orbits[id] = float(_orbits.get(id, 0.0)) + arc
		var a: float = _orbits[id]
		e.waypoints.append(GS.base_pos + Vector3(cos(a) * radius, alt, sin(a) * radius))


## The last lesson: one warhead after a radio warning; if it gets through, another one comes.
func _ballistic(delta: float) -> void:
	if _warhead_out and is_instance_valid(_warhead) and not _warhead.dead:
		return
	if _kills > _need:
		_next()
		return
	if _warhead_out:
		# it came down: again, after a breath
		_warhead_out = false
		_warhead = null
		_pause = 6.0
		rl.radio(GS.t("Инструктор: не успели — боевая часть упала. Повторяем."))
		return
	_pause -= delta
	if _pause > 0.0:
		return
	_need = _kills
	var a := randf() * TAU
	var dir := Vector3(cos(a), 0, sin(a))
	var tgt := GS.base_pos + Vector3(-dir.z, 0, dir.x) * 2500.0
	var start := tgt + dir * 38000.0 + Vector3(0, 17000.0, 0)
	var e := Enemy.new()
	e.setup(game, "s300", start, tgt, GS.t("Учебная цель"))
	game.enemy_root.add_child(e)
	game.enemies.append(e)
	# slower than the real thing: the first time there has to be room to find the handwheels
	e.missed = false
	e.target_pos = tgt
	e._p0 = start
	e._flight = WARHEAD_FLIGHT
	e._v0 = (tgt - start + Vector3(0, 0.5 * e.gravity * WARHEAD_FLIGHT * WARHEAD_FLIGHT, 0)) / WARHEAD_FLIGHT
	e.vel = e._v0
	_warhead = e
	_warhead_out = true
	rl.raid_call(e.def, 1, start, 0.0)


# --- What the game tells the range ---------------------------------------------------------------
func on_kill(e) -> void:
	if e == _drone or e == _far or e == _warhead:
		_kills += 1


## A drill target is never a strike: it is taken out of the sky where it would have come down.
func on_lost(_e) -> void:
	pass


func _finish() -> void:
	finished = true
	rl.radio(GS.t("Инструктор: обучение пройдено. Удачи на дежурстве."))
	get_tree().create_timer(2.5, false).timeout.connect(_show_done)


func _show_done() -> void:
	if not is_inside_tree():
		return
	var h = game.hud
	h._close_overlay()
	h._set_paused(true)
	var m := UiKit.modal(h.root, Vector2(600, 0))
	h._overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("ОБУЧЕНИЕ ПРОЙДЕНО"), 36, UiKit.NEON))
	var l := UiKit.label(GS.t("На дежурстве всё так же, только никто не подсказывает: о пусках сообщит радио — азимут, удаление, сколько целей. Расчёты стволов стреляют сами, пусковые ждут вас. Системы и ракеты заказывают с командного пункта. Ночью выручает ночной прицел."), 16, Color(0.8, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	v.add_child(l)
	v.add_child(UiKit.button(GS.t("Создать мир MaxRealism ▶"), func() -> void: game.main.show_create_world(true), 540))
	v.add_child(UiKit.button(GS.t("Главное меню"), func() -> void: game.main.show_menu(), 540))
