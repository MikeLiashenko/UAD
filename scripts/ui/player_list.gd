extends PanelContainer
## Minecraft-style player list (Tab) of a multiplayer session: everyone in the world with their
## colour, where their base stands, what they are doing right now and their connection, and a
## button to watch through their eyes.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const PingBars = preload("res://scripts/ui/ping_bars.gd")
const RemotePlayers = preload("res://scripts/game/remote_players.gd")

var game
var _title: Label
var _rows: VBoxContainer
var _sig := "-"
var _t := 0.0


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -330
	offset_right = 330
	offset_top = 64
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(8)
	add_child(v)
	_title = UiKit.glow_label("", 24, UiKit.NEON)
	v.add_child(_title)
	_rows = UiKit.vbox(6)
	v.add_child(_rows)
	var hint := UiKit.label(GS.t("%s — закрыть · «Смотреть» — вид глазами игрока, Esc — вернуться") % GS.key_label("players"), 13, Color(0.55, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(hint)
	_rebuild()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		_rebuild()


func _rebuild() -> void:
	var me := Net.code()
	var codes := Net.players.keys()
	codes.sort_custom(func(a, b) -> bool: return int(Net.players[a].slot) < int(Net.players[b].slot))
	var sig := "%s|%s|" % [game.watch_code, Net.role]
	for c in codes:
		var p: Dictionary = Net.players[c]
		sig += "%s|%s|%s|%s|%s|%d;" % [c, p.nick, p.view, p.has_base, p.has_cam, PingBars.for_ping(int(p.ping))]
	if sig == _sig:
		return
	_sig = sig
	var host_nick := String(Net.players[Net.host].nick) if Net.players.has(Net.host) else "?"
	if Net.role == "host":
		_title.text = GS.t("ВАШ МИР «%s» · ИГРОКОВ %d/%d") % [GS.world_name, codes.size(), Net.MAX_PLAYERS]
	else:
		_title.text = GS.t("В ГОСТЯХ У %s · ИГРОКОВ %d/%d") % [host_nick.to_upper(), codes.size(), Net.MAX_PLAYERS]
	for ch in _rows.get_children():
		ch.queue_free()
	for c in codes:
		_rows.add_child(_row(String(c), Net.players[c], String(c) == me))


func _row(c: String, p: Dictionary, mine: bool) -> Control:
	var h := UiKit.hbox(12)
	h.custom_minimum_size = Vector2(0, 44)
	var sw := ColorRect.new()
	sw.color = p.color
	sw.custom_minimum_size = Vector2(16, 16)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	var col := UiKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	var who := String(p.nick)
	if c == Net.host:
		who += GS.t(" · хост")
	if mine:
		who += GS.t(" (вы)")
	col.add_child(UiKit.label(who, 18, Color(1, 1, 1) if not mine else UiKit.NEON))
	var doing := RemotePlayers.view_name(String(p.view)) if bool(p.has_cam) else GS.t("выбирает позицию")
	var where := ""
	if bool(p.has_base):
		var d := Vector2(float(p.base.x) - GS.base_pos.x, float(p.base.z) - GS.base_pos.z).length() * 0.005
		where = GS.loc_name(int(p.loc)) + (GS.t(" · %.1f км от вас") % d if not mine else "")
	col.add_child(UiKit.label(doing + (" · " + where if where != "" else ""), 13, Color(0.65, 0.9, 0.8)))
	var pb := PingBars.new()
	pb.bars = PingBars.for_ping(int(p.ping))
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	var ms := UiKit.label("%d ms" % int(p.ping), 12, Color(0.55, 0.75, 0.68))
	ms.custom_minimum_size = Vector2(56, 0)
	ms.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ms)
	if not mine:
		var watching: bool = game.view == "watch" and game.watch_code == c
		var b := UiKit.button(GS.t("◉ Смотрите") if watching else GS.t("👁 Смотреть"), func() -> void:
			if watching:
				game.set_view("top")
			else:
				game.watch(c)
			game.hud.toggle_players(), 150, 15)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not bool(p.has_cam) and not watching
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	else:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(150, 0)
		h.add_child(sp)
	return h
