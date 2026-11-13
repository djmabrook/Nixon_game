extends MultiMeshInstance3D
## A line of his footprints pressed into the sand. On the title shore after the ending,
## they lead off the edge of the frame.

@export var stride := 0.72
@export var gait_width := 0.2
@export var print_size := Vector2(0.17, 0.3)


## Lay `count` prints from `start` walking along `dir`. `ground` maps a point to the sand.
## `fade_from` (0..1) starts fading the earliest prints, as if the tide has been at them.
func lay(start: Vector3, dir: Vector3, count: int, ground: Callable, fade_from := 0.0) -> void:
	dir.y = 0.0
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var qm := QuadMesh.new()
	qm.size = print_size
	qm.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://story/props/footprints.gdshader")
	qm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = qm
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var yaw := atan2(-dir.x, -dir.z)
	for i in count:
		var lr := -1.0 if i % 2 == 0 else 1.0
		var p := start + dir * (stride * i + rng.randf_range(-0.04, 0.04)) + side * lr * (gait_width * 0.5 + rng.randf_range(-0.02, 0.02))
		var g: Vector3 = ground.call(p)
		var b := Basis(Vector3.UP, yaw + lr * 0.08 + rng.randf_range(-0.06, 0.06))
		mm.set_instance_transform(i, Transform3D(b, g + Vector3.UP * 0.02))
		var age := float(i) / maxf(count - 1, 1)
		var a := 1.0 if age >= fade_from else lerpf(0.25, 1.0, age / maxf(fade_from, 0.001))
		mm.set_instance_color(i, Color(1, 1, 1, a))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-4000, -400, -4000), Vector3(8000, 800, 8000))
