@tool
extends Node3D
## A charred stake with an ember on top. Scaled up by the hub into a towering beacon
## at the outer end of each room's groove, in that room's color.
## Placeholder geometry: swap $Ember / $Post for the real model and keep the exports.

@export var color := Color(1.0, 0.35, 0.1):
	set(v):
		color = v
		_apply()
## Unlit once the room is completed.
@export var lit := true:
	set(v):
		lit = v
		_apply()
## Light reach in world units (node scale doesn't scale lights).
@export var light_range := 3.5:
	set(v):
		light_range = v
		_apply()

var _phase := randf() * TAU


func _ready() -> void:
	_apply()


func _process(_delta: float) -> void:
	if not lit or Engine.is_editor_hint():
		return
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	var s := global_basis.get_scale().y
	$Light.light_energy = (1.4 + 0.35 * sin(t * 7.0) + 0.2 * sin(t * 13.0)) * sqrt(s)
	$Ember.position.y = 1.05 + 0.04 * sin(t * 2.0)


func _apply() -> void:
	if not is_node_ready():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3) if lit else Color(0.12, 0.1, 0.1)
	mat.emission_enabled = lit
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	$Ember.material_override = mat
	$Light.light_color = color
	$Light.omni_range = light_range
	$Light.visible = lit
