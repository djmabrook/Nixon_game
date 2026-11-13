extends Node3D
## What the story adds to the hub on every visit: the wash at the tideline, the first
## television half-buried in the shore, and the story's sound. Story adds it whenever
## the hub loads; the sequences find it as the hub's "StoryDressing" child.

signal surveyed

const Shore := preload("res://story/shore.gd")
const TIDE := preload("res://story/props/tide.gd")
const AUDIO := preload("res://story/story_audio.gd")
const SET_SCENE := "res://props/watching_set.tscn"

## The first television: how big, and where relative to the wake spot.
const TV_SCALE := 5.0
const TV_INLAND := 38.0
const TV_SIDE := -16.0

var shore: Shore
var tide: MeshInstance3D
var tv: Node3D
var audio: AudioStreamPlayer
var is_surveyed := false


func _ready() -> void:
	name = "StoryDressing"
	audio = AUDIO.new()
	audio.name = "StoryAudio"
	add_child(audio)
	audio.surf = 0.8
	audio.under_sound_engine = get_node_or_null(^"/root/Sound") != null
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	shore = Shore.new(get_parent())
	shore.survey()
	tide = TIDE.new()
	tide.name = "Tide"
	add_child(tide)
	tide.build(shore)
	_place_tv()
	is_surveyed = true
	surveyed.emit()


func wait_surveyed() -> void:
	if not is_surveyed:
		await surveyed


## The first television, unless the hub already has a watching set of its own.
func _place_tv() -> void:
	for n in get_parent().find_children("*", "", true, false):
		if n != self and n.get_script() and String(n.get_script().resource_path).ends_with("watching_set.gd"):
			tv = n
			return
	if not ResourceLoader.exists(SET_SCENE):
		return
	var a := shore.anchor(&"first_tv")
	var pos: Vector3 = a.global_position if a else shore.wake + shore.inland * TV_INLAND + shore.along * TV_SIDE
	tv = load(SET_SCENE).instantiate()
	tv.name = "FirstTelevision"
	tv.set(&"close_on_room_complete", false)
	tv.set(&"droop_with_inks", true)
	add_child(tv)
	var g := shore.ground(pos)
	# Half-buried: sunk to below the screen's lower edge and tipped back, as if the sand
	# had been drifting over it for years. The screen faces the wake spot.
	var to_wake := shore.wake - g
	to_wake.y = 0.0
	var yaw := atan2(to_wake.x, to_wake.z)   # the set's screen faces +Z
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-11.0)) * Basis(Vector3.FORWARD, deg_to_rad(6.0))
	tv.global_transform = Transform3D(b.scaled(Vector3.ONE * TV_SCALE), g + Vector3.DOWN * TV_SCALE * 0.28)


## The television's screen, for shots.
func tv_screen() -> Vector3:
	if not is_instance_valid(tv):
		return shore.wake + shore.inland * TV_INLAND
	var s := tv.get_node_or_null(^"Screen") as Node3D
	return s.global_position if s else tv.global_position + Vector3.UP * TV_SCALE * 0.6
