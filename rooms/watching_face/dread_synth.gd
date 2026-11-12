extends AudioStreamPlayer
## Procedural sound for the watching face, so the room has a voice before real audio exists.
## A sub-bass drone that swells while the face moves, a heartbeat that quickens while it
## stares, and one-shot stings. Set `motion`, `stare` and `proximity` every frame.

const RATE := 22050.0

## 0..1 inputs, set by the room.
var motion := 0.0
var stare := 0.0
var proximity := 0.0

var _playback: AudioStreamGeneratorPlayback
var _phase_a := 0.0
var _phase_b := 0.0
var _beat_clock := 0.0
var _beat_env := 0.0
var _beat_phase := 0.0
var _sting_t := -1.0
var _sting_len := 0.0
var _sting_pitch := 0.0
var _level := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	stream = gen
	volume_db = -4.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## A falling, noisy shriek: the face has moved while you weren't looking.
func sting(strength := 1.0) -> void:
	_sting_t = 0.0
	_sting_len = 0.5 + 0.4 * strength
	_sting_pitch = 420.0 + 220.0 * strength


## A deep blow: you were caught.
func slam() -> void:
	_sting_t = 0.0
	_sting_len = 1.2
	_sting_pitch = 110.0


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var dt := 1.0 / RATE
	var target_level := 0.03 + 0.3 * motion * (0.25 + 0.75 * proximity) + 0.06 * proximity
	var beat_hz := 0.9 + 1.8 * stare
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_level += (target_level - _level) * 0.0005
		# Drone: two detuned low sines that rise a little as the face closes in.
		var base := 38.0 + 14.0 * proximity
		_phase_a = fmod(_phase_a + base * dt, 1.0)
		_phase_b = fmod(_phase_b + base * 1.498 * dt, 1.0)
		var drone := (sin(TAU * _phase_a) + 0.6 * sin(TAU * _phase_b)) * _level

		# Heartbeat: lub-dub, only when it stares.
		_beat_clock += beat_hz * dt
		if _beat_clock >= 1.0:
			_beat_clock -= 1.0
		var hit := _beat_clock < dt * beat_hz * 1.5 or absf(_beat_clock - 0.22) < dt * beat_hz * 0.75
		if hit and stare > 0.05:
			_beat_env = 1.0
		_beat_env *= 0.9992
		_beat_phase = fmod(_beat_phase + 52.0 * dt, 1.0)
		var beat := sin(TAU * _beat_phase) * _beat_env * _beat_env * 0.55 * stare

		# One-shot sting.
		var sting_s := 0.0
		if _sting_t >= 0.0:
			var k := _sting_t / _sting_len
			var env := (1.0 - k) * (1.0 - k)
			var f := _sting_pitch * (1.0 - 0.7 * k)
			sting_s = (sin(TAU * f * _sting_t) * 0.5 + randf_range(-0.5, 0.5) * (1.0 - k)) * env * 0.6
			_sting_t += dt
			if _sting_t >= _sting_len:
				_sting_t = -1.0

		var s := clampf(drone + beat + sting_s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)
