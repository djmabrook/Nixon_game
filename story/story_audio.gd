extends AudioStreamPlayer
## The story's sound, made on the fly (no files): surf on the shore, the television's empty
## broadcast, and one warm held chord at dawn. Then silence.
## The sound thread can replace any of it; the sequences only set the levels below.

## Levels 0..1. They glide toward these values.
var surf := 0.0
var swell := 0.0
var hum := 0.0
var dawn := 0.0
## Overall level 0..1, multiplied with everything.
var level := 1.0
## True when the `Sound` autoload carries the beds and the television: then this only adds
## the story's own moments (the last wave, the drain) under it, and no hum or dawn chord.
var under_sound_engine := false

const RATE := 22050.0

var _gen: AudioStreamGeneratorPlayback
var _s := {surf = 0.0, swell = 0.0, hum = 0.0, dawn = 0.0, level = 1.0}
var _brown := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _phase := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
var _t := 0.0
var _rng := RandomNumberGenerator.new()

# A low open chord for dawn (D2, A2, D3, F#3, A3) and the broadcast hum (50 Hz and up).
const DAWN_HZ := [73.42, 110.0, 146.83, 185.0, 220.0]
const HUM_HZ := [50.0, 100.0, 150.0]


func _ready() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.25
	stream = g
	volume_db = -4.0
	if DisplayServer.get_name() == "headless":
		return
	play()
	_gen = get_stream_playback()


func _process(delta: float) -> void:
	if _gen == null:
		return
	var k := 1.0 - exp(-1.5 * delta)
	var bed_k := 0.35 if under_sound_engine else 1.0
	_s.surf = lerpf(_s.surf, surf * bed_k, k)
	_s.swell = lerpf(_s.swell, swell, 1.0 - exp(-3.0 * delta))
	_s.hum = lerpf(_s.hum, 0.0 if under_sound_engine else hum, k)
	_s.dawn = lerpf(_s.dawn, 0.0 if under_sound_engine else dawn, 1.0 - exp(-0.5 * delta))
	_s.level = lerpf(_s.level, level, k)
	var frames := _gen.get_frames_available()
	for i in frames:
		_t += 1.0 / RATE
		var v := 0.0
		# Surf: brown noise, darkened, breathing in slow irregular swells.
		var white := _rng.randf() * 2.0 - 1.0
		_brown = clampf(_brown + white * 0.02, -1.0, 1.0) * 0.998
		var breathe: float = 0.55 + 0.45 * sin(_t * TAU / 7.5) * 0.7 + 0.3 * sin(_t * TAU / 12.2 + 1.3)
		var cut: float = 0.04 + 0.1 * (_s.swell + breathe * 0.3)
		_lp += (white - _lp) * cut
		v += (_brown * 0.9 + _lp * 0.6) * (_s.surf * clampf(breathe, 0.15, 1.0) + _s.swell * 1.4) * 0.7
		# Broadcast: a mains hum with a hiss on top, nothing on it.
		if _s.hum > 0.001:
			var h := 0.0
			for j in HUM_HZ.size():
				_phase[j] = fmod(_phase[j] + HUM_HZ[j] / RATE, 1.0)
				h += sin(_phase[j] * TAU) / float(j + 1)
			_lp2 += (white - _lp2) * 0.5
			v += (h * 0.22 + (white - _lp2) * 0.12) * _s.hum
		# Dawn: one chord, soft attack, held.
		if _s.dawn > 0.001:
			var c := 0.0
			for j in DAWN_HZ.size():
				var idx := 3 + j
				_phase[idx] = fmod(_phase[idx] + DAWN_HZ[j] * (1.0 + 0.0015 * sin(_t * 0.3 + j)) / RATE, 1.0)
				c += sin(_phase[idx] * TAU) * (0.28 if j < 2 else 0.18)
			v += c * _s.dawn * 0.35
		v = clampf(v * _s.level, -1.0, 1.0)
		_gen.push_frame(Vector2(v, v))
