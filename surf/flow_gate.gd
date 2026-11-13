class_name FlowGate
extends Node3D
## A ring of light standing over the sand. Ride or fly through it: a burst of speed, a chime
## a step up the scale from the last gate, flow. Lines of them show where to go without a
## word. The ring faces along its -Z (the way you're meant to pass through it, either way works).

signal passed(gate: FlowGate)

@export var radius := 3.4
@export var color := Color(1.0, 0.45, 0.25)
@export var boost := 7.0
@export var flow_gain := 0.1
## Seconds before a taken gate lights again. 0 = never.
@export var respawn := 14.0
## Float this high over the sand and ride the swells up and down with it (0 = stay put).
@export var hover := 0.0

var taken := false
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0
var _flash := 0.0
var _last_side := 0.0
var _armed := false


func _ready() -> void:
	add_to_group(&"surf_gate")
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.22
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 8
	_ring.mesh = torus
	_ring.rotation.x = PI * 0.5   # the torus lies flat; stand it up facing -Z
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 3.0
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _process(delta: float) -> void:
	_t += delta
	_flash = move_toward(_flash, 0.0, delta * 2.5)
	var pulse := 0.85 + 0.15 * sin(_t * 3.0 + global_position.x * 0.05)
	if taken:
		_ring.scale = _ring.scale.lerp(Vector3.ONE * (1.0 + 2.5 * (1.0 - _flash)), 1.0 - exp(-6.0 * delta))
		_mat.albedo_color.a = _flash
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.visible = _flash > 0.01
	else:
		_ring.visible = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_ring.scale = Vector3.ONE * pulse
		_ring.rotation.z += delta * 0.6
		var c := color.lerp(Color.from_hsv(fposmod(_t * 0.1, 1.0), 0.7, 1.0), 0.25)
		_mat.albedo_color = c
		_mat.emission = c


func _physics_process(_delta: float) -> void:
	if hover > 0.0:
		var t := get_tree().get_first_node_in_group(&"surf_terrain") as SurfTerrain
		if t:
			var p := global_position
			global_position = Vector3(p.x, t.height(Vector2(p.x, p.z)) + hover, p.z)
	if taken or not is_instance_valid(Game.player):
		return
	var s := Game.player.get_node_or_null(^"Surfer") as Surfer
	if s == null or s.is_wiped_out():
		_armed = false
		return
	var body := s.pos + Vector3.UP * 0.9
	var local := global_transform.affine_inverse() * body
	var side := signf(local.z)
	if _armed and side != _last_side and side != 0.0:
		var before := global_transform.affine_inverse() * (s.prev_pos + Vector3.UP * 0.9)
		var k := before.z / (before.z - local.z) if absf(before.z - local.z) > 1e-5 else 0.0
		var cross := before.lerp(local, k)
		if Vector2(cross.x, cross.y).length() <= radius * 1.15:
			_take(s)
	_last_side = side
	_armed = body.distance_to(global_position) < radius * 6.0


func _take(s: Surfer) -> void:
	taken = true
	_flash = 1.0
	s.boost(boost, flow_gain)
	passed.emit(self)
	if respawn > 0.0:
		get_tree().create_timer(respawn).timeout.connect(func() -> void:
			taken = false
			_ring.scale = Vector3.ONE)
