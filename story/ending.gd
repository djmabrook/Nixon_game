extends "res://story/sequence.gd"
## The ending, in the hub at dawn:
##   1. He rises out of the pit as the sky pales; the spiral is still.
##   2. On the tideline at sunrise, the camera pulls back further than it ever has: the
##      shore, the crater, the regions and the sleeping mountain, all at once.
##   3. It comes back down to him and lets him walk. The sun stands where every palm
##      shadow pointed. The Stray walks with him.
##   4. A little way on, the camera stops following. It settles out over the shallows and
##      stays. The picture draws in from the edges onto bare paper, and he walks off the
##      edge of the picture onto the paper margin. The Stray looks back once, at us, and
##      follows him out.
##   5. The empty shore holds. Silence. Black. Then the title shore, with his footprints.

const OVERLAY := preload("res://story/overlay.gd")
const STRAY_SCENE := "res://companions/stray/stray.tscn"
const STRAY_STANDIN := preload("res://story/props/stray_standin.gd")
const DAWN_LOOK := "res://shaders/presets/dawn.tres"

## Metres he walks along the tideline before the camera lets him go.
var walk_before_letting_go := 26.0
## The picture's rect on the paper once it has drawn in (UV x0, y0, x1, y1).
var picture_rect := Vector4(0.1, 0.1, 0.9, 0.8)
## If he stands still this long once the camera has let go, he walks on by himself.
var nudge_after := 14.0

var dressing: Node
var stray: Node3D
var overlay: CanvasLayer
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var env: Environment
var sun_dir := Vector3(1, 0.05, 0)

var _phase := &"rise"
var _walk_start := Vector3.ZERO
var _locked_at := 0.0
var _man_fig: Dictionary = {}
var _stray_fig: Dictionary = {}
var _last_screen := Vector2.ZERO
var _autowalk := false
var _pressed: Array[StringName] = []


func _init() -> void:
	sequence_name = &"ending"


func _ready() -> void:
	dressing = room().get_node(^"StoryDressing")
	hold()
	overlay = OVERLAY.new()
	overlay.name = "EndingOverlay"
	add_child(overlay)
	overlay.curtain = 1.0
	Game.player.visual.visible = false
	await dressing.wait_surveyed()
	shore = dressing.shore
	_still_the_hub()
	_make_dawn()
	await _rise()
	await _whole_land()
	await _walk_on()


# --- Setting the stage -------------------------------------------------------------------

## The spiral is at rest: no pull, no swallowing, the eyes on the mountain are out.
func _still_the_hub() -> void:
	var hub := room()
	if hub.has_method(&"set_dawn"):
		hub.call(&"set_dawn", true)
	hub.set_physics_process(false)
	# The hub holds him still on arrival and lets go from its own physics step, which is
	# now off; let go here instead.
	if is_instance_valid(Game.player):
		Game.player.set_physics_process(true)
	var vortex := hub.get_node_or_null(^"Vortex") as Area3D
	if vortex:
		vortex.set_deferred(&"monitoring", false)
	var landmarks := hub.get_node_or_null(^"Landmarks")
	if landmarks and landmarks.has_method(&"set_layer"):
		landmarks.call(&"set_layer", &"watcher", true)
		landmarks.call(&"set_layer", &"beacon", true)
		landmarks.call(&"set_layer", &"pink_storm", true)
		landmarks.call(&"set_layer", &"black_disc", false)
	if landmarks:
		var w := landmarks.get_node_or_null(^"Watcher")
		if w:
			for c in w.get_children():
				if String(c.name).begins_with("Eye"):
					c.visible = false
	if is_instance_valid(dressing.tv) and dressing.tv.has_method(&"close"):
		dressing.tv.call(&"close")
		dressing.tv.set(&"lid", 1.0)
	var moon := hub.get_node_or_null(^"Moon") as DirectionalLight3D
	if moon:
		create_tween().tween_property(moon, "light_energy", 0.0, 6.0 * time_scale)
	dressing.audio.set(&"surf", 0.45)
	dressing.audio.set(&"hum", 0.0)
	dressing.audio.set(&"dawn", 0.9)
	sound_call(&"unhush", [4.0])
	sound_call(&"set_bed", [&"bed_dawn"])
	dressing.tide.set(&"drain", 0.0)
	dressing.tide.set(&"lap", 1.2)


## The dawn sky, its sun and its light. The sun stands along the tideline, low over the
## sea, so he walks toward it at the end.
func _make_dawn() -> void:
	var a := shore.anchor(&"sun")
	var flat := shore.along
	if a:
		flat = a.global_position - shore.wake
		flat.y = 0.0
		flat = flat.normalized()
	sun_dir = (flat * 0.99 + Vector3.UP * 0.035).normalized()

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://story/dawn_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.55, 0.45)
	env.fog_density = 0.00045
	env.fog_sun_scatter = 0.35
	env.fog_sky_affect = 0.15
	cam.environment = env
	if is_instance_valid(Game.camera):
		Game.camera.environment = env

	sun = DirectionalLight3D.new()
	sun.name = "DawnSun"
	sun.light_color = Color(1.0, 0.72, 0.48)
	sun.light_energy = 0.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	_aim_sun(0.0)
	look_to(DAWN_LOOK, 2.0)


func _aim_sun(rise: float) -> void:
	var d := sun_dir
	d.y = lerpf(-0.04, 0.09, rise)
	d = d.normalized()
	sky_mat.set_shader_parameter("sun_dir", d)
	sky_mat.set_shader_parameter("rise", rise)
	sun.global_transform = Transform3D(Basis(), Vector3.ZERO).looking_at(-d, Vector3.UP if absf(d.y) < 0.99 else Vector3.BACK)
	sun.light_energy = lerpf(0.0, 1.6, smoothstep(0.0, 0.5, rise))
	env.ambient_light_energy = lerpf(0.35, 0.9, rise)


# --- 1: rising out of the pit ----------------------------------------------------------

func _rise() -> void:
	var p := Game.player
	var pit := shore.ground(shore.pit)
	var out := shore.wake - shore.pit
	out.y = 0.0
	out = out.normalized()
	p.global_position = pit + Vector3.DOWN * 10.0
	p.visual.scale = Vector3.ONE * 0.15
	p.visual.visible = true
	cut(pit + Vector3.UP * 110.0 + out * 70.0, pit, 38.0)
	glide(pit + Vector3.UP * 55.0 + out * 40.0 + out.cross(Vector3.UP) * 18.0, pit + Vector3.UP * 2.0, 9.0, 34.0)
	create_tween().tween_property(overlay, "curtain", 0.0, 2.5 * time_scale)
	var rise_t := create_tween()
	rise_t.tween_method(_aim_sun, 0.0, 0.35, 10.0 * time_scale)
	# Unwind out of the sand: the sinking spiral, played backwards.
	var start_a := 0.0
	var t := create_tween().set_parallel(true)
	t.tween_method(func(w: float) -> void:
		var e := (1.0 - w) * (1.0 - w)
		var a := start_a + e * TAU * 1.5
		var rr := 7.0 * e
		p.global_position = pit + Vector3(cos(a) * rr, -10.0 * e, sin(a) * rr)
		p.visual.rotation.y = a * 2.0
	, 0.0, 1.0, 6.0 * time_scale)
	t.tween_property(p.visual, "scale", Vector3.ONE, 6.0 * time_scale).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await t.finished
	p.face(out)
	await wait(2.5)
	var dip := create_tween()
	dip.tween_property(overlay, "curtain", 1.0, 1.4 * time_scale)
	await dip.finished


# --- 2: the whole land --------------------------------------------------------------------

func _whole_land() -> void:
	var p := Game.player
	_walk_start = shore.shore_point(-18.0, -1.5)
	place_player(_walk_start, shore.along)
	_ensure_stray()
	stray.global_position = _walk_start + shore.along * 1.6 - shore.inland * 0.8
	stray.visible = true
	if stray.has_method(&"follow"):
		stray.call(&"follow", p)
	var rise_t := create_tween()
	rise_t.tween_method(_aim_sun, 0.35, 0.7, 30.0 * time_scale)

	var close := _walk_start - shore.inland * 7.0 - shore.along * 3.0 + Vector3.UP * 2.0
	var land_centre := shore.pit + (shore.pit - shore.wake).normalized() * 600.0
	cut(close, _walk_start + Vector3.UP * 1.0, 40.0)
	create_tween().tween_property(overlay, "curtain", 0.0, 1.6 * time_scale)
	await wait(2.2)
	# Out to sea and up, further than anything before: he becomes a speck, then nothing,
	# and the whole land lies there in the morning.
	var far := shore.wake - shore.inland * 1900.0 + Vector3.UP * 820.0 - shore.along * 260.0
	var path := PackedVector3Array([
		close,
		_walk_start - shore.inland * 40.0 + Vector3.UP * 14.0,
		_walk_start - shore.inland * 320.0 + Vector3.UP * 150.0,
		far,
	])
	var looks := [_walk_start + Vector3.UP * 1.0, land_centre]
	var t := track(path, func() -> Vector3:
		var w := clampf((cam.global_position.distance_to(close)) / close.distance_to(far), 0.0, 1.0)
		return (looks[0] as Vector3).lerp(looks[1], smoothstep(0.0, 0.55, w))
	, 16.0, 40.0, 52.0)
	await t.finished
	await wait(5.0)
	# And back down to him.
	var back := PackedVector3Array([far, _walk_start - shore.inland * 260.0 + Vector3.UP * 90.0, _walk_start - shore.inland * 14.0 - shore.along * 9.0 + Vector3.UP * 4.0])
	var t2 := track(back, func() -> Vector3:
		var w := clampf(1.0 - cam.global_position.distance_to(_walk_start) / far.distance_to(_walk_start), 0.0, 1.0)
		return (looks[1] as Vector3).lerp(p.global_position + Vector3.UP * 1.0, smoothstep(0.3, 0.95, w))
	, 12.0, 52.0, 45.0)
	await t2.finished


# --- 3-5: walking off the picture -----------------------------------------------------

func _walk_on() -> void:
	await release(1.8)
	_phase = &"walking"


func _physics_process(_delta: float) -> void:
	_drive_autowalk()
	var p := Game.player
	if not is_instance_valid(p):
		return
	match _phase:
		&"walking":
			var gone := p.global_position - _walk_start
			gone.y = 0.0
			if gone.length() > walk_before_letting_go:
				_let_go()
		&"let_go":
			_watch_for_exit()
		&"paper":
			_watch_stray_exit()


## The camera stops following: it drifts out over the shallows, settles and stays.
func _let_go() -> void:
	_phase = &"settling"
	var p := Game.player
	hold()
	p.controls_enabled = true    # he is still his own; only the camera has stopped
	var here := p.global_position
	var eye := here - shore.inland * 24.0 + shore.along * 5.0 + Vector3.UP * 3.2
	var look := here + shore.along * 14.0 + shore.inland * 10.0 + Vector3.UP * 5.0
	await glide(eye, look, 4.0, 42.0).finished
	_locked_at = Time.get_ticks_msec() / 1000.0
	dressing.audio.set(&"dawn", 0.6)
	# The picture draws in from its edges onto the paper.
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(overlay, "rect", picture_rect, 5.0 * time_scale)
	t.tween_property(overlay, "paper_reveal", 1.0, 2.0 * time_scale)
	_phase = &"let_go"


func _watch_for_exit() -> void:
	var p := Game.player
	var size := overlay.call(&"screen_size") as Vector2
	var feet := cam.unproject_position(p.global_position)
	var head := cam.unproject_position(p.global_position + Vector3.UP * 1.7)
	var r: Vector4 = overlay.rect
	var inside := feet.x > r.x * size.x and feet.x < r.z * size.x and feet.y > r.y * size.y and feet.y < r.w * size.y
	var vel := (feet - _last_screen) * Engine.physics_ticks_per_second
	_last_screen = feet
	if not cam.is_position_behind(p.global_position) and inside:
		if Time.get_ticks_msec() / 1000.0 - _locked_at > nudge_after * time_scale and not p.is_walking:
			_autowalk = true
		return
	# Over the edge: from here on he is a few pixels of ink on the paper. Nothing is left
	# to hear.
	_phase = &"paper"
	sound_call(&"hush", [2.0, false])
	_autowalk = false
	p.controls_enabled = false
	p.velocity = Vector3.ZERO
	p.visual.visible = false
	var h := clampf(feet.y - head.y, 6.0, 40.0)
	if vel.length() < 6.0:
		vel = Vector2(16.0, 0.0)
	_man_fig = overlay.call(&"add_figure", &"man", feet, vel.normalized() * maxf(vel.length(), 14.0), h)
	_stray_exit_point = p.global_position + (p.global_position - _walk_start).normalized() * 4.0
	_stray_goodbye()


var _stray_exit_point := Vector3.ZERO
var _stray_crossing := false


func _stray_goodbye() -> void:
	if not is_instance_valid(stray):
		_finish()
		return
	if stray.has_method(&"walk_to"):
		await call_and_wait(stray, &"walk_to", [stray.global_position], 0.3)
	await wait(0.9)
	await call_and_wait(stray, &"look_at_camera", [1.6], 3.0)
	_stray_crossing = true
	call_and_wait(stray, &"walk_to", [_stray_exit_point + shore.along * 6.0], 12.0)


func _watch_stray_exit() -> void:
	if not _stray_crossing or not is_instance_valid(stray) or not stray.visible:
		return
	var size := overlay.call(&"screen_size") as Vector2
	var at := cam.unproject_position(stray.global_position)
	var top := cam.unproject_position(stray.global_position + Vector3.UP * 0.6)
	var r: Vector4 = overlay.rect
	var inside := at.x > r.x * size.x and at.x < r.z * size.x and at.y > r.y * size.y and at.y < r.w * size.y
	if inside:
		return
	stray.visible = false
	var vel: Vector2 = _man_fig.get("vel", Vector2(16, 0)) * 1.25
	_stray_fig = overlay.call(&"add_figure", &"stray", at, vel, clampf(at.y - top.y, 4.0, 14.0) * 1.4)
	_phase = &"gone"
	_finish()


func _finish() -> void:
	# Hold on the empty shore while they walk away across the paper.
	var size := overlay.call(&"screen_size") as Vector2
	var left := 30.0
	while left > 0.0:
		var out := true
		for f in [_man_fig, _stray_fig]:
			if not f.is_empty():
				var pos: Vector2 = f.pos
				if pos.x > -10.0 and pos.x < size.x + 10.0 and pos.y > -10.0 and pos.y < size.y + 20.0:
					out = false
		if out:
			break
		await get_tree().process_frame
		left -= get_process_delta_time()
	dressing.audio.set(&"dawn", 0.0)
	await wait(5.0)
	dressing.audio.set(&"surf", 0.0)
	var t := create_tween()
	t.tween_property(overlay, "curtain", 1.0, 2.5 * time_scale)
	await t.finished
	await wait(2.5)
	Story.set_flag(Story.FLAG_ENDING_SEEN, true)
	finished.emit(&"done")
	Story.show_title_next()
	Game.go_to_hub()


# --- helpers -----------------------------------------------------------------------------------

func _ensure_stray() -> void:
	for n in get_tree().get_nodes_in_group(&"stray"):
		if n is Node3D and room().is_ancestor_of(n):
			stray = n
			return
	if ResourceLoader.exists(STRAY_SCENE):
		stray = load(STRAY_SCENE).instantiate()
	else:
		stray = STRAY_STANDIN.new()
	stray.name = "Stray"
	room().add_child(stray)


## Walks him along the tideline toward the sun if the player has let go of the stick.
func _drive_autowalk() -> void:
	for a in _pressed:
		Input.action_release(a)
	_pressed.clear()
	if not _autowalk:
		return
	var c := get_viewport().get_camera_3d()
	if c == null:
		return
	var local := shore.along.rotated(Vector3.UP, -c.global_rotation.y)
	var pairs := [[&"move_right", local.x], [&"move_left", -local.x], [&"move_down", local.z], [&"move_up", -local.z]]
	for pair in pairs:
		if pair[1] > 0.05:
			Input.action_press(pair[0], clampf(pair[1], 0.0, 1.0))
			_pressed.append(pair[0])


func _exit_tree() -> void:
	for a in _pressed:
		Input.action_release(a)
	if is_instance_valid(Game.camera):
		Game.camera.environment = null
