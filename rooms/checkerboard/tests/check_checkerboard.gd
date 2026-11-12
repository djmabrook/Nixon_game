extends Node
## Headless check for the checkerboard room. Exit code 0 = pass.
## Run: godot --headless --path . res://rooms/checkerboard/tests/check_checkerboard.tscn

const ROOM := &"checkerboard"
var _failures := 0
var room


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	_check(Game.list_rooms().has(ROOM), "room discovered")
	await Game.go_to(ROOM)
	room = Game.current_room
	_check(room.room_id == ROOM, "entered room")
	await _frames(40)
	var p := Game.player
	_check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "little man stands on the spawn platform")
	_check(room._balls.size() >= 3, "balls found (%d)" % room._balls.size())
	_check(room._sky != null, "sky attached to camera")

	# --- The tide pushes balls toward the chosen edge.
	var ball = room._balls[0]
	var x0: float = ball.global_position.x
	_force_pull(Vector2(1, 0))
	await _frames(90)
	_check(ball.global_position.x > x0 + 1.5, "tide rolls a ball downhill (%.2f -> %.2f)" % [x0, ball.global_position.x])

	# --- Black tiles drag the little man, pink tiles hold him.
	var t: float = room.board.tile_size
	var black := Vector3(t * 0.5, 0.05, t * 1.5 + t * 2.0)   # (0,3): odd -> black
	var pink := Vector3(t * 0.5, 0.05, t * 0.5 + t * 2.0)    # (0,2): even -> pink
	_check(room.board.is_black_at(black) and not room.board.is_black_at(pink), "tile colour lookup")
	_force_pull(Vector2(-1, 0))
	await _frames(30)
	p.global_position = black
	room._drift = Vector3.ZERO
	await _frames(20)
	var moved_black := absf(p.global_position.x - black.x)
	p.global_position = pink
	room._drift = Vector3.ZERO
	await _frames(20)
	var moved_pink := absf(p.global_position.x - pink.x)
	_check(moved_black > 0.2 and moved_pink < 0.05, "black drags (%.2f), pink holds (%.2f)" % [moved_black, moved_pink])

	# --- A natural run of tides and a lift: nothing escapes the board.
	room._enter_phase(room.Phase.CALM, 0.1)
	p.global_position = room.get_spawn().global_position
	room._cycle = room.lift_every - 1   # next cycle is a lift
	await _frames(60 * 2)
	var floated := false
	for b in room._balls:
		if b.global_position.y > b.radius + 0.8:
			floated = true
	_check(floated, "lift floats the balls")
	await _frames(60 * 12)
	var all_on := true
	for b in room._balls:
		if not room.board.is_on_board(b.global_position) or b.global_position.y < -0.5:
			if not b.socketed:
				all_on = false
				print("    off board: ", b.name, " ", b.global_position)
	_check(all_on, "balls stay on the board through the tides")

	# --- Socket a small ball: the room completes.
	room._enter_phase(room.Phase.CALM, 999.0)
	var small = null
	for b in room._balls:
		if b.radius <= room.socket_fit_radius and not b.socketed:
			small = b
	if small == null:
		_check(Game.is_completed(ROOM), "a ball was already socketed by the tides")
	else:
		small.linear_velocity = Vector3.ZERO
		small.global_position = room.board.socket_center() + Vector3(0, 1.0, 0)
		await _frames(90)
		_check(small.socketed and Game.is_completed(ROOM), "ball in socket completes the room")
	var big = null
	for b in room._balls:
		if b.radius > room.socket_fit_radius:
			big = b
	_check(big != null and not big.socketed, "big ball can't be socketed")

	# --- Exit back to the hub.
	var exit: RoomExit = room.get_node("ExitToHub")
	p.global_position = exit.global_position
	for i in 30:
		await get_tree().physics_frame
		if Game.is_travelling():
			break
	while Game.is_travelling():
		await get_tree().process_frame
	_check(Game.current_room.room_id == Game.HUB_ID, "exit returns to hub")
	var door := Game.current_room.get_spawn(ROOM)
	_check(door != null and Game.player.global_position.distance_to(door.global_position) < 0.01, "back at the checkerboard door")

	# Coming back to a solved room keeps it calm.
	await Game.go_to(ROOM)
	_check(Game.current_room.phase == Game.current_room.Phase.DONE, "solved room stays at peace on return")

	print("CHECKERBOARD CHECK: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _force_pull(dir: Vector2) -> void:
	room._next_dir = dir
	room._tide_dir = dir
	room._enter_phase(room.Phase.PULL, 999.0)
	room._phase_t = 1.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
