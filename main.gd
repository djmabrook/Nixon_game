extends Node
## Entry scene. Hands the World node to Game and loads the hub.
## Post-processing (the dither shader) and global UI hang off this scene, not rooms.

## For testing: start straight in a room id instead of the hub.
@export var start_room: StringName = &"hub"


func _ready() -> void:
	var override := _cmdline_room()
	Game.start($World, override if override != &"" else start_room)


## `godot -- --room=test_room` starts in that room.
func _cmdline_room() -> StringName:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			return StringName(arg.trim_prefix("--room="))
	return &""
