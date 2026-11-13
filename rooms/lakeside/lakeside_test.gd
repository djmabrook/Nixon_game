extends Node
## Headless check for the lakeside rule. Run:
##   godot --headless --path . res://rooms/lakeside/lakeside_test.tscn   (exit code 0 = pass)

var _failures := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("LAKESIDE TEST: TIMEOUT")
		get_tree().quit(2))
	Game.save_enabled = false
	Game.reset_story()
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, &"lakeside")
	var room := Game.current_room
	_check(room.room_id == &"lakeside", "entered lakeside")
	var spawn := room.get_spawn(&"from_hub")
	_check(Game.player.global_position.distance_to(spawn.global_position) < 0.01, "arrived at the house door")
	var tv: WatchingSet = room.get_node("Layout/WatchingSet")
	_check(tv.mode == WatchingSet.Mode.OPEN, "the television on the shore is watching")
	_check(room.focus_target != null and Game.camera.focus_target == room.focus_target, "camera focus is the mountain")
	await _frames(5)

	var stones: Array = room._path_stones
	var length: float = stones[0].global_position.distance_to(stones.back().global_position)
	print("    crossing: %d stones, %.0f m end to end" % [stones.size(), length])
	_check(length > 1000.0, "the crossing is over a kilometre")
	_check(stones[0].collision_layer == 1, "first stone is real in the campfire's light")
	_check(stones[40].collision_layer == 0 and not stones[40].visible, "a stone out at sea does not exist in the dark")

	Game.player.global_position = room.campfire_spot.global_position + Vector3(1.0, 0.1, 0)
	await _frames(3)
	_check(room.interact() and room.torch_carried, "picked up a burning brand")

	# Walk the whole crossing stone by stone; each stone must be solid underfoot when
	# we reach it. Relight each islet's fire on the way.
	var ok := true
	var islets_lit := 0
	for i in stones.size():
		var s: Node3D = stones[i]
		Game.player.global_position = s.global_position + Vector3(0, 0.05, 0)
		Game.player.velocity = Vector3.ZERO
		await _frames(4)
		if s.collision_layer != 1 or Game.player.global_position.y < -0.2:
			ok = false
			print("    stone %d not solid (layer %d, y %.2f)" % [i, s.collision_layer, Game.player.global_position.y])
			break
		for f in room.fires:
			if not f.lit and not f.great and f.spot.global_position.distance_to(s.global_position) < 30.0:
				Game.player.global_position = f.spot.global_position + Vector3(1.0, 0.1, 0)
				await _frames(3)
				if room.interact() and f.lit:
					islets_lit += 1
	_check(ok, "brand makes every path stone solid across the whole sea")
	_check(islets_lit == 3, "relit all three islet fires (%d)" % islets_lit)
	_check(room.checkpoint == &"islet_2", "last islet is the checkpoint")
	_check(stones[60].collision_layer == 0, "stones far behind have faded out of existence")

	# The sea takes him: he wakes at the last islet fire, without the brand.
	Game.player.global_position = stones[stones.size() - 30].global_position + Vector3(14, 0.5, 0)
	for i in 200:
		await get_tree().physics_frame
		if not room._drowning and i > 10:
			break
	await _frames(120)
	var cp := room.get_spawn(&"islet_2")
	_check(Game.player.global_position.distance_to(cp.global_position) < 0.5, "drowning wakes you at the last fire you lit")
	_check(not room.torch_carried, "the brand is lost to the sea")

	# Take a new brand there, then climb to the brazier.
	Game.player.global_position = room.fires[3].spot.global_position + Vector3(1.0, 0.1, 0)
	await _frames(3)
	room.interact()
	Game.player.global_position = room.beacon_spot.global_position + Vector3(2.5, 0.2, 2.5)
	await _frames(20)
	_check(Game.player.is_on_floor() and Game.player.global_position.y > 2.0, "stands on the landing by the brazier")
	_check(room.interact() and room.beacon_is_lit, "lit the great brazier")
	_check(Game.is_completed(&"lakeside"), "room completed")
	_check(not Game.player.controls_enabled, "the reveal takes the camera")
	for i in 3000:
		await get_tree().physics_frame
		if not room.revealing:
			break
	_check(Game.player.controls_enabled, "control returns after the reveal")
	_check(room._head_climb > 700.0, "the light climbed the whole mountain")
	_check(stones[60].collision_layer == 1 and stones[400].collision_layer == 1, "the whole path is real once the brazier burns")
	_check(Game.carried == &"ember", "he carries the ember out (carry slot)")
	_check(Game.player.carry_slot.get_child_count() > 0, "the brand rides in his carry slot")
	_check(tv.mode == WatchingSet.Mode.CLOSED, "the television closed its eyes")
	_check(room.mountain_exit.enabled, "mountain door opened")

	Game.player.global_position = room.mountain_exit.global_position + Vector3(0, 0.2, 0.7)
	await _travel()
	_check(Game.current_room.room_id == Game.HUB_ID, "mountain door returns to hub")

	await Game.go_to(&"lakeside")
	_check(Game.current_room.beacon_is_lit, "the brazier still burns on a return visit")

	print("LAKESIDE TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


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
