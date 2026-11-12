class_name LittleManModel
extends Node3D
## The little man's rigged model and its clips. The Player drives it; rooms can
## recolour it with set_tint(). The clips are separate GLBs on the same rig and are
## merged into one AnimationPlayer at load time.

const RIG := preload("res://player/model/littleman_rigged.glb")
## Clip name -> [file, loops]
const CLIPS := {
	&"idle": ["res://player/model/littleman_idle.glb", true],
	&"walk": ["res://player/model/littleman_walk.glb", true],
	&"run": ["res://player/model/littleman_run.glb", true],
	&"carry_idle": ["res://player/model/littleman_carry_idle.glb", true],
	&"carry_walk": ["res://player/model/littleman_carry_walk.glb", true],
	&"climb": ["res://player/model/littleman_climb.glb", true],
	&"caught": ["res://player/model/littleman_caught.glb", false],
}
## His default colour (art direction: rust #a8452a).
const RUST := Color("a8452a")

## Cross-fade time between clips.
@export var blend_time := 0.2

var anim: AnimationPlayer
var current: StringName = &""
var _meshes: Array[MeshInstance3D] = []
var _tint_mat: StandardMaterial3D

static var _library: AnimationLibrary


func _ready() -> void:
	var rig := RIG.instantiate()
	add_child(rig)
	# The model faces +Z; the game's forward is -Z.
	rig.rotation.y = PI
	anim = rig.find_child("AnimationPlayer", true, false)
	for m in rig.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m)
	if _library == null:
		_library = _build_library()
	anim.add_animation_library(&"lm", _library)
	play(&"idle", 0.0)


## Play a clip by name (idle, walk, run, carry_idle, carry_walk, climb, caught).
func play(clip: StringName, blend := -1.0, speed := 1.0) -> void:
	if clip == current:
		anim.speed_scale = speed
		return
	if not _library.has_animation(clip):
		push_warning("LittleManModel: no clip '%s'" % clip)
		return
	current = clip
	anim.play(&"lm/" + String(clip), blend_time if blend < 0.0 else blend)
	anim.speed_scale = speed


## Recolour the whole figure (a region may draw him near-black). Pass RUST to restore.
func set_tint(color: Color) -> void:
	if _tint_mat == null:
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.roughness = 1.0
	_tint_mat.albedo_color = color
	for m in _meshes:
		m.material_override = null if color == RUST else _tint_mat


## Shadow casting for every mesh in the model (Player uses SHADOWS_ONLY for the late shadow).
func set_cast_shadow(mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for m in _meshes:
		m.cast_shadow = mode


static func _build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		var file: String = CLIPS[clip][0]
		if not ResourceLoader.exists(file):
			continue
		var scene := (load(file) as PackedScene).instantiate()
		var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			var a := ap.get_animation(ap.get_animation_list()[0]).duplicate() as Animation
			a.loop_mode = Animation.LOOP_LINEAR if CLIPS[clip][1] else Animation.LOOP_NONE
			lib.add_animation(clip, a)
		scene.free()
	return lib
