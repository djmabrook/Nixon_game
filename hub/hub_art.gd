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
const STONE_MAN := preload("res://hub/art/models/stone_littleman_c.glb")
## The stone little man (pose c, looking up): one of the men the stare caught before him.
## He stands on the beach just ahead of where the little man washes up, plinth half
## buried, facing across the crater toward the Watcher. Stone, so he never drains or
## changes, not even at dawn. x = distance from the centre, y = angle (degrees).
@export var stone_man_at := Vector2(935.0, 43.0)
const PALM_MESA := preload("res://hub/art/models/palm_mesa.glb")
## The trunk socket on the mesa's top, and how far each mesa stands in the sea.
const MESA_SOCKET := Vector3(0, 56.0, 0)
const MESA_SINK := 6.0
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

const DAWN_RUST := Color(0.29, 0.12, 0.07)

var color_amount := 0.0:
	set(v):
		color_amount = v
		_refresh()
## 0 night to 1 dawn: the palms go dark rust silhouettes against the dawn.
var dawn := 0.0:
	set(v):
		dawn = v
		_refresh()

var _entries: Array = []
var _palm_entries: Array = []


func _refresh() -> void:
	Palette.apply(_entries, color_amount)
	Palette.apply(_palm_entries, color_amount)
	if dawn > 0.0:
		for e in _palm_entries:
			var m: StandardMaterial3D = e[0]
			m.albedo_color = m.albedo_color.lerp(DAWN_RUST, dawn)


func _ready() -> void:
	add_to_group(&"hub_drainable")
	var hub := get_parent()
	var sand: Node = hub.get_node("SandVortex")

	# The arch: its opening runs along the radius, so you walk through it toward the crater.
	var arch: Node3D = ARCH.instantiate()
	arch.name = "StrataArch"
	add_child(arch)
	var a := deg_to_rad(arch_at.y)
	var out := Vector3(cos(a), 0.0, sin(a))
	arch.position = sand.ground_point(Vector2(out.x, out.z) * arch_at.x) - Vector3(0, 2.5, 0)
	arch.basis = Basis.looking_at(-out, Vector3.UP)
	Palette.add_collision(arch)

	# The stone little man, the first human shape you see, looking where you will.
	var stone: Node3D = STONE_MAN.instantiate()
	stone.name = "StoneLittleMan"
	add_child(stone)
	var sa := deg_to_rad(stone_man_at.y)
	var sdir := Vector3(cos(sa), 0.0, sin(sa))
	stone.position = sand.ground_point(Vector2(sdir.x, sdir.z) * stone_man_at.x) - Vector3(0, 0.18, 0)
	var to_watcher: Vector3 = hub.get_node("Landmarks").watcher_position() - stone.position
	to_watcher.y = 0.0
	stone.basis = Basis.looking_at(-to_watcher.normalized(), Vector3.UP)   # front (+Z) toward the Watcher
	Palette.add_collision(stone)

	# Colossal palms, each planted in its own rock mesa.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for k in colossi.size():
		var c := colossi[k]
		var at := _polar(c.x, c.y)
		var mesa: Node3D = PALM_MESA.instantiate()
		mesa.name = "Mesa%d" % k
		add_child(mesa)
		mesa.position = at + Vector3(0, -MESA_SINK, 0)
		# Its carved door and stair face the crater.
		mesa.basis = Basis.looking_at(at.normalized(), Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		var palm: Node3D = COLOSSAL_PALM.instantiate()
		palm.name = "ColossalPalm%d" % k
		add_child(palm)
		# Planted in the mesa's socket (its top centre, 4 m deep).
		palm.position = mesa.position + MESA_SOCKET
		palm.rotation.y = rng.randf() * TAU
		palm.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)

	# Palm islets: crowning the three rock islands, and scattered in the shallows.
	for island in ["IslandWest", "IslandEast", "IslandNorth"]:
		var isl := hub.get_node("Scenery/" + island) as Node3D
		var top := isl.position + Vector3(0, isl.scale.y * 0.5 * 2.0 - 4.0, 0)
		_islet(top, 7.0 * isl.scale.y / 40.5, rng)
	for s in shallows:
		_islet(_polar(s.x, s.y) + Vector3(0, -1.5, 0), rng.randf_range(4.0, 6.5), rng)

	for n in get_children():
		if n.name.begins_with("ColossalPalm") or n.name.begins_with("PalmIslet"):
			_palm_entries.append_array(Palette.prepare(n))
	for n in get_children():
		if not (n.name.begins_with("ColossalPalm") or n.name.begins_with("PalmIslet") or n == stone):
			_entries.append_array(Palette.prepare(n))
	_refresh()


func _islet(at: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var p: Node3D = PALM_ISLET.instantiate()
	p.name = "PalmIslet"
	add_child(p)
	p.position = at
	p.scale = Vector3.ONE * s
	p.rotation.y = rng.randf() * TAU


func _polar(dist: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * dist, 0.0, sin(a) * dist)
