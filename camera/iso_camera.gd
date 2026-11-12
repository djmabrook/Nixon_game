class_name IsoCamera
extends Camera3D
## Orthographic isometric camera that follows a target smoothly.
## Game creates one per room unless the room sets use_default_camera = false.

## The node to follow (usually Game.player).
@export var target: Node3D
## Rotation around the vertical axis, in degrees. 45 = classic isometric.
@export var yaw_degrees := 45.0:
	set(v):
		yaw_degrees = v
		_apply_angles()
## Downward tilt, in degrees.
@export var pitch_degrees := 30.0:
	set(v):
		pitch_degrees = v
		_apply_angles()
## How far back along the view direction the camera sits (doesn't change framing in ortho).
@export var distance := 30.0
## Point on the target the camera looks at.
@export var look_offset := Vector3(0, 0.6, 0)
## Higher = snappier follow. 0 = locked to target.
@export var follow_smoothing := 8.0
## Snap the focus point to a world grid of this size to reduce pixel shimmer. 0 = off.
@export var pixel_snap := 0.0

var _focus := Vector3.ZERO


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	if size <= 0.0:
		size = 12.0
	near = 0.05
	far = distance * 3.0
	_apply_angles()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var goal := target.global_position + look_offset
	if follow_smoothing <= 0.0:
		_focus = goal
	else:
		_focus = _focus.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	_place()


## Jump straight to the target with no easing (used on room entry).
func snap_to_target() -> void:
	if is_instance_valid(target):
		_focus = target.global_position + look_offset
	_place()


## True if a world point is inside the camera's view. The face boss uses this.
func is_point_visible(world_pos: Vector3, margin_px := 0.0) -> bool:
	if is_position_behind(world_pos):
		return false
	var rect := get_viewport().get_visible_rect().grow(-margin_px)
	return rect.has_point(unproject_position(world_pos))


func _apply_angles() -> void:
	rotation = Vector3(deg_to_rad(-pitch_degrees), deg_to_rad(yaw_degrees), 0.0)
	if is_inside_tree():
		_place()


func _place() -> void:
	var f := _focus
	if pixel_snap > 0.0:
		f = f.snapped(Vector3.ONE * pixel_snap)
	global_position = f + global_transform.basis.z * distance
