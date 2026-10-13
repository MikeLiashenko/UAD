extends Control
## The attack screen of a match on a server [K]: the plan of the other city, a point to aim at,
## the arsenal the server allows and the strikes already on their way (scripts/game/pvp.gd).
## A tap on the plan sets the aim point; a weapon, how many of it and "Launch" send the strike.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CityPlan = preload("res://scripts/ui/city_plan.gd")
const CustomCity = preload("res://scripts/world/custom_city.gd")
const ServerDef = preload("res://scripts/core/server_def.gd")

signal closed

## The last aim point, weapon and salvo, kept between openings of the screen (a match long).
static var last := {}

var game
var pvp
var _plan: CityPlan
var _side: VBoxContainer
var _money: Label
var _bars: Array = []
var _aim := Vector2.INF
var _weapon := ""
var _count := 1
var _aim_lbl: Label
var _count_lbl: Label
var _go: Button
var _why: Label
var _weapon_btns := {}
var _list: VBoxContainer
var _list_sig := ""
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pvp = game.pvp
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.full_rect(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.75)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(1180, 640))
	center.add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var top := UiKit.hbox()
	v.add_child(top)
	var title := UiKit.glow_label(GS.t("УДАР ПО ГОРОДУ %s") % pvp.enemy_name().to_upper(), 26, UiKit.RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = UiKit.label("", 24, UiKit.NEON)
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_money)
	top.add_child(UiKit.button(GS.t("Закрыть [%s]") % GS.key_label("strikes") if not GS.touch() else GS.t("✕ Закрыть"), close, 190, 17))
	var h := UiKit.hbox(12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_plan = CityPlan.new()
	_plan.custom_minimum_size = Vector2(700, 570)
	_plan.overlay = _draw_overlay
	_plan.tapped.connect(_on_tap)
	h.add_child(_plan)
	_plan.set_data(pvp.def.cities[1 - pvp.side])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 570)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_side = UiKit.vbox(6)
	_side.custom_minimum_size = Vector2(424, 0)
	scroll.add_child(_side)
	_build_side()
	if String(last.get("server", "")) == String(pvp.def.id) and int(last.get("side", -1)) == int(pvp.side):
		_aim = last.get("aim", Vector2.INF)
		_weapon = String(last.get("weapon", ""))
		_count = int(last.get("count", 1))
	if not pvp.allowed(_weapon):
		_weapon = "shahed" if pvp.allowed("shahed") else String((pvp.rules().get("arsenal", ["shahed"]) as Array)[0])
		_count = 1
	pvp.changed.connect(_refresh)
	GS.money_changed.connect(func(_v: int) -> void: _refresh())
	_refresh()


func _exit_tree() -> void:
	last = {"server": String(pvp.def.id), "side": int(pvp.side), "aim": _aim, "weapon": _weapon, "count": _count}


func _bar(title: String, col: Color) -> ProgressBar:
	var row := UiKit.hbox(8)
	_side.add_child(row)
	var l := UiKit.label(title, 14, col)
	l.custom_minimum_size = Vector2(170, 0)
	l.clip_text = true
	row.add_child(l)
	var b := ProgressBar.new()
	b.max_value = 100
	b.show_percentage = false
	b.custom_minimum_size = Vector2(190, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", UiKit.sbox(col, col, 0, 3, 0))
	row.add_child(b)
	var pc := UiKit.label("", 14, col, HORIZONTAL_ALIGNMENT_RIGHT)
	pc.custom_minimum_size = Vector2(46, 0)
	row.add_child(pc)
	b.set_meta("pc", pc)
	return b


func _note(text: String, col: Color, size := 13) -> Label:
	var l := UiKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	_side.add_child(l)
	return l


func _build_side() -> void:
	_bars = [_bar(GS.t("Наш город: %s") % pvp.my_name(), UiKit.NEON), _bar(GS.t("Противник: %s") % pvp.enemy_name(), UiKit.RED)]
	_side.add_child(HSeparator.new())
	_aim_lbl = _note("", UiKit.AMBER, 15)
	_note(GS.t("ЧЕМ БИТЬ"), UiKit.AMBER, 15)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_side.add_child(grid)
	for a in ServerDef.ARSENAL:
		var w := String(a[0])
		if not pvp.allowed(w):
			continue
		var wd: Dictionary = GS.ENEMIES[w]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(208, 52)
		b.add_theme_font_size_override("font_size", 13)
		var wname := GS.t(ServerDef.short_name(w)) + (GS.t(" · ложная цель") if wd.get("decoy", false) else "")
		b.text = "%s\n%s · %s" % [wname, GS.fmt_money(int(a[1])), GS.t("лететь %s") % pvp.fmt_time(pvp.transit(w))]
		b.tooltip_text = GS.t(String(wd.name))
		b.pressed.connect(_pick_weapon.bind(w))
		grid.add_child(b)
		_weapon_btns[w] = b
	var row := UiKit.hbox(8)
	_side.add_child(row)
	var cl := UiKit.label(GS.t("Сколько"), 15, Color(0.7, 1.0, 0.85))
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cl)
	row.add_child(UiKit.button("−", func() -> void: _set_count(_count - 1), 56, 22))
	_count_lbl = UiKit.label("1", 22, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	_count_lbl.custom_minimum_size = Vector2(200, 0)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_count_lbl)
	row.add_child(UiKit.button("+", func() -> void: _set_count(_count + 1), 56, 22))
	_go = UiKit.button(GS.t("ПУСК ▶"), _launch, 420, 24)
	_go.add_theme_color_override("font_color", Color(1.0, 0.85, 0.8))
	_side.add_child(_go)
	_why = _note("", UiKit.RED, 13)
	_side.add_child(HSeparator.new())
	_note(GS.t("НАШИ УДАРЫ"), UiKit.AMBER, 15)
	_list = UiKit.vbox(2)
	_side.add_child(_list)
	_side.add_child(HSeparator.new())
	_note(GS.t("Удар летит между городами (час полёта проходит за минуту), потом входит в небо противника — там его встречает ПВО. За каждое попадание возвращается половина цены. Сбитое над вашим городом оплачивается как обычно."), Color(0.55, 0.8, 0.7), 12)


func _pick_weapon(w: String) -> void:
	SFX.play("click", -8.0)
	_weapon = w
	_count = mini(_count, ServerDef.salvo_max(w))
	_refresh()


func _set_count(n: int) -> void:
	_count = clampi(n, 1, ServerDef.salvo_max(_weapon))
	_refresh()


func _on_tap(world: Vector2) -> void:
	var h: float = _plan.half()
	if absf(world.x) > h or absf(world.y) > h:
		return
	SFX.play("click", -8.0)
	_aim = world
	_refresh()


## What stands at a point of the other city: an object close by, else the district.
func place_name(p: Vector2) -> String:
	var city: Dictionary = _plan.data
	var best := 450.0
	var out := ""
	for o in city.get("objects", []):
		var d := Vector2(float(o.x), float(o.z)).distance_to(p)
		if d < best:
			best = d
			out = String(o.n) if String(o.n) != "" else GS.t(CustomCity.object_name(String(o.k)))
	if out != "":
		return out
	best = INF
	for d in city.get("districts", []):
		var dist := Vector2(float(d[1]), float(d[2])).distance_to(p)
		if dist < best and dist < float(d[5]) * 1.4:
			best = dist
			out = String(d[0])
	return out if out != "" else GS.t("окраина")


func _launch() -> void:
	if _aim == Vector2.INF:
		return
	if pvp.launch_strike(_weapon, _count, _aim):
		_refresh()


func _refresh() -> void:
	if not is_inside_tree() or _go == null:
		return
	_money.text = GS.fmt_money(GS.money)
	for i in 2:
		var s: int = pvp.side if i == 0 else 1 - pvp.side
		(_bars[i] as ProgressBar).value = float(pvp.hp[s])
		((_bars[i] as ProgressBar).get_meta("pc") as Label).text = "%d%%" % int(ceil(float(pvp.hp[s])))
	for w in _weapon_btns:
		(_weapon_btns[w] as Button).button_pressed = w == _weapon
	var total: int = ServerDef.price(_weapon) * _count
	_count_lbl.text = "×%d · %s" % [_count, GS.fmt_money(total)]
	if _aim == Vector2.INF:
		_aim_lbl.text = GS.t("🎯 Коснитесь плана города, чтобы выбрать цель")
	else:
		_aim_lbl.text = GS.t("🎯 Цель: %s") % place_name(_aim)
	var why: String = pvp.blocker(_weapon, _count)
	if why == "" and _aim == Vector2.INF:
		why = GS.t("Цель не выбрана")
	_go.disabled = why != ""
	_why.text = why
	_why.visible = why != ""
	_plan.queue_redraw()


## The strikes of our side, rebuilt when one is added or changes its state; the clocks tick in place.
func _refresh_list() -> void:
	var ids: Array = pvp.outgoing.keys()
	ids.sort()
	var sig := ""
	for id in ids:
		sig += "%s:%s;" % [id, String(pvp.outgoing[id].st)]
	if sig != _list_sig:
		_list_sig = sig
		for c in _list.get_children():
			c.queue_free()
		if ids.is_empty():
			_list.add_child(UiKit.label(GS.t("Пока ни одного — выберите цель и оружие."), 13, Color(0.55, 0.8, 0.7)))
		for id in ids:
			var l := UiKit.label("", 13)
			l.set_meta("id", id)
			_list.add_child(l)
	for l in _list.get_children():
		if not l.has_meta("id") or not pvp.outgoing.has(l.get_meta("id")):
			continue
		var o: Dictionary = pvp.outgoing[l.get_meta("id")]
		var head := "%s ×%d" % [GS.t(ServerDef.short_name(String(o.w))), int(o.c)]
		if String(o.by) != Net.code() and String(o.get("n", "")) != "":
			head += " · " + String(o.n)
		var col := UiKit.CYAN
		match String(o.st):
			"fly":
				head += GS.t(" — в пути, %s") % pvp.fmt_time(pvp.eta(o))
			"fight":
				head += GS.t(" — над городом, идёт бой")
				col = UiKit.AMBER
			_:
				head += GS.t(" — в цель %d, сбито %d") % [int(o.h), int(o.k)]
				col = UiKit.NEON if int(o.h) > 0 else Color(0.6, 0.66, 0.63)
		(l as Label).text = head
		(l as Label).add_theme_color_override("font_color", col)


func _process(delta: float) -> void:
	_t += delta
	_refresh_list()
	_plan.queue_redraw()


func _draw_overlay(plan: CityPlan) -> void:
	# where the strikes of our side are going and how they ended
	for id in pvp.outgoing:
		var o: Dictionary = pvp.outgoing[id]
		var p := plan.at(Vector2(float(o.x), float(o.z)))
		match String(o.st):
			"fly":
				var k := fposmod(_t * 0.7, 1.0)
				plan.draw_arc(p, 8.0 + 16.0 * k, 0, TAU, 24, Color(0.35, 0.85, 1.0, 0.8 * (1.0 - k)), 1.5)
				plan.draw_circle(p, 3.0, UiKit.CYAN)
				plan.text(p + Vector2(0, -12), pvp.fmt_time(pvp.eta(o)), 12, UiKit.CYAN)
			"fight":
				plan.draw_arc(p, 9.0 + 3.0 * sin(_t * 9.0), 0, TAU, 24, UiKit.AMBER, 2.0)
				plan.draw_circle(p, 3.0, UiKit.AMBER)
			_:
				var col := Color(1.0, 0.4, 0.25) if int(o.h) > 0 else Color(0.6, 0.66, 0.63)
				plan.draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), col, 2.5)
				plan.draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), col, 2.5)
				plan.text(p + Vector2(0, -12), "%d/%d" % [int(o.h), int(o.c)], 12, col)
	if _aim != Vector2.INF:
		var p := plan.at(_aim)
		var r := 15.0 + 2.0 * sin(_t * 5.0)
		plan.draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.0)
		for q in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			plan.draw_line(p + q * (r - 6.0), p + q * (r + 9.0), Color(1, 1, 1, 0.95), 2.0)
		plan.draw_circle(p, 2.5, UiKit.RED)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or GS.action_of(k) in ["strikes", "pause"]:
			get_viewport().set_input_as_handled()
			close()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			if not _go.disabled:
				_launch()
