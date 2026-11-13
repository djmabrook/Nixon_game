class_name Player
extends CharacterBody3D
## The little man. Walks on the ground plane, relative to the camera's view.
## Rooms that break movement rules can change the exported values at runtime,
## or set `controls_enabled = false` and drive `velocity` themselves.

## Fired when the player starts or stops walking (handy for sprite animation).
signal walking_changed(is_walking: bool)

@export var move_speed := 3.5
## Speed while holding `run`. Rooms are hundreds of meters across.
@export var run_speed := 9.0
@export var acceleration := 30.0
@export var friction := 40.0
@export var gravity := 20.0
## How fast the body turns toward the walk direction (radians/second-ish).
@export var turn_speed := 14.0
## When false, input is ignored (cutscenes, rooms that take control).
@export var controls_enabled := true
## Multiplier on the input vector. A room can set it to Vector2(-1, -1) to invert controls.
@export var input_scale := Vector2.ONE

@export_group("Animation")
## Ground speed (m/s) at which the walk clip plays at 1x. Tune to stop foot sliding.
@export var walk_anim_speed := 1.75
## Ground speed (m/s) at which the run clip plays at 1x.
@export var run_anim_speed := 4.5
## Set true to drive model.play() yourself (cutscenes, climbing, being caught).
@export var animation_locked := false
@export_group("")

## Seconds the shadow trails the body. Follows Game.shadow_lag() unless a room overrides it.
@export var shadow_lag := 0.5
## When true, shadow_lag tracks Game.shadow_lag() as inks come home.
@export var shadow_lag_from_story := true

## Something else moving him (the Surfer, surf/surfer.gd). While its is_driving() is true,
## the walking physics and clips step aside and it calls driver.drive(delta) instead.
var driver: Node = null

## Last non-zero walk direction on the ground plane (unit vector, world space).
var facing := Vector3.FORWARD
var is_walking := false

@onready var visual: Node3D = $Visual
## The rigged little man. model.play(&"caught"), model.set_tint(color), etc.
@onready var model: LittleManModel = $Visual/Model
@onready var _shadow_model: LittleManModel = $ShadowCaster/Model
## Where a carried ink's object hangs. Its child is replaced when Game.carried changes.
@onready var carry_slot: Node3D = $Visual/CarrySlot
## A shadows-only copy of the body that replays where the body was `shadow_lag` seconds ago.
@onready var shadow_caster: Node3D = $ShadowCaster

var _history: Array = []  # [time, Transform3D of body, visual yaw]


func _ready() -> void:
	add_to_group(&"player")
	shadow_caster.top_level = true
	model.set_cast_shadow(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_shadow_model.set_cast_shadow(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	if shadow_lag_from_story:
		shadow_lag = Game.shadow_lag()
	Game.carried_changed.connect(_refresh_carry)
	Game.ink_home.connect(_on_ink_home)
	_refresh_carry(Game.carried)


func _on_ink_home(_ink: StringName) -> void:
	if shadow_lag_from_story:
		shadow_lag = Game.shadow_lag()


func _process(_delta: float) -> void:
	_update_shadow()


func _physics_process(delta: float) -> void:
	if driver and driver.is_driving():
		driver.drive(delta)
		return
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
	if not animation_locked:
		_animate(horizontal.length())
	if walking != is_walking:
		is_walking = walking
		walking_changed.emit(walking)


func _animate(ground_speed: float) -> void:
	var carrying := Game.carried != &""
	if ground_speed < 0.1:
		model.play(&"carry_idle" if carrying else &"idle")
	elif ground_speed > (move_speed + run_speed) * 0.5 and not carrying:
		model.play(&"run", -1.0, clampf(ground_speed / run_anim_speed, 0.5, 3.0))
	else:
		model.play(&"carry_walk" if carrying else &"walk", -1.0, clampf(ground_speed / walk_anim_speed, 0.5, 3.0))


## What the little man is holding (&"" = nothing). Same as Game.carried.
func carried_ink() -> StringName:
	return Game.carried


## Shows the carried ink's object. Uses res://props/carry/<ink>.tscn if it exists,
## otherwise a small coloured placeholder. The sprites/models thread fills props/carry/.
func _refresh_carry(ink: StringName) -> void:
	for c in carry_slot.get_children():
		c.queue_free()
	if ink == &"":
		return
	var path := "res://props/carry/%s.tscn" % ink
	if ResourceLoader.exists(path):
		carry_slot.add_child((load(path) as PackedScene).instantiate())
		return
	var mesh := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = {&"ember": Color(1, 0.35, 0.1), &"salmon": Color(1, 0.55, 0.6), &"crimson": Color(0.05, 0.02, 0.02)}.get(ink, Color.WHITE)
	if ink == &"ember":
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 3.0
	m.material = mat
	mesh.mesh = m
	carry_slot.add_child(mesh)


func _update_shadow() -> void:
	if driver and driver.is_driving():
		return   # the driver poses the late shadow itself
	var now := Time.get_ticks_msec() / 1000.0
	_history.append([now, global_transform, visual.rotation.y, model.current, model.anim.speed_scale])
	var cutoff := now - shadow_lag
	while _history.size() > 1 and _history[1][0] <= cutoff:
		_history.pop_front()
	var past: Array = _history[0]
	var xf: Transform3D = past[1]
	shadow_caster.global_transform = xf.rotated_local(Vector3.UP, past[2])
	if past[3] != &"":
		_shadow_model.play(past[3], -1.0, past[4])


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
