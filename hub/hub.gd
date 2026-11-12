extends Room
## The spiral hub: a night beach where the sand sinks into a vortex.
##
## Every room found under rooms/ gets one groove (an "arm") in the sand that spirals
## inward to its own slice of the pit's rim. Walk down a groove, step into the pit,
## and the sand swallows the little man into that room. Coming back, he is spat out
## a few steps up his room's groove (a RoomSpawn named after the room id).
##
## Nothing here is a list of rooms: add a folder under rooms/ and a new groove appears.
## Completed rooms (Game.is_completed) keep their groove but its glow goes out.

## Where the grooves meet the rim, and how fast they wind (radians per unit outward).
@export var arm_winding := 0.32
## The arm whose outer end sits by the arrival spot, so the first groove is under your feet.
@export var first_arm_outer_angle := deg_to_rad(45.0)
## Outer end of the grooves (where the ember stakes stand).
@export var arm_outer_radius := 19.5
## How far up its groove the player reappears when coming back from a room.
@export var return_distance := 2.6

@export_group("Feel")
## Pull toward the pit (units/second at the rim, fading out by `pull_radius`).
## Keep pull_radius inside the return spots (pit + return_distance) so standing still is safe.
@export var pull_strength := 1.1
@export var pull_radius := 4.0
## Sideways swirl added to the pull.
@export var swirl_strength := 0.7
## Seconds after arriving before the pull starts (it then ramps in over the same time).
@export var arrival_grace := 2.5
## The camera tightens as you near the pit.
@export var near_camera_size := 11.5
## Length of the sinking sequence before the room loads.
@export var sink_time := 1.3

const STAKE_SCENE := preload("res://hub/props/ember_stake.tscn")
const PIT_RADIUS := 1.6

var _ids: Array[StringName] = []
var _arm_angles: PackedFloat32Array = []
var _sinking := false
var _far_camera_size := 0.0
var _focus := 0.0
var _pull_grace := 0.0

@onready var _sand: StaticBody3D = $SandVortex
@onready var _vortex: RoomExit = $Vortex
@onready var _pit_light: OmniLight3D = $PitGlow
@onready var _sand_mat: ShaderMaterial = _sand.material


func _ready() -> void:
	_far_camera_size = camera_size
	_ids = Game.list_rooms()
	# Alphabetical by name, so each room keeps the same groove from run to run
	# (StringName arrays don't sort alphabetically on their own).
	_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var n := _ids.size()
	var start_offset := first_arm_outer_angle - arm_winding * (arm_outer_radius - PIT_RADIUS)
	for i in n:
		_arm_angles.append(wrapf(start_offset + TAU * float(i) / float(n), -PI, PI))

	_sand_mat.set_shader_parameter("arm_count", n)
	_sand_mat.set_shader_parameter("arm_offset", start_offset)
	_sand_mat.set_shader_parameter("arm_winding", arm_winding)
	_sand_mat.set_shader_parameter("pit_radius", PIT_RADIUS)
	var colors: Array[Vector4] = []
	colors.resize(16)
	colors.fill(Vector4.ZERO)
	for i in mini(n, 16):
		var c := room_color(_ids[i])
		colors[i] = Vector4(c.r, c.g, c.b, 0.0 if Game.is_completed(_ids[i]) else 1.0)
	_sand_mat.set_shader_parameter("arm_colors", colors)

	_vortex.room_ids = _ids
	_vortex.arm_angles = _arm_angles
	_vortex.position = _sand.ground_point(Vector2.ZERO)
	_vortex.swallowed.connect(_on_swallowed)

	for i in n:
		_add_arm(i)
	var start: Node3D = $from_start
	start.position = _sand.ground_point(Vector2(start.position.x, start.position.z))


## A stable, saturated color per room id, so a room keeps its color as rooms are added.
static func room_color(id: StringName) -> Color:
	var h := float(hash(String(id)) % 997) / 997.0
	return Color.from_hsv(h, 0.75, 1.0)


## Point on arm `i` at distance `r` from the center, standing on the sand.
func arm_point(i: int, r: float) -> Vector3:
	var a := _arm_angles[i] + arm_winding * (r - PIT_RADIUS)
	return _sand.ground_point(Vector2(cos(a), sin(a)) * r)


func _add_arm(i: int) -> void:
	var id := _ids[i]
	# Ember stake at the outer end of the groove: the room's color, dark once completed.
	var stake: Node3D = STAKE_SCENE.instantiate()
	stake.name = "Stake_%s" % id
	add_child(stake)
	stake.position = arm_point(i, arm_outer_radius + 0.6)
	stake.set("color", room_color(id))
	stake.set("lit", not Game.is_completed(id))

	# Return spot: a few steps up the groove, facing out of the pit.
	var spawn := RoomSpawn.new()
	spawn.name = String(id)
	add_child(spawn)
	var r := PIT_RADIUS + return_distance
	spawn.position = arm_point(i, r)
	var ahead := arm_point(i, r + 1.0)
	ahead.y = spawn.position.y
	spawn.look_at(ahead, Vector3.UP)


func _on_room_entered(_spawn: StringName) -> void:
	_far_camera_size = camera_size
	# Hold him still while the fade clears, then let the sand pull only after a moment,
	# so coming back out of a room never drags you straight back in.
	Game.player.set_physics_process(false)
	_pull_grace = arrival_grace


func _on_travel_done() -> void:
	if is_instance_valid(Game.player) and not _sinking:
		Game.player.set_physics_process(true)


func _physics_process(delta: float) -> void:
	var p := Game.player
	if _sinking or Game.is_travelling() or not is_instance_valid(p) or p.get_parent() != self:
		return
	if not p.is_physics_processing():
		_on_travel_done()
	_pull_grace = maxf(_pull_grace - delta, 0.0)
	var grace_t := 1.0 - _pull_grace / maxf(arrival_grace, 0.001)
	var flat := Vector2(p.global_position.x - _vortex.global_position.x, p.global_position.z - _vortex.global_position.z)
	var r := flat.length()
	# The pit drags at your feet: gentle far out, strong near the rim, never inescapable.
	if r < pull_radius and r > 0.01:
		var t := 1.0 - smoothstep(PIT_RADIUS, pull_radius, r)
		var inward := -flat / r
		var tangent := Vector2(-inward.y, inward.x)
		var drift := (inward * pull_strength + tangent * swirl_strength) * t * grace_t * delta
		p.move_and_collide(Vector3(drift.x, 0.0, drift.y))


func _process(delta: float) -> void:
	var p := Game.player
	if _sinking:
		return
	var t_glow := Time.get_ticks_msec() / 1000.0
	_pit_light.light_energy = 2.2 + 0.5 * sin(t_glow * 2.0) + 0.2 * sin(t_glow * 5.3)
	if not is_instance_valid(p) or not is_instance_valid(Game.camera):
		return
	var r := Vector2(p.global_position.x, p.global_position.z).distance_to(
		Vector2(_vortex.global_position.x, _vortex.global_position.z))
	# Tighten the frame as the pit gets close.
	var near_t := 1.0 - smoothstep(PIT_RADIUS + 0.5, 10.0, r)
	var goal := lerpf(_far_camera_size, near_camera_size, near_t)
	Game.camera.size = lerpf(Game.camera.size, goal, 1.0 - exp(-3.0 * delta))
	# Light up the groove you are standing on.
	var arm := _arm_under(p.global_position)
	var target_focus := 1.0 if arm >= 0 else 0.0
	_focus = lerpf(_focus, target_focus, 1.0 - exp(-6.0 * delta))
	if arm >= 0:
		_sand_mat.set_shader_parameter("focus_arm", arm)
	_sand_mat.set_shader_parameter("focus_amount", _focus)


## Index of the groove under a world point, or -1.
func _arm_under(world: Vector3) -> int:
	var n := _ids.size()
	if n == 0:
		return -1
	var local := to_local(world)
	var r := Vector2(local.x, local.z).length()
	if r < PIT_RADIUS or r > arm_outer_radius + 1.0:
		return -1
	var theta := atan2(local.z, local.x)
	var u := (theta - _arm_angles[0] - arm_winding * (r - PIT_RADIUS)) * n / TAU
	var nearest := roundf(u)
	var d := absf(u - nearest) * TAU / n * r
	if d > 0.6:
		return -1
	return posmod(int(nearest), n)


## The sand takes him: he spirals down into the pit, shrinking, then the room loads.
func _on_swallowed(p: Player, _room_id: StringName) -> void:
	_sinking = true
	p.controls_enabled = false
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)   # the tween drives him now; no gravity fighting it
	var center := _vortex.global_position
	var start := p.global_position - center
	var start_r := Vector2(start.x, start.z).length()
	var start_a := atan2(start.z, start.x)
	var visual: Node3D = p.get_node("Visual")
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		var e := t * t
		var a := start_a + e * TAU * 1.25
		var rr := start_r * (1.0 - e)
		p.global_position = center + Vector3(cos(a) * rr, -1.4 * e, sin(a) * rr)
		visual.rotation.y += 0.35 * (1.0 + 4.0 * t)
	, 0.0, 1.0, sink_time)
	tw.tween_property(visual, "scale", Vector3(0.2, 0.2, 0.2), sink_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_pit_light, "light_energy", 7.0, sink_time)
	if is_instance_valid(Game.camera):
		tw.tween_property(Game.camera, "size", near_camera_size * 0.75, sink_time).set_ease(Tween.EASE_IN)
	await tw.finished
	_vortex.go()
