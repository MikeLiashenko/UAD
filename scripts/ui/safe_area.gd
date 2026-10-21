extends Control
## A full-screen frame that keeps the interface inside it clear of the screen's notch (or camera
## hole), rounded corners and home bar (GS.safe_insets). A phone turned over moves the notch to
## the other side without changing the window's size, so on a phone it looks again twice a second
## (and sets the interface's scale, GS.ui_scale, so the whole layout fits between the cut-outs).
## Full-screen pictures under the interface (dimmers, filters, the reticle and other overlays drawn
## where the 3D camera puts things) step back out to the edges with UiKit.bleed.

var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(OS.has_feature("mobile") or GS.force_safe != Vector4i.ZERO)
	fit()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		fit()


func fit() -> void:
	var k := GS.ui_scale()
	if not is_equal_approx(get_tree().root.content_scale_factor, k):
		get_tree().root.content_scale_factor = k
	var e := GS.safe_insets()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = e.x
	offset_top = e.y
	offset_right = -e.z
	offset_bottom = -e.w
	for c in get_tree().get_nodes_in_group(&"bleed"):
		bleed_fit(c as Control)


## The whole screen again for a full-screen control placed inside a safe frame.
static func bleed_fit(c: Control) -> void:
	var e := GS.safe_insets()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = -e.x
	c.offset_top = -e.y
	c.offset_right = e.z
	c.offset_bottom = e.w
