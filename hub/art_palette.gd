extends RefCounted
## Drains imported models to bone and black and brings their colour back with the inks.
## prepare() gives every mesh under `root` its own copies of its materials and remembers
## each one's full colour and its drained colour; apply() blends between them.

const BONE_LIGHT := Color(0.86, 0.80, 0.68)
const BONE_DARK := Color(0.05, 0.045, 0.04)
const TEXTURED_DRAINED := Color(0.42, 0.40, 0.37)


## Returns entries for apply(). `skip` names materials the caller drives itself.
static func prepare(root: Node, skip: Array[String] = []) -> Array:
	var entries: Array = []
	var cache := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as StandardMaterial3D
			if src == null or skip.has(src.resource_name):
				continue
			if not cache.has(src):
				var m: StandardMaterial3D = src.duplicate()
				var full := src.albedo_color
				var drained: Color
				if src.albedo_texture:
					drained = TEXTURED_DRAINED
				else:
					var l := full.get_luminance()
					drained = BONE_DARK.lerp(BONE_LIGHT, smoothstep(0.02, 0.6, l))
				cache[src] = m
				entries.append([m, full, drained, src.emission_enabled, src.emission_energy_multiplier])
			(mi as MeshInstance3D).set_surface_override_material(s, cache[src])
	return entries


static func apply(entries: Array, amount: float) -> void:
	for e in entries:
		var m: StandardMaterial3D = e[0]
		m.albedo_color = (e[2] as Color).lerp(e[1], amount)
		if e[3]:
			m.emission_enabled = amount > 0.01
			m.emission_energy_multiplier = float(e[4]) * amount


## Collision from the model's own triangles. Headless runs have no mesh data for this,
## so it quietly does nothing there.
static func add_collision(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)


static func material_named(root: Node, name: String) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as StandardMaterial3D
			if src and src.resource_name == name:
				var m: StandardMaterial3D = src.duplicate()
				(mi as MeshInstance3D).set_surface_override_material(s, m)
				out.append(m)
	return out
