extends Control
## Connection quality as in the Minecraft server list: five rising bars, a red cross offline.

## 0..5, or -1 for "no connection".
var bars := -1:
	set(v):
		bars = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(34, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Bars for a round trip to the database, ms (everything goes through it, so it is the lag).
static func for_ping(ms: int) -> int:
	if ms < 150:
		return 5
	if ms < 300:
		return 4
	if ms < 600:
		return 3
	if ms < 1200:
		return 2
	return 1


func _draw() -> void:
	if bars < 0:
		var c := Color(1.0, 0.3, 0.3, 0.9)
		draw_line(Vector2(9, 4), Vector2(25, 20), c, 3.0)
		draw_line(Vector2(25, 4), Vector2(9, 20), c, 3.0)
		return
	var col := Color(0.3, 1.0, 0.5) if bars >= 4 else (Color(1.0, 0.85, 0.3) if bars >= 2 else Color(1.0, 0.35, 0.3))
	for i in 5:
		var h := 5.0 + i * 4.0
		draw_rect(Rect2(Vector2(2 + i * 6.5, 22 - h), Vector2(4.5, h)), col if i < bars else Color(0.3, 0.4, 0.35, 0.5))
