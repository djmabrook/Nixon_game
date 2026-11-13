class_name SurfAudio
extends Node
## The board's sound, synthesised live so it follows the physics exactly:
## - air rushing past (filtered noise that opens and swells with speed, gusts in the air),
## - the edge hissing through sand (brighter and louder when carving and sliding),
## - one-shots made once at startup: the pop, landings by weight, a wipeout tumble, a bump,
##   and glassy chimes for gates and tricks on the D lydian notes the inks use.
## No voices: only air, sand and light. Everything goes through the Near bus (chimes: Ink).

const RATE := 22050.0
## D lydian, as in audio/AUDIO.md (D, E, F#, G#, A, B, C#), two octaves.
const LYDIAN := [293.66, 329.63, 369.99, 415.30, 440.0, 493.88, 554.37,
	587.33, 659.26, 739.99, 830.61, 880.0, 987.77, 1108.73]

var surfer: Surfer
var volume_db := -4.0

var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _lp_wind := [0.0, 0.0, 0.0, 0.0]
var _lp_sand := [0.0, 0.0]
var _hp_sand := [0.0, 0.0]
var _wind_amp := 0.0
var _sand_amp := 0.0
var _wind_cut := 0.05
var _sand_cut := 0.3
var _gust := 0.0
var _streams := {}
var _chime_step := 0
var _chime_reset := 0.0


func _ready() -> void:
	_rng.seed = 7
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = &"Near" if AudioServer.get_bus_index(&"Near") >= 0 else &"Master"
	_player.volume_db = volume_db
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_streams["pop"] = _make_pop()
	_streams["land"] = _make_land(1.0)
	_streams["land_soft"] = _make_land(0.45)
	_streams["wipe"] = _make_wipe()
	_streams["bump"] = _make_land(0.7, 0.12)
	if surfer:
		surfer.launched.connect(func(_s: float) -> void: _one("pop", -8.0 + minf(surfer.vel.length() / 10.0, 4.0), randf_range(0.9, 1.1)))
		surfer.landed.connect(_on_landed)
		surfer.wiped_out.connect(func(_s: float) -> void: _one("wipe", 0.0))
		surfer.trick_landed.connect(_on_trick)
		surfer.boosted.connect(func(_a: float) -> void: chime())
		surfer.recovered.connect(func() -> void: _sound_id(&"wake", -10.0))


func _process(delta: float) -> void:
	_chime_reset -= delta
	if _chime_reset <= 0.0:
		_chime_step = 0
	if _pb == null or not is_instance_valid(surfer):
		return
	var sp := surfer.vel.length()
	var riding := surfer.state == Surfer.State.RIDE and surfer.board.visible
	var air := surfer.state == Surfer.State.AIR
	_gust = lerpf(_gust, 1.0 if air else 0.0, 1.0 - exp(-3.0 * delta))
	var wind_t := clampf(sp / 50.0, 0.0, 1.0)
	var want_wind := pow(wind_t, 1.4) * (0.55 + 0.35 * _gust)
	var want_sand := 0.0
	if riding:
		want_sand = clampf(0.08 + sp / 70.0 * 0.4 + surfer.slide * 0.9 + absf(surfer.carve) * sp / 45.0 * 0.35, 0.0, 1.0)
	var target_wind_cut := lerpf(0.01, 0.16, wind_t) + _gust * 0.04
	var target_sand_cut := lerpf(0.15, 0.55, clampf(sp / 45.0 + surfer.slide * 0.5, 0.0, 1.0))
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var step := 1.0 / maxf(frames, 1)
	var w0: float = _wind_amp
	var s0: float = _sand_amp
	var wc0: float = _wind_cut
	var sc0: float = _sand_cut
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var k := float(i) * step
		var wa := lerpf(w0, want_wind, k)
		var sa := lerpf(s0, want_sand, k)
		var wc := lerpf(wc0, target_wind_cut, k)
		var sc := lerpf(sc0, target_sand_cut, k)
		var nl := _rng.randf() * 2.0 - 1.0
		var nr := _rng.randf() * 2.0 - 1.0
		# Wind: two-pole low-pass noise per ear (slightly different, so it's wide).
		_lp_wind[0] += wc * (nl - _lp_wind[0])
		_lp_wind[1] += wc * (_lp_wind[0] - _lp_wind[1])
		_lp_wind[2] += wc * 1.1 * (nr - _lp_wind[2])
		_lp_wind[3] += wc * 1.1 * (_lp_wind[2] - _lp_wind[3])
		# Sand: band-passed noise, a crackle on top from sparse grains.
		var grain := (_rng.randf() * 2.0 - 1.0) * (1.0 if _rng.randf() < 0.08 + 0.3 * sa else 0.0)
		var ns := (nl + nr) * 0.5 + grain * 1.5
		_lp_sand[0] += sc * (ns - _lp_sand[0])
		_hp_sand[0] = _lp_sand[0] - _lp_sand[1]
		_lp_sand[1] += 0.02 * (_lp_sand[0] - _lp_sand[1])
		var sand: float = _hp_sand[0] * sa * 0.9
		var l: float = _lp_wind[1] * wa * 3.2 + sand
		var r: float = _lp_wind[3] * wa * 3.2 + sand
		buf[i] = Vector2(clampf(l, -1.0, 1.0), clampf(r, -1.0, 1.0))
	_pb.push_buffer(buf)
	_wind_amp = want_wind
	_sand_amp = want_sand
	_wind_cut = target_wind_cut
	_sand_cut = target_sand_cut


## A glass chime on the next note up the scale (gates in a row climb it).
func chime(volume := -6.0) -> void:
	var f: float = LYDIAN[clampi(_chime_step, 0, LYDIAN.size() - 1)]
	_chime_step = mini(_chime_step + 1, LYDIAN.size() - 1)
	_chime_reset = 4.0
	var key := "chime_%d" % int(f)
	if not _streams.has(key):
		_streams[key] = _make_chime(f)
	_one(key, volume, 1.0, &"Ink")


func bump(speed_into: float) -> void:
	_one("bump", -14.0 + minf(speed_into, 12.0), randf_range(0.85, 1.1))


func _on_landed(quality: float, impact: float) -> void:
	var heavy := clampf(impact / 20.0, 0.0, 1.0)
	_one("land" if heavy > 0.4 else "land_soft", -12.0 + heavy * 10.0, randf_range(0.9, 1.08))
	if quality > 0.93:
		chime(-12.0)


func _on_trick(half_spins: int, flips: int, _air: float) -> void:
	for i in mini(half_spins + flips * 2, 5):
		get_tree().create_timer(0.07 * i).timeout.connect(chime.bind(-8.0))


func _one(key: String, db: float, pitch := 1.0, bus := &"Near") -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var sound := get_node_or_null(^"/root/Sound")
	if sound:
		sound.play(stream, db, pitch, bus if AudioServer.get_bus_index(bus) >= 0 else &"Master")
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _sound_id(id: StringName, db: float) -> void:
	var sound := get_node_or_null(^"/root/Sound")
	if sound and sound.has_sound(id):
		sound.play(id, db)


# ------------------------------------------------------------------ synthesis

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	return w


func _make_pop() -> AudioStreamWAV:
	# The board snapping off the sand: a dry click and a short rising rush.
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var click := sin(TAU * 140.0 * t) * exp(-t * 60.0) * 0.8
		var c := lerpf(0.05, 0.4, t / 0.22)
		lp += c * ((_rng.randf() * 2.0 - 1.0) - lp)
		var rush := lp * sin(PI * clampf(t / 0.22, 0.0, 1.0)) * 0.5
		out[i] = click + rush
	return _wav(out)


func _make_land(weight: float, length := 0.45) -> AudioStreamWAV:
	# Board and body meeting sand: a low thump with a skid of grains after it.
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(95.0, 45.0, clampf(t / 0.12, 0.0, 1.0))
		var thump := sin(TAU * f * t) * exp(-t * 18.0) * weight
		lp += 0.25 * ((_rng.randf() * 2.0 - 1.0) - lp)
		var skid := lp * exp(-t * 7.0) * (0.35 + 0.4 * weight)
		out[i] = (thump + skid) * 0.9
	return _wav(out)


func _make_wipe() -> AudioStreamWAV:
	# Tumbling: four soft body thuds into sand, spread out and getting smaller.
	var n := int(RATE * 1.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits := [0.0, 0.23, 0.5, 0.82]
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for j in hits.size():
			var dt: float = t - hits[j]
			if dt >= 0.0:
				var g := 1.0 / (1.0 + j * 0.8)
				v += sin(TAU * (70.0 - j * 6.0) * dt) * exp(-dt * 22.0) * g
		lp += 0.18 * ((_rng.randf() * 2.0 - 1.0) - lp)
		v += lp * exp(-t * 2.2) * 0.35
		out[i] = v * 0.8
	return _wav(out)


func _make_chime(f: float) -> AudioStreamWAV:
	# Glass: inharmonic partials, a soft attack, a long shimmer out.
	var n := int(RATE * 1.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[1.0, 1.0, 2.5], [2.0, 0.35, 4.0], [2.76, 0.3, 5.0], [5.4, 0.12, 9.0]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * f * p[0] * t + sin(TAU * 5.0 * t) * 0.02) * p[1] * exp(-t * p[2])
		v *= minf(t / 0.004, 1.0)
		out[i] = v * 0.32
	return _wav(out)
