class_name FaceBoss
extends Node3D
## The Watcher: a colossal face that only moves while nobody is looking at it.
##
## "Looking" means the active camera can actually see it: some part of the head is inside
## the view AND not hidden behind world geometry. Seen, it is frozen solid (only the pupils
## keep following the little man). Unseen, whether the camera looks away or a monolith
## blocks the view, it slides toward him and sinks lower as it closes in.
##
## Its own stare is the second threat: while it has a clear line of sight to the player,
## `stare` rises toward 1 and the room slows him down. Cover breaks its stare, but cover
## also hides the face from you, and then it moves.
##
## Works with any Camera3D (the viewport's current camera). Sizes are in metres.
## To swap the placeholder for a real model, put it under `Visual` with two Node3D
## pivots named `EyeL` and `EyeR` (pupil as first child, looking down -Z).

## Fired once when the face reaches the player.
signal caught_player
## Fired when the face becomes seen or unseen.
signal watched_changed(watched: bool)
## Fired when the face is seen again after moving while unseen.
## `distance` is how far it travelled in the dark. Rooms use it for the sting.
signal revealed(distance: float)
## Fired when the face gains or loses line of sight to the player.
signal sees_player_changed(sees: bool)
## Fired when close_eyes() starts.
signal eyes_closed

@export_group("Hunt")
## Top speed while unseen, in m/s.
@export var chase_speed := 24.0
## How fast it reaches top speed once you look away.
@export var acceleration := 3.0
## Horizontal distance at which it has the player.
@export var catch_radius := 280.0
## Seconds after the room starts before it may move.
@export var wake_delay := 2.0
## Set false to freeze it for good (after the room is won, in cutscenes).
@export var active := true
## A far-off backdrop version for other rooms' horizons: never moves or stares,
## its eyes are just two red lights.
@export var distant := false

@export_group("Stare")
## How far its gaze reaches.
@export var sight_range := 4000.0
## How fast the stare builds and fades (per second).
@export var stare_rise := 1.2
@export var stare_fall := 2.0

@export_group("Model")
## The Watcher's real model (origin at the base centre, front +Z). Empty = placeholder head.
@export var model: PackedScene
## Uniform scale for the model. watcher_bust_v2 is 12 m; 33.3 makes him about 450 m tall.
@export var model_scale := 33.3
## Stone eyelids, hinged on their origin: rotation.x 0 closed, -95 open.
@export var eyelid_left: PackedScene
@export var eyelid_right: PackedScene
## Lid hinge positions in model-local units.
@export var eyelid_left_pos := Vector3(0.9, 8.15, 0.95)
@export var eyelid_right_pos := Vector3(-0.9, 8.15, 0.95)
## Lid rotation.x when open.
@export var eyelid_open_deg := -95.0
## A camera-facing crimson glow on each eye so they pierce the dither from kilometres away.
@export var eye_glow := true

@export_group("Shape")
## Placeholder head scale (1 = a 6 m head). 90 makes it a mountain, about 550 m tall.
@export var head_scale := 90.0
## Height of the head's centre above whatever ground is under it. It rides the land:
## over stairs, slopes and plains alike, so the chin always rests on the ground.
@export var ride_height := 270.0
## Give it a solid body (physics layer 4) so the little man can't walk through it.
@export var solid := true
## Screen pixels a point must be inside the view before it counts as seen.
@export var visible_margin_px := 4.0

## Optional `func(x: float, z: float) -> float` giving the ground height under the face.
## Without it the face raycasts layer 1, which also finds anything standing under it.
var ground_provider: Callable
## While true it cannot move even when unseen (a room sets it, e.g. inside firelight).
var held := false
## True while the camera can see any part of the face.
var is_watched := true
## True while the face has a clear line of sight to the player.
var sees_player := false
## 0..1, smoothed sees_player. Rooms read it to slow the player and tint the screen.
var stare := 0.0
## 0..1, how hard it is moving right now. Drives sound and grid ripples.
var motion := 0.0

var _velocity := Vector3.ZERO
var _awake_in := 0.0
var _caught := false
var _moved_unseen := 0.0
var _eyes: Array[Node3D] = []
var _pupil_mat: StandardMaterial3D
var _base_pupil_scale := Vector3.ONE
var _faced_player := false
var _bob_time := 0.0
var _closed := false
## Model mode: where the visibility samples centre (the head, not the base) and its radius.
var _centre_offset := Vector3.ZERO
var _model_radius := 0.0
var _lids: Array[Node3D] = []
var _glows: Array[Sprite3D] = []
var _track_eyes := true

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"face_boss")
	_awake_in = wake_delay
	if model:
		_build_model()
	elif visual.get_child_count() == 0:
		_build_placeholder()
		# Chin tipped down toward the floor, so the eyes meet the little man below.
		visual.scale = Vector3.ONE * head_scale
		visual.rotation_degrees.x = -14.0
	if _eyes.is_empty():
		for eye_name in [&"EyeL", &"EyeR"]:
			var eye := visual.find_child(String(eye_name), true, false) as Node3D
			if eye:
				_eyes.append(eye)
	if solid and not distant:
		_add_body()
	if distant:
		active = false
		set_physics_process(false)
		for g in _glows:
			g.modulate.a = 1.0
		if _pupil_mat:
			_pupil_mat.emission_energy_multiplier = 8.0
			_pupil_mat.emission = Color(1.0, 0.05, 0.1)


## Shut the eyes for good: no stare, no movement, lights out.
func close_eyes(time := 2.0) -> void:
	active = false
	_closed = true
	for lid in _lids:
		create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT) \
				.tween_property(lid, "rotation_degrees:x", 0.0, time)
	for g in _glows:
		var gt := create_tween()
		gt.tween_interval(time * 0.6)
		gt.tween_property(g, "modulate:a", 0.0, time * 0.5)
	for socket_name in [&"SocketL", &"SocketR"]:
		var socket := visual.find_child(String(socket_name), true, false) as Node3D
		if socket == null:
			continue
		var lid := socket.get_node_or_null(^"Lid") as Node3D
		if lid:
			# The heavy lid slides down over the eye.
			lid.visible = true
			create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT) \
					.tween_property(lid, "position:y", 0.0, time)
		else:
			create_tween().set_trans(Tween.TRANS_SINE).tween_property(socket, "scale:y", 0.04, time)
	if _pupil_mat:
		var t := create_tween()
		t.tween_interval(time * 0.6)
		t.tween_property(_pupil_mat, "emission_energy_multiplier", 0.0, time)
	eyes_closed.emit()


func _add_body() -> void:
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = 1 << 3  # enemies
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := CollisionShape3D.new()
	if model:
		var cyl := CylinderShape3D.new()
		cyl.radius = _model_radius * 0.75
		cyl.height = _centre_offset.y * 2.0
		shape.shape = cyl
		shape.position = Vector3(0, _centre_offset.y, 0)
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = 2.5 * head_scale
		shape.shape = sphere
	body.add_child(shape)
	add_child(body)


## Rough radius of the head in metres, used for visibility samples.
func head_radius() -> float:
	if _model_radius > 0.0:
		return _model_radius
	return 2.8 * visual.scale.x


## The middle of the head in world space (the model's origin is at its base).
func centre() -> Vector3:
	return global_position + _centre_offset


func _physics_process(delta: float) -> void:
	var player := Game.player
	var cam := get_viewport().get_camera_3d()
	if not is_instance_valid(player) or cam == null or Game.is_travelling():
		return

	if not _faced_player:
		# Start already looking at him, so the first thing he sees is the stare.
		_faced_player = true
		var d := player.global_position - global_position
		rotation.y = atan2(-d.x, -d.z)
		global_position.y = _ground_height() + ride_height
	_update_watched(cam)
	_update_sight(player, delta)
	_track_with_eyes(player, delta)
	if _caught or not active:
		_velocity = Vector3.ZERO
		motion = move_toward(motion, 0.0, delta * 4.0)
		return

	_awake_in -= delta
	if is_watched or held or _awake_in > 0.0:
		# The rule: when seen, it is a statue. No easing, no drift. It just stops.
		_velocity = Vector3.ZERO
		motion = 0.0
	else:
		_hunt(player, delta)

	if flat_distance_to(player.global_position) < catch_radius:
		_caught = true
		caught_player.emit()


## Horizontal distance from the face to a point.
func flat_distance_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Called by the room when it is beaten: the face sinks away and stops for good.
func retreat() -> void:
	active = false
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(self, "global_position:y", -head_radius() * 1.5, 4.0)
	t.tween_property(visual, "rotation_degrees:x", 20.0, 4.0)


## Called by the room when the player is caught: the face drops onto him.
func lunge(target: Vector3) -> void:
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var to := target + (Vector3.UP * head_radius() * 0.4 if model == null else Vector3.ZERO)
	to.y = maxf(to.y, global_position.y - 40.0) if model else to.y
	t.tween_property(self, "global_position", global_position.lerp(to, 0.8), 0.7)
	t.tween_property(visual, "rotation_degrees:x", -35.0, 0.7)


## Height of the world (layer 1) under the face, or 0 if there is nothing there.
func _ground_height() -> float:
	if ground_provider.is_valid():
		return ground_provider.call(global_position.x, global_position.z)
	var top := Vector3(global_position.x, 5000.0, global_position.z)
	var bottom := Vector3(global_position.x, -5000.0, global_position.z)
	var query := PhysicsRayQueryParameters3D.create(top, bottom, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else 0.0


func _update_watched(cam: Camera3D) -> void:
	var c := centre()
	var r := head_radius() * 0.8
	var right := cam.global_transform.basis.x * r
	var up := cam.global_transform.basis.y * r
	var rect := get_viewport().get_visible_rect().grow(-visible_margin_px)
	var space := get_world_3d().direct_space_state
	var seen := false
	for p: Vector3 in [c, c + right, c - right, c + up, c - up]:
		if cam.is_position_behind(p) or not rect.has_point(cam.unproject_position(p)):
			continue
		# Inside the view. Is something standing in the way?
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1)
		if space.intersect_ray(query).is_empty():
			seen = true
			break
	if seen == is_watched:
		return
	is_watched = seen
	watched_changed.emit(seen)
	if seen and _moved_unseen > 1.0:
		revealed.emit(_moved_unseen)
	if seen:
		_moved_unseen = 0.0


func _hunt(player: Player, delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var desired := to_player.normalized() * chase_speed if to_player.length() > 0.01 else Vector3.ZERO
	_velocity = _velocity.move_toward(desired, acceleration * delta)
	var step := _velocity * delta
	global_position += step
	_moved_unseen += step.length()
	motion = clampf(_velocity.length() / chase_speed, 0.0, 1.0)
	# Turn the whole head only in the dark, so the player never catches it turning.
	if to_player.length() > 0.1:
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 2.0, 0.0, 1.0))
	# Ride the land with a slow, heavy heave. Also only while unseen.
	_bob_time += delta
	var goal_y := _ground_height() + ride_height + sin(_bob_time * 1.3) * head_radius() * 0.03
	global_position.y = move_toward(global_position.y, goal_y, chase_speed * delta)


func _update_sight(player: Player, delta: float) -> void:
	var from := _eye_centre()
	var to := player.global_position + Vector3.UP * 0.8
	var sees := not _closed and from.distance_to(to) <= sight_range
	if sees:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)  # world layer only
		sees = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	if sees != sees_player:
		sees_player = sees
		sees_player_changed.emit(sees)
	stare = move_toward(stare, 1.0 if sees else 0.0, (stare_rise if sees else stare_fall) * delta)

	if _pupil_mat and not _closed:
		_pupil_mat.emission_energy_multiplier = lerpf(IDLE_GLOW, 6.0, stare)
	if not _closed:
		for g in _glows:
			g.modulate.a = lerpf(0.55, 1.0, stare)
			g.pixel_size = lerpf(0.00003, 0.00006, stare)
	for eye in _eyes:
		var pupil := eye.get_child(0) as Node3D if eye.get_child_count() > 0 else null
		if pupil:
			# Pupils contract to pinpricks when it locks on.
			pupil.scale = _base_pupil_scale * lerpf(1.0, 0.55, stare)


func _track_with_eyes(player: Player, delta: float) -> void:
	if not _track_eyes:
		return
	var target := player.global_position + Vector3.UP * 0.8
	for eye in _eyes:
		var local := eye.get_parent_node_3d().to_local(target) - eye.position
		if local.length() < 0.01:
			continue
		var want := Basis.looking_at(local.normalized(), Vector3.UP)
		eye.basis = eye.basis.orthonormalized().slerp(want, clampf(delta * 10.0, 0.0, 1.0))


func _eye_centre() -> Vector3:
	if _eyes.size() >= 2:
		return (_eyes[0].global_position + _eyes[1].global_position) * 0.5
	return global_position


# --- Real model -----------------------------------------------------------------

func _build_model() -> void:
	var m := model.instantiate() as Node3D
	visual.add_child(m)
	# Our front is -Z; the model faces +Z.
	visual.rotation_degrees.y = 180.0
	visual.scale = Vector3.ONE * model_scale
	var aabb := AABB()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var box := (mi as MeshInstance3D).get_aabb()
		aabb = box if aabb.size == Vector3.ZERO else aabb.merge(box)
	_centre_offset = Vector3(0, aabb.size.y * 0.5 * model_scale, 0)
	_model_radius = maxf(aabb.size.x, aabb.size.y) * 0.5 * model_scale
	_track_eyes = false
	for eye_name in ["eye_L", "eye_R"]:
		var eye := m.find_child(eye_name, true, false) as Node3D
		if eye == null:
			continue
		_eyes.append(eye)
		if eye_glow:
			_glows.append(_add_glow(m, eye.position))
	for pair in [[eyelid_left, eyelid_left_pos, "LidL"], [eyelid_right, eyelid_right_pos, "LidR"]]:
		if pair[0] == null:
			continue
		var lid := (pair[0] as PackedScene).instantiate() as Node3D
		lid.name = pair[2]
		lid.position = pair[1]
		lid.rotation_degrees.x = eyelid_open_deg
		m.add_child(lid)
		_lids.append(lid)


## A soft crimson disc that always faces the camera and keeps the same size on screen.
func _add_glow(parent: Node3D, at: Vector3) -> Sprite3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.3, 1.0))
	grad.set_color(1, Color(0.8, 0.0, 0.1, 0.0))
	grad.add_point(0.25, Color(1.0, 0.1, 0.18, 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = true
	s.pixel_size = 0.00003
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.transparent = true
	s.modulate = Color(1, 1, 1, 0.55)
	s.position = at + Vector3(0, 0, 0.12)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	return s


# --- Placeholder head --------------------------------------------------------
# An original caricature of a nameless official, after the art direction: shelf brow,
# curtain jowls, mail-slot mouth, teacup-handle ears, target eyes. Built from primitives
# so it can be replaced wholesale. Front is -Z; units are a 6 m head, scaled up.

const STONE := Color(0.5, 0.46, 0.58)
const SHADE := Color(0.42, 0.36, 0.52)
const DARK := Color(0.08, 0.04, 0.12)
const WHITE := Color(0.9, 0.86, 0.94)
## The target rings always glow a little, so from far away the eyes read as two red lights.
const IDLE_GLOW := 2.5


func _build_placeholder() -> void:
	var stone := _mat(STONE)
	var shade := _mat(SHADE)
	var dark := _mat(DARK)
	var white := _mat(WHITE)
	_pupil_mat = _mat(Color(0.5, 0.0, 0.08))
	_pupil_mat.emission_enabled = true
	_pupil_mat.emission = Color(1.0, 0.06, 0.18)
	_pupil_mat.emission_energy_multiplier = IDLE_GLOW

	_sphere(visual, stone, 2.6, Vector3.ZERO, Vector3(1.0, 1.18, 0.92))            # skull
	_sphere(visual, dark, 2.62, Vector3(0, 1.75, 0.5), Vector3(1.04, 0.6, 0.95))    # hair cap
	# Shelf brow: one heavy ledge across the whole face.
	_box(visual, shade, Vector3(3.6, 0.42, 0.9), Vector3(0, 1.12, -2.05))
	# Curtain jowls: long folds hanging past the jaw.
	for side in [-1.0, 1.0]:
		_sphere(visual, shade, 0.9, Vector3(1.45 * side, -1.55, -1.0), Vector3(0.85, 1.6, 0.9))
	# Teacup-handle ears: loops standing off the sides of the head.
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.68
		torus.material = stone
		ear.mesh = torus
		ear.position = Vector3(2.75 * side, 0.1, 0.1)
		ear.rotation_degrees = Vector3(0, 0, 90)
		ear.scale = Vector3(1.0, 1.0, 1.35)
		ear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(ear)
	# A long, heavy nose.
	var nose := _capsule(visual, stone, 0.38, 1.7, Vector3(0, -0.05, -2.35))
	nose.rotation_degrees.x = -62.0
	_sphere(visual, shade, 0.52, Vector3(0, -0.6, -2.85), Vector3(1.0, 0.9, 1.0))
	# Mail-slot mouth: a thin dark slot with a lip of stone.
	_box(visual, dark, Vector3(1.5, 0.12, 0.6), Vector3(0, -1.32, -2.0))
	_box(visual, shade, Vector3(1.8, 0.1, 0.5), Vector3(0, -1.18, -2.08))

	for side in [-1.0, 1.0]:
		# Socket holds the eyeball under the brow; close_eyes() brings the lids down.
		var socket := Node3D.new()
		socket.name = "SocketL" if side < 0.0 else "SocketR"
		socket.position = Vector3(0.9 * side, 0.5, -1.98)
		visual.add_child(socket)
		_sphere(socket, white, 0.6, Vector3.ZERO, Vector3.ONE)
		var eye := Node3D.new()
		eye.name = "EyeL" if side < 0.0 else "EyeR"
		socket.add_child(eye)
		# Target eye: red ring first (it scales with the stare), black pupil in its centre.
		var ring := _sphere(eye, _pupil_mat, 0.36, Vector3(0, 0, -0.5), Vector3(1, 1, 0.3))
		_sphere(eye, _mat(Color.BLACK), 0.16, Vector3(0, 0, -0.6), Vector3(1, 1, 0.4))
		_base_pupil_scale = ring.scale
		# Eyelid: a shell of stone above the eye that drops over it.
		var lid := _sphere(socket, stone, 0.66, Vector3(0, 0.0, 0.0), Vector3(1, 1, 1))
		lid.name = "Lid"
		lid.position = Vector3(0, 1.1, 0)
		lid.visible = false


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	# A cold rim so the silhouette reads against the night sky from far away.
	m.rim_enabled = true
	m.rim = 0.8
	m.rim_tint = 0.5
	return m


func _sphere(parent: Node3D, mat: Material, radius: float, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	return _add(parent, mesh, mat, pos, scl)


func _capsule(parent: Node3D, mat: Material, radius: float, height: float, pos: Vector3) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _add(parent, mesh, mat, pos, Vector3.ONE)


func _box(parent: Node3D, mat: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, mat, pos, Vector3.ONE)


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
