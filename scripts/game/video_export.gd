extends Node
## Saves the nightly compilation to a real video file.
##
## There is no encoder to call out to, so the cut is recorded the way a screen recorder would do
## it: the compilation plays once at normal speed while every rendered frame is grabbed, cropped
## to the phone frame, scaled down and written as a JPEG into an AVI (scripts/core/avi.gd). The
## sound goes with it — a capture effect on the master bus hands over the samples that were
## actually played, so the bang still lands where it landed on screen.
##
## Wall clock drives both streams: the video frame index is computed from elapsed time, so if a
## frame takes too long the previous picture is repeated instead of the sound drifting away.

const Avi = preload("res://scripts/core/avi.gd")

signal done(saved: String, ok: bool)

## The file is vertical, like the video it pretends to be, and stays small enough to send.
const WIDTH := 540
const HEIGHT := 960
const FPS := 30
const QUALITY := 0.78
## At most this many repeated frames per pump, so a long stall cannot spiral.
const MAX_CATCHUP := 6

var game
var reel
## The overlay being recorded; it knows where the phone frame sits on screen.
var ui
var recording := false
var path := ""
## 0 .. 1, for the badge the overlay draws.
var progress := 0.0

## Test hook: generate the frames instead of grabbing them, so the recording path can run
## without a window (a headless run renders nothing to capture). See --exporttest.
var synthetic := false

var _avi
var _capture: AudioEffectCapture
var _t0 := 0
var _emitted := 0
var _last := PackedByteArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Picks a file next to the player's other videos: Видео/UAD/kyiv_cuts_day7.avi (the city of the world goes into the name).
static func target_path(day: int) -> String:
	var base := String(OS.get_system_dir(OS.SYSTEM_DIR_MOVIES))
	if base == "" or not DirAccess.dir_exists_absolute(base):
		base = "user://"
	var dir := base.path_join("UAD")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("%s_cuts_day%d.avi" % [GS.city_id, day])


## Opens the file and starts following the cut. The reel must already be playing.
func start(day: int) -> bool:
	path = target_path(day)
	_avi = Avi.new()
	if not _avi.open(path, WIDTH, HEIGHT, FPS, int(AudioServer.get_mix_rate()), 2):
		_avi = null
		return false
	_listen()
	recording = true
	_emitted = 0
	progress = 0.0
	_t0 = Time.get_ticks_msec()
	_record()
	return true


## Taps the master bus so the recording carries the sound the player is hearing.
func _listen() -> void:
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _capture)


func _unlisten() -> void:
	if _capture == null:
		return
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, i) == _capture:
			AudioServer.remove_bus_effect(0, i)
			break
	_capture = null


## One pass per rendered frame: a frame can only be grabbed once it is actually on screen.
func _record() -> void:
	while recording:
		await RenderingServer.frame_post_draw
		if not recording:
			return
		_pump()


func _pump() -> void:
	if _avi == null:
		return
	_take_sound()
	var elapsed: float = float(Time.get_ticks_msec() - _t0) / 1000.0
	if reel != null and reel.playing:
		progress = clampf(reel.progress(), 0.0, 1.0)
	var want: int = int(elapsed * float(FPS))
	if want <= _emitted:
		return
	var shot := _take_picture()
	if not shot.is_empty():
		_last = shot
	if _last.is_empty():
		return
	# a frame that took too long is covered by repeating the last picture, not by drifting
	var repeat: int = mini(want - _emitted, MAX_CATCHUP)
	for i in repeat:
		_avi.add_video(_last)
	_emitted += repeat


func _take_sound() -> void:
	if _capture == null:
		return
	var n: int = _capture.get_frames_available()
	if n > 0:
		_avi.add_audio(Avi.to_pcm16(_capture.get_buffer(n)))


## The screen, cropped to the phone frame and scaled down to the file's size.
func _take_picture() -> PackedByteArray:
	if synthetic:
		var test := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
		test.fill(Color(0.1, 0.5 + 0.4 * sin(float(_emitted) * 0.2), 0.4))
		return test.save_jpg_to_buffer(QUALITY)
	var tex := get_viewport().get_texture()
	if tex == null:
		return PackedByteArray()
	var img := tex.get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	var full := Rect2i(Vector2i.ZERO, img.get_size())
	var want := full
	if ui != null and is_instance_valid(ui):
		var r: Rect2 = ui.frame_rect()
		want = Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y))
	want = want.intersection(full)
	if want.size.x < 8 or want.size.y < 8:
		want = full
	img = img.get_region(want)
	img.resize(WIDTH, HEIGHT, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(QUALITY)


## Test hook: pretends this much more time has passed and writes the frames that fall due.
func test_advance(seconds: float) -> void:
	_t0 -= int(seconds * 1000.0)
	_pump()


## Closes the file. A cut that was broken off is thrown away rather than left half-written.
func finish(ok: bool) -> void:
	if not recording:
		return
	recording = false
	_unlisten()
	var frames: int = _avi.frames if _avi != null else 0
	if _avi != null:
		_avi.close()
	_avi = null
	if not ok or frames < FPS:
		DirAccess.remove_absolute(path)
		done.emit(path, false)
	else:
		done.emit(path, true)
