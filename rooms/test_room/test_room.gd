extends Room
## Example room. Rule broken: left is right and up is down.
## Mend: walk to the foot of the monolith. The television closes its eyes and the
## little man carries the room's ink (gives_ink) back to the hub.
## Copy rooms/_template/ to start a real room; this one exists to prove the contract works.

@export var mend_radius := 30.0


func _on_room_entered(_spawn: StringName) -> void:
	Game.player.input_scale = Vector2(-1, -1)


func _physics_process(_delta: float) -> void:
	if Game.is_completed(room_id) or not is_instance_valid(Game.player):
		return
	var to: Vector3 = Game.player.global_position - ($Landmark as Node3D).global_position
	if Vector2(to.x, to.z).length() < mend_radius:
		complete()
