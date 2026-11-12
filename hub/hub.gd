extends Room
## PLACEHOLDER HUB. The hub thread replaces this with the sand spiral.
## Keep the contract it shows: for each room id, a RoomExit into that room and a
## RoomSpawn named after the room id so the player comes back out at that door.
## Doors are giant slabs on a wide ring, so walking to one takes a while.

@export var ring_radius := 90.0
@export var door_size := Vector3(8.0, 40.0, 3.0)


func _ready() -> void:
	var ids := Game.list_rooms()
	for i in ids.size():
		var angle := TAU * float(i) / float(maxi(ids.size(), 1)) + PI
		var door_pos := Vector3(sin(angle), 0.0, cos(angle)) * ring_radius
		_add_door(ids[i], door_pos)


func _add_door(id: StringName, pos: Vector3) -> void:
	var slab := StaticBody3D.new()
	slab.name = "Slab_%s" % id
	add_child(slab)
	slab.position = pos + Vector3(0, door_size.y * 0.5, 0)
	slab.look_at(Vector3(0, slab.position.y, 0), Vector3.UP)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = door_size
	mesh.mesh = bm
	slab.add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = door_size
	col.shape = bs
	slab.add_child(col)
	if focus_target == null:
		focus_target = slab

	# The doorway: a trigger at the foot of the slab, on the hub side.
	var inward := -pos.normalized()
	var exit := RoomExit.new()
	exit.name = "Door_%s" % id
	exit.target_room = id
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_size.x, 4.0, 2.0)
	shape.shape = box
	shape.position.y = 2.0
	exit.add_child(shape)
	add_child(exit)
	exit.position = pos + inward * (door_size.z * 0.5 + 1.0)
	exit.look_at(exit.position + inward, Vector3.UP)

	# Return spot: a few steps toward the hub centre, facing away from the door.
	var spawn := RoomSpawn.new()
	spawn.name = String(id)
	add_child(spawn)
	spawn.position = pos + inward * 8.0
	spawn.look_at(spawn.position + inward, Vector3.UP)
