extends Room
## THE LAKESIDE. A black sea under a mountain at night. The campfire is the only color,
## and its light is the only thing that makes the world real.
##
## Rule broken: things exist only where firelight touches them. Stepping stones, a pier,
## a drowned hand, a ship's hull: all of it is there and solid only inside a fire's
## reach, and the black water takes you everywhere else.
##
## The crossing (~1.1 km, a few minutes) runs in four legs between islets. Carry a brand
## from the campfire, relight the cold fire on each islet (it becomes the place you wake
## if the sea takes you), and at the far shore climb to the great brazier. Its light
## climbs the mountain and shows what the mountain really is: the back of the Watcher's
## head, turned away from this place. That mends the lake: it gives the ember (the brand
## that never goes out) for his carry slot, and the watching television on the near
## shore closes its eyes. The door in the rock leads home. The house door on the near
## shore also leads back to the hub.
##
## Placeholder geometry: everything is built in lakeside_look.gd from primitives.

const Look := preload("res://rooms/lakeside/lakeside_look.gd")

const STONE_STEP := 1.25
## Every layout coordinate below is in "plan" units, stretched by S on the ground plane.
## At S = 2.2 the crossing is about 1.1 km: a few minutes on foot, a minute running.
const S := 2.2

## The crossing, leg by leg (Layout space, x/z). A leg is a list of runs; each run is a
## polyline sampled every STONE_STEP. Run kinds: "stones" or "pier" (a woken boardwalk).
const LEGS := [
	[["stones", [Vector2(0, -0.2), Vector2(4, -20), Vector2(-6, -45), Vector2(-3, -70), Vector2(5, -95), Vector2(1, -119.5)]]],
	[["stones", [Vector2(0, -136.5), Vector2(6, -160), Vector2(-2, -186)]],
	 ["pier", [Vector2(-2, -187.5), Vector2(-2, -232)]],
	 ["stones", [Vector2(-2, -233.5), Vector2(4, -255), Vector2(1, -268.5)]]],
	[["stones", [Vector2(0, -291.5), Vector2(-6, -315), Vector2(3, -340), Vector2(-4, -365), Vector2(0, -397.5)]]],
	[["stones", [Vector2(0, -412.5), Vector2(5, -440), Vector2(-3, -470), Vector2(0, -497.5)]]],
]
## The false branch: off the first leg, out to the moon lying in the water.
const MOON_BRANCH := [Vector2(-3.5, -70), Vector2(-20, -74), Vector2(-37.5, -79)]
const MOON_CENTER := Vector3(-74, 0, -82)  # plan units
const MOON_RADIUS := 80.0  # metres

## Islets: centre (x, z), radius. Each has a cold fire that becomes a checkpoint.
const ISLETS := [Vector3(0, -128, 19.6), Vector3(0, -280, 26.0), Vector3(0, -405, 17.4)]  # plan x/z, radius in m
const FAR_SHORE_Z := -497.0
const PLATEAU_Y := 14.0
## The Watcher's head (world metres), scaled up by HEAD_SCALE from its plan.
const HEAD_CENTER := Vector3(0, 0, -1750)
const HEAD_SCALE := 2.2

@export_group("Light")
## How far each light makes the world real, in metres.
@export var campfire_reach := 9.0
@export var islet_reach := 14.0
@export var torch_reach := 7.0
@export var beacon_reach := 1400.0
@export var interact_range := 2.0
@export var drown_depth := -1.2

## Fired when the great brazier is lit (the room's goal).
signal beacon_lit

@onready var layout: Node3D = $Layout
@onready var campfire_spot: Marker3D = $Layout/Campfire
@onready var beacon_spot: Marker3D = $Layout/Beacon
@onready var mountain_exit: RoomExit = $Layout/ExitMountain

var lb_material: Look.Lightbound
var head_material: Look.Lightbound  # same rule, but never fogged: the mountain must read from 1.7 km
var water_material: ShaderMaterial
var torch: Node3D
var torch_carried := false
var beacon_is_lit := false
## Every fire: {spot: Node3D, reach: float, lit: bool, spawn: StringName, great: bool, fire: Node3D}
var fires: Array[Dictionary] = []
var checkpoint: StringName = &"shore"

var _stones: Array[StaticBody3D] = []  # every walkable woken thing, in path order first
var _path_stones: Array[StaticBody3D] = []
var _last_stone: Node = null
var _glyph: Node3D
var _head_climb := 0.0
var _drowning := false
var _time := 0.0
var _fade: ColorRect
var _landmark: Marker3D


func _ready() -> void:
	lb_material = Look.Lightbound.new(false)
	head_material = Look.Lightbound.new(true)
	_landmark = $Layout/Landmark
	focus_target = _landmark
	Look.dress_night(self)
	var lake := Look.make_lake(layout)
	water_material = lake.material_override

	_build_land()
	_build_crossing()
	_build_colossi()

	var camp := Look.make_fire(1.0, true)
	campfire_spot.add_child(camp)
	fires.append({spot = campfire_spot, reach = campfire_reach, lit = true, spawn = &"shore", great = false, fire = camp})
	_set_light_range(camp, campfire_reach)
	for i in ISLETS.size():
		var isl: Vector3 = ISLETS[i]
		var spot := Marker3D.new()
		spot.name = "IsletFire%d" % i
		spot.position = _plan(isl.x, isl.y) + Vector3(-2.0, 0, 1.5)
		layout.add_child(spot)
		spot.add_child(Look.make_fire_pit(false))
		var spawn := RoomSpawn.new()
		spawn.name = "islet_%d" % i
		spawn.position = spot.position + Vector3(1.6, 0, 1.6)
		layout.add_child(spawn)
		fires.append({spot = spot, reach = islet_reach, lit = false, spawn = spawn.name, great = false, fire = null})
	beacon_spot.add_child(Look.make_fire_pit(true))
	fires.append({spot = beacon_spot, reach = 0.0, lit = false, spawn = &"plateau", great = true, fire = null})

	torch = Look.make_torch()
	add_child(torch)
	torch.visible = false
	_set_light_range(torch.get_node("Fire"), torch_reach)
	_glyph = Look.make_glyph()
	add_child(_glyph)
	_make_fade()

	mountain_exit.enabled = false
	mountain_exit.visible = false


func _on_room_entered(_spawn: StringName) -> void:
	if Game.is_completed(room_id):
		_light_fire(fires.back(), true)
	_update_world()


func _physics_process(delta: float) -> void:
	_time += delta
	_update_world()
	if not is_instance_valid(Game.player) or Game.current_room != self:
		return
	_carry_torch(delta)
	_footsteps()
	_update_glyph()
	_spin_beams(delta)
	if not _drowning and Game.player.global_position.y < drown_depth:
		_drown()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and not _drowning and Game.player.controls_enabled:
		if interact():
			get_viewport().set_input_as_handled()


## Does whatever makes sense where the little man stands. Returns true if something happened.
func interact() -> bool:
	var pos := Game.player.global_position
	if torch_carried:
		for f in fires:
			if not f.lit and _flat_dist(pos, f.spot.global_position) < _reach_to_use(f):
				_light_fire(f, false)
				return true
		_drop_torch()
		return true
	if torch.visible and _flat_dist(pos, torch.global_position) < interact_range:
		_pick_torch(torch.global_position)
		return true
	for f in fires:
		if f.lit and _flat_dist(pos, f.spot.global_position) < _reach_to_use(f) + 0.4:
			_pick_torch(f.spot.global_position + Vector3.UP * 0.6)
			return true
	return false


## True if a world point is real right now (inside any fire's reach).
func is_real_at(world_pos: Vector3) -> bool:
	return _light_amount(world_pos) > 0.5


# --- Building ------------------------------------------------------------------------------

func _build_land() -> void:
	Look.build_house(layout, Vector3(8, 0, 20)).rotation.y = PI * 0.5  # door faces east, beside the lake
	Look.foam_line(layout, Vector3(-32, 0, 0.05), Vector3(32, 0, 0.05), 3)
	Look.shore_rocks(layout, Vector3(0, 0, 1.2), Vector2(30, 0.8), 40, 11)
	for x in [-14.0, 11.0, 22.0, -24.0]:
		Look.reeds(layout, Vector3(x, 0, 0.2), 1.6, int(x * 7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 22:
		var p := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(6, 31))
		if absf(p.x) < 5.0 or p.distance_to(Vector3(8, 0, 20)) < 6.0:
			continue
		Look.make_pine(lb_material, layout, p, rng.randf_range(14.0, 26.0))

	for i in ISLETS.size():
		var isl: Vector3 = ISLETS[i]
		var c := _plan(isl.x, isl.y)
		var shape := CylinderShape3D.new()
		shape.radius = isl.z
		shape.height = 1.0
		var body := Look.solid(layout, "Islet%d" % i, shape, Transform3D(Basis.IDENTITY, c + Vector3(0, -0.5, 0)))
		Look.mesh(Look.cyl(isl.z, 1.0, 20, isl.z * 0.97), Look.mat(Look.SHORE), Vector3.ZERO, body)
		Look.foam_ring(layout, c, isl.z + 0.1, 40 + i)
		Look.shore_rocks(layout, c, Vector2(isl.z * 0.7, isl.z * 0.7), 10, 70 + i, 1.5)
		Look.reeds(layout, c + Vector3(isl.z * 0.75, 0, 0), 1.0, 90 + i)
	Look.make_lighthouse(lb_material, layout, _plan(0, -280) + Vector3(9, 0, -8)).set_meta(&"islet", 1)
	# Mid crossing, on the lighthouse islet: the camera drifts back until he is a red
	# speck on a black plane under the mountain.
	var vista := VistaZone.new()
	vista.name = "VistaUnderTheMountain"
	vista.look_target = _landmark
	vista.pull_back = 220.0
	vista.hold = 4.5
	vista.blend = 4.0
	var vs := CollisionShape3D.new()
	var vcyl := CylinderShape3D.new()
	vcyl.radius = (ISLETS[1] as Vector3).z - 3.0
	vcyl.height = 4.0
	vs.shape = vcyl
	vista.add_child(vs)
	layout.add_child(vista)
	vista.position = _plan(0, -280) + Vector3(0, 1.5, 0)

	# The far shore: a narrow landing, the ascent, the plateau, the mountain.
	var fz := FAR_SHORE_Z * S
	Look.box_body(layout, "FarShore", Vector3(140, 1, 16), Transform3D(Basis.IDENTITY, Vector3(0, -0.5, fz - 8.0)), Look.SHORE)
	Look.foam_line(layout, Vector3(-70, 0, fz + 0.05), Vector3(70, 0, fz + 0.05), 9)
	Look.build_ascent(lb_material, layout, fz, PLATEAU_Y, 28.0)
	Look.make_doorway(mountain_exit)


func _build_crossing() -> void:
	for leg in LEGS:
		for run in leg:
			for p in _sample(run[1]):
				_add_walkable(p, run[0] == "pier", true)
	for p in _sample(MOON_BRANCH).slice(1):
		_add_walkable(p, false, false)
	# Pier posts, woken in passing.
	var pier: Array = LEGS[1][1][1]
	var z: float = pier[0].y
	while z > pier[1].y:
		for side in [-1.0, 1.0]:
			Look.lb(lb_material, Look.box(Vector3(0.35, 4.0, 0.35)), Look.INK, _plan(pier[0].x, z) + Vector3(side * 1.9, 0.6, 0), layout)
		z -= 4.0 / S
	# The moon in the water, the size of a town. Solid, pale, and it leads nowhere.
	var moon_shape := CylinderShape3D.new()
	moon_shape.radius = MOON_RADIUS
	moon_shape.height = 0.4
	var moon_c := _plan(MOON_CENTER.x, MOON_CENTER.z)
	var moon := Look.solid(layout, "Moon", moon_shape, Transform3D(Basis.IDENTITY, moon_c + Vector3(0, -0.2, 0)))
	var mm := Look.glow(Color(0.62, 0.62, 0.6), 1.0)
	Look.mesh(Look.cyl(MOON_RADIUS, 0.4, 64), mm, Vector3.ZERO, moon)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 16:  # maria
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * MOON_RADIUS * 0.75
		Look.mesh(Look.cyl(rng.randf_range(4.0, 18.0), 0.02, 24), Look.glow(Color(0.42, 0.42, 0.41), 1.0),
			Vector3(cos(a) * r, 0.21, sin(a) * r), moon)
	Look.foam_ring(layout, moon_c, MOON_RADIUS + 0.2, 33)


func _build_colossi() -> void:
	# Leg 1: a drowned hand whose fingers arch over the stones.
	Look.make_hand(lb_material, layout, _plan(-6, -45) + Vector3(1, 0, 0)).scale = Vector3.ONE * 1.15
	# Leg 3: the hull of a ship, keel up, alongside the path.
	var ship := Node3D.new()
	ship.name = "Ship"
	ship.position = _plan(0, -330) + Vector3(22, -4, 0)
	ship.scale = Vector3.ONE * 1.5
	ship.rotation = Vector3(0, deg_to_rad(8), deg_to_rad(160))
	layout.add_child(ship)
	var hull := Look.lb(lb_material, Look.sphere(10.0, 16), Color(0.32, 0.32, 0.31), Vector3.ZERO, ship)
	hull.scale = Vector3(1.0, 0.75, 5.0)
	Look.lb(lb_material, Look.box(Vector3(0.8, 3.0, 96)), Look.INK, Vector3(0, -7.6, 0), ship)
	for i in 9:
		Look.lb(lb_material, Look.box(Vector3(20.4, 0.25, 0.4)), Look.INK, Vector3(0, -1.0, -36 + i * 9.0), ship)
	var mast := Look.lb(lb_material, Look.cyl(0.6, 30, 8), Color(0.25, 0.25, 0.24), Vector3(-9, 12, 10), layout)
	mast.position = ship.position + Vector3(-19, 3, 21)
	mast.scale = Vector3.ONE * 1.5
	mast.rotation = Vector3(0.5, 0, 0.9)
	# Leg 3: a drowned stair climbing out of the water to nowhere.
	var stair := Node3D.new()
	stair.name = "Stair"
	stair.position = _plan(-4, -378) + Vector3(-30, -2, 0)
	stair.scale = Vector3.ONE * 1.6
	stair.rotation.y = deg_to_rad(-60)
	layout.add_child(stair)
	for i in 12:
		Look.lb(lb_material, Look.box(Vector3(7.0, 2.4, 3.0)), Look.STONE, Vector3(0, i * 2.4, -i * 3.0), stair)
	# Watchers far out in the sea, the little man's own shape, forty metres tall.
	for w in [Vector2(-90, -210), Vector2(85, -330), Vector2(-70, -450)]:
		var at := _plan(w.x, w.y)
		Look.make_watcher(lb_material, layout, at, 70.0, at + Vector3(-at.x, 0, 90))
	_build_head()


## The mountain. Crags of rock and snow that dissolve as the beacon's light climbs them,
## uncovering the smooth stone head and shoulders of the Watcher, seen from behind.
func _build_head() -> void:
	var root := Node3D.new()
	root.name = "WatcherHead"
	root.position = HEAD_CENTER
	root.scale = Vector3.ONE * HEAD_SCALE
	layout.add_child(root)
	var stone := Color(0.46, 0.46, 0.45)
	var parts := [
		[Look.capsule(70.0, 480.0), Vector3(0, 10, 30), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8)],  # shoulders
		[Look.cyl(46.0, 90.0, 18), Vector3(0, 70, 0), Vector3.ZERO, Vector3.ONE],  # neck
		[Look.sphere(88.0, 28), Vector3(0, 170, 0), Vector3.ZERO, Vector3(1, 1.08, 1)],  # skull
		[Look.sphere(22.0, 14), Vector3(-87, 165, -12), Vector3.ZERO, Vector3(0.35, 1.2, 0.8)],  # ears
		[Look.sphere(22.0, 14), Vector3(87, 165, -12), Vector3.ZERO, Vector3(0.35, 1.2, 0.8)],
		[Look.sphere(70.0, 24), Vector3(0, 236, 6), Vector3.ZERO, Vector3(1.0, 0.36, 1.0)],  # snow on the dome
		[Look.capsule(30.0, 150.0), Vector3(-150, 72, 30), Vector3(0, 0, PI * 0.5 - 0.12), Vector3(1, 0.5, 1)],  # snow on shoulders
		[Look.capsule(30.0, 150.0), Vector3(150, 72, 30), Vector3(0, 0, PI * 0.5 + 0.12), Vector3(1, 0.5, 1)],
	]
	for i in parts.size():
		var p: Array = parts[i]
		var tint := Look.BONE if i >= 5 else stone
		var m := Look.lb(head_material, p[0], tint, p[1], root, 0.0, 1.0)
		m.rotation = p[2]
		m.scale = p[3]
	# The crags: what everyone has always taken for a mountain.
	var crags := [
		[Vector3(0, 0, 0), 175.0, 290.0], [Vector3(-150, 0, 40), 110.0, 150.0], [Vector3(150, 0, 30), 105.0, 140.0],
		[Vector3(-60, 0, -40), 90.0, 200.0], [Vector3(70, 0, -30), 85.0, 215.0],
	]
	for c in crags:
		Look.lb(head_material, Look.cone(c[1], c[2], 6), Color(0.15, 0.15, 0.16), c[0] + Vector3(0, c[2] * 0.5, 0), root, 0.0, 1.0, 1.0)
		Look.lb(head_material, Look.cone(c[1] * 0.28, c[2] * 0.28, 6), Look.BONE, c[0] + Vector3(0, c[2] * 0.86 + 0.1, 0), root, 0.0, 1.0, 1.0)


func _plan(x: float, z: float) -> Vector3:
	return Vector3(x * S, 0.0, z * S)


## Points along a plan-space polyline, every STONE_STEP metres, in world metres.
func _sample(points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in points.size() - 1:
		var a: Vector2 = points[i] * S
		var b: Vector2 = points[i + 1] * S
		var n := maxi(1, int(ceil(a.distance_to(b) / STONE_STEP)))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(points.back() * S)
	return out


func _add_walkable(p: Vector2, is_pier: bool, on_path: bool) -> void:
	var piece := _make_board() if is_pier else Look.make_stone(lb_material, on_path)
	layout.add_child(piece)
	piece.position = Vector3(p.x, 0.03, p.y)
	if not is_pier:
		piece.rotation.y = fposmod(p.x * 12.9898 + p.y * 78.233, TAU)
	piece.set_meta(&"on_path", on_path)
	piece.set_meta(&"solid", false)
	_stones.append(piece)
	if on_path:
		_path_stones.append(piece)


func _make_board() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Board"
	body.set_meta(&"pier", true)
	body.collision_layer = 0
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.4, 0.4, 1.4)
	cs.shape = bs
	cs.position.y = -0.2
	body.add_child(cs)
	Look.lb(lb_material, Look.box(Vector3(3.4, 0.25, 1.15)), Color(0.5, 0.5, 0.48), Vector3(0, -0.125, 0), body, 0.8)
	Look.lb(lb_material, Look.box(Vector3(3.6, 0.3, 0.2)), Look.INK, Vector3(0, -0.2, 0.62), body, 0.8)
	return body


# --- Reality ------------------------------------------------------------------------------

func _lights() -> Array:
	var out := []
	for f in fires:
		if f.lit:
			out.append([f.spot.global_position, f.reach])
	if torch.visible:
		out.append([torch.global_position, torch_reach])
	return out


func _light_amount(world_pos: Vector3) -> float:
	var best := 0.0
	for l in _lights():
		best = maxf(best, _reach(l[0], l[1], world_pos))
	return best


static func _reach(center: Vector3, reach: float, p: Vector3) -> float:
	if reach <= 0.0:
		return 0.0
	var band := maxf(1.2, reach * 0.12)
	return 1.0 - smoothstep(reach - band, reach, _flat_dist(center, p))


func _update_world() -> void:
	var ls := _lights()
	for s in _stones:
		var a := 0.0
		for l in ls:
			a = maxf(a, _reach(l[0], l[1], s.global_position))
		s.visible = a > 0.0
		var solid := a > 0.5
		if solid != s.get_meta(&"solid"):
			s.set_meta(&"solid", solid)
			s.collision_layer = 1 if solid else 0
	# Feed the four lights that matter most to the shaders: the beacon if it burns,
	# then whatever is nearest the little man.
	var focus := Game.player.global_position if is_instance_valid(Game.player) else Vector3.ZERO
	var big := ls.filter(func(l): return l[1] > 50.0)
	var rest := ls.filter(func(l): return l[1] <= 50.0)
	rest.sort_custom(func(a, b): return a[0].distance_squared_to(focus) < b[0].distance_squared_to(focus))
	var chosen := (big + rest).slice(0, 4)
	for i in 4:
		var v := Vector4.ZERO
		if i < chosen.size():
			var p: Vector3 = chosen[i][0]
			v = Vector4(p.x, p.y, p.z, chosen[i][1])
		lb_material.set_all("fire%d" % i, v)
		head_material.set_all("fire%d" % i, v)
		water_material.set_shader_parameter("fire%d" % i, v)
	head_material.set_all(&"climb_y", _head_climb)


func _set_light_range(fire: Node3D, reach: float) -> void:
	var light := fire.find_child("Light", true, false) as OmniLight3D
	if light:
		light.omni_range = minf(reach * 1.6, 60.0)


func _reach_to_use(f: Dictionary) -> float:
	return interact_range + (2.6 if f.great else 0.0)


# --- The brand ---------------------------------------------------------------------------

func _pick_torch(from: Vector3) -> void:
	torch_carried = true
	torch.visible = true
	Look.puff(self, from)
	torch.global_position = _torch_hold_point()


func _drop_torch() -> void:
	torch_carried = false
	var p := Game.player.global_position
	torch.global_position = Vector3(p.x, p.y + 0.15, p.z) + Game.player.facing * 0.3
	torch.rotation = Vector3(0.0, torch.rotation.y, deg_to_rad(-12.0))
	Look.puff(self, torch.global_position)


func _torch_hold_point() -> Vector3:
	var pl := Game.player
	var side := pl.facing.cross(Vector3.UP).normalized() * -0.32
	var bob := sin(_time * 11.0) * 0.05 if pl.is_walking else 0.0
	return pl.global_position + side + pl.facing * 0.12 + Vector3(0.0, 1.05 + bob, 0.0)


func _carry_torch(delta: float) -> void:
	if not torch_carried:
		return
	var goal := _torch_hold_point()
	var prev := torch.global_position
	if prev.distance_to(goal) > 3.0:  # he was carried somewhere (waking, a cutscene)
		torch.global_position = goal
		return
	torch.global_position = prev.lerp(goal, 1.0 - exp(-18.0 * delta))
	var swing := (goal - prev) * 4.0
	torch.rotation.x = lerp(torch.rotation.x, clampf(swing.z, -0.5, 0.5), 0.2)
	torch.rotation.z = lerp(torch.rotation.z, clampf(-swing.x, -0.5, 0.5), 0.2)


# --- Fires ---------------------------------------------------------------------------------

func _light_fire(f: Dictionary, instant: bool) -> void:
	if f.lit:
		return
	f.lit = true
	var pit: Node3D = f.spot.get_child(0)
	var fire := Look.make_fire(2.6 if f.great else 1.15, false)
	fire.position.y = pit.get_meta(&"fire_height", 0.0)
	f.spot.add_child(fire)
	f.fire = fire
	if f.great:
		_set_light_range(fire, 40.0)
		_finish(instant)
		return
	_set_light_range(fire, f.reach)
	checkpoint = f.spawn
	for lh in layout.get_children():
		if lh.get_meta(&"islet", -1) == fires.find(f) - 1:
			var beam := Look.wake_lighthouse(lh)
			beam.set_meta(&"spin", true)
	if not instant:
		Look.puff(self, f.spot.global_position + Vector3.UP * 0.5, 30)
		fire.scale = Vector3.ONE * 0.05
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(fire, "scale", Vector3.ONE * 1.15, 0.8)


## The great brazier: its light pours across the sea and climbs the mountain.
func _finish(instant: bool) -> void:
	beacon_is_lit = true
	checkpoint = &"shore"
	var f: Dictionary = fires.back()
	mountain_exit.visible = true
	mountain_exit.enabled = true
	if instant:
		f.reach = beacon_reach
		_head_climb = 800.0
		return
	beacon_lit.emit()
	# Mending the lake: Room.complete() hands him the ember (gives_ink) and the region's
	# television closes its eyes. The brand now rides in his carry slot, so the one in
	# his hand goes out of this room's hands and into the story's.
	complete()
	torch_carried = false
	torch.visible = false
	Look.puff(self, beacon_spot.global_position + Vector3.UP * 2.5, 90, 3.0)
	f.fire.scale = Vector3.ONE * 0.1
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(f.fire, "scale", Vector3.ONE * 2.6, 1.2)
	Game.player.controls_enabled = false
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_method(func(r): f.reach = r, 0.0, beacon_reach, 9.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var c := create_tween()
	c.tween_interval(4.0)
	c.tween_property(self, "_head_climb", 800.0, 10.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(Game.camera):
		# Stand back over the sea, low, and look up at the mountain as the light climbs it.
		var b := beacon_spot.global_position
		var look := HEAD_CENTER + Vector3(0, 260, 0)
		await Game.camera.play_shot(b + Vector3(90, 70, 620), look, 13.0, 4.0)
	else:
		await c.finished
	if is_instance_valid(Game.player):
		Game.player.controls_enabled = true


func _spin_beams(delta: float) -> void:
	for b in find_children("Beam", "", true, false):
		(b as Node3D).rotation.y += delta * 0.35


# --- Feel --------------------------------------------------------------------------------

func _footsteps() -> void:
	var pl := Game.player
	var under: Node = null
	if pl.is_on_floor():
		for i in pl.get_slide_collision_count():
			var c := pl.get_slide_collision(i).get_collider()
			if c is StaticBody3D and c.has_meta(&"on_path"):
				under = c
				break
	if under != _last_stone and (under != null or not pl.is_on_floor()):
		_last_stone = under
		if under:
			var s := under as Node3D
			Look.ripple(self, Vector3(s.global_position.x, -0.3, s.global_position.z))


func _update_glyph() -> void:
	var pos := Game.player.global_position
	var target: Variant = null
	if not Game.player.controls_enabled:
		pass
	elif torch_carried:
		for f in fires:
			if not f.lit and _flat_dist(pos, f.spot.global_position) < _reach_to_use(f) + 1.5:
				target = f.spot.global_position + Vector3.UP * (4.0 if f.great else 1.4)
	elif torch.visible and _flat_dist(pos, torch.global_position) < interact_range + 0.8:
		target = torch.global_position + Vector3.UP * 0.9
	else:
		for f in fires:
			if f.lit and _flat_dist(pos, f.spot.global_position) < _reach_to_use(f) + 1.5:
				target = f.spot.global_position + Vector3.UP * (5.5 if f.great else 1.8)
	_glyph.visible = target != null
	if target != null:
		_glyph.global_position = target + Vector3.UP * sin(_time * 4.0) * 0.08
		_glyph.rotation.y = _time * 2.0


func _make_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


## The sea takes him. He wakes at the last fire he lit, without the brand.
func _drown() -> void:
	_drowning = true
	var pl := Game.player
	pl.controls_enabled = false
	if torch_carried:
		torch_carried = false
		var sink := create_tween()
		sink.tween_property(torch, "global_position:y", torch.global_position.y - 1.5, 0.6)
		sink.tween_callback(func(): torch.visible = false)
	Look.ripple(self, Vector3(pl.global_position.x, -0.3, pl.global_position.z), 2.6)
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, 0.6)
	await t.finished
	torch.visible = false
	var spawn := get_spawn(checkpoint)
	pl.global_position = spawn.global_position
	pl.velocity = Vector3.ZERO
	pl.face(_landmark.global_position - pl.global_position)
	if is_instance_valid(Game.camera):
		Game.camera.face_toward(_landmark.global_position)
		Game.camera.snap_to_target()
	await get_tree().create_timer(0.4).timeout
	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, 0.9)
	pl.controls_enabled = true
	_drowning = false


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
