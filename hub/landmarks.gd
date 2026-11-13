@tool
extends Node3D
## Far-off things you see from the ridge, as switchable layers. Each is a painted cut-out
## (art/tex/horizon_*.png) standing 2 to 3.5 km out, square-on to the crater, outside the
## fog. The story decides when each layer shows; flip the exports or call set_layer.
##
## - Watcher: a dark head peeking over the horizon with two red eyes, under the stone-faced
##   range. The eyes go dark at dawn (watcher_eyes).
## - Beacon: the cone mountain far out at sea. Dark until ember is home, then its fire is lit.
## - PinkStorm: a breaking wave of pink cloud.
## - BlackDisc: a black disc hanging in the sky (there from the start; gone once crimson is home).
## Always there: the checker sphere rising, the glyph skyline, the colossi palms, the statues.

const TEX := "res://hub/art/tex/%s.png"
const SHADER := preload("res://hub/horizon.gdshader")

@export var watcher := true:
	set(v):
		watcher = v
		_sync()
@export var beacon := false:
	set(v):
		beacon = v
		_sync()
@export var pink_storm := false:
	set(v):
		pink_storm = v
		_sync()
@export var black_disc := true:
	set(v):
		black_disc = v
		_sync()
## The Watcher's two red lights. They go out at dawn.
@export var watcher_eyes := true:
	set(v):
		watcher_eyes = v
		_sync()
## 0 drained (bone and black) to 1 full colour. The story drives it.
@export_range(0.0, 1.0) var color_amount := 1.0:
	set(v):
		color_amount = v
		for m in _mats:
			m.set_shader_parameter("color_amount", v)
## 0 night to 1 dawn: cut-outs with a painted _dawn version switch to it.
@export_range(0.0, 1.0) var dawn := 0.0:
	set(v):
		dawn = v
		for m in _mats:
			m.set_shader_parameter("dawn", v)
## Color the far silhouettes lean toward, standing in for atmospheric haze.
@export var haze := Color(0.32, 0.07, 0.06)

var _mats: Array[ShaderMaterial] = []
var _watcher_mat: ShaderMaterial


func _ready() -> void:
	_build()
	_sync()


## Where the Watcher stands (local), so the hub can aim the fourth groove at it.
func watcher_position() -> Vector3:
	return _polar(3200.0, 225.0)


func set_layer(layer: StringName, on: bool) -> void:
	set(String(layer).to_snake_case(), on)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _watcher_mat == null or not watcher_eyes:
		return
	# The Watcher's eyes breathe very slowly.
	var t := Time.get_ticks_msec() / 1000.0
	_watcher_mat.set_shader_parameter("glow", 1.6 + 0.6 * sin(t * 0.4))


func _sync() -> void:
	if not is_node_ready():
		return
	for pair in [["Watcher", watcher], ["Beacon", beacon], ["BeaconDark", not beacon],
			["PinkStorm", pink_storm], ["BlackDisc", black_disc]]:
		if has_node(pair[0]):
			get_node(pair[0]).visible = pair[1]
	if _watcher_mat:
		_watcher_mat.set_shader_parameter("eyes_dim", 0.0 if watcher_eyes else 1.0)
		_watcher_mat.set_shader_parameter("glow", 1.6 if watcher_eyes else 1.0)


func _polar(dist: float, deg: float, y := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * dist, y, sin(a) * dist)


## A painted cut-out `width` metres wide (height from the texture's aspect), its bottom
## edge `sink` metres below sea level, standing at dist/deg and facing the crater.
func _cutout(parent: Node3D, tex_name: String, dist: float, deg: float, width: float, sink := 20.0, lift := 0.0) -> MeshInstance3D:
	var tex: Texture2D = load(TEX % tex_name)
	var h := width * float(tex.get_height()) / float(tex.get_width())
	var q := QuadMesh.new()
	q.size = Vector2(width, h)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("haze", Color(haze.r, haze.g, haze.b))
	m.set_shader_parameter("color_amount", color_amount)
	m.set_shader_parameter("dawn", dawn)
	for variant in ["drained", "dawn"]:
		var path := TEX % (tex_name + "_" + variant)
		if ResourceLoader.exists(path):
			m.set_shader_parameter("tex_" + variant, load(path))
			m.set_shader_parameter("has_" + variant, true)
	_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.name = tex_name.to_pascal_case()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var at := _polar(dist, deg, h * 0.5 - sink + lift) - parent.position
	mi.position = at
	# Square-on to the crater's centre (QuadMesh faces +Z).
	var out := Vector3(cos(deg_to_rad(deg)), 0.0, sin(deg_to_rad(deg)))
	mi.basis = Basis.looking_at(out, Vector3.UP)
	return mi


func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	add_child(g)
	return g


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_mats.clear()

	# The Watcher: straight across the crater from the shore you arrive on.
	var w := _group("Watcher")
	# The stone head, about 1 km across: from the rim its eyes clear the far side of the
	# crater. Its bottom cut sits below the rim line, and the range tucks in round its sides.
	var head := _cutout(w, "horizon_watcher_head", 3400.0, 225.0, 1000.0, -60.0)
	_watcher_mat = head.material_override
	_watcher_mat.set_shader_parameter("keep_red", 1.0)
	_cutout(w, "horizon_watcher_range", 3500.0, 196.0, 4200.0, 30.0)
	_cutout(w, "horizon_watcher_range", 3150.0, 239.0, 2400.0, 30.0)
	var left := _cutout(w, "horizon_watcher_range", 3150.0, 211.0, 2400.0, 30.0)
	left.scale.x = -1.0   # mirrored, so the two ranges cradle the head

	# The beacon: the cone mountain at sea, dark until ember comes home.
	var bd := _group("BeaconDark")
	_cutout(bd, "horizon_cone_mountain", 2400.0, 130.0, 1500.0, 40.0)
	var b := _group("Beacon")
	var lit := _cutout(b, "horizon_cone_lit", 2400.0, 130.0, 1500.0, 40.0)
	lit.material_override.set_shader_parameter("glow", 2.5)

	# The pink storm: a breaking wave of cloud low over the sea.
	var s := _group("PinkStorm")
	_cutout(s, "cloud_front_wave", 2900.0, 300.0, 5200.0, 0.0, 120.0)

	# Always on the horizon.
	var far := _group("Far")
	_cutout(far, "horizon_sphere_rise", 3000.0, 62.0, 1800.0, 60.0)
	_cutout(far, "horizon_glyph_skyline", 3300.0, 345.0, 4600.0, 30.0)
	_cutout(far, "horizon_palm_colossi", 2600.0, 165.0, 5000.0, 140.0)
	_cutout(far, "horizon_palm_colossi", 2700.0, 268.0, 4400.0, 130.0)
	_cutout(far, "far_statues", 1700.0, 95.0, 900.0, 40.0)

	# The black disc: a flat black circle hanging in the sky.
	var d := _group("BlackDisc")
	d.position = _polar(2600.0, 20.0, 700.0)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 260.0
	dm.bottom_radius = 260.0
	dm.height = 4.0
	dm.radial_segments = 48
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.disable_fog = true
	dmat.albedo_color = Color.BLACK
	disc.material_override = dmat
	d.add_child(disc)
	disc.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(20.0), 0.0)
