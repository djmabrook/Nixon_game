extends Room
## The spiral hub: a vast night beach where the sand sinks into a whirlpool.
##
## Scale (1 unit = 1 m): the crater is about a kilometre across. You arrive on the shore,
## tiny, facing a 120 m dune ridge that fills the horizon, with a column of embers rising
## behind it. Top the ridge and the camera pulls back over the crater (RimVista): a
## slate-grey whirlpool sinking 180 m to a stadium-sized glowing pit. Far landmarks
## (Landmarks node) sit on the horizon as switchable layers.
##
## Every room found under rooms/ gets one glowing groove (an "arm") that starts on the
## beach, climbs the dune and spirals down the crater to its own slice of the pit's rim.
## Walking with a groove, the sand carries you; once you have ridden a groove to the
## bottom it is a fast slide from then on. Step into the pit and the sand swallows
## the little man into that room. Coming back, he is set down a little way up his
## room's groove (a RoomSpawn named after the room id).
##
## Nothing here is a list of rooms: add a folder under rooms/ and a new groove appears.
## Completed rooms (Game.is_completed) keep their groove but its glow goes out.

## The pit: a flat, stadium-sized disc at the bottom of the crater. All of it swallows.
@export var pit_radius := 40.0
## How fast the grooves wind (radians per meter outward). 0.0102 is about 1.3 turns.
@export var arm_winding := 0.0102
## The arm whose outer end sits nearest the arrival spot.
@export var first_arm_outer_angle := deg_to_rad(45.0)
## Outer end of the grooves, out on the beach (where the ember beacons stand).
@export var arm_outer_radius := 905.0
## How far up its groove the player reappears when coming back from a room.
@export var return_distance := 25.0

@export_group("Feel")
## Extra speed when walking with a groove toward the pit, the first time down it.
@export var groove_carry := 8.0
## Once you have ridden a groove all the way down, it becomes a slide this fast.
@export var slide_speed := 70.0
## Pull toward the pit (m/s at the rim, fading out by `pull_radius`).
## Keep pull_radius inside the return spots (pit_radius + return_distance).
@export var pull_strength := 9.0
@export var pull_radius := 60.0
## Sideways swirl added to the pull.
@export var swirl_strength := 6.0
## Seconds after arriving before the pull starts (it then ramps in over the same time).
@export var arrival_grace := 2.5
## Length of the sinking sequence before the room loads.
@export var sink_time := 3.0

@export_group("Camera framing")
## Orbit distance (m) and FOV by zone. The camera pulls back on the ridge and over the
## pit so the little man shrinks against the whirlpool, and closes in on the beach.
@export var beach_distance := 9.0
@export var ridge_distance := 26.0
@export var crater_distance := 16.0
@export var pit_distance := 34.0
@export var beach_fov := 55.0
@export var ridge_fov := 48.0
@export var slide_fov := 72.0

const STAKE_SCENE := preload("res://hub/props/ember_stake.tscn")
const BEACON_SCALE := 30.0
const RIDDEN_META := &"hub_ridden_grooves"
const InkState := preload("res://hub/hub_story.gd")

var _ids: Array[StringName] = []
var _arm_angles: PackedFloat32Array = []
var _sinking := false
var _focus := 0.0
var _pull_grace := 0.0
var _sliding := 0.0
var _lowest_r_on := {}   # arm index -> lowest radius reached this visit
var _max_r_on := {}      # arm index -> highest radius reached this visit
var _arm_colors: Array[Color] = []
var _arm_reach: Array[float] = []
var _open: Array[bool] = []
var _stakes: Array = []
var _room_inks := {}   # room id -> the ink it gives

@onready var _sand: StaticBody3D = $SandVortex
@onready var _vortex: RoomExit = $Vortex
@onready var _pit_light: OmniLight3D = $PitGlow
@onready var _footprints: Node3D = $Footprints
@onready var _focus_point: Node3D = $Vortex/FocusPoint
@onready var _sand_mat: ShaderMaterial = _sand.material


func _ready() -> void:
	_ids = Game.list_rooms()
	# Alphabetical by name, so each room keeps the same groove from run to run
	# (StringName arrays don't sort alphabetically on their own).
	_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var n := _ids.size()
	# The locked (ultraviolet) groove's outer end points at the Watcher's mountain;
	# the others share the circle evenly with it.
	for id in _ids:
		_room_inks[id] = _read_gives_ink(id)
	var outer_angle := first_arm_outer_angle
	var locked := -1
	for i in n:
		if opens_with_eye(_ids[i]):
			locked = i
			break
	if locked >= 0:
		var to_mountain: Vector3 = $Landmarks.watcher_position()
		outer_angle = atan2(to_mountain.z, to_mountain.x) - TAU * float(locked) / float(n)
	var start_offset := outer_angle - arm_winding * (arm_outer_radius - pit_radius)
	for i in n:
		_arm_angles.append(wrapf(start_offset + TAU * float(i) / float(n), -PI, PI))

	_sand_mat.set_shader_parameter("arm_count", n)
	_sand_mat.set_shader_parameter("arm_offset", start_offset)
	_sand_mat.set_shader_parameter("arm_winding", arm_winding)
	_sand_mat.set_shader_parameter("arm_outer_radius", arm_outer_radius)
	_sand_mat.set_shader_parameter("pit_radius", pit_radius)
	_sand_mat.set_shader_parameter("crest_radius", _sand.crest_radius)
	_sand_mat.set_shader_parameter("vortex_radius", _sand.crest_radius)
	_arm_colors.resize(16)
	_arm_colors.fill(Color(0, 0, 0, 0))
	_arm_reach.resize(16)
	_arm_reach.fill(arm_outer_radius + 20.0)
	for i in mini(n, 16):
		var c := room_color(_ids[i])
		_arm_colors[i] = Color(c.r, c.g, c.b, 0.0)
		_open.append(not Game.is_room_locked(_ids[i]))
	refresh_arms()

	_vortex.room_ids = _ids
	_vortex.arm_angles = _arm_angles
	_vortex.open = _open
	_vortex.position = _sand.ground_point(Vector2.ZERO)
	(_vortex.get_node("CollisionShape3D").shape as CylinderShape3D).radius = pit_radius - 1.0
	_vortex.swallowed.connect(_on_swallowed)
	_pit_light.position = _vortex.position + Vector3.UP * 30.0
	focus_target = _focus_point
	_build_rim_vista()

	for i in n:
		_add_arm(i)
	var start: Node3D = $from_start
	start.position = _sand.ground_point(Vector2(start.position.x, start.position.z))
	# Anchors for the opening and ending sequences (story/), stood on the sand.
	for anchor in $StoryAnchors.get_children():
		anchor.position = _sand.ground_point(Vector2(anchor.position.x, anchor.position.z))
	# The hub's television sits half-buried at first_tv; it droops a third per ink.
	var tv: Node3D = $WatchingSet
	var tv_spot: Node3D = $StoryAnchors/first_tv
	tv.position = tv_spot.position + Vector3.DOWN * 1.2


## A stable, saturated color per room id, so a room keeps its color as rooms are added.
## Rooms that give an ink use that ink's colour; the mountain is ultraviolet.
func room_color(id: StringName) -> Color:
	var ink: StringName = _room_inks.get(id, &"")
	if ink != &"" or opens_with_eye(id):
		return InkState.ink_color(ink)
	var h := float(hash(String(id)) % 997) / 997.0
	return Color.from_hsv(h, 0.75, 1.0)


# --- Grooves, for the ink state (hub_story.gd) and the story sequences ----------

func room_count() -> int:
	return _ids.size()


func room_at(i: int) -> StringName:
	return _ids[i]


func arm_index(room_id: StringName) -> int:
	return _ids.find(room_id)


## The ink a room gives when mended (its root's gives_ink), or &"".
func room_ink(room_id: StringName) -> StringName:
	return _room_inks.get(room_id, &"")


func arm_for_ink(ink: StringName) -> int:
	for i in _ids.size():
		if _room_inks.get(_ids[i], &"") == ink:
			return i
	return -1


## A room that needs all three inks (the mountain) opens with the eye, and its groove
## points at the Watcher.
func opens_with_eye(room_id: StringName) -> bool:
	return Game.required_inks_for(room_id).size() >= Game.INKS.size()


func _read_gives_ink(room_id: StringName) -> StringName:
	var state := (load(Game.room_path(room_id)) as PackedScene).get_state()
	for k in state.get_node_property_count(0):
		if state.get_node_property_name(0, k) == &"gives_ink":
			return StringName(state.get_node_property_value(0, k))
	return &""


func room_open(room_id: StringName) -> bool:
	var i := _ids.find(room_id)
	return i >= 0 and i < _open.size() and _open[i]


## How far the room's ink has filled its groove (0 dry .. 1 full to the beacon).
func set_arm_fill(i: int, fill: float) -> void:
	if i >= 0 and i < 16:
		_arm_colors[i].a = fill


## How far out (m) the groove is drawn. 0 hides a locked groove.
func set_arm_reach(i: int, reach: float) -> void:
	if i >= 0 and i < 16:
		_arm_reach[i] = reach


func refresh_arms() -> void:
	_sand_mat.set_shader_parameter("arm_colors", _arm_colors)
	_sand_mat.set_shader_parameter("arm_reach", _arm_reach)


## Open or close a groove: its pit slice leads to its room and its beacon stands.
func set_arm_open(i: int, on: bool) -> void:
	if i < 0 or i >= _open.size():
		return
	_open[i] = on
	_vortex.open = _open
	for s in _stakes:
		if s.get_meta("room_id") == _ids[i]:
			s.visible = on


func stakes() -> Array:
	return _stakes


## The dawn state, for the ending: sunrise, full colour, the Watcher's lights out.
func set_dawn(on: bool) -> void:
	$InkState.dawn_override = 1 if on else 0
	$InkState.apply_static()


## Angle (atan2(z, x)) of arm `i` at distance `r` from the center.
func arm_angle(i: int, r: float) -> float:
	return _arm_angles[i] + arm_winding * (r - pit_radius)


## Point on arm `i` at distance `r` from the center, standing on the sand.
func arm_point(i: int, r: float) -> Vector3:
	var a := arm_angle(i, r)
	return _sand.ground_point(Vector2(cos(a), sin(a)) * r)


func _add_arm(i: int) -> void:
	var id := _ids[i]
	# A towering ember beacon at the outer end of the groove, in the room's color.
	var stake: Node3D = STAKE_SCENE.instantiate()
	stake.name = "Beacon_%s" % id
	add_child(stake)
	stake.position = arm_point(i, arm_outer_radius + 3.0)
	stake.scale = Vector3.ONE * BEACON_SCALE
	stake.set("light_range", 140.0)
	stake.set("color", room_color(id))
	stake.set("lit", false)   # hub_story.gd lights them when ember comes home
	stake.set_meta("room_id", id)
	stake.visible = _open[i] if i < _open.size() else true
	_stakes.append(stake)

	# Return spot: a little way up the groove, facing out of the pit.
	var spawn := RoomSpawn.new()
	spawn.name = String(id)
	add_child(spawn)
	var r := pit_radius + return_distance
	spawn.position = arm_point(i, r)
	var ahead := arm_point(i, r + 1.0)
	ahead.y = spawn.position.y
	spawn.look_at(ahead, Vector3.UP)


func _on_room_entered(_spawn: StringName) -> void:
	var p := Game.player
	# A faint warm glow around him so he never disappears on the night sand.
	var lamp := OmniLight3D.new()
	lamp.name = "HubLamp"
	lamp.light_color = Color(1.0, 0.7, 0.5)
	lamp.light_energy = 1.2
	lamp.omni_range = 7.0
	lamp.position = Vector3.UP * 2.2
	p.add_child(lamp)
	var cam := Game.camera
	if cam:
		cam.distance = _distance_for(_radius_of(p.global_position))
		cam.snap_to_target()
	# Hold him still while the fade clears, then let the sand pull only after a moment,
	# so coming back out of a room never drags you straight back in.
	p.set_physics_process(false)
	_pull_grace = arrival_grace
	_lowest_r_on.clear()
	_max_r_on.clear()
	_footprints.call("track", p)
	# Arriving with an ink plants it now; the planting plays once the fade clears.
	if Game.carried != &"":
		Game.bring_home()
	$InkState.play_pending.call_deferred()


func _on_travel_done() -> void:
	if is_instance_valid(Game.player) and not _sinking:
		Game.player.set_physics_process(true)


func _radius_of(world: Vector3) -> float:
	var l := to_local(world)
	return Vector2(l.x, l.z).length()


## Orbit distance for a distance from the center: close on the beach, far back on the
## ridge for the reveal, closer on the crater wall, far again over the pit.
func _distance_for(r: float) -> float:
	var crest: float = _sand.crest_radius
	var foot: float = _sand.dune_foot_radius
	if r >= crest:
		return lerpf(beach_distance, ridge_distance, 1.0 - smoothstep(crest, foot, r))
	var t_rim := smoothstep(crest * 0.75, crest, r)
	var t_pit := 1.0 - smoothstep(pit_radius, pit_radius + 140.0, r)
	return lerpf(lerpf(crater_distance, ridge_distance, t_rim), pit_distance, t_pit)


func _fov_for(r: float) -> float:
	var crest: float = _sand.crest_radius
	var near_ridge := 1.0 - smoothstep(0.0, 120.0, absf(r - crest))
	return lerpf(beach_fov, ridge_fov, near_ridge)


## Ridden grooves live on Game (as metadata) so they survive leaving the hub.
func _is_ridden(id: StringName) -> bool:
	var d: Dictionary = Game.get_meta(RIDDEN_META, {})
	return d.has(id)


func _mark_ridden(id: StringName) -> void:
	var d: Dictionary = Game.get_meta(RIDDEN_META, {})
	d[id] = true
	Game.set_meta(RIDDEN_META, d)


## A ring of trigger boxes along the ridge: the first time you top it, the camera
## pulls far back over the crater and looks down into the pit.
func _build_rim_vista() -> void:
	var zone := VistaZone.new()
	zone.name = "RimVista"
	zone.look_target = _focus_point
	zone.pull_back = 260.0
	zone.hold = 4.0
	zone.blend = 3.0
	add_child(zone)
	var crest: float = _sand.crest_radius
	var count := 48
	for i in count:
		var a := TAU * float(i) / count
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * crest / count + 2.0, 16.0, 30.0)
		col.shape = box
		zone.add_child(col)
		col.position = _sand.ground_point(Vector2(cos(a), sin(a)) * (crest + 6.0)) + Vector3.UP * 4.0
		col.rotation.y = -a + PI * 0.5


func _physics_process(delta: float) -> void:
	var p := Game.player
	if _sinking or Game.is_travelling() or not is_instance_valid(p) or p.get_parent() != self:
		return
	if not p.is_physics_processing():
		_on_travel_done()
	_pull_grace = maxf(_pull_grace - delta, 0.0)
	var grace_t := 1.0 - _pull_grace / maxf(arrival_grace, 0.001)
	var local := to_local(p.global_position)
	var flat := Vector2(local.x, local.z)
	var r := flat.length()
	var drift := Vector2.ZERO

	# The pit drags at your feet near the rim: strong close in, never inescapable.
	if r < pull_radius and r > 0.01:
		var t := 1.0 - smoothstep(pit_radius, pull_radius, r)
		var inward := -flat / r
		var tangent := Vector2(-inward.y, inward.x)
		drift += (inward * pull_strength + tangent * swirl_strength) * t * grace_t

	# Walking with a groove, the sand carries you down it. A groove you have already
	# ridden to the bottom is a slide.
	var arm := _arm_under(p.global_position)
	var slide_t := 0.0
	if arm >= 0:
		_lowest_r_on[arm] = minf(_lowest_r_on.get(arm, INF), r)
		_max_r_on[arm] = maxf(_max_r_on.get(arm, 0.0), r)
		if p.is_walking:
			var down := _arm_inward(arm, r)
			var along := Vector2(p.velocity.x, p.velocity.z).normalized().dot(down)
			if along > 0.2:
				var ridden := _is_ridden(_ids[arm])
				drift += down * (slide_speed if ridden else groove_carry) * along
				slide_t = along if ridden else 0.0
	_sliding = lerpf(_sliding, slide_t, 1.0 - exp(-4.0 * delta))

	if drift != Vector2.ZERO:
		# Follow the slope so fast moves hug the sand instead of launching off it.
		var step := drift * delta
		var next_r := (flat + step).length()
		var dy: float = _sand.height_at(next_r) - _sand.height_at(r)
		p.move_and_collide(Vector3(step.x, minf(dy, 0.0) - 0.02, step.y))


## Unit direction along arm `i` toward the pit, at radius `r` (xz plane).
func _arm_inward(i: int, r: float) -> Vector2:
	var a := arm_angle(i, r)
	var d := Vector2(cos(a) - r * arm_winding * sin(a), sin(a) + r * arm_winding * cos(a))
	return -d.normalized()


func _process(delta: float) -> void:
	if _sinking:
		return
	var t_glow := Time.get_ticks_msec() / 1000.0
	_pit_light.light_energy = 40.0 + 8.0 * sin(t_glow * 2.0) + 3.0 * sin(t_glow * 5.3)
	var p := Game.player
	if not is_instance_valid(p) or not is_instance_valid(Game.camera) or Game.is_travelling():
		return
	var r := _radius_of(p.global_position)
	var cam := Game.camera
	if not cam.is_in_shot():
		var k := 1.0 - exp(-1.2 * delta)
		cam.distance = lerpf(cam.distance, _distance_for(r) * (1.0 + 0.6 * _sliding), k)
		cam.set_base_fov(lerpf(cam.fov, lerpf(_fov_for(r), slide_fov, _sliding), k))
	# Light up the groove you are standing on.
	var arm := _arm_under(p.global_position)
	_focus = lerpf(_focus, 1.0 if arm >= 0 else 0.0, 1.0 - exp(-6.0 * delta))
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
	if r < pit_radius or r > arm_outer_radius:
		return -1
	var theta := atan2(local.z, local.x)
	var u := (theta - _arm_angles[0] - arm_winding * (r - pit_radius)) * n / TAU
	var nearest := roundf(u)
	var d := absf(u - nearest) * TAU / n * r
	if d > 10.0:
		return -1
	var idx := posmod(int(nearest), n)
	if idx < _open.size() and not _open[idx]:
		return -1
	return idx


## The sand takes him: he spirals down into the pit, shrinking, then the room loads.
func _on_swallowed(p: Player, room_id: StringName) -> void:
	_sinking = true
	# Came down this room's groove from the rim? Next time it's a slide.
	var i := _ids.find(room_id)
	if i >= 0 and _lowest_r_on.has(i) and _arm_reached_from_rim(i):
		_mark_ridden(room_id)
	p.controls_enabled = false
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)   # the tween drives him now; no gravity fighting it
	var center := _vortex.global_position
	var start := p.global_position - center
	var start_r := Vector2(start.x, start.z).length()
	var start_a := atan2(start.z, start.x)
	var start_y := start.y
	var visual: Node3D = p.visual
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		var e := t * t
		var a := start_a + e * TAU * 1.5
		var rr := start_r * (1.0 - e)
		p.global_position = center + Vector3(cos(a) * rr, start_y - 12.0 * e, sin(a) * rr)
		visual.rotation.y += 0.35 * (1.0 + 4.0 * t)
	, 0.0, 1.0, sink_time)
	tw.tween_property(visual, "scale", Vector3(0.15, 0.15, 0.15), sink_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_pit_light, "light_energy", 160.0, sink_time)
	if is_instance_valid(Game.camera):
		tw.tween_property(Game.camera, "distance", pit_distance * 1.8, sink_time).set_ease(Tween.EASE_OUT)
	await tw.finished
	_vortex.go()


## True once the little man has been on arm `i` up near the rim during this visit,
## i.e. he walked (most of) the groove rather than cutting across the pit floor.
func _arm_reached_from_rim(i: int) -> bool:
	return _max_r_on.get(i, 0.0) > _sand.crest_radius * 0.6
