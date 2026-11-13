extends Node
## Sound for the Red Grid, synthesised at load so the room ships without audio files.
## Replace any entry in `sounds` with a real sample later; the keys are what the room plays.
## The Watcher's sound is a broadcast with nothing on it: hum, hiss and a held tone.

const RATE := 22050
const VOICES := 8

var sounds := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var drone: AudioStreamPlayer
var wind: AudioStreamPlayer
var _seed := 1


func _ready() -> void:
	sounds[&"pick"] = _make(0.55, func(t: float) -> float:
		# Suction: a hiss swept upward into a soft pop.
		var f := lerpf(120.0, 900.0, pow(t / 0.55, 2.0))
		return (sin(TAU * f * t) * 0.35 + _noise() * 0.25 * (1.0 - t / 0.55)) * _env(t, 0.55, 0.02, 0.12))
	sounds[&"lay"] = _make(1.2, func(t: float) -> float:
		var f := lerpf(90.0, 38.0, minf(t / 0.5, 1.0))
		return (sin(TAU * f * t) * 0.9 + _noise() * 0.3 * exp(-t * 30.0)) * exp(-t * 3.2))
	for i in 6:
		var note: float = [146.83, 164.81, 196.0, 220.0, 246.94, 293.66][i]
		sounds[StringName("socket%d" % i)] = _make(3.0, func(t: float) -> float:
			var thud := sin(TAU * lerpf(70.0, 36.0, minf(t / 0.4, 1.0)) * t) * exp(-t * 4.0)
			var tone := (sin(TAU * note * t) + 0.35 * sin(TAU * note * 2.01 * t) + 0.2 * sin(TAU * note * 3.0 * t)) * exp(-t * 1.1)
			return thud * 0.8 + tone * 0.22 * smoothstep(0.0, 0.03, t))
	sounds[&"cut"] = _make(2.2, func(t: float) -> float:
		var tear := _noise() * exp(-t * 2.5) * (0.5 + 0.5 * sin(TAU * 31.0 * t))
		var ring := sin(TAU * 880.0 * t) * 0.15 * exp(-t * 1.5)
		return (tear * 0.55 + ring) * _env(t, 2.2, 0.005, 1.4))
	sounds[&"fall"] = _make(8.0, func(t: float) -> float:
		var f := lerpf(60.0, 22.0, t / 8.0)
		return (sin(TAU * f * t) * 0.7 + _noise() * 0.35) * _env(t, 8.0, 0.4, 6.0) * 0.9)
	sounds[&"spring"] = _make(6.0, func(t: float) -> float:
		# A wire plain the size of a county snapping taut: a huge twang with a wobble.
		var wob := 1.0 + 0.05 * sin(TAU * 3.2 * t) * exp(-t * 1.1)
		var s := 0.0
		for h in [1.0, 2.0, 3.01, 4.02, 5.5]:
			s += sin(TAU * 55.0 * h * wob * t) / h
		return (s * 0.45 + _noise() * 0.2 * exp(-t * 8.0)) * _env(t, 6.0, 0.003, 5.0))
	sounds[&"lid"] = _make(7.0, func(t: float) -> float:
		var s := 0.0
		for n in [146.83, 220.0, 293.66, 369.99, 440.0]:
			s += sin(TAU * n * t + sin(TAU * 0.3 * t) * 0.8)
		return (s * 0.08 + _noise() * 0.06) * _env(t, 7.0, 2.5, 3.0))
	sounds[&"ink"] = _make(3.0, func(t: float) -> float:
		var s := 0.0
		var notes := [293.66, 369.99, 440.0, 587.33]
		for i in notes.size():
			var st := i * 0.12
			if t > st:
				s += sin(TAU * notes[i] * (t - st)) * exp(-(t - st) * 1.4)
		return s * 0.18)
	sounds[&"swallow"] = _make(0.9, func(t: float) -> float:
		var f := lerpf(400.0, 50.0, t / 0.9)
		return sin(TAU * f * t) * 0.5 * _env(t, 0.9, 0.01, 0.5))
	sounds[&"spit"] = _make(0.5, func(t: float) -> float:
		var f := lerpf(60.0, 500.0, t / 0.5)
		return (sin(TAU * f * t) * 0.5 + _noise() * 0.15) * _env(t, 0.5, 0.01, 0.3))
	sounds[&"flinch"] = _make(1.5, func(t: float) -> float:
		return (sin(TAU * 41.0 * t) * 0.8 + sin(TAU * 61.5 * t) * 0.3) * _env(t, 1.5, 0.05, 1.2))

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)

	# Loops: the empty broadcast (louder in the dark) and a thin wind over the open plain.
	drone = _loop(_make(4.0, func(t: float) -> float:
		var hum := sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.18 + sin(TAU * 165.0 * t) * 0.07
		var tone := sin(TAU * 440.0 * t) * 0.03
		return (hum + tone + _noise() * 0.05) * 0.6))
	wind = _loop(_make(4.0, func(t: float) -> float:
		return _noise() * (0.25 + 0.15 * sin(TAU * 0.5 * t)) * 0.5))


func play(key: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(key):
		return
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = sounds[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _loop(stream: AudioStreamWAV) -> AudioStreamPlayer:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	p.autoplay = true
	add_child(p)
	return p


func _make(length: float, fn: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(fn.call(float(i) / RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _env(t: float, length: float, attack: float, release: float) -> float:
	return clampf(t / attack, 0.0, 1.0) * clampf((length - t) / release, 0.0, 1.0)


func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x3fffffff) - 1.0
