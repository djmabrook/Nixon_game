extends RefCounted
## Builds the lakeside's placeholder world from primitives. Palette: greys and black;
## fire is the only color. Anything made with lb() exists only in firelight (see
## lightbound.gdshader). Every make_*/build_* can later be swapped for a Meshy GLB
## without touching the rule logic in lakeside.gd.
##
## Scale: the little man is 1.2 m tall. The lake is ~115 m across, the pines reach 26 m,
## the drowned head is 24 m wide, the watchers stand 40 m out of the water, and the
## mountain is 190 m high.

const FireScript := preload("res://rooms/lakeside/fire.gd")
const WaterShader := preload("res://rooms/lakeside/water.gdshader")
const LightboundShader := preload("res://rooms/lakeside/lightbound.gdshader")
const HouseScene := preload("res://rooms/lakeside/art/lake_house.glb")
const BoatScene := preload("res://rooms/lakeside/art/rowing_boat.glb")
const BareTreeScene := preload("res://rooms/lakeside/art/bare_tree.glb")
const BeaconScene := preload("res://rooms/lakeside/art/lake_beacon.glb")
const BeaconLitScene := preload("res://rooms/lakeside/art/lake_beacon_lit.glb")
const BrandScene := preload("res://props/carry/ember_brand.glb")
const CaughtScene := preload("res://rooms/lakeside/art/stone_littleman_c.glb")
const BustScene := preload("res://rooms/lakeside/art/watcher_bust_v2.glb")

const INK := Color(0.03, 0.03, 0.035)
const STONE := Color(0.62, 0.62, 0.6)
const BONE := Color(0.86, 0.86, 0.84)
const ASH := Color(0.35, 0.35, 0.34)
const SHORE := Color(0.42, 0.42, 0.41)
const ROCK := Color(0.16, 0.16, 0.17)
const FIRE_DEEP := Color(0.55, 0.02, 0.02)
const FIRE_RED := Color(1.0, 0.12, 0.05)
const FIRE_CORE := Color(1.0, 0.55, 0.25)
const FIRE_LIGHT := Color(1.0, 0.32, 0.18)


# --- Helpers ----------------------------------------------------------------------------

static func mat(c: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func glow(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c if energy <= 1.0 else Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if energy <= 1.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m


static func mesh(m: Mesh, material: Material, pos := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	if parent:
		parent.add_child(mi)
	return mi


## The lightbound materials of one room: one ShaderMaterial per look, all fed the same fires.
class Lightbound extends RefCounted:
	var shader: Shader
	var mats := {}

	func _init(fogless: bool) -> void:
		if fogless:
			shader = Shader.new()
			shader.code = LightboundShader.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode fog_disabled;")
		else:
			shader = LightboundShader

	func get_material(tint: Color, sink: float, climb: float, invert: float) -> ShaderMaterial:
		var key := [tint, sink, climb, invert]
		if not mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter(&"tint", tint)
			m.set_shader_parameter(&"sink", sink)
			m.set_shader_parameter(&"climb", climb)
			m.set_shader_parameter(&"invert", invert)
			mats[key] = m
		return mats[key]

	func set_all(param: StringName, value: Variant) -> void:
		for m: ShaderMaterial in mats.values():
			m.set_shader_parameter(param, value)


## A mesh that exists only in firelight. `sink` > 0 reveals it whole and raises it out
## of the lake (stepping stones); 0 dissolves it fragment by fragment (giants).
## `climb` makes it follow the light climbing the mountain instead; `invert` flips that.
static func lb(set: Lightbound, m: Mesh, tint: Color, pos: Vector3, parent: Node3D, sink := 0.0, climb := 0.0, invert := 0.0) -> MeshInstance3D:
	return mesh(m, set.get_material(tint, sink, climb, invert), pos, parent)


## Every mesh under `root` drawn with one lightbound look, so a model exists only in firelight.
static func make_lightbound(root: Node, set: Lightbound, tint: Color, sink := 0.0) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = set.get_material(tint, sink, 0.0, 0.0)


## Emissive surfaces of a model ignore fog, so its fire reads from kilometres away.
static func unfog_glow(root: Node) -> void:
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			var mt := m.mesh.surface_get_material(i) as BaseMaterial3D
			if mt and mt.emission_enabled:
				var d := mt.duplicate() as BaseMaterial3D
				d.disable_fog = true
				m.set_surface_override_material(i, d)


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cone(radius: float, height: float, sides := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func cyl(radius: float, height: float, sides := 12, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func sphere(radius: float, segments := 12, squash := 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 * squash
	s.radial_segments = segments
	s.rings = maxi(segments / 2, 3)
	return s


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 4
	return c


static func solid(parent: Node3D, node_name: String, shape: Shape3D, xform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = xform
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


static func box_body(parent: Node3D, node_name: String, size: Vector3, xform: Transform3D, color: Color) -> StaticBody3D:
	var bs := BoxShape3D.new()
	bs.size = size
	var body := solid(parent, node_name, bs, xform)
	mesh(box(size), mat(color), Vector3.ZERO, body)
	return body


# --- Sky, light, water ------------------------------------------------------------------

static func dress_night(room: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	# Black fog: the sea has no far shore, things simply stop.
	env.fog_enabled = true
	env.fog_light_color = Color(0, 0, 0)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.name = "Night"
	we.environment = env
	room.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(1, 1, 1)
	moon.light_energy = 0.16
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 300.0
	moon.rotation_degrees = Vector3(-50, 20, 0)
	room.add_child(moon)


static func make_lake(parent: Node3D) -> MeshInstance3D:
	var water := PlaneMesh.new()
	water.size = Vector2(12000, 12000)
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	var lake := mesh(water, wm, Vector3(0, -0.32, -2500), parent)
	lake.name = "Lake"
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lake


## A dashed white line where land meets water, so the shore reads against the black lake.
static func foam_line(parent: Node3D, from: Vector3, to: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := glow(Color(0.75, 0.75, 0.72), 1.0)
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var side := dir.cross(Vector3.UP)
	var s := 0.0
	while s < length:
		var w := minf(rng.randf_range(0.4, 2.2), length - s)
		var seg := mesh(box(Vector3(0.07, 0.02, w)), m, from + dir * (s + w * 0.5) + side * rng.randf_range(-0.12, 0.12), parent)
		seg.position.y = -0.29
		seg.look_at(seg.global_position + dir if seg.is_inside_tree() else seg.position + dir, Vector3.UP)
		seg.rotation.y = atan2(-dir.x, -dir.z)
		seg.rotation.x = 0.0
		s += w + rng.randf_range(0.2, 0.8)


static func foam_ring(parent: Node3D, center: Vector3, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := glow(Color(0.75, 0.75, 0.72), 1.0)
	var a := 0.0
	while a < TAU:
		var span := rng.randf_range(0.08, 0.25)
		var mid := a + span * 0.5
		var r := radius + rng.randf_range(-0.1, 0.15)
		var seg := mesh(box(Vector3(0.07, 0.02, r * span)), m, center + Vector3(cos(mid), 0, sin(mid)) * r, parent)
		seg.position.y = -0.29
		seg.rotation.y = -mid
		a += span + rng.randf_range(0.03, 0.12)


# --- Land ------------------------------------------------------------------------------

## The cottage: the only normal-sized thing in the region. Its door faces local +Z.
static func build_house(parent: Node3D, at: Vector3) -> Node3D:
	var house := StaticBody3D.new()
	house.name = "House"
	house.position = at
	parent.add_child(house)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.6, 6.0, 5.2)
	shape.shape = bs
	shape.position.y = 3.0
	house.add_child(shape)
	house.add_child(HouseScene.instantiate())
	return house


static func make_boat(parent: Node3D, at: Vector3, yaw: float) -> void:
	var boat := BoatScene.instantiate() as Node3D
	boat.name = "RowingBoat"
	boat.position = at
	boat.rotation.y = yaw
	parent.add_child(boat)


## A bare tree, wider than it is tall, existing only in firelight.
static func make_bare_tree(lbm: Lightbound, parent: Node3D, at: Vector3, yaw: float, size: float) -> void:
	var tree := BareTreeScene.instantiate() as Node3D
	tree.name = "BareTree"
	tree.position = at
	tree.rotation.y = yaw
	tree.scale = Vector3.ONE * size
	parent.add_child(tree)
	make_lightbound(tree, lbm, Color(0.12, 0.12, 0.13))


## The beacon: a 122 m iron lattice tower standing in the sea on a stepped stone footing
## (top of the outer step at 2.2 m). Cold until lit; swap_beacon_lit() lights the bowl.
static func build_beacon(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "BeaconTower"
	root.position = at
	parent.add_child(root)
	var cold := BeaconScene.instantiate() as Node3D
	cold.name = "Cold"
	root.add_child(cold)
	var lit := BeaconLitScene.instantiate() as Node3D
	lit.name = "Lit"
	lit.visible = false
	root.add_child(lit)
	unfog_glow(lit)
	# Collision from the model itself: the footing's steps, the legs, the stair.
	for m: MeshInstance3D in cold.find_children("*", "MeshInstance3D", true, false):
		m.create_trimesh_collision()
	var light := OmniLight3D.new()
	light.name = "BowlLight"
	light.light_color = FIRE_LIGHT
	light.light_energy = 0.0
	light.omni_range = 220.0
	light.omni_attenuation = 0.8
	light.position = Vector3(0, 118, 0)
	root.add_child(light)
	return root


static func light_beacon(tower: Node3D, instant: bool) -> void:
	tower.get_node("Cold").visible = false
	tower.get_node("Lit").visible = true
	var light := tower.get_node("BowlLight") as OmniLight3D
	if instant:
		light.light_energy = 6.0
	else:
		tower.create_tween().tween_property(light, "light_energy", 6.0, 2.0)


## A landing ramp from the water up onto the footing's outer step.
static func boat_step(parent: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := to - from
	var length := d.length()
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	var up := basis * Vector3.UP
	box_body(parent, "BoatStep", Vector3(width, 0.6, length + 0.6),
		Transform3D(basis, from + d * 0.5 - up * 0.3), Color(0.5, 0.5, 0.48))


## A pine that dwarfs the house. Lightbound: a dark forest you only see in passing.
static func make_pine(lbm: Lightbound, parent: Node3D, at: Vector3, height: float) -> void:
	var tree := Node3D.new()
	tree.name = "Pine"
	tree.position = at
	parent.add_child(tree)
	lb(lbm, cyl(height * 0.018, height * 0.35, 6), INK, Vector3(0, height * 0.175, 0), tree)
	for i in 4:
		var r := (1.0 - i * 0.2) * height * 0.2
		var h := height * 0.34
		lb(lbm, cone(r, h, 7), Color(0.1, 0.1, 0.11), Vector3(0, height * 0.28 + i * h * 0.48 + h * 0.5, 0), tree)


static func shore_rocks(parent: Node3D, center: Vector3, half: Vector2, count: int, seed_value: int, keep_clear_x := 3.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var x := rng.randf_range(-half.x, half.x)
		if absf(x) < keep_clear_x:
			continue
		var r := rng.randf_range(0.25, 1.1)
		var m := mesh(sphere(r, 6, 0.65), mat(STONE if rng.randf() < 0.5 else ASH),
			center + Vector3(x, 0.05, rng.randf_range(-half.y, half.y)), parent)
		m.rotation.y = rng.randf() * TAU


static func reeds(parent: Node3D, center: Vector3, spread: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in 9:
		var h := rng.randf_range(0.6, 1.6)
		var reed := mesh(box(Vector3(0.05, h, 0.05)), mat(INK),
			center + Vector3(rng.randf_range(-spread, spread), h * 0.5 - 0.3, rng.randf_range(-spread * 0.6, spread * 0.6)), parent)
		reed.rotation.z = rng.randf_range(-0.25, 0.25)


# --- The colossal --------------------------------------------------------------------------

## A drowned hand reaching out of the lake. The path threads between its fingers.
static func make_hand(lbm: Lightbound, parent: Node3D, at: Vector3) -> Node3D:
	var hand := Node3D.new()
	hand.name = "DrownedHand"
	hand.position = at
	parent.add_child(hand)
	var skin := Color(0.78, 0.78, 0.76)
	# Four fingers on the left, curling over the path; a thumb on the right.
	var fingers := [
		[Vector3(-6.0, 0, 4.5), 13.0, 1.5], [Vector3(-7.2, 0, 0.8), 16.0, 1.6],
		[Vector3(-6.8, 0, -3.0), 15.0, 1.55], [Vector3(-5.4, 0, -6.4), 11.0, 1.35],
	]
	for f in fingers:
		_finger(lbm, hand, f[0], f[1], f[2], -1.0, skin)
	_finger(lbm, hand, Vector3(6.0, 0, 2.0), 10.0, 1.8, 1.0, skin)
	# The palm, just under the surface.
	var palm := lb(lbm, sphere(8.0, 14, 0.25), Color(0.5, 0.5, 0.49), Vector3(-2.0, -2.6, 0.0), hand)
	palm.scale = Vector3(1.0, 1.0, 1.25)
	return hand


static func _finger(lbm: Lightbound, hand: Node3D, base: Vector3, length: float, r: float, side: float, skin: Color) -> void:
	# Two segments: a near-vertical rise, then a knuckle that bends over toward the path.
	var root := Node3D.new()
	root.position = base
	root.rotation.z = side * 0.18
	hand.add_child(root)
	var l1 := length * 0.6
	lb(lbm, capsule(r, l1 + r * 2.0), skin, Vector3(0, l1 * 0.5, 0), root)
	var knuckle := Node3D.new()
	knuckle.position = Vector3(0, l1, 0)
	knuckle.rotation.z = side * 0.95
	root.add_child(knuckle)
	var l2 := length * 0.45
	lb(lbm, capsule(r * 0.88, l2 + r * 2.0), skin, Vector3(0, l2 * 0.5, 0), knuckle)
	lb(lbm, sphere(r * 1.05, 10), skin, Vector3.ZERO, knuckle)
	# A dark nail at the tip.
	var nail := lb(lbm, sphere(r * 0.6, 8, 0.3), INK, Vector3(0, l2 + r * 0.6, -r * 0.45), knuckle)
	nail.rotation.x = 0.4


## A face the size of a hill, sleeping in the water beside the path.
static func make_head(lbm: Lightbound, parent: Node3D, at: Vector3) -> void:
	var head := Node3D.new()
	head.name = "DrownedHead"
	head.position = at
	head.rotation.y = deg_to_rad(-70)  # faces the path
	parent.add_child(head)
	var skin := Color(0.72, 0.72, 0.7)
	lb(lbm, sphere(12.0, 20), skin, Vector3.ZERO, head)
	# Brow, nose, closed eyes, mouth, on the face's -Z side.
	var brow := lb(lbm, box(Vector3(14.0, 1.4, 3.0)), skin, Vector3(0, 4.2, -10.6), head)
	brow.rotation.x = 0.25
	var nose := PrismMesh.new()
	nose.size = Vector3(3.6, 6.0, 3.0)
	lb(lbm, nose, skin, Vector3(0, 0.6, -12.2), head)
	for x in [-4.4, 4.4]:
		var lid := lb(lbm, sphere(2.4, 12, 0.45), Color(0.5, 0.5, 0.49), Vector3(x, 2.6, -10.7), head)
		lid.scale = Vector3(1.0, 1.0, 0.6)
		var lash := lb(lbm, box(Vector3(4.2, 0.22, 0.5)), INK, Vector3(x, 2.15, -11.65), head)
		lash.rotation.z = 0.08 * signf(x)
	lb(lbm, box(Vector3(5.0, 0.35, 1.0)), INK, Vector3(0, -3.6, -11.4), head)


## A lone figure, built like the little man and forty metres tall, watching from the lake.
static func make_watcher(lbm: Lightbound, parent: Node3D, at: Vector3, height: float, look_at_pos: Vector3) -> void:
	var w := Node3D.new()
	w.name = "Watcher"
	w.position = at
	parent.add_child(w)
	var flat := Vector3(look_at_pos.x, at.y, look_at_pos.z)
	if flat.distance_to(at) > 0.1:
		w.rotation.y = atan2(-(flat.x - at.x), -(flat.z - at.z))
	var r := height * 0.25
	lb(lbm, capsule(r, height), BONE, Vector3(0, height * 0.5 - height * 0.12, 0), w)
	lb(lbm, sphere(r * 0.5, 10), BONE, Vector3(0, height * 0.66, -r * 0.92), w)  # the nose


## The ruined lighthouse on the island, with a lamp room that wakes when its fire is lit.
static func make_lighthouse(lbm: Lightbound, parent: Node3D, at: Vector3) -> Node3D:
	var lh := Node3D.new()
	lh.name = "Lighthouse"
	lh.position = at
	parent.add_child(lh)
	lb(lbm, cyl(2.4, 24.0, 10, 1.7), BONE, Vector3(0, 12.0, 0), lh)
	for i in 4:
		lb(lbm, cyl(2.36 - i * 0.17 + 0.05, 1.6, 10), INK, Vector3(0, 3.0 + i * 5.5, 0), lh)
	lb(lbm, cyl(2.4, 0.5, 10), INK, Vector3(0, 24.2, 0), lh)
	lb(lbm, cyl(1.4, 2.4, 8), Color(0.2, 0.2, 0.2), Vector3(0, 25.6, 0), lh)
	lb(lbm, cone(1.8, 1.8, 8), INK, Vector3(0, 27.7, 0), lh)
	# A door at its foot.
	lb(lbm, box(Vector3(1.0, 1.9, 0.2)), INK, Vector3(0, 0.95, 2.42), lh)
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 25.6, 0)
	lh.add_child(lamp)
	return lh


## Light the lighthouse: a slow white beam that sweeps the lake. It is moonlight, not fire,
## so it touches nothing into being, it only shows how much darkness there is.
static func wake_lighthouse(lh: Node3D) -> Node3D:
	var lamp := lh.get_node("Lamp") as Node3D
	var core := mesh(sphere(0.9, 10), glow(Color(1, 1, 1), 3.0), Vector3.ZERO, lamp)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pivot := Node3D.new()
	pivot.name = "Beam"
	lamp.add_child(pivot)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.6
	beam.bottom_radius = 9.0
	beam.height = 90.0
	beam.radial_segments = 16
	beam.cap_top = false
	beam.cap_bottom = false
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1, 1, 1, 0.07)
	var bmi := mesh(beam, bm, Vector3(0, 0, -45.0), pivot)
	bmi.rotation.x = deg_to_rad(-90 - 6)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spot := SpotLight3D.new()
	spot.light_color = Color(1, 1, 1)
	spot.light_energy = 3.0
	spot.spot_range = 110.0
	spot.spot_angle = 7.0
	spot.rotation.x = deg_to_rad(-12)
	pivot.add_child(spot)
	return pivot


static func make_doorway(exit: Node3D) -> void:
	var frame := Node3D.new()
	frame.name = "Doorway"
	exit.add_child(frame)
	var ink := mat(INK)
	mesh(box(Vector3(0.6, 7.0, 0.8)), ink, Vector3(-2.2, 3.5, 0), frame)
	mesh(box(Vector3(0.6, 7.0, 0.8)), ink, Vector3(2.2, 3.5, 0), frame)
	mesh(box(Vector3(5.0, 0.7, 0.8)), ink, Vector3(0, 7.2, 0), frame)
	mesh(box(Vector3(3.8, 6.8, 0.05)), glow(FIRE_RED, 1.6), Vector3(0, 3.4, 0.3), frame)
	var l := OmniLight3D.new()
	l.light_color = FIRE_LIGHT
	l.light_energy = 2.0
	l.omni_range = 9.0
	l.position = Vector3(0, 3.0, 2.0)
	frame.add_child(l)


# --- Props -------------------------------------------------------------------------------

static func make_stone(lbm: Lightbound, on_path: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Stone"
	body.set_meta(&"on_path", on_path)
	body.collision_layer = 0
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.85
	cs.height = 0.6
	shape.shape = cs
	shape.position.y = -0.3
	body.add_child(shape)
	var top := cyl(0.92, 0.6, 7, 0.82)
	lb(lbm, top, STONE if on_path else ASH, Vector3(0, -0.3, 0), body, 0.8)
	lb(lbm, cyl(0.95, 0.12, 7, 0.93), INK, Vector3(0, -0.36, 0), body, 0.8)
	return body


## A fire: logs, three flickering flame cones, rising embers and a red light.
static func make_fire(size := 1.0, with_ring := false) -> Node3D:
	var fire := Node3D.new()
	fire.name = "Fire"
	fire.scale = Vector3.ONE * size
	if with_ring:
		for i in 7:
			var a := TAU * i / 7.0
			mesh(sphere(0.16, 6, 0.6), mat(STONE), Vector3(cos(a), 0, sin(a)) * 0.55, fire)
	for i in 3:
		var stick := mesh(box(Vector3(0.12, 0.12, 0.85)), mat(INK), Vector3(0, 0.08, 0), fire)
		stick.rotation = Vector3(0.25, TAU * i / 3.0, 0)
	var layers := [[0.34, 0.95, FIRE_DEEP, 2.0], [0.24, 0.8, FIRE_RED, 3.0], [0.12, 0.55, FIRE_CORE, 4.0]]
	for i in layers.size():
		var L: Array = layers[i]
		var f := mesh(cone(L[0], L[1], 5), glow(L[2], L[3]), Vector3(0, 0.12 + L[1] * 0.5, 0))
		f.name = "Flame%d" % i
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.add_child(f)
	fire.add_child(_embers(16, 1.4))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = FIRE_LIGHT
	light.light_energy = 2.4
	light.omni_range = 6.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.position = Vector3(0, 0.7, 0)
	light.set_meta(&"base_energy", light.light_energy)
	fire.add_child(light)
	fire.set_script(FireScript)
	return fire


## A cold fire pit. `great` makes the brazier on the plateau: a stone bowl on a plinth.
static func make_fire_pit(great := false) -> Node3D:
	var pit := Node3D.new()
	pit.name = "FirePit"
	var k := 2.2 if great else 1.0
	if great:
		mesh(cyl(2.6, 1.2, 8, 2.2), mat(Color(0.3, 0.3, 0.3)), Vector3(0, 0.6, 0), pit)
		mesh(cyl(2.9, 0.9, 10, 3.3), mat(STONE), Vector3(0, 1.65, 0), pit)
		mesh(cyl(2.7, 0.1, 10), mat(ASH), Vector3(0, 2.12, 0), pit)
	else:
		for i in 8:
			var a := TAU * i / 8.0
			mesh(sphere(0.2, 6, 0.65), mat(STONE), Vector3(cos(a), 0, sin(a)) * 0.7, pit)
		mesh(cyl(0.55, 0.06, 8, 0.5), mat(ASH), Vector3(0, 0.03, 0), pit)
	var y := 2.15 if great else 0.1
	for i in 3:
		var stick := mesh(box(Vector3(0.12, 0.12, 0.8) * k), mat(INK), Vector3(0, y, 0), pit)
		stick.rotation = Vector3(0.2, TAU * i / 3.0 + 0.4, 0)
	pit.set_meta(&"fire_height", y)
	return pit


## The brand the little man carries: a stick with a small living flame on top.
static func make_torch() -> Node3D:
	var torch := Node3D.new()
	torch.name = "Torch"
	var brand := BrandScene.instantiate() as Node3D
	brand.position = Vector3(0, -0.16, 0)  # held at the grip
	torch.add_child(brand)
	# The model brings its own faceted flame; this adds the light and the embers.
	var flame := make_fire(0.3)
	flame.position = Vector3(0, 0.3, 0)
	for c in flame.get_children():
		if c.name.begins_with("Flame") or c is MeshInstance3D:
			c.visible = false
	torch.add_child(flame)
	var light := flame.get_node("Light") as OmniLight3D
	light.light_energy = 2.0
	light.shadow_enabled = false
	light.set_meta(&"base_energy", 2.0)
	return torch


## A small spinning red diamond: "you can do something here", without words.
static func make_glyph() -> Node3D:
	var root := Node3D.new()
	root.name = "Glyph"
	var s := SphereMesh.new()
	s.radius = 0.14
	s.height = 0.4
	s.radial_segments = 4
	s.rings = 2
	var mi := mesh(s, glow(FIRE_RED, 2.5), Vector3.ZERO, root)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.visible = false
	return root


static func _embers(amount: int, life: float, one_shot := false, speed := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Embers"
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25 * speed
	p.direction = Vector3.UP
	p.spread = 25.0 if not one_shot else 70.0
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_min = 0.4 * speed
	p.initial_velocity_max = (1.2 if not one_shot else 3.0) * speed
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.position = Vector3(0, 0.5, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06) * sqrt(speed)
	var m := glow(FIRE_CORE, 4.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.7, 0.4, 1))
	g.set_color(1, Color(0.6, 0.0, 0.0, 0))
	p.color_ramp = g
	return p


## A burst of embers that cleans itself up.
static func puff(parent: Node, at: Vector3, amount := 18, speed := 1.0) -> void:
	var p := _embers(amount, 0.9 * sqrt(speed), true, speed)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	parent.get_tree().create_timer(2.5).timeout.connect(p.queue_free)


## A white ring spreading on the water.
static func ripple(parent: Node, at: Vector3, grow := 1.4) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.82
	t.outer_radius = 0.9
	t.rings = 24
	t.ring_segments = 3
	var m := glow(Color(0.9, 0.9, 0.9), 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.7
	var mi := mesh(t, m)
	mi.scale = Vector3(0.8, 0.1, 0.8)
	parent.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "scale", Vector3(grow, 0.1, grow), 1.1)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(mi.queue_free)
