class_name Player
extends CharacterBody3D
## The little man. Walks on the ground plane, relative to the camera's view.
## Rooms that break movement rules can change the exported values at runtime,
## or set `controls_enabled = false` and drive `velocity` themselves.

## Fired when the player starts or stops walking (handy for sprite animation).
signal walking_changed(is_walking: bool)

@export var move_speed := 5.0
## Speed while holding `run`. Rooms are hundreds of meters across.
@export var run_speed := 10.0
@export var acceleration := 30.0
@export var friction := 40.0
@export var gravity := 20.0
## How fast the body turns toward the walk direction (radians/second-ish).
@export var turn_speed := 14.0
## When false, input is ignored (cutscenes, rooms that take control).
@export var controls_enabled := true
## Multiplier on the input vector. A room can set it to Vector2(-1, -1) to invert controls.
@export var input_scale := Vector2.ONE

## Last non-zero walk direction on the ground plane (unit vector, world space).
var facing := Vector3.FORWARD
var is_walking := false

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"player")


func _physics_process(delta: float) -> void:
	var dir := get_move_direction() if controls_enabled else Vector3.ZERO
	var speed := run_speed if controls_enabled and Input.is_action_pressed(&"run") else move_speed
	var target := dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if dir != Vector3.ZERO else friction
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	if dir != Vector3.ZERO:
		facing = dir
		var target_yaw := atan2(-dir.x, -dir.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	var walking := horizontal.length() > 0.1
	if walking != is_walking:
		is_walking = walking
		walking_changed.emit(walking)


## Turn instantly to face a world direction (flattened onto the ground).
func face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	facing = direction.normalized()
	visual.rotation.y = atan2(-facing.x, -facing.z)


## Input turned into a world-space direction on the XZ plane, aligned to the camera
## so "up" on the stick always walks up the screen.
func get_move_direction() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") * input_scale
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var yaw := cam.global_rotation.y if cam else 0.0
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	return dir.limit_length(1.0)
