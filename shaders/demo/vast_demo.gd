extends Node3D
## Vast-scale test for DitherLook with a perspective, third-person orbit camera
## (Shadow of the Colossus style): a huge plain, a ring of mountains lost in haze,
## a stone colossus, ruins and the little man.
##
## Keys: 1-5 switch looks, B blink (eyelids), F hold to drain colour (stare), 0 toggles the effect, S toggles stabilize, WASD walk,
## arrows or mouse drag orbit the camera, Q/E zoom.
## Screenshots / motion test:
##   godot --path . res://shaders/demo/vast_demo.tscn -- --shots=/some/dir
##   godot --path . res://shaders/demo/vast_demo.tscn -- --motion=/some/dir

const LOOKS := [
	preload("res://shaders/presets/colossus_haze.tres"),
	preload("res://shaders/presets/colossus_dusk.tres"),
	preload("res://shaders/presets/dawn.tres"),
	preload("res://shaders/presets/paper_margin.tres"),
	preload("res://shaders/presets/lakeside_1bit.tres"),
]

var dither: DitherLook
var cam: Camera3D
var man: Node3D
var yaw := 15.0
var pitch := -8.0
var dist := 7.0
var _noise := FastNoiseLite.new()
var _t := 0.0
var _auto := false


func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 5
	_build_world()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	dither = DitherLook.new()
	dither.follow_rooms = false
	dither.look = LOOKS[0]
	layer.add_child(dither)
	_place_camera()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_take_shots(a.trim_prefix("--shots="))
		elif a.begins_with("--motion="):
			_motion_test(a.trim_prefix("--motion="))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.keycode
		if k >= KEY_1 and k <= KEY_5:
			dither.transition_to(LOOKS[k - KEY_1], 0.8)
		elif k == KEY_0:
			dither.enabled = not dither.enabled
		elif k == KEY_B:
			_blink()
		elif k == KEY_S:
			dither.stabilize = not dither.stabilize
			print("stabilize: ", dither.stabilize)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		yaw -= e.relative.x * 0.25
		pitch = clampf(pitch - e.relative.y * 0.25, -60.0, 50.0)


func _process(delta: float) -> void:
	_t += delta
	dither.drain = move_toward(dither.drain, 1.0 if Input.is_key_pressed(KEY_F) else 0.0, delta * 1.5)
	yaw += (Input.get_axis(&"ui_left", &"ui_right")) * -70.0 * delta
	pitch = clampf(pitch + Input.get_axis(&"ui_down", &"ui_up") * 40.0 * delta, -60.0, 50.0)
	if Input.is_key_pressed(KEY_Q):
		dist = maxf(3.0, dist - 8.0 * delta)
	if Input.is_key_pressed(KEY_E):
		dist = minf(20.0, dist + 8.0 * delta)
	var f := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") if InputMap.has_action(&"move_left") else Vector2.ZERO
	var move := Vector3(f.x, 0, f.y).rotated(Vector3.UP, deg_to_rad(yaw))
	if move.length() > 0.01:
		man.position += move * 4.0 * delta
		man.rotation.y = atan2(move.x, move.z)
	man.position.y = _height(man.position.x, man.position.z)
	_place_camera()


func _blink() -> void:
	var cur := dither.look
	var lid := DitherLookSettings.new()
	lid.palette = PackedColorArray([Color("0b0a0c")])
	dither.eyelids_to(lid, 0.18)
	await get_tree().create_timer(0.3).timeout
	dither.eyelids_open_to(cur, 0.25)


func _place_camera() -> void:
	var target := man.position + Vector3(0, 1.6, 0)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	var pos := target + b.z * dist
	pos.y = maxf(pos.y, _height(pos.x, pos.z) + 0.6)
	cam.global_transform = Transform3D(b, pos)


# ---------------------------------------------------------------- world

func _height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var plain := _noise.get_noise_2d(x, z) * 6.0
	# A ring of mountains far out, so the horizon is ridges in haze.
	var ring := smoothstep(500.0, 1100.0, r) * (180.0 + 160.0 * _noise.get_noise_2d(x * 0.6 + 900.0, z * 0.6))
	return plain + maxf(0.0, ring)


func _build_world() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 140, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("8fa6bd")
	sky_mat.sky_horizon_color = Color("dfe3e2")
	sky_mat.ground_horizon_color = Color("dfe3e2")
	sky_mat.ground_bottom_color = Color("6d6a60")
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("cfd6da")
	env.fog_density = 0.0009
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	add_child(_terrain())

	var stone := _mat(Color("8d8577"), 0.95)
	var moss := _mat(Color("5d6648"), 1.0)
	var dark := _mat(Color("2c2b2a"), 1.0)

	# The colossus: a striding stone giant ~45 m tall, 140 m away.
	var giant := Node3D.new()
	giant.position = Vector3(30, _height(30, -140), -140)
	giant.rotation_degrees.y = 20
	add_child(giant)
	_box(giant, Vector3(-5, 9, 0), Vector3(5, 18, 6), stone, Vector3(0, 0, 8))      # legs
	_box(giant, Vector3(5, 9, 2), Vector3(5, 18, 6), stone, Vector3(0, 0, -10))
	_box(giant, Vector3(0, 25, 0), Vector3(16, 16, 9), stone, Vector3(4, 0, 0))     # torso
	_box(giant, Vector3(0, 31, -1), Vector3(17, 3, 10), moss)                      # fur ridge
	_box(giant, Vector3(-10, 22, 1), Vector3(4, 18, 4), stone, Vector3(0, 0, -12)) # arms
	_box(giant, Vector3(10, 22, -1), Vector3(4, 18, 4), stone, Vector3(15, 0, 10))
	_box(giant, Vector3(0, 37, 0), Vector3(7, 7, 7), stone, Vector3(-6, 0, 0))     # head
	var eye := _mat(Color("bfe7ff"), 0.4)
	eye.emission_enabled = true
	eye.emission = Color("bfe7ff")
	eye.emission_energy_multiplier = 4.0
	_box(giant, Vector3(-1.6, 37.5, -3.6), Vector3(1.0, 1.0, 0.4), eye)
	_box(giant, Vector3(1.6, 37.5, -3.6), Vector3(1.0, 1.0, 0.4), eye)

	# Ruins: a broken colonnade and a far temple on a ridge.
	for i in 9:
		var h := 14.0 if i % 3 else 7.0
		var x := -60.0 + i * 9.0
		var z := -40.0 - i * 2.0
		_box(self, Vector3(x, _height(x, z) + h * 0.5, z), Vector3(2.5, h, 2.5), stone)
	var tz := -620.0
	_box(self, Vector3(-120, _height(-120, tz) + 30, tz), Vector3(60, 60, 40), dark)
	# A long bridge silhouette at mid distance.
	_box(self, Vector3(-200, _height(-200, -260) + 25, -260), Vector3(180, 6, 8), stone)
	for i in 6:
		var bx := -280.0 + i * 32.0
		_box(self, Vector3(bx, _height(bx, -260) + 11, -260), Vector3(6, 24, 6), stone)

	# The little man.
	man = Node3D.new()
	add_child(man)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.7
	body.mesh = cap
	body.position.y = 0.85
	body.material_override = _mat(Color("7a2f22"), 0.9)
	man.add_child(body)


func _terrain() -> MeshInstance3D:
	# Concentric grid: dense near the middle, coarse far out.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 220
	var coords := PackedFloat32Array()
	for i in n + 1:
		var u := float(i) / n * 2.0 - 1.0
		coords.append(signf(u) * pow(absf(u), 2.2) * 1600.0)
	var sand := Color("8f8166")
	var grass := Color("56603f")
	var rock := Color("55514a")
	var snow := Color("e4e6e2")
	for j in n:
		for i in n:
			var quad := [Vector2(coords[i], coords[j]), Vector2(coords[i + 1], coords[j]),
				Vector2(coords[i + 1], coords[j + 1]), Vector2(coords[i], coords[j + 1])]
			for k in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[k]
				var h := _height(p.x, p.y)
				var g := _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.5 + 0.5
				var c := sand.lerp(grass, smoothstep(0.35, 0.7, g))
				c = c.lerp(rock, smoothstep(15.0, 60.0, h))
				c = c.lerp(snow, smoothstep(160.0, 240.0, h))
				st.set_color(c)
				st.add_vertex(Vector3(p.x, h, p.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# ---------------------------------------------------------------- screenshots

func _take_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(12)
	var views := [[15.0, -6.0, 7.0], [-5.0, 14.0, 5.0], [60.0, -22.0, 12.0]]
	for v in views.size():
		yaw = views[v][0]
		pitch = views[v][1]
		dist = views[v][2]
		_place_camera()
		dither.enabled = false
		await _frames(4)
		_save("%s/v%d_0_raw.png" % [dir, v])
		dither.enabled = true
		for i in LOOKS.size():
			if v > 0 and i > 0:
				break
			dither.transition_to(LOOKS[i], 0.0)
			await _frames(3)
			_save("%s/v%d_%d_%s.png" % [dir, v, i + 1, LOOKS[i].resource_name])
	# Story hooks on the first view.
	yaw = 15.0
	pitch = -6.0
	dist = 7.0
	_place_camera()
	dither.transition_to(LOOKS[0], 0.0)
	dither.drain = 0.6
	await _frames(3)
	_save(dir + "/h_drain_60.png")
	dither.drain = 0.0
	dither.eyelids_to(LOOKS[2], 1.0)
	await get_tree().create_timer(0.55).timeout
	_save(dir + "/h_eyelids_half.png")
	get_tree().quit()


## Orbit the camera a little (and separately, walk forward) with stabilize on and off, saving
## before/after frames so swimming can be measured.
func _motion_test(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	dither.transition_to(LOOKS[0], 0.0)
	await _frames(12)
	for stab in [true, false]:
		dither.stabilize = stab
		var tag := "stab" if stab else "raw"
		# Orbit: yaw by 0.37 deg about the man.
		yaw = 15.0
		man.position = Vector3.ZERO
		_place_camera()
		await _frames(4)
		_save("%s/%s_orbit_a.png" % [dir, tag])
		yaw += 0.37
		_place_camera()
		await _frames(4)
		_save("%s/%s_orbit_b.png" % [dir, tag])
		# Walk: one stride forward.
		yaw = 15.0
		_place_camera()
		await _frames(4)
		_save("%s/%s_walk_a.png" % [dir, tag])
		man.position += -cam.global_transform.basis.z.slide(Vector3.UP).normalized() * 0.35
		man.position.y = _height(man.position.x, man.position.z)
		_place_camera()
		await _frames(4)
		_save("%s/%s_walk_b.png" % [dir, tag])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

