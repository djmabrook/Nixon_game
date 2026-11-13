extends Node3D
## A living flame: flickers its cones and its light with a little noise so no two
## fires breathe in step. Built by lakeside_look.gd.

var _noise := FastNoiseLite.new()
var _seed := randf() * 1000.0
var _t := 0.0
var _flames: Array[Node3D] = []
var _light: OmniLight3D


func _ready() -> void:
	_noise.frequency = 1.6
	for c in get_children():
		if c.name.begins_with("Flame"):
			_flames.append(c)
	_light = get_node_or_null("Light")


func _process(delta: float) -> void:
	_t += delta
	for i in _flames.size():
		var f := _flames[i]
		var n := _noise.get_noise_2d(_t * 3.0 + i * 17.0, _seed)
		var base: Vector3 = f.get_meta(&"base_scale", f.scale)
		if not f.has_meta(&"base_scale"):
			f.set_meta(&"base_scale", base)
		f.scale = Vector3(base.x * (1.0 - n * 0.15), base.y * (1.0 + n * 0.35), base.z * (1.0 - n * 0.15))
		f.rotation.y += delta * (0.6 + i * 0.4)
		f.rotation.z = n * 0.12
	if _light:
		var e: float = _light.get_meta(&"base_energy", _light.light_energy)
		var n2 := _noise.get_noise_2d(_t * 5.0, _seed + 50.0)
		_light.light_energy = e * (1.0 + n2 * 0.25)
		_light.position.x = n2 * 0.05
