@tool
class_name SurfTerrain
extends Node3D
## The ground a region is surfed on: a heightfield with static dunes and travelling swells.
## Put one in a room (see surf/README.md) and the little man rides instead of walking.
##
## The physics never asks the collision mesh where the ground is. It asks height(), which is
## the room's own static shape (`base_func`, or the static swells on flat ground) plus the
## moving swells. The same moving swells are drawn by surf_waves.gdshaderinc on every
## material listed in `materials`, from the same numbers, so the board sits on what you see.

## Fired once the little man has been given his board in this room.
signal rider_ready(surfer: Surfer)

## Dunes that never move. Baked into the room's ground mesh by whoever builds it (the room
## calls static_extra() for each vertex).
@export var static_waves: Array[SurfWave] = []
## Swells that roll across the ground. At most 8.
@export var moving_waves: Array[SurfWave] = []
## Ground materials that include surf_waves.gdshaderinc. They get the swells every frame.
@export var materials: Array[ShaderMaterial] = []
## Keep the rider inside this circle (xz, metres from `bounds_center`). 0 = no limit.
@export var bounds_radius := 0.0
@export var bounds_center := Vector2.ZERO
## Gravity for everything surfing here (m/s²). Rooms can bend it, like everything else.
@export var gravity := 17.0
## Ride here at all. A room can switch surfing off and walk instead.
@export var enabled := true

## Full static ground height at an xz point (world). Rooms with their own shape set this,
## and include static_extra() in it. Unset: flat ground at this node's height plus static swells.
var base_func: Callable
## Bodies the rider passes through (the ground itself). Everything else on the world layer
## is an obstacle he can hit.
var ground_bodies: Array[RID] = []
## Seconds of swell time. Advances with physics; read it, don't set it.
var time := 0.0

var _calm: Array[Vector4] = []   # x, z, radius, -


func _ready() -> void:
	add_to_group(&"surf_terrain")
	if Engine.is_editor_hint():
		return
	Game.room_changed.connect(_on_room_changed)
	_push_uniforms()


## Static swells only, at an xz point (world). Ground builders add this to their own shape.
func static_extra(xz: Vector2) -> float:
	var h := 0.0
	for w in static_waves:
		h += w.height(xz, 0.0)
	return h


## The ground that never moves: what props stand on and what the collision mesh is built from.
func static_height(xz: Vector2) -> float:
	if base_func.is_valid():
		return base_func.call(xz)
	return global_position.y + static_extra(xz)


## Moving swells at an xz point, already faded out around calm spots.
func moving_height(xz: Vector2, t: float) -> float:
	if moving_waves.is_empty():
		return 0.0
	var h := 0.0
	for w in moving_waves:
		h += w.height(xz, t)
	return h * calm_at(xz)


## The ground under an xz point right now (or at time t).
func height(xz: Vector2, t := NAN) -> float:
	if is_nan(t):
		t = time
	return static_height(xz) + moving_height(xz, t)


## Height, slope and how fast the ground is rising: Vector4(h, dh/dx, dh/dz, dh/dt).
func sample(xz: Vector2, t := NAN) -> Vector4:
	if is_nan(t):
		t = time
	var e := 0.35
	var h := height(xz, t)
	var hx := (height(xz + Vector2(e, 0), t) - height(xz - Vector2(e, 0), t)) / (2.0 * e)
	var hz := (height(xz + Vector2(0, e), t) - height(xz - Vector2(0, e), t)) / (2.0 * e)
	var ht := 0.0
	if not moving_waves.is_empty():
		var dt := 1.0 / 60.0
		ht = (moving_height(xz, t + dt) - moving_height(xz, t - dt)) / (2.0 * dt)
	return Vector4(h, hx, hz, ht)


## Unit surface normal under an xz point.
func normal(xz: Vector2, t := NAN) -> Vector3:
	var s := sample(xz, t)
	return Vector3(-s.y, 1.0, -s.z).normalized()


## A point on the ground (static ground if `moving` is false: for placing props).
func ground_point(xz: Vector2, moving := true) -> Vector3:
	return Vector3(xz.x, height(xz) if moving else static_height(xz), xz.y)


## Keep the swells flat around a prop that stands on the ground (a door, a tree).
func add_calm_spot(world: Vector3, radius: float) -> void:
	if _calm.size() >= 32:
		push_warning("SurfTerrain: more than 32 calm spots; ignoring the rest")
		return
	_calm.append(Vector4(world.x, world.z, radius, 0.0))
	_push_uniforms()


func clear_calm_spots() -> void:
	_calm.clear()
	_push_uniforms()


func calm_at(xz: Vector2) -> float:
	var m := 1.0
	for s in _calm:
		var d := xz.distance_to(Vector2(s.x, s.y))
		m = minf(m, smoothstep(s.z, s.z * 1.8, d))
	return m


func add_material(mat: ShaderMaterial) -> void:
	if mat and not materials.has(mat):
		materials.append(mat)
		_push_uniforms()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	time += delta
	for m in materials:
		m.set_shader_parameter(&"surf_time", time)


func _push_uniforms() -> void:
	var wa: Array[Vector4] = []
	var wb: Array[Vector4] = []
	var wc: Array[Vector4] = []
	var wd: Array[Vector4] = []
	for i in mini(moving_waves.size(), 8):
		var p := moving_waves[i].pack()
		wa.append(p[0]); wb.append(p[1]); wc.append(p[2]); wd.append(p[3])
	while wa.size() < 8:
		wa.append(Vector4.ZERO); wb.append(Vector4(1, 0, 0, 0)); wc.append(Vector4.ZERO); wd.append(Vector4.ZERO)
	var calm: Array[Vector4] = _calm.duplicate()
	while calm.size() < 32:
		calm.append(Vector4(1e6, 1e6, 0.0, 0.0))
	for m in materials:
		m.set_shader_parameter(&"surf_wave_count", mini(moving_waves.size(), 8))
		m.set_shader_parameter(&"surf_wa", wa)
		m.set_shader_parameter(&"surf_wb", wb)
		m.set_shader_parameter(&"surf_wc", wc)
		m.set_shader_parameter(&"surf_wd", wd)
		m.set_shader_parameter(&"surf_calm_count", _calm.size())
		m.set_shader_parameter(&"surf_calm", calm)
		m.set_shader_parameter(&"surf_time", time)


## Keep the rider in bounds: returns the velocity, bent back off the edge of the region.
func confine(pos: Vector3, vel: Vector3, delta: float) -> Vector3:
	if bounds_radius <= 0.0:
		return vel
	var d := Vector2(pos.x, pos.z) - bounds_center
	var r := d.length()
	var soft := bounds_radius - 30.0
	if r < soft or r < 0.001:
		return vel
	var out := Vector3(d.x / r, 0.0, d.y / r)
	var push := clampf((r - soft) / 30.0, 0.0, 1.5)
	var vr := vel.dot(out)
	if vr > 0.0:
		vel -= out * vr * minf(push, 1.0) * clampf(delta * 8.0, 0.0, 1.0)
	vel -= out * push * 30.0 * delta
	return vel


func _on_room_changed(room: Room) -> void:
	if not enabled or not is_instance_valid(Game.player) or not room.is_ancestor_of(self):
		return
	var surfer := Surfer.attach(Game.player, self)
	rider_ready.emit(surfer)
