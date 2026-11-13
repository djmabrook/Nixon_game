extends Room
## The Red Grid. A crimson wire plain sags under the Watcher's pupil, a black disc 3 km wide
## hanging 900 m up. Walking into its shadow is an eclipse that lasts minutes, and fog pours
## down the sag into the dark.
##
## The rule it breaks: holes are objects. Small black discs lie on the plain. He picks them
## up and carries them, and wherever he lays one the ground there is gone (step in and the
## hole spits him back out). Laid in the six sockets around the bottom of the sag, they cut
## the pressed circle free. It falls away, the grid springs level, fog rises and closes over
## the pupil like a lid, and one small disc comes back up for him to carry home (crimson).
##
## Everything big is built in code from the constants below; room.tscn holds the contract
## nodes (spawn, exit, environment, sun, the television).

const Sfx := preload("res://rooms/red_grid/room_sfx.gd")

enum State { PLAYING, MENDING, MENDED }
enum HoleState { LOOSE, CARRIED, LAID, SOCKET, GONE }

const SAG_DEPTH := 220.0
const SAG_RADIUS := 800.0
const PUPIL_Y := 900.0
const PUPIL_R := 1500.0
const PLUG_R := 36.0
const SOCKET_ANGLE0 := PI / 6.0
const HOLE_R := 0.62
const NEAR_SIZE := 1600.0
const NEAR_CELLS := 160
const SHADOW_INNER := 1050.0
const SHADOW_OUTER := 1900.0

## Where the six loose discs lie (x, z). Heights come from the sag. They lead from the
## television near the spawn, through the eclipse, over the rim and down the slope.
const LOOSE_AT: Array[Vector2] = [
	Vector2(10, 1700), Vector2(-130, 1390), Vector2(160, 1100),
	Vector2(-240, 830), Vector2(250, 560), Vector2(-110, 300),
]

## Extra speed walking down into the sag (the stare pulls).
@export var downhill_assist := 0.45
## How much the stare slows him at the bottom before any socket is filled.
@export var stare_weight := 0.6
## Seconds per cinematic beat are multiplied by this (tests run it fast).
@export var cinematic_speed := 1.0

## Read by the dither post-process when it exists (shaders/dither_look.gd).
var dither_look: Resource

var state := State.PLAYING
var sag := SAG_DEPTH
var holes: Array[Dictionary] = []
var sockets: Array[Vector3] = []
var socket_hole: Array[int] = [-1, -1, -1, -1, -1, -1]
var carried: Array[int] = []

var _grid_mats: Array[ShaderMaterial] = []
var _eye_mat: ShaderMaterial
var _beam_mat: ShaderMaterial
var _lid_mat: ShaderMaterial
var _horizon_mat: ShaderMaterial
var _fall_mats: Array[ShaderMaterial] = []
var _sky_mat: ShaderMaterial
var _hole_mat: ShaderMaterial
var _wisp_mesh: ArrayMesh
var _pupil: MeshInstance3D
var _beam: MeshInstance3D
var _socket_marks: Array[MeshInstance3D] = []
var _ground_shape: CollisionShape3D
var _env: Environment
var _sfx: Sfx
var _sound: Node
var _rumble: Node
var _dither: Node
var _base_walk := 5.0
var _base_run := 10.0
var _eclipse := 0.0
var _lid := 0.0
var _flinch := 0.0
var _wave_age := 100.0
var _vista_pupil_done := false
var _vista_bowl_done := false
var _busy := false
var _exiting := false

@onready var _sun: DirectionalLight3D = $Sun
@onready var _tv: WatchingSet = $WatchingSet


func _init() -> void:
	dither_look = _make_look()


func _ready() -> void:
	_env = ($WorldEnvironment as WorldEnvironment).environment
	_setup_sound()
	_build_sky()
	_build_grid()
	_build_eye()
	_build_fog()
	_build_horizon()
	_build_sockets()
	_build_exit_hole()
	if Game.is_completed(room_id):
		_apply_mended()
	else:
		for at in LOOSE_AT:
			_add_hole(Vector3(at.x, sag_height(at, SAG_DEPTH), at.y), HoleState.LOOSE)
	_push_holes()


func _on_room_entered(_spawn: StringName) -> void:
	_base_walk = Game.player.move_speed
	_base_run = Game.player.run_speed
	_dither = get_tree().get_first_node_in_group(&"dither_look")


## Ground height of the sag at (x, z) for a given depth. Matches grid.gdshader.
static func sag_height(xz: Vector2, depth: float) -> float:
	var t := clampf(xz.length() / SAG_RADIUS, 0.0, 1.0)
	var s := 1.0 - t * t
	return -depth * s * s


# --- Per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	_wave_age += delta
	_flinch = move_toward(_flinch, 0.0, delta * 0.8)
	var player := Game.player
	var at := Vector2.ZERO
	if is_instance_valid(player):
		at = Vector2(player.global_position.x, player.global_position.z)
	var lit := smoothstep(SHADOW_INNER, SHADOW_OUTER, at.length())
	lit = lerpf(lit, 1.0, _lid * 0.8)
	_eclipse = 1.0 - lit

	# The pupil breathes, and flinches when a hole is laid in its sight.
	var dilate := 1.0 + 0.012 * sin(Time.get_ticks_msec() / 1000.0 * 0.7) - 0.05 * _flinch
	_pupil.scale = Vector3(dilate, 1.0, dilate)
	_eye_mat.set_shader_parameter(&"pupil_radius", PUPIL_R * dilate)
	_eye_mat.set_shader_parameter(&"eclipse", _eclipse)

	_sky_mat.set_shader_parameter(&"eclipse", _eclipse)
	_env.fog_light_color = Color(0.86, 0.66, 0.64).lerp(Color(0.10, 0.012, 0.022), _eclipse)
	_env.fog_density = lerpf(0.00045, 0.0011, _eclipse)
	_env.ambient_light_energy = lerpf(0.9, 0.25, _eclipse)
	_sun.light_energy = lerpf(1.0, 0.08, _eclipse)
	_horizon_mat.set_shader_parameter(&"darkness", _eclipse * 0.9)
	for m in _fall_mats:
		m.set_shader_parameter(&"light", 1.0 - _eclipse * 0.6)
	_grid_set(&"wave_age", _wave_age)

	for i in _socket_marks.size():
		var mark := _socket_marks[i]
		mark.visible = socket_hole[i] < 0 and state == State.PLAYING
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 3.0 + i)
		mark.scale = Vector3(pulse, 1.0, pulse)

	if _sfx:
		_sfx.drone.volume_db = lerpf(-30.0, -9.0, _eclipse) if _lid < 0.5 else -40.0
		_sfx.wind.volume_db = lerpf(-14.0, -34.0, _eclipse)
	if _rumble:
		# The pupil's weight, felt more the deeper he goes into the sag.
		var depth := 0.0
		if is_instance_valid(player):
			depth = clampf(-player.global_position.y / SAG_DEPTH, 0.0, 1.0)
		_rumble.set(&"intensity", (0.15 + depth * 0.85) * (1.0 - _lid))

	if not is_instance_valid(player) or state == State.MENDING:
		return
	_update_weight(player, at)
	_check_vistas(player, at)


func _physics_process(_delta: float) -> void:
	var player := Game.player
	if not is_instance_valid(player) or _busy or state == State.MENDING:
		return
	var at := Vector2(player.global_position.x, player.global_position.z)
	if state == State.MENDED:
		if not _exiting and player.global_position.y < -6.0:
			_exiting = true
			exit_to_hub()
		return
	for i in holes.size():
		var h := holes[i]
		var flat := Vector2(h.pos.x, h.pos.z)
		var d := at.distance_to(flat)
		match h.state:
			HoleState.LOOSE:
				if d < 1.5 and absf(player.global_position.y - h.pos.y) < 2.5:
					pick_up(i)
			HoleState.LAID, HoleState.SOCKET:
				if d < HOLE_R - 0.12 and player.is_on_floor():
					_fall_into(i)
					return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and state == State.PLAYING and not _busy:
		if interact():
			get_viewport().set_input_as_handled()


## The stare's weight at the bottom of the sag slows him; the slope speeds him inward.
## A laid hole nearby is a blind spot: the stare falls into it.
func _update_weight(player: Player, at: Vector2) -> void:
	var r := at.length()
	var filled := socket_hole.filter(func(x): return x >= 0).size()
	var w := (1.0 - smoothstep(60.0, 300.0, r)) * (1.0 - filled / 6.0 * 0.75)
	for h in holes:
		if h.state == HoleState.LAID or h.state == HoleState.SOCKET:
			if at.distance_to(Vector2(h.pos.x, h.pos.z)) < 9.0:
				w = 0.0
				break
	w *= 1.0 - _lid
	var mult := 1.0 - stare_weight * w
	if r < SAG_RADIUS and r > 1.0:
		var t := r / SAG_RADIUS
		var slope := 4.0 * t * (1.0 - t * t) # |d sag / d r| / (depth / radius), max ~1.54
		var inward := maxf(0.0, player.facing.dot(Vector3(-at.x, 0.0, -at.y) / r))
		mult += downhill_assist * slope / 1.54 * inward * float(player.is_walking)
	player.move_speed = _base_walk * mult
	player.run_speed = _base_run * mult
	if _dither and _dither.get(&"drain") != null:
		_dither.set(&"drain", w * 0.55)
	if _sound:
		_sound.call(&"set_stare", w * 0.6)


func _check_vistas(player: Player, at: Vector2) -> void:
	if not is_instance_valid(Game.camera) or Game.camera.is_in_shot():
		return
	if not _vista_pupil_done and at.length() < 1660.0:
		_vista_pupil_done = true
		_vista(Vector3(0, PUPIL_Y - 60.0, 0), 70.0, 3.5)
	elif not _vista_bowl_done and at.length() < 830.0:
		_vista_bowl_done = true
		_vista(Vector3(0, -SAG_DEPTH, 0), 95.0, 3.0)


func _vista(target: Vector3, pull: float, hold: float) -> void:
	var player := Game.player
	player.controls_enabled = false
	await Game.camera.play_vista(target, pull, hold * cinematic_speed, 2.5 * cinematic_speed)
	if is_instance_valid(player) and state == State.PLAYING:
		player.controls_enabled = true


# --- The rule: holes are objects ---------------------------------------------

## What the interact button does here. Returns true if it did something.
## Near a laid hole: pick it back up. Carrying, near an empty socket: lay it in the socket.
## Carrying anywhere else: lay it on the ground a step ahead.
func interact() -> bool:
	var player := Game.player
	if not is_instance_valid(player):
		return false
	var at := Vector2(player.global_position.x, player.global_position.z)
	for i in holes.size():
		if holes[i].state == HoleState.LAID and at.distance_to(Vector2(holes[i].pos.x, holes[i].pos.z)) < 2.6:
			pick_up(i)
			return true
	if carried.is_empty():
		return false
	var best := -1
	var best_d := 8.0
	for s in sockets.size():
		if socket_hole[s] >= 0:
			continue
		var d := at.distance_to(Vector2(sockets[s].x, sockets[s].z))
		if d < best_d:
			best_d = d
			best = s
	if best >= 0:
		lay_in_socket(best)
		return true
	var ahead := at + Vector2(player.facing.x, player.facing.z).normalized() * 1.9
	for h in holes:
		if h.state in [HoleState.LAID, HoleState.SOCKET] and ahead.distance_to(Vector2(h.pos.x, h.pos.z)) < HOLE_R * 2.2:
			return false
	lay_at(ahead)
	return true


## Lift a loose or laid hole onto his back.
func pick_up(i: int) -> void:
	var h := holes[i]
	if h.state != HoleState.LOOSE and h.state != HoleState.LAID:
		return
	_set_hole_state(i, HoleState.CARRIED)
	carried.append(i)
	_push_holes()
	_play(&"pick", -4.0, randf_range(0.95, 1.08))
	var node: Node3D = h.node
	node.reparent(Game.player.visual, true)
	_restack()


## Lay the top hole of his stack on the ground at (x, z).
func lay_at(xz: Vector2) -> void:
	if carried.is_empty():
		return
	var i: int = carried.pop_back()
	var pos := Vector3(xz.x, sag_height(xz, sag), xz.y)
	_place_hole(i, pos, HoleState.LAID)
	_play(&"lay", -3.0, randf_range(0.9, 1.05))
	_flinch = 1.0
	_wave(xz, 0.35)


## Lay the top hole of his stack into socket `s`. The sixth one cuts the circle free.
func lay_in_socket(s: int) -> void:
	if carried.is_empty() or socket_hole[s] >= 0:
		return
	var i: int = carried.pop_back()
	socket_hole[s] = i
	holes[i].socket = s
	_place_hole(i, sockets[s], HoleState.SOCKET)
	_grid_set_socket(s, 1.0)
	var filled := socket_hole.filter(func(x): return x >= 0).size()
	_play(StringName("socket%d" % (filled - 1)), -2.0, 1.0, sockets[s])
	_flinch = 1.0
	_wave(Vector2(sockets[s].x, sockets[s].z), 1.0)
	if is_instance_valid(_tv):
		_tv.droop(filled / 6.0 * 0.85)
	if filled == sockets.size():
		mend()


func _place_hole(i: int, pos: Vector3, st: HoleState) -> void:
	var h := holes[i]
	var node: Node3D = h.node
	node.reparent(self, true)
	h.pos = pos
	_set_hole_state(i, st)
	_push_holes()
	_restack()
	var t := node.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "global_position", pos + Vector3.UP * 0.02, 0.35)
	t.tween_property(node, "global_rotation", Vector3.ZERO, 0.3)
	t.tween_property(node, "scale", Vector3.ONE, 0.3)


## Discs on his back, fanned like records, the newest on top.
func _restack() -> void:
	for n in carried.size():
		var node: Node3D = holes[carried[n]].node
		var slot := Vector3(0.0, 1.05 + n * 0.07, 0.27 + n * 0.035)
		var rot := Vector3(PI / 2.0, 0.0, (n - carried.size() * 0.5) * 0.22)
		var t := node.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(node, "position", slot, 0.45)
		t.tween_property(node, "rotation", rot, 0.45)
		t.tween_property(node, "scale", Vector3.ONE * 0.62, 0.45)


## He stepped onto a hole. It swallows him, then spits him back out beside it,
## and a hole he laid himself comes back with him. Failure is never death.
func _fall_into(i: int) -> void:
	_busy = true
	var player := Game.player
	var h := holes[i]
	var hole_pos: Vector3 = h.pos
	var lip := Vector3(hole_pos.x, 0.0, hole_pos.z)
	var away := (player.global_position - lip)
	away.y = 0.0
	if away.length() < 0.05:
		away = -player.facing
	away = away.normalized()
	player.controls_enabled = false
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	_play(&"swallow", -2.0)
	var down := player.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(player, "global_position", hole_pos + Vector3.DOWN * 7.0, 0.55)
	await down.finished
	await get_tree().create_timer(0.7 * cinematic_speed).timeout
	_play(&"spit", -2.0)
	var land := hole_pos + away * 2.6
	land.y = sag_height(Vector2(land.x, land.z), sag)
	var up := player.create_tween()
	up.tween_method(func(w: float):
		var p := (hole_pos + Vector3.DOWN * 7.0).lerp(land, w)
		p.y += sin(w * PI) * 4.5
		player.global_position = p, 0.0, 1.0, 0.7)
	await up.finished
	if is_instance_valid(player):
		player.set_physics_process(true)
		player.controls_enabled = true
		player.face(away)
	if h.state == HoleState.LAID:
		pick_up(i)
	_busy = false


# --- The mend ----------------------------------------------------------------

## The ring is complete: cut the pressed circle free, let the grid spring level,
## close the fog over the pupil and hand him the crimson disc.
func mend() -> void:
	if state != State.PLAYING:
		return
	state = State.MENDING
	var player := Game.player
	var cam := Game.camera
	var k := cinematic_speed
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	if _sound:
		_sound.set(&"footsteps_enabled", false)

	# Step back out of the circle if he is standing in it.
	var at := Vector2(player.global_position.x, player.global_position.z)
	if at.length() < PLUG_R + 5.0:
		var out := (at.normalized() if at.length() > 0.5 else Vector2(0, 1)) * (PLUG_R + 7.0)
		var back := player.create_tween()
		back.tween_property(player, "global_position", Vector3(out.x, -SAG_DEPTH + 0.05, out.y), 0.8 * k)
		await back.finished
	player.set_physics_process(false)

	# 1. The cut runs around the ring.
	_play(&"cut", 0.0, 1.0, Vector3(0, -SAG_DEPTH, 0))
	var flash := create_tween()
	flash.tween_method(func(v: float): _grid_set(&"cut_flash", v), 0.0, 1.0, 0.25 * k)
	flash.tween_method(func(v: float): _grid_set(&"cut_flash", v), 1.0, 0.0, 1.2 * k)
	_wave(Vector2.ZERO, 1.5)
	var bottom := Vector3(0, -SAG_DEPTH, 0)
	var me := player.global_position
	var side := Vector3(me.x, 0, me.z).normalized() if Vector2(me.x, me.z).length() > 1.0 else Vector3.BACK
	if cam:
		cam.play_shot(me + side * 22.0 + Vector3.UP * 20.0, bottom + Vector3.DOWN * 25.0 - side * 10.0, 9.0 * k, 1.6 * k)
	await get_tree().create_timer(1.6 * k).timeout

	# 2. The pressed circle falls away, taking the six discs with it.
	var plug := _make_plug()
	for s in sockets.size():
		var hi := socket_hole[s]
		if hi >= 0:
			(holes[hi].node as Node3D).reparent(plug, true)
			_set_hole_state(hi, HoleState.GONE)
	_grid_set(&"plug_gone", 1.0)
	_push_holes()
	_play(&"fall", 0.0, 1.0, Vector3(0, -SAG_DEPTH, 0))
	var fall := create_tween().set_parallel()
	fall.tween_property(plug, "position:y", -SAG_DEPTH - 900.0, 9.0 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(plug, "rotation", Vector3(0.25, 0.6, -0.15), 9.0 * k)
	fall.tween_method(func(v: float): (plug.material_override as ShaderMaterial).set_shader_parameter(&"fade", v), 1.0, 0.0, 7.0 * k)
	await get_tree().create_timer(3.4 * k).timeout

	# 3. Nothing left to press on: the grid springs level and flings the fog upward.
	if cam:
		cam.play_shot(Vector3(520, 140, 760), Vector3(0, -70, 0), 6.0 * k, 1.2 * k)
	await get_tree().create_timer(1.0 * k).timeout
	_play(&"spring", 0.0, 1.0, Vector3(0, -SAG_DEPTH * 0.5, 0))
	_set_ground_level()
	for m in _fall_mats:
		create_tween().tween_method(func(v: float): m.set_shader_parameter(&"rise", v), 0.0, 1.0, 3.0 * k)
	create_tween().tween_method(func(v: float): _beam_mat.set_shader_parameter(&"cut", v), 0.0, 1.05, 2.5 * k)
	var spring := create_tween()
	spring.tween_method(func(t: float):
		_set_sag(SAG_DEPTH * exp(-1.05 * t) * cos(3.3 * t) if t < 5.9 else 0.0)
		if is_instance_valid(player):
			var p := player.global_position
			player.global_position = Vector3(p.x, sag_height(Vector2(p.x, p.z), sag) + 0.02, p.z), 0.0, 6.0, 6.0 * k)
	await spring.finished
	_set_sag(0.0)
	_beam.visible = false

	# 4. Fog rises and closes over the pupil like a lid. Light comes back.
	me = player.global_position
	if cam:
		cam.play_shot(me + side * 14.0 + Vector3.UP * 3.0, Vector3(0, PUPIL_Y, 0) + side * 200.0, 6.5 * k, 1.8 * k)
	await get_tree().create_timer(1.2 * k).timeout
	_play(&"lid", 0.0, 1.0, Vector3(0, PUPIL_Y - 70.0, 0))
	var lid := create_tween()
	lid.tween_method(func(v: float): _lid_mat.set_shader_parameter(&"presence", v), 0.0, 1.0, 1.5 * k)
	lid.tween_method(func(v: float):
		_lid_mat.set_shader_parameter(&"close", v)
		_eye_mat.set_shader_parameter(&"shut", v)
		_set_lid(v), 0.0, 1.0, 5.0 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await lid.finished
	await get_tree().create_timer(1.6 * k).timeout

	# 5. One small disc comes back up out of the hole and goes to him: the crimson ink.
	var ink := _make_hole_node(1.0)
	add_child(ink)
	ink.global_position = Vector3(0, -40, 0)
	ink.scale = Vector3.ONE * 0.6
	_play(&"ink", -2.0)
	var rise := create_tween()
	rise.tween_property(ink, "global_position", Vector3(0, 3.0, 0), 2.2 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.parallel().tween_property(ink, "rotation", Vector3(PI / 2.0, 0.0, 0.0), 2.2 * k)
	rise.tween_property(ink, "global_position", player.global_position + Vector3.UP * 1.1, 1.4 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await rise.finished
	ink.queue_free()
	if _sound:
		_sound.call(&"play", &"mend")

	state = State.MENDED
	complete()
	if _sound:
		_sound.set(&"footsteps_enabled", true)
		_sound.call(&"set_stare", 0.0)
	if is_instance_valid(player):
		player.set_physics_process(true)
		player.controls_enabled = true
		player.move_speed = _base_walk
		player.run_speed = _base_run
	if _dither and _dither.get(&"drain") != null:
		_dither.set(&"drain", 0.0)


## Already mended (coming back later): level grid, open hole, lid shut, no stare.
func _apply_mended() -> void:
	state = State.MENDED
	_set_sag(0.0)
	_set_ground_level()
	_grid_set(&"plug_gone", 1.0)
	for s in 6:
		_grid_set_socket(s, 0.0)
	_beam.visible = false
	_lid_mat.set_shader_parameter(&"presence", 1.0)
	_lid_mat.set_shader_parameter(&"close", 1.0)
	_eye_mat.set_shader_parameter(&"shut", 1.0)
	for m in _fall_mats:
		m.set_shader_parameter(&"rise", 1.0)
	_set_lid(1.0)


func _set_lid(v: float) -> void:
	_lid = v
	_grid_set(&"lid", v)


func _set_sag(v: float) -> void:
	sag = v
	_grid_set(&"sag_depth", v)


# --- Sound ---------------------------------------------------------------------

## Uses the game's sound system (audio/, the `Sound` autoload) when it is in the project:
## bed_grid air, stone steps, a giant rumble under the pupil and the shared library.
## Without it, the room falls back to its own small synth (room_sfx.gd).
func _setup_sound() -> void:
	_sound = get_node_or_null(^"/root/Sound")
	if _sound == null or not ResourceLoader.exists("res://audio/room_audio.gd"):
		_sfx = Sfx.new()
		_sfx.name = "Sfx"
		add_child(_sfx)
		return
	var cfg: Node = (load("res://audio/room_audio.gd") as Script).new()
	cfg.name = "RoomAudio"
	cfg.set(&"bed", &"bed_grid")
	cfg.set(&"surface", &"stone")
	cfg.set(&"lateness", 1.8)
	cfg.set(&"far_room_size", 1.0)
	cfg.set(&"far_wet", 0.4)
	add_child(cfg)
	if ResourceLoader.exists("res://audio/giant_voice.gd"):
		_rumble = (load("res://audio/giant_voice.gd") as Script).new()
		_rumble.name = "PupilRumble"
		_rumble.set(&"sound_id", &"giant_rumble")
		_rumble.set(&"size_m", 1500.0)
		_rumble.set(&"intensity", 0.15)
		add_child(_rumble)
		(_rumble as Node3D).position = Vector3(0, -SAG_DEPTH + 40.0, 0)


## Library ids for each moment when the sound system is present.
const LIBRARY := {
	&"pick": [&"pickup"], &"lay": [&"putdown"], &"swallow": [&"rewind"], &"spit": [&"wake"],
	&"cut": [&"giant_grind", 300.0], &"fall": [&"giant_boom", 800.0],
	&"spring": [&"giant_groan", 1500.0], &"lid": [&"eyelids_close", 1500.0],
	&"ink": [&"ink_crimson_take"],
}


func _play(key: StringName, volume_db := 0.0, pitch := 1.0, at: Variant = null) -> void:
	if _sfx:
		_sfx.play(key, volume_db, pitch)
		return
	if String(key).begins_with("socket"):
		# A disc seats with a thud the whole bowl hears.
		_sound.call(&"play", &"putdown", volume_db, pitch)
		_sound.call(&"giant", &"giant_settle", at, 60.0, volume_db - 4.0)
		return
	var entry: Array = LIBRARY.get(key, [])
	if entry.is_empty():
		return
	if entry.size() > 1 and at is Vector3:
		_sound.call(&"giant", entry[0], at, entry[1], volume_db)
	else:
		_sound.call(&"play", entry[0], volume_db, pitch)


# --- Building ------------------------------------------------------------------

func _make_look() -> Resource:
	var path := "res://shaders/dither_look_settings.gd"
	if not ResourceLoader.exists(path):
		return null
	var s: Resource = (load(path) as Script).new()
	s.resource_name = "red_grid"
	s.set(&"palette", PackedColorArray([
		Color("0d0b0a"), Color("2a050b"), Color("5c0814"), Color("9a0c24"), Color("c8102e"),
		Color("e0485a"), Color("e9a3a0"), Color("efe6d8"),
	]))
	s.set(&"virtual_height", 360)
	s.set(&"dither_spread", 0.3)
	s.set(&"bayer_size", 3)
	s.set(&"contrast", 1.12)
	s.set(&"soft_sampling", false)
	s.set(&"outline_strength", 0.6)
	s.set(&"outline_color", Color("0d0b0a"))
	s.set(&"outline_min_distance", 80.0)
	return s


func _build_sky() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://rooms/red_grid/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky


func _build_grid() -> void:
	var shader := preload("res://rooms/red_grid/grid.gdshader")
	var near_mesh := PlaneMesh.new()
	near_mesh.size = Vector2(NEAR_SIZE, NEAR_SIZE)
	near_mesh.subdivide_width = NEAR_CELLS - 1
	near_mesh.subdivide_depth = NEAR_CELLS - 1
	var far_mesh := PlaneMesh.new()
	far_mesh.size = Vector2(14000, 14000)
	far_mesh.subdivide_width = 69
	far_mesh.subdivide_depth = 69
	for spec in [[near_mesh, 0.0, "GridNear"], [far_mesh, NEAR_SIZE * 0.5 - 0.5, "GridFar"]]:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(&"inner_cut", spec[1])
		mat.set_shader_parameter(&"sag_depth", SAG_DEPTH)
		mat.set_shader_parameter(&"sag_radius", SAG_RADIUS)
		mat.set_shader_parameter(&"plug_radius", PLUG_R)
		mat.set_shader_parameter(&"shadow_inner", SHADOW_INNER)
		mat.set_shader_parameter(&"shadow_outer", SHADOW_OUTER)
		mat.set_shader_parameter(&"socket_angle0", SOCKET_ANGLE0)
		mat.set_shader_parameter(&"socket_filled", PackedFloat32Array([0, 0, 0, 0, 0, 0]))
		var mi := MeshInstance3D.new()
		mi.name = spec[2]
		mi.mesh = spec[0]
		mi.material_override = mat
		mi.extra_cull_margin = SAG_DEPTH + 20.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_grid_mats.append(mat)

	var body := StaticBody3D.new()
	body.name = "Ground"
	add_child(body)
	_ground_shape = CollisionShape3D.new()
	_ground_shape.shape = _sag_collision()
	body.add_child(_ground_shape)
	# Flat plain around the near square.
	var half := NEAR_SIZE * 0.5
	var reach := 7000.0
	for spec in [
		[Vector3(0, -1, -(half + reach) * 0.5), Vector3(reach * 2.0, 2, reach - half)],
		[Vector3(0, -1, (half + reach) * 0.5), Vector3(reach * 2.0, 2, reach - half)],
		[Vector3(-(half + reach) * 0.5, -1, 0), Vector3(reach - half, 2, NEAR_SIZE)],
		[Vector3((half + reach) * 0.5, -1, 0), Vector3(reach - half, 2, NEAR_SIZE)],
	]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		cs.shape = box
		cs.position = spec[0]
		body.add_child(cs)


## The sag as a triangle mesh, one quad per 10 m cell (same vertices as the near grid mesh).
func _sag_collision() -> ConcavePolygonShape3D:
	var n := NEAR_CELLS
	var step := NEAR_SIZE / n
	var h := NEAR_SIZE * 0.5
	var pts := PackedVector3Array()
	pts.resize((n + 1) * (n + 1))
	for zi in n + 1:
		for xi in n + 1:
			var x := -h + xi * step
			var z := -h + zi * step
			pts[zi * (n + 1) + xi] = Vector3(x, sag_height(Vector2(x, z), SAG_DEPTH), z)
	var faces := PackedVector3Array()
	faces.resize(n * n * 6)
	var f := 0
	for zi in n:
		for xi in n:
			var a := pts[zi * (n + 1) + xi]
			var b := pts[zi * (n + 1) + xi + 1]
			var c := pts[(zi + 1) * (n + 1) + xi]
			var d := pts[(zi + 1) * (n + 1) + xi + 1]
			faces[f] = a; faces[f + 1] = b; faces[f + 2] = c
			faces[f + 3] = b; faces[f + 4] = d; faces[f + 5] = c
			f += 6
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


## After the mend: a level plain with the open hole in the middle (fall in to go home).
func _set_ground_level() -> void:
	var segs := 72
	var radii := [PLUG_R, PLUG_R + 6.0, 80.0, 200.0, 450.0, NEAR_SIZE * 0.75]
	var faces := PackedVector3Array()
	for ri in radii.size() - 1:
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var r0: float = radii[ri]
			var r1: float = radii[ri + 1]
			var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			faces.append_array(PackedVector3Array([p00, p10, p01, p01, p10, p11]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	_ground_shape.shape = shape


func _build_eye() -> void:
	_pupil = MeshInstance3D.new()
	_pupil.name = "Pupil"
	var disc := CylinderMesh.new()
	disc.top_radius = PUPIL_R
	disc.bottom_radius = PUPIL_R
	disc.height = 40.0
	disc.radial_segments = 160
	disc.rings = 1
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.0, 0.0, 0.0)
	black.disable_fog = true
	disc.material = black
	_pupil.mesh = disc
	_pupil.position = Vector3(0, PUPIL_Y + 20.0, 0)
	_pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pupil)

	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	_eye_mat = ShaderMaterial.new()
	_eye_mat.shader = preload("res://rooms/red_grid/eye.gdshader")
	_eye_mat.set_shader_parameter(&"pupil_radius", PUPIL_R)
	_eye_mat.render_priority = -1
	var eye := MeshInstance3D.new()
	eye.name = "Iris"
	eye.mesh = plane
	eye.material_override = _eye_mat
	eye.position = Vector3(0, PUPIL_Y - 1.0, 0)
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(eye)

	# The stare, pressing down on the bottom of the sag.
	var top := PUPIL_Y - 2.0
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 9.0
	beam_mesh.bottom_radius = 5.0
	beam_mesh.height = top + SAG_DEPTH
	beam_mesh.radial_segments = 24
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://rooms/red_grid/beam.gdshader")
	_beam_mat.set_shader_parameter(&"bottom_y", -SAG_DEPTH)
	_beam_mat.set_shader_parameter(&"top_y", top)
	_beam = MeshInstance3D.new()
	_beam.name = "Stare"
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_mat
	_beam.position = Vector3(0, (top - SAG_DEPTH) * 0.5, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func _build_fog() -> void:
	var tex := preload("res://rooms/red_grid/art/fog_fall_strip.png")
	var shader := preload("res://rooms/red_grid/fog_fall.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := 11
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.18, 0.18)
		var width := rng.randf_range(70.0, 170.0)
		for layer in 3:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter(&"streaks", tex)
			mat.set_shader_parameter(&"seed", rng.randf() * 10.0)
			mat.set_shader_parameter(&"speed", rng.randf_range(0.035, 0.06))
			mat.set_shader_parameter(&"density", [0.55, 0.38, 0.22][layer])
			var mi := MeshInstance3D.new()
			mi.name = "FogFall%d_%d" % [i, layer]
			mi.mesh = _fall_strip(ang, width * (1.0 + layer * 0.25), 3.0 + layer * 9.0)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_fall_mats.append(mat)

	# The lid: hidden until the mend.
	var plane := PlaneMesh.new()
	plane.size = Vector2(11000, 11000)
	_lid_mat = ShaderMaterial.new()
	_lid_mat.shader = preload("res://rooms/red_grid/fog_lid.gdshader")
	var lid := MeshInstance3D.new()
	lid.name = "FogLid"
	lid.mesh = plane
	lid.material_override = _lid_mat
	lid.position = Vector3(0, PUPIL_Y - 70.0, 0)
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lid)


## A ribbon of fog lying on the slope from beyond the rim down toward the bottom.
func _fall_strip(ang: float, width: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var r_top := SAG_RADIUS + 140.0
	var r_bot := 70.0
	var steps := 48
	for s in steps:
		var v0 := float(s) / steps
		var v1 := float(s + 1) / steps
		var quad := []
		for v: float in [v0, v1]:
			var r := lerpf(r_top, r_bot, v)
			# Narrows as it pours into the bottom.
			var w := width * lerpf(1.0, 0.35, v)
			for u: float in [0.0, 1.0]:
				var xz: Vector2 = dir * r + perp * (u - 0.5) * w
				var y := sag_height(xz, SAG_DEPTH) + lift * lerpf(1.0, 0.6, v)
				quad.append([Vector3(xz.x, y, xz.y), Vector2(u, v)])
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])
	return st.commit()


func _build_horizon() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 5200.0
	ring.bottom_radius = 5200.0
	ring.height = 420.0
	ring.radial_segments = 96
	ring.rings = 1
	ring.cap_top = false
	ring.cap_bottom = false
	_horizon_mat = ShaderMaterial.new()
	_horizon_mat.shader = preload("res://rooms/red_grid/horizon.gdshader")
	_horizon_mat.set_shader_parameter(&"skyline", preload("res://rooms/red_grid/art/horizon_glyph_skyline.png"))
	var mi := MeshInstance3D.new()
	mi.name = "Skyline"
	mi.mesh = ring
	mi.material_override = _horizon_mat
	mi.position = Vector3(0, 170.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_sockets() -> void:
	var mark_mat := StandardMaterial3D.new()
	mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_mat.albedo_color = Color(0.95, 0.35, 0.42)
	var torus := TorusMesh.new()
	torus.inner_radius = HOLE_R + 0.15
	torus.outer_radius = HOLE_R + 0.32
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = mark_mat
	for s in 6:
		var a := SOCKET_ANGLE0 + TAU * s / 6.0
		var p := Vector3(cos(a) * PLUG_R, -SAG_DEPTH, sin(a) * PLUG_R)
		sockets.append(p)
		var mark := MeshInstance3D.new()
		mark.name = "Socket%d" % s
		mark.mesh = torus
		mark.position = p + Vector3.UP * 0.05
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		_socket_marks.append(mark)


## The way he came in: a small hole behind the spawn with fog sinking into it.
func _build_exit_hole() -> void:
	var exit := get_node_or_null(^"ExitToHub") as Node3D
	if exit == null:
		return
	var node := _make_hole_node(0.0, true)
	node.scale = Vector3.ONE * 2.6
	exit.add_child(node)
	node.position = Vector3(0, 0.03, 0)


func _make_hole_node(ink := 0.0, with_wisp := false) -> Node3D:
	if _hole_mat == null:
		_hole_mat = ShaderMaterial.new()
		_hole_mat.shader = preload("res://rooms/red_grid/hole.gdshader")
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var m := CylinderMesh.new()
	m.top_radius = HOLE_R
	m.bottom_radius = HOLE_R
	m.height = 0.03
	m.radial_segments = 32
	m.rings = 1
	disc.mesh = m
	var mat := _hole_mat
	if ink > 0.0:
		mat = _hole_mat.duplicate()
		mat.set_shader_parameter(&"ink", ink)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	if with_wisp:
		root.add_child(_make_wisp())
	return root


func _make_wisp() -> MeshInstance3D:
	if _wisp_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 46
		for q in n:
			var ph := float(q) / n
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				st.set_uv(c)
				st.set_uv2(Vector2(ph, 0))
				st.add_vertex(Vector3.ZERO)
		_wisp_mesh = st.commit()
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://rooms/red_grid/wisp.gdshader")
		_wisp_mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Wisp"
	mi.mesh = _wisp_mesh
	mi.custom_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 36, 24))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _add_hole(pos: Vector3, st: HoleState) -> int:
	var node := _make_hole_node(0.0, true)
	node.name = "Hole%d" % holes.size()
	add_child(node)
	node.global_position = pos + Vector3.UP * 0.02
	holes.append({node = node, pos = pos, state = st, socket = -1})
	return holes.size() - 1


func _set_hole_state(i: int, st: HoleState) -> void:
	holes[i].state = st
	var node: Node3D = holes[i].node
	var wisp := node.get_node_or_null(^"Wisp")
	if wisp:
		wisp.visible = st == HoleState.LOOSE


func _make_plug() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLUG_R * 2.0 + 2.0, PLUG_R * 2.0 + 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://rooms/red_grid/plug.gdshader")
	mat.set_shader_parameter(&"radius", PLUG_R)
	var plug := MeshInstance3D.new()
	plug.name = "Plug"
	plug.mesh = plane
	plug.material_override = mat
	plug.position = Vector3(0, -SAG_DEPTH, 0)
	add_child(plug)
	return plug


# --- Shader plumbing -----------------------------------------------------------

func _grid_set(param: StringName, value: Variant) -> void:
	for m in _grid_mats:
		m.set_shader_parameter(param, value)


func _grid_set_socket(s: int, v: float) -> void:
	var arr: PackedFloat32Array = _grid_mats[0].get_shader_parameter(&"socket_filled")
	if arr.size() < 6:
		arr = PackedFloat32Array([0, 0, 0, 0, 0, 0])
	arr[s] = v
	_grid_set(&"socket_filled", arr)


func _push_holes() -> void:
	var arr := PackedVector4Array()
	for h in holes:
		var kind := 0.0
		match h.state:
			HoleState.LOOSE:
				kind = 1.0
			HoleState.LAID, HoleState.SOCKET:
				kind = 2.0
		arr.append(Vector4(h.pos.x, h.pos.z, HOLE_R, kind))
	while arr.size() < 12:
		arr.append(Vector4.ZERO)
	_grid_set(&"holes", arr)


func _wave(xz: Vector2, strength: float) -> void:
	_wave_age = 0.0
	_grid_set(&"wave_pos", xz)
	_grid_set(&"wave_strength", strength)
