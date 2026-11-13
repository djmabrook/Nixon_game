extends Node
## The spiral's story state: how much of the world has its colour back.
##
## The shore starts drained: black, bone and sand, black palms and sea, unlit beacons,
## dry grooves with only a faint dotted pulse of each room's ink running inward.
## Arriving with an ink plants it (Game.bring_home()), and the hub plays the planting:
## the ink fills its groove from the pit up to its beacon, then lights what it owns:
##   ember   -> every beacon around the rim catches in turn, embers rise from the pit,
##              the far beacon tower is lit
##   salmon  -> a pink storm bank rolls in over the sea
##   crimson -> the islets and the horizon turn crimson, the black disc in the sky is gone
## and sea and palms get back a third of their colour.
## With all three home, three rings of ink circle the pit so it reads as an eye. It blinks
## once, and the mountain's ultraviolet groove uncoils, pointing at the Watcher.
## At dawn (Game flag "dawn", or the hub's set_dawn()) the sun rises where the palm
## shadows always pointed and the Watcher's lights go out.
##
## Which inks are home is Game.inks_home. What the hub has already shown is kept as Game
## metadata (hub_shown_inks, hub_eye_open) so each moment plays once; it's trimmed back
## if a new cycle clears the inks.
## A room's ink is its root's gives_ink. A locked room (Room.required_inks) has no groove
## until it opens; one that needs all three inks (the mountain) opens with the eye.

const INK_COLORS := {
	&"ember": Color(1.0, 0.32, 0.08),
	&"salmon": Color(1.0, 0.55, 0.52),
	&"crimson": Color(0.85, 0.05, 0.12),
}
## The colour of a groove with no ink of its own (the mountain): the ink nobody can see.
const ULTRAVIOLET := Color(0.55, 0.2, 1.0)

const PLANTED_META := &"hub_shown_inks"
const EYE_META := &"hub_eye_open"
## Dev only: set this Game meta to an Array of ink ids (and "dawn") to preview states.
const PREVIEW_META := &"hub_preview"

## How long the ink takes to fill a groove from the pit to its beacon.
@export var fill_time := 5.0
@export var islet_drained := Color(0.03, 0.025, 0.025)
@export var islet_crimson := Color(0.45, 0.05, 0.07)

## Set by the hub's set_dawn() for the ending: -1 follow Game, 0 night, 1 dawn.
var dawn_override := -1

var hub: Room
var _sand_mat: ShaderMaterial
var _sea_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _rock_mat: StandardMaterial3D
var _landmarks: Node
var _embers: CPUParticles3D
var _env: Environment
var _moon: DirectionalLight3D
var _moon_basis: Basis
var _playing := false


func _ready() -> void:
	hub = get_parent()
	await hub.ready
	_sand_mat = hub.get_node("SandVortex").material
	_sea_mat = (hub.get_node("Sea") as MeshInstance3D).mesh.surface_get_material(0)
	_env = (hub.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sky_mat = _env.sky.sky_material
	_rock_mat = (hub.get_node("Scenery/IslandWest") as MeshInstance3D).mesh.surface_get_material(0)
	_landmarks = hub.get_node("Landmarks")
	_embers = hub.get_node("Vortex/Embers")
	_moon = hub.get_node("Moon")
	_moon_basis = _moon.basis
	Game.ink_home.connect(_on_ink_home)
	apply_static()


static func ink_color(ink: StringName) -> Color:
	return INK_COLORS.get(ink, ULTRAVIOLET)


# --- What the story says -------------------------------------------------------

func _preview() -> Variant:
	return Game.get_meta(PREVIEW_META) if Game.has_meta(PREVIEW_META) else null


func inks_home() -> Array[StringName]:
	var out: Array[StringName] = []
	var preview = _preview()
	if preview is Array:
		for v in preview:
			if String(v) != "dawn":
				out.append(StringName(v))
		return out
	out.assign(Game.inks_home)
	return out


func is_dawn() -> bool:
	if dawn_override >= 0:
		return dawn_override == 1
	var preview = _preview()
	if preview is Array:
		return preview.has(&"dawn") or preview.has("dawn")
	return Game.get_flag(&"dawn", false) == true


## Inks whose planting the hub has shown.
func planted() -> Array:
	var home := inks_home()
	var shown: Array = Game.get_meta(PLANTED_META, [])
	return shown.filter(func(i): return home.has(i))


func eye_open() -> bool:
	return Game.get_meta(EYE_META, false) and inks_home().size() >= 3


## Inks home but not yet shown: these play their planting.
func pending() -> Array[StringName]:
	var out: Array[StringName] = []
	var done := planted()
	for id in inks_home():
		if not done.has(id):
			out.append(id)
	return out


## Whether room `id`'s groove should be showing now.
func groove_shown(id: StringName) -> bool:
	if Game.is_room_locked(id):
		return false
	return not hub.opens_with_eye(id) or eye_open()


# --- Applying it ----------------------------------------------------------------

## Set the world to match what has been shown, with no animation.
func apply_static() -> void:
	if is_dawn():
		Game.set_meta(PLANTED_META, inks_home())
		Game.set_meta(EYE_META, true)
	if not eye_open():
		Game.set_meta(EYE_META, false)
	var done := planted()
	var dawn := is_dawn()
	_set_color_amount(1.0 if dawn else float(done.size()) / 3.0)
	_set_ember(done.has(&"ember") or dawn, false)
	_set_storm(1.0 if done.has(&"salmon") or dawn else 0.0)
	_set_crimson(1.0 if done.has(&"crimson") or dawn else 0.0)
	for i in hub.room_count():
		var id: StringName = hub.room_at(i)
		var shown := groove_shown(id)
		var ink: StringName = hub.room_ink(id)
		var full: bool = done.has(ink) or (shown and hub.opens_with_eye(id) and dawn)
		hub.set_arm_fill(i, 1.0 if full else 0.0)
		hub.set_arm_reach(i, hub.arm_outer_radius + 20.0 if shown else 0.0)
		hub.set_arm_open(i, shown)
	_set_eye_rings(1.0 if eye_open() else 0.0)
	_set_dawn(1.0 if dawn else 0.0)
	hub.refresh_arms()


func _set_color_amount(a: float) -> void:
	_sand_mat.set_shader_parameter("color_amount", a)
	_sea_mat.set_shader_parameter("color_amount", a)
	for palm in hub.get_node("Scenery").get_children():
		if palm.get("color_amount") != null:
			palm.set("color_amount", a)
	for n in get_tree().get_nodes_in_group(&"hub_drainable"):
		if hub.is_ancestor_of(n):
			n.set("color_amount", a)
	_landmarks.set("color_amount", a)
	_env.ambient_light_color = Color(0.55, 0.52, 0.48).lerp(Color(0.75, 0.42, 0.36), a)
	_env.fog_light_color = Color(0.16, 0.15, 0.14).lerp(Color(0.3, 0.06, 0.05), a)


func _set_ember(on: bool, staggered: bool) -> void:
	_embers.emitting = on
	_embers.visible = on
	_landmarks.set("beacon", on)
	_sand_mat.set_shader_parameter("rim_color", Color(1.0, 0.25, 0.08, 1.0 if on else 0.0))
	(hub.get_node("PitGlow") as OmniLight3D).visible = on
	var stakes: Array = hub.stakes()
	for k in stakes.size():
		var stake: Node = stakes[k]
		if staggered and on:
			get_tree().create_timer(0.35 * k).timeout.connect(func() -> void:
				if is_instance_valid(stake):
					stake.set("lit", true))
		else:
			stake.set("lit", on)


func _set_storm(t: float) -> void:
	_landmarks.set("pink_storm", t > 0.0)
	_sky_mat.set_shader_parameter("storm_amount", t)


func _set_crimson(t: float) -> void:
	_rock_mat.albedo_color = islet_drained.lerp(islet_crimson, t)
	_sky_mat.set_shader_parameter("horizon_amount", t)
	_landmarks.set("black_disc", t < 0.5)


func _set_eye_rings(t: float) -> void:
	_sand_mat.set_shader_parameter("eye_rings", _rings(3 if t > 0.0 else 0))


## Ring colours in the order the inks came home, the first `count` of them visible.
func _rings(count: int) -> Array[Color]:
	var order := inks_home()
	var rings: Array[Color] = []
	for k in 3:
		var c: Color = ink_color(order[k]) if k < order.size() else Color.BLACK
		rings.append(Color(c.r, c.g, c.b, 1.0 if k < count else 0.0))
	return rings


func _set_dawn(t: float) -> void:
	_sky_mat.set_shader_parameter("dawn", t)
	_landmarks.set("watcher_eyes", t < 0.5)
	_landmarks.set("dawn", t)
	# The sun rises where the moon has been throwing every shadow.
	var toward: Vector3 = -_moon_basis.z
	var sun := Vector3(toward.x, 0.0, toward.z).normalized()
	sun.y = 0.08
	sun = sun.normalized()
	_sky_mat.set_shader_parameter("sun_dir", sun)
	var ra := hub.get_node_or_null(^"RoomAudio")
	if ra:
		ra.set("bed", &"bed_dawn" if t > 0.5 else &"bed_hub_night")
	if hub.sound() and Game.current_room == hub:
		hub.sound().set_bed(&"bed_dawn" if t > 0.5 else &"bed_hub_night")
	var lamp: Node3D = Game.player.get_node_or_null(^"HubLamp") if is_instance_valid(Game.player) else null
	if lamp:
		lamp.visible = t <= 0.5
	if t > 0.5:
		_moon.light_color = Color(0.95, 0.86, 0.78)
		_moon.light_energy = 0.6
		_moon.basis = Basis.looking_at(-sun, Vector3.UP)
		_env.fog_light_color = Color(0.85, 0.62, 0.5)
		_env.ambient_light_color = Color(0.62, 0.55, 0.52)
	else:
		_moon.basis = _moon_basis
		_moon.light_color = Color(0.62, 0.7, 1.0)
		_moon.light_energy = 0.55


# --- The planting -----------------------------------------------------------------

func _on_ink_home(_ink: StringName) -> void:
	# Planted while in the hub (by the hub itself on arrival, or a story sequence).
	play_pending.call_deferred()


## Play the planting for every ink that came home since it was last shown, then the eye
## and any grooves that have just unlocked. Takes the camera and holds the little man.
func play_pending() -> void:
	if _playing or not is_inside_tree():
		return
	if pending().is_empty() and not _has_unlocked_hidden() and not (planted().size() >= 3 and not eye_open()):
		return
	_playing = true
	while Game.is_travelling():
		await get_tree().process_frame
	var p := Game.player
	if p:
		p.controls_enabled = false
	for id in pending():
		await _plant(id)
	if planted().size() >= 3 and not eye_open():
		await _open_eye()
	await _uncoil_unlocked()
	if is_instance_valid(p):
		p.controls_enabled = true
	_playing = false


func is_playing() -> bool:
	return _playing


func _plant(ink_id: StringName) -> void:
	var arm: int = hub.arm_for_ink(ink_id)
	var effect_time := 4.0
	_shot_over_arm(arm, fill_time + effect_time)
	await get_tree().create_timer(2.5).timeout   # the camera flies out
	if arm >= 0:
		var tw := create_tween()
		tw.tween_method(func(f: float) -> void:
			hub.set_arm_fill(arm, f)
			hub.refresh_arms()
		, 0.0, 1.0, fill_time).set_trans(Tween.TRANS_SINE)
		await tw.finished
	if hub.sound():
		hub.sound().play(StringName("ink_%s_home" % ink_id))
	var done := planted()
	done.append(ink_id)
	Game.set_meta(PLANTED_META, done)
	var tw2 := create_tween().set_parallel(true)
	var from_amount: float = _sand_mat.get_shader_parameter("color_amount")
	tw2.tween_method(_set_color_amount, from_amount, float(done.size()) / 3.0, effect_time)
	match ink_id:
		&"ember":
			_set_ember(true, true)
		&"salmon":
			_landmarks.set("pink_storm", true)
			tw2.tween_method(_set_storm, 0.0, 1.0, effect_time)
			var storm: Node3D = _landmarks.get_node("PinkStorm")
			var home := storm.position
			storm.position = home + Vector3(0, -200, 0)
			tw2.tween_property(storm, "position", home, effect_time).set_trans(Tween.TRANS_SINE)
		&"crimson":
			tw2.tween_method(_set_crimson, 0.0, 1.0, effect_time)
	await tw2.finished
	await get_tree().create_timer(2.5).timeout   # the camera flies back


func _open_eye() -> void:
	_shot_over_pit(8.0)
	await get_tree().create_timer(2.5).timeout
	# Three rings of ink, in the order they came home.
	for k in 3:
		_sand_mat.set_shader_parameter("eye_rings", _rings(k + 1))
		await get_tree().create_timer(0.7).timeout
	# It blinks once.
	var pit: Vector3 = hub.get_node("Vortex").global_position
	if hub.sound():
		hub.sound().play_at(&"eyelids_close", pit)
		hub.sound().giant(&"giant_boom", pit, 1000.0)
	var blink := create_tween()
	blink.tween_method(func(v: float) -> void: _sand_mat.set_shader_parameter("lid", v), 0.0, 1.0, 0.35).set_ease(Tween.EASE_IN)
	blink.tween_interval(0.25)
	blink.tween_method(func(v: float) -> void: _sand_mat.set_shader_parameter("lid", v), 1.0, 0.0, 0.5).set_ease(Tween.EASE_OUT)
	await blink.finished
	Game.set_meta(EYE_META, true)
	await get_tree().create_timer(2.5).timeout


func _has_unlocked_hidden() -> bool:
	for i in hub.room_count():
		var id: StringName = hub.room_at(i)
		if not hub.room_open(id) and groove_shown(id):
			return true
	return false


## Grooves of rooms that have just unlocked uncoil from the pit out to their beacon.
func _uncoil_unlocked() -> void:
	for i in hub.room_count():
		var id: StringName = hub.room_at(i)
		if hub.room_open(id) or not groove_shown(id):
			continue
		_shot_over_arm(i, 8.0)
		await get_tree().create_timer(2.5).timeout
		if hub.sound():
			hub.sound().play(&"ink_ultraviolet_take")
		var tw := create_tween()
		tw.tween_method(func(rr: float) -> void:
			hub.set_arm_reach(i, rr)
			hub.refresh_arms()
		, hub.pit_radius, hub.arm_outer_radius + 20.0, 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await tw.finished
		hub.set_arm_open(i, true)
		await get_tree().create_timer(2.5).timeout


## Camera: high over the crater, looking down the length of a groove.
func _shot_over_arm(arm: int, hold: float) -> void:
	var cam := Game.camera
	if cam == null:
		return
	var pit: Vector3 = hub.get_node("Vortex").global_position
	var look: Vector3 = hub.arm_point(arm, 300.0) if arm >= 0 else pit
	var out: Vector3 = hub.arm_point(arm, 760.0) if arm >= 0 else pit + Vector3(500, 0, 500)
	cam.play_shot(out + Vector3.UP * 280.0, look, hold, 2.5)


func _shot_over_pit(hold: float) -> void:
	var cam := Game.camera
	if cam == null:
		return
	var pit: Vector3 = hub.get_node("Vortex").global_position
	cam.play_shot(pit + Vector3(1, 0, 1).normalized() * 260.0 + Vector3.UP * 300.0, pit, hold, 2.5)
