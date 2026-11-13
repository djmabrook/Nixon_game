class_name WatchingSet
extends Node3D
## A half-buried television whose eyes follow the little man.
## One sits in every region; its eyes close when the region is mended.
## The hub's set droops a little more with each ink brought home.
##
## Placeholder geometry. The art threads replace the meshes under Screen/ but should
## keep the node names (LeftEye, RightEye, each with Pupil and Lid) or override
## _apply_lids() and _track().

enum Mode {
	OPEN,      ## Eyes wide, tracking the little man.
	DROOPING,  ## Lids partly down, still tracking, slower.
	CLOSED,    ## Lids shut, still.
}

## Starting state. CLOSED sets are dark.
@export var mode := Mode.OPEN:
	set(v):
		mode = v
		if is_inside_tree():
			_target_lid = _lid_for_mode()
## Close when the room this set sits in calls Room.complete() (and start closed if it already did).
@export var close_on_room_complete := true
## Hub behaviour: lids lower by one third per ink home; closed when all three are home.
@export var droop_with_inks := false
## How quickly the eyes turn to follow.
@export var track_speed := 6.0
## How far the pupils travel inside the eye, in eye radii.
@export var pupil_travel := 0.45
## Lid speed (fraction per second).
@export var lid_speed := 0.6
## How far down the lids sit in DROOPING (0..1).
@export_range(0.0, 0.95) var droop_amount := 0.5:
	set(v):
		droop_amount = v
		if is_inside_tree():
			_target_lid = _lid_for_mode()

## Its sound: the Watcher's empty broadcast (audio/watcher_broadcast.gd). Louder the more open
## its eyes and the closer he is; it powers off when the lids shut. Null when muted.
@export var broadcast_enabled := true
## Within this many meters the set "stares": snow rises and the hum quickens.
@export var stare_radius := 25.0

## 0 = open, 1 = shut. Animates toward the mode's target.
var lid := 0.0
var broadcast: WatcherBroadcast
var _target_lid := 0.0
var _room: Room

@onready var _eyes: Array[Node3D] = [$Screen/LeftEye, $Screen/RightEye]


func _ready() -> void:
	_room = _find_room()
	if close_on_room_complete and _room:
		_room.room_completed.connect(close)
		if Game.is_completed(_room.room_id):
			mode = Mode.CLOSED
	if droop_with_inks:
		Game.ink_home.connect(func(_ink): _sync_to_inks())
		_sync_to_inks()
	_target_lid = _lid_for_mode()
	lid = _target_lid
	if broadcast_enabled:
		broadcast = WatcherBroadcast.new()
		broadcast.unit_size = 4.0
		add_child(broadcast)
		broadcast.position = Vector3(0, 1.0, 0)
		if lid >= 1.0:
			broadcast.presence = 0.0
			broadcast.eyes_open = false
	_apply_lids()


func _process(delta: float) -> void:
	lid = move_toward(lid, _target_lid, lid_speed * delta)
	_apply_lids()
	_update_broadcast()
	if mode != Mode.CLOSED and is_instance_valid(Game.player):
		var speed := track_speed * (0.4 if mode == Mode.DROOPING else 1.0)
		_track(Game.player.global_position + Vector3.UP * 1.2, speed * delta)


func _update_broadcast() -> void:
	if broadcast == null:
		return
	if mode == Mode.CLOSED:
		if broadcast.eyes_open and lid > 0.9:
			broadcast.close_eyes(0.8)
		return
	if not broadcast.eyes_open:
		broadcast.open_eyes(0.6)
	broadcast.presence = 1.0 - lid
	if is_instance_valid(Game.player):
		var d := global_position.distance_to(Game.player.global_position)
		broadcast.stare = clampf(1.0 - d / stare_radius, 0.0, 1.0) * (1.0 - lid)


func open() -> void:
	mode = Mode.OPEN


func droop(amount := 0.5) -> void:
	droop_amount = clampf(amount, 0.0, 0.95)
	mode = Mode.DROOPING


func close() -> void:
	mode = Mode.CLOSED


func _lid_for_mode() -> float:
	match mode:
		Mode.OPEN:
			return 0.0
		Mode.DROOPING:
			return droop_amount
		_:
			return 1.0


func _sync_to_inks() -> void:
	var p := Game.ink_progress()
	if p >= 1.0:
		close()
	elif p > 0.0:
		droop(p * 0.9)
	else:
		open()


## Slide each pupil toward the target, as seen from the screen.
func _track(world_target: Vector3, weight: float) -> void:
	for eye in _eyes:
		var pupil: Node3D = eye.get_node("Pupil")
		var local := eye.to_local(world_target).normalized()
		var r := (eye.get_node("White") as MeshInstance3D).mesh.get_aabb().size.x * 0.5
		var goal := Vector3(local.x, local.y, 0.0).limit_length(1.0) * r * pupil_travel
		goal.z = 0.02
		pupil.position = pupil.position.lerp(goal, clampf(weight, 0.0, 1.0))


## Lids are boxes that slide down over each eye; at 1 they cover it.
func _apply_lids() -> void:
	for eye in _eyes:
		var l: Node3D = eye.get_node("Lid")
		l.scale.y = maxf(lid, 0.001)
		l.visible = lid > 0.001
		l.position.y = 0.28 * (1.0 - lid)  # top edge stays at the top of the eye


func _find_room() -> Room:
	var n := get_parent()
	while n and not (n is Room):
		n = n.get_parent()
	return n as Room
