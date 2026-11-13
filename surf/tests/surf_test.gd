extends Node
## Headless check of the surfing: godot --headless --path . res://surf/tests/surf_test.tscn
## Exit code 0 = pass. Drives the rider through the hub crater with scripted input.

var _failures := 0
var s: Surfer
var hub


func _ready() -> void:
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		print("SURF TEST: FAIL (timed out)")
		get_tree().quit(1))
	Game.save_enabled = false
	Game.reset_story()
	Game.set_flag(&"opening_seen", true)
	Story.enabled = false
	var world := Node3D.new()
	add_child(world)
	await Game.start(world)
	hub = Game.current_room
	await _frames(5)
	while Story.is_playing():
		await _frames(10)
	await _frames(2)
	s = Game.player.get_node_or_null(^"Surfer")
	_check(s != null, "hub gives him a board")
	if s == null:
		_finish()
		return
	_check(Game.player.driver == s, "surfer drives the player")
	var t: SurfTerrain = hub.get_node("Surf")
	# The ground the physics uses matches the static mesh (props stand on it).
	var p := Vector2(300, 120)
	var mesh_h: float = hub.get_node("SandVortex").ground_point(p).y
	_check(absf(t.static_height(p) - mesh_h) < 0.4, "physics ground matches the sand mesh (%.2f vs %.2f)" % [t.static_height(p), mesh_h])
	var h0 := t.height(Vector2(250, 0), 0.0)
	var h1 := t.height(Vector2(250, 0), 2.0)
	_check(absf(h0 - h1) > 0.05, "swells move (%.2f -> %.2f)" % [h0, h1])

	# 1. Drop in from the rim, hands off: gravity takes him down the wall, fast.
	var rim := _rim_point(0.3, 470.0)
	s.place(rim, -Vector3(rim.x, 0, rim.z))
	var top_speed := 0.0
	var airs := 0
	s.launched.connect(func(_v): airs += 1)
	for i in 60 * 9:
		await get_tree().physics_frame
		top_speed = maxf(top_speed, s.vel.length())
	print("   drop-in: top speed %.1f m/s, %d launches, now r=%.0f state=%s" % [top_speed, airs, Vector2(s.pos.x, s.pos.z).length(), s.state])
	_check(top_speed > 25.0, "dropping into the crater builds real speed")
	_check(top_speed < 80.0, "speed stays sane")

	# 2. Stays on the surface while riding.
	var off := 0.0
	s.place(_rim_point(1.4, 300.0), Vector3(1, 0, 0.2))
	for i in 120:
		await get_tree().physics_frame
		if s.state == Surfer.State.RIDE:
			off = maxf(off, absf(s.pos.y - t.height(Vector2(s.pos.x, s.pos.z))))
	_check(off < 0.05, "board sits on the live surface while riding (max off %.3f)" % off)

	# 3. Pop: hold and release jump on flat-ish ground -> airborne, then lands.
	s.place(_rim_point(1.0, 75.0), Vector3(-sin(1.0), 0, cos(1.0)))
	s.vel = Vector3(-sin(1.0), 0, cos(1.0)) * 10.0
	s.input.touch_active = true
	s.input.touch_jump = true
	await _frames(20)
	s.input.touch_jump = false
	await _frames(2)
	_check(s.state == Surfer.State.AIR, "releasing pop jumps")
	var landed := false
	for i in 200:
		await get_tree().physics_frame
		if s.state == Surfer.State.RIDE:
			landed = true
			break
	_check(landed, "and lands clean")

	# 4. Carving turns him.
	s.place(_rim_point(2.5, 90.0), Vector3(1, 0, 0))
	s.vel = Vector3(15, 0, 0)
	var d0 := Vector2(s.vel.x, s.vel.z).normalized()
	s.input.touch_steer = 1.0
	await _frames(45)
	s.input.touch_steer = 0.0
	var d1 := Vector2(s.vel.x, s.vel.z).normalized()
	_check(absf(d0.angle_to(d1)) > 0.6, "carving turns his line (%.2f rad)" % absf(d0.angle_to(d1)))
	# Steering right turns right (clockwise seen from above, i.e. toward +z when going +x).
	_check(d0.angle_to(d1) > 0.0, "right is right")

	# 5. Landing upside down wipes him out, he ragdolls, then gets back up.
	s.place(_rim_point(3.0, 780.0), Vector3(0, 0, 1))
	s.vel = Vector3(0, 0, 14)
	s.input.touch_jump = true
	await _frames(15)
	s.input.touch_jump = false
	s.input.touch_lean = 1.0   # flip
	var wiped := false
	for i in 30:
		await get_tree().physics_frame
	s.input.touch_lean = 0.0
	s.wipeout(Vector3(0, 2, 0)) if s.state != Surfer.State.WIPEOUT else null
	wiped = s.state == Surfer.State.WIPEOUT
	_check(wiped, "a bad landing knocks him off")
	var ok_bones := true
	var lowest := INF
	for i in 90:
		await get_tree().process_frame
		for q in s.points():
			if not q.is_finite():
				ok_bones = false
			else:
				lowest = minf(lowest, q.y - t.height(Vector2(q.x, q.z)))
	_check(ok_bones and lowest > -0.25 and lowest < 1.0, "ragdoll lands and stays on top of the sand (lowest joint %.2f)" % lowest)
	var got_up := false
	for i in 60 * 6:
		await get_tree().physics_frame
		if s.state == Surfer.State.RIDE:
			got_up = true
			break
	_check(got_up, "he gets back up")
	# Bone lengths kept by the ragdoll.
	_check(_limbs_ok(), "limbs keep their length through it all")

	# 6. Gates: riding through one boosts him.
	var gates := get_tree().get_nodes_in_group(&"surf_gate")
	_check(gates.size() > 10, "gates line the grooves (%d)" % gates.size())
	if gates.size() > 0:
		var gate: FlowGate = gates[2]
		var fwd := -gate.global_basis.z
		var start := gate.global_position - fwd * 12.0
		s.place(start, fwd)
		s.vel = Vector3(fwd.x, 0, fwd.z).normalized() * 18.0
		for i in 90:
			await get_tree().physics_frame
			if gate.taken:
				break
		_check(gate.taken, "riding through a gate takes it")

	# 7. Riding into the pit swallows him into a room (the hub still works).
	s.place(_rim_point(0.0, 70.0), -Vector3(cos(0.0), 0, sin(0.0)))
	s.vel = -Vector3(cos(0.0), 0, sin(0.0)) * 12.0
	var travelled := false
	for i in 60 * 8:
		await get_tree().physics_frame
		if Game.is_travelling() or Game.current_room != hub:
			travelled = true
			break
	_check(travelled, "surfing into the pit takes him to a room")
	_finish()


func _limbs_ok() -> bool:
	var r := s.rig
	var pts := s.points()
	for pair in [[&"LeftUpLeg", &"LeftLeg"], [&"LeftLeg", &"LeftFoot"], [&"RightArm", &"RightForeArm"]]:
		var a: int = r.bone(pair[0])
		var b: int = r.bone(pair[1])
		var rest := r.rest_body[a].distance_to(r.rest_body[b])
		var now := pts[a].distance_to(pts[b])
		if absf(now - rest) > rest * 0.08:
			print("   limb ", pair, " rest ", rest, " now ", now)
			return false
	return true


func _rim_point(angle: float, r: float) -> Vector3:
	return Vector3(cos(angle) * r, 0, sin(angle) * r)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


func _finish() -> void:
	print("SURF TEST: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
