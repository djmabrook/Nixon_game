extends MeshInstance3D
## The wash at the tideline: a thin sheet of water laid over the sand that laps in and
## out, can throw one big wave, and can drain away (the "drained shore").
## Built on the sand by raycasts, so it fits any beach.

## Metres along the shore each way, and from `inland_reach` inland to `sea_reach` out.
@export var half_length := 170.0
@export var inland_reach := 22.0
@export var sea_reach := 80.0
@export var cells := Vector2i(96, 40)

## Resting waterline (metres seaward of the wake spot) and how far each lap travels.
var rest := 2.5
var lap := 1.6
var lap_period := 7.5
## 0 = lapping at rest. Drain pulls the whole sea back by `drained_by` metres.
var drain := 0.0
var drained_by := 34.0
## Extra push inland (a big wave), metres.
var surge := 0.0

var _mat: ShaderMaterial
var _wet := 0.0
var _t := 0.0


## `shore` is a story/shore.gd survey: the sheet is laid out from its wake spot.
func build(shore) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://story/props/tide.gdshader")
	_mat.set_shader_parameter("fade_along", half_length)
	_mat.set_shader_parameter("fade_sea", sea_reach)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D.IDENTITY
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := cells.x
	var ny := cells.y
	for j in ny + 1:
		for i in nx + 1:
			var u := lerpf(-half_length, half_length, float(i) / nx)
			var v := lerpf(-inland_reach, sea_reach, float(j) / ny)
			var p: Vector3 = shore.wake + shore.along * u - shore.inland * v
			var g: Vector3 = shore.ground(p)
			p.y = maxf(g.y + 0.05, shore.sea_level + 0.02)
			st.set_uv(Vector2(u, v))
			st.add_vertex(p)
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	mesh = st.commit()
	custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))


func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	# Two out-of-step swells make the lapping irregular.
	var w := sin(_t * TAU / lap_period) * 0.7 + sin(_t * TAU / (lap_period * 1.63) + 1.3) * 0.3
	var edge := rest + lap * w - surge + drain * drained_by
	# The wet mark follows the water up at once and dries back slowly.
	if _t <= delta:
		_wet = edge
	_wet = minf(_wet + 0.35 * delta, edge)
	_mat.set_shader_parameter("edge", edge)
	_mat.set_shader_parameter("wet_edge", _wet)
	_mat.set_shader_parameter("swell", clampf(surge / 8.0, 0.0, 1.0))


## Where the water is now, in metres seaward of the wake spot.
func waterline() -> float:
	return rest - surge + drain * drained_by
