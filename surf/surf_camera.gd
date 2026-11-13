class_name SurfCameraRig
extends Node
## Drives the room's FollowCamera while he surfs: a chase camera that swings in behind his
## line, drops its gaze down the face he's about to ride, pulls back and looks for the ground
## in the air, and widens with speed until the dunes stretch. Shake on landings and crashes,
## a punch on boosts, a lean into carves. Mouse / right stick look around and it eases back.
## Story shots (camera.play_shot) still win: the rig steps aside while one plays.

var surfer: Surfer
var camera: FollowCamera

@export var rest_distance := 6.2
@export var speed_distance := 10.5
@export var air_distance := 2.0
@export var rest_fov := 64.0
@export var speed_fov := 92.0
## Speed (m/s) at which distance and FOV reach their fast values.
@export var full_speed := 50.0
@export var height := 1.9
@export var mouse_sensitivity := 0.0028
@export var stick_speed := 2.6
## Seconds after you last looked before it eases back behind him.
@export var look_return_delay := 1.1

var _yaw := 0.0
var _pitch := -0.18
var _dist := 6.2
var _fov := 64.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _idle := 10.0
var _trauma := 0.0
var _punch := 0.0
var _roll := 0.0
var _pos := Vector3.ZERO
var _aim := Vector3.ZERO
var _t := 0.0
var _started := false
var _noise := FastNoiseLite.new()


func _ready() -> void:
	process_priority = 100   # after FollowCamera has placed itself, so we have the last word
	_noise.frequency = 1.0
	_noise.seed = 3
	if camera and surfer and surfer.fx:
		surfer.fx.attach_speed_lines(camera)


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func punch(amount: float) -> void:
	_punch = clampf(_punch + amount * 0.6, 0.0, 14.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_look_yaw -= m.relative.x * mouse_sensitivity
		_look_pitch -= m.relative.y * mouse_sensitivity
		_idle = 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(surfer) or not surfer.is_driving():
		return
	if camera.is_in_shot():
		_started = false
		return
	_t += delta
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		_look_yaw -= stick.x * stick_speed * delta
		_look_pitch -= stick.y * stick_speed * delta
		_idle = 0.0
	_idle += delta
	_look_pitch = clampf(_look_pitch, -0.9, 0.8)
	if _idle > look_return_delay:
		var k := 1.0 - exp(-2.2 * delta)
		_look_yaw = lerp_angle(_look_yaw, 0.0, k)
		_look_pitch = lerpf(_look_pitch, 0.0, k)

	var st := surfer.state
	var wiped := st == Surfer.State.WIPEOUT or st == Surfer.State.RECOVER
	var at := surfer.render_position()
	if st == Surfer.State.WIPEOUT and surfer.ragdoll:
		at = surfer.ragdoll.center()
	var v := surfer.vel
	var hv := Vector2(v.x, v.z)
	var sp := v.length()
	var t_speed := clampf(sp / full_speed, 0.0, 1.0)

	# Where to look from: behind the line of travel.
	var want_yaw := _yaw
	if not wiped:
		if hv.length() > 3.0:
			want_yaw = atan2(-hv.x, -hv.y)
		else:
			want_yaw = atan2(-surfer.heading.x, -surfer.heading.z)
	var yaw_rate := lerpf(2.2, 4.5, t_speed) * (0.55 if st == Surfer.State.AIR else 1.0) * (0.15 if wiped else 1.0)
	# Pitch: gaze follows the slope he's on (down a face, the camera looks down it).
	var slope_ang := atan2(v.y, maxf(hv.length(), 0.1))
	var want_pitch := -0.17 + clampf(slope_ang, -0.9, 0.6) * 0.5
	if st == Surfer.State.AIR:
		var ground := surfer.terrain.height(Vector2(at.x, at.z))
		want_pitch -= clampf((at.y - ground) / 25.0, 0.0, 0.45)
	if wiped:
		want_pitch = -0.32
	var want_dist := lerpf(rest_distance, speed_distance, t_speed)
	if st == Surfer.State.AIR:
		want_dist += air_distance * clampf(surfer.airtime * 1.5, 0.0, 1.0)
	if wiped:
		want_dist = 7.5
	var want_fov := lerpf(rest_fov, speed_fov, pow(t_speed, 1.2)) + _punch
	if wiped:
		want_fov = rest_fov - 6.0
	_punch = move_toward(_punch, 0.0, delta * 10.0)

	if not _started:
		_yaw = want_yaw
		_pitch = want_pitch
		_dist = want_dist
		_fov = camera.fov
		_started = true
	_yaw = lerp_angle(_yaw, want_yaw, 1.0 - exp(-yaw_rate * delta))
	_pitch = lerpf(_pitch, want_pitch, 1.0 - exp(-3.0 * delta))
	_dist = lerpf(_dist, want_dist, 1.0 - exp(-2.5 * delta))
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-4.0 * delta))

	var yaw := _yaw + _look_yaw
	var pitch := clampf(_pitch + _look_pitch, -1.2, 0.6)
	var orbit := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pivot := at + Vector3.UP * height
	var want_pos := pivot + orbit.z * _dist
	# Keep above the sand (swells included) along the way.
	var g := surfer.terrain.height(Vector2(want_pos.x, want_pos.z)) + 1.3
	if want_pos.y < g:
		want_pos.y = g
	var mid := (pivot + want_pos) * 0.5
	var gm := surfer.terrain.height(Vector2(mid.x, mid.z)) + 1.0
	if mid.y < gm:
		want_pos.y += (gm - mid.y) * 2.0
	_pos = want_pos if _pos == Vector3.ZERO else _pos.lerp(want_pos, 1.0 - exp(-16.0 * delta))
	# Look a little ahead of him along his line and above, so he sits low in frame.
	var lead := _flat3(v) * clampf(sp * 0.12, 0.0, 6.0)
	var aim_to := at + Vector3.UP * (height + 0.6) + lead
	_aim = aim_to if _aim == Vector3.ZERO else _aim.lerp(aim_to, 1.0 - exp(-14.0 * delta))
	var xf := Transform3D(Basis(), _pos).looking_at(_aim, Vector3.UP)
	# Lean into carves.
	_roll = lerpf(_roll, -surfer.carve * 0.07 * t_speed, 1.0 - exp(-4.0 * delta))
	xf.basis = xf.basis * Basis(Vector3.BACK, _roll)
	# Shake: trauma squared, plus a rumble at very high speed on the ground.
	var floor_trauma := clampf((sp - 32.0) / 60.0, 0.0, 0.2) if st == Surfer.State.RIDE else 0.0
	_trauma = maxf(_trauma - delta * 1.4, 0.0)
	var tr := maxf(_trauma, floor_trauma)
	var s := tr * tr
	if s > 0.0001:
		var n := _t * 28.0
		xf.origin += xf.basis * Vector3(_noise.get_noise_2d(n, 0.0), _noise.get_noise_2d(0.0, n), 0.0) * s * 0.45
		xf.basis = xf.basis * Basis.from_euler(Vector3(_noise.get_noise_2d(n, 50.0), _noise.get_noise_2d(50.0, n), _noise.get_noise_2d(n, n)) * s * 0.06)
	camera.global_transform = xf
	camera.fov = _fov
	# Keep FollowCamera's own numbers close, so a story shot returns to about here.
	camera.yaw_degrees = rad_to_deg(yaw)
	camera.pitch_degrees = rad_to_deg(pitch)
	camera.distance = _dist


static func _flat3(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 0.01 else Vector3.ZERO
