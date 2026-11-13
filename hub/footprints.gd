extends MultiMeshInstance3D
## Footprints the little man leaves in the sand. They fade over `lifetime` seconds.
## At hub scale he is a few pixels tall, so his trail is how you keep track of him
## and how you see how far you have come.

## The drawn print in six stages, fresh to nearly gone (art/tex/footprint_stages.png).
const STAGES := preload("res://hub/art/tex/footprint_stages.png")
const PRINT_SHADER := preload("res://hub/footprint.gdshader")

@export var max_prints := 400
@export var stride := 0.6
@export var lifetime := 14.0
@export var print_color := Color(0.12, 0.04, 0.04, 0.75)

var _player: Player
var _sand: Node
var _last := Vector3.INF
var _left := false
var _next := 0
var _born: PackedFloat32Array = []


func _ready() -> void:
	_sand = get_parent().get_node("SandVortex")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.2, 0.46)
	var mat := ShaderMaterial.new()
	mat.shader = PRINT_SHADER
	mat.set_shader_parameter("stages", STAGES)
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = max_prints
	mm.visible_instance_count = max_prints
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_born.resize(max_prints)
	_born.fill(-1000.0)
	for i in max_prints:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))


func track(p: Player) -> void:
	_player = p
	_last = Vector3.INF


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if is_instance_valid(_player) and _player.is_on_floor() and _player.controls_enabled:
		var pos := _player.global_position
		if _last == Vector3.INF:
			_last = pos
		elif pos.distance_to(_last) >= stride:
			_stamp(pos, (pos - _last).normalized(), now)
			_last = pos
	for i in max_prints:
		var age := now - _born[i]
		if age < lifetime + 0.5:
			var fade := clampf(age / lifetime, 0.0, 1.0)
			multimesh.set_instance_color(i, print_color if fade < 1.0 else Color(0, 0, 0, 0))
			multimesh.set_instance_custom_data(i, Color(fade, 0, 0, 0))


func _stamp(pos: Vector3, dir: Vector3, now: float) -> void:
	var local := to_local(pos)
	var n: Vector3 = _sand.normal_at(Vector2(local.x, local.z))
	var fwd := (dir - n * dir.dot(n)).normalized()
	if fwd.length() < 0.5:
		return
	var right := fwd.cross(n).normalized()
	_left = not _left
	var at := pos + right * (0.13 if _left else -0.13) + n * 0.03
	var basis := Basis(right, n, -fwd)
	multimesh.set_instance_transform(_next, global_transform.affine_inverse() * Transform3D(basis, at))
	_born[_next] = now
	_next = (_next + 1) % max_prints
