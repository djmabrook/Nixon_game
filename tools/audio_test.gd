extends Node
## Headless check of the shared audio system (audio/). Exit code 0 = pass.
## Run: godot --headless --path . res://tools/audio_test.tscn

var _failures := 0


func _ready() -> void:
	# Buses, in the order sends require.
	for b in [&"Master", &"Broadcast", &"World", &"Bed", &"Near", &"Far", &"Ink"]:
		_check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Far")) == &"World", "Far sends to World")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Broadcast")) == &"Master", "Broadcast bypasses the stare")

	# Library: every id loads, variants resolve, nothing repeats twice in a row.
	_check(Sound.ids().size() >= 70, "library indexed (%d sounds)" % Sound.ids().size())
	for id in [&"bed_hub_night", &"bed_lake", &"bed_checker", &"bed_grid", &"bed_mountain", &"bed_dawn",
			&"broadcast_hum", &"broadcast_hiss", &"broadcast_tone", &"giant_footfall", &"eyelids_close",
			&"ink_ember_home", &"ink_ultraviolet_take", &"mend", &"fire_loop", &"statue_stiffen", &"rewind"]:
		_check(Sound.get_stream(id) != null, "loads %s" % id)
	for surface in [&"sand", &"stone", &"tile", &"water", &"felt"]:
		_check(Sound.has_sound(StringName("step_" + surface)), "footsteps on %s" % surface)
	var last: AudioStream = null
	var repeated := false
	for i in 30:
		var s := Sound.get_stream(&"step_sand")
		repeated = repeated or s == last
		last = s
	_check(not repeated, "variants never repeat back to back")
	_check(Sound.bus_for(&"giant_grind") == &"Far" and Sound.bus_for(&"broadcast_hiss") == &"Broadcast"
		and Sound.bus_for(&"ink_salmon_home") == &"Ink" and Sound.bus_for(&"step_tile_2") == &"Near"
		and Sound.bus_for(&"bed_lake") == &"Bed", "ids route to their buses")

	# Giants: late and low.
	_check(Sound.giant_pitch(300.0) < Sound.giant_pitch(20.0) and is_equal_approx(Sound.giant_pitch(20.0), 1.0), "bigger is lower")

	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	await get_tree().process_frame
	var ears := Sound.listener_position()
	_check(absf(Sound.delay_for(ears + Vector3(0, 0, -343.0)) - 1.0) < 0.01, "343 m away arrives 1 s late")
	Sound.lateness = 2.0
	_check(absf(Sound.delay_for(ears + Vector3(0, 0, -343.0)) - 2.0) < 0.01, "lateness scales the delay")
	Sound.lateness = 1.0

	# Beds crossfade.
	Sound.set_bed(&"bed_hub_night", -3.0, 0.1)
	_check(Sound.bed_id() == &"bed_hub_night", "bed set")
	var loop := Sound.get_loop(&"bed_lake") as AudioStreamOggVorbis
	_check(loop != null and loop.loop, "beds loop")

	# One-shots play and clean up.
	var p := Sound.play(&"pickup")
	_check(p != null and p.bus == &"Near", "2D one-shot on Near")
	Sound.play_at(&"giant_footfall", ears + Vector3(0, 0, -686.0))
	var found_late := false
	for n in Game.current_room.get_children():
		if n is AudioStreamPlayer3D and n.bus == &"Far" and not n.playing:
			found_late = true
	_check(found_late, "a far sound waits before it plays")

	# The stare drains the world, not the broadcast.
	Sound.set_stare(1.0)
	var world_bus := AudioServer.get_bus_index(&"World")
	var lowpass := AudioServer.get_bus_effect(world_bus, 0) as AudioEffectLowPassFilter
	_check(lowpass.cutoff_hz < 1000.0, "full stare narrows the world to a thin band (%d Hz)" % lowpass.cutoff_hz)
	Sound.set_stare(0.0)
	_check(lowpass.cutoff_hz > 19000.0, "unwatched world is full range")

	# A watching television.
	var tv := WatcherBroadcast.new()
	tv.drains_world = true
	Game.current_room.add_child(tv)
	tv.stare = 1.0
	for i in 40:
		await get_tree().process_frame
	_check(Sound.get_stare() > 0.3, "the broadcast's stare drains the world")
	await tv.close_eyes(0.3)
	_check(not tv.eyes_open and Sound.get_stare() == 0.0, "closing its eyes lets the world go")

	# The shared watching television carries its own broadcast and powers it off with its lids.
	var set_scene := load("res://props/watching_set.tscn") as PackedScene
	var wset := set_scene.instantiate()
	Game.current_room.add_child(wset)
	_check(wset.broadcast != null and wset.broadcast.eyes_open, "a watching set broadcasts")
	wset.lid_speed = 20.0
	wset.close()
	for i in 90:
		await get_tree().process_frame
	_check(not wset.broadcast.eyes_open, "a closed set goes silent")

	# A giant voice hears intensity late.
	var gv := GiantVoice.new()
	gv.sound_id = &"giant_grind"
	gv.size_m = 300.0
	gv.intensity = 0.0
	Game.current_room.add_child(gv)
	gv.global_position = ears + Vector3(0, 0, -686.0)
	await get_tree().process_frame
	gv.intensity = 1.0
	for i in 20:
		await get_tree().process_frame
	_check(gv.volume_db < -60.0, "a giant 686 m away is still silent a moment after it moves")

	# Silence.
	Sound.hush(0.2, true)
	await get_tree().create_timer(0.35).timeout
	_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Bed")) < -60.0, "hush silences the world")
	_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Near")) > -1.0, "hush keeps his footsteps")
	Sound.unhush(0.2)
	await get_tree().create_timer(0.35).timeout
	_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Bed")) > -1.0, "unhush brings it back")

	# Rooms without RoomAudio fade the bed; rooms with it apply their settings.
	await Game.go_to(&"test_room")
	_check(Sound.surface == &"stone", "default surface")

	print("AUDIO TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	print(("  ok   " if ok else "  FAIL ") + what)
