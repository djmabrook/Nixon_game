@tool
extends Node3D
## The plain. A checkerboard that runs to every horizon, with a shallow crater at
## its centre and the socket at the crater's heart. Built from a few numbers so it
## can be tuned in the inspector and seen in the editor.
## The board sits at the room origin; tile edges sit on multiples of tile_size.

const FLOOR_SHADER := preload("res://rooms/checkerboard/checker_floor.gdshader")

## Size of one tile, in metres. The little man is 1.2 m tall.
@export var tile_size := 6.0:
	set(v):
		tile_size = v
		_rebuild()
## Half-width of the solid floor. Past play_radius the plain itself draws you back,
## so nobody ever reaches this edge.
@export var floor_half := 300.0:
	set(v):
		floor_half = v
		_rebuild()
## How far out the visible plain runs (it fades into the haze long before this).
@export var visual_half := 3000.0:
	set(v):
		visual_half = v
		_rebuild()
## Radius you can wander before the plain draws you back toward the middle.
@export var play_radius := 220.0
@export var crater_radius := 45.0:
	set(v):
		crater_radius = v
		_rebuild()
@export var crater_depth := 6.0:
	set(v):
		crater_depth = v
		_rebuild()
## The socket: a round hole at the crater's centre.
@export var socket_radius := 2.4:
	set(v):
		socket_radius = v
		_rebuild()
@export var pit_depth := 3.0:
	set(v):
		pit_depth = v
		_rebuild()
## Mesh resolution of the crater, in metres.
@export var crater_step := 1.0:
	set(v):
		crater_step = maxf(v, 0.1)
		_rebuild()

var floor_material: ShaderMaterial
var socket_light: OmniLight3D
var socket_halo: MeshInstance3D

var _built: Node3D


func _ready() -> void:
	_rebuild()


## The bottom of the socket hole (centre of the crater).
func socket_center() -> Vector3:
	return to_global(Vector3(0, -crater_depth, 0))


func crater_center() -> Vector3:
	return to_global(Vector3.ZERO)


## Ground height at a point (ignores the socket hole).
func height_at(world_pos: Vector3) -> float:
	var p := to_local(world_pos)
	var r := Vector2(p.x, p.z).length()
	return _bowl(r)


func is_in_play(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return Vector2(p.x, p.z).length() < play_radius


func is_on_floor_area(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) < floor_half and absf(p.z) < floor_half


## True on the dark tiles: the ones the tide can grab you on.
## Same formula as checker_floor.gdshader (world space; the board sits at the room origin).
func is_black_at(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return posmod(floori(p.x / tile_size) + floori(p.z / tile_size), 2) == 1


func _bowl(r: float) -> float:
	var k := 1.0 - smoothstep(crater_radius * 0.15, crater_radius, r)
	return -crater_depth * k


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _built:
		_built.free()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built, false, Node.INTERNAL_MODE_FRONT)

	var cr := crater_radius
	floor_material = ShaderMaterial.new()
	floor_material.shader = FLOOR_SHADER
	floor_material.set_shader_parameter(&"tile_size", tile_size)
	floor_material.set_shader_parameter(&"hole_min", Vector2(-cr, -cr))
	floor_material.set_shader_parameter(&"hole_max", Vector2(cr, cr))

	# Visible plain: one huge quad with the crater square cut out by the shader.
	var plain := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(visual_half * 2.0, visual_half * 2.0)
	pm.material = floor_material
	plain.mesh = pm
	plain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plain.set_instance_shader_parameter(&"use_hole", 1.0)
	_built.add_child(plain)

	# Solid plain: four collision slabs around the crater square (no mesh).
	var h := floor_half
	_slab(Vector3(-h, -1, -h), Vector3(h, 0, -cr))
	_slab(Vector3(-h, -1, cr), Vector3(h, 0, h))
	_slab(Vector3(-h, -1, -cr), Vector3(-cr, 0, cr))
	_slab(Vector3(cr, -1, -cr), Vector3(h, 0, cr))

	# The crater: a gentle bowl, drawn and collided from the same mesh.
	var crater_mesh := _crater_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = crater_mesh
	mi.material_override = floor_material
	_built.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = crater_mesh.create_trimesh_shape()
	body.add_child(cs)
	_built.add_child(body)

	# The socket itself: a round pit with a glowing floor.
	var s := socket_center()
	var wall := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = socket_radius
	tube.bottom_radius = socket_radius
	tube.height = pit_depth
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 32
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.14, 0.03, 0.07)
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tube.material = wall_mat
	wall.mesh = tube
	wall.position = s + Vector3(0, -pit_depth * 0.5, 0)
	_built.add_child(wall)
	var pit_body := StaticBody3D.new()
	pit_body.position = s + Vector3(0, -pit_depth - 0.25, 0)
	var pit_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = socket_radius + 0.5
	cyl.height = 0.5
	pit_shape.shape = cyl
	pit_body.add_child(pit_shape)
	var pit_floor := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = socket_radius
	disc.bottom_radius = socket_radius
	disc.height = 0.5
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.2, 0.02, 0.06)
	pit_mat.emission_enabled = true
	pit_mat.emission = Color(1.0, 0.3, 0.45)
	pit_mat.emission_energy_multiplier = 3.0
	disc.material = pit_mat
	pit_floor.mesh = disc
	pit_body.add_child(pit_floor)
	_built.add_child(pit_body)

	socket_light = OmniLight3D.new()
	socket_light.position = s + Vector3(0, -1.0, 0)
	socket_light.light_color = Color(1.0, 0.35, 0.5)
	socket_light.light_energy = 4.0
	socket_light.omni_range = 12.0
	_built.add_child(socket_light)

	socket_halo = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = socket_radius + 0.4
	torus.outer_radius = socket_radius + 0.7
	torus.rings = 64
	torus.ring_segments = 8
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = Color(1.0, 0.45, 0.6)
	torus.material = halo_mat
	socket_halo.mesh = torus
	socket_halo.position = s + Vector3(0, 0.05, 0)
	socket_halo.scale = Vector3(1, 0.05, 1)
	socket_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built.add_child(socket_halo)


## A square grid over the crater; heights follow the bowl, with a round hole cut
## at the centre for the socket (triangles inside it are dropped).
func _crater_mesh() -> ArrayMesh:
	var cr := crater_radius
	var n := int(ceil(cr * 2.0 / crater_step))
	var step := cr * 2.0 / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert := func(ix: int, iz: int) -> Vector3:
		var x := -cr + ix * step
		var z := -cr + iz * step
		var r := Vector2(x, z).length()
		# Snap the ring nearest the socket onto its rim so the hole is round.
		if r < socket_radius + step and r > 0.0001:
			var rim := Vector2(x, z).normalized() * socket_radius
			if r < socket_radius:
				return Vector3(rim.x, _bowl(socket_radius), rim.y)
		return Vector3(x, _bowl(r), z)
	for iz in n:
		for ix in n:
			var a: Vector3 = vert.call(ix, iz)
			var b: Vector3 = vert.call(ix + 1, iz)
			var c: Vector3 = vert.call(ix + 1, iz + 1)
			var d: Vector3 = vert.call(ix, iz + 1)
			for tri in [[a, b, c], [a, c, d]]:
				var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if Vector2(centre.x, centre.z).length() < socket_radius * 0.98:
					continue
				st.add_vertex(tri[0])
				st.add_vertex(tri[1])
				st.add_vertex(tri[2])
	st.generate_normals()
	return st.commit()


func _slab(a: Vector3, b: Vector3) -> StaticBody3D:
	var size := (b - a).abs()
	var body := StaticBody3D.new()
	body.position = (a + b) * 0.5
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	_built.add_child(body)
	return body
