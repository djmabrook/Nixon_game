@tool
extends Node3D
## A charred stake with an ember on top, standing at the outer end of a room's groove.
## Placeholder geometry: swap $Ember / $Post for the real model and keep the two exports.

@export var color := Color(1.0, 0.35, 0.1):
	set(v):
		color = v
		_apply()
## Unlit once the room is completed.
@export var lit := true:
	set(v):
		lit = v
		_apply()

var _phase := randf() * TAU


func _ready() -> void:
	_apply()


func _process(_delta: float) -> void:
	if not lit or Engine.is_editor_hint():
		return
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	$Light.light_energy = 1.4 + 0.35 * sin(t * 7.0) + 0.2 * sin(t * 13.0)
	$Ember.position.y = 1.05 + 0.04 * sin(t * 2.0)


func _apply() -> void:
	if not is_node_ready():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3) if lit else Color(0.12, 0.1, 0.1)
	mat.emission_enabled = lit
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	$Ember.material_override = mat
	$Light.light_color = color
	$Light.visible = lit
