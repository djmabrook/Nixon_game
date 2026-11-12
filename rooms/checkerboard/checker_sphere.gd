@tool
extends RigidBody3D
## A checkered ball. It builds its own mesh and collision from `radius`, so you can
## drop one into the room, set the radius and colors, and it just works.
## The room pushes it around with the gravity tide.

signal hit(speed: float)

const SHADER := preload("res://rooms/checkerboard/checker_sphere.gdshader")

@export var radius := 0.6:
	set(v):
		radius = maxf(v, 0.1)
		_build()
@export var color_a := Color(1.0, 0.56, 0.56):
	set(v):
		color_a = v
		_build()
@export var color_b := Color(0.03, 0.018, 0.026):
	set(v):
		color_b = v
		_build()
## Small enough to fall into the socket? Computed from radius by the room.
var home := Vector3.ZERO
var socketed := false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat: ShaderMaterial
var _squash := 0.0


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	home = global_position
	collision_layer = 1
	collision_mask = 1 | (1 << 4)
	mass = 4.0 * radius * radius * radius
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.7
	physics_material_override = pm
	angular_damp = 0.4
	linear_damp = 0.15
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _mesh == null:
		return
	# Squash on impact, eased back. Applied in world-up so it reads while rolling.
	_squash = move_toward(_squash, 0.0, delta * 3.0)
	var s := _squash * sin(_squash * 18.0)
	var k := 1.0 + s * 0.25
	_mesh.global_basis = Basis.from_scale(Vector3(1.0 / sqrt(k), k, 1.0 / sqrt(k))) * global_basis.orthonormalized()


func set_glow(amount: float) -> void:
	if _mat:
		_mat.set_shader_parameter(&"glow", amount)


func _on_body_entered(_body: Node) -> void:
	var speed := linear_velocity.length()
	if speed > 1.2:
		_squash = clampf(speed / 8.0, 0.2, 1.0)
		hit.emit(speed)


func _build() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Mesh"
		add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)
		_shape = CollisionShape3D.new()
		_shape.name = "Shape"
		add_child(_shape, false, Node.INTERNAL_MODE_FRONT)
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	sm.material = _mat
	_mesh.mesh = sm
	var ss := SphereShape3D.new()
	ss.radius = radius
	_shape.shape = ss
	_mat.set_shader_parameter(&"color_a", color_a)
	_mat.set_shader_parameter(&"color_b", color_b)
	# Bigger balls get more squares, like the reference.
	_mat.set_shader_parameter(&"columns", 8.0 if radius < 1.0 else 12.0)
	_mat.set_shader_parameter(&"rows", 4.0 if radius < 1.0 else 6.0)
