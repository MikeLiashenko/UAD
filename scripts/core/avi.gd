extends RefCounted
## Writes an AVI file with a Motion-JPEG video stream and 16-bit PCM audio — the same pair Godot's
## own movie writer uses, and the one every desktop player opens without extra codecs.
##
## The format is a RIFF tree: a header list describing the two streams, a `movi` list holding the
## frames themselves (`00dc` = a JPEG, `01wb` = a block of samples) and an index at the end. The
## sizes of the lists and the frame counts are only known once recording stops, so they are left
## as zeroes and patched in [method close].
##
## Nothing here touches the screen: the caller hands over already-encoded JPEGs and PCM, which is
## what makes the writer testable on its own (see `--avitest` in scripts/main.gd).

## Bytes of the fixed-size structures, kept as names because the offsets below depend on them.
const AVIH_SIZE := 56
const STRH_SIZE := 56
const BITMAPINFO_SIZE := 40
const WAVEFORMAT_SIZE := 18
## AVIF_HASINDEX: the file ends with an idx1 the player can seek through.
const FLAG_HAS_INDEX := 0x10
## AVIIF_KEYFRAME: every MJPEG frame stands on its own.
const FLAG_KEYFRAME := 0x10

var frames := 0
var audio_bytes := 0
var path := ""

var _f: FileAccess
var _fps := 30
var _width := 0
var _height := 0
var _rate := 44100
var _channels := 2
var _biggest := 0
## File offsets patched once the totals are known.
var _riff_size_at := 0
var _total_frames_at := 0
var _max_rate_at := 0
var _buffer_size_at := 0
var _vid_length_at := 0
var _aud_length_at := 0
var _movi_size_at := 0
var _movi_data_at := 0
## One entry per chunk: [fourcc, offset inside movi, payload size].
var _index: Array = []


func open(to: String, width: int, height: int, fps: int, mix_rate: int, channels := 2) -> bool:
	_f = FileAccess.open(to, FileAccess.WRITE)
	if _f == null:
		return false
	path = to
	_width = width
	_height = height
	_fps = maxi(fps, 1)
	_rate = maxi(mix_rate, 8000)
	_channels = clampi(channels, 1, 2)
	_write_header()
	return true


## True while a file is open and being written to.
func is_open() -> bool:
	return _f != null


func add_video(jpeg: PackedByteArray) -> void:
	if _f == null or jpeg.is_empty():
		return
	_chunk("00dc", jpeg)
	frames += 1
	_biggest = maxi(_biggest, jpeg.size())


func add_audio(pcm: PackedByteArray) -> void:
	if _f == null or pcm.is_empty():
		return
	_chunk("01wb", pcm)
	audio_bytes += pcm.size()


## Interleaved stereo samples as the audio bus hands them over, to signed 16-bit PCM.
static func to_pcm16(buf: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(buf.size() * 4)
	for i in buf.size():
		var s: Vector2 = buf[i]
		out.encode_s16(i * 4, int(clampf(s.x, -1.0, 1.0) * 32767.0))
		out.encode_s16(i * 4 + 2, int(clampf(s.y, -1.0, 1.0) * 32767.0))
	return out


## Writes the index, patches every size left open in the header and closes the file.
func close() -> void:
	if _f == null:
		return
	var movi_end := _f.get_position()
	_f.store_string("idx1")
	_f.store_32(_index.size() * 16)
	for e in _index:
		_f.store_string(String(e[0]))
		_f.store_32(FLAG_KEYFRAME)
		_f.store_32(int(e[1]))
		_f.store_32(int(e[2]))
	var end := _f.get_position()
	var secs: float = float(frames) / float(_fps)
	var bytes_per_sec: int = int(float(_f.get_position()) / maxf(secs, 0.001))
	_patch(_riff_size_at, end - 8)
	_patch(_movi_size_at, movi_end - _movi_data_at)
	_patch(_total_frames_at, frames)
	_patch(_max_rate_at, bytes_per_sec)
	_patch(_buffer_size_at, _biggest)
	_patch(_vid_length_at, frames)
	_patch(_aud_length_at, audio_bytes / (2 * _channels))
	_f.close()
	_f = null


# --- RIFF plumbing ---------------------------------------------------------------------------
func _patch(at: int, value: int) -> void:
	_f.seek(at)
	_f.store_32(value)
	_f.seek_end()


## One `movi` chunk plus its index entry. Chunks are padded to an even length.
func _chunk(fourcc: String, data: PackedByteArray) -> void:
	var at := _f.get_position()
	_f.store_string(fourcc)
	_f.store_32(data.size())
	_f.store_buffer(data)
	if data.size() % 2 == 1:
		_f.store_8(0)
	# the index counts from the `movi` fourcc, so the first chunk sits at offset 4
	_index.append([fourcc, at - _movi_data_at, data.size()])


func _list(fourcc: String) -> int:
	_f.store_string("LIST")
	var size_at := _f.get_position()
	_f.store_32(0)
	_f.store_string(fourcc)
	return size_at


func _write_header() -> void:
	_f.store_string("RIFF")
	_riff_size_at = _f.get_position()
	_f.store_32(0)
	_f.store_string("AVI ")
	var hdrl_at := _list("hdrl")
	_write_avih()
	_write_video_stream()
	_write_audio_stream()
	_patch(hdrl_at, _f.get_position() - hdrl_at - 4)
	_movi_size_at = _list("movi")
	_movi_data_at = _movi_size_at + 4


func _write_avih() -> void:
	_f.store_string("avih")
	_f.store_32(AVIH_SIZE)
	_f.store_32(int(1000000.0 / float(_fps))) # microseconds per frame
	_max_rate_at = _f.get_position()
	_f.store_32(0) # max bytes per second
	_f.store_32(0) # padding granularity
	_f.store_32(FLAG_HAS_INDEX)
	_total_frames_at = _f.get_position()
	_f.store_32(0) # total frames
	_f.store_32(0) # initial frames
	_f.store_32(2) # streams: video and audio
	_buffer_size_at = _f.get_position()
	_f.store_32(0) # suggested buffer size
	_f.store_32(_width)
	_f.store_32(_height)
	for i in 4:
		_f.store_32(0) # reserved


func _write_video_stream() -> void:
	var strl_at := _list("strl")
	_f.store_string("strh")
	_f.store_32(STRH_SIZE)
	_f.store_string("vids")
	_f.store_string("MJPG")
	_f.store_32(0) # flags
	_f.store_16(0) # priority
	_f.store_16(0) # language
	_f.store_32(0) # initial frames
	_f.store_32(1) # scale
	_f.store_32(_fps) # rate: scale / rate = frames per second
	_f.store_32(0) # start
	_vid_length_at = _f.get_position()
	_f.store_32(0) # length, in frames
	_f.store_32(0) # suggested buffer size
	_f.store_32(10000) # quality
	_f.store_32(0) # sample size: 0 for a variable-size frame
	for i in 4:
		_f.store_16(0) # rcFrame
	_f.store_string("strf")
	_f.store_32(BITMAPINFO_SIZE)
	_f.store_32(BITMAPINFO_SIZE)
	_f.store_32(_width)
	_f.store_32(_height)
	_f.store_16(1) # planes
	_f.store_16(24) # bits per pixel
	_f.store_string("MJPG")
	_f.store_32(_width * _height * 3)
	for i in 4:
		_f.store_32(0) # pixels per metre, palette
	_patch(strl_at, _f.get_position() - strl_at - 4)


func _write_audio_stream() -> void:
	var strl_at := _list("strl")
	var block: int = 2 * _channels
	_f.store_string("strh")
	_f.store_32(STRH_SIZE)
	_f.store_string("auds")
	_f.store_32(1) # PCM
	_f.store_32(0) # flags
	_f.store_16(0) # priority
	_f.store_16(0) # language
	_f.store_32(0) # initial frames
	_f.store_32(block) # scale
	_f.store_32(_rate * block) # rate
	_f.store_32(0) # start
	_aud_length_at = _f.get_position()
	_f.store_32(0) # length, in samples
	_f.store_32(_rate * block) # suggested buffer size
	_f.store_32(0) # quality
	_f.store_32(block) # sample size
	for i in 4:
		_f.store_16(0) # rcFrame
	_f.store_string("strf")
	_f.store_32(WAVEFORMAT_SIZE)
	_f.store_16(1) # WAVE_FORMAT_PCM
	_f.store_16(_channels)
	_f.store_32(_rate)
	_f.store_32(_rate * block) # average bytes per second
	_f.store_16(block) # block align
	_f.store_16(16) # bits per sample
	_f.store_16(0) # cbSize
	_patch(strl_at, _f.get_position() - strl_at - 4)
