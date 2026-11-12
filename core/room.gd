class_name Room
extends Node3D
## Root script for every room (and the hub). See CONVENTIONS.md.
##
## A room is a self-contained 3D scene. It must contain at least one RoomSpawn
## and usually one RoomExit back to the hub. Game adds the player and camera
## after the room is in the tree, then calls _on_room_entered().
## Override the hooks below to make the room break its rule.

## Fired after the player and camera are placed.
signal room_entered
## Fired just before the room is freed.
signal room_exiting
## Fired once when complete() is first called.
signal room_completed

## Set by Game from the folder name. Don't edit it in the scene.
var room_id: StringName

## Inks that must be home before this room opens (e.g. the mountain needs all three).
## Exits into a locked room do nothing, and the hub can show its door as shut.
@export var required_inks: Array[StringName] = []
## The ink this room gives when mended. complete() hands it to the little man.
@export var gives_ink: StringName = &""

@export_group("Camera")
## Set false if the room brings its own Camera3D (call make_current() yourself).
@export var use_default_camera := true
## Orbit distance from the little man, in meters. Pull back for vast spaces.
@export var camera_distance := 7.0
## Starting downward tilt in degrees (negative looks down).
@export var camera_pitch_degrees := -6.0
## Field of view. Lower (35-50) flattens and makes distant landmarks loom.
@export var camera_fov := 60.0
## Draw distance in meters.
@export var camera_far := 4000.0
## The room's landmark. Holding `focus` turns the camera toward it.
@export var focus_target: Node3D

@export_group("Look")
## Background color shown where there is no geometry.
@export var clear_color := Color.BLACK


## Override to set up rule-breaking behavior once the player is in the room.
func _on_room_entered(_spawn: StringName) -> void:
	pass


## Lets a room tweak the default camera before it's made current.
## The spawn's facing has already set the yaw.
func configure_camera(cam: FollowCamera) -> void:
	cam.distance = camera_distance
	cam.pitch_degrees = camera_pitch_degrees
	cam.set_base_fov(camera_fov)
	cam.far = camera_far
	cam.focus_target = focus_target
	RenderingServer.set_default_clear_color(clear_color)


## The spawn named `spawn_name`, else the one marked default, else the first.
func get_spawn(spawn_name: StringName = &"") -> RoomSpawn:
	var spawns: Array[RoomSpawn] = []
	for n in find_children("*", "Marker3D", true, false):
		if n is RoomSpawn:
			spawns.append(n)
	if spawns.is_empty():
		push_warning("Room '%s' has no RoomSpawn; player starts at the room origin." % room_id)
		return null
	if spawn_name != &"":
		for s in spawns:
			if s.name == spawn_name:
				return s
		push_warning("Room '%s' has no spawn '%s'; using default." % [room_id, spawn_name])
	for s in spawns:
		if s.is_default:
			return s
	return spawns[0]


## Call when the player has solved/survived the room. The hub can react to it.
func complete() -> void:
	if Game.is_completed(room_id):
		return
	Game.mark_completed(room_id)
	if gives_ink != &"":
		Game.carry(gives_ink)
	room_completed.emit()


## Leave the room. Defaults to the hub's door for this room (a spawn named after room_id).
func exit_to_hub() -> void:
	Game.go_to_hub(room_id)
