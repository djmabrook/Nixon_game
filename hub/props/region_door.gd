extends Node3D
## The door at the outer end of each room's groove: a bone monolith some 70 m tall, half
## sunk in the sand and leaning, its doorway a slot of black. The ember sliver over the
## doorway (and the light pooling out of it) takes the room's ink colour once it is lit.
## The mountain groove's door also has the usher's open hand plaza beside it (hand = true).
## Same exports as the old ember stake: color, lit, light_range.

const Palette := preload("res://hub/art_palette.gd")
const MODELS := "res://hub/art/models/%s.glb"
const RUST := Color(0.39, 0.06, 0.023)
const HAND := preload("res://hub/art/models/usher_hand_plaza.glb")

@export var color := Color(1.0, 0.35, 0.1):
	set(v):
		color = v
		_apply()
@export var lit := true:
	set(v):
		lit = v
		_apply()
@export var light_range := 140.0:
	set(v):
		light_range = v
		_apply()
## Which door model (art/models/<variant>.glb): mega_door_monolith, or a region's own
## door_lake, door_grid, door_checker, door_watcher. They share size, pivot and opening.
@export var variant := &"mega_door_monolith"
## Add the usher's hand plaza beside the door (the groove that opens with the eye).
@export var hand := false
## How far the model is sunk into the sand, in metres.
@export var sink := 18.0
## 0 drained to 1 full colour; the story sets it on everything in group hub_drainable.
var color_amount := 0.0:
	set(v):
		color_amount = v
		Palette.apply(_entries, v)
		_apply()

var _entries: Array = []
var _ink_mats: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _model: Node3D
var _phase := 0.0


func _ready() -> void:
	add_to_group(&"hub_drainable")
	var path := MODELS % variant
	if not ResourceLoader.exists(path):
		path = MODELS % "mega_door_monolith"
	_model = (load(path) as PackedScene).instantiate()
	add_child(_model)
	var seed_from := hash(name)
	_phase = float(seed_from % 1000) / 1000.0 * TAU
	_model.position.y = -sink
	# Each door leans its own way, as if the sand had shifted under it.
	_model.rotation = Vector3(deg_to_rad(-4.0 - float(seed_from % 5)),
			deg_to_rad(float(seed_from % 13) - 6.0), deg_to_rad(float(seed_from % 11) - 5.0))
	_ink_mats = Palette.material_named(_model, "ember")
	_entries = Palette.prepare(_model, ["ember"])
	# The plain monolith's shadowed trim reads as rust (the region doors have their own trim).
	for e in _entries:
		if (e[0] as StandardMaterial3D).resource_name == "bone_lo":
			e[1] = RUST
	Palette.add_collision(_model)
	if hand:
		# Palm up beside the doorway, a little toward the crater, offering the way in.
		var h: Node3D = HAND.instantiate()
		h.name = "HandPlaza"
		add_child(h)
		h.position = Vector3(62.0, -3.0, 14.0)
		h.rotation.y = deg_to_rad(-20.0)
		_entries.append_array(Palette.prepare(h))
		Palette.add_collision(h)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 22.0 - sink * 0.5, 14.0)
	_light.omni_attenuation = 1.2
	add_child(_light)
	Palette.apply(_entries, color_amount)
	_apply()


func _process(_delta: float) -> void:
	if not lit or _light == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	_light.light_energy = 9.0 + 2.0 * sin(t * 1.3) + 0.8 * sin(t * 3.7)


func _apply() -> void:
	if _light == null:
		return
	for m in _ink_mats:
		m.albedo_color = color.darkened(0.2) if lit else Color(0.08, 0.07, 0.07)
		m.emission_enabled = lit
		m.emission = color
		m.emission_energy_multiplier = 4.0
	_light.light_color = color
	_light.omni_range = light_range
	_light.visible = lit
