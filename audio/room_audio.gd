class_name RoomAudio
extends Node
## Drop one of these anywhere in a room scene to set how the room sounds.
## The Sound autoload finds it when the room is entered and applies it. See audio/AUDIO.md.

## The region's air: a bed id from res://audio/library (bed_hub_night, bed_lake, bed_checker,
## bed_grid, bed_mountain, bed_dawn) or empty for none.
@export var bed := &""
@export_range(-40.0, 6.0, 0.5) var bed_db := 0.0
## Footstep surface: sand, stone, tile, water or felt.
@export var surface := &"stone"
@export_range(-30.0, 6.0, 0.5) var footsteps_db := -9.0
## Multiplies how late far sounds arrive. 1 is physical; 1.5-2 makes giants feel further.
@export_range(0.0, 4.0, 0.05) var lateness := 1.0

@export_group("Space")
## Size of the space around the little man (Near bus reverb): 0 small, 1 vast.
@export_range(0.0, 1.0, 0.01) var near_room_size := 0.35
@export_range(0.0, 0.6, 0.01) var near_wet := 0.12
## How much the giants ring out (Far bus reverb).
@export_range(0.0, 1.0, 0.01) var far_room_size := 0.95
@export_range(0.0, 0.8, 0.01) var far_wet := 0.3


func apply() -> void:
	Sound.set_bed(bed, bed_db)
	Sound.surface = surface
	Sound.footsteps_db = footsteps_db
	Sound.lateness = lateness
	_set_reverb(&"Near", near_room_size, near_wet)
	_set_reverb(&"Far", far_room_size, far_wet)


static func _set_reverb(bus_name: StringName, size: float, wet: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectReverb:
			fx.room_size = size
			fx.wet = wet
