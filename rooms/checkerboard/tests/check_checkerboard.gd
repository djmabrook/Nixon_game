extends Node
## Headless check for the checker plain. Exit code 0 = pass.
## Run: godot --headless --path . res://rooms/checkerboard/tests/check_checkerboard.tscn

const ROOM := &"checkerboard"
var _failures := 0
var room


func _ready() -> void:
	Game.reset_story()   # start from a fresh save
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	_check(Game.list_rooms().has(ROOM), "room discovered")
	await Game.go_to(ROOM)
	room = Game.current_room
	_check(room.room_id == ROOM, "entered room")
	await _frames(40)
	var p := Game.player
	_check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "little man stands on the plain")
	var biggest := 0.0
	for b in room._balls:
		biggest = maxf(biggest, b.radius)
	_check(room._balls.size() >= 140, "herds spawned (%d spheres)" % room._balls.size())
	_check(biggest >= 24.0, "a cathedral sphere exists (r = %.1f m)" % biggest)
	_check(room.focus_target == room.moon and Game.camera.far >= 1000.0, "camera focus is the moon")
	_check(not room.board.is_black_at(p.global_position), "spawn is on a pink tile")
	var on_black := 0
	for st in room.get_node("Statues").get_children():
		if st.name.begins_with("CaughtWalking") and room.board.is_black_at(st.global_position):
			on_black += 1
	_check(on_black == 4, "the walking stone men all stand on black tiles")
	_check(Sound.bed_id() == &"bed_checker" and Sound.surface == &"tile", "checker bed and tile footsteps")
	await _frames(30)
	_check(room._voice_balls.count(null) < room.VOICE_COUNT, "rolling voices follow the nearest big spheres")

	# --- The tide rolls spheres toward the moon.
	var ball = null
	for b in room._balls:
		if b.radius > 0.7 and b.radius < 2.0 and not b.is_key:
			ball = b
			break
	var x0: float = ball.global_position.x
	_force_pull(0.0)   # moon due +X
	await _frames(90)
	_check(ball.global_position.x > x0 + 1.5, "tide rolls a sphere toward the moon (%.1f -> %.1f)" % [x0, ball.global_position.x])

	# --- Black tiles drag the little man, pink tiles hold him.
	var black := Vector3(-3, 0.05, 195)
	var pink := Vector3(-3, 0.05, 201)
	_check(room.board.is_black_at(black) and not room.board.is_black_at(pink), "tile colour lookup")
	_force_pull(PI)    # moon due -X
	await _frames(30)
	p.global_position = black
	room._drift = Vector3.ZERO
	await _frames(20)
	var moved_black := absf(p.global_position.x - black.x)
	p.global_position = pink
	room._drift = Vector3.ZERO
	await _frames(20)
	var moved_pink := absf(p.global_position.x - pink.x)
	_check(moved_black > 0.3 and moved_pink < 0.05, "black drags (%.2f), pink holds (%.2f)" % [moved_black, moved_pink])

	# --- The fourth tide: everything lifts, giants included.
	room._enter_phase(room.Phase.CALM, 0.1)
	room._cycle = room.lift_every - 1
	room._lifts_seen = 1   # skip the scripted vista shot in the test
	await _frames(60 * 3)
	var giant_up := false
	for b in room._balls:
		if b.radius > 20.0 and b.global_position.y > b.radius + 5.0:
			giant_up = true
	_check(giant_up, "lift raises a cathedral sphere")
	_check(room._moon_elev > room.moon_elevation + 0.05, "the eye looks up during the lift")

	# --- A run of natural tides: giants keep out of the crater, nothing is lost.
	await _frames(60 * 12)
	var crater_clear := true
	var lost := 0
	for b in room._balls:
		var flat := Vector2(b.global_position.x, b.global_position.z)
		if b.radius > room.pushable_radius and flat.length() < room.board.crater_radius:
			crater_clear = false
		if b.global_position.y < -25.0:
			lost += 1
			print("    lost: r=%.2f at %s v=%s" % [b.radius, b.global_position, b.linear_velocity])
	_check(crater_clear, "giants keep out of the crater")
	_check(lost == 0, "no spheres fell through the world (%d)" % lost)

	# --- Only the pale sphere fits the socket.
	room._enter_phase(room.Phase.CALM, 999.0)
	var marble = null
	for b in room._balls:
		if b.radius < 0.6:
			marble = b
			break
	marble.linear_velocity = Vector3.ZERO
	marble.global_position = room.board.socket_center() + Vector3(0, 1.5, 0)
	await _frames(60)
	_check(not marble.socketed and not Game.is_completed(ROOM), "a marble doesn't mend the room")
	var key = room.key_ball
	key.linear_velocity = Vector3.ZERO
	key.global_position = room.board.socket_center() + Vector3(0, 2.0, 0)
	await _frames(90)
	_check(key.socketed and Game.is_completed(ROOM), "the pale sphere in the socket mends the room")
	await _frames(60 * 8)
	_check(room._moon_elev < 0.0 and room._moon_open < 0.05, "the eye shuts and sets")
	_check(room._footing > 0.9, "pink footing blooms")
	_check(Game.carried == &"salmon", "he carries the salmon ink out")
	_check(room.get_node("WatchingSet").mode == WatchingSet.Mode.CLOSED, "the watching set closes its eyes")
	_check(not room.watching_set.broadcast.eyes_open, "its broadcast winds down")
	_check(room._crater_exit != null and room._crater_exit.enabled, "an exit opens in the crater")

	# --- Leave through the crater exit.
	p.global_position = room._crater_exit.global_position + Vector3(0, 0.5, 0)
	for i in 30:
		await get_tree().physics_frame
		if Game.is_travelling():
			break
	while Game.is_travelling():
		await get_tree().process_frame
	_check(Game.current_room.room_id == Game.HUB_ID, "crater exit returns to hub")
	var door := Game.current_room.get_spawn(ROOM)
	_check(door != null and Game.player.global_position.distance_to(door.global_position) < 0.01, "back at the plain's door")

	await Game.go_to(ROOM)
	_check(Game.current_room.phase == Game.current_room.Phase.DONE, "a mended plain stays at peace on return")
	_check(Game.current_room._crater_exit != null, "the crater exit is there on return")

	print("CHECKERBOARD CHECK: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _force_pull(az: float) -> void:
	room._moon_az = az
	room._moon_to = az
	room._enter_phase(room.Phase.PULL, 999.0)
	room._phase_t = 2.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
