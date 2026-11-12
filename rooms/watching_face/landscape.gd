extends Node3D
## The land of the Watcher's mountain, built from code so its numbers live in one place.
##
## From the spawn on the open grid (+Z) toward the face (-Z):
##   the plain -> a horizon-wide staircase -> his shoulders (a broad suit-grey plateau)
##   -> the tie road climbing his chest between the lapels -> the collar under his chin.
## The face rests on the collar. The black disc lies behind his head.
##
## ground_height(x, z) answers the height of this land anywhere, so the face can ride it
## and cover can stand on it without raycasts. Units are metres. Placeholder geometry.

const STAIR_BOTTOM_Z := 560.0
const STAIR_TOP_Z := 320.0
const STAIR_RISE := 80.0
const STAIR_STEPS := 40
const STAIR_HALF_W := 700.0

const SHOULDER_Y := 80.0
const SHOULDER_HALF_W := 800.0
const BACK_Z := -1300.0

const CHEST_LOW_Z := 150.0
const CHEST_TOP_Z := -450.0
const CHEST_HALF_W := 350.0
const COLLAR_Y := 200.0
const COLLAR_HALF_W := 450.0

## Where the tie road meets the knot: the foot of the face.
const FOOT := Vector3(0, COLLAR_Y, -440)

const MIC_TOWER := preload("res://rooms/watching_face/models/microphone_tower.glb")

@export var cover_seed := 7
@export var mast_count := 90
@export var telephone_count := 22

## Microphone heads, so the room can turn them toward footsteps.
var mic_heads: Array[Node3D] = []
## Telephones, so the room can ring the nearest one.
var telephones: Array[Node3D] = []

var _mats := {}


func _ready() -> void:
	_build_stairs()
	_build_bust()
	_build_tie_road()
	_raise_cover()


## Height of the land at (x, z).
func ground_height(x: float, z: float) -> float:
	var ax := absf(x)
	if ax <= COLLAR_HALF_W and z <= CHEST_TOP_Z and z >= BACK_Z:
		return COLLAR_Y
	if ax <= CHEST_HALF_W and z < CHEST_LOW_Z and z > CHEST_TOP_Z:
		return lerpf(SHOULDER_Y, COLLAR_Y, (CHEST_LOW_Z - z) / (CHEST_LOW_Z - CHEST_TOP_Z))
	if ax <= SHOULDER_HALF_W and z <= STAIR_TOP_Z and z >= BACK_Z:
		return SHOULDER_Y
	if ax <= STAIR_HALF_W and z > STAIR_TOP_Z and z <= STAIR_BOTTOM_Z:
		return STAIR_RISE * (STAIR_BOTTOM_Z - z) / (STAIR_BOTTOM_Z - STAIR_TOP_Z)
	return 0.0


# --- Horizon Hall staircase --------------------------------------------------

func _build_stairs() -> void:
	var stone_a := _mat("step_a", Color(0.1, 0.08, 0.16))
	var stone_b := _mat("step_b", Color(0.14, 0.11, 0.22))
	var edge := _mat("step_edge", Color(0.6, 0.45, 1.0), true)
	var depth := (STAIR_BOTTOM_Z - STAIR_TOP_Z) / STAIR_STEPS
	var rise := STAIR_RISE / STAIR_STEPS
	for i in STAIR_STEPS:
		var top := rise * (i + 1)
		var z_far := STAIR_BOTTOM_Z - depth * (i + 1)
		var z_near := z_far + depth
		_visual_box(Vector3(STAIR_HALF_W * 2.0, top, depth), Vector3(0, top * 0.5, (z_far + z_near) * 0.5),
				stone_a if i % 2 == 0 else stone_b)
		# A thin line of light on every nosing, so the flight reads from kilometres away.
		_visual_box(Vector3(STAIR_HALF_W * 2.0, 0.2, 0.2), Vector3(0, top, z_near), edge)
	# Walk on a smooth ramp under the steps.
	_solid_wedge(STAIR_HALF_W, STAIR_BOTTOM_Z, STAIR_TOP_Z, 0.0, 0.0, STAIR_RISE, null)


# --- The bust: shoulders, chest, lapels, collar, knot ---------------------------

func _build_bust() -> void:
	var suit := _suit_mat()
	var lapel := _mat("lapel", Color(0.2, 0.19, 0.24))
	var shirt := _mat("shirt", Color(0.85, 0.82, 0.86))
	var knot := _mat("knot", Color(0.25, 0.14, 0.6))
	# Shoulders: one plateau from the top of the stairs to behind his head.
	_solid_wedge(SHOULDER_HALF_W, STAIR_TOP_Z, BACK_Z, 0.0, SHOULDER_Y, SHOULDER_Y, suit)
	# Chest: a long slope up to the collar.
	_solid_wedge(CHEST_HALF_W, CHEST_LOW_Z, CHEST_TOP_Z, SHOULDER_Y, SHOULDER_Y, COLLAR_Y, suit)
	# Collar: where the chin rests, wide enough to walk around the head.
	_solid_wedge(COLLAR_HALF_W, CHEST_TOP_Z, BACK_Z, SHOULDER_Y, COLLAR_Y, COLLAR_Y, suit)
	# Lapels rise on both sides of the chest, walls that funnel the road.
	for side in [-1.0, 1.0]:
		var lap := _solid_wedge(120.0, CHEST_LOW_Z, CHEST_TOP_Z, SHOULDER_Y, SHOULDER_Y + 10.0, COLLAR_Y + 40.0, lapel)
		lap.position.x = (CHEST_HALF_W + 120.0) * side
		# Shirt collar wings either side of the knot.
		var wing := _solid_wedge(70.0, CHEST_TOP_Z + 60.0, CHEST_TOP_Z - 40.0, COLLAR_Y, COLLAR_Y + 4.0, COLLAR_Y + 30.0, shirt)
		wing.position.x = 110.0 * side
	# The knot, under the chin, where the road ends.
	var k := _solid_wedge(20.0, FOOT.z - 25.0, FOOT.z - 60.0, COLLAR_Y, COLLAR_Y + 14.0, COLLAR_Y + 18.0, knot)
	k.name = "Knot"


func _suit_mat() -> ShaderMaterial:
	if not _mats.has("suit"):
		var m := ShaderMaterial.new()
		m.shader = preload("res://rooms/watching_face/suit.gdshader")
		_mats["suit"] = m
	return _mats["suit"]


# --- The tie road -------------------------------------------------------------

func _build_tie_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_start := STAIR_TOP_Z
	var z_end := FOOT.z + 10.0
	var segments := 160
	for i in segments:
		var za := lerpf(z_start, z_end, float(i) / segments)
		var zb := lerpf(z_start, z_end, float(i + 1) / segments)
		var wa := _tie_half_width(za)
		var wb := _tie_half_width(zb)
		var ya := ground_height(0.0, za) + 0.08
		var yb := ground_height(0.0, zb) + 0.08
		var a0 := Vector3(-wa, ya, za)
		var a1 := Vector3(wa, ya, za)
		var b0 := Vector3(-wb, yb, zb)
		var b1 := Vector3(wb, yb, zb)
		for v in [[a0, 0.0], [b0, 0.0], [a1, 1.0], [a1, 1.0], [b0, 0.0], [b1, 1.0]]:
			st.set_uv(Vector2(v[1], 0.0))
			st.add_vertex(v[0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "TieRoad"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://rooms/watching_face/road.gdshader")
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The tie: a wide blade at the bottom of his chest, narrowing up to the knot.
func _tie_half_width(z: float) -> float:
	var k := clampf((STAIR_TOP_Z - z) / (STAIR_TOP_Z - FOOT.z), 0.0, 1.0)
	return lerpf(34.0, 16.0, k)


# --- Cover: microphone masts and telephones -----------------------------------

func _raise_cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cover_seed
	var placed: Array[Vector2] = []
	var masts_left := mast_count
	var phones_left := telephone_count
	var tries := 0
	while masts_left + phones_left > 0 and tries < 20000:
		tries += 1
		var p := Vector2(rng.randf_range(-320.0, 320.0), rng.randf_range(FOOT.z + 40.0, 680.0))
		# Keep the road itself and the stairs' flight open; cover stands beside them.
		if absf(p.x) < _tie_half_width(p.y) + 6.0 and p.y < STAIR_TOP_Z:
			continue
		if p.y > STAIR_TOP_Z and p.y < STAIR_BOTTOM_Z:
			continue
		# An open avenue from the spawn to the foot of the stairs.
		if p.y > STAIR_BOTTOM_Z and absf(p.x) < 45.0:
			continue
		var gap := 26.0
		var crowded := false
		for q in placed:
			if q.distance_to(p) < gap:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		# Masts grow thicker toward the face; telephones sit on the open ground.
		var node: Node3D
		var mast_bias := 0.5 if p.y > STAIR_TOP_Z else 0.8
		if masts_left > 0 and (phones_left == 0 or rng.randf() < mast_bias):
			node = _mast(rng)
			masts_left -= 1
		else:
			node = _telephone(rng)
			phones_left -= 1
		node.position = Vector3(p.x, ground_height(p.x, p.y), p.y)
		node.rotation.y = rng.randf() * TAU
		$"../Cover".add_child(node)


func _telephone(rng: RandomNumberGenerator) -> StaticBody3D:
	var body := _cover_body()
	telephones.append(body)
	var s := rng.randf_range(0.85, 1.35)
	var black := _mat("phone", Color(0.04, 0.02, 0.06), false, 0.35)
	var pink := _mat("cord", Color(0.92, 0.9, 0.84), true)
	# A telephone as big as a house, with no dial: a blank face where the dial should be.
	_solid_box(body, black, Vector3(20, 10, 16) * s, Vector3(0, 5, 0) * s)
	_solid_box(body, black, Vector3(16, 4, 12) * s, Vector3(0, 12, 0) * s)
	_solid_box(body, black, Vector3(30, 4, 5) * s, Vector3(0, 17, 0) * s)
	_solid_box(body, black, Vector3(7, 6, 8) * s, Vector3(-13, 15, 0) * s)
	_solid_box(body, black, Vector3(7, 6, 8) * s, Vector3(13, 15, 0) * s)
	_visual_box(Vector3(0.8, 0.8, 34) * s, Vector3(10, 0.4, 24) * s, pink, body)
	return body


func _mast(rng: RandomNumberGenerator) -> StaticBody3D:
	var body := _cover_body()
	# The art's microphone tower (42 m, base radius 13 m), true scale.
	var tower := MIC_TOWER.instantiate() as Node3D
	tower.name = "Head"
	body.add_child(tower)
	mic_heads.append(tower)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 7.0
	shape.height = 42.0
	cs.shape = shape
	cs.position = Vector3(0, 21, 0)
	body.add_child(cs)
	var base := CollisionShape3D.new()
	var bshape := CylinderShape3D.new()
	bshape.radius = 12.0
	bshape.height = 4.0
	base.shape = bshape
	base.position = Vector3(0, 2, 0)
	body.add_child(base)
	return body


# --- Helpers ------------------------------------------------------------------

func _mat(key: String, color: Color, unshaded := false, rim := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.75
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if rim > 0.0:
			m.rim_enabled = true
			m.rim = rim
		_mats[key] = m
	return _mats[key]


func _cover_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group(&"cover")
	return body


## A solid block whose top runs from `y_near` at z_near to `y_far` at z_far.
func _solid_wedge(half_w: float, z_near: float, z_far: float, y_base: float, y_near: float, y_far: float, mat: Material) -> StaticBody3D:
	var pts := PackedVector3Array([
		Vector3(-half_w, y_base, z_near), Vector3(half_w, y_base, z_near),
		Vector3(-half_w, y_base, z_far), Vector3(half_w, y_base, z_far),
		Vector3(-half_w, y_near, z_near), Vector3(half_w, y_near, z_near),
		Vector3(-half_w, y_far, z_far), Vector3(half_w, y_far, z_far),
	])
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)
	if mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var centre := Vector3.ZERO
		for v in pts:
			centre += v / pts.size()
		# Six faces as quads of corner indices; each triangle is wound to face outward.
		for q in [[4, 5, 7, 6], [0, 2, 3, 1], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
			for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				var a: Vector3 = pts[tri[0]]
				var b: Vector3 = pts[tri[1]]
				var c: Vector3 = pts[tri[2]]
				var n := (b - a).cross(c - a)
				if n.length_squared() < 1e-6:
					continue
				n = n.normalized()
				if n.dot((a + b + c) / 3.0 - centre) < 0.0:
					n = -n
					var t := b
					b = c
					c = t
				# Godot treats clockwise as front: emit so the outward normal faces the viewer.
				st.set_normal(n)
				st.add_vertex(a)
				st.set_normal(n)
				st.add_vertex(c)
				st.set_normal(n)
				st.add_vertex(b)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		body.add_child(mi)
	add_child(body)
	return body


func _visual_box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _solid_box(body: StaticBody3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	_visual_box(size, pos, mat, body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _solid_cyl(body: StaticBody3D, mat: Material, bottom: float, top: float, height: float, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 20
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(bottom, top)
	shape.height = height
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
