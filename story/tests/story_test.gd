extends Node
## Plays the whole story arc headless, fast, and checks each beat lands:
##   godot --headless --path . res://story/tests/story_test.tscn        (exit 0 = pass)
## With a display (xvfb-run ... -- --shots=DIR) it also saves stills of each beat.

var _failures := 0
var _shots := ""
var _main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	Game.set(&"save_enabled", false)
	Game.reset_story()
	Story.time_scale = 1.0 if _shots != "" else 0.08
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _run()
	print("STORY TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _run() -> void:
	# Title.
	await _until(func() -> bool: return Story.current_sequence() == &"title", 20.0)
	_check(Story.current_sequence() == &"title", "first hub load opens on the title shore")
	await _secs(2.5)
	await _shot("01_title")
	var dressing: Node = Game.current_room.get_node_or_null(^"StoryDressing")
	_check(dressing != null and dressing.is_surveyed, "hub dressed: tide, television, sound")
	_check(dressing != null and is_instance_valid(dressing.tv), "first television placed on the shore")
	var shore: Object = dressing.shore
	_check(shore.wake.distance_to(shore.pit) > 50.0, "wake spot found on the outer shore (%.0f m from the pit)" % shore.wake.distance_to(shore.pit))
	_check(not Game.player.controls_enabled, "title holds the little man")
	if _shots == "":
		await _until(func() -> bool: return Story.current_sequence() == &"opening", 10.0)
	else:
		_press_any()
		await _until(func() -> bool: return Story.current_sequence() == &"opening", 5.0)
	# Opening.
	_check(Story.current_sequence() == &"opening", "any button begins the opening")
	if _shots != "":
		await _secs(3.2); await _shot("02_last_wave")
		await _secs(6.0); await _shot("03_drained")
		await _secs(6.0); await _shot("04_stirs")
		await _secs(10.0); await _shot("05_stands")
		await _secs(8.0); await _shot("06_stray_arrives")
	await _until(func() -> bool: return Story.get_flag(Story.FLAG_OPENING_SEEN, false) and Game.player.controls_enabled, 120.0)
	_check(Story.get_flag(Story.FLAG_OPENING_SEEN, false), "opening marks itself seen")
	_check(Game.player.controls_enabled and get_viewport().get_camera_3d() == Game.camera, "control and the follow camera handed back")
	var stray := _stray()
	if stray:
		print("    stray at %.1f m, visible %s" % [stray.global_position.distance_to(Game.player.global_position), stray.visible])
	_check(stray != null and stray.visible and stray.global_position.distance_to(Game.player.global_position) < 6.0, "the Stray found him")
	_check(Game.player.visual.rotation.x == 0.0, "he is standing")
	await _shot("07_control")

	# The first television.
	var tv: Node3D = dressing.tv
	var near: Vector3 = tv.global_position + (shore.wake - tv.global_position).normalized() * 12.0
	Game.player.global_position = shore.ground(near) + Vector3.UP * 0.1
	await _until(func() -> bool: return Story.is_playing(), 5.0)
	_check(Story.get_flag(Story.FLAG_FIRST_TV_SEEN, false), "walking up to the set plays its beat")
	if _shots != "":
		await _secs(3.0); await _shot("08_tv_looms")
		await _secs(3.0); await _shot("09_tv_pov")
	await _until(func() -> bool: return not Story.is_playing(), 30.0)
	_check(Game.player.controls_enabled, "control back after the television")

	# The first descent: put him partway down the crater wall, walking toward the pit.
	var down: Vector3 = (shore.pit - shore.wake)
	down.y = 0.0
	var wall: Vector3 = shore.ground(shore.pit - down.normalized() * 150.0)
	Game.player.global_position = wall + Vector3.UP * 0.2
	Game.player.velocity = down.normalized() * 5.0
	await _until(func() -> bool: return Story.get_flag(Story.FLAG_FIRST_DESCENT_SEEN, false), 5.0)
	if Game.current_room.get_node_or_null(^"Vortex") == null:
		print("  skip the first descent (this hub has no crater)")
	else: _check(Story.get_flag(Story.FLAG_FIRST_DESCENT_SEEN, false), "the first descent plays its stadium shot (y %.0f)" % wall.y)
	if _shots != "":
		await _secs(4.0); await _shot("10_descent_stadium")
		await _secs(5.0); await _shot("11_descent_late")
	await _until(func() -> bool: return not Story.is_playing(), 40.0)
	_check(Game.player.controls_enabled, "control back after the descent")

	# The ending.
	Story.begin_ending()
	await _until(func() -> bool: return Story.current_sequence() == &"ending", 10.0)
	_check(Story.current_sequence() == &"ending", "begin_ending wakes the hub at dawn")
	if _shots != "":
		await _secs(5.0); await _shot("12_rise")
		await _secs(10.0); await _shot("13_dawn_shore")
		await _secs(12.0); await _shot("14_whole_land")
		await _secs(6.0); await _shot("15_whole_land_hold")
	await _until(func() -> bool: return Game.player.controls_enabled, 90.0)
	_check(Game.player.controls_enabled, "he walks the tideline himself")
	await _shot("16_walk_dawn")
	var ending: Node = Game.current_room.get_node_or_null(^"Story_Ending")
	var along: Vector3 = ending.shore.along
	# Walk him on until the camera lets go.
	for i in 40:
		Game.player.global_position = ending.shore.ground(Game.player.global_position + along * 1.0) + Vector3.UP * 0.05
		await get_tree().physics_frame
	await _until(func() -> bool: return ending.get(&"_phase") == &"let_go", 20.0)
	_check(ending.get(&"_phase") == &"let_go", "the camera stops following")
	if _shots != "":
		await _secs(6.0); await _shot("17_paper_frame")
	# He walks off (by himself if the stick is left alone).
	await _until(func() -> bool: return not Game.player.visual.visible, 60.0)
	_check(not Game.player.visual.visible, "he walks off the picture onto the paper")
	if _shots != "":
		await _secs(0.6); await _shot("18_on_paper")
		await _secs(3.0); await _shot("19_stray_looks_back")
		await _secs(5.0); await _shot("20_both_gone")
	await _until(func() -> bool: return Story.current_sequence() == &"title", 120.0)
	_check(Story.get_flag(Story.FLAG_ENDING_SEEN, false), "the ending is remembered")
	_check(Story.current_sequence() == &"title", "back to the title shore")
	await _secs(3.0)
	var prints := Game.current_room.find_child("LastFootprints", true, false)
	_check(prints != null, "his footprints lead off the title shore")
	await _shot("21_title_footprints")


func _stray() -> Node3D:
	for n in get_tree().get_nodes_in_group(&"stray"):
		return n
	return null


func _press_any() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)


func _secs(s: float) -> void:
	await get_tree().create_timer(s * Story.time_scale).timeout


func _until(cond: Callable, timeout: float) -> void:
	var left := timeout
	while not cond.call() and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _shot(label: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots, label])
	print("  shot ", label)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
