extends Room
## The Watching Face. Rule broken: things only move when nobody is looking.
##
## A giant face hangs over a purple grid between the little man and a black disc at the far end.
## While the face is on screen it is frozen. Off screen, it drifts after him. Its own stare
## slows him to a crawl, so he crosses the grid by turning the camera (interact) to keep it
## in view and by slipping behind pillars to break its line of sight. If it reaches him,
## the room resets. Reaching the disc completes the room.

## Degrees the camera turns per press of interact.
@export var camera_turn_degrees := 90.0
@export var camera_turn_time := 0.5
## Player speed multiplier at full stare.
@export_range(0.1, 1.0) var stare_slow := 0.45
## Seconds after a catch before the room resets.
@export var catch_reset_delay := 0.9

@onready var face: FaceBoss = $FaceBoss
@onready var goal: Area3D = $Goal
@onready var goal_ring: Node3D = $Goal/Ring
@onready var floor_mat: ShaderMaterial = $Floor/Mesh.material_override
@onready var vignette_mat: ShaderMaterial = $Screen/Vignette.material
@onready var synth: AudioStreamPlayer = $Synth

var _base_speed := 4.0
var _turn_tween: Tween
var _target_yaw := 0.0
var _shake := 0.0
var _flash := 0.0
var _done := false


func _ready() -> void:
	# Each room instance gets its own copies so state never leaks across reloads.
	floor_mat = floor_mat.duplicate()
	$Floor/Mesh.material_override = floor_mat
	vignette_mat = vignette_mat.duplicate()
	$Screen/Vignette.material = vignette_mat


func _on_room_entered(_spawn: StringName) -> void:
	_base_speed = Game.player.move_speed
	face.caught_player.connect(_on_caught)
	face.revealed.connect(_on_revealed)
	goal.body_entered.connect(_on_goal_body_entered)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and not _done:
		get_viewport().set_input_as_handled()
		turn_camera(1.0)


## Swing the camera a quarter turn around the little man. `dir` is +1 or -1.
func turn_camera(dir: float) -> void:
	if not is_instance_valid(Game.camera):
		return
	if not (_turn_tween and _turn_tween.is_running()):
		_target_yaw = Game.camera.yaw_degrees
	# Presses chain: each one adds a quarter turn to wherever the camera is heading.
	_target_yaw += camera_turn_degrees * dir
	if _turn_tween:
		_turn_tween.kill()
	_turn_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_property(Game.camera, "yaw_degrees", _target_yaw, camera_turn_time)


func _process(delta: float) -> void:
	var player := Game.player
	if not is_instance_valid(player) or not is_instance_valid(face):
		return

	# Its stare weighs the little man down.
	if player.controls_enabled:
		player.move_speed = _base_speed * lerpf(1.0, stare_slow, face.stare)

	var dist := Vector2(face.global_position.x - player.global_position.x,
			face.global_position.z - player.global_position.z).length()
	var proximity := clampf(1.0 - (dist - face.catch_radius) / 14.0, 0.0, 1.0)

	floor_mat.set_shader_parameter(&"face_pos", face.global_position)
	floor_mat.set_shader_parameter(&"face_motion", face.motion)
	floor_mat.set_shader_parameter(&"stare", face.stare)

	_flash = move_toward(_flash, 0.0, delta * 2.5)
	vignette_mat.set_shader_parameter(&"stare", maxf(face.stare, proximity * 0.5))
	vignette_mat.set_shader_parameter(&"flash", _flash)

	synth.motion = face.motion
	synth.stare = face.stare
	synth.proximity = proximity

	goal_ring.rotate_y(delta * 0.8)

	_apply_shake(delta, proximity)

	if player.global_position.y < -8.0 and not Game.is_travelling():
		_reset()


func _apply_shake(delta: float, proximity: float) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	_shake = move_toward(_shake, 0.0, delta * 1.8)
	# A faint constant tremor as it gets close, on top of event shakes.
	var amount := _shake * _shake * 0.5 + proximity * proximity * 0.04 * face.motion
	cam.h_offset = randf_range(-amount, amount)
	cam.v_offset = randf_range(-amount, amount)


func _on_revealed(distance: float) -> void:
	var strength := clampf(distance / 8.0, 0.2, 1.0)
	_shake = maxf(_shake, 0.35 + 0.4 * strength)
	_flash = maxf(_flash, 0.25 * strength)
	synth.sting(strength)


func _on_caught() -> void:
	if _done:
		return
	_done = true
	Game.player.controls_enabled = false
	Game.player.velocity = Vector3.ZERO
	face.lunge()
	synth.slam()
	_shake = 1.0
	_flash = 0.9
	await get_tree().create_timer(catch_reset_delay).timeout
	_reset()


func _on_goal_body_entered(body: Node3D) -> void:
	if not body is Player or _done:
		return
	_done = true
	face.retreat()
	complete()
	_flash = 0.6
	synth.sting(0.3)
	Game.player.move_speed = _base_speed
	await get_tree().create_timer(0.8).timeout
	exit_to_hub()


func _reset() -> void:
	Game.go_to(room_id, &"from_hub")
