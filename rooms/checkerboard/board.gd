@tool
extends Node3D
## The checkerboard. Builds floor, rim, socket pit and glow strips from a few
## numbers, so the layout can be tuned in the inspector and seen in the editor.
## The board is centred on this node; tile edges sit on multiples of tile_size.

const FLOOR_SHADER := preload("res://rooms/checkerboard/checker_floor.gdshader")
## Physics layer 5: only the balls collide with it (keeps them off the entry path).
const BALL_ONLY_LAYER := 1 << 4

@export var tiles := 10:
	set(v):
		tiles = maxi(2, v - v % 2)
		_rebuild()
@export var tile_size := 1.5:
	set(v):
		tile_size = v
		_rebuild()
## Tile (column, row) counted from the -X/-Z corner that is a hole the balls can drop into.
@export var socket_tile := Vector2i(1, 1):
	set(v):
		socket_tile = v
		_rebuild()
@export var rim_height := 0.45:
	set(v):
		rim_height = v
		_rebuild()
## Width of the gap in the +Z rim where the little man walks in.
@export var entry_width := 3.0:
	set(v):
		entry_width = v
		_rebuild()

var floor_material: ShaderMaterial
## Glow strip per edge: 0 = +X, 1 = -X, 2 = +Z, 3 = -Z.
var edge_strips: Array[MeshInstance3D] = []
var socket_light: OmniLight3D
var socket_core: MeshInstance3D
var socket_halo: MeshInstance3D

var _built: Node3D


func _ready() -> void:
	_rebuild()


func half() -> float:
	return tiles * tile_size * 0.5


func socket_center() -> Vector3:
	return to_global(Vector3(
		-half() + (socket_tile.x + 0.5) * tile_size, 0.0,
		-half() + (socket_tile.y + 0.5) * tile_size))


func is_on_board(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) < half() and absf(p.z) < half()


## True on the dark tiles: the ones the tide can grab you on.
func is_black_at(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	# Same formula as checker_floor.gdshader (world space). The board sits at the
	# room origin and half() is a whole number of tiles, so the two agree.
	return posmod(floori(p.x / tile_size) + floori(p.z / tile_size), 2) == 1


func edge_index(dir: Vector2) -> int:
	if absf(dir.x) > absf(dir.y):
		return 0 if dir.x > 0.0 else 1
	return 2 if dir.y > 0.0 else 3


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _built:
		_built.free()
	edge_strips.clear()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built, false, Node.INTERNAL_MODE_FRONT)

	floor_material = ShaderMaterial.new()
	floor_material.shader = FLOOR_SHADER
	floor_material.set_shader_parameter(&"tile_size", tile_size)

	var h := half()
	var t := tile_size
	var depth := 1.0
	# Floor as four slabs around the socket hole.
	var sx0 := -h + socket_tile.x * t
	var sz0 := -h + socket_tile.y * t
	_slab(Vector3(-h, -depth, -h), Vector3(h, 0, sz0), floor_material)
	_slab(Vector3(-h, -depth, sz0 + t), Vector3(h, 0, h), floor_material)
	_slab(Vector3(-h, -depth, sz0), Vector3(sx0, 0, sz0 + t), floor_material)
	_slab(Vector3(sx0 + t, -depth, sz0), Vector3(h, 0, sz0 + t), floor_material)

	# Socket pit: a floor deeper down, glowing.
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.2, 0.02, 0.06)
	pit_mat.emission_enabled = true
	pit_mat.emission = Color(1.0, 0.3, 0.45)
	pit_mat.emission_energy_multiplier = 2.5
	var c := Vector3(sx0 + t * 0.5, 0, sz0 + t * 0.5)
	socket_core = _slab(Vector3(sx0, -depth - 0.4, sz0), Vector3(sx0 + t, -depth, sz0 + t), pit_mat).get_child(1)
	socket_light = OmniLight3D.new()
	socket_light.position = c + Vector3(0, -0.3, 0)
	socket_light.light_color = Color(1.0, 0.35, 0.5)
	socket_light.light_energy = 1.5
	socket_light.omni_range = 3.5
	_built.add_child(socket_light)
	# Halo on the floor around the hole, so the goal reads from across the board.
	socket_halo = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = t * 0.62
	torus.outer_radius = t * 0.72
	torus.rings = 48
	torus.ring_segments = 8
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = Color(1.0, 0.45, 0.6)
	torus.material = halo_mat
	socket_halo.mesh = torus
	socket_halo.position = c + Vector3(0, 0.02, 0)
	socket_halo.scale = Vector3(1, 0.05, 1)
	socket_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built.add_child(socket_halo)

	# Rim: four walls, with an entry gap on +Z that only the balls collide with.
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.08, 0.03, 0.05)
	rim_mat.roughness = 0.6
	var w := 0.3
	var r := rim_height
	_slab(Vector3(h, 0, -h - w), Vector3(h + w, r, h + w), rim_mat)        # +X
	_slab(Vector3(-h - w, 0, -h - w), Vector3(-h, r, h + w), rim_mat)      # -X
	_slab(Vector3(-h, 0, -h - w), Vector3(h, r, -h), rim_mat)              # -Z
	var g := entry_width * 0.5
	_slab(Vector3(-h, 0, h), Vector3(-g, r, h + w), rim_mat)               # +Z left
	_slab(Vector3(g, 0, h), Vector3(h, r, h + w), rim_mat)                 # +Z right
	var gate := _slab(Vector3(-g, 0, h), Vector3(g, r, h + w), null)
	gate.collision_layer = BALL_ONLY_LAYER
	gate.collision_mask = 0

	# Glow strips along each edge's top. The room lights the downhill one.
	var strip_specs := [
		[Vector3(h + w * 0.5, r, 0), Vector3(w, 0.06, h * 2 + w * 2)],
		[Vector3(-h - w * 0.5, r, 0), Vector3(w, 0.06, h * 2 + w * 2)],
		[Vector3(0, r, h + w * 0.5), Vector3(h * 2, 0.06, w)],
		[Vector3(0, r, -h - w * 0.5), Vector3(h * 2, 0.06, w)],
	]
	for spec in strip_specs:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.25, 0.02, 0.04)
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.08, 0.12)
		sm.emission_energy_multiplier = 0.0
		bm.material = sm
		m.mesh = bm
		m.position = spec[0]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_built.add_child(m)
		edge_strips.append(m)


func set_edge_glow(index: int, amount: float) -> void:
	if index < 0 or index >= edge_strips.size():
		return
	var mat: StandardMaterial3D = (edge_strips[index].mesh as BoxMesh).material
	mat.emission_energy_multiplier = amount * 4.0


## Box from min corner to max corner, with collision on layer 1 (and a mesh if mat given).
func _slab(a: Vector3, b: Vector3, mat: Material) -> StaticBody3D:
	var size := (b - a).abs()
	var body := StaticBody3D.new()
	body.position = (a + b) * 0.5
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		body.add_child(mi)
	_built.add_child(body)
	return body
