extends Node
## Headless check for the Red Grid: contract, the carry-a-hole rule, falling into a hole,
## the full mend, the crimson ink and the way home through the hole.
## Run: godot --headless --path . res://rooms/red_grid/tests/check_red_grid.tscn  (exit 0 = pass)

const RedGrid := preload("res://rooms/red_grid/red_grid.gd")

var _failures := 0


func _ready() -> void:
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		print("RED GRID CHECK: TIMEOUT")
		get_tree().quit(2))
	Game.save_enabled = false
	Game.reset_story()
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, &"red_grid")
	var room := Game.current_room
	_check(room != null and room.room_id == &"red_grid", "entered red_grid")
	_check(room.gives_ink == &"crimson", "gives crimson")
	_check(Game.camera.focus_target == room.get_node("StareFocus"), "focus target is the stare")
	_check(Game.camera.far >= 6000.0, "draws far enough to see the pupil's rim")
	room.cinematic_speed = 0.1
	room.set(&"_vista_pupil_done", true)
	room.set(&"_vista_bowl_done", true)

	await _frames(10)
	_check(Game.player.is_on_floor(), "standing on the plain at the spawn")
	var bottom := _ground_y(Vector3.ZERO)
	_check(bottom < -219.0 and bottom > -221.0, "sag bottom is 220 m down (%.1f)" % bottom)
	_check(absf(_ground_y(Vector3(400, 0, 0)) - RedGrid.sag_height(Vector2(400, 0), 220.0)) < 1.0, "collision matches the drawn sag")
	_check(room.holes.size() == 6, "six loose holes")
	for probe in [Vector3(0, 0, 1000), Vector3(-1000, 0, 0), Vector3(900, 0, -900), Vector3(0, 0, -3000), Vector3(805, 0, 0)]:
		_check(absf(_ground_y(probe)) < 0.5, "solid plain at %s" % probe)

	# Walk onto a hole: it is picked up.
	_put(room.holes[0].pos)
	await _frames(4)
	_check(room.carried.size() == 1, "walking onto a hole picks it up")

	# Lay it ahead, then step into it: it swallows him and spits him out, holding it again.
	Game.player.face(Vector3.FORWARD)
	_check(room.interact(), "interact lays a carried hole")
	_check(room.carried.is_empty() and room.holes[0].state == RedGrid.HoleState.LAID, "hole lies on the ground")
	var laid: Vector3 = room.holes[0].pos
	await _frames(20)
	_put(laid)
	await _frames(3)
	_check(room._busy, "stepping in swallows him")
	while room._busy:
		await get_tree().process_frame
	_check(room.carried.size() == 1 and Game.player.controls_enabled, "spat back out, carrying the hole again")
	_check(Vector2(Game.player.global_position.x, Game.player.global_position.z).distance_to(Vector2(laid.x, laid.z)) > 1.5, "he lands beside it")

	# Gather the rest.
	for i in range(1, 6):
		_put(room.holes[i].pos)
		await _frames(3)
	_check(room.carried.size() == 6, "carrying all six")

	# Lay five in sockets.
	for s in 5:
		_put(_beside_socket(room, s))
		await _frames(2)
		_check(room.interact(), "lays a disc in socket %d" % s)
	_check(room.state == RedGrid.State.PLAYING, "not mended with five")
	var tv: WatchingSet = room.get_node("WatchingSet")
	_check(tv.mode == WatchingSet.Mode.DROOPING, "television droops as the ring fills")

	# The sixth mends it.
	_put(_beside_socket(room, 5))
	await _frames(2)
	room.interact()
	_check(room.state == RedGrid.State.MENDING, "sixth disc starts the mend")
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while room.state != RedGrid.State.MENDED and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_check(room.state == RedGrid.State.MENDED, "mend finishes")
	_check(absf(room.sag) < 0.01, "grid sprang level")
	_check(Game.is_completed(&"red_grid"), "room completed")
	_check(Game.carried == &"crimson", "he carries crimson")
	_check(tv.mode == WatchingSet.Mode.CLOSED, "television closed its eyes")
	_check(Game.player.controls_enabled, "control returns")
	await _frames(2)
	var level := _ground_y(Vector3(100, 0, 0))
	_check(absf(level) < 0.5, "collision is level (%.1f)" % level)
	_check(not _ground_hit(Vector3(0, 20, 0)), "the circle is open")

	# Walk into the hole: home to the hub.
	_put(Vector3(5, 0.5, 0))
	var t1 := Time.get_ticks_msec()
	while Game.current_room.room_id != Game.HUB_ID and Time.get_ticks_msec() - t1 < 8000:
		await get_tree().process_frame
	_check(Game.current_room.room_id == Game.HUB_ID, "the hole leads home")
	while Game.is_travelling():
		await get_tree().process_frame

	# Coming back later: mended state.
	await Game.go_to(&"red_grid")
	room = Game.current_room
	_check(room.state == RedGrid.State.MENDED and room.holes.is_empty(), "returns mended, no loose holes")

	print("RED GRID CHECK: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _beside_socket(room: Node, s: int) -> Vector3:
	var p: Vector3 = room.sockets[s]
	return p + Vector3(p.x, 0, p.z).normalized() * 3.0


func _put(p: Vector3) -> void:
	Game.player.global_position = p + Vector3.UP * 0.1
	Game.player.velocity = Vector3.ZERO


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ground_hit(from: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0, 1)
	return not Game.current_room.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ground_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 100, at.z), Vector3(at.x, -400, at.z), 1)
	var hit := Game.current_room.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -9999.0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
