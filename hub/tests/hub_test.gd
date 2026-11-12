extends Node
## Headless check for the spiral hub. Run before every hub PR, next to the smoke test:
##   godot --headless --path . res://hub/tests/hub_test.tscn   (exit code 0 = pass)
## Walks the little man down every room's groove into the pit and checks he lands in
## that room, then comes back out at that room's groove.

var _failures := 0


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	var hub: Room = Game.current_room
	var ids: Array[StringName] = hub.get("_ids")
	_check(ids.size() > 0, "at least one room discovered")
	var vortex = hub.get_node("Vortex")

	# Every arm's rim angle maps back to its own room, and every room has a return spawn.
	for i in ids.size():
		var rim: Vector3 = hub.arm_point(i, 1.6)
		_check(vortex.room_at_angle(atan2(rim.z, rim.x)) == ids[i], "rim slice %d -> %s" % [i, ids[i]])
		_check(hub.get_spawn(ids[i]).name == String(ids[i]), "return spawn for %s" % ids[i])

	# The arrival spot stands on the sand, and the player stays on it.
	for i in 10:
		await get_tree().physics_frame
	_check(Game.player.is_on_floor(), "player stands on the sand")

	for i in ids.size():
		var id := ids[i]
		if Game.current_room.room_id != Game.HUB_ID:
			await Game.go_to_hub()
		hub = Game.current_room
		var start: Vector3 = hub.arm_point(i, 2.4)
		Game.player.global_position = start + Vector3.UP * 0.1
		# Walk inward along the groove until the pit takes him.
		var target: Vector3 = hub.arm_point(i, 0.2)
		for f in 240:
			if Game.is_travelling() or Game.current_room != hub:
				break
			Game.player.global_position = Game.player.global_position.move_toward(target, 0.08)
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

	print("HUB TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
