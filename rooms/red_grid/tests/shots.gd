extends Node
## Renders review stills of the Red Grid through the game's real main scene (and its dither
## look, when the shader is in the project). Not a test; needs a display:
##   xvfb-run godot --rendering-driver opengl3 --path . res://rooms/red_grid/tests/shots.tscn -- --shots=DIR

const RedGrid := preload("res://rooms/red_grid/red_grid.gd")

var _dir := "user://red_grid_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.save_enabled = false
	Game.reset_story()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.set(&"start_room", &"red_grid")
	add_child(main)
	while Game.current_room == null or Game.is_travelling():
		await get_tree().process_frame
	var room := Game.current_room
	room.set(&"_vista_pupil_done", true)
	room.set(&"_vista_bowl_done", true)
	await _settle(30)

	# 1. Arrival: the eye overhead, the television, the plain to the horizon.
	await _shot("01_arrival", Vector3(0, 0, 1800), Vector3(0, 0, -1), Vector3(4.0, 3.2, 1811), Vector3(-30, 160, 1500))
	# 2. The threshold vista: a speck under the pupil.
	await _shot("02_under_the_eye", Vector3(0, 0, 1640), Vector3(0, 0, -1), Vector3(10, 22, 1720), Vector3(0, 700, 300))
	# 3. The television watching him take the first hole.
	await _shot("03_television", Vector3(10, 0, 1716), Vector3(1, 0, -0.3), Vector3(11.5, 1.5, 1722), Vector3(15, 0.5, 1712))
	# 4. Deep in the eclipse, carrying holes, a fog fall ahead.
	_carry(room, 3)
	await _shot("04_eclipse", Vector3(-120, 0, 1180), Vector3(0.1, 0, -1), Vector3(-118, 4.0, 1191), Vector3(-160, -80, 700))
	# 5. The rim: the bowl, the fog pouring down, the stare landing at the bottom.
	await _shot("05_rim", Vector3(-150, 0, 850), Vector3(0.15, 0, -1), Vector3(-158, 14.0, 872), Vector3(0, -200, 0))
	# 6. The bottom: the ring of sockets, the stare overhead.
	_carry(room, 6)
	var bp := Vector3(0, -RedGrid.SAG_DEPTH, 48)
	await _shot("06_bottom", bp, Vector3(0, 0, -1), bp + Vector3(5, 3.5, 11), Vector3(0, -150, -30))
	# 7. Close behind him at the bottom, the bowl's wall rising like a stadium.
	await _shot("07_stadium", bp, Vector3(0, 0, -1), bp + Vector3(1.5, 2.2, 6.5), Vector3(0, -120, -400))
	# 8. Five sockets filled, the cut lit between them.
	for s in 5:
		Game.player.global_position = room.sockets[s] + Vector3(room.sockets[s].x, 0, room.sockets[s].z).normalized() * 3.0
		room.interact()
	await _shot("08_ring", Vector3(0, -RedGrid.SAG_DEPTH, 46), Vector3(0, 0, -1), Vector3(30, -RedGrid.SAG_DEPTH + 26, 70), Vector3(0, -RedGrid.SAG_DEPTH, 0))

	# The mend, caught mid-flight.
	room.cinematic_speed = 1.0
	Game.player.global_position = room.sockets[5] + Vector3(room.sockets[5].x, 0, room.sockets[5].z).normalized() * 3.0
	room.interact()
	await get_tree().create_timer(3.4).timeout
	await _grab("09_circle_falls")
	await get_tree().create_timer(4.2).timeout
	await _grab("10_spring")
	await get_tree().create_timer(8.6).timeout
	await _grab("11_lid_closing")
	while room.state != RedGrid.State.MENDED:
		await get_tree().process_frame
	await _settle(20)
	var p := Game.player.global_position
	await _shot("12_mended", p, Vector3(0, 0, -1), p + Vector3(6, 4, 14), Vector3(0, 300, -400))
	get_tree().quit()


func _carry(room: Node, n: int) -> void:
	for i in room.holes.size():
		if room.carried.size() >= n:
			break
		if room.holes[i].state == RedGrid.HoleState.LOOSE:
			room.pick_up(i)


func _shot(name: String, player_at: Vector3, facing: Vector3, cam_at: Vector3, look: Vector3) -> void:
	var y := RedGrid.sag_height(Vector2(player_at.x, player_at.z), Game.current_room.sag)
	Game.player.global_position = Vector3(player_at.x, y + 0.05, player_at.z)
	Game.player.face(facing)
	Game.camera.set_process(false)
	Game.camera.global_transform = Transform3D(Basis(), cam_at).looking_at(look, Vector3.UP)
	await _settle(25)
	await _grab(name)
	Game.camera.set_process(true)


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/%s.png" % [_dir, name])
	print("shot ", name)


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
