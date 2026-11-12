@tool
extends Node3D
## Placeholder palm built from boxes: a leaning, curving trunk and drooping fronds.
## Swap for the real model later (a GLB from the Meshy thread) and delete this script.

@export var height := 4.5:
	set(v):
		height = v
		_build()
@export var lean := 0.35:
	set(v):
		lean = v
		_build()
@export var fronds := 8:
	set(v):
		fronds = v
		_build()
@export var trunk_color := Color(0.30, 0.13, 0.09)
@export var frond_color := Color(0.12, 0.38, 0.22)


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not has_node("Crown"):
		return
	var t := Time.get_ticks_msec() / 1000.0 + position.x
	$Crown.rotation.z = 0.04 * sin(t * 0.9)
	$Crown.rotation.x = 0.03 * sin(t * 0.7 + 1.0)


func _build() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		remove_child(c)
		c.free()
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = trunk_color
	trunk_mat.roughness = 1.0
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = frond_color
	frond_mat.roughness = 1.0
	frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var segs := 7
	var top := Vector3.ZERO
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var a := Vector3(lean * height * t0 * t0, height * t0, 0)
		var b := Vector3(lean * height * t1 * t1, height * t1, 0)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		var w := lerpf(0.34, 0.2, t0)
		box.size = Vector3(w, a.distance_to(b) + 0.05, w)
		box.material = trunk_mat
		seg.mesh = box
		add_child(seg)
		seg.position = (a + b) * 0.5
		seg.rotation.z = -atan2(b.x - a.x, b.y - a.y)
		top = b

	var crown := Node3D.new()
	crown.name = "Crown"
	add_child(crown)
	crown.position = top
	for i in fronds:
		var yaw := TAU * float(i) / fronds + 0.3 * sin(i * 2.1)
		var pivot := Node3D.new()
		crown.add_child(pivot)
		pivot.rotation = Vector3(0, yaw, 0)
		# Two pieces per frond so it arcs up then droops.
		for k in 2:
			var leaf := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.1, 0.04, 0.42 - 0.12 * k)
			bm.material = frond_mat
			leaf.mesh = bm
			pivot.add_child(leaf)
			leaf.position = Vector3(0.5 + 1.0 * k, 0.15 - 0.45 * k, 0)
			leaf.rotation.z = 0.25 - 0.75 * k
