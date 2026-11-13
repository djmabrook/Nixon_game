extends Node
## Plays the whole game arc headless on the real main scene, fast:
##   godot --headless --path . res://tools/arc_test.tscn     (exit 0 = pass)
## Hub -> each region -> mend -> carry its ink home -> the mountain opens ->
## the mountain's exit -> the ending starts. Uses no save file.
## The opening and ending sequences themselves are checked in story/tests/story_test.tscn.

const REGIONS := {&"lakeside": &"ember", &"checkerboard": &"salmon", &"red_grid": &"crimson"}
const MOUNTAIN := &"watching_face"

var _failures := 0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func():
		print("ARC TEST: FAIL (timed out)")
		get_tree().quit(1))
	Game.save_enabled = false
	Game.reset_story()
	# Skip the title and opening; this test is about the regions.
	Story.enabled = false
	Story.time_scale = 0.08
	add_child(load("res://main.tscn").instantiate())
	await _until(func() -> bool: return Game.current_room != null and not Game.is_travelling(), 30.0)
	_check(Game.current_room.room_id == Game.HUB_ID, "starts in the spiral hub")
	var ids := Game.list_rooms()
	for r in REGIONS:
		_check(ids.has(r), "hub knows %s" % r)
	_check(ids.has(MOUNTAIN), "hub knows the mountain")
	_check(not ids.has(&"test_room"), "test room has no door")
	_check(Game.is_room_locked(MOUNTAIN), "mountain locked at the start")

	for region in REGIONS:
		var ink: StringName = REGIONS[region]
		await Game.go_to(region)
		await _frames(30)
		_check(Game.current_room and Game.current_room.room_id == region, "%s loads" % region)
		_check(is_instance_valid(Game.player) and is_instance_valid(get_viewport().get_camera_3d()), "%s has the little man and a camera" % region)
		Game.current_room.complete()
		await _frames(5)
		_check(Game.is_completed(region) and Game.carried == ink, "mending %s hands him %s" % [region, ink])
		await Game.go_to_hub(region)
		await _until(func() -> bool: return Game.is_ink_home(ink), 20.0)
		_check(Game.is_ink_home(ink), "%s planted at the spiral" % ink)
		await _frames(10)

	_check(Game.all_inks_home(), "all three inks home")
	_check(Game.inks_home == ([&"ember", &"salmon", &"crimson"] as Array[StringName]), "arrival order kept")
	_check(not Game.is_room_locked(MOUNTAIN), "mountain opens")
	_check(is_zero_approx(Game.player.shadow_lag), "shadow has caught up")

	await Game.go_to(MOUNTAIN)
	await _frames(30)
	_check(Game.current_room and Game.current_room.room_id == MOUNTAIN, "mountain loads")
	var room := Game.current_room
	for ink in REGIONS.values():
		_check(room.call(&"has_ink", ink), "mountain sees %s" % ink)

	# Close the eyes and leave through the disc: the Story takes over with the ending.
	Story.enabled = true
	room.set(&"_ended", true)
	room.call(&"_on_exit_disc_entered", Game.player)
	await _until(func() -> bool: return Story.current_sequence() == &"ending", 30.0)
	_check(Game.is_completed(MOUNTAIN), "mountain marked done")
	_check(Story.current_sequence() == &"ending", "the ending begins at the spiral")

	print("ARC TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(cond: Callable, timeout: float) -> void:
	var left := timeout
	while not cond.call() and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
