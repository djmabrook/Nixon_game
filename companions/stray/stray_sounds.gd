class_name StraySounds
extends RefCounted
## The Stray's fallback tick, synthesized, for when the Sound autoload (audio/) is not in
## the project. The Stray never vocalises; a cursor tick is its only sound.

const RATE := 22050


## A small tap as it lands from a hop.
static func tick() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(RATE * 0.025)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * 1700.0 * t) * exp(-t * 520.0) * 0.4 + (rng.randf() * 2.0 - 1.0) * exp(-t * 2200.0) * 0.25
	return _wav(s)


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
