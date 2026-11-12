extends Node
## Headless check of the Stray's behaviour in rooms/_stray_demo.
## Run: godot --headless --path . res://companions/stray/tests/stray_test.tscn   (exit 0 = pass)

var _failures := 0
var _stray: Stray
var _modes: Array = []


func _ready() -> void:
	Game.save_enabled = false
	Game.reset_story()
	var world := Node3D.new()
	add_child(world)
	await Game.start(world, &"_stray_demo")
	await _frames(5)
	_stray = Stray.find_in(get_tree())
	_check(_stray != null, "stray is in the room")
	_stray.mode_changed.connect(func(m): _modes.append(m))
	_check(_flat_dist() < 3.0, "starts at his heel (%.1f m)" % _flat_dist())
	_check(_stray.ink.is_equal_approx(Stray.INK_COLORS[&"ember"]), "borrows the room's ink")
	Game.player.controls_enabled = false
	var acked := [false]

	# Walk forward. It should keep up and hop.
	var hopped := false
	for i in 240:
		await _walk(Vector3(0, 0, -1), 5.0)
		hopped = hopped or _stray.get_node("Rig").position.y > 0.05
	_check(hopped, "hops while following")
	_check(_flat_dist() < 4.5, "keeps up at a walk (%.1f m)" % _flat_dist())

	# By now the tower is in range: it runs ahead, points, and is satisfied once he looks.
	var marker: StrayInterest = Game.current_room.get_node("Tower/TowerInterest")
	marker.acknowledged.connect(func(): acked[0] = true)
	for i in 300:
		Game.camera.face_toward(marker.global_position)
		await get_tree().process_frame
		if acked[0]:
			break
	_check(Stray.Mode.POINT in _modes, "runs ahead to point at something")
	_check(acked[0], "is satisfied when he looks where it points")

	# Walk near the awake television: it hides behind him.
	var tv: WatchingSet = Game.current_room.get_node("AwakeSet")
	await _walk_to(tv.global_position + Vector3(8, 0, 8), 5.0)
	await _seconds(1.5)
	_check(_stray.mode == Stray.Mode.COWER, "hides near an awake television (mode %s)" % Stray.Mode.keys()[_stray.mode])
	var p := Game.player.global_position
	var behind := (_stray.global_position - p).dot((p - tv.global_position).normalized())
	_check(behind > 0.2 and _flat_dist() < 1.3, "tucked behind his legs (%.2f behind, %.2f away)" % [behind, _flat_dist()])

	# Its eyes close: relief, then it curls up by it when he stands still.
	tv.close()
	await _seconds(1.0)
	_check(_stray.mode != Stray.Mode.COWER, "stops hiding once the eyes close")
	await _seconds(6.0)
	_check(_stray.mode == Stray.Mode.CURL, "curls up by a sleeping television (mode %s)" % Stray.Mode.keys()[_stray.mode])
	_check(_stray._lie > 0.8, "is lying down (%.2f)" % _stray._lie)

	# Walk away: it wakes and follows.
	await _walk_to(Vector3(0, 0, -20), 6.0)
	await _seconds(1.0)
	_check(_stray.mode != Stray.Mode.CURL, "wakes up when he leaves")
	await _seconds(1.5)
	_check(_flat_dist() < 4.0, "catches up after waking (%.1f m)" % _flat_dist())

	# Teleport him away: it glitches out and reappears beside him.
	Game.player.global_position = Vector3(120, 0, 60)
	await _seconds(1.5)
	_check(Stray.Mode.LOST in _modes, "glitches out when left far behind")
	_check(_flat_dist() < 3.5, "reappears at his heel (%.1f m)" % _flat_dist())

	# Scripted calls for story code.
	var goal := Game.player.global_position + Vector3(5, 0, 3)
	await _stray.walk_to(goal)
	_check(_stray.global_position.distance_to(goal) < 0.6, "walk_to arrives")
	await _stray.look_at_camera(0.5)
	_check(true, "look_at_camera returns")
	await _stray.sniff_around(goal, 1)
	_check(true, "sniff_around returns")
	_stray.release()
	_check(_stray.mode == Stray.Mode.FOLLOW and not _stray._scripted, "release hands it back")

	print("STRAY TEST: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _flat_dist() -> float:
	var d := _stray.global_position - Game.player.global_position
	d.y = 0.0
	return d.length()


func _walk(dir: Vector3, speed: float) -> void:
	await get_tree().physics_frame
	Game.player.global_position += dir.normalized() * speed / Engine.physics_ticks_per_second


func _walk_to(pos: Vector3, speed: float) -> void:
	pos.y = Game.player.global_position.y
	while Game.player.global_position.distance_to(pos) > 0.2:
		var d := pos - Game.player.global_position
		Game.player.global_position += d.limit_length(speed / Engine.physics_ticks_per_second)
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
