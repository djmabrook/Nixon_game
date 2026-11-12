extends RoomExit
## The pit at the center of the spiral. It is one RoomExit for every room:
## the rim is split into one slice per room, at the inner end of that room's groove,
## and the slice the little man walks in through picks the room.
## The hub plays the sinking sequence first, then calls trigger().

signal swallowed(player: Player, room_id: StringName)

## Room ids in arm order, and the angle (radians, atan2(z, x)) where each arm meets the rim.
var room_ids: Array[StringName] = []
var arm_angles: PackedFloat32Array = []
## Which slices lead anywhere. A locked groove (the ultraviolet one before three inks)
## is closed, and walking in over it takes you to the nearest open room instead.
var open: Array[bool] = []


func _ready() -> void:
	super()
	require_interact = false


## The room whose slice of the rim contains `angle`. Empty if there are no rooms.
func room_at_angle(angle: float) -> StringName:
	if room_ids.is_empty():
		return &""
	var best := 0
	var best_d := INF
	for i in arm_angles.size():
		if i < open.size() and not open[i]:
			continue
		var d := absf(angle_difference(angle, arm_angles[i]))
		if d < best_d:
			best_d = d
			best = i
	if best_d == INF:
		return &""
	return room_ids[best]


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	_player_inside = true
	if not enabled or Game.is_travelling():
		return
	var offset := body.global_position - global_position
	var id := room_at_angle(atan2(offset.z, offset.x))
	if id == &"":
		return
	enabled = false
	target_room = id
	target_spawn = &""
	swallowed.emit(body, id)


## Called by the hub when the sinking sequence ends.
func go() -> void:
	enabled = true
	trigger()
