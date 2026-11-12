extends Node
## Headless check of the Watcher's mountain and its rule.
## Run: godot --headless --path . res://tools/face_boss_test.tscn   (exit code 0 = pass)

const ROOM := &"watching_face"

var _failures := 0


func _ready() -> void:
	# The mountain is locked until all three inks are home.
	Game.reset_story()
	_check(Game.is_room_locked(ROOM), "locked until the three inks are home")
	for ink in Game.INKS:
		Game.carry(ink)
		Game.bring_home()
	_check(not Game.is_room_locked(ROOM), "opens with all three home")
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, ROOM)
	var room: Room = Game.current_room
	var face: FaceBoss = room.get_node("FaceBoss")
	var land: Node3D = room.get_node("Landscape")
	var cam := Game.camera
	var player := Game.player
	_check(room.room_id == ROOM, "entered room")
	_check(cam.focus_target == face, "face is the camera's focus")
	_check(face.head_radius() > 150.0 and face.model != null, "the Watcher model, mountain sized")
	var snd := get_node_or_null(^"/root/Sound")
	if snd:
		_check(room.audio.has_shared_sound(), "uses the shared Sound system (broadcast, grind, bed)")
	_check(land.mic_heads.size() >= 50 and land.telephones.size() >= 10, "mic forest and telephones raised")
	face.wake_delay = 0.0
	face._awake_in = 0.0
	await _frames(5)
	_check(absf(face.global_position.y - (200.0 + face.ride_height)) < 1.0, "face rests on the collar")

	# The staircase is walkable: drop him halfway up and he stands about 40 m high.
	_place(player, Vector3(0, 42, 440))
	await _frames(60)
	_check(absf(player.global_position.y - 40.0) < 2.0, "staircase carries him up (y=%.1f)" % player.global_position.y)
	_place(player, Vector3(0, 1, 640))
	await _frames(10)

	# Watched: in view, frozen.
	cam.face_toward(face.centre())
	var before := face.global_position
	await _frames(30)
	_check(face.is_watched and face.global_position.distance_to(before) < 0.001, "frozen while watched")

	# Look away: it slides toward him.
	_look_away(cam, face, player)
	var d0 := face.flat_distance_to(player.global_position)
	await _seconds(2.5)
	_check(not face.is_watched and face.flat_distance_to(player.global_position) < d0 - 3.0, "moves while unwatched")

	# Look back: the reveal, and it freezes.
	var revealed := [false]
	face.revealed.connect(func(_d): revealed[0] = true)
	cam.face_toward(face.centre())
	await _frames(5)
	var frozen_at := face.global_position
	await _frames(20)
	_check(revealed[0] and face.global_position.distance_to(frozen_at) < 0.001, "looking back reveals and freezes it")

	# Ember: inside a planted fire's light it cannot move, even unseen.
	room.plant_fire()
	_look_away(cam, face, player)
	var held_at := face.global_position
	await _seconds(1.5)
	_check(not face.is_watched and face.global_position.distance_to(held_at) < 0.01, "ember: firelight holds it while unseen")
	_place(player, player.global_position + Vector3(60, 0, 0))
	_look_away(cam, face, player)
	await _seconds(1.5)
	_check(face.global_position.distance_to(held_at) > 1.0, "outside the light it moves again")

	# Cover hides him from the stare and hides the face from the camera.
	var cover := _cover_near(room, Vector3(0, 0, 630))
	_check(cover != null, "found cover on the plain")
	var away := (cover.global_position - face.global_position) * Vector3(1, 0, 1)
	_place(player, cover.global_position + away.normalized() * 16.0 + Vector3.UP)
	cam.snap_to_target()
	cam.face_toward(face.centre())
	await _frames(10)
	_check(not face.sees_player and not face.is_watched, "cover blocks its stare and your view")
	# Out on the open avenue down the middle of the plain.
	_place(player, Vector3(0, 1, 620))
	cam.face_toward(face.centre())
	await _seconds(1.2)
	_check(face.sees_player and player.move_speed < 5.0 * 0.6, "open ground: it stares and slows him")

	# Crimson: on the laid disc the stare falls into a blind spot.
	room.lay_disc()
	await _frames(5)
	_check(face.sees_player and player.move_speed > 4.9, "crimson disc: a blind spot for the stare")

	# Salmon: standing still, the land slides him toward the face. Walking, pink footing holds.
	_place(player, player.global_position + Vector3(0, 0, -30))
	cam.face_toward(face.centre())
	await _frames(10)
	var sd0 := face.flat_distance_to(player.global_position)
	await _seconds(1.0)
	_check(face.flat_distance_to(player.global_position) < sd0 - 0.3, "standing still, the land slides him toward it")
	var tiles_before := room.get_child_count()
	Input.action_press(&"move_right")
	await _seconds(1.0)
	Input.action_release(&"move_right")
	_check(room.get_child_count() > tiles_before, "walking, pink footing blooms under him")

	# Caught: a grey statue, the Negative, then the rewind.
	var old_id := room.get_instance_id()
	face.held = false
	face.global_position = player.global_position + Vector3(10, 0, 0)
	await _frames(3)
	var stone := false
	for mi in player.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override != null:
			stone = true
	_check(stone and room.get_node("Screen/Negative").visible, "caught: stone and the Negative")
	await _until(func(): return Game.current_room.get_instance_id() != old_id and not Game.is_travelling(), 6.0)
	_check(Game.current_room.get_instance_id() != old_id, "the moment rewinds")
	_check(Game.player.global_position.distance_to(Game.current_room.get_node("from_hub").global_position) < 1.0, "back at the start")

	# The ending: at the knot he raises the ember, the eyes close, and he walks past.
	await _frames(5)
	room = Game.current_room
	face = room.get_node("FaceBoss")
	player = Game.player
	cam = Game.camera
	face.wake_delay = 0.0
	face._awake_in = 0.0
	_place(player, room.get_node("Foot").global_position + Vector3(0, 2, 10))
	await _frames(15)
	room.tap()
	await _seconds(1.0)
	_check(room._ended and not face.sees_player, "raising the ember closes the eyes")
	_look_away(cam, face, player)
	var rest := face.global_position
	await _seconds(2.0)
	_check(face.global_position.distance_to(rest) < 0.01, "behind him and off screen, nothing moves")
	if snd:
		await _seconds(4.5)
		_check(snd.call(&"is_hushed"), "and the world falls silent but his steps")
	_place(player, room.get_node("ExitDisc").global_position + Vector3(0, 2, 0))
	await _seconds(0.6)
	_check(Game.is_completed(ROOM), "the black disc beyond the face completes the room")
	await _until(func(): return Game.current_room.room_id == Game.HUB_ID and not Game.is_travelling(), 8.0)
	_check(Game.current_room.room_id == Game.HUB_ID, "and takes him home")

	Game.reset_story()
	print("FACE BOSS TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _place(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	Game.camera.snap_to_target()


func _look_away(cam: FollowCamera, face: FaceBoss, player: Player) -> void:
	cam.face_toward(player.global_position * 2.0 - face.global_position)


func _cover_near(room: Node, p: Vector3) -> Node3D:
	var best: Node3D = null
	for c in room.get_node("Cover").get_children():
		var n := c as Node3D
		if n.global_position.z < 590.0 or n.global_position.z > 680.0:
			continue
		if best == null or n.global_position.distance_to(p) < best.global_position.distance_to(p):
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
