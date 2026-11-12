extends RefCounted
## Builds the lakeside's placeholder geometry and effects from primitives.
## Palette: pure greys and black. Fire is the only color (deep red to ember orange).
## Swap any make_*() for a Meshy GLB later without touching the rule logic.

const FireScript := preload("res://rooms/lakeside/fire.gd")
const WaterShader := preload("res://rooms/lakeside/water.gdshader")

const INK := Color(0.03, 0.03, 0.035)
const STONE := Color(0.62, 0.62, 0.6)
const BONE := Color(0.86, 0.86, 0.84)
const ASH := Color(0.35, 0.35, 0.34)
const FIRE_DEEP := Color(0.55, 0.02, 0.02)
const FIRE_RED := Color(1.0, 0.12, 0.05)
const FIRE_CORE := Color(1.0, 0.55, 0.25)
const FIRE_LIGHT := Color(1.0, 0.32, 0.18)


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


## Every material on a light-bound prop, made unique so each fades on its own.
static func collect_materials(root: Node) -> Array:
	var out := []
	for n in [root] + root.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D and n.material_override is BaseMaterial3D:
			n.material_override = n.material_override.duplicate()
			out.append(n.material_override)
	return out


# --- The world --------------------------------------------------------------------------

static func dress(room: Node3D) -> void:
	var layout: Node3D = room.get_node("Layout")

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
	var we := WorldEnvironment.new()
	we.name = "Night"
	we.environment = env
	room.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(1, 1, 1)
	moon.light_energy = 0.14
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-50, 20, 0)
	room.add_child(moon)

	# The lake: one black mirror under everything.
	var water := PlaneMesh.new()
	water.size = Vector2(80, 80)
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	mesh(water, wm, Vector3(0, -0.32, -4), layout).name = "Lake"

	# The moon lives in the lake, not the sky. The dead-end stones lead to it.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.01
	disc.radial_segments = 24
	var moon_mat := glow(Color(0.95, 0.95, 0.92), 1.0)
	moon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moon_mat.albedo_color = Color(0.8, 0.8, 0.78, 0.55)
	mesh(disc, moon_mat, Vector3(-4.9, -0.3, -2.6), layout).name = "MoonInLake"

	_foam(layout, 2.0, 7.0)
	_foam(layout, -11.3, 6.0)
	_house(layout)
	_mountains(layout)
	_shore_details(layout)
	_doorway(room.get_node("Layout/ExitMountain"))


## A dashed white line where land meets water, so the shore reads against the black lake.
static func _foam(layout: Node3D, z: float, half: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(z * 10.0)
	var m := glow(Color(0.75, 0.75, 0.72), 1.0)
	var x := -half
	while x < half:
		var w := rng.randf_range(0.3, 1.2)
		mesh(box(Vector3(minf(w, half - x), 0.02, 0.06)), m,
			Vector3(x + w * 0.5, -0.29, z + rng.randf_range(-0.12, 0.04) * signf(z)), layout)
		x += w + rng.randf_range(0.15, 0.5)


static func _house(layout: Node3D) -> void:
	var house := StaticBody3D.new()
	house.name = "House"
	house.position = Vector3(3.5, 0, 6.6)
	layout.add_child(house)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 3.0, 3.0)
	shape.shape = bs
	shape.position.y = 1.5
	house.add_child(shape)

	var white := mat(BONE)
	var ink := mat(INK)
	mesh(box(Vector3(3.0, 2.2, 3.0)), white, Vector3(0, 1.1, 0), house)
	var roof := PrismMesh.new()
	roof.size = Vector3(3.7, 1.5, 3.5)
	mesh(roof, ink, Vector3(0, 2.95, 0), house)
	mesh(box(Vector3(0.45, 1.1, 0.45)), ink, Vector3(0.9, 3.3, 0.6), house)  # chimney
	# The door faces the camera: the little man steps out of it into the night.
	mesh(box(Vector3(0.9, 1.55, 0.08)), ink, Vector3(0, 0.78, 1.52), house)
	for x in [-0.95, 0.95]:
		mesh(box(Vector3(0.5, 0.5, 0.06)), ink, Vector3(x, 1.4, 1.52), house)
	mesh(box(Vector3(0.06, 0.5, 0.5)), ink, Vector3(1.52, 1.4, 0.3), house)
	# Clapboard lines, so the white walls read as a drawn house in 1-bit.
	for i in 5:
		mesh(box(Vector3(3.02, 0.03, 3.02)), ink, Vector3(0, 0.25 + i * 0.4, 0), house)
	mesh(box(Vector3(1.4, 0.12, 0.7)), mat(ASH), Vector3(0, 0.06, 1.85), house)  # step


static func _mountains(layout: Node3D) -> void:
	var peaks := [Vector4(0, -29, 9.0, 13.0), Vector4(-10, -26, 6.5, 8.5), Vector4(9, -27, 5.5, 7.0)]
	for p in peaks:
		var root := Node3D.new()
		root.name = "Mountain"
		root.position = Vector3(p.x, 0, p.y)
		layout.add_child(root)
		mesh(cone(p.z, p.w, 5), mat(Color(0.2, 0.2, 0.21)), Vector3(0, p.w * 0.5, 0), root)
		# Snow cap: a smaller white cone on the same slope.
		mesh(cone(p.z * 0.3, p.w * 0.3, 5), mat(BONE), Vector3(0, p.w * 0.85 + 0.02, 0), root)


static func _shore_details(layout: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Rocks along both shorelines.
	for i in 18:
		var far := i >= 10
		var x := rng.randf_range(-6.5, 6.5) if not far else rng.randf_range(-5.5, 5.5)
		var z := (2.1 + rng.randf_range(-0.2, 0.3)) if not far else (-11.4 + rng.randf_range(-0.3, 0.2))
		if absf(x) < 1.6:
			continue  # keep the path landing clear
		var s := SphereMesh.new()
		var r := rng.randf_range(0.18, 0.45)
		s.radius = r
		s.height = r * 1.3
		s.radial_segments = 6
		s.rings = 3
		mesh(s, mat(STONE if rng.randf() < 0.5 else ASH), Vector3(x, 0.02, z), layout)
	# Reeds: thin ink strokes in clumps at the water's edge.
	for c in 6:
		var cx := rng.randf_range(-6.5, 6.5)
		if absf(cx) < 2.0:
			cx += 3.0 * signf(cx + 0.01)
		var cz := 2.0 if c % 2 == 0 else -11.3
		for k in 5:
			var h := rng.randf_range(0.5, 1.1)
			var reed := mesh(box(Vector3(0.04, h, 0.04)), mat(INK),
				Vector3(cx + rng.randf_range(-0.4, 0.4), h * 0.5 - 0.3, cz + rng.randf_range(-0.3, 0.3)), layout)
			reed.rotation.z = rng.randf_range(-0.2, 0.2)


static func _doorway(exit: Node3D) -> void:
	var frame := Node3D.new()
	frame.name = "Doorway"
	exit.add_child(frame)
	var ink := mat(INK)
	mesh(box(Vector3(0.25, 2.4, 0.4)), ink, Vector3(-0.85, 1.2, 0), frame)
	mesh(box(Vector3(0.25, 2.4, 0.4)), ink, Vector3(0.85, 1.2, 0), frame)
	mesh(box(Vector3(1.95, 0.28, 0.4)), ink, Vector3(0, 2.4, 0), frame)
	# A red glow in the doorway: the way home is warm.
	mesh(box(Vector3(1.45, 2.25, 0.05)), glow(FIRE_RED, 1.6), Vector3(0, 1.12, 0.12), frame)
	var l := OmniLight3D.new()
	l.light_color = FIRE_LIGHT
	l.light_energy = 1.2
	l.omni_range = 3.0
	l.position = Vector3(0, 1.2, -0.6)
	frame.add_child(l)


# --- Props ------------------------------------------------------------------------------

static func make_stone(on_path: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Stone"
	body.set_meta(&"on_path", on_path)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.85
	cs.height = 0.6
	shape.shape = cs
	shape.position.y = -0.3
	body.add_child(shape)
	var top := CylinderMesh.new()
	top.top_radius = 0.82
	top.bottom_radius = 0.92
	top.height = 0.6
	top.radial_segments = 7
	top.rings = 1
	mesh(top, mat(STONE if on_path else ASH), Vector3(0, -0.3, 0), body)
	# A dark band at the waterline, so stones read against the black lake.
	var band := CylinderMesh.new()
	band.top_radius = 0.93
	band.bottom_radius = 0.95
	band.height = 0.12
	band.radial_segments = 7
	band.rings = 1
	mesh(band, mat(INK), Vector3(0, -0.36, 0), body)
	return body


static func make_tree(height: float) -> Node3D:
	var tree := Node3D.new()
	tree.name = "Tree"
	mesh(box(Vector3(0.14, height * 0.3, 0.14)), mat(INK), Vector3(0, height * 0.15, 0), tree)
	for i in 3:
		var r := (0.95 - i * 0.22) * height * 0.32
		var h := height * 0.42
		mesh(cone(r, h, 6), mat(Color(0.08, 0.08, 0.09)), Vector3(0, height * 0.32 + i * h * 0.5 + h * 0.5, 0), tree)
	return tree


## A fire: logs, three flickering flame cones, rising embers and a red light.
static func make_fire(size := 1.0, with_ring := false) -> Node3D:
	var fire := Node3D.new()
	fire.name = "Fire"
	fire.scale = Vector3.ONE * size
	if with_ring:
		for i in 7:
			var a := TAU * i / 7.0
			var s := SphereMesh.new()
			s.radius = 0.16
			s.height = 0.2
			s.radial_segments = 6
			s.rings = 3
			mesh(s, mat(STONE), Vector3(cos(a), 0, sin(a)) * 0.55, fire)
	for i in 3:
		var log := mesh(box(Vector3(0.12, 0.12, 0.85)), mat(INK), Vector3(0, 0.08, 0), fire)
		log.rotation = Vector3(0.25, TAU * i / 3.0, 0)
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


## The cold fire pit under the mountain: a ring of stones around dead ash.
static func make_fire_pit() -> Node3D:
	var pit := Node3D.new()
	pit.name = "FirePit"
	for i in 8:
		var a := TAU * i / 8.0
		var s := SphereMesh.new()
		s.radius = 0.2
		s.height = 0.26
		s.radial_segments = 6
		s.rings = 3
		mesh(s, mat(STONE), Vector3(cos(a), 0, sin(a)) * 0.7, pit)
	var ash := CylinderMesh.new()
	ash.top_radius = 0.5
	ash.bottom_radius = 0.55
	ash.height = 0.06
	mesh(ash, mat(ASH), Vector3(0, 0.03, 0), pit)
	for i in 2:
		var log := mesh(box(Vector3(0.12, 0.12, 0.8)), mat(INK), Vector3(0, 0.1, 0), pit)
		log.rotation = Vector3(0.2, PI * 0.5 * i + 0.4, 0)
	return pit


## The brand the little man carries: a stick with a small living flame on top.
static func make_torch() -> Node3D:
	var torch := Node3D.new()
	torch.name = "Torch"
	mesh(box(Vector3(0.07, 0.7, 0.07)), mat(INK), Vector3(0, 0.0, 0), torch)
	var flame := make_fire(0.42)
	flame.position = Vector3(0, 0.32, 0)
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
	s.radius = 0.12
	s.height = 0.34
	s.radial_segments = 4
	s.rings = 2
	var mi := mesh(s, glow(FIRE_RED, 2.5), Vector3.ZERO, root)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.visible = false
	return root


static func _embers(amount: int, life: float, one_shot := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Embers"
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 25.0 if not one_shot else 70.0
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2 if not one_shot else 3.0
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.position = Vector3(0, 0.5, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
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
static func puff(parent: Node, at: Vector3, amount := 18) -> void:
	var p := _embers(amount, 0.9, true)
	parent.add_child(p)
	p.global_position = at
	p.position.y = at.y
	p.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(p.queue_free)


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
	mi.scale = Vector3(1, 0.1, 1) * 0.8
	mi.scale.y = 0.1
	parent.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "scale", Vector3(grow, 0.1, grow), 1.1)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(mi.queue_free)
