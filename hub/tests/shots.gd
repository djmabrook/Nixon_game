extends Node
## Dev only: renders hub frames for eyeballing. Not run by the smoke test.
## godot --rendering-driver opengl3 --path . res://hub/tests/shots.tscn -- --out=DIR --state=S
## States: drained (default), planting (ember coming home), full (three inks, eye open), dawn.
var out := "user://"
var state := "drained"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=") + "/"
		if a.begins_with("--state="):
			state = a.trim_prefix("--state=")
	Game.save_enabled = false
	Game.reset_story()
	match state:
		"planting":
			Game.carry(&"ember")
		"full", "dawn":
			Game.inks_home.assign([&"ember", &"salmon", &"crimson"])
			Game.set_meta(&"hub_shown_inks", [&"ember", &"salmon", &"crimson"])
			Game.set_meta(&"hub_eye_open", true)
			if state == "dawn":
				Game.set_flag(&"dawn", true)
	_add_dither()
	var w := Node3D.new()
	add_child(w)
	await Game.start(w)
	var hub = Game.current_room
	if state == "planting":
		await _wait(5.0)
		await _shot("planting_fill")
		await _wait(5.0)
		await _shot("planting_ember")
		get_tree().quit()
		return
	await _wait(1.5)
	await _shot(state + "_beach")
	# The arch, from where you arrive.
	var arch: Vector3 = hub.get_node("Art/StrataArch").global_position
	var adir := Vector3(arch.x, 0, arch.z).normalized()
	var side := adir.cross(Vector3.UP)
	Game.camera.play_shot(arch + adir * 70.0 + side * 90.0 + Vector3(0, 10, 0), arch + Vector3(0, 35, 0), 1.5, 0.1)
	await _wait(1.0)
	await _shot(state + "_arch")
	await _wait(1.0)
	# The stone little man, from just behind him, looking where he looks.
	var stone: Node3D = hub.get_node("Art/StoneLittleMan")
	var sf := stone.global_basis.z
	Game.camera.play_shot(stone.global_position - sf * 4.5 + Vector3(1.2, 1.6, 0), stone.global_position + sf * 60.0 + Vector3(0, 12, 0), 1.5, 0.05)
	await _wait(1.0)
	await _shot(state + "_stone")
	await _wait(1.0)
	await _at(hub, 495.0, state + "_rim")
	# The door at the end of groove 0, from in front of it.
	var door: Vector3 = hub.stakes()[0].global_position
	var dir := Vector3(door.x, 0, door.z).normalized()
	Game.camera.play_shot(door - dir * 120.0 + Vector3(0, 14, 0), door + Vector3(0, 22, 0), 6.0, 0.1)
	await _wait(1.5)
	await _shot(state + "_door")
	# From above the crest, out across the crater toward the Watcher.
	var wp: Vector3 = hub.get_node("Landmarks").watcher_position()
	var away := -Vector3(wp.x, 0, wp.z).normalized() * 520.0 + Vector3(0, 150, 0)
	Game.camera.play_shot(away, wp + Vector3(0, 250, 0), 6.0, 0.1)
	await _wait(1.5)
	await _shot(state + "_watcher")
	Game.camera.play_shot(hub.get_node("Vortex").global_position + Vector3(260, 300, 260), hub.get_node("Vortex").global_position, 5.0, 0.5)
	await _wait(1.5)
	await _shot(state + "_eye")
	get_tree().quit()

func _at(hub, r: float, name: String, wait := 3.0) -> void:
	Game.player.global_position = hub.arm_point(0, r) + Vector3.UP * 0.5
	Game.camera.face_toward(hub.get_node("Vortex/FocusPoint").global_position)
	await _wait(wait)
	await _shot(name)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)


## The game's dither pass, when the dither look (shaders/, PR #2) is in this checkout.
func _add_dither() -> void:
	if not ResourceLoader.exists("res://shaders/dither_look.tscn"):
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var d: Node = load("res://shaders/dither_look.tscn").instantiate()
	d.set("follow_rooms", false)
	var preset := {"drained": "hub_inks_0", "planting": "hub_inks_1", "full": "hub_inks_3", "dawn": "dawn"}.get(state, "hub_inks_0") as String
	var path := "res://shaders/presets/%s.tres" % preset
	if ResourceLoader.exists(path):
		d.set("look", load(path))
	layer.add_child(d)
