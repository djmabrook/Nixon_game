extends Node
## Headless check for the spiral hub. Run before every hub PR, next to the smoke test:
##   godot --headless --path . res://hub/tests/hub_test.tscn   (exit code 0 = pass)
## Walks the little man down every room's groove into the pit and checks he lands in
## that room, then comes back out at that room's groove.

var _failures := 0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func():
		print("HUB TEST: FAIL (timed out)")
		get_tree().quit(1))
	Game.save_enabled = false
	Game.reset_story()
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	var hub: Room = Game.current_room
	var ids: Array[StringName] = hub.get("_ids")
	_check(ids.size() > 0, "at least one room discovered")
	var vortex = hub.get_node("Vortex")

	# Every arm's rim angle maps back to its own room, and every room has a return spawn.
	for i in ids.size():
		if not hub.room_open(ids[i]):
			continue   # locked rooms have no groove yet (checked in _story_checks)
		var rim: Vector3 = hub.arm_point(i, hub.pit_radius)
		_check(vortex.room_at_angle(atan2(rim.z, rim.x)) == ids[i], "rim slice %d -> %s" % [i, ids[i]])
		_check(hub.get_spawn(ids[i]).name == String(ids[i]), "return spawn for %s" % ids[i])

	# The arrival spot stands on the sand, and the player stays on it.
	for i in 10:
		await get_tree().physics_frame
	_check(Game.player.is_on_floor(), "player stands on the sand")

	for i in ids.size():
		var id := ids[i]
		if not Game.current_room.room_open(id):
			continue
		if Game.current_room.room_id != Game.HUB_ID:
			await Game.go_to_hub()
		hub = Game.current_room
		var start: Vector3 = hub.arm_point(i, hub.pit_radius + 3.0)
		Game.player.global_position = start + Vector3.UP * 0.1
		# Walk inward along the groove until the pit takes him.
		var target: Vector3 = hub.arm_point(i, 0.2)
		for f in 240:
			if Game.is_travelling() or Game.current_room != hub:
				break
			Game.player.global_position = Game.player.global_position.move_toward(target, 0.12)
			await get_tree().physics_frame
		while Game.is_travelling() or Game.current_room == hub:
			await get_tree().process_frame
			if Game.current_room == hub and not Game.is_travelling() and not hub.get("_sinking"):
				break
		_check(Game.current_room.room_id == id, "groove %d leads into %s" % [i, id])

		Game.current_room.exit_to_hub()
		while Game.is_travelling() or Game.current_room.room_id != Game.HUB_ID:
			await get_tree().process_frame
		var back := Game.current_room.get_spawn(id)
		_check(Game.player.global_position.distance_to(back.global_position) < 0.05, "%s returns to its groove" % id)
		# He must not be dragged straight back in while standing still.
		for f in 360:
			await get_tree().physics_frame
		_check(Game.current_room.room_id == Game.HUB_ID and not Game.is_travelling(), "%s: idle player is not swallowed again" % id)

	await _story_checks()
	print("HUB TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


## Story states, driven through Game's ink API. test_room gives ember. If a locked room
## needing all three inks exists (copy tools/fixtures/locked_room.tscn to
## rooms/zz_mountain/room.tscn to try it), its groove is checked too.
func _story_checks() -> void:
	Engine.time_scale = 10.0
	if Game.current_room.room_id != Game.HUB_ID:
		await Game.go_to_hub()
	var hub: Room = Game.current_room
	var story = hub.get_node("InkState")
	var mat: ShaderMaterial = hub.get_node("SandVortex").material
	var vortex = hub.get_node("Vortex")
	_check(is_zero_approx(mat.get_shader_parameter("color_amount")), "arrival is drained")
	var mountain := &""
	for id in Game.list_rooms():
		if hub.opens_with_eye(id):
			mountain = id
	if mountain != &"":
		_check(not hub.room_open(mountain), "mountain groove hidden before three inks")
		var rim: Vector3 = hub.arm_point(hub.arm_index(mountain), hub.pit_radius)
		_check(vortex.room_at_angle(atan2(rim.z, rim.x)) != mountain, "mountain slice leads elsewhere while locked")

	# Come back from test_room carrying ember: it's planted and the groove fills.
	await Game.go_to(&"test_room")
	Game.current_room.complete()
	await Game.go_to_hub(&"test_room")
	hub = Game.current_room
	story = hub.get_node("InkState")
	mat = hub.get_node("SandVortex").material
	_check(Game.inks_home.has(&"ember") and Game.carried == &"", "arriving with ember plants it")
	await _wait_story(story)
	_check(story.planted().has(&"ember"), "ember planting shown")
	_check(is_equal_approx(mat.get_shader_parameter("color_amount"), 1.0 / 3.0), "a third of the colour back")
	_check(Game.player.controls_enabled, "control handed back after planting")

	# The other two inks, planted while in the hub: the eye opens.
	Game.carry(&"salmon"); Game.bring_home()
	await _wait_story(story)
	Game.carry(&"crimson"); Game.bring_home()
	await _wait_story(story)
	_check(story.planted().size() == 3, "all three plantings shown")
	_check(is_equal_approx(mat.get_shader_parameter("color_amount"), 1.0), "colour fully back")
	_check(story.eye_open(), "the eye opened")
	if mountain != &"":
		_check(hub.room_open(mountain), "mountain groove uncoiled")
		vortex = hub.get_node("Vortex")
		var i: int = hub.arm_index(mountain)
		var rim2: Vector3 = hub.arm_point(i, hub.pit_radius)
		_check(vortex.room_at_angle(atan2(rim2.z, rim2.x)) == mountain, "mountain slice leads to the mountain")
		var to_mountain: Vector3 = hub.get_node("Landmarks").watcher_position()
		var outer: Vector3 = hub.arm_point(i, hub.arm_outer_radius)
		_check(absf(angle_difference(atan2(outer.z, outer.x), atan2(to_mountain.z, to_mountain.x))) < 0.05, "mountain groove points at the mountain")
	hub.set_dawn(true)
	_check(is_equal_approx(hub.get_node("WorldEnvironment").environment.sky.sky_material.get_shader_parameter("dawn"), 1.0), "dawn state")
	hub.set_dawn(false)
	Engine.time_scale = 1.0
	Game.reset_story()


func _wait_story(story) -> void:
	for f in 20000:
		await get_tree().process_frame
		if not story.is_playing() and story.pending().is_empty() and not Game.is_travelling() and f > 3:
			return
