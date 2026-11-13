class_name SurfBoard
extends Node3D
## The board: a dark slab hovering a few centimetres over the sand, its rim and belly lit
## with a colour that drifts through the spectrum faster the better he's flowing.
## Built from code (no asset needed); swap `mesh` for a modelled board any time.

const LENGTH := 1.42
const WIDTH := 0.42
const THICK := 0.045
const HOVER := 0.028
const ROCKER := 0.05

## Set by the Surfer every frame.
var flow := 0.0
var speed := 0.0

var mesh_instance: MeshInstance3D
var glow: OmniLight3D
var _mat: ShaderMaterial
var _hue := 0.0


func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = build_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://surf/surf_board.gdshader")
	mesh_instance.material_override = _mat
	add_child(mesh_instance)
	glow = OmniLight3D.new()
	glow.name = "BellyGlow"
	glow.position = Vector3(0, 0.01, 0)
	glow.omni_range = 4.5
	glow.light_energy = 0.8
	glow.shadow_enabled = false
	add_child(glow)


func _process(delta: float) -> void:
	_hue = fposmod(_hue + delta * (0.03 + 0.25 * flow + speed * 0.002), 1.0)
	_mat.set_shader_parameter(&"hue", _hue)
	_mat.set_shader_parameter(&"flow", flow)
	glow.light_color = Color.from_hsv(_hue, 0.75, 1.0)
	glow.light_energy = 0.7 + 2.6 * flow + speed * 0.015
	glow.omni_range = 3.5 + 4.0 * flow


## Outline: a superellipse, nose and tail rockered up. COLOR marks parts for the shader:
## r = rim, g = deck, b = belly.
static func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var outline: Array[Vector2] = []
	for i in n:
		var a := TAU * float(i) / n
		var c := cos(a)
		var s := sin(a)
		var e := 2.6
		var x := signf(c) * pow(absf(c), 2.0 / e) * WIDTH * 0.5
		var z := signf(s) * pow(absf(s), 2.0 / e) * LENGTH * 0.5
		outline.append(Vector2(x, z))
	var rock := func(z: float) -> float: return ROCKER * pow(absf(z) / (LENGTH * 0.5), 3.0)
	var bottom := func(p: Vector2) -> Vector3: return Vector3(p.x, HOVER + rock.call(p.y), p.y)
	var top := func(p: Vector2) -> Vector3: return Vector3(p.x, HOVER + THICK + rock.call(p.y), p.y)
	var deck_c := Color(0, 1, 0)
	var belly_c := Color(0, 0, 1)
	var rim_c := Color(1, 0, 0)
	var center_top := Vector3(0, HOVER + THICK, 0)
	var center_bot := Vector3(0, HOVER, 0)
	for i in n:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		# Deck (seen from above: clockwise winding is front-facing in Godot).
		_v(st, center_top, deck_c, Vector2(0.5, 0.5))
		_v(st, top.call(p1), deck_c, _uv(p1))
		_v(st, top.call(p0), deck_c, _uv(p0))
		# Belly (seen from below).
		_v(st, center_bot, belly_c, Vector2(0.5, 0.5))
		_v(st, bottom.call(p0), belly_c, _uv(p0))
		_v(st, bottom.call(p1), belly_c, _uv(p1))
		# Rim.
		var a: Vector3 = top.call(p0)
		var b: Vector3 = top.call(p1)
		var c: Vector3 = bottom.call(p0)
		var d: Vector3 = bottom.call(p1)
		_v(st, a, rim_c, _uv(p0))
		_v(st, b, rim_c, _uv(p1))
		_v(st, d, rim_c, _uv(p1))
		_v(st, a, rim_c, _uv(p0))
		_v(st, d, rim_c, _uv(p1))
		_v(st, c, rim_c, _uv(p0))
	st.generate_normals()
	return st.commit()


static func _uv(p: Vector2) -> Vector2:
	return Vector2(p.x / WIDTH + 0.5, p.y / LENGTH + 0.5)


static func _v(st: SurfaceTool, p: Vector3, c: Color, uv: Vector2) -> void:
	st.set_color(c)
	st.set_uv(uv)
	st.add_vertex(p)
