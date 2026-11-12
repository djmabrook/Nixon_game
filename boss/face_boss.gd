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

@export_group("Hunt")
## Top speed while unseen, in m/s.
@export var chase_speed := 24.0
## How fast it reaches top speed once you look away.
@export var acceleration := 3.0
## Horizontal distance at which it has the player.
@export var catch_radius := 270.0
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

@export_group("Shape")
## Placeholder head scale (1 = a 6 m head). 90 makes it a mountain, about 550 m tall.
@export var head_scale := 90.0
## Head centre height when far away, and when it is right on top of him.
@export var hover_far := 300.0
@export var hover_near := 300.0
## Horizontal distances between which it sinks from hover_far to hover_near.
@export var sink_from := 1200.0
@export var sink_to := 300.0
## Screen pixels a point must be inside the view before it counts as seen.
@export var visible_margin_px := 4.0

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

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"face_boss")
	_awake_in = wake_delay
	if visual.get_child_count() == 0:
		_build_placeholder()
		# Chin tipped down toward the floor, so the eyes meet the little man below.
		visual.scale = Vector3.ONE * head_scale
		visual.rotation_degrees.x = -14.0
	for eye_name in [&"EyeL", &"EyeR"]:
		var eye := visual.find_child(String(eye_name), true, false) as Node3D
		if eye:
			_eyes.append(eye)
	if distant:
		active = false
		set_physics_process(false)
		if _pupil_mat:
			_pupil_mat.emission_energy_multiplier = 8.0
			_pupil_mat.emission = Color(1.0, 0.05, 0.1)


## Shut the eyes for good: no stare, no movement, lights out.
func close_eyes(time := 2.0) -> void:
	active = false
	_closed = true
	for socket_name in [&"SocketL", &"SocketR"]:
		var socket := visual.find_child(String(socket_name), true, false) as Node3D
		if socket:
			create_tween().set_trans(Tween.TRANS_SINE).tween_property(socket, "scale:y", 0.04, time)
	if _pupil_mat:
		create_tween().tween_property(_pupil_mat, "emission_energy_multiplier", 0.0, time * 0.5)


## Rough radius of the head in metres, used for visibility samples.
func head_radius() -> float:
	return 2.8 * visual.scale.x


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
		global_position.y = _hover_for(player)
	_update_watched(cam)
	_update_sight(player, delta)
	_track_with_eyes(player, delta)
	if _caught or not active:
		_velocity = Vector3.ZERO
		motion = move_toward(motion, 0.0, delta * 4.0)
		return

	_awake_in -= delta
	if is_watched or _awake_in > 0.0:
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
	var to := target + Vector3.UP * head_radius() * 0.4
	t.tween_property(self, "global_position", global_position.lerp(to, 0.8), 0.7)
	t.tween_property(visual, "rotation_degrees:x", -35.0, 0.7)


func _hover_for(player: Node3D) -> float:
	var k := inverse_lerp(sink_to, sink_from, flat_distance_to(player.global_position))
	return lerpf(hover_near, hover_far, clampf(k, 0.0, 1.0))


func _update_watched(cam: Camera3D) -> void:
	var c := global_position
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
	# Sink lower as it closes in, with a slow, heavy bob. Also only while unseen.
	_bob_time += delta
	var goal_y := _hover_for(player) + sin(_bob_time * 1.3) * head_radius() * 0.04
	global_position.y = move_toward(global_position.y, goal_y, chase_speed * 0.6 * delta)


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
	for eye in _eyes:
		var pupil := eye.get_child(0) as Node3D if eye.get_child_count() > 0 else null
		if pupil:
			# Pupils contract to pinpricks when it locks on.
			pupil.scale = _base_pupil_scale * lerpf(1.0, 0.55, stare)


func _track_with_eyes(player: Player, delta: float) -> void:
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


# --- Placeholder head --------------------------------------------------------
# An original caricature built from primitives: a long, heavy head with a
# bulbous nose, low jowls, thick brows, and wide unblinking eyes. Front is -Z.

const SKIN := Color(0.6, 0.5, 0.74)
const SHADE := Color(0.4, 0.3, 0.55)
const DARK := Color(0.10, 0.04, 0.16)
const WHITE := Color(0.9, 0.86, 0.94)
## The pupils always glow a little, so from far away the eyes read as two red lights.
const IDLE_GLOW := 1.2


func _build_placeholder() -> void:
	var skin := _mat(SKIN)
	var shade := _mat(SHADE)
	var dark := _mat(DARK)
	var white := _mat(WHITE)
	_pupil_mat = _mat(Color.BLACK)
	_pupil_mat.emission_enabled = true
	_pupil_mat.emission = Color(1.0, 0.08, 0.25)
	_pupil_mat.emission_energy_multiplier = IDLE_GLOW

	_sphere(visual, skin, 2.6, Vector3.ZERO, Vector3(1.0, 1.18, 0.92))           # skull
	_sphere(visual, shade, 2.4, Vector3(0, -2.9, 0.6), Vector3(1.5, 0.75, 1.3))   # the mountain it rises from
	_sphere(visual, dark, 2.62, Vector3(0, 1.7, 0.45), Vector3(1.04, 0.62, 0.95)) # hair cap
	_sphere(visual, shade, 0.95, Vector3(-1.35, -1.25, -1.2), Vector3.ONE)       # jowls
	_sphere(visual, shade, 0.95, Vector3(1.35, -1.25, -1.2), Vector3.ONE)
	_sphere(visual, skin, 0.62, Vector3(-2.55, 0.1, 0.0), Vector3(0.35, 1.0, 0.7)) # ears
	_sphere(visual, skin, 0.62, Vector3(2.55, 0.1, 0.0), Vector3(0.35, 1.0, 0.7))

	var nose := _capsule(visual, skin, 0.36, 1.5, Vector3(0, -0.05, -2.35))
	nose.rotation_degrees.x = -62.0
	_sphere(visual, shade, 0.5, Vector3(0, -0.55, -2.85), Vector3(1.0, 0.9, 1.0)) # nose tip

	for side in [-1.0, 1.0]:
		var brow := _box(visual, dark, Vector3(1.25, 0.26, 0.4), Vector3(0.88 * side, 1.12, -2.08))
		brow.rotation_degrees.z = -14.0 * side
		# Socket holds the eyeball; close_eyes() squashes it shut.
		var socket := Node3D.new()
		socket.name = "SocketL" if side < 0.0 else "SocketR"
		socket.position = Vector3(0.88 * side, 0.48, -1.98)
		visual.add_child(socket)
		_sphere(socket, white, 0.58, Vector3.ZERO, Vector3.ONE)
		var eye := Node3D.new()
		eye.name = "EyeL" if side < 0.0 else "EyeR"
		socket.add_child(eye)
		var pupil := _sphere(eye, _pupil_mat, 0.28, Vector3(0, 0, -0.5), Vector3(1, 1, 0.4))
		_base_pupil_scale = pupil.scale

	_box(visual, dark, Vector3(1.6, 0.16, 0.5), Vector3(0, -1.35, -1.95))         # mouth line
	_box(visual, shade, Vector3(2.0, 0.12, 0.4), Vector3(0, -1.08, -2.05))        # upper lip


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
