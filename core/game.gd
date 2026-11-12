extends Node
## Global game state and room travel. Autoloaded as `Game`.
##
## Every room lives at res://rooms/<room_id>/room.tscn and is found automatically.
## The hub is the special room id "hub" at res://hub/hub.tscn.
## Rooms never instance the player or camera: Game adds them on arrival.

signal room_changed(room: Room)
## The little man picked up a region's ink (Game.carry). He's now carrying it.
signal ink_gained(ink: StringName)
## An ink was planted at the spiral (Game.bring_home). inks_home already includes it.
signal ink_home(ink: StringName)
## What the little man carries changed (&"" = nothing).
signal carried_changed(ink: StringName)

const HUB_ID := &"hub"
const HUB_SCENE := "res://hub/hub.tscn"
const ROOMS_DIR := "res://rooms"
const ROOM_FILE := "room.tscn"
const PLAYER_SCENE := preload("res://player/player.tscn")
const CAMERA_SCENE := preload("res://camera/follow_camera.tscn")
const FADE_TIME := 0.35

## The three inks carried home from the outer regions, in no particular order.
const INKS: Array[StringName] = [&"ember", &"salmon", &"crimson"]
## Shadow lag at the start (no inks home). It falls to 0 when all three are home.
const SHADOW_LAG_START := 0.5
const SAVE_PATH := "user://save.json"

## The room currently loaded, the player inside it, and the camera following it.
var current_room: Room
var player: Player
var camera: FollowCamera

## Room ids the player has finished (Room.complete()). The hub reads this.
var completed_rooms: Dictionary = {}

## Story state. Saved to disk on every change.
## Inks planted at the spiral, in the order they arrived.
var inks_home: Array[StringName] = []
## The ink the little man is carrying right now (&"" = nothing). Survives room travel.
var carried: StringName = &""
## Small persistent story flags that survive relaunch and new cycles
## (e.g. opening_seen, ending_seen). Values must be JSON-friendly.
var flags: Dictionary = {}
## Turn off to keep tests and experiments from touching the save file.
var save_enabled := true

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
	load_game()


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
	if is_room_locked(room_id):
		push_warning("Game.go_to: room '%s' is locked (needs %s)" % [room_id, required_inks_for(room_id)])
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
	save_game()


func is_completed(room_id: StringName) -> bool:
	return completed_rooms.has(room_id)


# --- Inks -------------------------------------------------------------------

## The little man takes a region's ink (call when its room is mended).
## Does nothing if that ink is already home.
func carry(ink: StringName) -> void:
	if not INKS.has(ink):
		push_error("Game.carry: unknown ink '%s'" % ink)
		return
	if is_ink_home(ink) or carried == ink:
		return
	carried = ink
	ink_gained.emit(ink)
	carried_changed.emit(carried)
	save_game()


## Plant what he's carrying at the spiral. Pass an ink to require that one.
## Returns the ink brought home, or &"" if there was nothing to bring.
func bring_home(ink: StringName = &"") -> StringName:
	if carried == &"" or (ink != &"" and ink != carried):
		return &""
	var brought := carried
	carried = &""
	if not inks_home.has(brought):
		inks_home.append(brought)
	carried_changed.emit(carried)
	ink_home.emit(brought)
	save_game()
	return brought


func is_ink_home(ink: StringName) -> bool:
	return inks_home.has(ink)


func all_inks_home() -> bool:
	return inks_home.size() >= INKS.size()


## 0.0 at the start, 1.0 when all three inks are home. Handy for anything that heals by degrees.
func ink_progress() -> float:
	return float(inks_home.size()) / float(INKS.size())


## How far (seconds) the little man's shadow trails him right now.
func shadow_lag() -> float:
	return SHADOW_LAG_START * (1.0 - ink_progress())


# --- Locking ----------------------------------------------------------------

## The inks a room needs home before it opens (its Room.required_inks export).
func required_inks_for(room_id: StringName) -> Array[StringName]:
	if not has_room(room_id):
		return [] as Array[StringName]
	return required_inks_in_scene(room_path(room_id))


## Reads Room.required_inks from a room scene's root without instancing it.
func required_inks_in_scene(scene_path: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var state := (load(scene_path) as PackedScene).get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"required_inks":
			for ink in state.get_node_property_value(0, i):
				out.append(StringName(ink))
	return out


func is_room_locked(room_id: StringName) -> bool:
	return not inks_satisfy(required_inks_for(room_id))


## True if every ink in `needed` is home.
func inks_satisfy(needed: Array[StringName]) -> bool:
	for ink in needed:
		if not is_ink_home(ink):
			return false
	return true


# --- Save -------------------------------------------------------------------

func save_game() -> void:
	if not save_enabled:
		return
	var data := {
		"inks_home": inks_home.map(func(i): return String(i)),
		"carried": String(carried),
		"completed_rooms": completed_rooms.keys().map(func(r): return String(r)),
		"flags": flags,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	if not save_enabled or not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	inks_home.clear()
	for i in data.get("inks_home", []):
		inks_home.append(StringName(i))
	carried = StringName(data.get("carried", ""))
	completed_rooms.clear()
	for r in data.get("completed_rooms", []):
		completed_rooms[StringName(r)] = true
	flags.clear()
	var saved_flags = data.get("flags", {})
	if typeof(saved_flags) == TYPE_DICTIONARY:
		for k in saved_flags:
			flags[StringName(k)] = saved_flags[k]


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value
	save_game()


func get_flag(flag: StringName, default: Variant = null) -> Variant:
	return flags.get(flag, default)


## Start the story over after the ending: clears inks, carried item and mended rooms,
## keeps flags (so the title can remember the ending was seen).
func new_cycle() -> void:
	inks_home.clear()
	carried = &""
	completed_rooms.clear()
	carried_changed.emit(carried)
	save_game()


## Wipe everything, flags included, and delete the save file.
func reset_story() -> void:
	flags.clear()
	inks_home.clear()
	carried = &""
	completed_rooms.clear()
	if save_enabled and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	carried_changed.emit(carried)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
