class_name Stray
extends Node3D
## The Stray: a lost arrow cursor, dog-sized, that adopts the little man.
##
## Drop res://companions/stray/stray.tscn into any room. It finds the player on its own,
## hops at his heel, runs ahead to point at StrayInterest markers, hides behind his legs
## near an awake StrayStare (a television with eyes) and curls up beside a sleeping one.
## Story code can take it over with the scripted calls below (arrive, walk_to, sniff_around,
## look_at_camera, cower, point_at, curl_up) and hand it back with release().
##
## It is a flat thing that lives on the screen: its bone face turns toward the camera and
## its tip points at things the way a cursor does, by where they are on screen.
## It has no ink of its own. When it points, the tip borrows the room's ink for one blink.

## Emitted when it reaches the spot it was moving to (walk_to and friends await this).
signal arrived
## Emitted when it clicks on something it is pointing at.
signal pointed(thing: Node3D)
## Emitted when its behaviour changes (see Mode).
signal mode_changed(new_mode: Mode)

enum Mode {
	FOLLOW,  ## Heeling: hops beside him, looks up at him, sniffs around when he dawdles.
	POINT,  ## Ran ahead and is pointing at something until he looks.
	COWER,  ## Hiding behind his legs from an awake stare.
	CURL,  ## Curled up by a sleeping stare.
	SNIFF,  ## Nosing about near him.
	LOST,  ## Glitching out and back in beside him (he got too far away).
	SCRIPTED,  ## Story code is driving it.
}

## Its own palette: bone and black. (Art direction: it is from the frame, not from any room.)
const BONE := Color("efe6d8")
const BLACK := Color("0d0b0a")
## Where the tip is in the model (the GLB is flat in XY with the tail tip at the origin).
const TIP_LOCAL := Vector2(-0.42, 0.551)
const TIP_ANGLE := 0.6513  # atan2(0.42, 0.551): the tip's lean from upright, in radians.
## The three inks (Game.INKS) as colours, from the art direction.
const INK_COLORS := {&"ember": Color("f0431e"), &"salmon": Color("f0787a"), &"crimson": Color("c8102e")}

const STRAY_SHADER := preload("res://companions/stray/stray.gdshader")
const RIPPLE_SHADER := preload("res://companions/stray/ripple.gdshader")

## Who it belongs to. Empty = it adopts the node in the "player" group on its own.
@export var target: Node3D
## Off = it only moves when story code tells it to.
@export var autonomous := true
## The ink the tip borrows for one blink when it points. Alpha 0 = nothing to borrow.
## With `ink_from_story` on, it is set for you: a room's own `gives_ink`, else the ink he
## carries, else (in the hub) the last ink brought home. The drained hub has none.
@export var ink := Color(0, 0, 0, 0)
@export var ink_from_story := true

@export_group("Movement")
## Fastest it can hop (m/s). The little man runs at 10.
@export var max_speed := 13.0
@export var acceleration := 38.0
## How far from his side it likes to walk.
@export var heel_distance := 1.4
## Further than this from him and it glitches out and reappears beside him.
@export var teleport_distance := 45.0
## Hop height at a walk (meters). Runs bound higher, idles hop lower.
@export var hop_height := 0.2

@export_group("Character")
## Runs ahead to point at StrayInterest markers.
@export var notices_things := true
## Seconds he must stand still before it looks up at him, sniffs about, and (rarely) spins.
@export var look_up_after := 3.0
@export var sniff_after := 10.0
@export var spin_after := 28.0
## Chance of the loading-spin joke per long idle. Keep it rare.
@export_range(0.0, 1.0) var spin_chance := 0.3

@export_group("Sound")
## It never vocalises (audio/AUDIO.md): its only sound is a cursor tick. It uses the Sound
## autoload's `cursor_tick` when there is one, else this stream, else a built-in synthesized tick.
@export var tick_sound: AudioStream
@export var volume_db := -6.0

var mode := Mode.FOLLOW

# Movement
var _vel := Vector3.ZERO
var _goal := Vector3.ZERO
var _has_goal := false
var _stop_radius := 0.3
var _speed_cap := 8.0
var _arrived_sent := true
var _hop := 0.0  # 0..1 through a hop; 0 means on the ground
var _side := 1.0  # which side of him it heels on (camera right = +1)

# Pose: goals and smoothed values
var _face := Vector3.BACK
var _face_goal := Vector3.BACK
var _mirror := 1.0  # scale.x of the model; passes through 0 when it flips, like paper turning
var _mirror_goal := 1.0
var _roll := 0.0
var _roll_goal := 0.0
var _roll_rate := 10.0
var _lie := 0.0
var _lie_goal := 0.0
var _crouch := 0.0
var _crouch_goal := 0.0
var _tremble := 0.0
var _tremble_goal := 0.0
var _spin := 0.0  # extra roll for one-off gags (loading spin, shaking off)
var _sq := 0.0  # squash spring (negative = squashed)
var _sq_v := 0.0
var _aim_dir := Vector3.ZERO
var _aim_w := 0.0
var _aim_w_goal := 0.0
var _breathe := 0.0
var _t := 0.0

# Brain
var _target_prev := Vector3.ZERO
var _target_speed := 0.0
var _idle := 0.0
var _mode_t := 0.0
var _scripted := false
var _stare: StrayStare
var _stare_pos := Vector3.ZERO
var _edge_stare: StrayStare
var _interest: Node3D
var _interest_pos := Vector3.ZERO
var _interest_marker: StrayInterest
var _point_limit := 8.0
var _clicked := false
var _ack := 0.0
var _scan_t := 0.0
var _looked_up := false
var _spun := false
var _sniffs_left := 0
var _sniff_center := Vector3.ZERO
var _sniff_hold := 0.0
var _curl_phase := 0
var _curl_spot := Vector3.ZERO
var _peek_t := 0.0
var _peek_side := 1.0
var _glance_t := 0.0
var _busy := false  # a one-off gag is playing; don't start another
var _placed := false

# Nodes
var _rig: Node3D
var _squash: Node3D
var _mesh: MeshInstance3D
var _mats: Array[ShaderMaterial] = []  # [rim, face]
var _ghosts: Array[MeshInstance3D] = []
var _ghost_mats: Array[ShaderMaterial] = []
var _trail: Array[Transform3D] = []
var _trail_t := 0.0
var _trail_amount := 0.0
var _ripple: MeshInstance3D
var _ripple_mat: ShaderMaterial
var _dust: CPUParticles3D
var _feet: AudioStreamPlayer3D
var _builtin_tick: AudioStream
var _rng := RandomNumberGenerator.new()

signal _sniff_finished
signal _look_finished


## The Stray in this scene tree, if there is one.
static func find_in(tree: SceneTree) -> Stray:
	return tree.get_first_node_in_group(&"stray") as Stray


func _ready() -> void:
	add_to_group(&"stray")
	_rng.seed = hash(get_path())
	_rig = $Rig
	_squash = $Rig/Squash
	_mesh = _find_mesh($Rig/Squash)
	_build_materials()
	_build_ghosts()
	_build_ripple()
	_build_dust()
	_build_sounds()
	_face = Vector3.BACK
	_face_goal = _face


# ---------------------------------------------------------------- scripted API


## Go back to being its own dog, heeling `new_target` (default: the player).
func follow(new_target: Node3D = null) -> void:
	if new_target:
		target = new_target
	release()


## Hand control back after any of the scripted calls.
func release() -> void:
	_scripted = false
	_aim_w_goal = 0.0
	_lie_goal = 0.0
	_enter(Mode.FOLLOW)


## Run in from `from` (off screen), stop near `to`, and look up at whoever it found.
func arrive(from: Vector3, to: Vector3) -> void:
	_scripted = true
	_enter(Mode.SCRIPTED)
	global_position = from
	_snap_to_ground(true)
	_vel = Vector3.ZERO
	_placed = true
	await walk_to(to, max_speed * 0.85)
	_skid()
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(target):
		_glance_t = 1.4


## Hop to `pos` and return when it gets there.
func walk_to(pos: Vector3, speed := 7.0) -> void:
	_scripted = true
	if mode != Mode.SCRIPTED:
		_enter(Mode.SCRIPTED)
	_set_goal(pos, 0.25, speed)
	await arrived


## Nose about around `around` (a Node3D or a Vector3; default: where it stands).
func sniff_around(around: Variant = null, count := 3) -> void:
	_scripted = true
	var center := global_position
	if around is Node3D:
		center = (around as Node3D).global_position
	elif around is Vector3:
		center = around
	_start_sniff(center, count)
	await _sniff_finished
	_enter(Mode.SCRIPTED)


## Turn and point its tip straight at the camera: the one time it looks at the player.
func look_at_camera(hold := 1.6) -> void:
	_scripted = true
	_enter(Mode.SCRIPTED)
	_has_goal = false
	_aim_w_goal = 1.0
	get_tree().create_timer(0.35).timeout.connect(blink)
	await get_tree().create_timer(0.5 + hold).timeout
	_aim_w_goal = 0.0
	await get_tree().create_timer(0.4).timeout
	_look_finished.emit()


## Hide behind the little man from something at `near` until release().
func cower(near: Vector3) -> void:
	_scripted = true
	_stare = null
	_stare_pos = near
	_enter(Mode.COWER)


## Point at `thing` (a Node3D or a Vector3) for `duration` seconds, then release().
func point_at(thing: Variant, duration := 3.0) -> void:
	_scripted = true
	_interest_marker = null
	_interest = thing as Node3D if thing is Node3D else null
	_interest_pos = thing if thing is Vector3 else Vector3.ZERO
	_point_limit = duration
	_enter(Mode.POINT)
	while mode == Mode.POINT:
		await get_tree().process_frame
	_scripted = false


## Curl up at `spot` until release().
func curl_up(spot: Vector3) -> void:
	_scripted = true
	_stare = null
	_curl_spot = spot
	_enter(Mode.CURL)


## A cursor blink. The tip flashes the room's ink, if there is one.
func blink() -> void:
	var face := _mats[1]
	var tw := create_tween()
	tw.tween_callback(func(): face.set_shader_parameter(&"face_off", 1.0))
	tw.tween_interval(0.05)
	tw.tween_callback(func():
		face.set_shader_parameter(&"face_off", 0.0)
		face.set_shader_parameter(&"ink_flash", 1.0 if ink.a > 0.0 else 0.0))
	tw.tween_interval(0.11)
	tw.tween_callback(func(): face.set_shader_parameter(&"ink_flash", 0.0))


## Change the borrowed ink (when an ink comes home to the hub, say). Alpha 0 = none.
func set_ink(color: Color) -> void:
	ink = color
	for m in _mats + _ghost_mats:
		m.set_shader_parameter(&"ink", ink)


# ---------------------------------------------------------------- main loop


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	_mode_t += delta
	_acquire_target()
	if is_instance_valid(target):
		_track_target(delta)
		if autonomous and not _scripted:
			_think(delta)
		_run_mode(delta)
	_move(delta)
	_pose(delta)
	_update_trail(delta)


func _acquire_target() -> void:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group(&"player") as Node3D
		if not target:
			return
		_target_prev = target.global_position
		if ink_from_story:
			_adopt_story_ink()
			if not Game.ink_home.is_connected(_on_story_ink):
				Game.ink_home.connect(_on_story_ink)
				Game.carried_changed.connect(_on_story_ink)
		_adopt_watching_sets()
	if not _placed:
		_placed = true
		global_position = _heel_spot()
		_snap_to_ground(true)
		_trail.clear()


func _track_target(delta: float) -> void:
	var p := target.global_position
	var v := (p - _target_prev) / maxf(delta, 0.0001)
	v.y = 0.0
	_target_speed = lerpf(_target_speed, v.length(), 1.0 - exp(-10.0 * delta))
	_target_prev = p
	if _target_speed < 0.4:
		_idle += delta
	else:
		_idle = 0.0
		_looked_up = false
		_spun = false


# ---------------------------------------------------------------- brain


func _think(delta: float) -> void:
	if mode == Mode.LOST:
		return
	if _flat(global_position - target.global_position).length() > teleport_distance:
		_go_lost()
		return

	# The Watcher kind of stare: just turn thin.
	_edge_stare = _nearest_stare(true, StrayStare.Reaction.EDGE_ON, 1.0)

	var scary := _nearest_stare(true, StrayStare.Reaction.HIDE_BEHIND, 1.15 if mode == Mode.COWER else 1.0)
	if scary:
		if mode != Mode.COWER:
			if mode == Mode.CURL:
				_startle()
			_stare = scary
			_enter(Mode.COWER)
		_stare = scary
		return
	if mode == Mode.COWER:
		_relief()
		_enter(Mode.FOLLOW)
		return

	if mode == Mode.POINT:
		return
	if mode == Mode.CURL:
		if _stare and _flat(target.global_position - _curl_spot).length() > _stare.rest_radius + 3.0:
			_wake()
		return

	var sleepy := _nearest_stare(false, -1, 1.0)
	if sleepy and _idle > 1.5:
		_stare = sleepy
		_curl_spot = sleepy.curl_spot(target.global_position)
		_enter(Mode.CURL)
		return

	_scan_t -= delta
	if notices_things and _scan_t <= 0.0 and mode in [Mode.FOLLOW, Mode.SNIFF]:
		_scan_t = 0.4
		var it := _best_interest()
		if it:
			_interest_marker = it
			_interest = it
			_point_limit = 8.0
			it.mark_pointed(_now())
			_enter(Mode.POINT)
			return

	if mode == Mode.SNIFF and _target_speed > 1.0:
		_enter(Mode.FOLLOW)
	elif mode == Mode.FOLLOW and _idle > sniff_after and _mode_t > 4.0:
		_start_sniff(target.global_position, 3)
	elif mode == Mode.FOLLOW and _idle > spin_after and not _spun:
		_spun = true
		if _rng.randf() < spin_chance:
			_loading_spin()


func _enter(new_mode: Mode) -> void:
	var old := mode
	mode = new_mode
	_mode_t = 0.0
	_crouch_goal = 0.0
	_tremble_goal = 0.0
	if old == Mode.CURL and new_mode != Mode.CURL:
		_lie_goal = 0.0
	match new_mode:
		Mode.POINT:
			_clicked = false
			_ack = 0.0
		Mode.CURL:
			_curl_phase = 0
			_set_goal(_curl_spot, 0.15, 6.0)
		Mode.COWER:
			_peek_t = 1.5
	if old != new_mode:
		mode_changed.emit(new_mode)


func _run_mode(delta: float) -> void:
	_glance_t -= delta
	_face_goal = _toward_camera()
	match mode:
		Mode.FOLLOW:
			_do_follow(delta)
		Mode.POINT:
			_do_point(delta)
		Mode.COWER:
			_do_cower(delta)
		Mode.CURL:
			_do_curl(delta)
		Mode.SNIFF:
			_do_sniff(delta)
		Mode.SCRIPTED:
			_lean_or_rest()
		Mode.LOST:
			pass
	if is_instance_valid(_edge_stare) and mode != Mode.CURL and mode != Mode.COWER:
		_face_goal = _edge_on_to(_edge_stare.global_position)
		_crouch_goal = maxf(_crouch_goal, 0.15)
	if _glance_t > 0.0 and mode != Mode.CURL:
		_tip_toward(target.global_position + Vector3.UP * 1.6)
	if _aim_w_goal > 0.0:
		var cam := _cam()
		if cam:
			_aim_dir = cam.global_position - (global_position + Vector3.UP * 0.1)


func _do_follow(_delta: float) -> void:
	var heel := _heel_spot()
	var moving := _target_speed > 0.6
	if moving or global_position.distance_to(heel) > 2.2 or not _has_goal:
		_set_goal(heel, 0.35, maxf(_target_speed * 1.3, 6.0))
	_lean_or_rest()
	if not moving and _idle > look_up_after and not _looked_up:
		_looked_up = true
		_glance_t = 1.3


func _do_point(delta: float) -> void:
	var where := _interest.global_position if is_instance_valid(_interest) else _interest_pos
	var from := target.global_position
	var dir := _flat(where - from)
	dir = dir.normalized() if dir.length() > 0.01 else -_cam_flat_z()
	var spot := from + dir * 2.4 + _cam_flat_x() * _side * 0.8
	_set_goal(spot, 0.3, max_speed)
	var reached := _flat(global_position - spot).length() < 0.6
	if not reached:
		_lean_or_rest()
		if _mode_t < 2.0:
			return
	_tip_toward(where)
	if not _clicked:
		_clicked = true
		_click()
		pointed.emit(_interest)
		_mode_t = 0.0
	# Eager little bounces, and a look back at him: "there, look".
	if fmod(_mode_t, 2.2) < delta and _mode_t > 1.0:
		_glance_t = 0.4
		_small_hop(0.6)
	_ack = _ack + delta if _is_centered(where) else 0.0
	if _mode_t > 1.4 and _ack > 0.5:
		_double_tick(0.0)
		_small_hop(1.0)
		get_tree().create_timer(0.28).timeout.connect(_small_hop.bind(0.7))
		if _interest_marker:
			_interest_marker.acknowledged.emit()
		_enter(Mode.SCRIPTED if _scripted else Mode.FOLLOW)
	elif _mode_t > _point_limit:
		_enter(Mode.SCRIPTED if _scripted else Mode.FOLLOW)


func _do_cower(delta: float) -> void:
	var s := _stare.global_position if is_instance_valid(_stare) else _stare_pos
	_stare_pos = s
	var p := target.global_position
	var away := _flat(p - s)
	away = away.normalized() if away.length() > 0.01 else _cam_flat_z()
	var perp := away.cross(Vector3.UP)
	_peek_t -= delta
	var peeking := _peek_t < 0.45 and _peek_t > 0.0
	if _peek_t <= -0.3:
		_peek_t = _rng.randf_range(2.0, 3.4)
		_peek_side = -_peek_side
	var spot := p + away * 0.55 + perp * _peek_side * (0.4 if peeking else 0.12)
	_set_goal(spot, 0.1, 14.0)
	_face_goal = _edge_on_to(s).lerp(_toward_camera(), 0.2).normalized()
	if peeking:
		_crouch_goal = 0.25
		_tremble_goal = 0.015
		_tip_toward(s)
	else:
		_crouch_goal = 0.45
		_tremble_goal = 0.05
		_mirror_goal = _mirror_goal if absf(_mirror_goal) > 0.0 else 1.0
		_roll_goal = -_mirror_goal * 0.45  # tip tucked upright, small as it can be
		_roll_rate = 14.0


func _do_curl(delta: float) -> void:
	var stare_at := _stare.global_position if is_instance_valid(_stare) else _curl_spot + _cam_flat_z()
	match _curl_phase:
		0:  # trot over
			_lean_or_rest()
			if _arrived_sent or _mode_t > 6.0:
				_curl_phase = 1
				_mode_t = 0.0
		1:  # circle twice on the spot, like a dog choosing where to lie
			var a := _mode_t * TAU * 1.6
			_set_goal(_curl_spot + Vector3(cos(a), 0.0, sin(a)) * 0.32, 0.05, 4.0)
			_lean_or_rest()
			if _mode_t > 1.25:
				_curl_phase = 2
				_mode_t = 0.0
				_set_goal(_curl_spot, 0.05, 2.0)
				_sq_v -= 2.5
				_tick(-6.0, 0.7)
		2:  # lie down, nose to the sleeping set, and breathe like a sleeping machine's light
			_face_goal = _flat(_curl_spot - stare_at).normalized()
			if _face_goal.length() < 0.5:
				_face_goal = _toward_camera()
			_lie_goal = 1.0
			_roll_goal = _mirror_goal * 0.5
			_roll_rate = 3.0
			var face := _mats[1]
			var pulse := 0.5 + 0.5 * sin(_mode_t * 1.25 - PI * 0.5)
			face.set_shader_parameter(&"face_off", 0.42 * pulse * clampf(_mode_t - 1.0, 0.0, 1.0))
			_breathe = pulse
	if _curl_phase < 2:
		_breathe = 0.0
	if delta == 0.0:
		pass


func _do_sniff(delta: float) -> void:
	if _sniff_hold > 0.0:
		_sniff_hold -= delta
		_tip_down()
		# little nose dips
		if fmod(_sniff_hold, 0.42) < delta:
			_sq_v -= 1.2
			_tick(-14.0, 0.85)
		if _sniff_hold <= 0.0:
			_sniffs_left -= 1
			if _sniffs_left <= 0:
				_sniff_finished.emit()
				_idle = minf(_idle, sniff_after - 12.0)  # don't nose about again too soon
				if not _scripted:
					_enter(Mode.FOLLOW)
				return
			_next_sniff_spot()
		return
	_lean_or_rest()
	if _arrived_sent:
		_sniff_hold = _rng.randf_range(0.9, 1.6)


func _start_sniff(center: Vector3, count: int) -> void:
	_sniff_center = center
	_sniffs_left = count
	_enter(Mode.SNIFF)
	_next_sniff_spot()


func _next_sniff_spot() -> void:
	_sniff_hold = 0.0
	var a := _rng.randf_range(0.0, TAU)
	var r := _rng.randf_range(1.0, 2.6)
	var spot := _sniff_center + Vector3(cos(a), 0.0, sin(a)) * r
	# keep it on the camera's side of him so it stays in frame
	if is_instance_valid(target):
		var cz := _cam_flat_z()
		var rel := _flat(spot - target.global_position)
		if rel.dot(cz) < -0.5:
			spot -= cz * rel.dot(cz) * 1.5
	_set_goal(spot, 0.2, 3.5)


# ---------------------------------------------------------------- gags


func _click() -> void:
	_sq_v -= 3.2
	blink()
	_double_tick(0.0)
	_ripple.global_position = global_position + Vector3.UP * 0.02
	_ripple_mat.set_shader_parameter(&"color", Color(ink.r, ink.g, ink.b, 1.0) if ink.a > 0.0 else BONE)
	_ripple.visible = true
	var tw := create_tween()
	tw.tween_method(func(v: float): _ripple_mat.set_shader_parameter(&"progress", v), 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func(): _ripple.visible = false)


func _small_hop(strength := 1.0) -> void:
	if _hop <= 0.0:
		_hop = 0.001
		_sq_v -= 1.5 * strength


func _skid() -> void:
	_sq_v -= 4.0
	_spin_by(-_mirror_goal * 0.35, 0.12, true)
	_dust.restart()
	_tick(-2.0, 0.7)


func _startle() -> void:
	_sq_v += 5.0
	_hop = 0.001
	_tick(-2.0, 1.2)


## Shakes itself off, like a wet dog.
func _relief() -> void:
	_spin_by(0.0, 0.0, false)
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	for i in 5:
		var amp := 0.45 * (1.0 - i / 5.0)
		tw.tween_property(self, "_spin", amp if i % 2 == 0 else -amp, 0.06)
	tw.tween_property(self, "_spin", 0.0, 0.08)
	tw.tween_callback(func():
		_busy = false)


func _wake() -> void:
	_lie_goal = 0.0
	_mats[1].set_shader_parameter(&"face_off", 0.0)
	_breathe = 0.0
	_sq_v += 4.0  # a big stretch
	get_tree().create_timer(0.45).timeout.connect(_relief)
	_enter(Mode.FOLLOW)


## The busy cursor: two full turns, then a dizzy wobble. Rare on purpose.
func _loading_spin() -> void:
	if _busy:
		return
	_busy = true
	var face := _mats[1]
	var tw := create_tween()
	tw.tween_property(self, "_spin", TAU * 2.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(func(v: float): face.set_shader_parameter(&"face_off", 0.35 * sin(v * PI * 6.0) ** 2), 0.0, 1.0, 1.7)
	tw.tween_callback(func(): _spin = 0.0)
	for i in 4:
		var amp := 0.22 * (1.0 - i / 4.0)
		tw.tween_property(self, "_spin", amp if i % 2 == 0 else -amp, 0.13)
	tw.tween_property(self, "_spin", 0.0, 0.1)
	tw.tween_callback(func():
		face.set_shader_parameter(&"face_off", 0.0)
		_busy = false)


func _spin_by(amount: float, time: float, back: bool) -> void:
	if time <= 0.0:
		return
	var tw := create_tween()
	tw.tween_property(self, "_spin", amount, time)
	if back:
		tw.tween_property(self, "_spin", 0.0, time * 2.0)


## Too far from him: it dissolves like a pointer losing its window and reappears at his heel.
func _go_lost() -> void:
	_enter(Mode.LOST)
	_tremble_goal = 0.2
	var tw := create_tween()
	tw.tween_method(_set_vanish, 0.0, 1.0, 0.25)
	tw.tween_callback(func():
		_tremble_goal = 0.0
		_tremble = 0.0
		global_position = _heel_spot()
		_snap_to_ground(true)
		_vel = Vector3.ZERO
		_has_goal = false
		_trail.clear())
	tw.tween_method(_set_vanish, 1.0, 0.0, 0.3)
	tw.tween_callback(func():
		_click()
		_enter(Mode.FOLLOW))


func _set_vanish(v: float) -> void:
	for m in _mats:
		m.set_shader_parameter(&"vanish", v)


# ---------------------------------------------------------------- body


func _set_goal(pos: Vector3, stop_radius: float, speed: float) -> void:
	if not _has_goal or _goal.distance_to(pos) > 0.05 or not is_equal_approx(_speed_cap, speed):
		_goal = pos
		_has_goal = true
		_stop_radius = stop_radius
		_speed_cap = minf(speed, max_speed)
		if _flat(global_position - pos).length() > stop_radius:
			_arrived_sent = false


func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _has_goal and mode != Mode.LOST:
		var to := _flat(_goal - global_position)
		var d := to.length()
		if d > _stop_radius:
			desired = to / d * minf(_speed_cap, (d - _stop_radius * 0.5) * 3.0 + 0.6)
		elif not _arrived_sent:
			_arrived_sent = true
			arrived.emit()
	_vel = _vel.move_toward(desired, acceleration * delta)
	global_position += _vel * delta

	# Never stand inside his feet.
	if is_instance_valid(target) and mode != Mode.LOST:
		var away := _flat(global_position - target.global_position)
		var dd := away.length()
		if dd < 0.42 and dd > 0.001:
			global_position += away / dd * (0.42 - dd)
	_snap_to_ground(false)

	# Hopping. Stride grows with speed: tiny pats at a walk, long bounds at a run.
	var speed := _vel.length()
	if speed > 0.35 or _hop > 0.0:
		var k := clampf(speed / 12.0, 0.0, 1.0)
		var stride := lerpf(0.45, 2.0, k)
		var rate := maxf(speed / stride, 2.8)
		_hop += rate * delta
		if _hop >= 1.0:
			_land(speed)
			_hop = fmod(_hop, 1.0) if speed > 0.35 else 0.0


func _land(speed: float) -> void:
	_sq_v -= 1.6 + speed * 0.28
	if speed > 0.6:
		_tick(lerpf(-18.0, -8.0, clampf(speed / 12.0, 0.0, 1.0)), 0.7)
	if speed > 7.0:
		_dust.restart()


func _snap_to_ground(hard: bool) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 2.5
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = hit.position.y
	elif is_instance_valid(target):
		var y := target.global_position.y
		global_position.y = y if hard else lerpf(global_position.y, y, 0.2)


func _pose(delta: float) -> void:
	var f := func(rate: float) -> float: return 1.0 - exp(-rate * delta)
	_face = _face.slerp(_face_goal.normalized(), f.call(7.0)).normalized()
	_mirror = move_toward(_mirror, _mirror_goal, delta * 8.0)
	_roll = lerp_angle(_roll, _roll_goal, f.call(_roll_rate))
	_lie = lerpf(_lie, _lie_goal, f.call(5.0))
	_crouch = lerpf(_crouch, _crouch_goal, f.call(9.0))
	_tremble = lerpf(_tremble, _tremble_goal, f.call(8.0))
	_aim_w = lerpf(_aim_w, _aim_w_goal, f.call(5.0))
	_roll_rate = lerpf(_roll_rate, 10.0, f.call(2.0))

	# Squash spring: quick, a little wobbly.
	_sq_v += (-_sq * 190.0 - _sq_v * 13.0) * delta
	_sq = clampf(_sq + _sq_v * delta, -0.45, 0.45)

	var y := Vector3.UP
	var z := _face if absf(_face.dot(y)) < 0.95 else Vector3.BACK
	var x := y.cross(z).normalized()
	z = x.cross(y)
	var upright := Basis(x, y, z)
	var b := upright * Basis(Vector3.RIGHT, -_lie * PI * 0.5)
	var shiver := sin(_t * 53.0) * _tremble + sin(_t * 31.0) * _tremble * 0.6
	b = b * Basis(Vector3.BACK, _roll + _spin + shiver)
	if _aim_w > 0.001 and _aim_dir.length() > 0.01:
		var tip_w := (upright * Vector3(TIP_LOCAL.x * signf(_mirror_goal), TIP_LOCAL.y, 0.0)).normalized()
		var aimed := Basis(Quaternion(tip_w, _aim_dir.normalized())) * upright
		# a small head-cock while it looks
		aimed = aimed * Basis(Vector3.BACK, sin(_t * 2.1) * 0.08)
		# Most of the way, not all: tip toward the lens but the bone face still showing.
		b = b.slerp(aimed.orthonormalized(), clampf(_aim_w, 0.0, 1.0) * 0.62)
	_rig.basis = b

	var air := sin(PI * _hop) if _hop > 0.0 else 0.0
	var k := clampf(_vel.length() / 12.0, 0.0, 1.0)
	_rig.position = Vector3(0.0, air * hop_height * lerpf(0.7, 1.6, k), 0.0)

	var stretch := _sq + air * 0.1
	var sy := (1.0 + stretch) * (1.0 - _crouch * 0.42) * (1.0 + _breathe * 0.025)
	var sxz := 1.0 - stretch * 0.45 + _crouch * 0.12
	var mx := _mirror if absf(_mirror) > 0.06 else 0.06 * signf(_mirror_goal)
	_squash.scale = Vector3(mx * sxz, sy, sxz * (1.0 + _breathe * 0.12))


## Default pose: lean into travel like a dog trotting, else stand and sway a little.
func _lean_or_rest() -> void:
	var cam := _cam()
	var speed := _vel.length()
	if cam and speed > 0.6:
		var sx := _vel.dot(cam.global_basis.x)
		if absf(sx) > 0.8:
			_mirror_goal = -signf(sx)  # the tip leads, on screen
		_roll_goal = _mirror_goal * clampf(speed * 0.035, 0.0, 0.42)
	else:
		_roll_goal = _mirror_goal * (0.05 * sin(_t * 1.7))


## Roll so the tip points at `world` as seen on screen. Mirrors when the thing is on the other side.
func _tip_toward(world: Vector3) -> void:
	var th := _screen_angle(global_position + Vector3.UP * 0.3, world)
	th = clampf(th, -2.0, 2.0)
	if absf(th) > 0.2:
		_mirror_goal = signf(th)
	_roll_goal = th - _mirror_goal * TIP_ANGLE
	_roll_rate = 16.0


func _tip_down() -> void:
	_roll_goal = _mirror_goal * (1.85 - TIP_ANGLE)
	_roll_rate = 8.0


## Angle on screen from `a` to `b`, counter-clockwise from straight up, in radians.
func _screen_angle(a: Vector3, b: Vector3) -> float:
	var cam := _cam()
	if cam == null:
		return 0.0
	if cam.is_position_behind(b) or cam.is_position_behind(a):
		var v := b - a
		return atan2(-v.dot(cam.global_basis.x), v.dot(cam.global_basis.y))
	var d := cam.unproject_position(b) - cam.unproject_position(a)
	return atan2(-d.x, -d.y)


func _is_centered(world: Vector3) -> bool:
	var cam := _cam()
	if cam == null or cam.is_position_behind(world):
		return false
	var size := get_viewport().get_visible_rect().size
	var p := cam.unproject_position(world) / size
	return absf(p.x - 0.5) < 0.18 and absf(p.y - 0.5) < 0.3


# ---------------------------------------------------------------- helpers


func _heel_spot() -> Vector3:
	var p := target.global_position
	var right := _cam_flat_x()
	var rel := global_position - p
	var s := rel.dot(right)
	if absf(s) > 0.5:
		_side = signf(s)
	return p + right * _side * heel_distance + _cam_flat_z() * 0.45


func _toward_camera() -> Vector3:
	var cam := _cam()
	if cam == null:
		return Vector3.BACK
	var v := _flat(cam.global_position - global_position)
	return v.normalized() if v.length() > 0.01 else _cam_flat_z()


## Face direction that shows `pos` only the Stray's edge, on the side nearest the camera.
func _edge_on_to(pos: Vector3) -> Vector3:
	var to := _flat(pos - global_position)
	if to.length() < 0.01:
		return _toward_camera()
	var perp := to.normalized().cross(Vector3.UP)
	return perp if perp.dot(_toward_camera()) >= 0.0 else -perp


func _nearest_stare(awake: bool, reaction: int, slack: float) -> StrayStare:
	var best: StrayStare
	var best_d := INF
	var p := target.global_position
	for n in get_tree().get_nodes_in_group(&"stray_stare"):
		var s := n as StrayStare
		if s == null or s.awake != awake:
			continue
		if awake and reaction >= 0 and s.reaction != reaction:
			continue
		var d := s.global_position.distance_to(p)
		var r := (s.fear_radius if awake else s.rest_radius) * slack
		if d < r and d < best_d:
			best = s
			best_d = d
	return best


func _best_interest() -> StrayInterest:
	var best: StrayInterest
	var best_score := -INF
	var p := target.global_position
	var now := _now()
	for n in get_tree().get_nodes_in_group(&"stray_interest"):
		var it := n as StrayInterest
		if it == null or not it.can_notice(p, now):
			continue
		var score := it.priority * 100.0 - it.global_position.distance_to(p)
		if score > best_score:
			best = it
			best_score = score
	return best


func _room() -> Room:
	var n := get_parent()
	while n and not (n is Room):
		n = n.get_parent()
	return n as Room


func _on_story_ink(_ink: StringName) -> void:
	_adopt_story_ink()


## A room's own ink, else what he carries, else the last ink planted at the spiral.
func _adopt_story_ink() -> void:
	var name := &""
	var room := _room()
	if room and room.gives_ink != &"":
		name = room.gives_ink
	elif Game.carried != &"":
		name = Game.carried
	elif not Game.inks_home.is_empty():
		name = Game.inks_home[-1]
	set_ink(INK_COLORS.get(name, Color(0, 0, 0, 0)))


## Every WatchingSet in the room gets a StrayStare that mirrors its eyes, so rooms
## don't have to add one by hand.
func _adopt_watching_sets() -> void:
	var room := _room()
	if room == null:
		return
	for ws in room.find_children("*", "WatchingSet", true, false):
		var has := false
		for c in ws.get_children():
			if c is StrayStare:
				has = true
		if not has:
			var s := StrayStare.new()
			s.name = &"StrayStare"
			s.position = Vector3(0, 1.0, 0)
			ws.add_child(s)


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _cam_flat_x() -> Vector3:
	var cam := _cam()
	if cam == null:
		return Vector3.RIGHT
	var v := _flat(cam.global_basis.x)
	return v.normalized() if v.length() > 0.01 else Vector3.RIGHT


func _cam_flat_z() -> Vector3:
	var cam := _cam()
	if cam == null:
		return Vector3.BACK
	var v := _flat(cam.global_basis.z)
	return v.normalized() if v.length() > 0.01 else Vector3.BACK


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## One cursor tick at its position. Steps are quiet ticks pitched down to about 0.7.
func _tick(db: float, pitch := 1.0) -> void:
	pitch *= _rng.randf_range(0.95, 1.05)
	var sound := get_node_or_null(^"/root/Sound")
	if tick_sound == null and sound and sound.has_method(&"play_at"):
		sound.play_at(&"cursor_tick", global_position, volume_db + db, pitch)
		return
	_feet.stream = tick_sound if tick_sound else _builtin_tick
	_feet.volume_db = volume_db + db
	_feet.pitch_scale = pitch
	_feet.play()


## Two ticks, a click: it noticed something.
func _double_tick(db: float) -> void:
	_tick(db, 1.0)
	get_tree().create_timer(0.075).timeout.connect(_tick.bind(db - 2.0, 1.08))


# ---------------------------------------------------------------- build


func _find_mesh(root: Node) -> MeshInstance3D:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		return n
	push_error("Stray: no MeshInstance3D under Rig/Squash")
	return null


func _make_material(face: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STRAY_SHADER
	m.set_shader_parameter(&"base_color", BONE if face else BLACK)
	m.set_shader_parameter(&"dark_color", BLACK)
	m.set_shader_parameter(&"is_face", face)
	m.set_shader_parameter(&"ink", ink)
	m.set_shader_parameter(&"tip", TIP_LOCAL)
	return m


## Surface 0 is "rim" (black), surface 1 is "face" (bone); matched by name when possible.
func _surface_is_face(mesh: Mesh, i: int) -> bool:
	var mat := mesh.surface_get_material(i)
	if mat and mat.resource_name != "":
		return mat.resource_name.to_lower().contains("face")
	return i == 1


func _build_materials() -> void:
	_mats = [_make_material(false), _make_material(true)]
	for i in _mesh.mesh.get_surface_count():
		_mesh.set_surface_override_material(i, _mats[1] if _surface_is_face(_mesh.mesh, i) else _mats[0])


## Mouse trails: when it bounds at speed, three fading after-images follow it.
func _build_ghosts() -> void:
	for i in 3:
		var g := MeshInstance3D.new()
		g.mesh = _mesh.mesh
		g.top_level = true
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		var rim := _make_material(false)
		var face := _make_material(true)
		_ghost_mats.append_array([rim, face])
		for s in _mesh.mesh.get_surface_count():
			g.set_surface_override_material(s, face if _surface_is_face(_mesh.mesh, s) else rim)
		add_child(g)
		_ghosts.append(g)


func _update_trail(delta: float) -> void:
	var want := 1.0 if _vel.length() > 8.0 and mode != Mode.LOST else 0.0
	_trail_amount = move_toward(_trail_amount, want, delta * 4.0)
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.04
		_trail.push_front(_mesh.global_transform)
		if _trail.size() > 10:
			_trail.pop_back()
	for i in _ghosts.size():
		var g := _ghosts[i]
		var idx := (i + 1) * 3
		if _trail_amount <= 0.01 or idx >= _trail.size():
			g.visible = false
			continue
		g.visible = true
		g.global_transform = _trail[idx]
		var v := lerpf(1.0, 0.45 + i * 0.18, _trail_amount)
		_ghost_mats[i * 2].set_shader_parameter(&"vanish", v)
		_ghost_mats[i * 2 + 1].set_shader_parameter(&"vanish", v)


func _build_ripple() -> void:
	_ripple = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.6)
	_ripple.mesh = plane
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = RIPPLE_SHADER
	_ripple.material_override = _ripple_mat
	_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripple.top_level = true
	_ripple.visible = false
	add_child(_ripple)


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 7
	_dust.lifetime = 0.4
	_dust.explosiveness = 1.0
	_dust.direction = Vector3.UP
	_dust.spread = 75.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.2
	_dust.gravity = Vector3(0, -7, 0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = BONE
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	_dust.mesh = q
	_dust.position.y = 0.03
	add_child(_dust)


func _build_sounds() -> void:
	_feet = AudioStreamPlayer3D.new()
	_feet.unit_size = 5.0
	_feet.max_distance = 70.0
	add_child(_feet)
	_builtin_tick = StraySounds.tick()
