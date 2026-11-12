extends Node
## Tiny synth so the room has sound without audio files. Every sound is built
## once in _ready() as an AudioStreamWAV. Swap any of them for a real sample later
## by assigning a stream to the matching key in `sounds`.

const RATE := 22050
const VOICES := 8

var sounds := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _drone: AudioStreamPlayer


func _ready() -> void:
	sounds[&"warn"] = _make(0.85, func(t: float) -> float:
		var f := lerpf(180.0, 420.0, t / 0.85)
		return sin(TAU * f * t) * 0.35 * _env(t, 0.85, 0.05, 0.2) * (0.6 + 0.4 * sin(TAU * 18.0 * t)))
	sounds[&"surge"] = _make(0.9, func(t: float) -> float:
		var f := lerpf(70.0, 46.0, t / 0.9)
		return (sin(TAU * f * t) * 0.7 + _noise() * 0.18) * _env(t, 0.9, 0.01, 0.8))
	sounds[&"thunk"] = _make(0.25, func(t: float) -> float:
		var f := lerpf(160.0, 60.0, t / 0.25)
		return (sin(TAU * f * t) + _noise() * 0.25) * exp(-t * 22.0) * 0.8)
	sounds[&"push"] = _make(0.12, func(t: float) -> float:
		return (sin(TAU * 240.0 * t) * 0.5 + _noise() * 0.2) * exp(-t * 35.0))
	sounds[&"lift"] = _make(1.6, func(t: float) -> float:
		var s := 0.0
		for f in [523.25, 659.25, 783.99, 1046.5]:
			s += sin(TAU * f * t + sin(TAU * 3.0 * t) * 0.6)
		return s * 0.12 * _env(t, 1.6, 0.25, 1.2))
	sounds[&"socket"] = _make(2.8, func(t: float) -> float:
		var s := 0.0
		var notes := [261.63, 329.63, 392.0, 493.88, 587.33]
		for i in notes.size():
			var start := i * 0.09
			if t > start:
				var lt := t - start
				s += (sin(TAU * notes[i] * lt) + 0.3 * sin(TAU * notes[i] * 2.0 * lt)) * exp(-lt * 1.6)
		return s * 0.16 + sin(TAU * 55.0 * t) * 0.35 * exp(-t * 3.0))
	sounds[&"respawn"] = _make(0.5, func(t: float) -> float:
		var f := lerpf(900.0, 300.0, t / 0.5)
		return sin(TAU * f * t) * 0.25 * _env(t, 0.5, 0.01, 0.45))

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)

	_drone = AudioStreamPlayer.new()
	_drone.stream = _make_drone()
	_drone.volume_db = -80.0
	add_child(_drone)
	_drone.play()


func play(id: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(id):
		return
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = sounds[id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## 0..1. The low hum that sits under the tide.
func set_drone(amount: float) -> void:
	_drone.volume_db = linear_to_db(clampf(amount, 0.0001, 1.0) * 0.6)
	_drone.pitch_scale = 0.9 + amount * 0.2


func _make(duration: float, fn: Callable) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var v := clampf(fn.call(float(i) / RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


func _make_drone() -> AudioStreamWAV:
	# 2 s loop; every partial completes whole cycles so the loop is seamless.
	var wav := _make(2.0, func(t: float) -> float:
		return (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 82.5 * t) * 0.25 + sin(TAU * 110.5 * t) * 0.12) \
			* (0.8 + 0.2 * sin(TAU * 1.5 * t)))
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(2.0 * RATE)
	return wav


static func _env(t: float, dur: float, attack: float, release: float) -> float:
	var a := clampf(t / attack, 0.0, 1.0)
	var r := clampf((dur - t) / release, 0.0, 1.0)
	return a * r


static func _noise() -> float:
	return randf() * 2.0 - 1.0
