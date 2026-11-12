extends Room
## The Watching Face. Rule broken: things only move when nobody is looking.
##
## The little man stands at the start of a striped road a kilometre long, on an endless
## purple grid. At its end a face the size of a mountain fills the sky. Around the road
## stand telephones as big as houses and microphone masts as tall as towers.
## The face is frozen while you can see it. The moment it is out of view, because you
## looked away or something stands in the way, it slides toward you: slow to start,
## heavy, and heard late. In the open its stare weighs you down to a crawl; behind cover
## you are fast but blind to it. Reach the black disc at its foot and its eyes close.
## Let it reach you and you turn to grey stone for a beat, then the moment rewinds.

## Player speed multiplier at full stare (walk and run).
@export_range(0.1, 1.0) var stare_slow := 0.38
## Seconds after a catch before the room resets.
@export var catch_reset_delay := 2.2

@export_group("Cover")
@export var cover_seed := 7
@export var telephone_count := 34
@export var mast_count := 26
## Area cover is scattered over (x range, z range), in metres.
@export var field_x := Vector2(-170, 170)
@export var field_z := Vector2(-380, 540)
## Keep this much of the road's centre open so there is always an exposed line.
@export var road_clear := 9.0

@onready var face: FaceBoss = $FaceBoss
@onready var goal: Area3D = $Disc/Goal
@onready var gate_ring: Node3D = $Disc/Ring
@onready var floor_mat: ShaderMaterial = $Floor/Mesh.material_override
@onready var vignette_mat: ShaderMaterial = $Screen/Vignette.material
@onready var synth: AudioStreamPlayer = $Synth
var _base_walk := 5.0
var _base_run := 10.0
var _shake := 0.0
var _flash := 0.0
var _done := false


func _ready() -> void:
	# Each room instance gets its own copies so state never leaks across reloads.
	floor_mat = floor_mat.duplicate()
	$Floor/Mesh.material_override = floor_mat
	vignette_mat = vignette_mat.duplicate()
	$Screen/Vignette.material = vignette_mat
	_raise_cover()
	_raise_skyline()


func _on_room_entered(_spawn: StringName) -> void:
	_base_walk = Game.player.move_speed
	_base_run = Game.player.run_speed
	face.caught_player.connect(_on_caught)
	face.revealed.connect(_on_revealed)
	goal.body_entered.connect(_on_goal_body_entered)
	floor_mat.set_shader_parameter(&"face_radius", face.head_radius())
	# The reveal: pull far back so he is a speck on the road and the face fills the sky.
	# It cannot move during the shot, since the shot is looking straight at it.
	if DisplayServer.get_name() != "headless":
		Game.camera.play_vista(face.global_position, 70.0, 2.5, 2.5)


func _process(delta: float) -> void:
	var player := Game.player
	if not is_instance_valid(player) or not is_instance_valid(face):
		return

	# Its stare weighs the little man down.
	if player.controls_enabled:
		var k := lerpf(1.0, stare_slow, face.stare)
		player.move_speed = _base_walk * k
		player.run_speed = _base_run * k

	var dist := face.flat_distance_to(player.global_position)
	var proximity := clampf(1.0 - (dist - face.catch_radius) / 700.0, 0.0, 1.0)

	floor_mat.set_shader_parameter(&"face_pos", face.global_position)
	floor_mat.set_shader_parameter(&"face_motion", face.motion)
	floor_mat.set_shader_parameter(&"stare", face.stare)

	_flash = move_toward(_flash, 0.0, delta * 1.5)
	vignette_mat.set_shader_parameter(&"stare", maxf(face.stare * 0.8, proximity * 0.6))
	vignette_mat.set_shader_parameter(&"flash", _flash)

	synth.motion = face.motion
	synth.stare = face.stare
	synth.proximity = proximity

	gate_ring.rotate_object_local(Vector3.UP, delta * 0.3)

	_apply_shake(delta, proximity)

	if player.global_position.y < -20.0 and not Game.is_travelling():
		_reset()


func _apply_shake(delta: float, proximity: float) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	# A low tremor while it moves close by, on top of event shakes.
	var amount := _shake * _shake * 0.35 + proximity * proximity * face.motion * 0.08
	cam.h_offset = randf_range(-amount, amount)
	cam.v_offset = randf_range(-amount, amount)


func _on_revealed(distance: float) -> void:
	var strength := clampf(distance / 150.0, 0.2, 1.0)
	_shake = maxf(_shake, 0.4 + 0.5 * strength)
	_flash = maxf(_flash, 0.3 * strength)
	synth.sting(strength)


func _on_caught() -> void:
	if _done:
		return
	_done = true
	Game.player.controls_enabled = false
	Game.player.velocity = Vector3.ZERO
	# Make him look: swing the view up onto the face as it drops.
	var cam := Game.camera
	var to_face := face.global_position - cam.global_position
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(cam, "yaw_degrees", rad_to_deg(atan2(-to_face.x, -to_face.z)), 0.5)
	t.tween_property(cam, "pitch_degrees", 30.0, 0.5)
	face.lunge(Game.player.global_position)
	_turn_to_stone(Game.player)
	synth.slam()
	_shake = 1.0
	_flash = 0.5
	await get_tree().create_timer(catch_reset_delay).timeout
	_reset()


func _on_goal_body_entered(body: Node3D) -> void:
	if not body is Player or _done:
		return
	_done = true
	# The eyes close, the lights go out, the sound stops. Nothing moves any more.
	face.close_eyes(2.5)
	complete()
	_flash = 0.4
	Game.player.move_speed = _base_walk
	Game.player.run_speed = _base_run
	create_tween().tween_property(synth, "volume_db", -60.0, 3.0)
	await get_tree().create_timer(4.0).timeout
	exit_to_hub()


## The caught beat: the little man goes grey and still, like a small statue.
func _turn_to_stone(player: Player) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.55, 0.58)
	stone.roughness = 1.0
	for mi in player.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = stone


func _reset() -> void:
	Game.go_to(room_id, &"from_hub")


# --- Cover ------------------------------------------------------------------
# Telephones the size of houses and microphone masts as tall as towers, placed from
# a fixed seed so the field is the same every visit. Placeholder geometry.

var _mats := {}


func _mat(key: String, color: Color, unshaded := false, rim := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.6
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if rim > 0.0:
			m.rim_enabled = true
			m.rim = rim
		_mats[key] = m
	return _mats[key]


func _raise_cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cover_seed
	var placed: Array[Vector2] = []
	var phones_left := telephone_count
	var masts_left := mast_count
	var tries := 0
	while phones_left + masts_left > 0 and tries < 5000:
		tries += 1
		var p := Vector2(rng.randf_range(field_x.x, field_x.y), rng.randf_range(field_z.x, field_z.y))
		# More cover near the road, thinning out into the empty grid.
		if absf(p.x) > 60.0 and rng.randf() < 0.5:
			continue
		if absf(p.x) < road_clear:
			continue
		var crowded := false
		for q in placed:
			if q.distance_to(p) < 34.0:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var node: Node3D
		if rng.randf() < float(masts_left) / float(masts_left + phones_left):
			node = _mast(rng)
			masts_left -= 1
		else:
			node = _telephone(rng)
			phones_left -= 1
		node.position = Vector3(p.x, 0.0, p.y)
		node.rotation.y = rng.randf() * TAU
		$Cover.add_child(node)


func _telephone(rng: RandomNumberGenerator) -> StaticBody3D:
	var body := _cover_body()
	var s := rng.randf_range(0.85, 1.35)
	var black := _mat("phone", Color(0.04, 0.02, 0.06), false, 0.35)
	var pink := _mat("cord", Color(1.0, 0.45, 0.75), true)
	var cream := _mat("dial", Color(0.92, 0.86, 0.95))
	# Base: a sloped block the size of a house.
	_box(body, black, Vector3(20, 10, 16) * s, Vector3(0, 5, 0) * s, true)
	_box(body, black, Vector3(16, 4, 12) * s, Vector3(0, 12, 0) * s, true)
	# Handset lying across the top: two ear cups joined by a bar.
	_box(body, black, Vector3(30, 4, 5) * s, Vector3(0, 17, 0) * s, true)
	_box(body, black, Vector3(7, 6, 8) * s, Vector3(-13, 15, 0) * s, true)
	_box(body, black, Vector3(7, 6, 8) * s, Vector3(13, 15, 0) * s, true)
	# Dial on the front face.
	var dial := _cyl(body, cream, 4.5 * s, 0.6 * s, Vector3(0, 6, -8.2) * s)
	dial.rotation_degrees.x = 90.0
	var hub := _cyl(body, black, 1.6 * s, 0.8 * s, Vector3(0, 6, -8.6) * s)
	hub.rotation_degrees.x = 90.0
	# A cord trailing off across the grid.
	_box(body, pink, Vector3(0.8, 0.8, 30) * s, Vector3(10, 0.4, 22) * s, false)
	return body


func _mast(rng: RandomNumberGenerator) -> StaticBody3D:
	var body := _cover_body()
	var h := rng.randf_range(70.0, 170.0)
	var steel := _mat("steel", Color(0.55, 0.5, 0.62), false, 0.25)
	var grille := _mat("grille", Color(0.12, 0.1, 0.16), false, 0.5)
	var glow := _mat("tally", Color(1.0, 0.2, 0.35), true)
	# Tripod foot, wide enough to hide behind.
	_cyl(body, steel, 3.0, 6.0, Vector3(0, 3, 0), true, 7.0)
	_cyl(body, steel, 1.8, h, Vector3(0, h * 0.5, 0), true)
	# Microphone head: a capsule of grille on a collar, tipped toward the face.
	var head := Node3D.new()
	head.position = Vector3(0, h, 0)
	head.rotation_degrees.x = -25.0
	body.add_child(head)
	_cyl(head, steel, 3.2, 4.0, Vector3(0, 2, 0))
	var cap := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 6.0
	cm.height = 22.0
	cm.material = grille
	cap.mesh = cm
	cap.position = Vector3(0, 14, 0)
	head.add_child(cap)
	# A small red light at the collar, for scale against the sky.
	var light := _cyl(head, glow, 0.9, 0.6, Vector3(0, 4.3, -3.2))
	light.rotation_degrees.x = 90.0
	return body


func _cover_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group(&"cover")
	return body


func _box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		_collide(parent, shape, pos)
	return mi


func _cyl(parent: Node3D, mat: Material, radius: float, height: float, pos: Vector3, solid := false, bottom := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = bottom if bottom > 0.0 else radius
	cm.height = height
	cm.radial_segments = 24
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = maxf(radius, bottom)
		shape.height = height
		_collide(parent, shape, pos)
	return mi


func _collide(parent: Node3D, shape: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)


## Far-off silhouettes past the edges of the field, purely for scale.
func _raise_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cover_seed * 31
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.0, 0.035)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 40:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(1400.0, 3200.0)
		var size := Vector3(rng.randf_range(40.0, 120.0), rng.randf_range(300.0, 1100.0), rng.randf_range(40.0, 120.0))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(cos(ang) * r, size.y * 0.5, sin(ang) * r)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		$Skyline.add_child(mi)
