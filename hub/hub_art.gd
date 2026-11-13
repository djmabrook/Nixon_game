extends Node3D
## The hub's big set pieces, placed from the approved models in art/models:
## - a strata arch on the beach that frames your first look at the crater,
## - colossal palms (200 m) on rock mesas out at sea,
## - palm islets on the rock islands and in the shallows.
## Everything starts drained and colours in with the inks (group hub_drainable).
## The region doors live with their grooves (props/region_door.gd).

const Palette := preload("res://hub/art_palette.gd")
const ARCH := preload("res://hub/art/models/sand_strata_arch.glb")
const COLOSSAL_PALM := preload("res://hub/art/models/colossal_palm.glb")
const PALM_ISLET := preload("res://hub/art/models/palm_islet.glb")

## Arch: distance from the centre and angle (degrees), on the beach near where you arrive.
@export var arch_at := Vector2(905.0, 31.0)
## Colossal palms out at sea: x = distance, y = angle (degrees).
@export var colossi: Array[Vector2] = [
	Vector2(1750.0, 8.0), Vector2(2050.0, 84.0), Vector2(1600.0, 118.0),
	Vector2(1900.0, 205.0), Vector2(2150.0, 248.0), Vector2(1700.0, 322.0),
]
## Small palm islets in the shallows past the shore.
@export var shallows: Array[Vector2] = [
	Vector2(1090.0, 18.0), Vector2(1130.0, 70.0), Vector2(1070.0, 152.0),
	Vector2(1150.0, 236.0), Vector2(1100.0, 290.0),
]

var color_amount := 0.0:
	set(v):
		color_amount = v
		Palette.apply(_entries, v)

var _entries: Array = []


func _ready() -> void:
	add_to_group(&"hub_drainable")
	var hub := get_parent()
	var sand: Node = hub.get_node("SandVortex")
	var rock_mat: Material = ((hub.get_node("Scenery/IslandWest") as MeshInstance3D).mesh as PrimitiveMesh).material

	# The arch: its opening runs along the radius, so you walk through it toward the crater.
	var arch: Node3D = ARCH.instantiate()
	arch.name = "StrataArch"
	add_child(arch)
	var a := deg_to_rad(arch_at.y)
	var out := Vector3(cos(a), 0.0, sin(a))
	arch.position = sand.ground_point(Vector2(out.x, out.z) * arch_at.x) - Vector3(0, 2.5, 0)
	arch.basis = Basis.looking_at(-out, Vector3.UP)
	Palette.add_collision(arch)

	# Colossal palms, each on its own mesa of the islands' rock.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for k in colossi.size():
		var c := colossi[k]
		var at := _polar(c.x, c.y)
		var mesa := MeshInstance3D.new()
		mesa.name = "Mesa%d" % k
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(70.0, 95.0)
		cm.bottom_radius = cm.top_radius * 1.5
		cm.height = rng.randf_range(50.0, 90.0)
		cm.radial_segments = 7
		cm.rings = 1
		cm.material = rock_mat
		mesa.mesh = cm
		add_child(mesa)
		mesa.position = at + Vector3(0, cm.height * 0.5 - 6.0, 0)
		mesa.rotation.y = rng.randf() * TAU
		var palm: Node3D = COLOSSAL_PALM.instantiate()
		palm.name = "ColossalPalm%d" % k
		add_child(palm)
		palm.position = at + Vector3(0, cm.height - 8.0, 0)
		palm.rotation.y = rng.randf() * TAU
		palm.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)

	# Palm islets: crowning the three rock islands, and scattered in the shallows.
	for island in ["IslandWest", "IslandEast", "IslandNorth"]:
		var isl := hub.get_node("Scenery/" + island) as Node3D
		var top := isl.position + Vector3(0, isl.scale.y * 0.5 * 2.0 - 4.0, 0)
		_islet(top, 7.0 * isl.scale.y / 40.5, rng)
	for s in shallows:
		_islet(_polar(s.x, s.y) + Vector3(0, -1.5, 0), rng.randf_range(4.0, 6.5), rng)

	_entries = Palette.prepare(self)
	Palette.apply(_entries, color_amount)


func _islet(at: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var p: Node3D = PALM_ISLET.instantiate()
	add_child(p)
	p.position = at
	p.scale = Vector3.ONE * s
	p.rotation.y = rng.randf() * TAU


func _polar(dist: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * dist, 0.0, sin(a) * dist)
