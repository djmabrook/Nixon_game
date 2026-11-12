extends Room
## THE LAKESIDE. A 1-bit night by a lake. The campfire is the only color in the world,
## and its light is the only thing that makes the world real.
##
## Rule broken: things only exist where firelight touches them. The stones across the
## lake are there and solid only inside a light's reach, and dark water swallows you
## everywhere else. Take a burning brand from the campfire (interact), carry it across,
## and light the cold fire pit under the mountain. That fire wakes the path for good and
## opens a way home at the mountain's foot. The house door also leads back to the hub.
##
## Static layout lives in room.tscn under Layout (rotated 45 degrees so "up the screen" is
## Layout's -Z). The stones, house, mountain, fire and other set dressing are built here
## so placeholder geometry stays easy to tune from a few constants.

const RoomLook := preload("res://rooms/lakeside/lakeside_look.gd")

## Stones across the lake, in Layout space (x, z). Each pair of neighbours overlaps so
## the little man can walk across without jumping.
const PATH_STONES: Array[Vector2] = [
	Vector2(0.0, 1.4), Vector2(0.4, 0.1), Vector2(1.0, -1.1), Vector2(1.2, -2.4),
	Vector2(0.7, -3.6), Vector2(-0.1, -4.7), Vector2(-0.8, -5.8), Vector2(-1.0, -7.1),
	Vector2(-0.6, -8.3), Vector2(0.0, -9.5), Vector2(0.2, -10.8),
]
## A false branch that sinks into nothing. Dreams have dead ends.
const DEAD_END_STONES: Array[Vector2] = [
	Vector2(-1.3, -4.1), Vector2(-2.5, -3.6), Vector2(-3.7, -3.2),
]
const TREES: Array[Vector3] = [  # x, z, height
	Vector3(-5.2, 7.2, 3.2), Vector3(-6.2, 4.4, 2.6), Vector3(-4.0, 9.0, 3.6),
	Vector3(6.0, 8.6, 2.8), Vector3(-4.2, -14.0, 3.0), Vector3(4.2, -17.0, 3.4),
	Vector3(3.8, -12.6, 2.4), Vector3(-3.0, -17.8, 2.8),
]

## How far each light makes the world real, in metres.
@export var campfire_reach := 4.2
@export var torch_reach := 3.1
@export var beacon_reach := 5.0
## How fast things fade in and out of existence.
@export var reveal_speed := 5.0
## The little man can grab or use things this close.
@export var interact_range := 1.6
## Below this height the lake has you.
@export var drown_depth := -1.0

## Fired when the cold fire under the mountain is lit (the room's goal).
signal beacon_lit

@onready var layout: Node3D = $Layout
@onready var campfire_spot: Marker3D = $Layout/Campfire
@onready var beacon_spot: Marker3D = $Layout/Beacon
@onready var mountain_exit: RoomExit = $Layout/ExitMountain

var campfire: Node3D
var beacon: Node3D
var torch: Node3D
var torch_carried := false
var beacon_is_lit := false

## Everything that exists only in firelight: {node, body (or null), mat, rest_y, reality, permanent}
var _bound: Array[Dictionary] = []
var _stone_bodies: Dictionary = {}  # StaticBody3D -> stone entry, for footstep ripples
var _last_stone: Node = null
var _glyph: Node3D
var _drowning := false
var _time := 0.0


func _ready() -> void:
	RoomLook.dress(self)
	campfire = RoomLook.make_fire(1.0, true)
	campfire_spot.add_child(campfire)
	beacon = RoomLook.make_fire_pit()
	beacon_spot.add_child(beacon)
	torch = RoomLook.make_torch()
	add_child(torch)
	torch.visible = false
	_glyph = RoomLook.make_glyph()
	add_child(_glyph)

	for p in PATH_STONES:
		_add_stone(p, true)
	for p in DEAD_END_STONES:
		_add_stone(p, false)
	for t in TREES:
		var tree := RoomLook.make_tree(t.z)
		layout.add_child(tree)
		tree.position = Vector3(t.x, 0.0, t.y)
		_bind(tree, null, RoomLook.collect_materials(tree))

	mountain_exit.enabled = false
	mountain_exit.visible = false
	_set_reach(campfire, campfire_reach)
	_set_reach(torch, torch_reach)


func _on_room_entered(_spawn: StringName) -> void:
	if Game.is_completed(room_id):
		_light_beacon(true)
	# Settle the world instantly so nothing pops on the first frame.
	_update_reality(10.0)


func _physics_process(delta: float) -> void:
	_time += delta
	_update_reality(delta)
	_update_water()
	if not is_instance_valid(Game.player) or Game.current_room != self:
		return
	_carry_torch(delta)
	_footsteps()
	_update_glyph()
	if not _drowning and Game.player.global_position.y < drown_depth:
		_drown()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and not _drowning:
		if interact():
			get_viewport().set_input_as_handled()


## Does whatever makes sense where the little man stands. Returns true if something happened.
func interact() -> bool:
	var pos := Game.player.global_position
	if torch_carried:
		if not beacon_is_lit and _flat_dist(pos, beacon_spot.global_position) < interact_range:
			_light_beacon(false)
			return true
		_drop_torch()
		return true
	if torch.visible and _flat_dist(pos, torch.global_position) < interact_range:
		_pick_torch()
		return true
	if _flat_dist(pos, campfire_spot.global_position) < interact_range + 0.4:
		_pick_torch()
		return true
	return false


## True if a world point is real right now (inside any light's reach).
func is_real_at(world_pos: Vector3) -> bool:
	return _light_amount(world_pos) > 0.5


# --- Lights and reality ---------------------------------------------------------------

func _lights() -> Array:
	var out := [[campfire_spot.global_position, campfire_reach]]
	if torch.visible:
		out.append([torch.global_position, torch_reach])
	if beacon_is_lit:
		out.append([beacon_spot.global_position, beacon_reach])
	return out


## 1 inside a light's reach, fading to 0 over its last metre.
func _light_amount(world_pos: Vector3) -> float:
	var best := 0.0
	for l in _lights():
		var d := _flat_dist(world_pos, l[0])
		best = maxf(best, 1.0 - smoothstep(l[1] - 1.2, l[1], d))
	return best


func _update_water() -> void:
	var lake := layout.get_node_or_null(^"Lake") as MeshInstance3D
	if lake == null:
		return
	var m := lake.material_override as ShaderMaterial
	var ls := _lights()
	for i in 3:
		var v := Vector4.ZERO
		if i < ls.size():
			var p: Vector3 = ls[i][0]
			v = Vector4(p.x, p.y, p.z, ls[i][1])
		m.set_shader_parameter("fire%d" % i, v)


func _bind(node: Node3D, body: CollisionObject3D, mats: Array) -> Dictionary:
	var entry := {
		node = node, body = body, mats = mats, rest_y = node.position.y,
		reality = 0.0, permanent = false, solid = true,
	}
	_bound.append(entry)
	_apply_reality(entry, 0.0)
	return entry


func _update_reality(delta: float) -> void:
	for e in _bound:
		var target := 1.0 if e.permanent else _light_amount(e.node.global_position)
		var r: float = move_toward(e.reality, target, reveal_speed * delta)
		if r != e.reality:
			_apply_reality(e, r)


func _apply_reality(e: Dictionary, r: float) -> void:
	var was_solid: bool = e.solid
	e.reality = r
	var node: Node3D = e.node
	# Rise out of the dark water as it becomes real; sink as it forgets itself.
	node.position.y = e.rest_y - (1.0 - r) * 0.7
	node.visible = r > 0.01
	var ease_r := r * r * (3.0 - 2.0 * r)
	for m: BaseMaterial3D in e.mats:
		if r >= 0.999:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.albedo_color.a = ease_r
		# A brief white rim as it crosses into being.
		var flash := clampf(1.0 - absf(r - 0.55) * 6.0, 0.0, 1.0)
		m.emission_enabled = flash > 0.0
		m.emission = Color(1, 1, 1) * flash * 0.6
	var body: CollisionObject3D = e.body
	if body:
		e.solid = r > 0.5
		if e.solid != was_solid:
			body.collision_layer = 1 if e.solid else 0


func _add_stone(p: Vector2, on_path: bool) -> void:
	var stone := RoomLook.make_stone(on_path)
	layout.add_child(stone)
	stone.position = Vector3(p.x, 0.0, p.y)
	stone.rotation.y = randf() * TAU
	var entry := _bind(stone, stone, RoomLook.collect_materials(stone))
	_stone_bodies[stone] = entry


func _set_reach(fire: Node3D, reach: float) -> void:
	var light := fire.find_child("Light", true, false) as OmniLight3D
	if light:
		light.omni_range = reach * 1.6
		light.set_meta(&"base_energy", light.light_energy)


# --- The brand ------------------------------------------------------------------------

func _pick_torch() -> void:
	if torch.visible and not torch_carried:
		RoomLook.puff(self, torch.global_position)
	torch_carried = true
	torch.visible = true
	torch.global_position = _torch_hold_point()
	RoomLook.puff(self, campfire_spot.global_position + Vector3.UP * 0.6)


func _drop_torch() -> void:
	torch_carried = false
	var p := Game.player.global_position
	torch.global_position = Vector3(p.x, p.y + 0.15, p.z) + Game.player.facing * 0.3
	torch.rotation = Vector3(0.0, torch.rotation.y, deg_to_rad(-12.0))
	RoomLook.puff(self, torch.global_position)


func _torch_hold_point() -> Vector3:
	var pl := Game.player
	var side := pl.facing.cross(Vector3.UP).normalized() * -0.32
	var bob := sin(_time * 11.0) * 0.05 if pl.is_walking else 0.0
	return pl.global_position + side + pl.facing * 0.12 + Vector3(0.0, 0.75 + bob, 0.0)


func _carry_torch(delta: float) -> void:
	if not torch_carried:
		return
	var goal := _torch_hold_point()
	var prev := torch.global_position
	torch.global_position = prev.lerp(goal, 1.0 - exp(-18.0 * delta))
	# Lean back against the walk, like a real flame dragged through air.
	var swing := (goal - prev) * 4.0
	torch.rotation.x = lerp(torch.rotation.x, clampf(swing.z, -0.5, 0.5), 0.2)
	torch.rotation.z = lerp(torch.rotation.z, clampf(-swing.x, -0.5, 0.5), 0.2)


# --- Goal -----------------------------------------------------------------------------

func _light_beacon(instant: bool) -> void:
	if beacon_is_lit:
		return
	beacon_is_lit = true
	var fire := RoomLook.make_fire(1.35, true)
	beacon.add_child(fire)
	_set_reach(fire, beacon_reach)
	for e in _bound:
		if e.node.get_meta(&"on_path", false):
			e.permanent = true
	mountain_exit.visible = true
	mountain_exit.enabled = true
	if instant:
		return
	torch_carried = false
	torch.visible = false
	RoomLook.puff(self, beacon_spot.global_position + Vector3.UP * 0.5, 40)
	fire.scale = Vector3.ONE * 0.05
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(fire, "scale", Vector3.ONE, 0.9)
	if is_instance_valid(Game.camera):
		var cam_size := Game.camera.size
		var ct := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ct.tween_property(Game.camera, "size", cam_size * 1.35, 1.4)
		ct.tween_interval(1.6)
		ct.tween_property(Game.camera, "size", cam_size, 1.8)
	beacon_lit.emit()
	complete()


# --- Feel -----------------------------------------------------------------------------

func _footsteps() -> void:
	var pl := Game.player
	var under: Node = null
	if pl.is_on_floor():
		for i in pl.get_slide_collision_count():
			var c := pl.get_slide_collision(i).get_collider()
			if _stone_bodies.has(c):
				under = c
				break
		if under == null:
			under = _last_stone if _last_stone and _stone_bodies.has(_last_stone) and \
				_flat_dist(pl.global_position, (_last_stone as Node3D).global_position) < 0.8 else null
	if under != _last_stone:
		_last_stone = under
		if under:
			var s := under as Node3D
			RoomLook.ripple(self, Vector3(s.global_position.x, -0.3, s.global_position.z))


func _update_glyph() -> void:
	var pos := Game.player.global_position
	var target: Variant = null
	if torch_carried:
		if not beacon_is_lit and _flat_dist(pos, beacon_spot.global_position) < interact_range + 1.2:
			target = beacon_spot.global_position + Vector3.UP * 1.3
	elif torch.visible and _flat_dist(pos, torch.global_position) < interact_range + 0.8:
		target = torch.global_position + Vector3.UP * 0.9
	elif _flat_dist(pos, campfire_spot.global_position) < interact_range + 1.2:
		target = campfire_spot.global_position + Vector3.UP * 1.7
	_glyph.visible = target != null
	if target != null:
		_glyph.global_position = target + Vector3.UP * sin(_time * 4.0) * 0.08
		_glyph.rotation.y = _time * 2.0


func _drown() -> void:
	_drowning = true
	var pl := Game.player
	pl.controls_enabled = false
	if torch_carried:
		torch_carried = false
		var t := create_tween()
		t.tween_property(torch, "global_position:y", torch.global_position.y - 1.5, 0.6)
		t.tween_callback(func(): torch.visible = false)
	RoomLook.ripple(self, Vector3(pl.global_position.x, -0.3, pl.global_position.z), 2.2)
	await get_tree().create_timer(0.5).timeout
	# The lake gives you back to the fire, as if waking up.
	Game.go_to(room_id, &"shore")


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
