extends "res://story/sequence.gd"
## The opening, in the hub:
##   1. Washed up. One last wave goes over him, then the sea drains away down the beach.
##   2. He stirs, pushes up off the sand, stands, and looks around.
##   3. The Stray blinks into being far down the tideline and comes to him.
##   4. Control. Walking inland he meets the first television, whose eyes follow him.
##   5. The first long descent: partway down the crater the camera turns to show the rim
##      rising behind him like a stadium, and he keeps walking down.
## Beats 4 and 5 keep waiting on later hub visits until they have played once.

const Title := preload("res://story/title.gd")
const STRAY_SCENE := "res://companions/stray/stray.tscn"
const STRAY_STANDIN := preload("res://story/props/stray_standin.gd")

## Skip the wash-up (a return visit that still owes the television or the descent).
var skip_wake := false
## How close (m) to the television before it holds his gaze.
var tv_radius := 20.0
## The stadium shot plays on his first walk down, once he is this far (m) below the
## highest point he reached on the way in (the crater's rim), or this far below the shore.
var descent_drop := 70.0
var descent_depth := 28.0

var dressing: Node
var stray: Node3D
var _listening := false
var _beat_running := false
var _autowalk := Vector3.ZERO
var _pressed: Array[StringName] = []
var _highest := -INF


func _init() -> void:
	sequence_name = &"opening"


func _ready() -> void:
	dressing = room().get_node(^"StoryDressing")
	if not skip_wake:
		hold()
	await dressing.wait_surveyed()
	shore = dressing.shore
	if not skip_wake:
		await _wash_up()
	else:
		stray = _find_stray()
	_listening = true


func is_holding() -> bool:
	return holding or _beat_running


# --- 1-3: washed up ------------------------------------------------------------------

func _wash_up() -> void:
	var p := Game.player
	var tide = dressing.tide
	var audio: Node = dressing.audio
	var wake := shore.wake
	place_player(wake, shore.inland)
	pose_prone(p)
	var look_ridge := wake + shore.inland * 70.0 + Vector3.UP * 26.0
	if cam.global_position.distance_to(Title.title_eye(shore)) > 12.0:
		cut(Title.title_eye(shore), look_ridge, 44.0)
	_hide_stray_until_found()

	# The last wave: the water climbs over him and slides back.
	audio.set(&"surf", 1.0)
	glide(wake - shore.inland * 15.0 + shore.along * 6.0 + Vector3.UP * 2.4, wake + shore.inland * 8.0 + Vector3.UP * 3.0, 9.0, 40.0)
	await wait(1.2)
	audio.set(&"swell", 1.0)
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(tide, "surge", tide.rest + 8.0, 1.8 * time_scale).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.9 * time_scale)
	t.tween_callback(func() -> void: audio.set(&"swell", 0.0))
	t.tween_property(tide, "surge", 0.0, 2.8 * time_scale).set_ease(Tween.EASE_IN_OUT)
	await t.finished

	# The drain: the whole sea pulls away down the beach and leaves the sand shining.
	audio.set(&"surf", 0.35)
	var d := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	d.tween_property(tide, "drain", 1.0, 8.0 * time_scale)
	d.tween_property(tide, "lap", 0.5, 8.0 * time_scale)
	await wait(2.5)
	# Down on the sand with him.
	await glide(wake + shore.along * 3.4 - shore.inland * 1.2 + Vector3.UP * 0.6, wake + Vector3.UP * 0.3 + shore.inland * 0.3, 4.0, 36.0).finished
	await wait(1.5)

	# He stirs.
	await _stir(p)

	# Behind him, eye level: the ridge fills the sky.
	glide(wake - shore.inland * 5.5 + shore.along * 1.6 + Vector3.UP * 1.8, wake + shore.inland * 60.0 + Vector3.UP * 16.0, 5.0, 46.0)
	await _look_around(p)

	# The Stray: a caret blinking far down the tideline, then hopping toward him.
	_ensure_stray()
	var from := shore.shore_point(68.0, 1.0)
	var to := wake + shore.along * 2.0 - shore.inland * 0.4
	cut(wake - shore.along * 9.0 - shore.inland * 3.5 + Vector3.UP * 1.3, wake + shore.along * 26.0 + Vector3.UP * 0.9, 38.0)
	glide(wake - shore.along * 6.0 - shore.inland * 3.0 + Vector3.UP * 1.1, wake + shore.along * 10.0 + Vector3.UP * 0.8, 12.0, 34.0)
	_turn_visual(p, shore.along, 1.4)
	stray.global_position = from
	stray.visible = true
	await call_and_wait(stray, &"arrive", [from, to], 16.0)
	if not is_instance_valid(stray) or stray.global_position.distance_to(to) > 3.0:
		stray.global_position = to

	# It sniffs around him; he watches it.
	var mid := (wake + stray.global_position) * 0.5
	glide(mid - shore.inland * 3.6 + Vector3.UP * 0.9, mid + Vector3.UP * 0.35, 3.0, 40.0)
	_turn_visual(p, stray.global_position - p.global_position, 0.8)
	await call_and_wait(stray, &"sniff_around", [p], 4.0)

	# Off you go.
	p.face(shore.inland)
	Story.set_flag(Story.FLAG_OPENING_SEEN, true)
	audio.set(&"surf", 0.7)
	await release(2.4)
	if is_instance_valid(stray) and stray.has_method(&"follow"):
		stray.call(&"follow", p)


func _stir(p: Player) -> void:
	var v := p.visual
	var t := create_tween()
	# Two small twitches.
	for i in 2:
		t.tween_property(v, "rotation:z", 0.06, 0.08 * time_scale)
		t.tween_property(v, "rotation:z", -0.03, 0.1 * time_scale)
		t.tween_property(v, "rotation:z", 0.0, 0.12 * time_scale)
		t.tween_interval(0.7 * time_scale)
	# Push up off the sand, sag once, push again, then stand.
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "rotation:x", deg_to_rad(-62.0), 1.6 * time_scale)
	t.parallel().tween_property(v, "position:y", 0.34, 1.6 * time_scale)
	t.tween_interval(0.6 * time_scale)
	t.tween_property(v, "rotation:x", deg_to_rad(-70.0), 0.35 * time_scale).set_ease(Tween.EASE_IN)
	t.tween_interval(0.7 * time_scale)
	t.tween_property(v, "rotation:x", deg_to_rad(-24.0), 1.4 * time_scale)
	t.parallel().tween_property(v, "position:y", 0.12, 1.4 * time_scale)
	t.tween_interval(0.5 * time_scale)
	t.tween_property(v, "rotation:x", 0.0, 1.3 * time_scale).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(v, "position:y", 0.0, 1.3 * time_scale)
	await t.finished
	pose_standing(p)


func _look_around(p: Player) -> void:
	await wait(0.8)
	await _turn_visual(p, -shore.along * 0.6 + shore.inland, 1.0)
	await wait(0.9)
	await _turn_visual(p, shore.along * 0.8 + shore.inland * 0.4, 1.4)
	await wait(0.7)
	await _turn_visual(p, shore.inland, 1.0)
	await wait(1.0)


func _turn_visual(p: Player, dir: Vector3, seconds: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	var from := p.visual.rotation.y
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(w: float) -> void: p.visual.rotation.y = lerp_angle(from, yaw, w), 0.0, 1.0, seconds * time_scale)
	await t.finished
	p.facing = dir.normalized()


# --- The Stray -------------------------------------------------------------------------

func _find_stray() -> Node3D:
	for n in get_tree().get_nodes_in_group(&"stray"):
		if n is Node3D and room().is_ancestor_of(n):
			return n
	return null


## If the Stray already travels with him (its own system spawned it), it waits out of
## sight until the moment it finds him.
func _hide_stray_until_found() -> void:
	stray = _find_stray()
	if stray:
		stray.visible = false
		stray.global_position = shore.shore_point(68.0, 1.0)
		if stray.has_method(&"walk_to"):
			stray.call(&"walk_to", stray.global_position)


func _ensure_stray() -> void:
	if not is_instance_valid(stray):
		stray = _find_stray()
	if not is_instance_valid(stray):
		if ResourceLoader.exists(STRAY_SCENE):
			stray = load(STRAY_SCENE).instantiate()
		else:
			stray = STRAY_STANDIN.new()
		stray.name = "Stray"
		stray.visible = false
		room().add_child(stray)
	stray.visible = false


# --- 4-5: the first television and the first descent ------------------------------------

func _physics_process(_delta: float) -> void:
	_drive_autowalk()
	if not _listening or _beat_running or holding:
		return
	var p := Game.player
	if not is_instance_valid(p) or Game.is_travelling() or _hub_busy():
		return
	if not Story.get_flag(Story.FLAG_FIRST_TV_SEEN) and is_instance_valid(dressing.tv):
		if p.global_position.distance_to(dressing.tv.global_position) < tv_radius:
			_tv_beat()
			return
	_highest = maxf(_highest, p.global_position.y)
	if not Story.get_flag(Story.FLAG_FIRST_DESCENT_SEEN) and _toward_pit(p) > 0.2:
		var y := p.global_position.y
		if y < shore.shore_height - descent_depth or y < _highest - descent_drop:
			_descent_beat()


func _process(_delta: float) -> void:
	# The broadcast hum swells as he nears the set (while its eyes are open).
	if not is_instance_valid(dressing) or not is_instance_valid(dressing.tv) or not is_instance_valid(Game.player):
		return
	var d: float = Game.player.global_position.distance_to(dressing.tv.global_position)
	var open: bool = dressing.tv.get(&"lid") == null or float(dressing.tv.get(&"lid")) < 0.9
	if not _beat_running:
		dressing.audio.set(&"hum", clampf(1.0 - d / 70.0, 0.0, 1.0) * 0.45 if open else 0.0)


func _tv_beat() -> void:
	_beat_running = true
	Story.set_flag(Story.FLAG_FIRST_TV_SEEN, true)
	hold()
	var p := Game.player
	var tv: Node3D = dressing.tv
	var screen: Vector3 = dressing.tv_screen()
	var facing := tv.global_basis.z.normalized()
	facing.y = 0.0
	facing = facing.normalized()
	var side := facing.cross(Vector3.UP)
	dressing.audio.set(&"hum", 1.0)
	drain_to(0.75, 1.2)
	if is_instance_valid(stray) and stray.has_method(&"cower"):
		stray.call(&"cower", tv.global_position)
	# Behind him and low, the set looming with its eyes on him; push in slowly.
	var behind := p.global_position - facing * -7.5 + side * 2.5
	var hd := (p.global_position - tv.global_position)
	hd.y = 0.0
	var away := hd.normalized()
	behind = p.global_position + away * 7.0 + side * 2.2 + Vector3.UP * 1.1
	cut(behind, screen, 40.0)
	await glide(p.global_position + away * 4.5 + side * 1.4 + Vector3.UP * 1.0, screen + Vector3.UP * 0.5, 4.5, 34.0).finished
	# What it sees: him, small, from right at the glass.
	cut(screen + facing * 1.2 + Vector3.UP * 0.2, p.global_position + Vector3.UP * 1.0, 28.0)
	await wait(2.2)
	drain_to(0.0, 1.5)
	dressing.audio.set(&"hum", 0.45)
	await release(1.6)
	if is_instance_valid(stray) and stray.has_method(&"follow"):
		stray.call(&"follow", p)
	_beat_running = false


## The hub plays its own planting and eye sequences; never take the camera from them.
func _hub_busy() -> bool:
	var ink_state := room().get_node_or_null(^"InkState")
	return ink_state != null and ink_state.has_method(&"is_playing") and bool(ink_state.call(&"is_playing"))


func _toward_pit(p: Player) -> float:
	var to := shore.pit - p.global_position
	to.y = 0.0
	return Vector2(p.velocity.x, p.velocity.z).normalized().dot(Vector2(to.x, to.z).normalized()) if to.length() > 1.0 else 0.0


func _descent_beat() -> void:
	_beat_running = true
	Story.set_flag(Story.FLAG_FIRST_DESCENT_SEEN, true)
	var p := Game.player
	_ensure_camera()
	cam.global_transform = Game.camera.global_transform
	cam.fov = Game.camera.fov
	cam.make_current()
	holding = true
	var down := shore.pit - p.global_position
	down.y = 0.0
	down = down.normalized()
	var side := down.cross(Vector3.UP)
	# He keeps walking down while we look back up at him: the rim behind rises like the
	# tiers of a stadium.
	_autowalk = down
	var ahead := shore.ground(p.global_position + down * 38.0 + side * 9.0) + Vector3.UP * 2.0
	var ahead2 := shore.ground(p.global_position + down * 30.0 + side * 12.0) + Vector3.UP * 1.4
	await track(PackedVector3Array([ahead, ahead2]), func() -> Vector3: return p.global_position + Vector3.UP * 6.0, 7.5, 34.0, 30.0).finished
	# Then from high over the pit: a speck on the crater wall.
	var over := shore.pit + Vector3.UP * 150.0 - down * 60.0 + side * 40.0
	cut(over, p.global_position, 42.0)
	await track(PackedVector3Array([over, over + Vector3.UP * 25.0 + side * 20.0]), func() -> Vector3: return p.global_position, 5.0, 42.0, 38.0).finished
	_autowalk = Vector3.ZERO
	await release(2.0)
	_beat_running = false


## While `_autowalk` is set he walks that way by himself (pressing the move actions as
## the player would, so the hub's grooves still carry him).
func _drive_autowalk() -> void:
	for a in _pressed:
		Input.action_release(a)
	_pressed.clear()
	if _autowalk == Vector3.ZERO:
		return
	var p := Game.player
	var c := get_viewport().get_camera_3d()
	if not is_instance_valid(p) or c == null:
		return
	p.controls_enabled = true
	var local := _autowalk.rotated(Vector3.UP, -c.global_rotation.y)
	var pairs := [[&"move_right", local.x], [&"move_left", -local.x], [&"move_down", local.z], [&"move_up", -local.z]]
	for pair in pairs:
		if pair[1] > 0.05:
			Input.action_press(pair[0], clampf(pair[1], 0.0, 1.0))
			_pressed.append(pair[0])


func _exit_tree() -> void:
	for a in _pressed:
		Input.action_release(a)
