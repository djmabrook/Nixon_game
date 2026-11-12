extends Node
## Dev only: renders a few hub frames to user:// for eyeballing. Not run by the smoke test.
## godot --path . res://hub/tests/shots.tscn -- --out=/some/dir
func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=") + "/"
	await Game.start($"../World" if has_node("../World") else _world())
	await _wait(1.0)
	await _shot(out + "hub_start.png")
	Game.player.global_position = Game.current_room.arm_point(0, 5.0)
	await _wait(2.0)
	await _shot(out + "hub_near.png")
	Game.player.global_position = Game.current_room.arm_point(0, 1.0)
	await _wait(0.6)
	await _shot(out + "hub_sinking.png")
	get_tree().quit()

func _world() -> Node3D:
	var w := Node3D.new()
	add_child(w)
	return w

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
