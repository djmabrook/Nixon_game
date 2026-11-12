extends Room
## CHECKER PLAIN. The broken rule: gravity.
##
## A pink and black plain runs to every horizon. A red moon, the Watcher's eye,
## hangs low and circles it, and "down" always points at the moon. When it pulls,
## the black tiles let it take the little man and the pink tiles hold him. Spheres
## from marbles to cathedrals migrate across the plain like herds. Every fourth tide
## the eye looks up and everything lifts at once, giants included.
##
## At the plain's centre is a crater, and at its heart a socket. Escort the small
## pale sphere in from the edge across several tides and drop it in: the eye shuts
## and sets, the tide stops for good, the spheres settle, and pink footing blooms
## wherever the little man walks. An exit opens in the crater.
##
## Tide loop: CALM (eye half-lidded) -> WARN (the moon comes round to a new bearing)
##            -> PULL toward it -> CALM ...   every `lift_every`: CALM -> LIFT -> CALM.

enum Phase { CALM, WARN, PULL, LIFT, DONE }

const Ball := preload("res://rooms/checkerboard/checker_sphere.gd")
const SKY_SHADER := preload("res://rooms/checkerboard/dream_sky.gdshader")
const MOON_DISTANCE := 1500.0
## Herd recipe: [count, min radius, max radius]. Marbles to cathedrals.
const HERDS := [[60, 0.25, 0.6], [50, 0.8, 2.0], [30, 2.5, 6.0], [8, 8.0, 15.0], [4, 24.0, 36.0]]

@export_group("Tide timing")
@export var first_calm_time := 6.0
@export var calm_time := 2.5
@export var warn_time := 2.5
@export var pull_time := 6.0
@export var lift_time := 7.0
## Every Nth tide is a lift instead of a pull.
@export var lift_every := 4

@export_group("Tide strength")
## Sideways acceleration on spheres at full tide (m/s²). Big ones are capped slower.
@export var ball_accel := 7.0
## How fast the tide drags the little man on a black tile (m/s). He walks at 5.
@export var drift_max := 4.3
@export var drift_accel := 7.0
## How hard the little man shoves a sphere he can move.
@export var push_strength := 0.6
## Spheres up to this radius can be pushed by him.
@export var pushable_radius := 2.5
## Random seed for the herds, so the plain is the same every visit.
@export var herd_seed := 7

@export_group("Moon")
## Height of the moon above the horizon, in radians.
@export var moon_elevation := 0.07

var phase := Phase.CALM

var _phase_t := 0.0
var _phase_len := 0.0
var _cycle := 0
var _moon_az := -PI * 0.5
var _moon_from := -PI * 0.5
var _moon_to := -PI * 0.5
var _moon_elev := 0.07
var _moon_open := 0.5
var _strength := 0.0
var _warn := 0.0
var _drift := Vector3.ZERO
var _lean := Vector3.ZERO
var _shake := 0.0
var _ripple_t := 1000.0
var _calm_glow := 0.0
var _footing := 0.0
var _trail := PackedVector3Array()
var _push_cooldown := 0.0
var _bloom := 0.0
var _time := 0.0
var _lifts_seen := 0
var _cam_extra := 0.0
var _cam_base := 9.0
var _balls: Array[Ball] = []
var _sky_mat: ShaderMaterial
var _crater_exit: Node3D

@onready var board: Node3D = $Board
@onready var sfx: Node = $Sfx
@onready var moon: Node3D = $Moon
@onready var moon_light: DirectionalLight3D = $MoonLight
@onready var key_ball: Ball = $KeySphere
@onready var exit_ring: Node3D = $ExitToHub/Ring
@onready var exit_light: OmniLight3D = $ExitToHub/Light
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var wind: GPUParticles3D = $Wind


func _ready() -> void:
	_trail.resize(8)
	_spawn_herds()
	_balls.append(key_ball)
	for b in _balls:
		b.hit.connect(_on_ball_hit.bind(b))

	var socket := Area3D.new()
	socket.name = "Socket"
	socket.collision_layer = 1 << 2
	socket.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = board.socket_radius * 0.9
	cyl.height = 1.2
	cs.shape = cyl
	socket.add_child(cs)
	add_child(socket)
	socket.global_position = board.socket_center() + Vector3(0, -board.pit_depth + 0.7, 0)
	socket.body_entered.connect(_on_socket_body_entered)

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.environment.sky = sky
	_moon_elev = moon_elevation
	_place_moon()


func _on_room_entered(_spawn: StringName) -> void:
	_cam_base = camera_distance
	_enter_phase(Phase.CALM, first_calm_time)
	if Game.is_completed(room_id):
		# Mended on an earlier visit: the eye has set and nothing pulls.
		_enter_phase(Phase.DONE, 0.0)
		_calm_glow = 1.0
		_footing = 1.0
		_moon_elev = -0.2
		_moon_open = 0.0
		_open_crater_exit(false)
	_place_moon()


# --- Herds ------------------------------------------------------------------

func _spawn_herds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = herd_seed
	var placed: Array[Vector4] = []   # x, z, radius, unused
	var spawn := get_spawn()
	var spawn_pos := spawn.global_position if spawn else Vector3.ZERO
	var parent := $Herds
	for herd in HERDS:
		for i in herd[0]:
			var r := rng.randf_range(herd[1], herd[2])
			var pos := Vector3.ZERO
			for attempt in 40:
				var ang := rng.randf() * TAU
				var dist: float = sqrt(rng.randf_range(0.05, 1.0)) * (board.play_radius - r)
				pos = Vector3(cos(ang) * dist, r, sin(ang) * dist)
				if _clear_spot(pos, r, placed, spawn_pos):
					break
			placed.append(Vector4(pos.x, pos.z, r, 0))
			var b := Ball.new()
			b.radius = r
			b.name = "Sphere%d" % parent.get_child_count()
			parent.add_child(b)
			b.global_position = pos
			b.home = pos
			b.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
			_balls.append(b)


func _clear_spot(pos: Vector3, r: float, placed: Array[Vector4], spawn_pos: Vector3) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() < board.crater_radius + r + 4.0:
		return false
	if flat.distance_to(Vector2(spawn_pos.x, spawn_pos.z)) < r + 14.0:
		return false
	for p in placed:
		if flat.distance_to(Vector2(p.x, p.y)) < r + p.z + 1.5:
			return false
	return true


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
				_on_lift_started()
			else:
				_moon_from = _moon_az
				_moon_to = _moon_az + randf_range(deg_to_rad(70), deg_to_rad(140)) * (1.0 if randf() < 0.5 else -1.0)
				_enter_phase(Phase.WARN, warn_time)
				sfx.play(&"warn", -6.0)
		Phase.WARN:
			_moon_az = _moon_to
			_enter_phase(Phase.PULL, pull_time)
			sfx.play(&"surge", 0.0)
			_shake = maxf(_shake, 0.45)
		Phase.PULL, Phase.LIFT:
			_enter_phase(Phase.CALM, calm_time)


func _tide_strength() -> float:
	if phase != Phase.PULL:
		return 0.0
	return smoothstep(0.0, 1.0, _phase_t) * (1.0 - smoothstep(_phase_len - 1.2, _phase_len, _phase_t))


func tide_dir() -> Vector2:
	return Vector2(cos(_moon_az), sin(_moon_az))


func _moon_vector() -> Vector3:
	var d := tide_dir()
	return Vector3(d.x * cos(_moon_elev), sin(_moon_elev), d.y * cos(_moon_elev))


func _place_moon() -> void:
	var mv := _moon_vector()
	moon.global_position = board.crater_center() + mv * MOON_DISTANCE
	moon_light.global_basis = Basis.looking_at(-mv, Vector3.UP)
	_sky_mat.set_shader_parameter(&"moon_dir", mv)
	_sky_mat.set_shader_parameter(&"moon_open", _moon_open)


# --- Frame ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(Game.player) or Game.current_room != self:
		return
	_time += delta
	_advance_phase(delta)
	_strength = _tide_strength()
	_warn = move_toward(_warn, 1.0 if phase == Phase.WARN else 0.0, delta * 4.0)
	var tide := Vector3(tide_dir().x, 0.0, tide_dir().y) * _strength

	_update_moon(delta)
	_update_world(delta)
	_update_balls(tide, delta)
	_update_player(tide, delta)
	_update_camera(delta)


func _update_moon(delta: float) -> void:
	match phase:
		Phase.WARN:
			# The moon comes round to its new bearing.
			var k := smoothstep(0.0, 1.0, _phase_t / _phase_len)
			_moon_az = lerp_angle(_moon_from, _moon_to, k)
			_moon_open = move_toward(_moon_open, 1.0, delta * 2.0)
			_moon_elev = move_toward(_moon_elev, moon_elevation, delta * 0.1)
		Phase.PULL:
			_moon_open = move_toward(_moon_open, 1.0, delta * 2.0)
		Phase.LIFT:
			# The eye lifts its gaze, and everything follows it up.
			var up := smoothstep(0.0, 2.0, _phase_t) * (1.0 - smoothstep(_phase_len - 1.5, _phase_len, _phase_t))
			_moon_elev = lerpf(moon_elevation, 0.32, up)
			_moon_open = move_toward(_moon_open, 1.0, delta * 2.0)
		Phase.CALM:
			_moon_open = move_toward(_moon_open, 0.45, delta * 0.8)
			_moon_elev = move_toward(_moon_elev, moon_elevation, delta * 0.1)
		Phase.DONE:
			# Shut and set.
			_moon_open = move_toward(_moon_open, 0.0, delta * 0.6)
			if _moon_open < 0.3:
				_moon_elev = move_toward(_moon_elev, -0.2, delta * 0.03)
	_place_moon()
	var lit := clampf(_moon_elev / moon_elevation, 0.0, 1.0) if _moon_elev < moon_elevation else 1.0
	moon_light.light_energy = (0.35 + _strength * 0.8 + _warn * 0.2) * lit


func _update_world(delta: float) -> void:
	_ripple_t += delta
	var td := tide_dir()
	var m: ShaderMaterial = board.floor_material
	m.set_shader_parameter(&"tide_dir", td)
	m.set_shader_parameter(&"tide_strength", _strength)
	m.set_shader_parameter(&"warn", _warn)
	m.set_shader_parameter(&"ripple_time", _ripple_t)
	m.set_shader_parameter(&"ripple_origin", board.socket_center())
	m.set_shader_parameter(&"calm", _calm_glow)
	m.set_shader_parameter(&"footing", _footing)

	_bloom = move_toward(_bloom, 0.0, delta * 0.4)
	_sky_mat.set_shader_parameter(&"tide_dir", td)
	_sky_mat.set_shader_parameter(&"tide_strength", _strength)
	_sky_mat.set_shader_parameter(&"warn_dir", td)
	_sky_mat.set_shader_parameter(&"warn", _warn)
	_sky_mat.set_shader_parameter(&"moon_glow", 0.4 + _strength * 0.9 + _warn * 0.4)
	_sky_mat.set_shader_parameter(&"bloom", _bloom)
	sfx.set_drone(maxf(_strength, _warn * 0.25))

	# Wind streaks blow toward the moon while it pulls.
	var p := Game.player
	wind.global_position = p.global_position + Vector3(0, 3.0, 0) - Vector3(td.x, 0, td.y) * 15.0
	wind.emitting = _strength > 0.25
	(wind.process_material as ParticleProcessMaterial).direction = Vector3(td.x, 0.0, td.y)

	# Pink footing: after the mend, salmon tiles bloom where he has walked.
	if _footing > 0.0 and p.global_position.distance_to(_trail[0]) > 2.5:
		for i in range(_trail.size() - 1, 0, -1):
			_trail[i] = _trail[i - 1]
		_trail[0] = p.global_position
		m.set_shader_parameter(&"trail", _trail)

	if phase != Phase.DONE:
		board.socket_light.light_energy = 4.0 + 1.5 * sin(_time * 2.0)
	var beat := 0.5 + 0.5 * sin(_time * 2.0)
	var halo_scale := 1.0 + (beat * 0.12 if phase != Phase.DONE else 0.0)
	board.socket_halo.scale = Vector3(halo_scale, 0.05, halo_scale)
	var halo_mat: StandardMaterial3D = (board.socket_halo.mesh as TorusMesh).material
	halo_mat.albedo_color = Color(1.0, 0.45, 0.6) * ((0.55 + 0.45 * beat) if phase != Phase.DONE else 1.0)

	if _crater_exit:
		_crater_exit.get_node("Ring").rotation.y += delta * 0.8
	exit_ring.rotation.y += delta * 0.8
	exit_ring.position.y = 0.6 + sin(_time * 2.0) * 0.12
	exit_light.light_energy = 3.0 + sin(_time * 2.0) * 0.8


func _update_balls(tide: Vector3, delta: float) -> void:
	var lifting := phase == Phase.LIFT and _phase_t < _phase_len - 1.2
	var settled := phase == Phase.DONE
	var p := Game.player
	var crater: Vector3 = board.crater_center()
	for i in _balls.size():
		var b := _balls[i]
		if b.socketed:
			continue
		var pos := b.global_position
		if lifting:
			b.gravity_scale = 0.0
			var rise := smoothstep(0.0, 2.5, _phase_t)
			var high := 4.0 + float(i % 9) * 3.5 + b.radius * 1.2
			var target_y := b.radius + rise * (high + sin(_time * 0.7 + i * 1.3) * 1.0)
			var f := (target_y - pos.y) * 2.5 - b.linear_velocity.y * 2.0
			b.apply_central_force(Vector3(0, f, 0) * b.mass)
			b.apply_torque(Vector3(0.3, 0.6, 0.2) * b.mass * b.radius * b.radius * 0.2)
			b.apply_central_force(-b.linear_velocity * Vector3(1, 0, 1) * 0.5 * b.mass)
		else:
			b.gravity_scale = 1.0
			if not settled:
				# Big spheres are slow: a cathedral takes many seconds to pass.
				var cap := minf(16.0 / sqrt(b.radius), 11.0)
				var along := b.linear_velocity.dot(tide.normalized()) if _strength > 0.01 else 0.0
				if along < cap:
					b.apply_central_force(tide * ball_accel * b.mass)
			else:
				b.apply_central_force(-b.linear_velocity * Vector3(1, 0, 1) * 0.8 * b.mass)
		# Big spheres keep out of the crater so the socket stays reachable.
		var flat := Vector3(pos.x - crater.x, 0, pos.z - crater.z)
		if b.radius > pushable_radius:
			var inside: float = board.crater_radius + b.radius + 2.0 - flat.length()
			if inside > 0.0:
				b.apply_central_force(flat.normalized() * minf(inside, 8.0) * 4.0 * b.mass)
		# The plain draws strays back toward the middle.
		var over: float = flat.length() - board.play_radius
		if over > 0.0:
			b.apply_central_force(-flat.normalized() * minf(over, 10.0) * 2.5 * b.mass)
		if pos.y < -20.0 or not board.is_on_floor_area(pos):
			_respawn_ball(b)
		# Feel the giants go by: a low shake that grows as they near.
		if b.radius > 6.0:
			var near := p.global_position.distance_to(pos) - b.radius
			var speed := b.linear_velocity.length()
			if near < 25.0 and speed > 1.5:
				_shake = maxf(_shake, clampf((25.0 - near) / 25.0 * speed / 10.0, 0.0, 0.5))


func _update_player(tide: Vector3, delta: float) -> void:
	var p := Game.player
	var on_black: bool = board.is_black_at(p.global_position)
	if on_black and p.is_on_floor() and phase == Phase.PULL:
		_drift = _drift.move_toward(tide * drift_max, drift_accel * delta)
	else:
		# Pink tiles grip: the drift dies almost at once.
		_drift = _drift.move_toward(Vector3.ZERO, 18.0 * delta)
	var flat: Vector3 = p.global_position - board.crater_center()
	flat.y = 0.0
	var over: float = flat.length() - board.play_radius
	var home := Vector3.ZERO
	if over > 0.0:
		home = -flat.normalized() * minf(over * 1.5, 8.0)
	var motion := _drift + home
	if motion.length_squared() > 0.0001:
		p.move_and_collide(motion * delta)

	# Spheres shove him; he shoves the ones he can move.
	for b in _balls:
		if b.socketed:
			continue
		var d := p.global_position - b.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 0.001 or dist > b.radius + 0.5 or p.global_position.y + 1.7 < b.global_position.y - b.radius:
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
		if b == null or b.radius > pushable_radius:
			continue
		var n := -c.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var want := Vector2(p.velocity.x, p.velocity.z).length() * 1.1 + 0.5
		var along := b.linear_velocity.dot(n)
		if along < want:
			b.apply_central_impulse(n * (want - along) * b.mass * push_strength * minf(1.0, 1.2 / b.radius))
			if _push_cooldown <= 0.0:
				sfx.play(&"push", -10.0, clampf(0.8 / b.radius, 0.4, 2.0))
				_push_cooldown = 0.25

	# Lean into the pull, like walking in wind.
	var lean_target := -_drift * 0.1
	_lean = _lean.lerp(lean_target, 1.0 - exp(-10.0 * delta))
	var local := _lean.rotated(Vector3.UP, -p.visual.rotation.y)
	p.visual.rotation.x = local.z
	p.visual.rotation.z = -local.x

	if p.global_position.y < -20.0:
		_respawn_player()


func _update_camera(delta: float) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	# Pull back when the world is doing something big.
	var want := 0.0
	if phase == Phase.PULL:
		want = 5.0 * _strength
	elif phase == Phase.LIFT:
		want = 10.0
	_cam_extra = lerpf(_cam_extra, want, 1.0 - exp(-1.0 * delta))
	cam.distance = _cam_base + _cam_extra
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	var s := _shake * _shake * 0.5
	cam.h_offset = (randf() * 2.0 - 1.0) * s
	cam.v_offset = (randf() * 2.0 - 1.0) * s


# --- Events -----------------------------------------------------------------

func _on_lift_started() -> void:
	sfx.play(&"lift", -2.0)
	_lifts_seen += 1
	if _lifts_seen == 1 and is_instance_valid(Game.camera) and not Game.camera.is_in_shot():
		# The vista: low behind him, looking up as the plain rises into the sky.
		var p := Game.player
		var fwd := -Game.camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var from := p.global_position - fwd * 14.0 + Vector3.UP * 1.2
		var look := p.global_position + fwd * 80.0 + Vector3.UP * 30.0
		p.controls_enabled = false
		await Game.camera.play_shot(from, look, 4.0, 2.0)
		if is_instance_valid(p):
			p.controls_enabled = true


func _on_ball_hit(speed: float, ball: Ball) -> void:
	var near := Game.player.global_position.distance_to(ball.global_position) - ball.radius if is_instance_valid(Game.player) else 100.0
	var vol := linear_to_db(clampf(speed / 9.0, 0.05, 1.0)) - near * 0.15 + clampf(ball.radius, 0.0, 12.0)
	if vol < -40.0:
		return
	sfx.play(&"thunk", minf(vol, 6.0), clampf(0.9 / sqrt(ball.radius), 0.2, 2.0))
	if ball.radius > 6.0 and speed > 3.0 and near < 40.0:
		_shake = maxf(_shake, 0.6 * (1.0 - near / 40.0))


func _on_socket_body_entered(body: Node3D) -> void:
	var b := body as Ball
	if b == null or b.socketed or phase == Phase.DONE:
		return
	if not b.is_key:
		# Anything else is spat back out.
		b.apply_central_impulse((Vector3.UP * 9.0 + Vector3(randf() - 0.5, 0, randf() - 0.5) * 4.0) * b.mass)
		return
	b.socketed = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	var rest: Vector3 = board.socket_center() + Vector3(0, -board.pit_depth + b.radius, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(b, "global_position", rest, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(b.set_glow, 0.35, 1.2, 1.2)
	tw.tween_property(board.socket_light, "light_energy", 16.0, 1.5)
	tw.tween_property(self, "_calm_glow", 1.0, 4.0)
	tw.tween_property(self, "_footing", 1.0, 4.0)
	_enter_phase(Phase.DONE, 0.0)
	_ripple_t = 0.0
	_shake = 0.9
	_bloom = 1.0
	_drift = Vector3.ZERO
	_trail.fill(Game.player.global_position)
	sfx.play(&"socket", 0.0)
	sfx.play(&"touchdown", -2.0)
	complete()
	_open_crater_exit.call_deferred(true)
	# Watch the eye close and set.
	if is_instance_valid(Game.camera):
		Game.camera.face_toward(moon.global_position)


func _open_crater_exit(animate: bool) -> void:
	if _crater_exit:
		return
	var exit := RoomExit.new()
	exit.name = "CraterExit"
	exit.target_room = Game.HUB_ID
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	cs.shape = box
	cs.position.y = 1.5
	exit.add_child(cs)
	var ring := $ExitToHub/Ring.duplicate() as Node3D
	exit.add_child(ring)
	var light := $ExitToHub/Light.duplicate() as Node3D
	exit.add_child(light)
	add_child(exit)
	var c: Vector3 = board.socket_center()
	exit.global_position = c + Vector3(board.socket_radius + 8.0, 0, 0)
	_crater_exit = exit
	if animate:
		exit.enabled = false
		ring.scale = Vector3.ONE * 0.01
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(ring, "scale", Vector3.ONE, 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): exit.enabled = true)


func _respawn_ball(b: Ball) -> void:
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.global_position = b.home + Vector3(0, 12.0 + b.radius, 0)
	sfx.play(&"respawn", -12.0)


func _respawn_player() -> void:
	var p := Game.player
	var spawn := get_spawn()
	p.velocity = Vector3.ZERO
	_drift = Vector3.ZERO
	p.global_position = spawn.global_position if spawn else global_position
	sfx.play(&"respawn", -6.0)
