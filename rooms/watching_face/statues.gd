extends Node3D
## The stone little men: the ones the stare caught before him. Every one faces the Watcher's
## face, and every one stands where the face could see him (no one was caught out of sight).
##
## The staircase holds a few, far apart (pose a): the first is a surprise, the rest a pattern.
## The upper plain and the lower tie road grow denser, poses a and c. The upper tie road holds
## pose b only, thinning as it climbs. The last is a single b a short walk below the landing,
## alone: the furthest anyone got. None beyond it.

const POSE_A := preload("res://rooms/watching_face/models/stone_littleman_a.glb")
const POSE_B := preload("res://rooms/watching_face/models/stone_littleman_b.glb")
const POSE_C := preload("res://rooms/watching_face/models/stone_littleman_c.glb")

@export var statue_seed := 11
@export var plain_count := 22

var _face: FaceBoss
var _land: Node3D
var _rng := RandomNumberGenerator.new()
## Every statue raised, so tests can count and check them.
var raised: Array[Node3D] = []


## Call once the physics world is ready (the sight checks raycast).
func raise(face: FaceBoss, land: Node3D) -> void:
	_face = face
	_land = land
	_rng.seed = statue_seed
	# The staircase: three, far apart, up the flight.
	for p in [Vector2(-17.0, 588.0), Vector2(13.0, 528.0), Vector2(-8.0, 472.0)]:
		_place_on_land(POSE_A, p)
	# The upper plain: denser toward him, a and c, never in a mast's or telephone's shadow.
	var tip_z: float = face.catch_world_point().z
	var placed := 0
	var tries := 0
	while placed < plain_count and tries < 600:
		tries += 1
		# Squaring the random pulls the spread toward the face end of the plain.
		var k := 1.0 - pow(_rng.randf(), 2.0)
		var z := lerpf(land.STAIR_TOP_Z - 20.0, tip_z + 30.0, k)
		var p := Vector2(_rng.randf_range(-260.0, 260.0) * lerpf(1.0, 0.5, k), z)
		if _place_on_land(POSE_C if _rng.randf() < 0.35 else POSE_A, p):
			placed += 1
	# The lower tie road (native z 7.0 down to 5.0): a and c, denser as it rises.
	for i in 7:
		var nz := lerpf(7.0, 5.0, sqrt(float(i) / 6.0))
		_place_on_him(POSE_C if i % 3 == 1 else POSE_A, Vector2(_rng.randf_range(-0.22, 0.22), nz))
	# The upper tie road (native z 4.8 up to 3.6): pose b only, further apart as it climbs.
	var nz2 := 4.8
	var gap := 0.18
	while nz2 > 3.6:
		_place_on_him(POSE_B, Vector2(_rng.randf_range(-0.16, 0.16), nz2))
		nz2 -= gap
		gap *= 1.45
	# The furthest anyone got: alone, a short walk below the landing, where the eyes still
	# reach (closer in, the chin hides you).
	var last := 3.2
	while not _place_on_him(POSE_B, Vector2(0.05, last)) and last < 3.6:
		last += 0.04


func _place_on_land(scene: PackedScene, p: Vector2) -> bool:
	var at := Vector3(p.x, _land.ground_height(p.x, p.y), p.y)
	if not _in_sight(at):
		return false
	_add(scene, at, self)
	return true


## On the Watcher's body, in his model's units; the statue rides with him.
func _place_on_him(scene: PackedScene, native: Vector2) -> bool:
	var top := _face.model_point(Vector3(native.x, 4.0, native.y))
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 400.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider != _face.climb_body or not _in_sight(hit.position):
		return false
	_add(scene, hit.position, _face)
	return true


func _add(scene: PackedScene, at: Vector3, parent: Node3D) -> void:
	var s := scene.instantiate() as Node3D
	s.name = "Statue"
	parent.add_child(s)
	s.global_position = at
	_face_the_face(s)
	raised.append(s)


## Front is +Z: turn him (upright) toward the face.
func _face_the_face(s: Node3D) -> void:
	var to := _face.centre() - s.global_position
	to.y = 0.0
	if to.length() > 0.1:
		s.global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)


## Could the eyes see a man standing here?
func _in_sight(at: Vector3) -> bool:
	var to := at + Vector3.UP * 1.2
	var from: Vector3 = _face._eye_centre()
	from += (to - from).normalized() * _face.model_scale * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The highest statue on him, in his model's units (z), or INF if none: the furthest anyone got.
func furthest_native_z() -> float:
	var best := INF
	for st in raised:
		if st.get_parent() == _face:
			best = minf(best, _face.visual.to_local(st.global_position).z)
	return best
