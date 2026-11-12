extends Room
## CHECKERBOARD. The broken rule: gravity.
##
## "Down" swings across the board like a tide. The black tiles let it take you,
## the pink tiles hold you fast, and the checkered balls roll wherever down is.
## Every few tides, down lets go entirely and the balls float.
## Roll a small ball into the glowing socket to finish the room.
##
## Read it like a loop:  CALM -> WARN (an edge blinks) -> PULL toward that edge -> CALM ...
##                       and every `lift_every` cycles: CALM -> LIFT (balls float) -> CALM.

enum Phase { CALM, WARN, PULL, LIFT, DONE }

const Ball := preload("res://rooms/checkerboard/checker_sphere.gd")
const DIRS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

@export_group("Tide timing")
@export var first_calm_time := 2.5
@export var calm_time := 1.4
@export var warn_time := 0.9
@export var pull_time := 4.2
@export var lift_time := 3.4
## Every Nth tide is a lift instead of a pull.
@export var lift_every := 4

@export_group("Tide strength")
## Sideways acceleration on the balls at full tide (m/s²).
@export var ball_accel := 7.5
## How fast the tide drags the little man on a black tile at full tide (m/s). He walks at 4.
@export var drift_max := 3.3
@export var drift_accel := 7.0
## How hard the little man shoves a ball he walks into.
@export var push_strength := 0.6
## Balls up to this radius fit the socket.
@export var socket_fit_radius := 0.7

var phase := Phase.CALM

var _phase_t := 0.0
var _phase_len := 0.0
var _cycle := 0
var _tide_dir := Vector2(0, -1)
var _next_dir := Vector2(0, -1)
var _strength := 0.0
var _warn := 0.0
var _drift := Vector3.ZERO
var _lean := Vector3.ZERO
var _shake := 0.0
var _ripple_t := 100.0
var _calm_glow := 0.0
var _push_cooldown := 0.0
var _look_base := Vector3.ZERO
var _look_tide := Vector3.ZERO
var _intro := Vector3.ZERO
var _balls: Array[Ball] = []
var _sky: MeshInstance3D
var _sky_mat: ShaderMaterial
var _sky_lean := 0.0
var _bloom := 0.0
var _time := 0.0

@onready var board: Node3D = $Board
@onready var sfx: Node = $Sfx
@onready var exit_ring: Node3D = $ExitToHub/Ring
@onready var exit_light: OmniLight3D = $ExitToHub/Light


func _ready() -> void:
	for n in find_children("*", "RigidBody3D", true, false):
		if n is Ball:
			_balls.append(n)
			n.hit.connect(_on_ball_hit.bind(n))

	var socket := Area3D.new()
	socket.name = "Socket"
	socket.collision_layer = 1 << 2
	socket.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(board.tile_size * 0.8, 0.5, board.tile_size * 0.8)
	cs.shape = box
	socket.add_child(cs)
	add_child(socket)
	socket.global_position = board.socket_center() + Vector3(0, -0.75, 0)
	socket.body_entered.connect(_on_socket_body_entered)


func _on_room_entered(_spawn: StringName) -> void:
	_look_base = Game.camera.look_offset
	# Open on the whole board, then drift down to the little man.
	_intro = global_position - Game.player.global_position
	_intro.y = 0.0
	Game.camera.look_offset = _look_base + _intro
	Game.camera.snap_to_target()
	_add_sky()
	_enter_phase(Phase.CALM, first_calm_time)
	if Game.is_completed(room_id):
		# Already solved on an earlier visit: the room stays at peace.
		_enter_phase(Phase.DONE, 0.0)
		_calm_glow = 1.0
		board.socket_light.light_energy = 5.0


# --- Tide -------------------------------------------------------------------

func _enter_phase(p: Phase, length: float) -> void:
	phase = p
	_phase_t = 0.0
	_phase_len = length


func _advance_phase(delta: float) -> void:
	_phase_t += delta
	if phase == Phase.DONE or _phase_t < _phase_len:
		return
	match phase:
		Phase.CALM:
			_cycle += 1
			if lift_every > 0 and _cycle % lift_every == 0:
				_enter_phase(Phase.LIFT, lift_time)
				sfx.play(&"lift", -4.0)
			else:
				_next_dir = _pick_dir()
				_enter_phase(Phase.WARN, warn_time)
				sfx.play(&"warn", -8.0)
		Phase.WARN:
			_tide_dir = _next_dir
			_enter_phase(Phase.PULL, pull_time)
			sfx.play(&"surge", -2.0)
			_shake = maxf(_shake, 0.35)
		Phase.PULL, Phase.LIFT:
			_enter_phase(Phase.CALM, calm_time)


func _pick_dir() -> Vector2:
	var options: Array[Vector2] = []
	for d in DIRS:
		if d != _tide_dir:
			options.append(d)
	return options.pick_random()


func _tide_strength() -> float:
	if phase != Phase.PULL:
		return 0.0
	return smoothstep(0.0, 0.5, _phase_t) * (1.0 - smoothstep(_phase_len - 0.7, _phase_len, _phase_t))


# --- Frame ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(Game.player) or Game.current_room != self:
		return
	_time += delta
	_advance_phase(delta)
	_strength = _tide_strength()
	_warn = move_toward(_warn, 1.0 if phase == Phase.WARN else 0.0, delta * 6.0)
	var tide := Vector3(_tide_dir.x, 0.0, _tide_dir.y) * _strength

	_update_board(delta)
	_update_balls(tide, delta)
	_update_player(tide, delta)
	_update_camera(tide, delta)


func _update_board(delta: float) -> void:
	_ripple_t += delta
	var m: ShaderMaterial = board.floor_material
	m.set_shader_parameter(&"tide_dir", _tide_dir)
	m.set_shader_parameter(&"tide_strength", _strength)
	m.set_shader_parameter(&"warn", _warn)
	m.set_shader_parameter(&"ripple_time", _ripple_t)
	m.set_shader_parameter(&"ripple_origin", board.socket_center())
	m.set_shader_parameter(&"calm", _calm_glow)

	var pulling: int = board.edge_index(_tide_dir)
	var warning: int = board.edge_index(_next_dir)
	for i in 4:
		var glow := 0.0
		if phase == Phase.PULL and i == pulling:
			glow = _strength
		elif phase == Phase.WARN and i == warning:
			glow = 0.35 + 0.65 * float(int(_phase_t * 10.0) % 2)
		board.set_edge_glow(i, glow)

	if phase != Phase.DONE:
		board.socket_light.light_energy = 1.4 + 0.5 * sin(_time * 3.0)
	# The halo beckons while unsolved, then settles into a steady glow.
	var beat := 0.5 + 0.5 * sin(_time * 3.0)
	var halo_scale := 1.0 + (beat * 0.12 if phase != Phase.DONE else 0.0)
	board.socket_halo.scale = Vector3(halo_scale, 0.05, halo_scale)
	var halo_mat: StandardMaterial3D = (board.socket_halo.mesh as TorusMesh).material
	var halo_bright := (0.55 + 0.45 * beat) if phase != Phase.DONE else 1.0
	halo_mat.albedo_color = Color(1.0, 0.45, 0.6) * halo_bright
	sfx.set_drone(maxf(_strength, _warn * 0.2))

	# The exit breathes so it reads as "the way out" without words.
	exit_ring.rotation.y += delta * 0.8
	exit_ring.position.y = 0.25 + sin(_time * 2.0) * 0.06
	exit_light.light_energy = (1.2 if phase != Phase.DONE else 2.4) + sin(_time * 2.0) * 0.3


func _update_balls(tide: Vector3, delta: float) -> void:
	var floating := phase == Phase.LIFT or phase == Phase.DONE
	var release := phase == Phase.LIFT and _phase_t > _phase_len - 0.5
	for i in _balls.size():
		var b := _balls[i]
		if b.socketed:
			continue
		if floating and not release:
			b.gravity_scale = 0.0
			var rise := smoothstep(0.0, 1.2, _phase_t) if phase == Phase.LIFT else 1.0
			var target_y := b.radius + rise * (1.4 + b.radius + sin(_time * 1.7 + i * 1.3) * 0.25)
			var f := (target_y - b.global_position.y) * 14.0 - b.linear_velocity.y * 4.0
			b.apply_central_force(Vector3(0, f, 0) * b.mass)
			b.apply_torque(Vector3(0.3, 0.6, 0.2) * b.mass * 0.4)
			# Gentle drift so the room keeps moving while it floats.
			b.apply_central_force(-b.linear_velocity * Vector3(1, 0, 1) * 0.8 * b.mass)
			# Keep floating balls over the board so they land back on it.
			var limit: float = board.half() - b.radius - 0.3
			var pos := b.global_position
			var inside := Vector3(clampf(pos.x, -limit, limit), pos.y, clampf(pos.z, -limit, limit))
			b.apply_central_force((inside - pos) * 10.0 * b.mass)
		else:
			b.gravity_scale = 1.0
			b.apply_central_force(tide * ball_accel * b.mass)
		if b.global_position.y < -8.0:
			_respawn_ball(b)


func _update_player(tide: Vector3, delta: float) -> void:
	var p := Game.player
	var on_black: bool = board.is_on_board(p.global_position) and board.is_black_at(p.global_position)
	if on_black and p.is_on_floor() and phase == Phase.PULL:
		_drift = _drift.move_toward(tide * drift_max, drift_accel * delta)
	else:
		# Pink tiles grip: the drift dies almost at once.
		_drift = _drift.move_toward(Vector3.ZERO, 18.0 * delta)
	if _drift.length_squared() > 0.0001:
		p.move_and_collide(_drift * delta)

	# Balls shove him; he shoves balls.
	for b in _balls:
		if b.socketed:
			continue
		var d := p.global_position - b.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 0.001 or dist > b.radius + 0.45 or absf(p.global_position.y + 0.6 - b.global_position.y) > b.radius + 0.6:
			continue
		var v := b.linear_velocity
		v.y = 0.0
		var toward := v.dot(d / dist)
		if toward > 0.6:
			p.move_and_collide(d / dist * toward * delta)
			_drift += d / dist * toward * 0.15
	_push_cooldown -= delta
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var b := c.get_collider() as Ball
		if b == null:
			continue
		var n := -c.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var want := p.move_speed * 1.1
		var along := b.linear_velocity.dot(n)
		if along < want:
			b.apply_central_impulse(n * (want - along) * b.mass * push_strength * (0.6 / b.radius))
			if _push_cooldown <= 0.0:
				sfx.play(&"push", -10.0, randf_range(0.8, 1.2) / b.radius * 0.6)
				_push_cooldown = 0.25

	# Lean into the pull, like walking in wind.
	var lean_target := -_drift * 0.12
	_lean = _lean.lerp(lean_target, 1.0 - exp(-10.0 * delta))
	var local := _lean.rotated(Vector3.UP, -p.visual.rotation.y)
	p.visual.rotation.x = local.z
	p.visual.rotation.z = -local.x

	if p.global_position.y < -6.0:
		_respawn_player()


func _update_camera(tide: Vector3, delta: float) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	# The view sags a little toward "down".
	_look_tide = _look_tide.lerp(tide * 0.7, 1.0 - exp(-3.0 * delta))
	_intro = _intro.lerp(Vector3.ZERO, 1.0 - exp(-(0.9 if _time > 1.2 else 0.0) * delta))
	cam.look_offset = _look_base + _look_tide + _intro
	_shake = move_toward(_shake, 0.0, delta * 1.6)
	var s := _shake * _shake * 0.35
	cam.h_offset = (randf() * 2.0 - 1.0) * s
	cam.v_offset = (randf() * 2.0 - 1.0) * s
	if _sky_mat:
		var screen_side := cam.global_basis.x.dot(tide)
		_sky_lean = lerpf(_sky_lean, -screen_side * 0.08, 1.0 - exp(-2.0 * delta))
		_bloom = move_toward(_bloom, 0.0, delta * 0.7)
		_sky_mat.set_shader_parameter(&"lean", _sky_lean)
		_sky_mat.set_shader_parameter(&"bloom", _bloom)


# --- Events -----------------------------------------------------------------

func _on_ball_hit(speed: float, ball: Ball) -> void:
	sfx.play(&"thunk", linear_to_db(clampf(speed / 9.0, 0.08, 1.0)), randf_range(0.9, 1.1) * 0.7 / ball.radius)
	if ball.radius > 0.9 and speed > 3.0:
		_shake = maxf(_shake, clampf(speed / 14.0, 0.0, 0.5))


func _on_socket_body_entered(body: Node3D) -> void:
	var b := body as Ball
	if b == null or b.socketed or b.radius > socket_fit_radius:
		return
	if phase == Phase.DONE:
		return
	b.socketed = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	var rest: Vector3 = board.socket_center() + Vector3(0, -1.0 + b.radius, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(b, "global_position", rest, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(b.set_glow, 0.0, 1.0, 1.2)
	tw.tween_property(board.socket_light, "light_energy", 5.0, 1.5)
	tw.tween_property(self, "_calm_glow", 1.0, 2.5)
	_enter_phase(Phase.DONE, 0.0)
	_ripple_t = 0.0
	_shake = 0.7
	_bloom = 1.0
	_drift = Vector3.ZERO
	sfx.play(&"socket", 0.0)
	complete()


func _respawn_ball(b: Ball) -> void:
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.global_position = b.home + Vector3(0, 6.0, 0)
	sfx.play(&"respawn", -10.0)


func _respawn_player() -> void:
	var p := Game.player
	var spawn := get_spawn()
	p.velocity = Vector3.ZERO
	_drift = Vector3.ZERO
	p.global_transform = spawn.global_transform if spawn else global_transform
	sfx.play(&"respawn", -6.0)


func _add_sky() -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://rooms/checkerboard/dream_sky.gdshader")
	var quad := QuadMesh.new()
	var height := camera_size * 1.5
	quad.size = Vector2(height * 16.0 / 9.0 * 1.3, height)
	quad.material = _sky_mat
	_sky = MeshInstance3D.new()
	_sky.name = "DreamSky"
	_sky.mesh = quad
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(_sky)
	_sky.position = Vector3(0, 0, -cam.far * 0.9)
