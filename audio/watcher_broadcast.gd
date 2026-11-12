class_name WatcherBroadcast
extends Node3D
## The Watcher's only sound: a broadcast with nothing on it. Never a voice.
##
## Three layers, all on the Broadcast bus:
##   hum    mains hum through a dead set. Always there while he is present. It pulses
##          like a slow heart when he stares, faster the harder he looks.
##   hiss   snow, a channel with no signal. Rises with the stare.
##   tone   the held test tone. Only when he truly has you.
##
## Use one on every watching television (spatial, small) and one for the Watcher himself
## (not spatial: on the mountain he is the sky). Drive `presence` and `stare` each frame.
## When `drains_world` is on, the stare also drains the rest of the mix (Sound.set_stare).
##
##   broadcast.presence = proximity
##   broadcast.stare = face.stare
##   await broadcast.close_eyes(4.0)       # the lids come down; then there is nothing

signal eyes_closed

## Positioned in the world (a television) or everywhere at once (the Watcher as sky).
@export var spatial := true
## Meters at full volume when spatial. A television is ~3, the mountain face ~200.
@export var unit_size := 4.0
## 0..1: how present he is. Distance to the set, how much of the face fills the sky.
@export_range(0.0, 1.0, 0.01) var presence := 1.0
## 0..1: how hard he is looking at the little man right now.
@export_range(0.0, 1.0, 0.01) var stare := 0.0
## The stare also drains colour from the rest of the mix (only one broadcast should do this).
@export var drains_world := false
## A set that powers off with a CRT sound when its eyes close.
@export var is_television := true
@export_group("Levels")
@export_range(-40.0, 6.0, 0.5) var hum_db := -6.0
@export_range(-40.0, 6.0, 0.5) var hiss_db := -12.0
@export_range(-40.0, 6.0, 0.5) var tone_db := -22.0

var eyes_open := true

var _hum: Node
var _hiss: Node
var _tone: Node
var _beat_phase := 0.0
var _closing := 0.0      # 0 open .. 1 closed
var _smoothed_stare := 0.0


func _ready() -> void:
	_hum = _layer(&"broadcast_hum")
	_hiss = _layer(&"broadcast_hiss")
	_tone = _layer(&"broadcast_tone")


func _exit_tree() -> void:
	if drains_world:
		Sound.set_stare(0.0)


func _process(delta: float) -> void:
	_smoothed_stare = move_toward(_smoothed_stare, stare if eyes_open else 0.0, delta * 2.5)
	var s := _smoothed_stare
	var open := 1.0 - _closing
	var p := presence * open

	# A heart in the hum: lub-dub, 48 bpm unwatched to 130 bpm under the full stare.
	var bpm := lerpf(48.0, 130.0, s)
	_beat_phase = fmod(_beat_phase + delta * bpm / 60.0, 1.0)
	var lub := exp(-pow((_beat_phase - 0.0) / 0.06, 2.0)) + exp(-pow((_beat_phase - 1.0) / 0.06, 2.0))
	var dub := 0.7 * exp(-pow((_beat_phase - 0.28) / 0.06, 2.0))
	var beat := 1.0 + (lub + dub) * 0.9 * s

	_set_level(_hum, hum_db, p * (0.55 + 0.45 * s) * beat)
	_set_level(_hiss, hiss_db, p * (0.1 + 0.9 * pow(s, 1.5)))
	_set_level(_tone, tone_db, p * smoothstep(0.55, 1.0, s))
	# Spin-down as the eyes close: the set winds down like a transformer losing power.
	var pitch := lerpf(1.0, 0.45, _closing * _closing)
	_tone.pitch_scale = pitch
	_hum.pitch_scale = lerpf(1.0, 0.6, _closing)
	if drains_world:
		Sound.set_stare(s * presence * open)


## The lids come down: the tone bends and falls, the hum winds down, the snow stops.
## A television also powers off. Await it if the next beat must wait for the silence.
func close_eyes(time := 3.0) -> void:
	if not eyes_open:
		return
	eyes_open = false
	var t := create_tween()
	t.tween_property(self, "_closing", 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	if is_television:
		if spatial:
			Sound.play_at(&"tv_off", global_position, -4.0, 1.0, {"unit_size": unit_size})
		else:
			Sound.play(&"tv_off", -4.0)
	for layer in [_hum, _hiss, _tone]:
		layer.stop()
	if drains_world:
		Sound.set_stare(0.0)
	eyes_closed.emit()


## Wake the set again (a rewind, a fresh room).
func open_eyes(time := 1.0) -> void:
	if eyes_open:
		return
	eyes_open = true
	if is_television:
		if spatial:
			Sound.play_at(&"tv_on", global_position, -6.0, 1.0, {"unit_size": unit_size})
		else:
			Sound.play(&"tv_on", -6.0)
	for layer in [_hum, _hiss, _tone]:
		layer.play(randf() * 4.0)
	create_tween().tween_property(self, "_closing", 0.0, time)


## A flicker of interference: the set catching sight of him, or losing him.
func glitch(volume_db := -8.0) -> void:
	if spatial:
		Sound.play_at(&"static_burst", global_position, volume_db, randf_range(0.9, 1.15), {"unit_size": unit_size})
	else:
		Sound.play(&"static_burst", volume_db, randf_range(0.9, 1.15))


func _layer(id: StringName) -> Node:
	var p: Node
	if spatial:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = unit_size
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.attenuation_filter_cutoff_hz = 4000.0
		p3.attenuation_filter_db = -18.0
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.stream = Sound.get_loop(id)
	p.bus = &"Broadcast"
	p.volume_db = -80.0
	add_child(p)
	p.play(randf() * 4.0)
	return p


static func _set_level(p: Node, db: float, amount: float) -> void:
	p.volume_db = db + linear_to_db(maxf(amount, 0.00001))
