extends Node
## Headless check of the watching face room and its rule.
## Run: godot --headless --path . res://tools/face_boss_test.tscn   (exit code 0 = pass)

const ROOM := &"watching_face"

var _failures := 0


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, ROOM)
	_check(Game.list_rooms().has(ROOM), "room discovered")
	_check(Game.current_room.room_id == ROOM, "entered room")
	var face: FaceBoss = Game.current_room.get_node("FaceBoss")
	_check(face != null, "face present")
	face.wake_delay = 0.0
	face._awake_in = 0.0
	var player := Game.player
	await _frames(5)

	# Watched: put the face just up-screen of the player. It must not move.
	var cam := Game.camera
	var up_screen := -Vector3(cam.global_transform.basis.z.x, 0, cam.global_transform.basis.z.z).normalized()
	face.global_position = player.global_position + up_screen * 6.0 + Vector3.UP * face.hover_height
	var before := face.global_position
	await _frames(30)
	_check(face.is_watched, "on screen counts as watched")
	_check(face.global_position.distance_to(before) < 0.001, "frozen while watched")

	# Unwatched: far down-screen, out of view. It must close in.
	face.global_position = player.global_position - up_screen * 30.0 + Vector3.UP * face.hover_height
	var d0 := _flat_dist(face, player)
	await _frames(40)
	_check(not face.is_watched, "off screen counts as unwatched")
	_check(_flat_dist(face, player) < d0 - 0.5, "moves while unwatched")

	# Turning the camera brings it back into view, which freezes it again.
	# Park it off to the side, where a quarter turn will swing it down into view.
	var back := Vector3(cam.global_transform.basis.z.x, 0, cam.global_transform.basis.z.z).normalized()
	face.global_position = player.global_position + back.rotated(Vector3.UP, deg_to_rad(90)) * 16.0 + Vector3.UP * face.hover_height
	await _frames(20)
	_check(not face.is_watched, "off to the side counts as unwatched")
	var revealed := [false]
	face.revealed.connect(func(_d): revealed[0] = true)
	Game.current_room.turn_camera(1.0)
	await _seconds(0.9)
	_check(face.is_watched and revealed[0], "turning the camera reveals and freezes it")

	# Cover: a pillar between face and player breaks its stare.
	var pillar: Node3D = Game.current_room.get_node("Pillars/Pillar9")  # (-1, 0, -12)
	face.active = false
	face.global_position = pillar.global_position + Vector3(0, face.hover_height, -6)
	player.global_position = pillar.global_position + Vector3(0, 0.1, 1.4)
	await _frames(10)
	_check(not face.sees_player, "pillar blocks its stare")
	player.global_position = pillar.global_position + Vector3(4, 0.1, 1.4)
	await _seconds(1.0)
	_check(face.sees_player and face.stare > 0.9, "open ground: it stares")
	_check(player.move_speed < 4.0 * 0.6, "stare slows the little man")

	# Caught: the room resets.
	var old_id := Game.current_room.get_instance_id()
	face.active = true
	face.global_position = player.global_position + Vector3(0.5, face.hover_height, 0)
	await _until(func(): return Game.current_room.get_instance_id() != old_id and not Game.is_travelling(), 4.0)
	_check(Game.current_room.get_instance_id() != old_id and Game.current_room.room_id == ROOM, "caught resets the room")
	_check(Game.player.global_position.distance_to(Vector3(0, 0, 19)) < 0.1, "back at the start")

	# Goal: completes and returns to the hub at this room's door.
	await _frames(5)
	Game.current_room.get_node("FaceBoss").active = false
	Game.player.global_position = Game.current_room.get_node("Goal").global_position + Vector3.UP * 0.1
	await _until(func(): return Game.current_room.room_id == Game.HUB_ID and not Game.is_travelling(), 4.0)
	_check(Game.is_completed(ROOM), "reaching the disc completes the room")
	_check(Game.current_room.room_id == Game.HUB_ID, "then returns to the hub")

	print("FACE BOSS TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
