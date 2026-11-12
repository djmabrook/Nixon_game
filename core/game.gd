extends Node
## Global game state and room travel. Autoloaded as `Game`.
##
## Every room lives at res://rooms/<room_id>/room.tscn and is found automatically.
## The hub is the special room id "hub" at res://hub/hub.tscn.
## Rooms never instance the player or camera: Game adds them on arrival.

signal room_changed(room: Room)

const HUB_ID := &"hub"
const HUB_SCENE := "res://hub/hub.tscn"
const ROOMS_DIR := "res://rooms"
const ROOM_FILE := "room.tscn"
const PLAYER_SCENE := preload("res://player/player.tscn")
const CAMERA_SCENE := preload("res://camera/follow_camera.tscn")
const FADE_TIME := 0.35

## The room currently loaded, the player inside it, and the camera following it.
var current_room: Room
var player: Player
var camera: FollowCamera

## Room ids the player has finished (Room.complete()). The hub reads this.
var completed_rooms: Dictionary = {}

var _world: Node
var _fade: ColorRect
var _travelling := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


## Called once by main.tscn. Everything Game loads goes under `world`.
func start(world: Node, first_room: StringName = HUB_ID) -> void:
	_world = world
	await go_to(first_room)


## Every room id found under res://rooms/ (folders starting with "_" are skipped).
func list_rooms() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir := DirAccess.open(ROOMS_DIR)
	if dir == null:
		return ids
	for folder in dir.get_directories():
		if folder.begins_with("_") or folder.begins_with("."):
			continue
		if ResourceLoader.exists(room_path(folder)):
			ids.append(StringName(folder))
	ids.sort()
	return ids


func room_path(room_id: StringName) -> String:
	if room_id == HUB_ID:
		return HUB_SCENE
	return "%s/%s/%s" % [ROOMS_DIR, room_id, ROOM_FILE]


func has_room(room_id: StringName) -> bool:
	return ResourceLoader.exists(room_path(room_id))


func go_to_hub(spawn: StringName = &"") -> void:
	await go_to(HUB_ID, spawn)


## Fade out, swap the room, place the player at `spawn` (a RoomSpawn name), fade in.
## An empty spawn uses the room's default spawn.
func go_to(room_id: StringName, spawn: StringName = &"") -> void:
	if _travelling:
		return
	if not has_room(room_id):
		push_error("Game.go_to: no room '%s' at %s" % [room_id, room_path(room_id)])
		return
	_travelling = true
	if current_room:
		await _fade_to(1.0)
		current_room.room_exiting.emit()
		current_room.queue_free()
		await current_room.tree_exited
		current_room = null
		player = null
		camera = null

	var scene: PackedScene = load(room_path(room_id))
	var room := scene.instantiate() as Room
	if room == null:
		push_error("Game.go_to: root of %s must use core/room.gd" % room_path(room_id))
		_travelling = false
		return
	room.room_id = room_id
	_world.add_child(room)
	current_room = room

	player = PLAYER_SCENE.instantiate()
	room.add_child(player)
	var marker := room.get_spawn(spawn)
	player.global_position = marker.global_position if marker else room.global_position
	if marker:
		player.face(-marker.global_basis.z)

	if room.use_default_camera:
		camera = CAMERA_SCENE.instantiate()
		room.add_child(camera)
		camera.target = player
		if marker:
			camera.yaw_degrees = marker.global_rotation_degrees.y
		room.configure_camera(camera)
		camera.snap_to_target()
		camera.make_current()

	room._on_room_entered(spawn)
	room.room_entered.emit()
	room_changed.emit(room)
	await _fade_to(0.0)
	_travelling = false


func is_travelling() -> bool:
	return _travelling


func mark_completed(room_id: StringName) -> void:
	completed_rooms[room_id] = true


func is_completed(room_id: StringName) -> bool:
	return completed_rooms.has(room_id)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
