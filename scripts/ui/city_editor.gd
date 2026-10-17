extends Control
## The city editor: a city drawn from nothing — rivers and lakes, woods, districts with their
## kind of housing, avenues with bridges, railways and the objects an enemy will aim at. It draws
## a city of the player's own (the map editor, CityStore) or one of the two cities of a server
## (ServerDef): whoever opens it gives the drawing to start from and is told of every change
## (`changed`) and of the end (`done`).
##
## The city is drawn in 3D, on the city itself: the generator of the game (CityMap) builds it
## from the drawing (CustomCity) and the camera flies over it as over any map of the game
## (CameraRig). The drawing lies on top as marks (CityGizmos); after a change the city is built
## again — by itself a moment later on a computer, by the "Build" button on a touch screen,
## where a build is a noticeable pause. The flat plan (CityPlan) is the other view of the same
## drawing, a button away.
##
## A tool is picked on the right and the ground is tapped: a district, a lake, a wood or an
## object appears under the finger; a river, a road or a railway grows point by point until
## "Finish". The "Select" tool picks what is tapped (its name, size and turn are then on the
## right) and drags it; dragging empty ground moves the view. The wheel or a pinch scales it, the
## right mouse button or two fingers turning about each other turn the 3D view.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CityPlan = preload("res://scripts/ui/city_plan.gd")
const CustomCity = preload("res://scripts/world/custom_city.gd")
const Cities = preload("res://scripts/world/cities.gd")
const CityGizmos = preload("res://scripts/ui/city_gizmos.gd")
const CameraRig = preload("res://scripts/game/camera_rig.gd")

## The drawing changed: the city as it is now (to be written wherever it lives).
signal changed(city: Dictionary)
## "Done": the final, cleaned city.
signal done(city: Dictionary)

## Tools: id, label. "select" picks and drags; the rest add what they name.
const TOOLS := [
	["select", "✋ Выбор"], ["district", "🏘 Район"], ["road", "🛣 Дорога"], ["rail", "🚆 Ж/д"],
	["river", "🌊 Река"], ["lake", "💧 Озеро"], ["forest", "🌲 Лес"], ["object", "🏭 Объект"],
]
## Which list of the city data a line tool draws into.
const LINE_LISTS := {"river": "rivers", "road": "roads", "rail": "rails"}
const LIST_OF := {"district": "districts", "object": "objects", "lake": "lakes", "forest": "forests", "river": "rivers", "road": "roads", "rail": "rails"}
const LIMITS := {"districts": CustomCity.MAX_DISTRICTS, "objects": CustomCity.MAX_OBJECTS, "lakes": CustomCity.MAX_LAKES, "forests": CustomCity.MAX_FORESTS,
	"rivers": CustomCity.MAX_RIVERS, "roads": CustomCity.MAX_ROADS, "rails": CustomCity.MAX_RAILS}
const UNDO_MAX := 40
## A computer builds the 3D city again this long after the last change, seconds.
const AUTO_BUILD := 0.9

## The city to start from, the caption in the corner and its colour; `flip` mirrors the
## ready-made sample (the second city of a server).
var source := {}
var caption := ""
var caption_color := UiKit.NEON
var flip := false
## The root (main.gd): its map and camera are the 3D view. The id the city is built under.
var main
var city_id := "edit_city"
## The view the editor opens in: "3d" or "plan".
var view := "3d"
## The city being drawn (a working copy; every change is told through `changed`).
var data := {}

var _plan: CityPlan
var _bg: ColorRect
var _rig: CameraRig
var _giz: CityGizmos
var _view_btn: Button
var _build_btn: Button
var _turn_btns: Array = []
var _veil: Control
## The 3D city is behind the drawing (and for how long nothing has changed).
var _stale := true
var _stale_t := 0.0
var _building := false
## Built again by itself (a computer) or by the button only (a touch screen).
var _auto := true
## Grows with every change of the drawing: the marks over the 3D city follow it.
var _version := 0
var _name: LineEdit
var _tool := "select"
var _tool_btns := {}
var _box: VBoxContainer
var _hint: Label
var _counts: Label
var _undo_btn: Button
## The line being drawn point by point: [[x, z], …] (a river's points get their width when it is finished).
var _draft: Array = []
## What is selected: {} or {"type": "district" | "object" | "lake" | "forest" | "river" | "road" | "rail", "i": index, "pt": point of a line or -1}.
var _sel := {}
var _kind := "panel"
var _object := "plant"
var _undo: Array = []
var _drag := {}
var _confirm: Control
var _t := 0.0


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	data = CustomCity.clean(source)
	_auto = not GS.touch()
	_bg = UiKit.full_rect(ColorRect.new()) as ColorRect
	_bg.color = Color(0.0, 0.03, 0.03, 0.97)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	# --- the 3D view: the game's map camera over the built city, the drawing on top as marks
	_rig = CameraRig.new()
	_rig.cam = main.cam
	_rig.yaw = 0.0
	_rig.pitch = 0.95
	_rig.drag_hook = _rig_grab
	_rig.clicked.connect(_rig_click)
	_rig.dragged.connect(_rig_drag)
	add_child(_rig)
	_giz = CityGizmos.new()
	add_child(_giz)
	# --- the plan
	_plan = CityPlan.new()
	_plan.anchor_right = 1.0
	_plan.anchor_bottom = 1.0
	_plan.offset_left = 10
	_plan.offset_top = 62
	_plan.offset_right = -372
	_plan.offset_bottom = -10
	_plan.overlay = _draw_overlay
	_plan.tapped.connect(_on_tap)
	_plan.dragged.connect(_on_drag)
	add_child(_plan)
	_plan.set_data(data)
	# --- the top line: whose city, its name and size
	var top := UiKit.hbox(8)
	top.anchor_right = 1.0
	top.offset_left = 10
	top.offset_top = 10
	top.offset_right = -372
	top.offset_bottom = 56
	add_child(top)
	var title := UiKit.glow_label(caption, 24, caption_color)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	_name = LineEdit.new()
	_name.max_length = CustomCity.NAME_MAX
	_name.text = String(data.name)
	_name.custom_minimum_size = Vector2(170, 42)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 20)
	_name.select_all_on_focus = true
	_name.text_submitted.connect(func(_s: String) -> void: _name.release_focus())
	_name.focus_exited.connect(_save_name)
	top.add_child(_name)
	_view_btn = UiKit.button("", func() -> void: set_view("plan" if view == "3d" else "3d"), 120, 17)
	_view_btn.focus_mode = Control.FOCUS_NONE
	_view_btn.custom_minimum_size = Vector2(120, 42)
	top.add_child(_view_btn)
	_build_btn = UiKit.button(GS.t("🏗 Построить"), _build3d, 170, 17)
	_build_btn.focus_mode = Control.FOCUS_NONE
	_build_btn.custom_minimum_size = Vector2(170, 42)
	_build_btn.tooltip_text = GS.t("Построить 3D-город заново по рисунку")
	top.add_child(_build_btn)
	# --- over the view, at its right edge: scale, the whole city, and for 3D turn and tilt (held)
	var side := UiKit.vbox(6)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -426
	side.offset_right = -378
	side.offset_top = 70
	add_child(side)
	for spec in [["+", 1.0 / 1.3], ["−", 1.3]]:
		var f: float = spec[1]
		var zb := UiKit.button(String(spec[0]), func() -> void: _zoom(f), 46, 22)
		zb.focus_mode = Control.FOCUS_NONE
		zb.custom_minimum_size = Vector2(46, 46)
		side.add_child(zb)
	var fit := UiKit.button("⛶", _fit, 46, 20)
	fit.focus_mode = Control.FOCUS_NONE
	fit.custom_minimum_size = Vector2(46, 46)
	fit.tooltip_text = GS.t("Весь город")
	side.add_child(fit)
	for spec in [["⟲", "turn", -1.0], ["⟳", "turn", 1.0], ["▲", "tilt", 1.0], ["▼", "tilt", -1.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(46, 46)
		b.add_theme_font_size_override("font_size", 22)
		var prop: String = spec[1]
		var dir: float = spec[2]
		b.button_down.connect(func() -> void: _rig.set(prop, dir))
		b.button_up.connect(func() -> void: _rig.set(prop, 0.0))
		side.add_child(b)
		_turn_btns.append(b)
	# --- the right panel: tools, what is selected, the buttons
	var p := UiKit.panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -364
	p.offset_right = -8
	p.offset_top = 8
	p.offset_bottom = -8
	add_child(p)
	var v := UiKit.vbox(6)
	p.add_child(v)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for spec in TOOLS:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = GS.t(String(spec[1]))
		b.custom_minimum_size = Vector2(160, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_set_tool.bind(String(spec[0])))
		grid.add_child(b)
		_tool_btns[spec[0]] = b
	_hint = UiKit.label("", 13, Color(0.6, 0.9, 0.78))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(326, 54)
	v.add_child(_hint)
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_box = UiKit.vbox(6)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	v.add_child(HSeparator.new())
	_counts = UiKit.label("", 12, Color(0.55, 0.8, 0.7))
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counts.custom_minimum_size = Vector2(326, 0)
	v.add_child(_counts)
	var row := UiKit.hbox(6)
	v.add_child(row)
	_undo_btn = UiKit.button(GS.t("↶ Отменить"), undo, 160, 16)
	row.add_child(_undo_btn)
	row.add_child(UiKit.button(GS.t("Очистить"), _ask_clear, 160, 16))
	v.add_child(UiKit.button(GS.t("Готово ✔"), _done, 326, 20))
	_set_tool("select")
	_fit()
	set_view(view)


func _exit_tree() -> void:
	# the map goes back to the menus as they expect it
	if main != null and main.map != null and is_instance_valid(main.map):
		main.map.visible = true
		main.map.set_fog_scale(1.0)


# --- The two views --------------------------------------------------------------------------------
## "3d": the built city under the camera, the drawing as marks on it. "plan": the flat drawing.
func set_view(v: String) -> void:
	view = "plan" if v == "plan" else "3d"
	var three := view == "3d"
	_bg.visible = not three
	_plan.visible = not three
	_giz.visible = three
	_rig.set_process(three)
	_rig.set_process_unhandled_input(three)
	# in 3D whatever no control takes goes on to the camera and the ground under the pointer
	mouse_filter = Control.MOUSE_FILTER_IGNORE if three else Control.MOUSE_FILTER_STOP
	for b in _turn_btns:
		(b as Button).visible = three
	_build_btn.visible = three
	_view_btn.text = GS.t("🗺 План") if three else GS.t("🏙 3D")
	_view_btn.tooltip_text = GS.t("Плоский план города") if three else GS.t("Город в 3D")
	main.map.visible = three
	if three:
		_look()
		if main.map.city_id != city_id or main.map.city != Cities.get_def(city_id):
			_stale = true
			_build3d()
	_refresh()


## The look of the map in the editor: daylight and a clear air, none of its own captions.
func _look() -> void:
	main.map.visible = view == "3d"
	main.map.set_fog_scale(0.0)
	main.map.set_night(0.2)
	main.map.set_labels_visible(false)


## Builds the 3D city again from the drawing as it is now. A build is a pause of a second or a
## few: a veil says so first (two frames, so it is on screen before the pause).
func _build3d() -> void:
	if _building or view != "3d":
		return
	_building = true
	_veil = UiKit.full_rect(ColorRect.new())
	(_veil as ColorRect).color = Color(0.0, 0.03, 0.04, 0.6)
	var lbl := UiKit.glow_label(GS.t("Строим город…"), 30, UiKit.NEON)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_veil.add_child(lbl)
	add_child(_veil)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	Cities.register(city_id, data)
	main.build_city(city_id)
	_rig.bounds = float(data.size) * 1.05
	_look()
	_veil.queue_free()
	_veil = null
	_stale = false
	_building = false


## The whole city in view.
func _fit() -> void:
	_plan.fit()
	var h := float(data.size)
	_rig.bounds = h * 1.05
	# (the panel on the right covers a part of the screen, and the camera aims a little above its
	# target: the city is put in the middle of what is left)
	_rig._t_target = Vector3(h * 0.2, 0.0, -h * 0.04)
	_rig._t_dist = h * 1.95
	_rig._t_yaw = 0.0
	_rig._t_pitch = 1.0
	if not _rig.is_processing():
		# not on screen yet: nothing to glide from
		_rig.target = _rig._t_target
		_rig.dist = _rig._t_dist
		_rig.yaw = 0.0
		_rig.pitch = 1.0


## Closer (f < 1) or further.
func _zoom(f: float) -> void:
	if view == "3d":
		_rig._t_dist = clampf(_rig._t_dist * f, 150.0, float(data.size) * 4.0)
	else:
		_plan.zoom_by(1.0 / f)


## The marks follow the drawing in both views.
func _redraw() -> void:
	_version += 1
	_plan.queue_redraw()


## The point of the ground under a point of the screen (3D view); null over the sky.
func _ground(screen: Vector2) -> Variant:
	var cam: Camera3D = main.cam
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if dir.y >= -0.001:
		return null
	var p := from + dir * (-from.y / dir.y)
	return Vector2(p.x, p.z)


## Metres of the city in one unit of the interface at a point (how far a finger may miss).
func _m_per_unit(w: Vector2) -> float:
	if view != "3d":
		return 1.0 / maxf(_plan.zoom, 0.00001)
	var cam: Camera3D = main.cam
	var d := cam.global_position.distance_to(Vector3(w.x, 0.0, w.y))
	return 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) / maxf(get_viewport().get_visible_rect().size.y, 1.0)


func _rig_click(pos: Vector2) -> void:
	var w = _ground(pos)
	if w != null and not _building:
		_on_tap(w)


## A left drag begins in the 3D view: on something the "Select" tool can move it is ours, on empty
## ground the camera's.
func _rig_grab(pos: Vector2) -> bool:
	var w = _ground(pos)
	if w == null or _building:
		return false
	_on_drag(w, 0)
	if bool(_drag.get("pan", true)):
		_drag = {}
		return false
	return true


func _rig_drag(pos: Vector2, phase: int) -> void:
	var w = _ground(pos)
	if w == null:
		w = _drag.get("last", Vector2.ZERO) # the finger went up into the sky: where it last was
	_on_drag(w, phase)


# --- State -----------------------------------------------------------------------------------------
func _list(type: String) -> Array:
	return data[LIST_OF[type]]


func _remember() -> void:
	_undo.append(JSON.stringify(data))
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


## The drawing changed: its owner writes it down at once.
func _commit() -> void:
	changed.emit(data.duplicate(true))
	_stale = true
	_stale_t = 0.0
	_plan.data = data
	_redraw()
	_refresh()


func undo() -> void:
	if not _draft.is_empty():
		_draft.pop_back()
		_refresh()
		return
	if _undo.is_empty():
		return
	data = CustomCity.clean(JSON.parse_string(_undo.pop_back()))
	_sel = {}
	_commit()


func _save_name() -> void:
	var n := CustomCity.clean_name(_name.text)
	if n == "":
		n = String(data.name)
	_name.text = n
	if n != String(data.name):
		_remember()
		data.name = n
		_commit()


func _resize_city(half: float) -> void:
	SFX.play("click", -8.0)
	if is_equal_approx(half, float(data.size)):
		_refresh()
		return
	_remember()
	data.size = half
	data = CustomCity.clean(data) # what lay beyond the new edge is moved onto it
	_sel = {}
	_commit()
	_fit()


func _set_tool(t: String) -> void:
	_finish_line()
	_tool = t
	if t != "select":
		_sel = {}
	_refresh()


func _full(type: String) -> bool:
	return _list(type).size() >= int(LIMITS[LIST_OF[type]])


# --- Taps and drags on the plan -----------------------------------------------------------------
func _inside(w: Vector2) -> bool:
	var h := float(data.size)
	return absf(w.x) <= h and absf(w.y) <= h


func _on_tap(w: Vector2) -> void:
	if _tool == "select":
		_sel = _hit(w)
		SFX.play("click", -10.0)
		_refresh()
		return
	if not _inside(w):
		return
	if _full(_tool) and _draft.is_empty():
		SFX.play("alert", -12.0)
		_hint.text = GS.t("Больше нельзя: лимит этого вида исчерпан.")
		return
	SFX.play("click", -8.0)
	match _tool:
		"district":
			_remember()
			var n := _list("district").size() + 1
			data.districts.append([GS.t("Район %d") % n, w.x, w.y, 0.0, _kind, 900.0])
			_sel = {"type": "district", "i": data.districts.size() - 1, "pt": -1}
			_commit()
		"object":
			_remember()
			data.objects.append({"k": _object, "x": w.x, "z": w.y, "r": 0.0, "n": ""})
			_sel = {"type": "object", "i": data.objects.size() - 1, "pt": -1}
			_commit()
		"lake":
			_remember()
			data.lakes.append([w.x, w.y, 420.0, 280.0, 0.0])
			_sel = {"type": "lake", "i": data.lakes.size() - 1, "pt": -1}
			_commit()
		"forest":
			_remember()
			data.forests.append([w.x, w.y, 1200.0, 900.0, 0.0])
			_sel = {"type": "forest", "i": data.forests.size() - 1, "pt": -1}
			_commit()
		_:
			if _draft.size() < CustomCity.MAX_POINTS and (_draft.is_empty() or Vector2(_draft[-1][0], _draft[-1][1]).distance_to(w) > 30.0):
				_draft.append([w.x, w.y])
			_refresh()


## Ends the line being drawn: two points or more make a river, a road or a railway.
func _finish_line() -> void:
	if not LINE_LISTS.has(_tool) or _draft.size() < 2:
		_draft = []
		return
	_remember()
	var pts := []
	for p in _draft:
		pts.append([p[0], p[1], 150.0] if _tool == "river" else [p[0], p[1]])
	data[LINE_LISTS[_tool]].append({"n": "", "p": pts})
	_draft = []
	_sel = {"type": _tool, "i": (data[LINE_LISTS[_tool]] as Array).size() - 1, "pt": -1}
	_commit()


## What is under a point of the plan: objects first, then the points of lines, districts, water, woods.
func _hit(w: Vector2) -> Dictionary:
	var px := _m_per_unit(w) # metres in a unit of the screen: how far a finger may miss
	var best := {}
	var bd := 18.0 * px
	for i in data.objects.size():
		var d := Vector2(float(data.objects[i].x), float(data.objects[i].z)).distance_to(w)
		if d < bd:
			bd = d
			best = {"type": "object", "i": i, "pt": -1}
	if not best.is_empty():
		return best
	bd = 14.0 * px
	for type in ["road", "rail", "river"]:
		var lines := _list(type)
		for i in lines.size():
			var pts: Array = lines[i].p
			for k in pts.size():
				var d := Vector2(float(pts[k][0]), float(pts[k][1])).distance_to(w)
				if d < bd:
					bd = d
					best = {"type": type, "i": i, "pt": k}
	if not best.is_empty():
		return best
	# a line anywhere along its length
	bd = 10.0 * px
	for type in ["road", "rail", "river"]:
		var lines := _list(type)
		for i in lines.size():
			var pts: Array = lines[i].p
			for k in pts.size() - 1:
				var a := Vector2(float(pts[k][0]), float(pts[k][1]))
				var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1]))
				var extra := (float(pts[k][2]) if type == "river" else 0.0)
				var d := maxf(Geometry2D.get_closest_point_to_segment(w, a, b).distance_to(w) - extra, 0.0)
				if d < bd:
					bd = d
					best = {"type": type, "i": i, "pt": -1}
	if not best.is_empty():
		return best
	bd = INF
	for i in data.districts.size():
		var d := Vector2(float(data.districts[i][1]), float(data.districts[i][2])).distance_to(w)
		if d < float(data.districts[i][5]) * 1.15 and d < bd:
			bd = d
			best = {"type": "district", "i": i, "pt": -1}
	if not best.is_empty():
		return best
	for type in ["lake", "forest"]:
		var list := _list(type)
		for i in list.size():
			var e: Array = list[i]
			var q := (w - Vector2(float(e[0]), float(e[1]))).rotated(-deg_to_rad(float(e[4])))
			if Vector2(q.x / float(e[2]), q.y / float(e[3])).length() <= 1.0:
				return {"type": type, "i": i, "pt": -1}
	return {}


func _sel_valid() -> bool:
	return not _sel.is_empty() and int(_sel.i) < _list(String(_sel.type)).size()


## Position of the selected item (or of the selected point of a line).
func _sel_pos() -> Vector2:
	var it = _list(String(_sel.type))[int(_sel.i)]
	match String(_sel.type):
		"district":
			return Vector2(float(it[1]), float(it[2]))
		"object":
			return Vector2(float(it.x), float(it.z))
		"lake", "forest":
			return Vector2(float(it[0]), float(it[1]))
	var pts: Array = it.p
	var k := int(_sel.pt) if int(_sel.pt) >= 0 else 0
	return Vector2(float(pts[k][0]), float(pts[k][1]))


## Moves the selected item by `d` metres (a whole line when no point of it is selected).
func _move_sel(d: Vector2) -> void:
	var h := float(data.size)
	var it = _list(String(_sel.type))[int(_sel.i)]
	match String(_sel.type):
		"district":
			it[1] = clampf(float(it[1]) + d.x, -h, h)
			it[2] = clampf(float(it[2]) + d.y, -h, h)
		"object":
			it.x = clampf(float(it.x) + d.x, -h, h)
			it.z = clampf(float(it.z) + d.y, -h, h)
		"lake", "forest":
			it[0] = clampf(float(it[0]) + d.x, -h, h)
			it[1] = clampf(float(it[1]) + d.y, -h, h)
		_:
			var pts: Array = it.p
			for k in pts.size():
				if int(_sel.pt) < 0 or int(_sel.pt) == k:
					pts[k][0] = clampf(float(pts[k][0]) + d.x, -h, h)
					pts[k][1] = clampf(float(pts[k][1]) + d.y, -h, h)


func _on_drag(w: Vector2, phase: int) -> void:
	match phase:
		0:
			var hit := _hit(w) if _tool == "select" else {}
			if hit.is_empty():
				_drag = {"pan": true, "from": w}
			else:
				_sel = hit
				_remember()
				_drag = {"pan": false, "last": w, "moved": false}
				_refresh()
		1:
			if _drag.is_empty():
				return
			if bool(_drag.pan):
				# the grabbed point of the city stays under the finger
				_plan.center += (_drag.from as Vector2) - w
				_plan._clamp_center()
				_redraw()
			elif _sel_valid():
				_move_sel(w - (_drag.last as Vector2))
				_drag.last = w
				_drag.moved = true
				_redraw()
		2:
			if not _drag.is_empty() and not bool(_drag.pan):
				if bool(_drag.moved):
					_commit()
				else:
					_undo.pop_back()
			_drag = {}


# --- The right panel -------------------------------------------------------------------------------
func _refresh() -> void:
	for id in _tool_btns:
		(_tool_btns[id] as Button).button_pressed = id == _tool
	_undo_btn.disabled = _undo.is_empty() and _draft.is_empty()
	_counts.text = GS.t("Районы %d/%d · объекты %d/%d · реки %d/%d · дороги %d/%d · озёра %d · леса %d") % [data.districts.size(), CustomCity.MAX_DISTRICTS,
		data.objects.size(), CustomCity.MAX_OBJECTS, data.rivers.size(), CustomCity.MAX_RIVERS, data.roads.size(), CustomCity.MAX_ROADS, data.lakes.size(), data.forests.size()]
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	match _tool:
		"select":
			_hint.text = GS.t("Коснитесь района, объекта, воды или точки дороги, чтобы выбрать; выбранное можно тащить. Пустое место — сдвиг, колесо или щипок — масштаб, правая кнопка мыши или поворот двумя пальцами — вращение 3D-вида.")
			if _sel_valid():
				_build_selected()
			else:
				_sel = {}
				_box.add_child(_note(GS.t("Ничего не выбрано."), Color(0.55, 0.8, 0.7)))
				# the size of the whole city is set while nothing in it is picked
				_box.add_child(_note(GS.t("РАЗМЕР ГОРОДА"), UiKit.AMBER, 15))
				var sizes := UiKit.hbox(6)
				_box.add_child(sizes)
				for sz in CustomCity.SIZES:
					var sb := Button.new()
					sb.toggle_mode = true
					sb.focus_mode = Control.FOCUS_NONE
					sb.text = GS.t(String(sz[1]))
					sb.custom_minimum_size = Vector2(0, 40)
					sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					sb.add_theme_font_size_override("font_size", 13)
					sb.button_pressed = is_equal_approx(float(sz[0]), float(data.size))
					sb.pressed.connect(_resize_city.bind(float(sz[0])))
					sizes.add_child(sb)
		"district":
			_hint.text = GS.t("Выберите тип застройки и коснитесь плана: появится район. Районы рядом срастаются в один город.")
			_build_kinds()
		"object":
			_hint.text = GS.t("Выберите объект и коснитесь плана. Объекты — цели для ударов противника: без них бить будут по центрам районов.")
			_build_objects()
		"lake":
			_hint.text = GS.t("Коснитесь плана: появится озеро. Размер и поворот — инструментом «Выбор».")
		"forest":
			_hint.text = GS.t("Коснитесь плана: появится лес. В лесу хорошо прятать батарею.")
		_:
			var what := {"river": GS.t("реки"), "road": GS.t("дороги"), "rail": GS.t("железной дороги")}
			_hint.text = GS.t("Касайтесь плана: каждая точка продолжает линию %s. Две точки и больше — «Завершить». Дорога через воду получит мост.") % String(what[_tool])
			_box.add_child(_note(GS.t("Точек в линии: %d") % _draft.size(), UiKit.AMBER))
			var fin := UiKit.button(GS.t("✔ Завершить линию"), func() -> void:
				_finish_line()
				_refresh(), 326, 18)
			fin.disabled = _draft.size() < 2
			_box.add_child(fin)
			var back := UiKit.button(GS.t("↶ Убрать точку"), undo, 326, 16)
			back.disabled = _draft.is_empty()
			_box.add_child(back)
	_redraw()


func _note(text: String, col: Color, size := 13) -> Label:
	var l := UiKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	return l


func _pick_grid(options: Array, current: String, on_pick: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_box.add_child(grid)
	for o in options:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = GS.t(String(o[1]))
		b.custom_minimum_size = Vector2(160, 38)
		b.add_theme_font_size_override("font_size", 13)
		b.clip_text = true
		b.button_pressed = String(o[0]) == current
		b.pressed.connect(func() -> void:
			SFX.play("click", -8.0)
			on_pick.call(String(o[0])))
		grid.add_child(b)


func _build_kinds() -> void:
	_pick_grid(CustomCity.DISTRICT_KINDS, _kind, func(k: String) -> void:
		_kind = k
		_refresh())


func _build_objects() -> void:
	_pick_grid(CustomCity.OBJECT_KINDS, _object, func(k: String) -> void:
		_object = k
		_refresh())


## A slider with its name and value: `apply` gets every new value, the change is one step of the undo.
func _slider(title: String, lo: float, hi: float, step: float, value: float, unit: String, apply: Callable) -> void:
	var l := UiKit.label("", 13, Color(0.7, 1.0, 0.85))
	_box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 30)
	s.focus_mode = Control.FOCUS_NONE
	_box.add_child(s)
	var put := func(v: float) -> void:
		l.text = "%s: %d %s" % [title, int(round(v)), unit]
	put.call(value)
	s.drag_started.connect(_remember)
	s.value_changed.connect(func(v: float) -> void:
		put.call(v)
		apply.call(v)
		_redraw())
	s.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_soft_commit()
		else:
			_undo.pop_back())


## Written down without rebuilding the panel (a slider is still under the finger).
func _soft_commit() -> void:
	changed.emit(data.duplicate(true))
	_stale = true
	_stale_t = 0.0
	_version += 1
	_undo_btn.disabled = _undo.is_empty()


func _name_field(current: String, placeholder: String, apply: Callable) -> void:
	var e := LineEdit.new()
	e.max_length = CustomCity.NAME_MAX
	e.text = current
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(320, 40)
	e.add_theme_font_size_override("font_size", 17)
	e.select_all_on_focus = true
	var was := {"name": current} # a lambda keeps its own copy of a captured value: the box is shared
	var save := func() -> void:
		var n := CustomCity.clean_name(e.text)
		if n != String(was.name):
			_remember()
			apply.call(n)
			was.name = n
			_soft_commit()
			_redraw()
	e.text_submitted.connect(func(_s: String) -> void: e.release_focus())
	e.focus_exited.connect(save)
	_box.add_child(e)


func _build_selected() -> void:
	var type := String(_sel.type)
	var it = _list(type)[int(_sel.i)]
	match type:
		"district":
			_box.add_child(_note(GS.t("РАЙОН"), UiKit.AMBER, 15))
			_name_field(String(it[0]), GS.t("Название района"), func(n: String) -> void: it[0] = n if n != "" else GS.t("Район"))
			_pick_grid(CustomCity.DISTRICT_KINDS, String(it[4]), func(k: String) -> void:
				_remember()
				it[4] = k
				_kind = k
				_commit())
			_slider(GS.t("Радиус"), 300.0, 2500.0, 50.0, float(it[5]), GS.t("м"), func(v: float) -> void: it[5] = v)
			_slider(GS.t("Поворот улиц"), -45.0, 45.0, 1.0, float(it[3]), "°", func(v: float) -> void: it[3] = v)
		"object":
			_box.add_child(_note(GS.t("ОБЪЕКТ · %s") % GS.t(CustomCity.object_name(String(it.k))), UiKit.AMBER, 15))
			_name_field(String(it.n), GS.t(CustomCity.object_name(String(it.k))), func(n: String) -> void: it.n = n)
			_slider(GS.t("Поворот"), 0.0, 355.0, 5.0, fposmod(float(it.r), 360.0), "°", func(v: float) -> void: it.r = v)
		"lake", "forest":
			_box.add_child(_note(GS.t("ОЗЕРО") if type == "lake" else GS.t("ЛЕС"), UiKit.AMBER, 15))
			var lo := 60.0 if type == "lake" else 100.0
			var hi := 3000.0 if type == "lake" else 5000.0
			_slider(GS.t("Ширина"), lo, hi, 20.0, float(it[2]), GS.t("м"), func(v: float) -> void: it[2] = v)
			_slider(GS.t("Высота"), lo, hi, 20.0, float(it[3]), GS.t("м"), func(v: float) -> void: it[3] = v)
			_slider(GS.t("Поворот"), 0.0, 175.0, 5.0, fposmod(float(it[4]), 180.0), "°", func(v: float) -> void: it[4] = v)
		_:
			var titles := {"river": GS.t("РЕКА"), "road": GS.t("ДОРОГА"), "rail": GS.t("ЖЕЛЕЗНАЯ ДОРОГА")}
			_box.add_child(_note(String(titles[type]), UiKit.AMBER, 15))
			_name_field(String(it.n), GS.t("Название"), func(n: String) -> void: it.n = n)
			var pts: Array = it.p
			if type == "river":
				_slider(GS.t("Ширина"), 40.0, 1200.0, 20.0, float(pts[0][2]) * 2.0, GS.t("м"), func(v: float) -> void:
					for q in pts:
						q[2] = v * 0.5)
			if int(_sel.pt) >= 0:
				_box.add_child(_note(GS.t("Выбрана точка %d из %d: её можно тащить.") % [int(_sel.pt) + 1, pts.size()], Color(0.6, 0.9, 0.78)))
				var del_pt := UiKit.button(GS.t("Убрать эту точку"), func() -> void:
					_remember()
					pts.remove_at(int(_sel.pt))
					_sel.pt = -1
					_commit(), 326, 16)
				del_pt.disabled = pts.size() <= 2
				_box.add_child(del_pt)
			else:
				_box.add_child(_note(GS.t("Выбрана вся линия: тащите её целиком или коснитесь точки."), Color(0.6, 0.9, 0.78)))
	_box.add_child(UiKit.button(GS.t("🗑 Удалить"), _delete_selected, 326, 16))


func _delete_selected() -> void:
	if not _sel_valid():
		return
	_remember()
	_list(String(_sel.type)).remove_at(int(_sel.i))
	_sel = {}
	_commit()


func _ask_clear() -> void:
	var m := UiKit.modal(self, Vector2(480, 0))
	_confirm = m[0]
	var box := _confirm
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Очистить город?"), 30, UiKit.RED))
	var t := UiKit.label(GS.t("Можно начать с пустого поля или вернуть готовый образец. Отменить можно кнопкой «Отменить»."), 16, Color(0.9, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 0)
	v.add_child(t)
	var replace := func(d: Dictionary) -> void:
		_remember()
		data = CustomCity.clean(d)
		_sel = {}
		_draft = []
		box.queue_free()
		_commit()
		_fit()
	v.add_child(UiKit.button(GS.t("Пустое поле"), func() -> void: replace.call(CustomCity.blank(String(data.name), float(data.size)))))
	v.add_child(UiKit.button(GS.t("Готовый образец"), func() -> void: replace.call(CustomCity.sample(String(data.name), flip))))
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: box.queue_free()))


func _done() -> void:
	_finish_line()
	_save_name()
	done.emit(CustomCity.clean(data))


# --- Drawn over the plan ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	if view != "3d":
		if not _draft.is_empty() or not _sel.is_empty():
			_plan.queue_redraw()
		return
	# typing a name must not fly the camera away on W, A, S, D
	_rig.keys = not (get_viewport().gui_get_focus_owner() is LineEdit)
	_giz.update(data, _sel, _draft, _rig.dist, _version)
	_build_btn.disabled = not _stale or _building
	_build_btn.add_theme_color_override("font_color", UiKit.AMBER if _stale else Color(0.7, 1.0, 0.85))
	if _stale and not _building:
		_stale_t += delta
		# a computer builds by itself once the hand has rested; nothing half-drawn or half-dragged
		var busy: bool = not _drag.is_empty() or not _draft.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or (_confirm != null and is_instance_valid(_confirm))
		if _auto and not busy and _stale_t >= AUTO_BUILD:
			_build3d()


func _draw_overlay(plan: CityPlan) -> void:
	var white := Color(1, 1, 1, 0.95)
	# the line being drawn
	if not _draft.is_empty():
		var pl := PackedVector2Array()
		for p in _draft:
			pl.append(plan.at(Vector2(float(p[0]), float(p[1]))))
		if pl.size() >= 2:
			plan.draw_polyline(pl, Color(1.0, 0.9, 0.4, 0.9), 2.5)
		for q in pl:
			plan.draw_circle(q, 5.0, Color(1.0, 0.9, 0.4))
		plan.draw_arc(pl[pl.size() - 1], 9.0 + 2.0 * sin(_t * 6.0), 0, TAU, 20, white, 1.5)
	if not _sel_valid():
		return
	var type := String(_sel.type)
	var it = _list(type)[int(_sel.i)]
	var pulse := 2.0 * sin(_t * 5.0)
	match type:
		"district":
			plan.draw_arc(plan.at(Vector2(float(it[1]), float(it[2]))), float(it[5]) * 1.15 * plan.zoom + 3.0, 0, TAU, 48, white, 2.0)
		"object":
			var p := plan.at(Vector2(float(it.x), float(it.z)))
			plan.draw_arc(p, 16.0 + pulse, 0, TAU, 24, white, 2.0)
			# which way it faces, and the ground it keeps free of houses
			var a := deg_to_rad(float(it.r))
			plan.draw_line(p, p + Vector2(sin(a), -cos(a)) * 30.0, white, 2.0)
			plan.draw_arc(p, CustomCity.object_radius(String(it.k)) * plan.zoom, 0, TAU, 40, Color(1, 1, 1, 0.35), 1.0)
		"lake", "forest":
			var pts := plan._ellipse(it, 40)
			pts.append(pts[0])
			plan.draw_polyline(pts, white, 2.0)
		_:
			var pts: Array = it.p
			var pl := PackedVector2Array()
			for q in pts:
				pl.append(plan.at(Vector2(float(q[0]), float(q[1]))))
			plan.draw_polyline(pl, white, 1.5)
			for k in pl.size():
				var on := k == int(_sel.pt)
				plan.draw_rect(Rect2(pl[k] - Vector2.ONE * (6.0 if on else 4.0), Vector2.ONE * (12.0 if on else 8.0)), Color(1.0, 0.9, 0.4) if on else white)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey)
		if k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _confirm != null and is_instance_valid(_confirm):
				_confirm.queue_free()
			elif not _draft.is_empty():
				_draft = []
				_refresh()
			elif not _sel.is_empty():
				_sel = {}
				_refresh()
			else:
				_done()
		elif k.keycode == KEY_Z and k.ctrl_pressed:
			get_viewport().set_input_as_handled()
			undo()
		elif k.keycode == KEY_DELETE and _sel_valid():
			get_viewport().set_input_as_handled()
			_delete_selected()
		elif (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and _draft.size() >= 2:
			get_viewport().set_input_as_handled()
			_finish_line()
			_refresh()
