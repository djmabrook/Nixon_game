class_name Surfer
extends Node
## The little man on his board. Owns his movement wherever a SurfTerrain is in the room.
##
## Physics (all on SurfTerrain.height(), never the collision mesh):
## - Riding: gravity along the slope, air drag, sand friction. Tucking on a downslope pulls
##   harder (that's how you pump for speed); tucking uphill costs you, so stand up on the rise.
## - Carving: the board turns, the velocity follows as fast as the edge can grip. Turn harder
##   than the grip and he slides: spray, speed loss, a power slide you can steer out of.
## - Launching: no jump trigger hidden in the terrain. When the ground falls away faster than
##   gravity can follow (a crest at speed, a swell dropping under him), he leaves it.
##   Hold pop to crouch, release to ollie; releasing right at a lip adds the two together.
## - Air: left/right spins, forward/back flips, tuck grabs and dives. Close to the ground the
##   board settles toward a clean landing on its own if you're near it.
## - Landing: match the slope and the board's line and he keeps his speed (land on a downslope
##   and he gains). Land sideways, upside down, or too hard and he wipes out: full ragdoll on the
##   live terrain, then he gets back up.
##
## Rooms bend it like the walking rules: change the exports, push(accel) every physics frame
## for currents and conveyors, boost(speed) for gates. Signals tell rooms what happened.

signal launched(speed: float)
signal landed(quality: float, impact: float)
## A trick was landed cleanly: half-turns of spin and whole flips.
signal trick_landed(half_spins: int, flips: int, airtime: float)
signal wiped_out(speed: float)
signal recovered
signal boosted(amount: float)

enum State { RIDE, AIR, WIPEOUT, RECOVER }

@export_group("Ride")
## Pull along a downslope while tucked, and the extra cost of tucking uphill.
@export var tuck_downhill := 1.65
@export var tuck_uphill := 1.25
## Air drag (per metre/second squared) standing and tucked.
@export var drag := 0.0036
@export var drag_tucked := 0.0021
## Sand friction, as a fraction of gravity.
@export var rolling := 0.012
## Pushing along with no slope: acceleration and the speed it fades out at.
@export var paddle_accel := 8.0
@export var paddle_top := 13.0
@export var brake_decel := 16.0
@export var max_speed := 80.0

@export_group("Carve")
## Board turn rate (rad/s) slow and fast.
@export var turn_rate_slow := 3.6
@export var turn_rate_fast := 1.7
## How hard the edge grips (m/s² sideways) before it slides.
@export var grip := 60.0
## Speed lost sliding sideways (per second at a full 90° slide).
@export var slide_drag := 2.4
## When you let go of the stick, how fast the board lines back up with where it's going.
@export var self_align := 3.0

@export_group("Air")
## >1 holds him to the ground over small bumps; the ground must drop faster than this many g.
@export var stick := 1.08
@export var pop_min := 4.5
@export var pop_max := 9.5
## Seconds of holding pop for the full ollie.
@export var charge_time := 0.45
@export var air_spin_rate := 7.5
@export var air_flip_rate := 6.0
## Gravity multiplier while tucked in the air (dive onto the downslope).
@export var air_tuck_gravity := 1.55
@export var air_drag := 0.0012

@export_group("Landing")
## Too hard: ground-normal impact speed (m/s) that knocks him off.
@export var max_impact := 30.0
## Board line vs travel, degrees (either way round; landing backwards is fine).
@export var max_landing_angle := 58.0
## Upside-down tolerance, degrees from upright.
@export var max_flip_error := 60.0
## Speed bonus for a landing that matches the slope.
@export var perfect_bonus := 0.07

@export_group("Wipeout")
@export var wipeout_min_time := 1.3
@export var wipeout_max_time := 4.0
@export var recover_time := 0.8
## Head-on speed into a wall that knocks him down.
@export var crash_speed := 15.0
## Slow motion at the moment of a wipeout (time scale), 1 = off.
@export var wipeout_slowmo := 0.35

var state := State.RIDE
var pos := Vector3.ZERO
var prev_pos := Vector3.ZERO
var vel := Vector3.ZERO
## Where the nose points (unit, along the ground). He may ride either way round.
var heading := Vector3.FORWARD
## 0..1, how well it's going. Speed, air, clean tricks and gates raise it; wipeouts halve it.
var flow := 0.0
## Last ground normal under him.
var ground_normal := Vector3.UP
## Seconds in the air on this jump.
var airtime := 0.0
## 0..1 how much he's sliding sideways (spray, hiss).
var slide := 0.0
## Smoothed carve, -1..1 (lean, arms, camera roll).
var carve := 0.0
## Sideways acceleration he's pulling (m/s²).
var lateral_accel := 0.0
var input := SurfInput.new()

var player: Player
var terrain: SurfTerrain
var rig: RiderRig
var shadow_rig: RiderRig
var ragdoll: SurfRagdoll
var board: SurfBoard
var trail: SurfTrail
var fx: SurfFX
var cam: SurfCameraRig
var audio: SurfAudio

var _vy := 0.0
var _last_written := Vector3.INF
var _forces := Vector3.ZERO
var _forces_frame := -1
var _land_grace := 0.0
var _charge := 0.0
var _crouch := 0.2
var _crouch_v := 0.0
var _squash := 0.0
var _spin := 0.0
var _flip := 0.0
var _spin_v := 0.0
var _flip_v := 0.0
var _launch_basis := Basis()
var _air_heading := Vector3.FORWARD
var _time := 0.0
var _state_time := 0.0
var _from_points := PackedVector3Array()
var _board_from := Transform3D()
var _board_vel := Vector3.ZERO
var _board_spin := Vector3.ZERO
var _board_xf := Transform3D()
var _history: Array = []
var _roll := 0.0
var _up := Vector3.UP
var _driving := true
var _points := PackedVector3Array()
var _ink_node: Node


## Give `p` a board on `t`. Reuses the one he has.
static func attach(p: Player, t: SurfTerrain) -> Surfer:
	for c in p.get_children():
		if c is Surfer:
			(c as Surfer).terrain = t
			return c
	var s := Surfer.new()
	s.name = "Surfer"
	s.terrain = t
	p.add_child(s)
	return s


func _ready() -> void:
	player = get_parent() as Player
	process_priority = 10
	rig = RiderRig.new(RiderRig.find_skeleton(player.model))
	var shadow_model := player.shadow_caster.get_node_or_null(^"Model")
	if shadow_model:
		shadow_rig = RiderRig.new(RiderRig.find_skeleton(shadow_model))
	board = SurfBoard.new()
	board.name = "Board"
	player.visual.add_child(board)
	var room := player.get_parent()
	trail = SurfTrail.new()
	trail.name = "SurfTrail"
	trail.surfer = self
	room.add_child(trail)
	fx = SurfFX.new()
	fx.name = "SurfFX"
	fx.surfer = self
	room.add_child(fx)
	audio = SurfAudio.new()
	audio.name = "SurfAudio"
	audio.surfer = self
	add_child(audio)
	if is_instance_valid(Game.camera):
		cam = SurfCameraRig.new()
		cam.name = "SurfCamera"
		cam.surfer = self
		cam.camera = Game.camera
		room.add_child(cam)
	_mount()
	pos = player.global_position
	var g := terrain.height(Vector2(pos.x, pos.z))
	pos.y = maxf(pos.y, g)
	prev_pos = pos
	heading = _flat(player.facing)
	_vy = 0.0
	_last_written = pos
	_up = terrain.normal(Vector2(pos.x, pos.z))
	_ink_node = get_tree().get_first_node_in_group(&"dither_look")


func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


## Takes over from walking (and the walking clips).
func _mount() -> void:
	player.driver = self
	player.animation_locked = true
	player.model.anim.stop()
	player.model.current = &""
	var sm := player.shadow_caster.get_node_or_null(^"Model") as LittleManModel
	if sm and sm.anim:
		sm.anim.stop()
		sm.current = &""
	board.visible = true
	if has_node(^"/root/Sound"):
		get_node(^"/root/Sound").footsteps_enabled = false


## Lets the walking body and its clips back (a story sequence moving him on foot).
func _dismount() -> void:
	player.animation_locked = false
	board.visible = false
	if has_node(^"/root/Sound"):
		get_node(^"/root/Sound").footsteps_enabled = true


## Player asks this every physics frame: false hands him back to walking for a while.
func is_driving() -> bool:
	var story := get_node_or_null(^"/root/Story")
	var want: bool = not (story != null and story.has_method(&"is_playing") and story.is_playing())
	if want != _driving:
		_driving = want
		if want:
			_mount()
			pos = player.global_position
			prev_pos = pos
			vel = Vector3.ZERO
			heading = _flat(player.facing)
			_last_written = pos
			state = State.RIDE
		else:
			_dismount()
	return _driving


# ------------------------------------------------------------------ rooms

## Add an acceleration (m/s²) this physics frame: currents, conveyors, wind.
func push(accel: Vector3) -> void:
	var f := Engine.get_physics_frames()
	if f != _forces_frame:
		_forces = Vector3.ZERO   # pushes from frames he didn't ride (held, dismounted) don't pile up
		_forces_frame = f
	_forces += accel


## A burst of speed along where he's going (gates, launch pads). Also grows flow.
func boost(amount: float, flow_gain := 0.12) -> void:
	var d := vel.normalized() if vel.length_squared() > 1.0 else heading
	vel += d * amount
	add_flow(flow_gain)
	boosted.emit(amount)
	if cam:
		cam.punch(amount)


func add_flow(amount: float) -> void:
	flow = clampf(flow + amount, 0.0, 1.0)


func speed() -> float:
	return vel.length()


func is_airborne() -> bool:
	return state == State.AIR


func is_wiped_out() -> bool:
	return state == State.WIPEOUT or state == State.RECOVER


## Put him somewhere (room spawns, tests): on the ground, still, facing `face`.
func place(at: Vector3, face := Vector3.ZERO) -> void:
	pos = at
	pos.y = terrain.height(Vector2(at.x, at.z))
	prev_pos = pos
	vel = Vector3.ZERO
	_vy = 0.0
	if face != Vector3.ZERO:
		heading = _flat(face)
	if state != State.RIDE:
		_end_wipeout()
	state = State.RIDE
	_write()


## Knock him off the board now (rooms can use it too: a hand swatting him, a wall of sand).
func wipeout(extra_vel := Vector3.ZERO) -> void:
	if state == State.WIPEOUT or state == State.RECOVER:
		return
	var v := vel + extra_vel
	var pts := _points if _points.size() == rig.count else rig.current_points()
	ragdoll = SurfRagdoll.new(rig, terrain)
	var tumble_axis := Vector3.UP.cross(v).normalized() if v.length() > 1.0 else heading.cross(Vector3.UP)
	var spin := tumble_axis * clampf(v.length() / 4.0, 1.5, 9.0) + Vector3.UP * randf_range(-2.0, 2.0)
	ragdoll.start(pts, v, spin, get_physics_process_delta_time())
	# The board flies on its own.
	_board_xf = board.global_transform
	_board_vel = v * 0.8 + Vector3.UP * 3.0
	_board_spin = Vector3(randf_range(-9, 9), randf_range(-12, 12), randf_range(-9, 9))
	board.top_level = true
	board.global_transform = _board_xf
	state = State.WIPEOUT
	_state_time = 0.0
	flow *= 0.5
	wiped_out.emit(v.length())
	if cam:
		cam.shake(clampf(v.length() / 30.0, 0.4, 1.0))
	if wipeout_slowmo < 1.0 and DisplayServer.get_name() != "headless":
		Engine.time_scale = wipeout_slowmo
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_interval(0.35)
		tw.tween_method(func(x: float) -> void: Engine.time_scale = x, wipeout_slowmo, 1.0, 0.5)


# ------------------------------------------------------------------ physics

## Called by Player._physics_process while he's on the board.
func drive(delta: float) -> void:
	_time += delta
	_state_time += delta
	if _forces_frame != Engine.get_physics_frames():
		_forces = Vector3.ZERO
	input.update(delta, player.controls_enabled and state != State.WIPEOUT and state != State.RECOVER)
	_adopt_external_moves()
	prev_pos = pos
	match state:
		State.RIDE:
			_ride(delta)
		State.AIR:
			_air(delta)
		State.WIPEOUT:
			_wipeout(delta)
		State.RECOVER:
			_recover(delta)
	_forces = Vector3.ZERO
	_update_flow(delta)
	_write()


func _adopt_external_moves() -> void:
	# Something teleported him (a spawn, a test, a room's rule): start from there.
	if _last_written != Vector3.INF and player.global_position.distance_to(_last_written) > 0.05:
		var at := player.global_position
		var g := terrain.height(Vector2(at.x, at.z))
		pos = at
		prev_pos = at
		if at.y - g < 1.5:
			pos.y = g
			if state == State.AIR:
				state = State.RIDE
			_vy = 0.0
		elif state == State.RIDE:
			_go_air(Vector3(vel.x, 0.0, vel.z))


func _write() -> void:
	player.global_position = pos
	player.velocity = vel
	var f := _flat(vel) if Vector2(vel.x, vel.z).length() > 0.5 else _flat(heading)
	player.facing = f
	var moving := vel.length() > 0.5
	if moving != player.is_walking:
		player.is_walking = moving
		player.walking_changed.emit(moving)
	_last_written = pos


func _ride(dt: float) -> void:
	var xz := Vector2(pos.x, pos.z)
	var s := terrain.sample(xz)
	var n := Vector3(-s.y, 1.0, -s.z).normalized()
	ground_normal = n
	var g := terrain.gravity
	var gvec := Vector3(0, -g, 0)
	var slope := gvec - n * gvec.dot(n)
	var vt := vel - n * vel.dot(n)
	var sp := vt.length()
	var vdir := vt / sp if sp > 0.05 else heading
	# Pump: tucked, the slope pulls harder; tucked uphill, it costs.
	var tucked := input.tuck or input.jump_held
	var k := 1.0
	if tucked:
		k = tuck_downhill if slope.dot(vdir) > 0.0 else tuck_uphill
	var a := slope * k
	# Drag and friction.
	var dk := drag_tucked if tucked else drag
	a -= vdir * (dk * sp * sp + rolling * g * n.y) * (1.0 if sp > 0.05 else 0.0)
	# Paddle on the flat, brake on demand.
	var nose := _nose_for(vdir)
	if input.lean > 0.0 and sp < paddle_top:
		a += nose * paddle_accel * input.lean * (1.0 - sp / paddle_top)
	var braking := input.lean < -0.1
	if braking and sp > 0.1:
		a -= vdir * brake_decel * -input.lean
	a += _forces - n * _forces.dot(n)
	vt += a * dt
	# Carve: turn the board, then let the velocity follow as far as grip allows.
	var turn := lerpf(turn_rate_slow, turn_rate_fast, clampf(sp / 45.0, 0.0, 1.0))
	if tucked:
		turn *= 0.75
	if braking:
		turn *= 1.3
	heading = _tangent(heading.rotated(n, -input.steer * turn * dt), n)
	sp = vt.length()
	var turned := 0.0
	if sp > 0.5:
		vdir = vt / sp
		var want := _nose_for(vdir)
		var ang := vdir.signed_angle_to(want, n)
		if absf(input.steer) < 0.1 and not braking:
			# Let go and the board lines back up with the travel.
			heading = _tangent(heading.lerp(_nose_sign(vdir) * vdir, 1.0 - exp(-self_align * dt)), n)
			want = _nose_for(vdir)
			ang = vdir.signed_angle_to(want, n)
		var max_turn := grip / sp * dt
		turned = clampf(ang, -max_turn, max_turn)
		vdir = vdir.rotated(n, turned)
		var side := absf(sin(clampf(absf(ang) - absf(turned), 0.0, PI * 0.5)))
		if braking:
			side = maxf(side, -input.lean * 0.8)
		slide = lerpf(slide, side, 1.0 - exp(-10.0 * dt))
		sp *= 1.0 - slide_drag * side * dt
		vt = vdir * sp
	else:
		slide = lerpf(slide, 0.0, 1.0 - exp(-10.0 * dt))
	lateral_accel = turned / dt * sp
	carve = lerpf(carve, clampf(input.steer * (0.4 + 0.6 * clampf(sp / 25.0, 0.0, 1.0)), -1.0, 1.0), 1.0 - exp(-8.0 * dt))
	vel = vt.limit_length(max_speed)
	vel = terrain.confine(pos, vel, dt)

	# Pop: hold to crouch, release to jump off the board's normal.
	if input.jump_held:
		_charge = minf(_charge + dt / charge_time, 1.0)
	if input.jump_released and _land_grace <= 0.0:
		var pop := lerpf(pop_min, pop_max, _charge)
		_charge = 0.0
		var hv := Vector3(vel.x, _vy, vel.z)
		_go_air(hv + n * pop)
		return
	if not input.jump_held:
		_charge = move_toward(_charge, 0.0, dt * 4.0)

	# Move along the ground and decide if the ground lets go of him.
	var nxz := xz + Vector2(vel.x, vel.z) * dt
	# The terrain has already stepped its clock this frame (it sits before him in the tree).
	var s1 := terrain.sample(nxz)
	var vy_follow := s1.y * vel.x + s1.z * vel.z + s1.w
	var need := (vy_follow - _vy) / dt
	_land_grace = maxf(_land_grace - dt, 0.0)
	if need < -g * stick and _land_grace <= 0.0 and Vector2(vel.x, vel.z).length() > 3.0:
		_go_air(Vector3(vel.x, _vy, vel.z))
		return
	var from := pos
	pos = Vector3(nxz.x, s1.x, nxz.y)
	_vy = vy_follow
	vel.y = vy_follow - s1.w   # the surface's own motion isn't his speed along it
	_sweep_obstacles(from, dt)


func _go_air(v: Vector3) -> void:
	state = State.AIR
	_state_time = 0.0
	airtime = 0.0
	vel = v
	_spin = 0.0
	_flip = 0.0
	_spin_v = 0.0
	_flip_v = 0.0
	_air_heading = heading
	_launch_basis = _board_basis(heading, ground_normal, 0.0)
	pos.y += 0.02
	launched.emit(vel.length())


func _air(dt: float) -> void:
	airtime += dt
	var g := terrain.gravity
	var tucked := input.tuck or input.jump_held
	vel.y -= g * (air_tuck_gravity if tucked else 1.0) * dt
	vel -= vel * vel.length() * air_drag * dt
	vel += _forces * dt
	# Steer a little in the air; mostly it spins and flips him.
	var hv := Vector2(vel.x, vel.z)
	if hv.length() > 1.0:
		var r := hv.rotated(-input.steer * 0.22 * dt)
		vel.x = r.x
		vel.z = r.y
	var spin_boost := 1.25 if tucked else 1.0
	_spin_v = lerpf(_spin_v, -input.steer * air_spin_rate * spin_boost, 1.0 - exp(-7.0 * dt))
	_flip_v = lerpf(_flip_v, input.lean * air_flip_rate * spin_boost if airtime > 0.12 else 0.0, 1.0 - exp(-7.0 * dt))
	_spin += _spin_v * dt
	_flip += _flip_v * dt
	# Landing assist: close to the ground and close to clean, settle the rest of the way.
	var ground := terrain.height(Vector2(pos.x, pos.z))
	var above := pos.y - ground
	var t_land := above / maxf(-vel.y, 0.5)
	if t_land < 0.35 and vel.y < 0.0:
		var target_spin := _nearest_clean_spin()
		var e_spin := target_spin - _spin
		if absf(e_spin) < deg_to_rad(45.0) and absf(input.steer) < 0.5:
			_spin += e_spin * (1.0 - exp(-10.0 * dt))
			_spin_v *= 0.8
		var target_flip := roundf(_flip / TAU) * TAU
		var e_flip := target_flip - _flip
		if absf(e_flip) < deg_to_rad(65.0) and absf(input.lean) < 0.5:
			_flip += e_flip * (1.0 - exp(-10.0 * dt))
			_flip_v *= 0.8
	var from := pos
	pos += vel * dt
	vel = terrain.confine(pos, vel, dt)
	_sweep_obstacles(from, dt)
	if state != State.AIR:
		return
	var s := terrain.sample(Vector2(pos.x, pos.z))
	if pos.y <= s.x:
		_land(s)


func _nearest_clean_spin() -> float:
	# Spin at which the nose (or tail) lines up with the horizontal travel.
	var hv := _flat(vel)
	var base := _air_heading
	var a := base.signed_angle_to(hv, Vector3.UP)
	var best := a
	var best_d := INF
	for k in range(-6, 7):
		var cand := a + PI * k
		var d := absf(cand - _spin)
		if d < best_d:
			best_d = d
			best = cand
	return best


func _land(s: Vector4) -> void:
	var n := Vector3(-s.y, 1.0, -s.z).normalized()
	ground_normal = n
	var nose := (_air_board_basis() * Vector3.FORWARD)
	var vt := vel - n * vel.dot(n)
	var impact := maxf(-vel.dot(n) + s.w * n.y, 0.0)
	var nose_t := _tangent(nose, n)
	var align := absf(nose_t.dot(vt.normalized())) if vt.length() > 1.0 else 1.0
	var flip_err := absf(wrapf(_flip, -PI, PI))
	var ok := impact < max_impact and align > cos(deg_to_rad(max_landing_angle)) and flip_err < deg_to_rad(max_flip_error)
	pos.y = s.x
	if not ok:
		state = State.RIDE   # wipeout() reads the riding pose
		wipeout(Vector3.ZERO)
		return
	var quality := clampf(vt.length() / maxf(vel.length(), 0.01), 0.0, 1.0)
	var keep := lerpf(0.78, 1.0, quality) * lerpf(0.85, 1.0, inverse_lerp(cos(deg_to_rad(max_landing_angle)), 1.0, align))
	if quality > 0.93:
		keep += perfect_bonus
		add_flow(0.06)
	vel = vt * keep
	heading = nose_t if nose_t.length_squared() > 0.1 else _tangent(vel, n)
	_vy = s.y * vel.x + s.z * vel.z + s.w
	vel.y = _vy - s.w
	state = State.RIDE
	_state_time = 0.0
	_land_grace = 0.12
	_squash = clampf(impact / 18.0, 0.15, 1.0)
	var half_spins := int(roundf(absf(_spin) / PI))
	var flips := int(roundf(absf(_flip) / TAU))
	if airtime > 0.6:
		add_flow(clampf(airtime * 0.04, 0.0, 0.12))
	if half_spins >= 1 or flips >= 1:
		add_flow(0.08 * half_spins + 0.2 * flips)
		trick_landed.emit(half_spins, flips, airtime)
	landed.emit(quality, impact)
	if cam:
		cam.shake(clampf(impact / 40.0, 0.05, 0.6))


func _wipeout(dt: float) -> void:
	ragdoll.step(dt)
	var c := ragdoll.center()
	pos = Vector3(c.x, terrain.height(Vector2(c.x, c.z)), c.z)
	vel = ragdoll.center_velocity(dt)
	slide = 0.0
	_step_loose_board(dt)
	if (_state_time > wipeout_min_time and ragdoll.still > 0.35) or _state_time > wipeout_max_time:
		state = State.RECOVER
		_state_time = 0.0
		_from_points = ragdoll.pos.duplicate()
		_board_from = board.global_transform
		var d := _flat(ragdoll.center_velocity(dt))
		if d.length_squared() < 0.5:
			d = _flat(heading)
		heading = _tangent(d, terrain.normal(Vector2(pos.x, pos.z)))
		vel = Vector3.ZERO
		_vy = 0.0


func _recover(_dt: float) -> void:
	pos.y = terrain.height(Vector2(pos.x, pos.z))
	vel = Vector3.ZERO
	if _state_time >= recover_time:
		_end_wipeout()
		recovered.emit()


func _end_wipeout() -> void:
	state = State.RIDE
	_state_time = 0.0
	board.top_level = false
	board.transform = Transform3D()
	ragdoll = null
	_land_grace = 0.3


func _step_loose_board(dt: float) -> void:
	var g := terrain.gravity
	_board_vel.y -= g * dt
	var o := _board_xf.origin + _board_vel * dt
	var b := _board_xf.basis
	var w := _board_spin.length()
	if w > 0.001:
		b = Basis(_board_spin / w, w * dt) * b
	var s := terrain.sample(Vector2(o.x, o.z))
	if o.y < s.x + 0.03:
		var n := Vector3(-s.y, 1.0, -s.z).normalized()
		o.y = s.x + 0.03
		var vn := _board_vel.dot(n)
		if vn < 0.0:
			_board_vel -= n * vn * 1.3
		_board_vel *= 1.0 - minf(4.0 * dt, 1.0)
		_board_spin *= 1.0 - minf(5.0 * dt, 1.0)
		# Settle flat (either face down) on the sand.
		var up := b.y if b.y.dot(n) >= 0.0 else -b.y
		b = Basis(Quaternion(up.normalized(), n)).slerp(Basis(), 1.0 - minf(6.0 * dt, 1.0)) * b
	_board_xf = Transform3D(b.orthonormalized(), o)


func _sweep_obstacles(from: Vector3, dt: float) -> void:
	if not player.is_inside_tree():
		return
	var motion := pos - from
	if motion.length_squared() < 1e-6:
		return
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), from + Vector3.UP * 0.9)
	q.motion = motion
	var ex: Array[RID] = terrain.ground_bodies.duplicate()
	ex.append(player.get_rid())
	q.exclude = ex
	var r := space.cast_motion(q)
	if r.is_empty() or r[1] >= 1.0:
		return
	q.transform.origin += motion * r[1]
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	var hit_n: Vector3 = info.get("normal", -motion.normalized())
	hit_n.y = 0.0
	hit_n = hit_n.normalized() if hit_n.length_squared() > 0.01 else -_flat(motion)
	pos = from + motion * r[0]
	var into := -vel.dot(hit_n)
	if into > crash_speed:
		wipeout(hit_n * into * 0.6)
		return
	if into > 0.0:
		vel += hit_n * into * 1.15
		if cam:
			cam.shake(clampf(into / 20.0, 0.1, 0.5))
		if audio:
			audio.bump(into)


func _update_flow(dt: float) -> void:
	var sp := vel.length()
	if state == State.RIDE or state == State.AIR:
		if sp > 24.0:
			flow += (sp - 24.0) / 900.0 * dt
		elif sp < 12.0:
			flow -= 0.03 * dt
		flow -= 0.006 * dt
	flow = clampf(flow, 0.0, 1.0)
	if has_node(^"/root/Sound"):
		get_node(^"/root/Sound").set_music_intensity(0.3 + 0.7 * flow)


# ------------------------------------------------------------------ the look

func _process(delta: float) -> void:
	if not _driving or rig == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var at := render_position()
	var t := _time + f * get_physics_process_delta_time()
	# Springy crouch: tuck, charging a pop, and the squash of a landing.
	var want := 0.22
	if input.tuck:
		want = 0.62
	want = maxf(want, 0.35 + 0.6 * _charge)
	if state == State.AIR:
		want = 0.55 if input.tuck else 0.3
	_squash = move_toward(_squash, 0.0, delta * 2.5)
	want = clampf(want + _squash * 0.8, 0.0, 1.0)
	_crouch_v += ((want - _crouch) * 220.0 - _crouch_v * 22.0) * delta
	_crouch += _crouch_v * delta
	_crouch = clampf(_crouch, -0.1, 1.1)
	match state:
		State.RIDE, State.AIR:
			var basis: Basis
			if state == State.AIR:
				basis = _air_board_basis()
			else:
				_up = _up.lerp(ground_normal, 1.0 - exp(-14.0 * delta)).normalized()
				var lean := clampf(atan2(-lateral_accel, terrain.gravity), -0.95, 0.95)
				_roll = lerpf(_roll, lean, 1.0 - exp(-10.0 * delta))
				basis = _board_basis(heading, _up, _roll)
			player.visual.global_transform = Transform3D(basis, at)
			var air := clampf(airtime * 3.0, 0.0, 1.0) if state == State.AIR else 0.0
			var grab := (1.0 if input.tuck else 0.0) * air
			var shift := input.lean * 0.6 * (0.0 if state == State.AIR else 1.0)
			var body := rig.stance(_crouch, shift, carve * _side_sign(), air, grab, 1.0, t)
			_points = RiderRig.body_to_world(body, player.visual.global_transform)
			rig.apply(_points)
		State.WIPEOUT:
			_points = ragdoll.pos.duplicate()
			rig.apply(_points)
			board.global_transform = _board_xf
		State.RECOVER:
			var k := smoothstep(0.0, 1.0, _state_time / recover_time)
			var n := terrain.normal(Vector2(at.x, at.z))
			var basis := _board_basis(heading, n, 0.0)
			player.visual.global_transform = Transform3D(basis, at)
			var stand := RiderRig.body_to_world(rig.stance(lerpf(0.9, 0.3, k), 0.0, 0.0, 0.0, 0.0, k, t), player.visual.global_transform)
			_points = PackedVector3Array()
			_points.resize(stand.size())
			for i in stand.size():
				_points[i] = _from_points[i].lerp(stand[i], k)
			rig.apply(_points)
			board.global_transform = _board_from.interpolate_with(player.visual.global_transform, smoothstep(0.0, 0.7, k))
	_update_shadow()
	board.flow = flow
	board.speed = vel.length()


## Where he is this render frame (between physics steps).
func render_position() -> Vector3:
	return prev_pos.lerp(pos, Engine.get_physics_interpolation_fraction())


## Body points of the little man this frame (world).
func points() -> PackedVector3Array:
	return _points


func _update_shadow() -> void:
	if shadow_rig == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_history.append([now, _points.duplicate(), player.visual.global_transform])
	var cutoff := now - player.shadow_lag
	while _history.size() > 1 and _history[1][0] <= cutoff:
		_history.pop_front()
	var past: Array = _history[0]
	player.shadow_caster.global_transform = past[2]
	shadow_rig.apply(past[1])


# ------------------------------------------------------------------ helpers

## The board's basis: nose along `nose_dir`, standing on `up`, rolled into the turn.
func _board_basis(nose_dir: Vector3, up: Vector3, roll: float) -> Basis:
	var nose := _tangent(nose_dir, up)
	var z := -nose
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z)
	if absf(roll) > 0.0001:
		b = Basis(nose, roll * _side_sign()) * b
	return b.orthonormalized()


func _air_board_basis() -> Basis:
	var b := Basis(Vector3.UP, _spin) * _launch_basis
	# Lift toward level as he leaves the lip, then flip about the nose.
	var lvl := _board_basis(Basis(Vector3.UP, _spin) * _air_heading, Vector3.UP, 0.0)
	b = b.slerp(lvl, clampf(airtime * 2.5, 0.0, 1.0))
	return (b * Basis(Vector3.FORWARD, _flip)).orthonormalized()


## +1 when the nose leads, -1 riding backwards.
func _nose_sign(vdir: Vector3) -> float:
	return 1.0 if heading.dot(vdir) >= 0.0 else -1.0


func _nose_for(vdir: Vector3) -> Vector3:
	return heading * _nose_sign(vdir)


func _side_sign() -> float:
	var v := _flat(vel)
	return 1.0 if v.length_squared() < 0.01 or heading.dot(v) >= 0.0 else -1.0


static func _tangent(v: Vector3, n: Vector3) -> Vector3:
	var t := v - n * v.dot(n)
	return t.normalized() if t.length_squared() > 1e-8 else (n.cross(Vector3.RIGHT)).normalized()


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD
