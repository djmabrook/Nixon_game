extends Node3D
## Stand-in for the Stray until res://companions/stray/stray.tscn lands. It answers the
## same scripted calls the story makes, so swapping in the real one needs no story change.
## A lost arrow cursor: it hops, blinks like a caret when it first appears, and keeps
## close to the little man's heel.

const MODEL_PATH := "res://story/props/stray_cursor.glb"

var _mode := &"idle"
var _target: Node3D
var _goal := Vector3.ZERO
var _speed := 7.0
var _hop := 0.0
var _arrived := true
var _look_cam := 0.0
var _model: Node3D

signal arrived


func _ready() -> void:
	add_to_group(&"stray")
	_model = (load(MODEL_PATH) as PackedScene).instantiate()
	add_child(_model)
	_model.scale = Vector3.ONE * 1.4


func arrive(from: Vector3, to: Vector3) -> void:
	global_position = from
	visible = true
	# Blink in like a caret: on, off, on.
	for i in 3:
		visible = false
		await get_tree().create_timer(0.18, false).timeout
		visible = true
		await get_tree().create_timer(0.24, false).timeout
	await walk_to(to)


func walk_to(pos: Vector3) -> void:
	_mode = &"walk"
	_goal = pos
	_arrived = false
	await arrived


func follow(target: Node3D) -> void:
	_target = target
	_mode = &"follow"


func sniff_around(target: Node3D) -> void:
	_target = target
	_mode = &"sniff"
	await get_tree().create_timer(2.6, false).timeout


func cower(near: Vector3) -> void:
	_mode = &"cower"
	_goal = near


func look_at_camera(hold := 1.5) -> void:
	_mode = &"look"
	_look_cam = hold
	await get_tree().create_timer(hold + 0.4, false).timeout


func release() -> void:
	_mode = &"follow" if is_instance_valid(_target) else &"idle"


func set_ink(_c: Color) -> void:
	pass


func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var p := global_position
	var want := p
	var speed := _speed
	match _mode:
		&"walk":
			want = _goal
		&"follow", &"sniff":
			if is_instance_valid(_target):
				var tp := _target.global_position
				var side := _target.global_basis.x if _mode == &"follow" else Vector3(cos(t * 1.7), 0, sin(t * 1.7))
				var r := 1.6 if _mode == &"follow" else 1.1
				want = tp + side * r - (_target.global_basis.z * -0.6 if _mode == &"follow" else Vector3.ZERO)
				if _mode == &"follow" and p.distance_to(tp) < 2.5:
					want = p
				speed = 9.0 if p.distance_to(tp) > 6.0 else 4.0
		&"cower":
			var pl := Game.player
			if is_instance_valid(pl):
				var away := (pl.global_position - _goal)
				away.y = 0.0
				want = pl.global_position + away.normalized() * 0.7
			speed = 6.0
	var to := want - p
	to.y = 0.0
	var moving := to.length() > 0.15
	if moving:
		var step := minf(speed * delta, to.length())
		p += to.normalized() * step
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-10.0 * delta))
	elif _mode == &"walk" and not _arrived:
		_arrived = true
		arrived.emit()
	if _mode == &"look" and is_instance_valid(get_viewport().get_camera_3d()):
		var c := get_viewport().get_camera_3d().global_position - p
		rotation.y = lerp_angle(rotation.y, atan2(-c.x, -c.z), 1.0 - exp(-8.0 * delta))
	# Stand on the sand.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit.normal as Vector3).y > 0.5:
		p.y = hit.position.y
	global_position = p
	# Hop while moving; tremble while cowering.
	_hop = _hop + delta * 9.0 if moving else 0.0
	_model.position.y = absf(sin(_hop)) * 0.18 if moving else 0.0
	_model.rotation.z = sin(t * 40.0) * 0.06 if _mode == &"cower" else 0.0
	_model.rotation.x = -0.35 if _mode == &"look" else lerpf(_model.rotation.x, 0.0, 0.2)
