class_name SurfFX
extends Node3D
## The juice around the rider: sand spray off the edge when he carves or slides, a burst of
## sand and light where he lands or wipes out, streaks of speed past the camera, and the
## world's one ink colour drifting through the spectrum as his flow builds.

var surfer: Surfer
## Sand colour of this region (rooms may change it).
var sand_color := Color(0.85, 0.62, 0.48)
## Flow above which the dithered world's ink starts cycling colour.
var ink_cycle_from := 0.25

var spray: GPUParticles3D
var burst: GPUParticles3D
var sparks: GPUParticles3D
var speed_lines: GPUParticles3D
var _dither: Node
var _ink_base := Color(0, 0, 0, 0)
var _ink_hue := 0.0
var _ink_on := false


func _ready() -> void:
	top_level = true
	spray = _particles(220, 0.9, _spray_material(), _quad(0.09, sand_color))
	burst = _particles(140, 1.2, _burst_material(), _quad(0.12, sand_color))
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.emitting = false
	sparks = _particles(60, 1.4, _sparks_material(), _quad(0.07, Color(1, 1, 1), true))
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.emitting = false
	if surfer:
		surfer.landed.connect(_on_landed)
		surfer.wiped_out.connect(_on_wiped_out)
		surfer.trick_landed.connect(_on_trick)
		surfer.boosted.connect(func(_a: float) -> void: _sparkle(surfer.pos + Vector3.UP))
	_dither = get_tree().get_first_node_in_group(&"dither_look")
	if _dither and _dither.has_method(&"current_ink"):
		_ink_base = _dither.current_ink(get_tree())


func attach_speed_lines(cam: Camera3D) -> void:
	speed_lines = GPUParticles3D.new()
	speed_lines.name = "SpeedLines"
	speed_lines.amount = 90
	speed_lines.lifetime = 0.45
	speed_lines.local_coords = true
	speed_lines.process_material = _speed_material()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1, 0.95, 0.9, 0.35)
	m.vertex_color_use_as_albedo = true
	q.material = m
	speed_lines.draw_pass_1 = q
	speed_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	speed_lines.visibility_aabb = AABB(Vector3(-20, -20, -60), Vector3(40, 40, 80))
	speed_lines.amount_ratio = 0.0
	speed_lines.position = Vector3(0, 0, -38)
	cam.add_child(speed_lines)


func _process(delta: float) -> void:
	if not is_instance_valid(surfer):
		return
	var sp := surfer.vel.length()
	var riding := surfer.state == Surfer.State.RIDE
	# Spray off the tail and edge: more when sliding or carving hard at speed.
	var amount := 0.0
	if riding and surfer.board.visible:
		amount = clampf(surfer.slide * 1.2 + absf(surfer.carve) * sp / 40.0 * 0.6 + (sp - 20.0) / 60.0 * 0.3, 0.0, 1.0)
		var b := surfer.board.global_transform
		spray.global_position = b * Vector3(0, 0.05, 0.4)
		var out := -surfer.vel.normalized() + Vector3.UP * 0.6 + b.basis.x * signf(-surfer.carve) * 0.6
		(spray.process_material as ParticleProcessMaterial).direction = out.normalized()
		(spray.process_material as ParticleProcessMaterial).initial_velocity_max = 3.0 + sp * 0.3
	spray.amount_ratio = amount
	spray.emitting = amount > 0.02
	if speed_lines:
		speed_lines.amount_ratio = clampf((sp - 22.0) / 35.0, 0.0, 1.0)
		speed_lines.emitting = speed_lines.amount_ratio > 0.01
	_cycle_ink(delta)


func _cycle_ink(delta: float) -> void:
	if _dither == null or not _dither.has_method(&"set_ink_override"):
		return
	var f := surfer.flow
	if f > ink_cycle_from:
		_ink_hue = fposmod(_ink_hue + delta * (0.02 + 0.2 * f), 1.0)
		var k := smoothstep(ink_cycle_from, ink_cycle_from + 0.3, f)
		var base := _ink_base if _ink_base.a > 0.0 else Color.from_hsv(_ink_hue, 0.9, 1.0)
		var c := base.lerp(Color.from_hsv(_ink_hue, 0.9, 1.0), k)
		c.a = 1.0
		_dither.set_ink_override(c)
		_ink_on = true
	elif _ink_on:
		_dither.set_ink_override(Color(0, 0, 0, 0))
		_ink_on = false


func _exit_tree() -> void:
	if _ink_on and is_instance_valid(_dither):
		_dither.set_ink_override(Color(0, 0, 0, 0))


func _on_landed(quality: float, impact: float) -> void:
	burst.global_position = surfer.pos + Vector3.UP * 0.1
	burst.amount_ratio = clampf(impact / 20.0, 0.25, 1.0)
	burst.restart()
	if quality > 0.93:
		_sparkle(surfer.pos + Vector3.UP * 0.3)


func _on_wiped_out(_speed: float) -> void:
	burst.global_position = surfer.pos + Vector3.UP * 0.2
	burst.amount_ratio = 1.0
	burst.restart()


func _on_trick(_h: int, _f: int, _air: float) -> void:
	_sparkle(surfer.pos + Vector3.UP * 0.8)


func _sparkle(at: Vector3) -> void:
	sparks.global_position = at
	(sparks.draw_pass_1.surface_get_material(0) as StandardMaterial3D).albedo_color = Color.from_hsv(randf(), 0.8, 1.0)
	sparks.restart()


func _particles(n: int, life: float, mat: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.process_material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 30, 60))
	p.emitting = false
	add_child(p)
	return p


func _quad(size: float, c: Color, glow := false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 4.0
	q.material = m
	return q


func _spray_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 1)
	m.spread = 28.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, -17, 0)
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.5
	m.scale_max = 1.6
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.25
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	m.color_ramp = gt
	return m


func _burst_material() -> ParticleProcessMaterial:
	var m := _spray_material()
	m.direction = Vector3.UP
	m.spread = 75.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 10.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 0.6
	m.emission_ring_inner_radius = 0.2
	m.emission_ring_height = 0.1
	return m


func _sparks_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 8.0
	m.gravity = Vector3(0, -3, 0)
	m.damping_min = 2.0
	m.damping_max = 4.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.hue_variation_min = -0.5
	m.hue_variation_max = 0.5
	return m


func _speed_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	# A hollow tube ahead of the camera, so streaks pass the edges of the frame, never the rider.
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3(0, 0, 1)
	m.emission_ring_radius = 12.0
	m.emission_ring_inner_radius = 5.5
	m.emission_ring_height = 6.0
	m.direction = Vector3(0, 0, 1)
	m.spread = 2.0
	m.initial_velocity_min = 70.0
	m.initial_velocity_max = 95.0
	m.gravity = Vector3.ZERO
	m.particle_flag_align_y = true
	return m
