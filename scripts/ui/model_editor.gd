extends RefCounted
## The 3D model editor of the mod workshop (scripts/ui/mod_workshop.gd) for «.uadmodel» files
## (format: scripts/mods/model3d.gd). `view` goes where the code is: the model on a turntable — a
## drag turns the camera, the wheel / a pinch / ± zoom, a tap picks a part — with a toolbar to add
## parts and to start from one of the game's own models; `panel` goes into the right column: the
## parts list, the chosen part's shape, group (body / turret / gun / propeller), colour, material,
## position, rotation and size, and the pivots the turret turns and the gun tilts around.

signal changed

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Model3D = preload("res://scripts/mods/model3d.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

const SHAPE_NAMES := {"box": "Коробка", "cylinder": "Цилиндр", "sphere": "Шар", "prism": "Призма", "mesh": "Своя форма"}
const GROUP_NAMES := {"body": "Корпус", "turret": "Башня", "gun": "Ствол / пусковая", "spin": "Винт / радар"}
const MAT_NAMES := {"paint": "Краска (камуфляж)", "solid": "Матовый", "metal": "Металл", "glass": "Стекло", "glow": "Свечение"}
const PIVOT_NAMES := {"turret": "Ось башни", "gun": "Ось ствола (от башни)", "muzzle": "Дуло (от ствола)", "spin": "Ось винта"}

var model := {}
var view: Control
var panel: Control
var selected := -1

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _hl: MeshInstance3D
var _markers := {}
var _yaw := 0.7
var _pitch := 0.35
var _dist := 14.0
var _target := Vector3(0, 1.5, 0)
var _drag_from := Vector2.ZERO
var _dragging := false
var _moved := 0.0
var _touches := {}
var _pinch0 := 0.0
var _list: ItemList
var _props: VBoxContainer
var _fields := {}
var _undo: Array = []
var _redo: Array = []
var _quiet := false
var _kind_btn: Button


func _init() -> void:
	_build_view()
	_build_panel()


## Opens a model (its JSON text); a broken or empty file starts a new one.
func load_text(text: String, kind := "weapon") -> void:
	var j := JSON.new()
	var md := {}
	if text.strip_edges() != "" and j.parse(text) == OK:
		md = Model3D.sanitize(j.data)
	if md.is_empty() or md.has("error"):
		md = starter(kind)
	model = md
	selected = -1
	_undo.clear()
	_redo.clear()
	_frame_camera()
	_rebuild()


func to_text() -> String:
	return JSON.stringify(model, "\t")


## A first model for a new file: a body and, for a system, a turret with a barrel.
static func starter(kind: String) -> Dictionary:
	var parts := []
	if kind == "enemy":
		parts = [
			{"shape": "cylinder", "group": "body", "pos": [0, 0, 0], "rot": [90, 0, 0], "size": [0.6, 3.2, 0.6], "taper": [1.0, 0.6], "color": "#5a5f63", "mat": "paint"},
			{"shape": "prism", "group": "body", "pos": [0, 0, 0.3], "rot": [-90, 0, 0], "size": [2.6, 1.6, 0.08], "apex": 0.5, "color": "#4d5256", "mat": "paint"},
			{"shape": "box", "group": "spin", "pos": [0, 0, 0], "rot": [0, 0, 0], "size": [1.2, 0.08, 0.05], "color": "#202020", "mat": "solid"},
		]
		return Model3D.sanitize({"kind": "enemy", "pivots": {"spin": [0, 0, 1.65]}, "parts": parts})
	parts = [
		{"shape": "box", "group": "body", "pos": [0, 0.9, 0], "rot": [0, 0, 0], "size": [2.6, 1.0, 5.2], "color": "#4f5a35", "mat": "paint"},
		{"shape": "cylinder", "group": "turret", "pos": [0, 0.25, 0], "rot": [0, 0, 0], "size": [1.6, 0.5, 1.6], "color": "#4f5a35", "mat": "paint"},
		{"shape": "box", "group": "gun", "pos": [0, 0, -0.6], "rot": [0, 0, 0], "size": [0.8, 0.6, 2.0], "color": "#3d4428", "mat": "paint"},
	]
	return Model3D.sanitize({"kind": "weapon", "pivots": {"turret": [0, 1.4, 0], "gun": [0, 0.7, 0], "muzzle": [0, 0, -1.8]}, "parts": parts})


# --- the viewport ----------------------------------------------------------------------------------
func _build_view() -> void:
	view = UiKit.vbox(4)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := UiKit.hbox(4)
	view.add_child(bar)
	for spec in [["▭", "box"], ["◯", "cylinder"], ["▲", "cone"], ["●", "sphere"], ["◣", "prism"]]:
		var b := _tool_btn(String(spec[0]), GS.t("Добавить: %s") % GS.t(SHAPE_NAMES.get(spec[1], "Конус")))
		b.pressed.connect(add_part.bind(String(spec[1])))
		bar.add_child(b)
	bar.add_child(_tool_btn("↶", GS.t("Отменить")))
	bar.get_child(bar.get_child_count() - 1).pressed.connect(undo)
	bar.add_child(_tool_btn("↷", GS.t("Вернуть")))
	bar.get_child(bar.get_child_count() - 1).pressed.connect(redo)
	var lib := UiKit.button(GS.t("Наша модель…"), _ask_builtin, 150, 15)
	lib.custom_minimum_size = Vector2(150, 40)
	bar.add_child(lib)
	_kind_btn = UiKit.button("", _toggle_kind, 130, 15)
	_kind_btn.custom_minimum_size = Vector2(130, 40)
	bar.add_child(_kind_btn)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(300, 240)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_view_input)
	view.add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	box.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.09, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.6)
	e.ambient_light_energy = 0.9
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	_vp.add_child(_grid())
	# a man beside it, for the scale
	var man := MeshInstance3D.new()
	man.mesh = Meshes.person_mesh()
	man.material_override = Meshes.Fx.solid(Color(0.62, 0.64, 0.6), 0.9)
	man.position = Vector3(3.5, 0, 1.5)
	_vp.add_child(man)
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.far = 600
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	_hl = MeshInstance3D.new()
	_hl.mesh = BoxMesh.new()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(0.25, 1.0, 0.65, 0.28)
	hm.no_depth_test = true
	hm.render_priority = 10
	_hl.material_override = hm
	_hl.visible = false
	_vp.add_child(_hl)
	for k in ["turret", "gun", "muzzle", "spin"]:
		var mk := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		mk.mesh = sm
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.no_depth_test = true
		mm.albedo_color = {"turret": Color(1, 0.8, 0.2), "gun": Color(0.3, 0.85, 1), "muzzle": Color(1, 0.3, 0.3), "spin": Color(1, 0.4, 1)}[k]
		mk.material_override = mm
		_vp.add_child(mk)
		_markers[k] = mk
	var zoom := UiKit.hbox(4)
	zoom.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	zoom.offset_left = -100
	zoom.offset_top = 6
	zoom.offset_right = -6
	box.add_child(zoom)
	for z in [["−", 1.25], ["+", 0.8]]:
		var zb := _tool_btn(String(z[0]), "")
		var f := float(z[1])
		zb.pressed.connect(func() -> void:
			_dist = clampf(_dist * f, 2.0, 120.0)
			_place_camera())
		zoom.add_child(zb)
	_place_camera()


func _tool_btn(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 40)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _grid() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-10, 11):
		var a := 0.5 if i % 5 == 0 else 0.18
		im.surface_set_color(Color(0.3, 1.0, 0.7, a))
		im.surface_add_vertex(Vector3(i, 0, -10))
		im.surface_add_vertex(Vector3(i, 0, 10))
		im.surface_set_color(Color(0.3, 1.0, 0.7, a))
		im.surface_add_vertex(Vector3(-10, 0, i))
		im.surface_add_vertex(Vector3(10, 0, i))
	# the forward direction: the nose / the barrel point this way (-Z)
	im.surface_set_color(Color(1.0, 0.4, 0.3, 0.9))
	im.surface_add_vertex(Vector3(0, 0.01, 0))
	im.surface_add_vertex(Vector3(0, 0.01, -10))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	return mi


func _place_camera() -> void:
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


func _frame_camera() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in model.get("parts", []):
		var c := _part_xform(p).origin
		var s := Vector3(float(p.size[0]), float(p.size[1]), float(p.size[2])) * 0.5
		lo = lo.min(c - s)
		hi = hi.max(c + s)
	if lo.x == INF:
		lo = Vector3(-1, 0, -1)
		hi = Vector3(1, 2, 1)
	_target = (lo + hi) * 0.5
	_dist = clampf((hi - lo).length() * 1.4, 3.0, 120.0)
	_place_camera()


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() == 2:
			var ps: Array = _touches.values()
			_pinch0 = (ps[0] as Vector2).distance_to(ps[1])
		return
	if ev is InputEventScreenDrag and _touches.size() >= 2:
		var d := ev as InputEventScreenDrag
		_touches[d.index] = d.position
		var ps: Array = _touches.values()
		var now := (ps[0] as Vector2).distance_to(ps[1])
		if _pinch0 > 1.0 and now > 1.0:
			_dist = clampf(_dist * _pinch0 / now, 2.0, 120.0)
			_pinch0 = now
			_place_camera()
		_moved = 99.0
		return
	if ev is InputEventMagnifyGesture:
		_dist = clampf(_dist / (ev as InputEventMagnifyGesture).factor, 2.0, 120.0)
		_place_camera()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist * 0.9, 2.0, 120.0)
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist * 1.1, 2.0, 120.0)
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_from = mb.position
				_moved = 0.0
			else:
				_dragging = false
				if _moved < 8.0 and _touches.size() < 2:
					_pick(mb.position)
	elif ev is InputEventMouseMotion and _dragging and _touches.size() < 2:
		var mm := ev as InputEventMouseMotion
		_moved += mm.relative.length()
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch + mm.relative.y * 0.006, -0.2, 1.45)
		_place_camera()


## The part under a tap: the nearest one whose box the ray goes through.
func _pick(at: Vector2) -> void:
	var from := _cam.project_ray_origin(at)
	var dir := _cam.project_ray_normal(at)
	var best := -1
	var best_t := INF
	var parts: Array = model.get("parts", [])
	for i in parts.size():
		var p: Dictionary = parts[i]
		var x := _part_xform(p)
		var inv := x.affine_inverse()
		var o := inv * from
		var d := inv.basis * dir
		var h := Vector3(float(p.size[0]), float(p.size[1]), float(p.size[2])) * 0.5
		var t := _ray_box(o, d, h)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = i
	select(best)


static func _ray_box(o: Vector3, d: Vector3, h: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for a in 3:
		if absf(d[a]) < 1e-8:
			if absf(o[a]) > h[a]:
				return -1.0
			continue
		var t1 := (-h[a] - o[a]) / d[a]
		var t2 := (h[a] - o[a]) / d[a]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)


## Where a part is in the model: its own place on top of its group's pivots.
func _part_xform(p: Dictionary) -> Transform3D:
	var pv: Dictionary = model.get("pivots", Model3D.DEFAULT_PIVOTS)
	var base := Vector3.ZERO
	match String(p.group):
		"turret":
			base = _v(pv.turret)
		"gun":
			base = _v(pv.turret) + _v(pv.gun)
		"spin":
			base = _v(pv.spin)
	var b := Basis.from_euler(_v(p.rot) * (PI / 180.0))
	return Transform3D(b, base + _v(p.pos))


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _rebuild() -> void:
	for c in _holder.get_children():
		c.queue_free()
	if model.is_empty():
		return
	_holder.add_child(Model3D.build(model))
	var weapon := String(model.get("kind", "weapon")) == "weapon"
	var pv: Dictionary = model.pivots
	_markers.turret.position = _v(pv.turret)
	_markers.gun.position = _v(pv.turret) + _v(pv.gun)
	_markers.muzzle.position = _v(pv.turret) + _v(pv.gun) + _v(pv.muzzle)
	_markers.spin.position = _v(pv.spin)
	for k in ["turret", "gun", "muzzle"]:
		_markers[k].visible = weapon
	var has_spin := false
	for p in model.parts:
		if String(p.group) == "spin":
			has_spin = true
	_markers.spin.visible = has_spin
	_kind_btn.text = GS.t("Это: ПВО") if weapon else GS.t("Это: угроза")
	_refresh_list()
	_show_selection()


# --- editing -------------------------------------------------------------------------------------
func _snapshot() -> void:
	_undo.append(JSON.stringify(model))
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()


func _commit() -> void:
	_rebuild()
	changed.emit()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(JSON.stringify(model))
	model = Model3D.sanitize(JSON.parse_string(_undo.pop_back()))
	selected = mini(selected, model.parts.size() - 1)
	_commit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(JSON.stringify(model))
	model = Model3D.sanitize(JSON.parse_string(_redo.pop_back()))
	selected = mini(selected, model.parts.size() - 1)
	_commit()


func add_part(shape: String) -> void:
	if model.parts.size() >= Model3D.MAX_PARTS:
		return
	SFX.play("click", -10.0)
	_snapshot()
	var p := {"shape": "cylinder" if shape == "cone" else shape, "group": "body", "pos": [_target.x, _target.y, _target.z], "rot": [0, 0, 0],
		"size": [1.0, 1.0, 1.0], "color": "#6b7350", "mat": "paint"}
	if shape == "cone":
		p["taper"] = [1.0, 0.0]
	if shape == "cylinder":
		p["taper"] = [1.0, 1.0]
	if shape == "prism":
		p["apex"] = 0.5
	if selected >= 0:
		# beside the chosen part, in its group
		var s: Dictionary = model.parts[selected]
		p.group = s.group
		p.pos = [float(s.pos[0]) + float(s.size[0]) * 0.5 + 0.6, float(s.pos[1]), float(s.pos[2])]
	model.parts.append(Model3D.sanitize({"parts": [p]}).parts[0])
	selected = model.parts.size() - 1
	_commit()


func select(i: int) -> void:
	selected = i if i >= 0 and i < model.get("parts", []).size() else -1
	if _list != null:
		if selected >= 0:
			_list.select(selected)
			_list.ensure_current_is_visible()
		else:
			_list.deselect_all()
	_show_selection()


func _show_selection() -> void:
	if selected < 0 or selected >= model.get("parts", []).size():
		_hl.visible = false
		_fill_props()
		return
	var p: Dictionary = model.parts[selected]
	var x := _part_xform(p)
	(_hl.mesh as BoxMesh).size = Vector3(float(p.size[0]), float(p.size[1]), float(p.size[2])) * 1.04 + Vector3.ONE * 0.03
	_hl.transform = x
	_hl.visible = true
	_fill_props()


func _toggle_kind() -> void:
	_snapshot()
	model.kind = "enemy" if String(model.kind) == "weapon" else "weapon"
	_commit()


func _ask_builtin() -> void:
	var weapon := String(model.get("kind", "weapon")) == "weapon"
	var m := UiKit.modal(view, Vector2(520, 0))
	var root: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.glow_label(GS.t("Наша модель — основа для своей"), 26, UiKit.NEON))
	var hint := UiKit.label(GS.t("Модель заменит текущую; её детали можно менять, двигать и красить."), 14, Color(0.65, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(480, 0)
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := UiKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var ids: Array = GS.BASE_WEAPON_ORDER if weapon else GS.BASE_ENEMIES.keys()
	for id in ids:
		var nm := GS.t(String((GS.BASE_WEAPONS if weapon else GS.BASE_ENEMIES)[id].name))
		var b := UiKit.button(nm, func() -> void:
			root.queue_free()
			use_builtin(String(id), weapon), 460, 16)
		b.custom_minimum_size = Vector2(460, 40)
		list.add_child(b)
	v.add_child(UiKit.button(GS.t("Отмена"), func() -> void: root.queue_free()))


## One of the game's own models, turned into editable parts.
func use_builtin(id: String, weapon: bool) -> void:
	var n: Node3D = Meshes.weapon_model(id) if weapon else Meshes.enemy_model(id)
	var md := Model3D.sanitize(Model3D.from_node(n, "weapon" if weapon else "enemy", id))
	n.free()
	if md.has("error"):
		return
	_snapshot()
	model = md
	selected = -1
	_frame_camera()
	_commit()


# --- the panel -----------------------------------------------------------------------------------
func _build_panel() -> void:
	panel = UiKit.vbox(4)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(UiKit.label(GS.t("Детали — нажмите в окне или в списке"), 14, UiKit.AMBER))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(270, 150)
	_list.add_theme_font_size_override("font_size", 14)
	_list.item_selected.connect(func(i: int) -> void: select(i))
	panel.add_child(_list)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_props = UiKit.vbox(4)
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_props)


func _refresh_list() -> void:
	_list.clear()
	for p in model.get("parts", []):
		_list.add_item("%s · %s" % [GS.t(SHAPE_NAMES[p.shape]) if not (p.shape == "cylinder" and float(p.get("taper", [1, 1])[1]) == 0.0) else GS.t("Конус"), GS.t(GROUP_NAMES[p.group])])
	if selected >= 0 and selected < _list.item_count:
		_list.select(selected)


func _fill_props() -> void:
	_quiet = true
	for c in _props.get_children():
		c.queue_free()
	_fields.clear()
	if selected >= 0 and selected < model.get("parts", []).size():
		var p: Dictionary = model.parts[selected]
		_props.add_child(_option(GS.t("Форма"), SHAPE_NAMES, String(p.shape), func(v: String) -> void: _set_field(["shape"], v)))
		_props.add_child(_option(GS.t("Часть"), GROUP_NAMES, String(p.group), func(v: String) -> void: _set_field(["group"], v)))
		var crow := UiKit.hbox(6)
		crow.add_child(UiKit.label(GS.t("Цвет"), 14, Color(0.7, 0.9, 0.8)))
		var cp := ColorPickerButton.new()
		cp.color = Color.html(String(p.color))
		cp.custom_minimum_size = Vector2(80, 36)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.color_changed.connect(func(c: Color) -> void: _set_field(["color"], "#" + c.to_html(false), false))
		cp.popup_closed.connect(func() -> void: changed.emit())
		crow.add_child(cp)
		_props.add_child(crow)
		_props.add_child(_option(GS.t("Материал"), MAT_NAMES, String(p.mat), func(v: String) -> void: _set_field(["mat"], v)))
		_props.add_child(_vec_row(GS.t("Место, м"), p.pos, "pos", 0.05, -80.0, 80.0))
		_props.add_child(_vec_row(GS.t("Поворот, °"), p.rot, "rot", 5.0, -360.0, 360.0))
		_props.add_child(_vec_row(GS.t("Размер, м"), p.size, "size", 0.05, 0.0, 80.0))
		if String(p.shape) == "cylinder":
			var t: Array = p.get("taper", [1.0, 1.0])
			_props.add_child(_num_row(GS.t("Низ (доля)"), float(t[0]), 0.05, 0.0, 1.0, func(v: float) -> void: _set_field(["taper", 0], v)))
			_props.add_child(_num_row(GS.t("Верх (доля)"), float(t[1]), 0.05, 0.0, 1.0, func(v: float) -> void: _set_field(["taper", 1], v)))
		if String(p.shape) == "prism":
			_props.add_child(_num_row(GS.t("Вершина"), float(p.get("apex", 0.5)), 0.05, 0.0, 1.0, func(v: float) -> void: _set_field(["apex"], v)))
		var act := UiKit.hbox(4)
		for spec in [[GS.t("Копия"), _duplicate.bind(false)], [GS.t("Зеркально"), _duplicate.bind(true)], [GS.t("Удалить"), _delete]]:
			var b := UiKit.button(spec[0], spec[1], 86, 14)
			b.custom_minimum_size = Vector2(86, 38)
			act.add_child(b)
		_props.add_child(act)
	else:
		var l := UiKit.label(GS.t("Ничего не выбрано. Добавьте деталь кнопками над окном или возьмите нашу модель за основу."), 13, Color(0.6, 0.82, 0.74))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(260, 0)
		_props.add_child(l)
	_props.add_child(UiKit.label(GS.t("Оси"), 15, UiKit.CYAN))
	var weapon := String(model.get("kind", "weapon")) == "weapon"
	for k in (["turret", "gun", "muzzle", "spin"] if weapon else ["spin"]):
		_props.add_child(_vec_row(GS.t(PIVOT_NAMES[k]), model.get("pivots", {}).get(k, Model3D.DEFAULT_PIVOTS[k]), "pivot:" + k, 0.05, -80.0, 80.0))
	_quiet = false


func _option(title: String, names: Dictionary, value: String, cb: Callable) -> Control:
	var row := UiKit.hbox(6)
	var l := UiKit.label(title, 14, Color(0.7, 0.9, 0.8))
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 14)
	var keys: Array = names.keys()
	for k in keys:
		o.add_item(GS.t(String(names[k])))
	o.selected = maxi(keys.find(value), 0)
	o.item_selected.connect(func(i: int) -> void: cb.call(String(keys[i])))
	row.add_child(o)
	return row


func _vec_row(title: String, v: Array, key: String, step: float, lo: float, hi: float) -> Control:
	var box := UiKit.vbox(2)
	box.add_child(UiKit.label(title, 13, Color(0.6, 0.82, 0.74)))
	var row := UiKit.hbox(3)
	box.add_child(row)
	for a in 3:
		var s := SpinBox.new()
		s.min_value = lo
		s.max_value = hi
		s.step = step
		s.allow_greater = false
		s.custom_arrow_step = step
		s.value = float(v[a])
		s.prefix = ["X", "Y", "Z"][a]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(84, 34)
		s.get_line_edit().add_theme_font_size_override("font_size", 13)
		var axis := a
		s.value_changed.connect(func(x: float) -> void:
			if key.begins_with("pivot:"):
				_set_pivot(key.trim_prefix("pivot:"), axis, x)
			else:
				_set_field([key, axis], x))
		row.add_child(s)
	return box


func _num_row(title: String, v: float, step: float, lo: float, hi: float, cb: Callable) -> Control:
	var row := UiKit.hbox(6)
	var l := UiKit.label(title, 13, Color(0.6, 0.82, 0.74))
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void: cb.call(x))
	row.add_child(s)
	return row


## Changes a value of the chosen part: path = ["key"] or ["key", index].
func _set_field(path: Array, v, refill := true) -> void:
	if _quiet or selected < 0:
		return
	_snapshot()
	var p: Dictionary = model.parts[selected]
	if path.size() == 1:
		p[path[0]] = v
		if path[0] == "shape":
			if v == "cylinder" and not p.has("taper"):
				p["taper"] = [1.0, 1.0]
			if v == "prism" and not p.has("apex"):
				p["apex"] = 0.5
			if v == "mesh" and not p.has("tris"):
				p.shape = "box"
	else:
		var arr: Array = p[path[0]]
		arr[path[1]] = v
	model.parts[selected] = Model3D.sanitize({"parts": [p]}).parts[0]
	_rebuild_keep(refill and path[0] in ["shape", "group"])
	changed.emit()


func _set_pivot(k: String, axis: int, v: float) -> void:
	if _quiet:
		return
	_snapshot()
	var pv: Dictionary = model.pivots
	var arr: Array = pv[k]
	arr[axis] = v
	_rebuild_keep(false)
	changed.emit()


## Builds the model again without rebuilding the panel the finger is on (unless the panel's own
## shape changes: another shape has other fields).
func _rebuild_keep(refill: bool) -> void:
	for c in _holder.get_children():
		c.queue_free()
	_holder.add_child(Model3D.build(model))
	var pv: Dictionary = model.pivots
	_markers.turret.position = _v(pv.turret)
	_markers.gun.position = _v(pv.turret) + _v(pv.gun)
	_markers.muzzle.position = _v(pv.turret) + _v(pv.gun) + _v(pv.muzzle)
	_markers.spin.position = _v(pv.spin)
	if refill:
		_refresh_list()
		_show_selection()
	elif selected >= 0:
		var p: Dictionary = model.parts[selected]
		(_hl.mesh as BoxMesh).size = Vector3(float(p.size[0]), float(p.size[1]), float(p.size[2])) * 1.04 + Vector3.ONE * 0.03
		_hl.transform = _part_xform(p)
		_list.set_item_text(selected, "%s · %s" % [GS.t(SHAPE_NAMES[p.shape]), GS.t(GROUP_NAMES[p.group])])


func _duplicate(mirror: bool) -> void:
	if selected < 0 or model.parts.size() >= Model3D.MAX_PARTS:
		return
	_snapshot()
	var p: Dictionary = (model.parts[selected] as Dictionary).duplicate(true)
	if mirror:
		# the other side: X turned over, and the turns that go with it
		p.pos[0] = -float(p.pos[0])
		p.rot[1] = -float(p.rot[1])
		p.rot[2] = -float(p.rot[2])
		if String(p.shape) == "prism":
			p.apex = 1.0 - float(p.get("apex", 0.5))
		if String(p.shape) == "mesh":
			# X turned over, and each triangle's order too (or it would face inwards)
			var t: Array = p.tris
			for i in range(0, t.size() - 8, 9):
				for k in 3:
					t[i + k * 3] = -float(t[i + k * 3])
				for k in 3:
					var tmp = t[i + 3 + k]
					t[i + 3 + k] = t[i + 6 + k]
					t[i + 6 + k] = tmp
	else:
		p.pos[0] = float(p.pos[0]) + 0.3
	model.parts.append(p)
	selected = model.parts.size() - 1
	_commit()


func _delete() -> void:
	if selected < 0:
		return
	_snapshot()
	model.parts.remove_at(selected)
	selected = -1
	_commit()
