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
## The beacon tower stands in the sea at the end of the crossing (world metres).
const TOWER_CENTER := Vector3(0, 0, -1122.5)
const TOWER_STEP_Y := 2.2  # top of the footing's outer step
const RAMP_START_Z := -1092.0
## The Watcher's bust (world metres): about 3 km tall, far beyond the beacon, inside the
## mountain cone that hides him until the beacon's light climbs it.
const HEAD_CENTER := Vector3(0, 0, -4200)
const HEAD_SCALE := 220.0
const CONE_RADIUS := 2600.0
const CONE_HEIGHT := 3900.0
## How tall the dissolving edge is as the light climbs (world metres).
const CLIMB_BAND := 160.0
## Where the climbing light ends, just above the summit.
const CLIMB_TOP := 4100.0

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
var _tower: Node3D
## True while the brazier's reveal plays.
var revealing := false


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
	_add_room_audio()

	var camp := Look.make_fire(1.0, true)
	campfire_spot.add_child(camp)
	_add_fire_loop(campfire_spot, -2.0)
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
	var pit := Look.make_fire_pit(false)
	pit.scale = Vector3.ONE * 1.6
	beacon_spot.add_child(pit)
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
	_ink_the_little_man()
	if Game.has_signal(&"room_changed"):
		# Sound resets its footstep surface when the room changes, just after this.
		Game.room_changed.connect(func(_r): _set_surface_resolver(), CONNECT_ONE_SHOT)
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


## In this region the fire is the only colour: the little man is drawn near-black.
func _ink_the_little_man() -> void:
	var ink := Look.mat(Color(0.05, 0.05, 0.055))
	var slot := Game.player.carry_slot
	for m: MeshInstance3D in Game.player.visual.find_children("*", "MeshInstance3D", true, false):
		if m != slot and not slot.is_ancestor_of(m):
			m.material_override = ink


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
	Look.make_boat(layout, Vector3(-3.4, -0.18, -0.9), 0.5)
	for t in [Vector4(-12, 0, 9, 0.3), Vector4(16, 0, 6, 2.0), Vector4(-20, 0, 24, 1.1)]:
		Look.make_bare_tree(lb_material, layout, Vector3(t.x, t.y, t.z), t.w, 1.6)
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
		Look.make_bare_tree(lb_material, layout, c + Vector3(-isl.z * 0.45, 0, -isl.z * 0.3), 0.8 + i, 1.3)
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
	# The far end: the beacon tower in the sea, a boat step up onto its footing.
	_tower = Look.build_beacon(layout, TOWER_CENTER)
	Look.boat_step(layout, Vector3(0, 0, RAMP_START_Z), Vector3(0, TOWER_STEP_Y, TOWER_CENTER.z + 23.5), 3.4)
	Look.foam_ring(layout, TOWER_CENTER, 31.0, 9)
	# The landing at the foot of the tower, where the brazier waits and the exit opens.
	var landing := BoxShape3D.new()
	landing.size = Vector3(18.0, 1.0, 8.0)
	var lc := Vector3(0, TOWER_STEP_Y - 0.5, -1101.0)
	Look.solid(layout, "Landing", landing, Transform3D(Basis.IDENTITY, lc))
	Look.lb(lb_material, Look.box(landing.size), Look.STONE, lc, layout)
	Look.lb(lb_material, Look.box(Vector3(18.4, 0.3, 0.3)), Look.INK, lc + Vector3(0, 0.4, 4.05), layout)
	Look.make_doorway(mountain_exit)


func _build_crossing() -> void:
	for leg in LEGS:
		for run in leg:
			for p in _sample(run[1]):
				if p.y < RAMP_START_Z - 0.5:
					continue  # the boat step takes over here
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


## The mountain: one clean cone of dark rock, streaked pale down its upper third, that
## everyone has always taken for a mountain. As the beacon's light climbs it the cone
## dissolves, uncovering the stone head and shoulders of the Watcher, seen from behind.
func _build_head() -> void:
	var root: Node3D = Look.BustScene.instantiate()
	root.name = "WatcherHead"
	root.position = HEAD_CENTER
	root.rotation.y = PI  # his back to the lake: he looks away, out of the world
	root.scale = Vector3.ONE * HEAD_SCALE
	layout.add_child(root)
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var tint := Color(0.46, 0.46, 0.45)
			if src is StandardMaterial3D and (src as StandardMaterial3D).albedo_color.v < 0.95:
				# Greys only: any red would turn to ember under the lake's 1-bit look.
				var v := (src as StandardMaterial3D).albedo_color.get_luminance()
				tint = Color(v, v, v)
			m.set_surface_override_material(i, head_material.get_material(tint, 0.0, 1.0, 0.0))
	# The cone that just encloses him, centred on his crown.
	var cone_root := Node3D.new()
	cone_root.name = "Mountain"
	cone_root.position = HEAD_CENTER
	layout.add_child(cone_root)
	var rock := Look.lb(head_material, Look.cone(CONE_RADIUS, CONE_HEIGHT, 48), Color(0.13, 0.13, 0.14),
		Vector3(0, CONE_HEIGHT * 0.5, 0), cone_root, 0.0, 1.0, 1.0)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Long pale streaks down the upper third, evenly spaced so the cone stays perfectly
	# symmetrical. Alternate streaks run longer, like snow caught in gullies.
	var streaks := 24
	for i in streaks:
		var a := TAU * i / streaks
		var top := CONE_HEIGHT * 0.97
		var bottom := CONE_HEIGHT * (0.56 if i % 2 == 0 else 0.7)
		var p1 := _on_cone(a, top)
		var p2 := _on_cone(a, bottom)
		var length := p1.distance_to(p2)
		var width := lerpf(90.0, 240.0, (CONE_HEIGHT - bottom) / CONE_HEIGHT)
		var s := Look.lb(head_material, Look.box(Vector3(width, 6.0, length)), Look.BONE,
			(p1 + p2) * 0.5, cone_root, 0.0, 1.0, 1.0)
		var dir := (p1 - p2).normalized()
		var out := Vector3(cos(a), 0, sin(a))
		s.basis = Basis.looking_at(dir, out)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The snowcap, so the summit reads as a mountain from the shore.
	var cap_h := CONE_HEIGHT * 0.06
	Look.lb(head_material, Look.cone(CONE_RADIUS * 0.06 + 6.0, cap_h, 48), Look.BONE,
		Vector3(0, CONE_HEIGHT - cap_h * 0.5 + 2.0, 0), cone_root, 0.0, 1.0, 1.0)
	head_material.set_all(&"climb_band", CLIMB_BAND)


## A point just outside the cone's surface at angle `a` and height `y` (cone-local metres).
func _on_cone(a: float, y: float) -> Vector3:
	var r := CONE_RADIUS * (1.0 - y / CONE_HEIGHT) + 2.5
	return Vector3(cos(a) * r, y, sin(a) * r)


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
	var fire := Look.make_fire(1.8 if f.great else 1.15, false)
	fire.position.y = pit.get_meta(&"fire_height", 0.0) * pit.scale.y
	f.spot.add_child(fire)
	f.fire = fire
	_add_fire_loop(f.spot, 0.0 if f.great else -3.0)
	if not instant:
		_sound(&"play_at", [&"fire_ignite", f.spot.global_position])
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
		_head_climb = CLIMB_TOP
		Look.light_beacon(_tower, true)
		return
	beacon_lit.emit()
	_sound(&"play", [&"ink_ember_take"])
	get_tree().create_timer(1.6).timeout.connect(func(): _sound(&"play", [&"mend"]))
	# Mending the lake: Room.complete() hands him the ember (gives_ink) and the region's
	# television closes its eyes. The brand now rides in his carry slot, so the one in
	# his hand goes out of this room's hands and into the story's.
	complete()
	torch_carried = false
	torch.visible = false
	Look.puff(self, beacon_spot.global_position + Vector3.UP * 2.5, 90, 3.0)
	f.fire.scale = Vector3.ONE * 0.1
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(f.fire, "scale", Vector3.ONE * 1.8, 1.2)
	_fire_climbs_the_tower()
	Game.player.controls_enabled = false
	revealing = true
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_method(func(r): f.reach = r, 0.0, beacon_reach, 9.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var c := create_tween()
	c.tween_interval(4.0)
	c.tween_callback(func(): _sound(&"giant", [&"giant_groan", HEAD_CENTER + Vector3(0, 1500, 0), 3000.0]))
	c.tween_property(self, "_head_climb", CLIMB_TOP, 11.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(Game.camera):
		# Stand back over the sea, low, and look up at the mountain as the light climbs it.
		var b := beacon_spot.global_position
		var look := HEAD_CENTER + Vector3(0, 1500, 0)
		await Game.camera.play_shot(b + Vector3(160, 140, 1000), look, 14.0, 4.0)
	if c.is_running():
		await c.finished
	revealing = false
	if is_instance_valid(Game.player):
		Game.player.controls_enabled = true


## The flame runs up the tower's stair to the bowl 118 m up, then the bowl catches.
func _fire_climbs_the_tower() -> void:
	var steps := 24
	for i in steps:
		var t := float(i) / (steps - 1)
		var a := t * TAU * 3.5 + PI * 0.5
		var r := lerpf(14.0, 6.0, t)
		var p := _tower.global_position + Vector3(cos(a) * r, lerpf(TOWER_STEP_Y + 1.0, 116.0, t), sin(a) * r)
		get_tree().create_timer(0.6 + t * 3.2).timeout.connect(func(): Look.puff(self, p, 14, 2.0))
	get_tree().create_timer(4.0).timeout.connect(func():
		Look.puff(self, _tower.global_position + Vector3(0, 118, 0), 120, 6.0)
		Look.light_beacon(_tower, false))


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
	_sound(&"play", [&"rewind"])
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
	_sound(&"play", [&"wake"])
	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, 0.9)
	pl.controls_enabled = true
	_drowning = false


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Sound --------------------------------------------------------------------------------
# The sound system lives in its own branch until it merges, so every call is soft: with no
# Sound autoload (or no library), the room is simply silent.

func _sound_node() -> Node:
	return get_node_or_null(^"/root/Sound")


func _sound(method: StringName, args: Array) -> void:
	var snd := _sound_node()
	if snd and snd.has_method(method):
		snd.callv(method, args)


func _add_room_audio() -> void:
	if not ResourceLoader.exists("res://audio/room_audio.gd"):
		return
	var ra: Node = load("res://audio/room_audio.gd").new()
	ra.name = "RoomAudio"
	ra.set(&"bed", &"bed_lake")
	ra.set(&"surface", &"stone")
	ra.set(&"lateness", 1.5)
	add_child(ra)


## Wet steps at the very edge of the near shore and in the shallows; stone everywhere else.
func _set_surface_resolver() -> void:
	var snd := _sound_node()
	if snd and &"surface_resolver" in snd:
		snd.set(&"surface_resolver", func(pos: Vector3) -> StringName:
			return &"water" if pos.y < -0.05 or (pos.z > -0.5 and pos.z < 1.6) else &"stone")


func _add_fire_loop(at: Node3D, volume_db: float) -> void:
	var snd := _sound_node()
	if not snd or not snd.has_method(&"get_loop"):
		return
	var stream: AudioStream = snd.call(&"get_loop", &"fire_loop")
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "FireLoop"
	p.stream = stream
	p.bus = &"Near"
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.position.y = 0.6
	at.add_child(p)
	p.play()
