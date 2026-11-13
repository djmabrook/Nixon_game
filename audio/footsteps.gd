extends Node
## The little man's footsteps, added for every room by the Sound autoload.
## A step lands every `stride` meters of ground covered, on whatever `Sound.surface` says
## (or `Sound.surface_resolver`, for rooms with several grounds). Rooms do nothing.

## Meters per step while walking and running. He is small; the world is not.
const WALK_STRIDE := 0.95
const RUN_STRIDE := 1.55

var _player: CharacterBody3D
var _travelled := 0.0
var _last_pos := Vector3.ZERO
var _was_on_floor := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func attach(player: CharacterBody3D) -> void:
	_player = player
	_last_pos = player.global_position
	_travelled = 0.0
	_was_on_floor = true


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var pos := _player.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	var on_floor := _player.is_on_floor()
	if on_floor and not _was_on_floor:
		_step(2.0)  # landing
		_travelled = 0.0
	_was_on_floor = on_floor
	if not on_floor or moved > 4.0:  # in the air, or teleported
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var running := speed > 7.0
	_travelled += moved
	var stride := RUN_STRIDE if running else WALK_STRIDE
	if _travelled >= stride:
		_travelled -= stride
		_step(2.5 if running else 0.0)


func _step(extra_db: float) -> void:
	if not Sound.footsteps_enabled:
		return
	var surface: StringName = Sound.surface
	if Sound.surface_resolver.is_valid():
		surface = Sound.surface_resolver.call(_player.global_position)
	var id := StringName("step_" + String(surface))
	if not Sound.has_sound(id):
		return
	Sound.play(id, Sound.footsteps_db + extra_db + _rng.randf_range(-1.5, 1.0), _rng.randf_range(0.94, 1.06), &"Near")
