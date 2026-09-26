extends Control
## "Strikes" screen [K]: the operational map of the launch sites around the city and the strikes
## we send at them. The city sits in the middle, the sites on the bearings their threats arrive
## from and at their distance (the scale is compressed so a position 45 km away and an airfield
## 1000 km away both fit). Unknown sites show only their sector until the radar tracks a launch
## back. Picking a site shows what it launches, its state and the strike options; strikes in
## flight crawl towards their targets and land at dusk (scripts/game/strikes.gd).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Strikes = preload("res://scripts/game/strikes.gd")

signal closed

const RED := Color(1.0, 0.32, 0.26)
const AMBER := Color(1.0, 0.72, 0.3)
const GREY := Color(0.5, 0.55, 0.53)

var game
var _map: MapView
var _side: VBoxContainer
var _money: Label
var _sel := ""


## The map itself: rings, bearings, the city, the sites and the strikes in flight.
class MapView extends Control:
	var owner_screen
	var sites: Array = []
	var sel := ""
	var _t := 0.0
	var _max_km := 1000.0
	## Where each site is drawn: its bearing, eased apart from neighbours in the same sector.
	var _pos := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	## km -> pixels, compressed so the near positions do not sit on top of the city.
	func radius(km: float) -> float:
		var r := minf(size.x, size.y) * 0.5 - 46.0
		return r * pow(clampf(km / _max_km, 0.0, 1.2), 0.6)

	func at(bearing: float, km: float) -> Vector2:
		var a := deg_to_rad(bearing)
		return size * 0.5 + Vector2(sin(a), -cos(a)) * radius(km)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_pick((event as InputEventMouseButton).position)
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			_pick((event as InputEventScreenTouch).position)

	## Sites in one sector would sit on top of each other: their bearings are fanned out until the
	## icons are ~46 px apart (the distance from the city stays true).
	func _layout() -> void:
		var ang := {}
		for s in sites:
			ang[String(s.id)] = float(s.bearing)
		for it in 40:
			var moved := false
			for a in sites:
				for b in sites:
					var ia := String(a.id)
					var ib := String(b.id)
					if ia >= ib:
						continue
					var pa := at(float(ang[ia]), float(a.km))
					var pb := at(float(ang[ib]), float(b.km))
					if pa.distance_to(pb) < 46.0:
						var d := wrapf(float(ang[ib]) - float(ang[ia]), -180.0, 180.0)
						var step := 2.5 if d >= 0.0 else -2.5
						ang[ia] = float(ang[ia]) - step
						ang[ib] = float(ang[ib]) + step
						moved = true
			if not moved:
				break
		_pos.clear()
		for s in sites:
			_pos[String(s.id)] = at(float(ang[String(s.id)]), float(s.km))

	func spot(s: Dictionary) -> Vector2:
		return _pos.get(String(s.id), at(float(s.bearing), float(s.km)))

	func _pick(p: Vector2) -> void:
		var best := ""
		var bd := 44.0
		for s in sites:
			var d := p.distance_to(spot(s))
			if d < bd:
				bd = d
				best = String(s.id)
		if best != "":
			owner_screen.select(best)

	func _draw() -> void:
		var sz := size
		var c := sz * 0.5
		_max_km = 100.0
		for s in sites:
			_max_km = maxf(_max_km, float(s.km) * 1.1)
		_layout()
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.05, 0.045, 0.96))
		var grid := Color(0.2, 1.0, 0.65, 0.05)
		for x in range(0, int(sz.x), 40):
			draw_line(Vector2(x, 0), Vector2(x, sz.y), grid, 1.0)
		for y in range(0, int(sz.y), 40):
			draw_line(Vector2(0, y), Vector2(sz.x, y), grid, 1.0)
		# distance rings
		for km in [50.0, 100.0, 250.0, 500.0, 1000.0]:
			if km > _max_km:
				continue
			var r := radius(km)
			draw_arc(c, r, 0, TAU, 96, Color(0.2, 1.0, 0.65, 0.18), 1.2)
			_txt(c + Vector2(4, -r - 3), GS.t("%d км") % int(km), 11, Color(0.4, 0.9, 0.7, 0.55))
		# reach of our strike weapons
		var reach_cols := {"lyutyi": Color(0.35, 0.85, 1.0, 0.35), "neptune": Color(1.0, 0.85, 0.35, 0.35), "storm": Color(1.0, 0.45, 0.9, 0.35)}
		for w in Strikes.WEAPON_ORDER:
			var r := radius(float(Strikes.WEAPONS[w].range))
			if r < minf(sz.x, sz.y) * 0.5:
				_dashed_circle(c, r, reach_cols[w])
				_txt(c + Vector2(-r * 0.71 - 110, r * 0.71 + 14), GS.t(String(Strikes.WEAPONS[w].short)), 11, reach_cols[w] * Color(1, 1, 1, 2.2), HORIZONTAL_ALIGNMENT_RIGHT, 110)
		# compass
		_txt(c + Vector2(-5, -radius(_max_km) - 20), GS.t("С"), 14, Color(0.6, 1.0, 0.8, 0.8))
		# strikes in flight: dotted tracks with a head crawling towards the target until dusk
		var prog := 1.0
		if owner_screen.game != null and owner_screen.game.director != null and not owner_screen.game.director.is_night():
			prog = clampf(owner_screen.game.director.phase_time / maxf(owner_screen.game.director.phase_len, 1.0), 0.05, 1.0)
		var k := 0
		for x in GS.strikes:
			for s in sites:
				if String(s.id) == String(x.site):
					var to := spot(s)
					var off := Vector2(-(to - c).y, (to - c).x).normalized() * (k % 3 - 1) * 6.0
					_dashed_line(c + off, to + off, Color(0.4, 1.0, 0.7, 0.45))
					var head := (c + off).lerp(to + off, prog)
					draw_circle(head, 4.0, Color(0.6, 1.0, 0.8))
					draw_circle(head, 8.0 + 2.0 * sin(_t * 8.0), Color(0.4, 1.0, 0.7, 0.2))
			k += 1
		# the sites; their captions go last, nudged apart where they would overlap
		var captions := []
		for s in sites:
			var id := String(s.id)
			var st := Strikes.state(id)
			var p := spot(s)
			if not bool(st.known):
				_dashed_line(c, p, Color(1.0, 0.45, 0.35, 0.18))
				draw_arc(p, 13.0, 0, TAU, 20, Color(1.0, 0.5, 0.4, 0.35), 1.2)
				_txt(p + Vector2(-5, 5), "?", 16, Color(1.0, 0.6, 0.5, 0.7))
				if id == sel:
					draw_arc(p, 20.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
				continue
			var col := RED
			match String(st.st):
				"damaged":
					col = AMBER
				"destroyed":
					col = GREY
			if String(st.st) == "ok":
				draw_arc(p, 14.0 + 6.0 * fposmod(_t * 0.8, 1.0), 0, TAU, 24, Color(col.r, col.g, col.b, 0.5 * (1.0 - fposmod(_t * 0.8, 1.0))), 1.5)
			_icon(p, String(s.icon), col)
			if String(st.st) == "destroyed":
				draw_line(p + Vector2(-11, -11), p + Vector2(11, 11), RED, 2.5)
				draw_line(p + Vector2(-11, 11), p + Vector2(11, -11), RED, 2.5)
			if id == sel:
				draw_arc(p, 21.0, 0, TAU, 28, Color(1, 1, 1, 0.9), 2.0)
				for q in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
					draw_line(p + q * 25.0, p + q * 33.0, Color(1, 1, 1, 0.9), 2.0)
			captions.append([p, "%s · %d км" % [GS.t(String(s.short)), int(s.km)], col])
		var taken: Array[Rect2] = [Rect2(c - Vector2(60, 12), Vector2(120, 40))]
		captions.sort_custom(func(a, b) -> bool: return (a[0] as Vector2).y < (b[0] as Vector2).y)
		for cap in captions:
			var p: Vector2 = cap[0]
			var right := p.x < sz.x * 0.7
			var w := GS.font.get_string_size(String(cap[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var r := Rect2(Vector2(p.x + 18 if right else p.x - 18 - w, p.y - 18), Vector2(w, 16))
			for tries in 8:
				if not taken.any(func(t: Rect2) -> bool: return t.intersects(r)):
					break
				r.position.y += 16.0
			taken.append(r)
			var cc: Color = cap[2]
			_txt(r.position + Vector2(0, 13), String(cap[1]), 12, Color(cc.r, cc.g, cc.b, 0.95))
		# the city
		draw_circle(c, 16.0 + 3.0 * sin(_t * 2.0), Color(0.2, 1.0, 0.65, 0.15))
		draw_circle(c, 7.0, Color(0.2, 1.0, 0.65))
		draw_arc(c, 11.0, 0, TAU, 24, Color(0.7, 1.0, 0.85), 1.5)
		_txt(c + Vector2(-100, 30), GS.t(String(GS.city_def().name)), 15, Color(0.7, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200)

	func _icon(p: Vector2, kind: String, col: Color) -> void:
		draw_circle(p, 13.0, Color(0, 0, 0, 0.55))
		match kind:
			"drone":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(9, 7), p + Vector2(0, 3), p + Vector2(-9, 7)]), col)
			"plane":
				draw_line(p + Vector2(0, -10), p + Vector2(0, 10), col, 3.0)
				draw_line(p + Vector2(-10, -1), p + Vector2(10, -1), col, 3.0)
				draw_line(p + Vector2(-5, 8), p + Vector2(5, 8), col, 2.5)
			"ship":
				draw_colored_polygon(PackedVector2Array([p + Vector2(-11, 1), p + Vector2(11, 1), p + Vector2(7, 7), p + Vector2(-8, 7)]), col)
				draw_rect(Rect2(p + Vector2(-4, -6), Vector2(8, 7)), col)
				draw_line(p + Vector2(0, -6), p + Vector2(0, -11), col, 1.5)
			_:
				draw_rect(Rect2(p + Vector2(-3, -4), Vector2(6, 12)), col)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -4), p + Vector2(3, -4), p + Vector2(0, -11)]), col)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 5), p + Vector2(-7, 9), p + Vector2(-3, 9)]), col)
				draw_colored_polygon(PackedVector2Array([p + Vector2(3, 5), p + Vector2(7, 9), p + Vector2(3, 9)]), col)

	func _dashed_line(a: Vector2, b: Vector2, col: Color) -> void:
		var n := int(a.distance_to(b) / 9.0)
		for i in n:
			if i % 2 == 0:
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 1.5)

	func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
		var n := maxi(24, int(r / 5.0))
		for i in n:
			if i % 2 == 0:
				draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 3, col, 1.4)

	func _txt(p: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
		draw_string_outline(GS.font, p, s, align, width, sz, 4, Color(0, 0, 0, 0.8))
		draw_string(GS.font, p, s, align, width, sz, col)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	var title := UiKit.glow_label(GS.t("ОПЕРАТИВНАЯ КАРТА · УДАРЫ ПО ТОЧКАМ ПУСКА"), 26, UiKit.NEON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = UiKit.label("", 24, UiKit.NEON)
	top.add_child(_money)
	var h := UiKit.hbox(12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_map = MapView.new()
	_map.owner_screen = self
	_map.custom_minimum_size = Vector2(760, 570)
	_map.sites = Strikes.sites(GS.city_def())
	h.add_child(_map)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 570)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_side = UiKit.vbox(8)
	_side.custom_minimum_size = Vector2(364, 0)
	scroll.add_child(_side)
	# start on a known site that still works, else any known one, else the first sector
	for s in _map.sites:
		if bool(Strikes.state(String(s.id)).known) and (_sel == "" or String(Strikes.state(_sel).st) != "ok"):
			_sel = String(s.id)
	if _sel == "" and not _map.sites.is_empty():
		_sel = String(_map.sites[0].id)
	GS.state_changed.connect(_refresh)
	_refresh()


func select(id: String) -> void:
	if id != _sel:
		SFX.play("click", -8.0)
	_sel = id
	_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or GS.action_of(k) in ["strikes", "pause"]:
			get_viewport().set_input_as_handled()
			close()


func _is_day() -> bool:
	return game != null and game.director != null and not game.director.is_night()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_money.text = GS.fmt_money(GS.money)
	_map.sel = _sel
	for ch in _side.get_children():
		ch.queue_free()
	var s := {}
	for x in _map.sites:
		if String(x.id) == _sel:
			s = x
	if s.is_empty():
		_note(GS.t("У этого города нет известных точек пуска."), UiKit.AMBER)
		_close_btn()
		return
	var st := Strikes.state(_sel)
	var known := bool(st.known)
	var name_l := UiKit.glow_label(GS.t(String(s.name)) if known else GS.t("Неизвестный район пуска"), 20, RED if known else UiKit.AMBER)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(360, 0)
	_side.add_child(name_l)
	var what := []
	for w in s.weapons:
		what.append(GS.t(String(GS.ENEMIES[w].plural)))
	_note(GS.t("Запускает: %s") % ", ".join(what), Color(0.85, 1.0, 0.92), 14)
	_note(GS.t("Направление: %s · ~%d км") % [Strikes.compass(float(s.bearing)), int(s.km)], Color(0.6, 0.9, 0.78), 14)
	if not known:
		_note(GS.t("Район пуска ещё не установлен: разведка засечёт его, когда оттуда прилетит первая цель."), UiKit.AMBER, 14)
	else:
		var d := clampf(float(s.def) + float(st.def), 0.0, 0.9)
		var lvl := GS.t("слабая") if d < 0.3 else (GS.t("средняя") if d < 0.5 else GS.t("сильная"))
		_note(GS.t("ПВО точки: %s") % lvl, Color(0.6, 0.9, 0.78), 14)
		var scol := UiKit.NEON if String(st.st) == "ok" else (AMBER if String(st.st) == "damaged" else GREY)
		_note(Strikes.status_text(_sel), RED if String(st.st) == "ok" else scol, 16)
	var flying := Strikes.in_flight(_sel)
	if flying > 0:
		_note(GS.t("В полёте: %d — долетят к ночи") % flying, UiKit.CYAN, 15)
	_side.add_child(HSeparator.new())
	_note(GS.t("НАНЕСТИ УДАР"), UiKit.AMBER, 15)
	for w in Strikes.WEAPON_ORDER:
		var wd: Dictionary = Strikes.WEAPONS[w]
		var why := Strikes.blocker(s, w, _is_day())
		var txt := "%s · %s" % [GS.t(String(wd.short)), GS.fmt_money(int(wd.price))]
		if why == "" or why == GS.t("Не хватает денег") or why == GS.t("Удары наносятся днём"):
			if known:
				txt += GS.t(" · шанс %d%%") % int(round(Strikes.chance(s, w) * 100.0))
		var b := UiKit.button(txt, func() -> void:
			if Strikes.blocker(s, w, _is_day()) == "":
				Strikes.launch(s, w)
				SFX.play("launch", -6.0)
				if game != null:
					game.hud.log_event(GS.t("Удар %s по цели «%s» — в полёте, долетит к ночи") % [GS.t(String(wd.short)), GS.t(String(s.name))], UiKit.CYAN)
				_refresh(), 360, 16)
		b.disabled = why != ""
		_side.add_child(b)
		_note(why if why != "" else GS.t(String(wd.desc)), RED if why != "" else Color(0.55, 0.8, 0.7), 12)
	_side.add_child(HSeparator.new())
	_note(GS.t("Удары наносятся днём и долетают к ночи. Повреждённая точка запускает вдвое меньше, уничтоженная молчит, пока её не восстановят. После каждого удара противник усиливает ПВО точки."), Color(0.55, 0.8, 0.7), 12)
	_close_btn()


func _note(text: String, col: Color, size := 13) -> Label:
	var l := UiKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	_side.add_child(l)
	return l


func _close_btn() -> void:
	_side.add_child(UiKit.button(GS.t("Закрыть [%s]") % GS.key_label("strikes"), close, 360, 18))
