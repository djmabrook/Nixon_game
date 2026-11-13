extends Node
## Headless check that the room contract works end to end.
## Run: godot --headless res://tools/smoke_test.tscn   (exit code 0 = pass)

var _failures := 0


func _ready() -> void:
	# Fail instead of hanging if something breaks mid-test.
	get_tree().create_timer(60.0).timeout.connect(func():
		print("SMOKE TEST: FAIL (timed out)")
		get_tree().quit(1))
	Game.save_enabled = false
	Game.reset_story()
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	_check(Game.current_room != null and Game.current_room.room_id == Game.HUB_ID, "starts in hub")
	_check(is_instance_valid(Game.player), "player spawned in hub")
	_check(is_instance_valid(Game.camera) and Game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and Game.camera.far >= 1000.0, "perspective camera with long draw distance")
	_check(Game.list_rooms().has(&"test_room"), "test_room discovered")
	_check(not Game.list_rooms().has(&"_template"), "_template skipped")

	await Game.go_to(&"test_room")
	_check(Game.current_room.room_id == &"test_room", "entered test_room")
	_check(Game.player.input_scale == Vector2(-1, -1), "room hook ran")
	_check(Game.player.global_position.distance_to(Vector3.ZERO) < 0.01, "spawned at default RoomSpawn")

	var landmark: Node3D = Game.current_room.get_node("Landmark")
	_check(Game.camera.focus_target == landmark, "room's landmark set as camera focus")
	await get_tree().process_frame
	Game.camera.face_toward(landmark.global_position)
	_check(Game.camera.is_point_visible(landmark.global_position), "landmark visible when faced")
	_check(not Game.camera.is_point_visible(Game.current_room.get_node("ExitToHub").global_position), "exit behind camera not visible")

	# Story hooks: mend the room, carry its ink, see the television close.
	var tv: WatchingSet = Game.current_room.get_node("WatchingSet")
	_check(tv.mode == WatchingSet.Mode.OPEN, "television starts open")
	_check(is_equal_approx(Game.player.shadow_lag, 0.5), "shadow lags 0.5 s with no inks home")
	Game.player.global_position = Vector3(0, 0, -195)
	for i in 5:
		await get_tree().physics_frame
	_check(Game.is_completed(&"test_room"), "walking to the monolith mends the room")
	_check(Game.carried == &"ember", "little man carries the room's ink")
	_check(Game.player.carry_slot.get_child_count() == 1, "carried ink shows in the carry slot")
	_check(tv.mode == WatchingSet.Mode.CLOSED, "television closes when the room is mended")

	# Let physics settle, then walk the player into the exit.
	for i in 5:
		await get_tree().physics_frame
	var exit: RoomExit = Game.current_room.get_node("ExitToHub")
	Game.player.global_position = exit.global_position
	for i in 30:
		await get_tree().physics_frame
		if Game.is_travelling():
			break
	while Game.is_travelling():
		await get_tree().process_frame
	_check(Game.current_room.room_id == Game.HUB_ID, "exit returned to hub")
	var door_spawn := Game.current_room.get_spawn(&"test_room")
	_check(door_spawn != null and Game.player.global_position.distance_to(door_spawn.global_position) < 0.01, "returned at the room's door")

	_check(Game.carried == &"" and Game.inks_home == ([&"ember"] as Array[StringName]), "hub plants the carried ink")
	_check(is_equal_approx(Game.player.shadow_lag, 0.5 * 2.0 / 3.0), "shadow lag shrinks with one ink home")
	var hub_tv: WatchingSet = Game.current_room.get_node("WatchingSet")
	_check(hub_tv.mode == WatchingSet.Mode.DROOPING, "hub television droops")

	# Locking: a room needing all three inks stays shut until they're home.
	var needed := Game.required_inks_in_scene("res://tools/fixtures/locked_room.tscn")
	_check(needed.size() == 3 and not Game.inks_satisfy(needed), "locked room needs three inks")
	Game.carry(&"salmon"); Game.bring_home()
	Game.carry(&"crimson"); Game.bring_home()
	_check(Game.inks_satisfy(needed) and Game.all_inks_home(), "unlocks with all three home")
	_check(Game.inks_home == ([&"ember", &"salmon", &"crimson"] as Array[StringName]), "inks kept in arrival order")
	_check(is_zero_approx(Game.player.shadow_lag), "shadow catches up at the end")
	_check(hub_tv.mode == WatchingSet.Mode.CLOSED, "hub television closes with all inks home")

	# Flags and a new cycle.
	Game.set_flag(&"ending_seen", true)
	Game.new_cycle()
	_check(Game.inks_home.is_empty() and Game.carried == &"" and Game.completed_rooms.is_empty(), "new cycle clears inks and rooms")
	_check(Game.get_flag(&"ending_seen") == true, "flags survive a new cycle")
	_check(Game.get_flag(&"missing", 7) == 7, "get_flag default")
	print("SMOKE TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
