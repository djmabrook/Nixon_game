class_name FollowCamera
extends Camera3D
## Third-person orbiting camera. Perspective, long draw distance, built for scale:
## the little man stays small in frame and the world stays big.
## Game creates one per room unless the room sets use_default_camera = false.
##
## Controls: mouse or right stick orbits. Holding `focus` turns the view toward the
## room's focus target (its landmark). When the player walks without touching the
## camera, it drifts back behind them.

## The node to follow (usually Game.player).
@export var target: Node3D
## Point on the target the camera orbits around (roughly the little man's head).
@export var pivot_offset := Vector3(0, 1.5, 0)

@export_group("Orbit")
## Distance from the pivot, in meters.
@export var distance := 7.0
## Horizontal angle in degrees. 0 looks toward -Z.
@export var yaw_degrees := 0.0
## Vertical angle in degrees. Negative looks down on the player.
@export var pitch_degrees := -6.0
@export var min_pitch := -70.0
@export var max_pitch := 35.0
@export var mouse_sensitivity := 0.15
## Degrees per second at full stick.
@export var stick_speed := 140.0
@export var invert_y := false
## Extra upward tilt after orbiting, so the horizon sits low and the little man
## sits in the lower third with the sky and landmarks above him.
@export var frame_tilt_degrees := 12.0

@export_group("Feel")
## Higher = tighter follow of the player's position.
@export var follow_smoothing := 10.0
## Seconds without camera input before it drifts behind a walking player. 0 = never.
@export var recenter_delay := 1.5
## How quickly it drifts behind the player.
@export var recenter_speed := 1.2
## Physics layers the camera won't pass through (layer 1 = world).
@export_flags_3d_physics var collision_mask := 1

@export_group("Focus")
## What `focus` turns toward (a room's landmark). Rooms set this through Room.focus_target.
@export var focus_target: Node3D
## Turn speed while focusing.
@export var focus_speed := 4.0
## FOV while focusing (a slight zoom).
@export var focus_fov := 45.0

var _pivot := Vector3.ZERO
var _idle_time := 0.0
var _base_fov := 60.0
var _shot_active := false


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	_base_fov = fov
	if far < 1000.0:
		far = 4000.0
	near = 0.1


func _unhandled_input(event: InputEvent) -> void:
	if _shot_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		yaw_degrees -= m.relative.x * mouse_sensitivity
		pitch_degrees += m.relative.y * mouse_sensitivity * (1.0 if invert_y else -1.0)
		pitch_degrees = clampf(pitch_degrees, min_pitch, max_pitch)
		_idle_time = 0.0


func _process(delta: float) -> void:
	if _shot_active or not is_instance_valid(target):
		return
	var goal := target.global_position + pivot_offset
	_pivot = _pivot.lerp(goal, 1.0 - exp(-follow_smoothing * delta)) if follow_smoothing > 0.0 else goal

	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		yaw_degrees -= look.x * stick_speed * delta
		pitch_degrees += look.y * stick_speed * delta * (1.0 if invert_y else -1.0)
		_idle_time = 0.0
	else:
		_idle_time += delta

	var focusing := Input.is_action_pressed(&"focus") and is_instance_valid(focus_target)
	if focusing:
		_turn_toward(focus_target.global_position, focus_speed * delta)
		_idle_time = 0.0
	elif recenter_delay > 0.0 and _idle_time > recenter_delay:
		_recenter_behind_target(delta)
	fov = lerpf(fov, focus_fov if focusing else _base_fov, 1.0 - exp(-6.0 * delta))

	pitch_degrees = clampf(pitch_degrees, min_pitch, max_pitch)
	_place()


## Jump straight into position with no easing (used on room entry).
func snap_to_target() -> void:
	if is_instance_valid(target):
		_pivot = target.global_position + pivot_offset
	_place()


## Point the orbit so the camera looks from behind the target toward `world_pos`.
func face_toward(world_pos: Vector3) -> void:
	_turn_toward(world_pos, 1.0)
	_place()


## A cinematic shot: fly to `from`, look at `look_at_pos`, hold, then return to the orbit.
## Player input to the camera is ignored during the shot. Await it if you need to.
func play_shot(from: Vector3, look_at_pos: Vector3, hold := 3.0, blend := 1.5) -> void:
	_shot_active = true
	var start := global_transform
	var end := Transform3D(Basis(), from).looking_at(look_at_pos, Vector3.UP)
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(w: float): global_transform = start.interpolate_with(end, w), 0.0, 1.0, blend)
	t.tween_interval(hold)
	await t.finished
	var back := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	back.tween_method(func(w: float): global_transform = end.interpolate_with(_orbit_transform(), w), 0.0, 1.0, blend)
	await back.finished
	_shot_active = false


## Changes the resting FOV (focus zooms in from it).
func set_base_fov(value: float) -> void:
	_base_fov = value
	fov = value


## A vista: pull far back and up from the little man and look toward `look_target`,
## so he shrinks to a few pixels against it, then return. VistaZone calls this.
func play_vista(look_target: Vector3, pull_back := 60.0, hold := 3.5, blend := 2.5) -> void:
	if not is_instance_valid(target):
		return
	var me := target.global_position
	var dir := look_target - me
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else -global_basis.z
	var from := me - dir * pull_back + Vector3.UP * pull_back * 0.2
	await play_shot(from, look_target, hold, blend)


func is_in_shot() -> bool:
	return _shot_active


## True if a world point is in view (inside the frustum and on screen). The face boss uses this.
## It doesn't check occlusion; raycast yourself if walls should block sight.
func is_point_visible(world_pos: Vector3, margin_px := 0.0) -> bool:
	if is_position_behind(world_pos) or not is_position_in_frustum(world_pos):
		return false
	var rect := get_viewport().get_visible_rect().grow(-margin_px)
	return rect.has_point(unproject_position(world_pos))


func _turn_toward(world_pos: Vector3, weight: float) -> void:
	var to := world_pos - _pivot
	if to.length_squared() < 0.001:
		return
	var want_yaw := rad_to_deg(atan2(-to.x, -to.z))
	var flat := Vector2(to.x, to.z).length()
	var want_pitch := clampf(rad_to_deg(atan2(to.y, flat)) * 0.6, min_pitch, max_pitch)
	yaw_degrees = rad_to_deg(lerp_angle(deg_to_rad(yaw_degrees), deg_to_rad(want_yaw), clampf(weight, 0.0, 1.0)))
	pitch_degrees = lerpf(pitch_degrees, want_pitch, clampf(weight, 0.0, 1.0))


func _recenter_behind_target(delta: float) -> void:
	var player := target as Player
	if player == null or not player.is_walking:
		return
	var want_yaw := rad_to_deg(atan2(-player.facing.x, -player.facing.z))
	yaw_degrees = rad_to_deg(lerp_angle(deg_to_rad(yaw_degrees), deg_to_rad(want_yaw), clampf(recenter_speed * delta, 0.0, 1.0)))


func _orbit_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0))
	var want := _pivot + basis.z * distance
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(_pivot, want, collision_mask)
		if target is CollisionObject3D:
			q.exclude = [(target as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = hit.position + (hit.normal as Vector3) * 0.3
	var aim := basis * Basis(Vector3.RIGHT, deg_to_rad(frame_tilt_degrees))
	return Transform3D(aim, want)


func _place() -> void:
	global_transform = _orbit_transform()
