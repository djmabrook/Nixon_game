extends Node3D
## Shared machinery for the story sequences: taking and giving back the player and
## camera, a cinematic camera of our own, and small helpers for timing and posing.
##
## A sequence owns `StoryCamera` (a plain Camera3D) while it holds the shot, so it never
## fights the hub's own per-frame camera tuning. Releasing blends back into Game.camera.

signal finished(next: StringName)

const Shore := preload("res://story/shore.gd")
const CAMERA_NAME := &"StoryCamera"

var sequence_name: StringName = &"sequence"
var shore: Shore
var cam: Camera3D
var holding := false
## Seconds scaled by this (tests run sequences fast).
var time_scale := 1.0

var _cam_tween: Tween


func is_holding() -> bool:
	return holding


func room() -> Room:
	return get_parent() as Room


## Survey the hub once its bodies are in the physics space.
func survey() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	shore = Shore.new(room())
	shore.survey()


# --- Holding the player and camera ----------------------------------------------------

func hold() -> void:
	holding = true
	var p := Game.player
	if is_instance_valid(p):
		p.controls_enabled = false
		p.velocity = Vector3.ZERO
	_ensure_camera()
	if is_instance_valid(Game.camera) and not cam.current:
		cam.global_transform = Game.camera.global_transform
		cam.fov = Game.camera.fov
	cam.make_current()


## Hand back to the player, blending from the story shot into the follow camera.
func release(blend := 1.6) -> void:
	var p := Game.player
	var follow := Game.camera
	if is_instance_valid(follow) and is_instance_valid(cam) and cam.current and blend > 0.0:
		if is_instance_valid(p):
			follow.face_toward(p.global_position + p.facing * 20.0 + Vector3.UP * 1.5)
			follow.snap_to_target()
		var from := cam.global_transform
		var from_fov := cam.fov
		var t := _new_cam_tween()
		t.tween_method(func(w: float) -> void:
			if is_instance_valid(follow):
				cam.global_transform = from.interpolate_with(follow.global_transform, w)
				cam.fov = lerpf(from_fov, follow.fov, w)
		, 0.0, 1.0, blend * time_scale)
		await t.finished
	if is_instance_valid(follow):
		follow.make_current()
	if is_instance_valid(p):
		p.controls_enabled = true
	holding = false


func _ensure_camera() -> void:
	if is_instance_valid(cam):
		return
	cam = room().get_node_or_null(NodePath(CAMERA_NAME)) as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = CAMERA_NAME
		cam.near = 0.1
		cam.far = 9000.0
		room().add_child(cam)
	if is_instance_valid(Game.camera):
		cam.far = maxf(Game.camera.far, 6000.0)
		cam.environment = Game.camera.environment


# --- Camera moves ----------------------------------------------------------------------

func _new_cam_tween() -> Tween:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween()
	return _cam_tween


## Cut straight to a shot.
func cut(from: Vector3, look: Vector3, fov := 50.0) -> void:
	_ensure_camera()
	cam.global_transform = Transform3D(Basis(), from).looking_at(look, Vector3.UP)
	cam.fov = fov


## Glide to a shot over `seconds` (sine in-out). Returns the tween; await `.finished`.
func glide(from: Vector3, look: Vector3, seconds: float, fov := -1.0, trans := Tween.TRANS_SINE) -> Tween:
	_ensure_camera()
	var start := cam.global_transform
	var end := Transform3D(Basis(), from).looking_at(look, Vector3.UP)
	var start_fov := cam.fov
	var end_fov := fov if fov > 0.0 else cam.fov
	var t := _new_cam_tween().set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(w: float) -> void:
		cam.global_transform = start.interpolate_with(end, w)
		cam.fov = lerpf(start_fov, end_fov, w)
	, 0.0, 1.0, maxf(seconds * time_scale, 0.01))
	return t


## Glide along a path of eye points while always looking at `look_fn.call()` (for a
## moving subject). Catmull-Rom through the points.
func track(points: PackedVector3Array, look_fn: Callable, seconds: float, fov_from := -1.0, fov_to := -1.0) -> Tween:
	_ensure_camera()
	var f0 := fov_from if fov_from > 0.0 else cam.fov
	var f1 := fov_to if fov_to > 0.0 else f0
	var t := _new_cam_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(w: float) -> void:
		var eye := _spline(points, w)
		var look: Vector3 = look_fn.call()
		if not eye.is_equal_approx(look):
			cam.global_transform = Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
		cam.fov = lerpf(f0, f1, w)
	, 0.0, 1.0, maxf(seconds * time_scale, 0.01))
	return t


static func _spline(pts: PackedVector3Array, w: float) -> Vector3:
	var n := pts.size()
	if n == 1:
		return pts[0]
	var f := clampf(w, 0.0, 1.0) * (n - 1)
	var i := mini(int(f), n - 2)
	var u := f - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n - 1)]
	return p1.cubic_interpolate(p2, p0, p3, u)


# --- Timing ----------------------------------------------------------------------------

func wait(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds * time_scale, 0.0), false).timeout


## Await whatever `obj.method(args)` returns if it is awaitable, but never longer than
## `timeout` seconds (scripted calls into other threads' nodes must never hang the story).
func call_and_wait(obj: Object, method: StringName, args: Array, timeout: float) -> void:
	if not is_instance_valid(obj) or not obj.has_method(method):
		return
	var done := [false]
	var runner := func() -> void:
		await obj.callv(method, args)
		done[0] = true
	runner.call()
	var left := timeout * time_scale
	while not done[0] and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


# --- Posing the little man --------------------------------------------------------------

## Face-down in the wash: the visual tipped forward onto the sand.
func pose_prone(p: Player) -> void:
	p.visual.rotation.x = -PI * 0.5
	p.visual.position = Vector3(0, 0.22, 0)


func pose_standing(p: Player) -> void:
	p.visual.rotation.x = 0.0
	p.visual.rotation.z = 0.0
	p.visual.position = Vector3.ZERO


## Place the little man standing on the sand at `pos`, facing `dir`.
func place_player(pos: Vector3, dir: Vector3) -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	p.global_position = pos + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	p.face(dir)
	if is_instance_valid(Game.camera):
		Game.camera.face_toward(pos + dir * 20.0)
		Game.camera.snap_to_target()


func dither() -> Node:
	return get_tree().get_first_node_in_group(&"dither_look")


## Bleed the frame's colour toward black and bone (the stare), if the dither look is in.
func drain_to(amount: float, seconds: float) -> void:
	var d := dither()
	if d and &"drain" in d:
		create_tween().tween_property(d, "drain", amount, maxf(seconds * time_scale, 0.01))


## Switch the dither look to a preset by path (dissolving through the pattern), if present.
func look_to(preset_path: String, seconds: float) -> void:
	var d := dither()
	if d == null or not ResourceLoader.exists(preset_path):
		return
	var look := load(preset_path)
	if d.has_method(&"transition_to"):
		d.call(&"transition_to", look, maxf(seconds * time_scale, 0.01))


## The sound direction's `Sound` autoload, when it is in the project (audio/AUDIO.md).
func sound() -> Node:
	return get_node_or_null(^"/root/Sound")


## Call a Sound method if the autoload is there; otherwise nothing.
func sound_call(method: StringName, args: Array = []) -> void:
	var s := sound()
	if s and s.has_method(method):
		s.callv(method, args)


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
