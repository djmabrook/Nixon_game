extends Room
## PLACEHOLDER HUB. The hub thread replaces this with the sand spiral.
## Keep the contract it shows: for each room id, a RoomExit into that room and a
## RoomSpawn named after the room id so the player comes back out at that door.

@export var ring_radius := 6.0


func _ready() -> void:
	var ids := Game.list_rooms()
	for i in ids.size():
		var angle := TAU * float(i) / float(maxi(ids.size(), 1))
		var door_pos := Vector3(sin(angle), 0.0, cos(angle)) * ring_radius
		_add_door(ids[i], door_pos)


func _add_door(id: StringName, pos: Vector3) -> void:
	var exit := RoomExit.new()
	exit.name = "Door_%s" % id
	exit.target_room = id
	exit.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.0, 1.2)
	shape.shape = box
	shape.position.y = 1.0
	exit.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.0, 0.2)
	mesh.mesh = bm
	mesh.position.y = 1.0
	exit.add_child(mesh)
	add_child(exit)

	# Return spot: one step toward the hub centre from the door, facing outward.
	var spawn := RoomSpawn.new()
	spawn.name = String(id)
	add_child(spawn)
	spawn.position = pos * ((ring_radius - 2.0) / ring_radius)
	if pos.length() > 0.01:
		spawn.look_at(spawn.position + pos.normalized(), Vector3.UP)
