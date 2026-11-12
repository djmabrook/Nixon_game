extends Room
## The Watcher's mountain. Rule: things only move when nobody is looking.
##
## The little man crosses an open grid, climbs a staircase as wide as the horizon to the
## Watcher's shoulders, and walks up his tie, a striped road on his chest, to the collar
## under his chin. The face is frozen while any of it is on screen; out of view (looked away
## from, or hidden by a mast or a telephone) it slides toward him over the land. Its stare
## slows him and drains the ink from the picture. Caught, he turns to a small grey statue,
## the world flashes to the Negative, and the moment rewinds.
##
## The three inks he carried home are his only shelter:
##   ember   (tap interact)  plant a fire; inside its light the face cannot move, even unseen.
##   salmon  (walking)       pink footing blooms under his feet and holds against the land's
##                            slide toward the face. Stand still and he slides.
##   crimson (hold interact) lay the black disc; standing on it is a blind spot for the stare.
##
## The ending: at the knot under his chin, he raises the ember (tap interact). The lids come
## down, the red targets go out, the drone and heartbeat stop and the ultraviolet drains from
## the sky. He walks on past the face, off screen and behind him, and nothing moves. The black
## disc beyond the head takes him home.

const BRAND := preload("res://rooms/watching_face/models/brand.glb")

const INK_EMBER := &"ember"
const INK_SALMON := &"salmon"
const INK_CRIMSON := &"crimson"

## Speed multiplier at full stare (walk and run).
@export_range(0.1, 1.0) var stare_slow := 0.38
## Seconds of the stone-and-Negative beat before the rewind.
@export var catch_reset_delay := 2.0

@export_group("Inks")
## Most fires that can burn at once; planting another moves the oldest.
@export var max_fires := 3
## Radius of a fire's light, in metres.
@export var fire_radius := 40.0
## Radius of the laid black disc.
@export var disc_radius := 7.0
## Seconds interact must be held to lay the disc instead of planting a fire.
@export var hold_to_lay := 0.45
## Speed of the land's slide toward the face: far away, and right under it (m/s).
@export var slide_far := 0.6
@export var slide_near := 3.2

@onready var face: FaceBoss = $FaceBoss
@onready var land: Node3D = $Landscape
@onready var foot: Area3D = $Foot
@onready var exit_disc: Area3D = $ExitDisc/Goal
@onready var exit_ring: Node3D = $ExitDisc/Ring
@onready var floor_mat: ShaderMaterial = $Floor/Mesh.material_override
@onready var vignette_mat: ShaderMaterial = $Screen/Vignette.material
@onready var negative: ColorRect = $Screen/Negative
@onready var synth: AudioStreamPlayer = $Synth

var _base_walk := 5.0
var _base_run := 10.0
var _shake := 0.0
var _flash := 0.0
var _caught := false
var _at_foot := false
var _ended := false
var _leaving := false
var _press_time := -1.0
var _fires: Array[Node3D] = []
var _disc: Node3D
var _last_tile := Vector3.INF
var _effective_stare := 0.0
var _sky_mat: ShaderMaterial


func _ready() -> void:
	# Each room instance gets its own copies so state never leaks across reloads.
	floor_mat = floor_mat.duplicate()
	$Floor/Mesh.material_override = floor_mat
	vignette_mat = vignette_mat.duplicate()
	$Screen/Vignette.material = vignette_mat
	negative.material = negative.material.duplicate()
	negative.visible = false
	var env: Environment = $WorldEnvironment.environment
	_sky_mat = env.sky.sky_material
	_sky_mat.set_shader_parameter(&"awake", 1.0)
	face.ground_provider = land.ground_height


func _on_room_entered(_spawn: StringName) -> void:
	_base_walk = Game.player.move_speed
	_base_run = Game.player.run_speed
	face.caught_player.connect(_on_caught)
	face.revealed.connect(_on_revealed)
	foot.body_entered.connect(_on_foot_body.bind(true))
	foot.body_exited.connect(_on_foot_body.bind(false))
	exit_disc.body_entered.connect(_on_exit_disc_entered)
	floor_mat.set_shader_parameter(&"face_radius", face.head_radius())
	# The reveal: pull far back so he is a speck on the grid, and the Watcher opens his eyes.
	face.open_eyes(3.0)
	if DisplayServer.get_name() != "headless":
		Game.camera.play_vista(face.centre(), 80.0, 2.5, 2.5)


## True if the little man has brought this ink home. The room is locked until all three
## are, so in play this is always true; it keeps each shelter tied to its ink.
func has_ink(ink: StringName) -> bool:
	return Game.is_ink_home(ink)


# --- Input: tap plants the ember (or raises it at his foot), hold lays the disc --------

func _unhandled_input(event: InputEvent) -> void:
	if _caught or _leaving:
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_press_time = 0.0
	elif event.is_action_released(&"interact") and _press_time >= 0.0:
		get_viewport().set_input_as_handled()
		if _press_time < hold_to_lay:
			tap()
		_press_time = -1.0


## A short press: raise the ember at his foot, otherwise plant a fire.
func tap() -> void:
	if _at_foot and not _ended and has_ink(INK_EMBER):
		raise_ember()
	elif not _ended:
		plant_fire()


func plant_fire() -> void:
	if not has_ink(INK_EMBER):
		return
	var fire: Node3D
	if _fires.size() >= max_fires:
		fire = _fires.pop_front()
	else:
		fire = _make_fire()
		add_child(fire)
	fire.global_position = Game.player.global_position
	_fires.append(fire)
	synth.sting(0.15)


func lay_disc() -> void:
	if not has_ink(INK_CRIMSON):
		return
	if _disc == null:
		_disc = _make_disc()
		add_child(_disc)
	_disc.global_position = Game.player.global_position + Vector3.UP * 0.05
	_disc.scale = Vector3.ONE * 0.05
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(_disc, "scale", Vector3.ONE, 0.4)


func is_in_firelight(p: Vector3) -> bool:
	for f in _fires:
		if Vector2(f.global_position.x - p.x, f.global_position.z - p.z).length() < fire_radius:
			return true
	return false


func is_on_disc(p: Vector3) -> bool:
	return _disc != null and Vector2(_disc.global_position.x - p.x, _disc.global_position.z - p.z).length() < disc_radius


# --- Every frame -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var player := Game.player
	if not is_instance_valid(player) or _caught or Game.is_travelling():
		return
	if _press_time >= 0.0:
		_press_time += delta
		if _press_time >= hold_to_lay and _press_time - delta < hold_to_lay:
			lay_disc()
	if _ended:
		return

	# Ember: inside its light the face cannot move, seen or not.
	face.held = is_in_firelight(player.global_position)

	# Salmon: the land slides toward the face. Pink footing blooms while he walks and holds.
	var holding := player.is_walking and has_ink(INK_SALMON)
	if holding:
		if player.global_position.distance_to(_last_tile) > 2.4:
			_last_tile = player.global_position
			_bloom_tile(player.global_position)
	elif player.is_on_floor():
		var to_face := face.global_position - player.global_position
		to_face.y = 0.0
		if to_face.length() > 1.0:
			var speed := lerpf(slide_far, slide_near, _proximity())
			player.move_and_collide(to_face.normalized() * speed * delta)


func _process(delta: float) -> void:
	var player := Game.player
	if not is_instance_valid(player) or not is_instance_valid(face):
		return
	var proximity := _proximity()

	# Crimson: on the disc the stare falls into a blind spot.
	_effective_stare = 0.0 if is_on_disc(player.global_position) or _ended else face.stare
	if player.controls_enabled:
		var k := lerpf(1.0, stare_slow, _effective_stare)
		player.move_speed = _base_walk * k
		player.run_speed = _base_run * k

	# The stare drains the ink from the picture (the dither shader's hook), or darkens the edges.
	var look := get_tree().get_first_node_in_group(&"dither_look")
	if look:
		look.set(&"drain", _effective_stare)
	_flash = move_toward(_flash, 0.0, delta * 1.5)
	vignette_mat.set_shader_parameter(&"stare", maxf(_effective_stare * (0.3 if look else 0.8), proximity * 0.5))
	vignette_mat.set_shader_parameter(&"flash", _flash)

	floor_mat.set_shader_parameter(&"face_pos", face.global_position)
	floor_mat.set_shader_parameter(&"face_motion", face.motion)
	floor_mat.set_shader_parameter(&"stare", _effective_stare)

	synth.motion = face.motion
	synth.stare = _effective_stare
	synth.proximity = proximity
	synth.ring = 0.0 if _ended or face.sees_player else _nearest_phone_closeness(player.global_position)

	_turn_mics(player, delta)
	exit_ring.rotate_object_local(Vector3.UP, delta * 0.3)
	for f in _fires:
		var light := f.get_node(^"Light") as OmniLight3D
		light.light_energy = 6.0 + sin(Time.get_ticks_msec() * 0.013 + f.position.x) * 1.2 + randf() * 0.6
	_apply_shake(delta, proximity)

	if player.global_position.y < -40.0 and not Game.is_travelling():
		_reset()


func _proximity() -> float:
	var dist := face.flat_distance_to(Game.player.global_position)
	return clampf(1.0 - (dist - face.catch_radius) / 900.0, 0.0, 1.0)


## Microphones swivel toward his footsteps.
func _turn_mics(player: Player, delta: float) -> void:
	if not player.is_walking:
		return
	for head: Node3D in land.mic_heads:
		var d := player.global_position - head.global_position
		if Vector2(d.x, d.z).length() > 160.0:
			continue
		var want := atan2(-d.x, -d.z)
		head.global_rotation.y = lerp_angle(head.global_rotation.y, want, clampf(delta * 0.8, 0.0, 1.0))


## Telephones ring when he is out of the Watcher's sight. 1 = right beside one.
func _nearest_phone_closeness(p: Vector3) -> float:
	var best := 0.0
	for phone: Node3D in land.telephones:
		var d := phone.global_position.distance_to(p)
		best = maxf(best, 1.0 - d / 90.0)
	return best


func _apply_shake(delta: float, proximity: float) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	var amount := _shake * _shake * 0.35 + proximity * proximity * face.motion * 0.08
	cam.h_offset = randf_range(-amount, amount)
	cam.v_offset = randf_range(-amount, amount)


# --- Events ----------------------------------------------------------------------

func _on_revealed(distance: float) -> void:
	var strength := clampf(distance / 150.0, 0.2, 1.0)
	_shake = maxf(_shake, 0.4 + 0.5 * strength)
	_flash = maxf(_flash, 0.3 * strength)
	synth.sting(strength)


func _on_caught() -> void:
	if _caught or _ended:
		return
	_caught = true
	var player := Game.player
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	# He stiffens into a small grey statue, a monument like the Watcher.
	_turn_to_stone(player)
	face.lunge(player.global_position)
	synth.slam()
	_shake = 1.0
	# The world seen from inside the stare: the Negative, for a beat.
	negative.visible = true
	await get_tree().create_timer(0.7).timeout
	negative.visible = false
	await get_tree().create_timer(maxf(catch_reset_delay - 0.7, 0.0)).timeout
	_reset()


## The ending: firelight climbs the stone and, for the first time, he is the one seen.
func raise_ember() -> void:
	if _ended:
		return
	_ended = true
	face.held = true
	face.close_eyes(3.0)
	var fire := _make_fire()
	add_child(fire)
	fire.global_position = Game.player.global_position + Vector3.UP * 2.0
	var light := fire.get_node(^"Light") as OmniLight3D
	create_tween().tween_property(light, "omni_range", 400.0, 3.0)
	Game.camera.play_shot(Game.player.global_position + Vector3(30, 8, 40), face.centre(), 3.0, 2.0)
	create_tween().tween_property(synth, "volume_db", -80.0, 4.0)
	create_tween().tween_method(func(v): _sky_mat.set_shader_parameter(&"awake", v), 1.0, 0.0, 6.0)


func _on_foot_body(body: Node3D, inside: bool) -> void:
	if body is Player:
		_at_foot = inside


func _on_exit_disc_entered(body: Node3D) -> void:
	if not body is Player or not _ended or _leaving:
		return
	_leaving = true
	complete()
	await get_tree().create_timer(1.0).timeout
	exit_to_hub()


func _reset() -> void:
	Game.go_to(room_id, &"from_hub")


func _turn_to_stone(player: Player) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.55, 0.58)
	stone.roughness = 1.0
	for mi in player.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = stone


# --- Ink props (placeholders) --------------------------------------------------------

func _make_fire() -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	# The brand from the art: a charred stick with a faceted flame, planted upright.
	var brand := BRAND.instantiate() as Node3D
	brand.scale = Vector3.ONE * 2.0
	root.add_child(brand)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 6.0
	light.omni_range = fire_radius
	light.omni_attenuation = 0.6
	light.position.y = 2.0
	root.add_child(light)
	# A faint ring on the ground marks the edge of safe light.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = fire_radius - 0.4
	tm.outer_radius = fire_radius
	tm.rings = 96
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.5, 0.2, 0.35)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = rm
	ring.mesh = tm
	ring.scale.y = 0.05
	root.add_child(ring)
	return root


func _make_disc() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "BlindSpot"
	var cm := CylinderMesh.new()
	cm.top_radius = disc_radius
	cm.bottom_radius = disc_radius
	cm.height = 0.05
	cm.radial_segments = 48
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	cm.material = mat
	mi.mesh = cm
	return mi


func _bloom_tile(at: Vector3) -> void:
	var tile := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.8, 1.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.98, 0.56, 0.48, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.material = mat
	tile.mesh = pm
	add_child(tile)
	tile.global_position = at + Vector3.UP * 0.12
	tile.rotation.y = snappedf(Game.player.visual.rotation.y, PI * 0.5)
	tile.scale = Vector3.ONE * 0.2
	var t := create_tween()
	t.tween_property(tile, "scale", Vector3.ONE, 0.2)
	t.tween_interval(1.6)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	t.tween_callback(tile.queue_free)
