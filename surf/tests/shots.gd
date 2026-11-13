extends Node
## Dev only: renders surfing frames in the hub for review.
## xvfb-run godot --rendering-method forward_plus --path . res://surf/tests/shots.tscn -- --out=DIR
var out := "user://"
var s: Surfer


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=") + "/"
	Game.save_enabled = false
	Game.reset_story()
	Story.enabled = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _wait(2.0)
	s = Game.player.get_node("Surfer")
	s.input.touch_active = true
	# 1. On the lip, about to drop in.
	var a := 0.55
	s.place(Vector3(cos(a), 0, sin(a)) * 488.0, -Vector3(cos(a), 0, sin(a)))
	await _wait(0.25)
	await _shot("01_lip")
	# 2. Down the wall at speed, tucked.
	s.input.touch_tuck = true
	await _wait(3.2)
	await _shot("02_dropping")
	s.input.touch_tuck = false
	# 3. Carving hard across the wall.
	s.input.touch_steer = 1.0
	await _wait(0.6)
	await _shot("03_carve")
	s.input.touch_steer = 0.0
	await _wait(1.5)
	# 4. Pop off a swell: airborne.
	s.input.touch_jump = true
	await _wait(0.35)
	s.input.touch_jump = false
	await _wait(0.35)
	await _shot("04_air")
	s.input.touch_tuck = true
	await _wait(0.25)
	await _shot("05_grab")
	s.input.touch_tuck = false
	await _wait(2.0)
	# 6. Close on the stance, from the side.
	s.place(Vector3(cos(2.2), 0, sin(2.2)) * 300.0, Vector3(-sin(2.2), 0, cos(2.2)))
	s.vel = Vector3(-sin(2.2), 0, cos(2.2)) * 14.0
	await _wait(0.6)
	var at := s.pos
	Game.camera.play_shot(at + s.heading.cross(Vector3.UP) * -4.0 + Vector3.UP * 1.5 + s.heading * 1.5, at + Vector3.UP * 1.0, 2.0, 0.01)
	await _wait(0.15)
	await _shot("06_stance")
	await _wait(2.5)
	# 7. Wipeout, mid tumble.
	s.place(Vector3(cos(3.0), 0, sin(3.0)) * 780.0, Vector3(0, 0, 1))
	s.vel = Vector3(0, 0, 22)
	await _wait(0.4)
	s.wipeout(Vector3(0, 4, 6))
	await _wait(0.5)
	await _shot("07_wipeout")
	await _wait(1.2)
	await _shot("08_down")
	await _wait(3.0)
	# 9. The crater from high over the rim, swells and gates.
	Game.camera.play_shot(Vector3(620, 260, 380), Vector3(0, -40, 0), 3.0, 0.01)
	await _wait(0.3)
	await _shot("09_crater")
	get_tree().quit()


## Waits in game time (physics frames), so slow software rendering doesn't skew the shots.
func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(out + name + ".png")
	print("saved ", name, " state=", s.state if s else -1, " v=%.1f flow=%.2f" % [s.vel.length() if s else 0.0, s.flow if s else 0.0])
