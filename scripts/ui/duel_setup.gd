extends Control
## The window of a duel (ServerDef.duel) on the multiplayer tab: three nights, one against one.
## The challenger picks the city they defend and the friend's, then sends the challenge — it is
## published under their code, goes out with their presence (Net.duel_invite) and the challenger
## enters the match at once to wait there; the friend accepts it from their own list of friends.
## With `bot` the same duel is played against the machine and nothing goes over the network.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Cities = preload("res://scripts/world/cities.gd")
const ServerDef = preload("res://scripts/core/server_def.gd")
const CityStore = preload("res://scripts/core/city_store.gd")

## The cities picked last, kept while the game runs.
static var last := ["kyiv", "kharkiv"]

var main
## The friend challenged: their code and nick ("" with `bot`).
var friend := ""
var friend_nick := ""
var bot := false

## [key, city of the duel, label]: the game's own cities, then the ones the player drew.
var _options: Array = []
var _picks: Array = []
var _go: Button
var _status: Label
var _busy := false


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.bleed(ColorRect.new()) as ColorRect
	dim.color = Color(0, 0.02, 0.02, 0.65)
	add_child(dim)
	var center := UiKit.full_rect(CenterContainer.new())
	add_child(center)
	var p := UiKit.panel(Vector2(600, 0))
	center.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.glow_label(GS.t("ДУЭЛЬ С БОТОМ") if bot else GS.t("ДУЭЛЬ · %s") % friend_nick.to_upper(), 30, UiKit.NEON))
	var about := UiKit.label(GS.t("Один на один, три ночи. Каждый защищает свой город и бьёт по городу соперника: днём удары готовятся, ночью взлетают. Побеждает тот, чей город после третьей ночи цел больше, — или тот, кто разрушит чужой раньше."), 15, Color(0.6, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(560, 0)
	v.add_child(about)
	for id in Cities.IDS:
		_options.append([id, ServerDef.builtin_city(id), GS.t(String(Cities.get_def(id).name))])
	for e in CityStore.list():
		var c: Dictionary = e.city
		_options.append(["my:" + String(e.id), c, GS.t("✎ %s (свой)") % String(c.name)])
	_picks = [_picker(v, GS.t("Ваш город"), String(last[0]), UiKit.NEON), _picker(v, GS.t("Город бота") if bot else GS.t("Город друга"), String(last[1]), UiKit.RED)]
	_status = UiKit.label("", 15, Color(0.7, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(560, 0)
	v.add_child(_status)
	_go = UiKit.button(GS.t("▶ Начать дуэль") if bot else GS.t("⚔ Вызвать на дуэль"), _start, 560, 22)
	v.add_child(_go)
	v.add_child(UiKit.button(GS.t("Отмена"), _cancel, 560, 18))
	_check()


func _picker(parent: Control, title: String, want: String, col: Color) -> OptionButton:
	var row := UiKit.hbox(10)
	parent.add_child(row)
	var l := UiKit.label(title, 18, col)
	l.custom_minimum_size = Vector2(180, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(370, 48)
	ob.add_theme_font_size_override("font_size", 20)
	ob.get_popup().add_theme_font_size_override("font_size", 20)
	for i in _options.size():
		ob.add_item(String(_options[i][2]), i)
	var at := 0
	for i in _options.size():
		if String(_options[i][0]) == want:
			at = i
	ob.select(at)
	ob.item_selected.connect(func(_i: int) -> void:
		SFX.play("click", -8.0)
		_check())
	row.add_child(ob)
	return ob


func _key(i: int) -> String:
	return String(_options[(_picks[i] as OptionButton).selected][0])


func _check() -> void:
	if _busy:
		return
	var same := _key(0) == _key(1)
	_go.disabled = same
	_status.add_theme_color_override("font_color", UiKit.AMBER if same else Color(0.6, 0.85, 0.75))
	if same:
		_status.text = GS.t("Выберите два разных города")
	elif bot:
		_status.text = GS.t("За город соперника играет бот. Ничего не сохраняется.")
	else:
		_status.text = GS.t("%s увидит вызов у себя на вкладке «Мультиплеер». Вы войдёте в игру сразу — выберите позицию и ждите соперника там.") % friend_nick


func _start() -> void:
	if _busy or _go.disabled:
		return
	last = [_key(0), _key(1)]
	var cities := []
	for i in 2:
		cities.append((_options[(_picks[i] as OptionButton).selected][1] as Dictionary).duplicate(true))
	var def := ServerDef.duel(Net.code(), Net.nick(), cities)
	if def.is_empty():
		_fail(GS.t("Не удалось собрать дуэль"))
		return
	SFX.play("click", -4.0)
	if bot:
		main.start_server(def, 0, true)
		return
	_busy = true
	_go.disabled = true
	for ob in _picks:
		(ob as OptionButton).disabled = true
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))
	_status.text = GS.t("Отправляем вызов…")
	var me := self
	Net.srv_publish(def, func(ok: bool, why: String) -> void:
		if not is_instance_valid(me):
			return
		if not ok:
			_fail(why)
			return
		Net.srv_join(def, 0, func(ok2: bool, why2: String) -> void:
			if not is_instance_valid(me):
				if ok2:
					Net.close() # cancelled while the answer was on its way
				return
			if not ok2:
				_fail(why2)
				return
			Net.set_duel_invite({"to": friend, "sid": String(def.id), "c": [String(def.cities[0].name), String(def.cities[1].name)],
				"b": [ServerDef.builtin(def.cities[0]), ServerDef.builtin(def.cities[1])]})
			main.start_server(def, 0, false)))


func _fail(text: String) -> void:
	_busy = false
	SFX.play("alert", -10.0)
	for ob in _picks:
		(ob as OptionButton).disabled = false
	_check()
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.RED)


func _cancel() -> void:
	if _busy:
		Net.close()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()
