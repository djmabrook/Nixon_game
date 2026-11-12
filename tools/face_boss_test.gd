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
	var room: Room = Game.current_room
	var face: FaceBoss = room.get_node("FaceBoss")
	var cam := Game.camera
	_check(face != null and cam.focus_target == face, "face present and is the camera's focus")
	_check(face.head_radius() > 150.0, "face is mountain sized")
	_check(room.get_node("Cover").get_child_count() >= 40, "cover raised")
	face.wake_delay = 0.0
	face._awake_in = 0.0
	var player := Game.player
	await _frames(5)

	# Watched: the spawn faces it, so it starts in view and must not move.
	cam.face_toward(face.global_position)
	var before := face.global_position
	await _frames(30)
	_check(face.is_watched, "in view counts as watched")
	_check(face.global_position.distance_to(before) < 0.001, "frozen while watched")

	# Look away: it must start closing in.
	cam.face_toward(player.global_position * 2.0 - face.global_position)
	var d0 := face.flat_distance_to(player.global_position)
	await _seconds(2.0)
	_check(not face.is_watched, "looking away counts as unwatched")
	_check(face.flat_distance_to(player.global_position) < d0 - 3.0, "moves while unwatched")

	# Look back: it freezes and the reveal fires.
	var revealed := [false]
	face.revealed.connect(func(_d): revealed[0] = true)
	cam.face_toward(face.global_position)
	await _frames(5)
	var frozen_at := face.global_position
	await _frames(20)
	_check(face.is_watched and revealed[0], "looking back reveals it")
	_check(face.global_position.distance_to(frozen_at) < 0.001, "and freezes it")

	# Cover: stand right behind a telephone or mast, facing the face.
	var cover := _cover_between(room, face)
	_check(cover != null, "found cover")
	if cover:
		var away := (cover.global_position - face.global_position) * Vector3(1, 0, 1)
		player.global_position = cover.global_position + away.normalized() * 14.0 + Vector3.UP * 0.2
		player.velocity = Vector3.ZERO
		cam.snap_to_target()
		cam.face_toward(face.global_position)
		await _frames(10)
		_check(not face.sees_player, "cover blocks its stare")
		_check(not face.is_watched, "cover also hides it from you")
		# Step into the open.
		player.global_position += away.normalized().cross(Vector3.UP) * 60.0
		cam.snap_to_target()
		cam.face_toward(face.global_position)
		await _seconds(1.2)
		_check(face.sees_player and face.stare > 0.9, "open ground: it stares")
		_check(player.move_speed < 5.0 * 0.6 and player.run_speed < 10.0 * 0.6, "stare slows the little man")

	# Caught: he turns to stone, then the room resets.
	var old_id := room.get_instance_id()
	face.global_position = player.global_position + Vector3(10, face.hover_far, 0)
	await _frames(3)
	var stone := false
	for mi in player.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override != null:
			stone = true
	_check(stone, "caught: the little man turns to stone")
	await _until(func(): return Game.current_room.get_instance_id() != old_id and not Game.is_travelling(), 6.0)
	_check(Game.current_room.get_instance_id() != old_id and Game.current_room.room_id == ROOM, "caught resets the room")
	_check(Game.player.global_position.distance_to(Game.current_room.get_node("from_hub").global_position) < 0.5, "back at the start")

	# Goal: the eyes close, the room completes, and he returns to the hub.
	await _frames(5)
	var face2: FaceBoss = Game.current_room.get_node("FaceBoss")
	face2.active = false
	Game.player.global_position = Game.current_room.get_node("Disc").global_position + Vector3.UP * 0.2
	await _seconds(0.5)
	_check(Game.is_completed(ROOM), "reaching the disc completes the room")
	await _seconds(0.5)
	_check(not face2.sees_player, "its eyes are shut")
	await _until(func(): return Game.current_room.room_id == Game.HUB_ID and not Game.is_travelling(), 8.0)
	_check(Game.current_room.room_id == Game.HUB_ID, "then returns to the hub")

	print("FACE BOSS TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


## A tall cover piece on the near side of the field, between spawn and face.
func _cover_between(room: Node, face: FaceBoss) -> Node3D:
	var best: Node3D = null
	for c in room.get_node("Cover").get_children():
		var n := c as Node3D
		if absf(n.global_position.x) < 80.0 and n.global_position.z > 0.0:
			if best == null or n.global_position.z > best.global_position.z:
				best = n
	return best


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
