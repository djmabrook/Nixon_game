extends Node
## Headless check that the room contract works end to end.
## Run: godot --headless res://tools/smoke_test.tscn   (exit code 0 = pass)

var _failures := 0


func _ready() -> void:
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

	Game.current_room.complete()
	print("SMOKE TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
