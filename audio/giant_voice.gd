class_name GiantVoice
extends AudioStreamPlayer3D
## The continuous sound of something huge: a rolling cathedral sphere, a mountain shifting,
## the fog falling down the sag. Put it on the giant thing and drive `intensity`.
##
## Everything reaches the listener late. Set `intensity` now and you hear it change
## distance / 343 m/s seconds later, so a face 600 m away keeps grinding for almost two
## seconds after it has stopped. That lag is the point: giant things sound late and low.
##
##   $Grind.intensity = face.motion        # every frame
##   $Grind.size_m = 300.0                 # lower, longer reach

## Library id of a looping sound (giant_grind, sphere_roll_loop, giant_rumble, fire_loop ...).
@export var sound_id := &"giant_grind"
## How big the thing is, in meters. Sets pitch (bigger is lower) and how far it carries.
@export var size_m := 50.0:
	set(v):
		size_m = v
		_apply_size()
## 0 = silent, 1 = full. Heard late. Smooth it yourself if it jumps.
@export_range(0.0, 1.0, 0.01) var intensity := 1.0
## Loudest level, at intensity 1.
@export_range(-40.0, 12.0, 0.5) var level_db := 0.0
## How much the pitch rises with intensity (a sphere rolling faster, stone under more strain).
@export_range(0.0, 0.5, 0.01) var pitch_with_intensity := 0.08
## Start on ready. Off if the room starts it later.
@export var start_playing := true

var _history: Array[Vector2] = []  # (time, intensity) not yet heard
var _target := 0.0                   # the intensity the listener hears now
var _heard := 0.0
var _clock := 0.0


func _ready() -> void:
	bus = &"Far"
	doppler_tracking = DOPPLER_TRACKING_DISABLED
	attenuation_model = ATTENUATION_INVERSE_DISTANCE
	attenuation_filter_cutoff_hz = 1400.0
	attenuation_filter_db = -40.0
	if stream == null and sound_id != &"":
		stream = Sound.get_loop(sound_id)
	_apply_size()
	_target = intensity
	_heard = intensity
	volume_db = -80.0
	if start_playing and stream:
		play(randf() * maxf(stream.get_length() - 0.5, 0.0))


func _process(delta: float) -> void:
	_clock += delta
	_history.append(Vector2(_clock, intensity))
	var lag := Sound.delay_for(global_position)
	while not _history.is_empty() and _history[0].x <= _clock - lag:
		_target = _history.pop_front().y
	var target := _target
	# Giant things also swell and fade slowly; nothing that size starts or stops at once.
	var rate := 1.5 / (1.0 + size_m / 60.0)
	_heard = move_toward(_heard, target, rate * delta)
	volume_db = level_db + linear_to_db(maxf(_heard, 0.0001))
	pitch_scale = Sound.giant_pitch(size_m) * (1.0 + pitch_with_intensity * (_heard - 0.5))


func _apply_size() -> void:
	unit_size = clampf(size_m * 0.6, 5.0, 400.0)
	max_distance = 0.0
