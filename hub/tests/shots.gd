extends Node
## Dev only: renders hub frames for eyeballing. Not run by the smoke test.
## godot --rendering-driver opengl3 --path . res://hub/tests/shots.tscn -- --out=/some/dir
var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=") + "/"
	var w := Node3D.new()
	add_child(w)
	await Game.start(w)
	var hub = Game.current_room
	await _wait(1.5)
	await _shot("1_beach")
	await _at(hub, 700.0, "2_dune_climb")
	await _at(hub, 506.0, "3_rim_vista", 5.0, false)
	await _wait(6.0)
	await _at(hub, 495.0, "4_on_rim")
	await _at(hub, 200.0, "5_crater_wall")
	await _at(hub, 90.0, "6_above_pit")
	get_tree().quit()

func _at(hub, r: float, name: String, wait := 3.0, face := true) -> void:
	Game.player.global_position = hub.arm_point(0, r) + Vector3.UP * 0.5
	if face:
		Game.camera.face_toward(hub.get_node("Vortex/FocusPoint").global_position)
	await _wait(wait)
	await _shot(name)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)
