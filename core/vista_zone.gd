class_name VistaZone
extends Area3D
## Walk into it and the camera pulls far back and looks toward `look_target`,
## so the little man shrinks against something huge, then hands control back.
## Give it a CollisionShape3D child. Layer 3 (triggers), mask 2 (player).

## What the shot looks at (a landmark).
@export var look_target: Node3D
## How far back (meters) the camera pulls from the little man.
@export var pull_back := 60.0
## Seconds held on the view once it arrives.
@export var hold := 3.5
## Seconds to fly out and back.
@export var blend := 2.5
## Play only the first time per visit to the room.
@export var once := true
## Freeze the little man during the shot.
@export var freeze_player := true

var _played := false


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 << 1
	monitorable = false
	body_entered.connect(_on_body_entered)


func play() -> void:
	if not is_instance_valid(look_target) or not is_instance_valid(Game.camera) or Game.camera.is_in_shot():
		return
	_played = true
	var player := Game.player
	if freeze_player and player:
		player.controls_enabled = false
	await Game.camera.play_vista(look_target.global_position, pull_back, hold, blend)
	if freeze_player and is_instance_valid(player):
		player.controls_enabled = true


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not (once and _played):
		play()
