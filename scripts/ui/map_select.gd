extends Control
## Base placement on the 3D city map. The location type (forest / riverside / city / field)
## changes gameplay: camouflage, gun line-of-sight, debris risk and rewards.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Fx = preload("res://scripts/core/fx.gd")
const Meshes = preload("res://scripts/core/meshes.gd")

var main
var map
var cam: Camera3D
var focus := Vector3(60, 0, 0)
var height := 1500.0
var _t_height := 1500.0

var chosen := Vector3.ZERO
var chosen_loc := -1
var _hover_ring: MeshInstance3D
var _marker: Node3D
var _hover_lbl: Label
var _sel_title: Label
var _sel_desc: Label
var _start: Button
var _press := Vector2.ZERO
var _left := false
var _moved := false
var _t := 0.0
## Multiplayer guest: markers of the other players' bases, code -> Node3D.
var _friends := {}
var _friends_t := 0.0


func _ready() -> void:
	map = main.map
	cam = main.cam
	focus = map.city.map_focus
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	map.set_fog_scale(0.0)
	map.set_night(0.3)
	_build_ui()
	_hover_ring = MeshInstance3D.new()
	_hover_ring.mesh = Fx.ring_mesh(40.0, 5.0)
	_hover_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.add_child(_hover_ring)
	_marker = Node3D.new()
	Meshes.part(_marker, Fx.ring_mesh(45.0, 7.0), Fx.ghost(Color(0.2, 1.0, 0.6, 0.9), 2.0), Vector3(0, 2, 0))
	var beam := Meshes.cyl(_marker, 4.0, 4.0, 400.0, Vector3(0, 200, 0), Fx.ghost(Color(0.2, 1.0, 0.6, 0.25), 1.5), Vector3.ZERO, 12)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	map.add_child(_marker)


func _exit_tree() -> void:
	map.set_fog_scale(1.0)
	if is_instance_valid(_hover_ring):
		_hover_ring.queue_free()
	if is_instance_valid(_marker):
		_marker.queue_free()
	for c in _friends:
		if is_instance_valid(_friends[c]):
			(_friends[c] as Node3D).queue_free()


func _build_ui() -> void:
	var guest := bool(main.pending_world.get("guest", false))
	var head := GS.t("ПОЗИЦИЯ ПВО · %s") % String(main.pending_world.get("name", GS.ctext("title"))).to_upper()
	if guest:
		head = GS.t("В ГОСТЯХ У %s · ПОЗИЦИЯ ПВО") % String(main.pending_world.get("host", "?")).to_upper()
	var title := UiKit.glow_label(head, 30, UiKit.CYAN if guest else UiKit.NEON)
	title.anchor_right = 1.0
	title.offset_right = -400
	title.offset_top = 14
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var hint := UiKit.label(GS.t("ЛКМ — разместить базу · перетаскивание / WASD — сдвиг карты · колесо — масштаб"), 15, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	hint.anchor_right = 1.0
	hint.offset_right = -400
	hint.offset_top = 58
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_hover_lbl = UiKit.label("", 18, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_hover_lbl.anchor_top = 1.0
	_hover_lbl.anchor_bottom = 1.0
	_hover_lbl.anchor_right = 1.0
	_hover_lbl.offset_right = -400
	_hover_lbl.offset_top = -48
	_hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_lbl)

	var p := UiKit.panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -388
	p.offset_right = -10
	p.offset_top = 10
	p.offset_bottom = -10
	add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UiKit.label(GS.t("ТИПЫ МЕСТНОСТИ"), 17, UiKit.AMBER))
	for loc in [GS.Loc.FOREST, GS.Loc.RIVER, GS.Loc.CITY, GS.Loc.FIELD]:
		var def: Dictionary = GS.LOCATIONS[loc]
		var h := UiKit.hbox(8)
		var sw := ColorRect.new()
		sw.color = def.color
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(sw)
		var col := UiKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(GS.loc_name(loc), 17, def.color))
		var d := UiKit.label(GS.loc_desc(loc), 12, Color(0.65, 0.85, 0.78))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
		h.add_child(col)
		v.add_child(h)
	var sep := HSeparator.new()
	v.add_child(sep)
	v.add_child(UiKit.label(GS.t("ВЫБРАННАЯ ПОЗИЦИЯ"), 17, UiKit.AMBER))
	_sel_title = UiKit.label(GS.t("— не выбрана —"), 20)
	v.add_child(_sel_title)
	_sel_desc = UiKit.label(GS.t("Кликните по карте, чтобы разместить базу."), 13, Color(0.65, 0.85, 0.78))
	_sel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sel_desc)
	_start = UiKit.button(GS.t("НАЧАТЬ ОБОРОНУ ▶"), _on_start, 340, 22)
	_start.disabled = true
	v.add_child(_start)
	if guest:
		v.add_child(UiKit.button(GS.t("Отключиться"), func() -> void: main.show_worlds(), 340, 18))
	else:
		v.add_child(UiKit.button(GS.t("Назад"), func() -> void: main.show_create_world(), 340, 18))


func _ground_point(screen: Vector2) -> Variant:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if dir.y >= -0.001:
		return null
	var t := -from.y / dir.y
	return from + dir * t


func _process(delta: float) -> void:
	_t += delta
	_friends_t -= delta
	if _friends_t <= 0.0:
		_friends_t = 0.5
		_update_friends()
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y += 1
	focus += Vector3(mv.x, 0, mv.y) * height * 0.8 * delta
	focus.x = clampf(focus.x, -900, 900)
	focus.z = clampf(focus.z, -900, 900)
	height = lerpf(height, _t_height, 1.0 - exp(-delta * 8.0))
	cam.global_position = focus + Vector3(0, height, height * 0.42)
	cam.look_at(focus, Vector3.UP)

	var gp = _ground_point(get_viewport().get_mouse_position())
	if gp == null:
		_hover_ring.visible = false
		return
	var p: Vector3 = gp
	var loc: int = map.location_at(p.x, p.z)
	_hover_ring.visible = true
	_hover_ring.position = Vector3(p.x, 3, p.z)
	var c: Color = Color(1, 0.2, 0.2) if loc < 0 else GS.LOCATIONS[loc].color
	_hover_ring.material_override = Fx.ghost(Color(c.r, c.g, c.b, 0.8), 1.5)
	_hover_lbl.text = GS.t("Здесь нельзя разместить базу (вода / объект / край карты)") if loc < 0 else GS.t("Позиция: ") + GS.loc_name(loc)
	_hover_lbl.add_theme_color_override("font_color", c)
	if _marker.visible:
		_marker.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 5.0))


## Where the other players of the session already stand: a beam in their colour with a name tag.
func _update_friends() -> void:
	var me := Net.code()
	for c in Net.players:
		var pl: Dictionary = Net.players[c]
		if c == me or not bool(pl.has_base):
			continue
		if not _friends.has(c):
			var col: Color = pl.color
			var m := Node3D.new()
			Meshes.part(m, Fx.ring_mesh(40.0, 6.0), Fx.ghost(Color(col.r, col.g, col.b, 0.9), 2.0), Vector3(0, 2, 0))
			var beam := Meshes.cyl(m, 3.0, 3.0, 300.0, Vector3(0, 150, 0), Fx.ghost(Color(col.r, col.g, col.b, 0.25), 1.5), Vector3.ZERO, 10)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var l := Label3D.new()
			l.font = GS.font
			l.font_size = 40
			l.outline_size = 10
			l.modulate = col
			l.outline_modulate = Color(0, 0, 0, 0.85)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.fixed_size = true
			l.no_depth_test = true
			l.pixel_size = 0.0011
			l.position = Vector3(0, 320, 0)
			m.add_child(l)
			map.add_child(m)
			_friends[c] = m
		var node: Node3D = _friends[c]
		node.position = Vector3(pl.base.x, 0, pl.base.z)
		for ch in node.get_children():
			if ch is Label3D:
				(ch as Label3D).text = GS.t("База %s") % String(pl.nick)
	for c in _friends.keys():
		if not Net.players.has(c):
			(_friends[c] as Node3D).queue_free()
			_friends.erase(c)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_t_height = clampf(_t_height * 0.88, 250.0, 2200.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_t_height = clampf(_t_height * 1.14, 250.0, 2200.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left = true
				_moved = false
				_press = mb.position
			else:
				if _left and not _moved:
					_pick(mb.position)
				_left = false
	elif event is InputEventMouseMotion and _left:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press) > 10.0:
			_moved = true
		if _moved:
			focus -= Vector3(mm.relative.x, 0, mm.relative.y) * height * 0.0016
	elif event is InputEventMagnifyGesture:
		_t_height = clampf(_t_height / (event as InputEventMagnifyGesture).factor, 250.0, 2200.0)


func _pick(screen: Vector2) -> void:
	var gp = _ground_point(screen)
	if gp == null:
		return
	var p: Vector3 = gp
	var loc: int = map.location_at(p.x, p.z)
	if loc < 0:
		SFX.play("alert", -12.0)
		return
	SFX.play("click", -4.0)
	chosen = Vector3(p.x, 0, p.z)
	chosen_loc = loc
	_marker.visible = true
	_marker.position = chosen
	var def: Dictionary = GS.LOCATIONS[loc]
	_sel_title.text = GS.loc_name(loc)
	_sel_title.add_theme_color_override("font_color", def.color)
	_sel_desc.text = GS.loc_desc(loc)
	_start.disabled = false


func _on_start() -> void:
	if chosen_loc >= 0:
		main.create_world(chosen, chosen_loc)
