extends Node
## Headless check for the lakeside rule. Run:
##   godot --headless --path . res://rooms/lakeside/lakeside_test.tscn   (exit code 0 = pass)

var _failures := 0


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, &"lakeside")
	var room := Game.current_room
	_check(room.room_id == &"lakeside", "entered lakeside")
	var spawn := room.get_spawn(&"from_hub")
	_check(Game.player.global_position.distance_to(spawn.global_position) < 0.01, "arrived at the house door")
	await _frames(10)

	var stones: Array = room._stone_bodies.keys()
	var first: Node3D = _path_stone(room, 0)
	var middle: Node3D = _path_stone(room, 5)
	_check(first.collision_layer == 1, "first stone is real in the campfire's light")
	_check(middle.collision_layer == 0 and not middle.visible, "mid-lake stone does not exist in the dark")

	# Take a brand from the fire.
	Game.player.global_position = room.campfire_spot.global_position + Vector3(0.8, 0.1, 0)
	await _frames(3)
	_check(room.interact() and room.torch_carried, "picked up a burning brand")

	# Walk the path stone by stone; each stone must be solid underfoot when we reach it.
	var ok := true
	for i in room.PATH_STONES.size():
		var s := _path_stone(room, i)
		Game.player.global_position = s.global_position + Vector3(0, 0.05, 0)
		Game.player.velocity = Vector3.ZERO
		await _frames(25)
		if s.collision_layer != 1 or Game.player.global_position.y < -0.2:
			ok = false
			print("    stone %d not solid (layer %d, y %.2f)" % [i, s.collision_layer, Game.player.global_position.y])
			break
	_check(ok, "brand makes every path stone solid on the way across")
	_check(_path_stone(room, 2).collision_layer == 0, "stones behind fade back out of existence")

	Game.player.global_position = room.beacon_spot.global_position + Vector3(0.9, 0.1, 0)
	await _frames(3)
	_check(room.interact() and room.beacon_is_lit, "lit the fire under the mountain")
	_check(Game.is_completed(&"lakeside"), "room completed")
	await _frames(40)
	_check(first.collision_layer == 1 and middle.collision_layer == 1, "path stays real once the beacon burns")
	_check(room.mountain_exit.enabled, "mountain door opened")

	# Falling into the lake wakes you at the campfire, beacon still burning.
	Game.player.global_position = room.layout.to_global(Vector3(5.0, 0.0, -5.0))
	for i in 120:
		await get_tree().physics_frame
		if Game.is_travelling():
			break
	while Game.is_travelling():
		await get_tree().process_frame
	var shore := Game.current_room.get_spawn(&"shore")
	_check(Game.current_room != room and Game.player.global_position.distance_to(shore.global_position) < 0.01, "drowning returns you to the fire")
	_check(Game.current_room.beacon_is_lit, "beacon remembered after waking")

	# The mountain door leads home.
	room = Game.current_room
	await _frames(5)
	Game.player.global_position = room.mountain_exit.global_position
	await _travel()
	_check(Game.current_room.room_id == Game.HUB_ID, "mountain door returns to hub")

	print("LAKESIDE TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _path_stone(room: Node, i: int) -> Node3D:
	var want: Vector2 = room.PATH_STONES[i]
	for s: Node3D in room._stone_bodies.keys():
		if s.get_meta(&"on_path") and Vector2(s.position.x, s.position.z).distance_to(want) < 0.01:
			return s
	return null


func _travel() -> void:
	for i in 60:
		await get_tree().physics_frame
		if Game.is_travelling():
			break
	while Game.is_travelling():
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
