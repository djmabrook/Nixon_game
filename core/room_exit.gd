class_name RoomExit
extends Area3D
## A trigger volume that sends the player to another room when touched.
## Give it a CollisionShape3D child. Layer 3 (triggers), mask 2 (player).

## Where to go. "hub" returns to the spiral.
@export var target_room: StringName = &"hub"
## RoomSpawn name in the target room. Empty = the target's default spawn.
## For exits back to the hub, leave empty and it uses this room's id,
## so the player reappears at this room's door.
@export var target_spawn: StringName = &""
## If true, the exit needs the interact button while standing in it.
@export var require_interact := false
## Disabled exits do nothing (e.g. locked until the room is completed).
@export var enabled := true

var _player_inside := false


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if require_interact and _player_inside and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		trigger()


func trigger() -> void:
	if not enabled or Game.is_travelling():
		return
	var spawn := target_spawn
	if spawn == &"" and target_room == Game.HUB_ID and Game.current_room:
		spawn = Game.current_room.room_id
	Game.go_to(target_room, spawn)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_inside = true
		if not require_interact:
			trigger()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_inside = false
