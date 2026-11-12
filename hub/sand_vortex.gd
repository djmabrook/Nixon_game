@tool
extends StaticBody3D
## The beach and the sinking sand funnel, built from code so the slope, the
## collision and the spiral shader always agree. Shows in the editor too.
## hub.gd asks it for heights (height_at) to stand spawns and markers on the sand.

## Radius of the sand island. Past `shore_radius` it slopes under the sea.
@export var radius := 1150.0:
	set(v):
		radius = v
		_queue_rebuild()
@export var shore_radius := 1000.0:
	set(v):
		shore_radius = v
		_queue_rebuild()
## The whirlpool: a flat-bottomed pit `pit_depth` below the beach, rising to a dune
## ridge `crest_height` above it at `crest_radius`, then easing back down to the beach
## by `dune_foot_radius`. The ridge hides the pit until you climb it.
@export var pit_depth := 60.0:
	set(v):
		pit_depth = v
		_queue_rebuild()
@export var crest_height := 120.0:
	set(v):
		crest_height = v
		_queue_rebuild()
@export var crest_radius := 500.0:
	set(v):
		crest_radius = v
		_queue_rebuild()
@export var dune_foot_radius := 860.0:
	set(v):
		dune_foot_radius = v
		_queue_rebuild()
## Mesh resolution. Rings are packed toward the center where the slope bends.
@export var rings := 240:
	set(v):
		rings = v
		_queue_rebuild()
@export var segments := 384:
	set(v):
		segments = v
		_queue_rebuild()

## The spiral sand material (hub/sand.tres).
@export var material: Material:
	set(v):
		material = v
		if _mesh:
			_mesh.material_override = v

var _rebuild_queued := false
var _radii: PackedFloat32Array = []
var _faces := PackedVector3Array()
# Built at runtime with no owner, so the generated mesh is never saved into hub.tscn.
var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.material_override = material
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	add_child(_shape)
	rebuild()


## Ground height at a distance `r` from the center (local space).
func height_at(r: float) -> float:
	var h: float
	if r <= crest_radius:
		# Crater: flat floor at the pit, a long curving wall up to the ridge.
		var t := r / crest_radius
		h = lerpf(-pit_depth, crest_height, 0.5 - 0.5 * cos(PI * pow(t, 1.15)))
	elif r <= dune_foot_radius:
		var t := (r - crest_radius) / (dune_foot_radius - crest_radius)
		h = crest_height * (0.5 + 0.5 * cos(PI * t))
	else:
		h = 0.0
	return h - 8.0 * smoothstep(shore_radius - 20.0, radius, r)


## Surface normal of the smooth shape at a (local) xz position.
func normal_at(xz: Vector2) -> Vector3:
	var e := 0.25
	var hx := height_at((xz + Vector2(e, 0)).length()) - height_at((xz - Vector2(e, 0)).length())
	var hz := height_at((xz + Vector2(0, e)).length()) - height_at((xz - Vector2(0, e)).length())
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Point on the smooth surface (used to build the mesh).
func smooth_point(xz: Vector2) -> Vector3:
	return Vector3(xz.x, height_at(xz.length()), xz.y)


## Point on the actual triangle mesh under a (local) xz position, so things placed
## with it stand exactly on the collision surface instead of floating or sinking.
func ground_point(xz: Vector2) -> Vector3:
	var r := xz.length()
	if _radii.is_empty() or r >= radius:
		return smooth_point(xz)
	var a := fposmod(atan2(xz.y, xz.x), TAU)
	var s := mini(int(a / TAU * segments), segments - 1)
	var a0 := TAU * float(s) / segments
	var a1 := TAU * float(s + 1) / segments
	var ri := _radii.bsearch(r, false) - 1
	ri = clampi(ri, 0, rings - 1)
	var tris: Array = []
	if ri == 0:
		tris.append([Vector2.ZERO, _ring_pt(1, a1), _ring_pt(1, a0)])
	else:
		var p00 := _ring_pt(ri, a0)
		var p01 := _ring_pt(ri, a1)
		var p10 := _ring_pt(ri + 1, a0)
		var p11 := _ring_pt(ri + 1, a1)
		tris.append([p00, p01, p11])
		tris.append([p00, p11, p10])
	for t in tris:
		var bc := _barycentric(xz, t[0], t[1], t[2])
		if bc.x >= -0.001 and bc.y >= -0.001 and bc.z >= -0.001:
			var h: float = bc.x * height_at(t[0].length()) + bc.y * height_at(t[1].length()) + bc.z * height_at(t[2].length())
			return Vector3(xz.x, h, xz.y)
	return smooth_point(xz)


func _ring_pt(ri: int, a: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * _radii[ri]


static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 0.000001:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_faces = PackedVector3Array()
	_radii.clear()
	_radii.append(0.0)
	for i in range(1, rings + 1):
		var t := float(i) / float(rings)
		_radii.append(radius * pow(t, 1.25))
	var radii := _radii
	# Center fan.
	for s in segments:
		var a0 := TAU * float(s) / segments
		var a1 := TAU * float(s + 1) / segments
		_tri(st, Vector2.ZERO, Vector2(cos(a1), sin(a1)) * radii[1], Vector2(cos(a0), sin(a0)) * radii[1])
	for ri in range(1, rings):
		var r0 := radii[ri]
		var r1 := radii[ri + 1]
		for s in segments:
			var a0 := TAU * float(s) / segments
			var a1 := TAU * float(s + 1) / segments
			var p00 := Vector2(cos(a0), sin(a0)) * r0
			var p01 := Vector2(cos(a1), sin(a1)) * r0
			var p10 := Vector2(cos(a0), sin(a0)) * r1
			var p11 := Vector2(cos(a1), sin(a1)) * r1
			_tri(st, p00, p01, p11)
			_tri(st, p00, p11, p10)
	st.generate_normals()
	var mesh := st.commit()
	_mesh.mesh = mesh
	# Collision from our own vertex list (mesh data isn't readable on the headless renderer).
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	_shape.shape = shape
	_faces = PackedVector3Array()
	_build_shore_wall()


func _tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	for p in [a, c, b]:   # Godot front faces wind clockwise seen from above
		var v := smooth_point(p)
		st.set_uv(p)
		st.add_vertex(v)
		_faces.append(v)


## Invisible ring that keeps the little man on the beach.
func _build_shore_wall() -> void:
	for c in get_children():
		if c.name.begins_with("Wall"):
			remove_child(c)
			c.free()
	var count := 420
	var wall_r := shore_radius - 2.0
	var seg_len := TAU * wall_r / count + 0.3
	for i in count:
		var a := TAU * (float(i) + 0.5) / count
		var col := CollisionShape3D.new()
		col.name = "Wall%d" % i
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len, 20.0, 2.0)
		col.shape = box
		var pos := Vector3(cos(a) * wall_r, 2.0, sin(a) * wall_r)
		add_child(col)
		col.position = pos
		col.rotation.y = -a + PI * 0.5


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()
