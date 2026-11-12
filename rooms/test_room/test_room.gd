extends Room
## Example room. Rule broken: left is right and up is down.
## Copy rooms/_template/ to start a real room; this one exists to prove the contract works.


func _on_room_entered(_spawn: StringName) -> void:
	Game.player.input_scale = Vector2(-1, -1)
