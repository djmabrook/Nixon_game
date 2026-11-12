extends Node3D
## Test scene for DitherLook. Builds a small isometric world in code so it has no
## dependencies on the rest of the game.
##
## Keys: 1-6 switch looks (dither dissolve), 0 toggles the effect, Space cycles,
## WASD / arrows walk the little man.
## Run it: open shaders/demo/dither_demo.tscn and press F6.
## Screenshots: godot --path . res://shaders/demo/dither_demo.tscn -- --shots=/some/dir

const LOOKS := [
	preload("res://shaders/presets/lakeside_1bit.tres"),
	preload("res://shaders/presets/sand_spiral_16bit.tres"),
	preload("res://shaders/presets/y2k_red_grid.tres"),
	preload("res://shaders/presets/pink_checker.tres"),
	preload("res://shaders/presets/cloud_sky.tres"),
	preload("res://shaders/presets/purple_face_grid.tres"),
]

var dither: DitherLook
var man: Node3D
var cam: Camera3D
var _look_i := 0
var _t := 0.0


func _ready() -> void:
	_build_world()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	dither = DitherLook.new()
	dither.follow_rooms = false
	dither.look = LOOKS[0]
	layer.add_child(dither)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_take_shots(a.trim_prefix("--shots="))
		elif a.begins_with("--motion="):
			_motion_test(a.trim_prefix("--motion="))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.keycode
		if k >= KEY_1 and k <= KEY_6:
			_switch(k - KEY_1)
		elif k == KEY_0:
			dither.enabled = not dither.enabled
		elif k == KEY_SPACE:
			_switch((_look_i + 1) % LOOKS.size())


func _switch(i: int) -> void:
	_look_i = i
	dither.transition_to(LOOKS[i], 0.8)
	print("look: ", LOOKS[i].resource_name)


func _process(delta: float) -> void:
	_t += delta
	var dir := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	# Rotate input to match the isometric camera.
	var move := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, deg_to_rad(45))
	man.position += move * 3.0 * delta
	if move.length() > 0.01:
		man.rotation.y = atan2(move.x, move.z)
	man.get_child(0).position.y = 0.45 + absf(sin(_t * 9.0)) * 0.06 * minf(1.0, move.length())


# ---------------------------------------------------------------- world

func _build_world() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.0
	cam.rotation_degrees = Vector3(-30, 45, 0)
	cam.position = Vector3(12, 10, 12)
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1a1440")
	sky_mat.sky_horizon_color = Color("e07aa8")
	sky_mat.ground_horizon_color = Color("e07aa8")
	sky_mat.ground_bottom_color = Color("201010")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Checkerboard floor.
	_mesh(_plane(24), _checker_mat(Color("f2f0ea"), Color("101010"), 12), Vector3.ZERO)

	# Checkered spheres.
	var pink := _checker_mat(Color("ea7167"), Color("121006"), 4)
	_mesh(_sphere(1.2), pink, Vector3(-3.5, 1.2, 1.5))
	_mesh(_sphere(0.7), pink, Vector3(-1.2, 0.7, 4.5))

	# Mountain cone.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.0
	cone.height = 5.0
	_mesh(cone, _flat(Color("6a6a70")), Vector3(-5, 2.5, -6))

	# House: box + roof.
	var box := BoxMesh.new()
	box.size = Vector3(3, 1.8, 2.2)
	_mesh(box, _flat(Color("e9e6df")), Vector3(3.5, 0.9, -3))
	var roof := PrismMesh.new()
	roof.size = Vector3(3.4, 1.2, 2.6)
	var r := _mesh(roof, _flat(Color("2a2a2c")), Vector3(3.5, 2.4, -3))
	r.rotation_degrees.y = 90

	# Campfire: emissive + light.
	var fire := PrismMesh.new()
	fire.size = Vector3(0.6, 0.9, 0.6)
	var fm := _flat(Color("ff5a1f"))
	fm.emission_enabled = true
	fm.emission = Color("ff4a10")
	fm.emission_energy_multiplier = 2.5
	_mesh(fire, fm, Vector3(4, 0.45, 2.5))
	var omni := OmniLight3D.new()
	omni.light_color = Color("ff6a2a")
	omni.light_energy = 3.0
	omni.omni_range = 5.0
	omni.position = Vector3(4, 1.0, 2.5)
	add_child(omni)

	# Black disc standing on its edge.
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.15
	var d := _mesh(disc, _flat(Color("050505")), Vector3(0, 2.4, -7))
	d.rotation_degrees = Vector3(90, 45, 0)

	# Hue ramp of spheres: shows how each palette maps colour.
	for i in 8:
		var c := Color.from_hsv(float(i) / 8.0, 0.75, 0.9)
		_mesh(_sphere(0.35), _flat(c), Vector3(6.5, 0.35, -1.0 + i * 0.9))

	# The little man.
	man = Node3D.new()
	man.position = Vector3(1, 0, 1.5)
	add_child(man)
	var body := Node3D.new()
	man.add_child(body)
	var cap := CapsuleMesh.new()
	cap.radius = 0.18
	cap.height = 0.7
	var bm := MeshInstance3D.new()
	bm.mesh = cap
	bm.material_override = _flat(Color("3a1c14"))
	body.add_child(bm)
	var head := MeshInstance3D.new()
	head.mesh = _sphere(0.15)
	head.material_override = _flat(Color("3a1c14"))
	head.position.y = 0.5
	body.add_child(head)


func _mesh(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _plane(s: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(s, s)
	return p


func _sphere(rad: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = rad
	s.height = rad * 2.0
	return s


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _checker_mat(a: Color, b: Color, repeats: float) -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	var m := _flat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(repeats, repeats, 1)
	return m


# ---------------------------------------------------------------- screenshots

func _take_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(10)
	dither.enabled = false
	await _frames(3)
	_save(dir + "/00_raw.png")
	dither.enabled = true
	for i in LOOKS.size():
		dither.transition_to(LOOKS[i], 0.0)
		await _frames(3)
		_save("%s/%02d_%s.png" % [dir, i + 1, LOOKS[i].resource_name])
	# Mid-transition frame.
	dither.transition_to(LOOKS[0], 0.0)
	await _frames(2)
	dither.transition_to(LOOKS[1], 1.0)
	await get_tree().create_timer(0.5).timeout
	_save(dir + "/07_transition.png")
	get_tree().quit()


## Pans the camera by a sub-pixel amount with stabilize on and off and saves before/after
## frames, so crawl can be measured (see the PR for numbers).
func _motion_test(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	dither.transition_to(LOOKS[1], 0.0)
	var start := cam.position
	var upp := cam.size / get_viewport().get_visible_rect().size.y
	for stab in [true, false]:
		dither.stabilize = stab
		var tag := "stab" if stab else "raw"
		cam.position = start + cam.basis.x * 0.3 * upp
		await _frames(4)
		_save("%s/%s_a.png" % [dir, tag])
		cam.position += cam.basis.x * 7.37 * upp + cam.basis.y * 3.61 * upp
		await _frames(4)
		_save("%s/%s_b.png" % [dir, tag])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
