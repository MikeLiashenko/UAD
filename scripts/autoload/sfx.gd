extends Node
## Procedural audio (autoload "SFX"). Every sound is synthesized into PCM at startup.

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _siren: AudioStreamPlayer
var _last_play := {}
var _rng := RandomNumberGenerator.new()


const MUSIC := {
	"menu": "res://audio/menu.mp3",
	"day": "res://audio/day.mp3",
	"night": "res://audio/night.mp3",
}
const MUSIC_DB := -4.0

var _music: Array[AudioStreamPlayer] = []
var _music_idx := 0
var _music_track := ""
var _duck := 0.0


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_ensure_bus("Effects")
	_ensure_bus("Music")
	for i in 20:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_players.append(p)
	_siren = AudioStreamPlayer.new()
	_siren.bus = "Effects"
	add_child(_siren)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -60.0
		add_child(m)
		_music.append(m)
	_streams["step"] = _to_wav(_gen_step())
	_streams["mg"] = _to_wav(_gen_gun(0.07, 55.0, 0.9))
	_streams["cannon"] = _to_wav(_gen_gun(0.16, 22.0, 0.35))
	_streams["explosion"] = _to_wav(_gen_explosion(1.6, 2.8))
	_streams["boom_small"] = _to_wav(_gen_explosion(0.7, 6.0))
	_streams["launch"] = _to_wav(_gen_launch())
	_streams["alert"] = _to_wav(_gen_alert())
	_streams["click"] = _to_wav(_gen_tone(0.04, 1400.0, 60.0, 0.25))
	_streams["cash"] = _to_wav(_gen_cash())
	_streams["splash"] = _to_wav(_gen_splash())
	_streams["siren"] = _to_wav(_gen_siren())
	_streams["buzz"] = _to_wav(_gen_buzz(), true)
	_streams["prop"] = _to_wav(_gen_prop())
	set_music_volume(clampf(float(GS.settings.music), 0.0, 1.0))


## Plays a sound. min_gap throttles very frequent sounds (machine-gun fire).
func play(sound: String, volume_db := 0.0, pitch := 1.0, min_gap := 0.0) -> void:
	if not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(_last_play.get(sound, -10.0)) < min_gap:
		return
	_last_play[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


## Raw stream for looping players (the FPV rotor buzz rides on its own AudioStreamPlayer).
func stream(sound: String) -> AudioStream:
	return _streams.get(sound, null)


func play_siren() -> void:
	_siren.stream = _streams["siren"]
	_siren.volume_db = -6.0
	_siren.play()
	_duck = 8.0


func stop_siren() -> void:
	_siren.stop()


## Crossfades to a looping music track: "menu", "day", "night" (or "" for silence).
## What is playing right now, so a caller can put it back afterwards.
func music_track() -> String:
	return _music_track


func play_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old := _music[_music_idx]
	_music_idx = 1 - _music_idx
	var cur := _music[_music_idx]
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(old, "volume_db", -60.0, 2.0)
	if track != "" and MUSIC.has(track) and ResourceLoader.exists(MUSIC[track]):
		var s = load(MUSIC[track])
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		cur.stream = s
		cur.volume_db = -60.0
		cur.play()
		fade.tween_property(cur, "volume_db", MUSIC_DB, 2.0)
	fade.chain().tween_callback(old.stop)


func _process(delta: float) -> void:
	# duck the music while the air-raid siren is howling
	_duck = maxf(0.0, _duck - delta)
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		var target := -9.0 if _duck > 0.0 else 0.0
		var cur_off := AudioServer.get_bus_volume_db(bus) - _music_base_db
		AudioServer.set_bus_volume_db(bus, _music_base_db + move_toward(cur_off, target, delta * 12.0))


var _music_base_db := 0.0


func set_music_volume(linear: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	_music_base_db = linear_to_db(maxf(linear, 0.0001))
	AudioServer.set_bus_volume_db(bus, _music_base_db)
	AudioServer.set_bus_mute(bus, linear <= 0.001)


# --- Synthesis ------------------------------------------------------------------
func _to_wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _gen_gun(dur: float, decay: float, bright: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * bright
		var thump := sin(TAU * 70.0 * t) * exp(-t * 30.0)
		s[i] = (lp * 0.8 + thump * 0.7) * exp(-t * decay)
	return s


func _gen_explosion(dur: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		var cutoff := lerpf(0.5, 0.03, clampf(t / dur, 0.0, 1.0))
		lp += (white - lp) * cutoff
		lp2 += (lp - lp2) * 0.3
		var thump := sin(TAU * (48.0 - t * 20.0) * t) * exp(-t * 5.0)
		var crack := white * exp(-t * 40.0) * 0.5
		s[i] = (lp2 * 2.2 + thump * 0.9 + crack) * exp(-t * decay) * 0.8
	return s


func _gen_launch() -> PackedFloat32Array:
	var dur := 1.8
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * lerpf(0.08, 0.35, minf(t * 2.0, 1.0))
		var env := minf(t * 25.0, 1.0) * exp(-t * 1.6)
		s[i] = lp * env * 1.6
	return s


func _gen_alert() -> PackedFloat32Array:
	var dur := 0.62
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var seg := int(t / 0.155)
		var f := 880.0 if seg % 2 == 0 else 660.0
		var local := fmod(t, 0.155)
		var env := 1.0 if local < 0.12 else 0.0
		var sq := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		s[i] = sq * env * 0.22
	return s


func _gen_tone(dur: float, freq: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * freq * t) * exp(-t * decay) * amp
	return s


func _gen_cash() -> PackedFloat32Array:
	var a := _gen_tone(0.3, 1320.0, 12.0, 0.3)
	var b := _gen_tone(0.3, 1760.0, 12.0, 0.3)
	var offset := int(0.07 * RATE)
	var s := PackedFloat32Array()
	s.resize(a.size() + offset)
	for i in s.size():
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i >= offset:
			v += b[i - offset]
		s[i] = v
	return s


func _gen_step() -> PackedFloat32Array:
	# soft footstep on asphalt: short low-passed noise thud
	var dur := 0.12
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.18
		s[i] = (lp * 1.4 + sin(TAU * 90.0 * t) * 0.3) * exp(-t * 38.0) * minf(t * 400.0, 1.0)
	return s


func _gen_splash() -> PackedFloat32Array:
	var dur := 0.7
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		var hp := white - prev
		prev = white
		s[i] = hp * 0.35 * minf(t * 60.0, 1.0) * exp(-t * 5.0)
	return s


func _gen_siren() -> PackedFloat32Array:
	# Classic air-raid siren: slowly rising and falling howl with harmonics.
	var dur := 8.0
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 330.0 + 420.0 * (0.5 - 0.5 * cos(TAU * t / 4.0))
		ph += TAU * f / RATE
		var v := sin(ph) + 0.4 * sin(2.0 * ph) + 0.2 * sin(3.0 * ph)
		var env := minf(t / 0.8, 1.0) * minf((dur - t) / 1.2, 1.0)
		s[i] = v * env * 0.3
	return s


## Quadcopter rotor loop for the FPV feed. Four motors at slightly detuned frequencies beat
## against each other the way a real quad does; the whole buffer is an exact number of periods
## of the base tone so that LOOP_FORWARD is seamless.
func _gen_buzz() -> PackedFloat32Array:
	var base := 147.0
	var periods := 147 # 1.0 s at exactly `base` Hz
	var dur := float(periods) / base
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var motors := [1.0, 1.006, 0.993, 1.011]
	var hp := 0.0
	for i in n:
		var t := float(i) / float(n) # 0..1 over exactly `periods` cycles
		var v := 0.0
		for m in motors:
			var ph := TAU * periods * float(m) * t
			v += sin(ph) * 0.5 + sin(2.0 * ph) * 0.28 + sin(3.0 * ph) * 0.12
		# blade chop: an amplitude wobble at the rotor's four-blade passing frequency
		v *= 0.75 + 0.25 * sin(TAU * periods * 4.0 * t)
		# a breath of wind noise, high-passed so it hisses instead of rumbling
		var nz := _rng.randf_range(-1.0, 1.0)
		hp = hp * 0.82 + nz * 0.18
		s[i] = clampf(v * 0.1 + (nz - hp) * 0.05, -1.0, 1.0)
	return s


## Spin-up whir when a drone leaves the rail.
func _gen_prop() -> PackedFloat32Array:
	var dur := 0.8
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := 60.0 + 190.0 * k
		ph += TAU * f / RATE
		var v := sin(ph) + 0.35 * sin(2.0 * ph)
		var nz := _rng.randf_range(-1.0, 1.0) * 0.35 * k
		var env := minf(t / 0.06, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
		s[i] = (v * 0.28 + nz * 0.2) * env
	return s
