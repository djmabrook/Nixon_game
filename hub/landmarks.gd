@tool
extends Node3D
## Far-off things you see from the ridge, as switchable layers. Placeholder geometry,
## built in code; each layer is a child Node3D you can swap for a real model.
## They ignore fog (so they stay as silhouettes) and are tinted toward the haze instead.
##
## - Watcher: a mountain on the horizon with two faint red lights near its peak.
## - Beacon: a lit tower far out at sea.
## - PinkStorm: a bank of pink storm cloud.
## - BlackDisc: a black disc hanging in the sky (there from the start; gone once crimson is home).
## The story decides when each appears; flip the exports (or call set_layer) to show them.

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
## Color the far silhouettes lean toward, standing in for atmospheric haze.
@export var haze := Color(0.32, 0.07, 0.06)


func _ready() -> void:
	_build()
	_sync()


## Where the Watcher's mountain stands (local), so the hub can aim the fourth groove at it.
func watcher_position() -> Vector3:
	return _polar(3200.0, 225.0)


func set_layer(layer: StringName, on: bool) -> void:
	set(String(layer).to_snake_case(), on)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not has_node("Watcher"):
		return
	# The Watcher's lights breathe very slowly.
	var t := Time.get_ticks_msec() / 1000.0
	var e := 3.0 + 1.5 * sin(t * 0.4)
	for eye in $Watcher.get_children():
		if eye is MeshInstance3D and eye.name.begins_with("Eye"):
			(eye.material_override as StandardMaterial3D).emission_energy_multiplier = e


func _sync() -> void:
	if not is_node_ready():
		return
	for pair in [["Watcher", watcher], ["Beacon", beacon], ["PinkStorm", pink_storm], ["BlackDisc", black_disc]]:
		if has_node(pair[0]):
			get_node(pair[0]).visible = pair[1]
	if has_node("Watcher"):
		for eye in $Watcher.get_children():
			if eye.name.begins_with("Eye"):
				eye.visible = watcher_eyes


func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.albedo_color = c
	if emit:
		m.emission_enabled = true
		m.emission = c
	return m


func _polar(dist: float, deg: float, y := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * dist, y, sin(a) * dist)


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.free()

	# The Watcher: a broad dark mountain straight across the crater from the shore you arrive on.
	var w := Node3D.new()
	w.name = "Watcher"
	add_child(w)
	w.position = watcher_position()
	var peak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 40.0
	cone.bottom_radius = 900.0
	cone.height = 650.0
	cone.radial_segments = 9
	cone.rings = 1
	peak.mesh = cone
	peak.material_override = _mat(Color(0.05, 0.015, 0.02).lerp(haze, 0.25))
	w.add_child(peak)
	peak.position.y = 300.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye%d" % int(side)
		var sm := SphereMesh.new()
		sm.radius = 9.0
		sm.height = 18.0
		eye.mesh = sm
		eye.material_override = _mat(Color(1.0, 0.08, 0.04), true)
		w.add_child(eye)
		# Facing the crater: offset sideways along the mountain's face.
		var to_center := -w.position.normalized()
		var side_dir := to_center.cross(Vector3.UP).normalized()
		eye.position = Vector3(0, 520.0, 0) + to_center * 120.0 + side_dir * side * 45.0

	# The Beacon: a tall thin tower with a lit crown, far out at sea.
	var b := Node3D.new()
	b.name = "Beacon"
	add_child(b)
	b.position = _polar(2400.0, 130.0)
	var tower := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(20, 420, 20)
	tower.mesh = tm
	tower.material_override = _mat(Color(0.06, 0.02, 0.02).lerp(haze, 0.3))
	b.add_child(tower)
	tower.position.y = 210.0
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 22.0
	cm.height = 44.0
	crown.mesh = cm
	crown.material_override = _mat(Color(1.0, 0.45, 0.12), true)
	b.add_child(crown)
	crown.position.y = 440.0

	# The pink storm: stacked, flattened cloud masses low over the sea.
	var s := Node3D.new()
	s.name = "PinkStorm"
	add_child(s)
	s.position = _polar(2800.0, 300.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var puff := MeshInstance3D.new()
		var pm := SphereMesh.new()
		var rad := rng.randf_range(160.0, 340.0)
		pm.radius = rad
		pm.height = rad * 0.9
		puff.mesh = pm
		puff.material_override = _mat(Color(0.95, 0.45, 0.65).lerp(haze, rng.randf_range(0.15, 0.45)))
		s.add_child(puff)
		puff.position = Vector3(rng.randf_range(-900, 900), rng.randf_range(120, 520), rng.randf_range(-300, 300))
		puff.scale = Vector3(1.6, 0.55, 1.0)

	# The black disc: a flat black circle hanging in the sky, edge-on to nothing.
	var d := Node3D.new()
	d.name = "BlackDisc"
	add_child(d)
	d.position = _polar(2600.0, 20.0, 700.0)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 260.0
	dm.bottom_radius = 260.0
	dm.height = 4.0
	dm.radial_segments = 48
	disc.mesh = dm
	disc.material_override = _mat(Color(0.0, 0.0, 0.0))
	d.add_child(disc)
	disc.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(20.0), 0.0)
