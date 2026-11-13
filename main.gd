extends Node
## Entry scene. Hands the World node to Game and loads the hub.
## Post-processing (the dither shader) and global UI hang off this scene, not rooms.

## For testing: start straight in a room id instead of the hub.
@export var start_room: StringName = &"hub"


func _ready() -> void:
	_capture_mouse(true)
	var override := _cmdline_room()
	Game.start($World, override if override != &"" else start_room)


func _unhandled_input(event: InputEvent) -> void:
	# Esc frees the mouse; clicking back into the window captures it again.
	if event.is_action_pressed(&"pause"):
		_capture_mouse(false)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## `godot -- --room=test_room` starts in that room.
func _cmdline_room() -> StringName:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			return StringName(arg.trim_prefix("--room="))
	return &""
