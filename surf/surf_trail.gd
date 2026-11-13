class_name SurfTrail
extends MeshInstance3D
## A ribbon of light painted behind the board, cycling through colour, lying on the sand
## (it rides the swells as they pass under it) and drawing arcs through the air on jumps.
## The better the flow, the longer and wider it gets.

var surfer: Surfer
## Seconds a point lives, at no flow and at full flow.
var life_min := 1.4
var life_max := 4.5
var width := 0.32
var spacing := 0.35

var _pts: Array = []   # [pos, side, born, hue, on_ground]
var _mesh := ImmediateMesh.new()
var _clock := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	extra_cull_margin = 10000.0


func _process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(surfer) or not is_instance_valid(surfer.board):
		return
	var life := lerpf(life_min, life_max, surfer.flow)
	var riding := surfer.state == Surfer.State.RIDE or surfer.state == Surfer.State.AIR
	if riding and surfer.board.visible:
		var b := surfer.board.global_transform
		var tail := b * Vector3(0, 0.03, 0.45)
		var side := b.basis.x.normalized()
		if _pts.is_empty() or (_pts[-1][0] as Vector3).distance_to(tail) > spacing:
			var hue := fposmod(_clock * (0.05 + 0.35 * surfer.flow), 1.0)
			_pts.append([tail, side, _clock, hue, surfer.state == Surfer.State.RIDE])
	while not _pts.is_empty() and _clock - float(_pts[0][2]) > life:
		_pts.pop_front()
	_mesh.clear_surfaces()
	if _pts.size() < 2:
		return
	var t := surfer.terrain
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var w := width * (0.7 + 0.8 * surfer.flow)
	for i in _pts.size():
		var p: Array = _pts[i]
		var at: Vector3 = p[0]
		if p[4] and t:
			at.y = t.height(Vector2(at.x, at.z)) + 0.04
		var age := (_clock - float(p[2])) / life
		var fade := pow(1.0 - clampf(age, 0.0, 1.0), 1.5)
		# The newest stretch fades in so the ribbon starts under the board, not in front of it.
		fade *= clampf(float(_pts.size() - 1 - i) / 3.0, 0.0, 1.0)
		var col := Color.from_hsv(float(p[3]), 0.8, 1.0, fade * (0.35 + 0.4 * surfer.flow))
		var half := w * 0.5 * (1.0 - 0.5 * age)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(at - (p[1] as Vector3) * half)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(at + (p[1] as Vector3) * half)
	_mesh.surface_end()


func clear() -> void:
	_pts.clear()
