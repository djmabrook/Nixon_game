@tool
class_name DitherLook
extends ColorRect
## Dithered pixel post-process. A full-screen ColorRect that reads the finished frame,
## snaps it to chunky virtual pixels, adds an ordered (Bayer) dither and maps every
## pixel to the palette of `look`.
##
## In the game it lives at Main/PostProcess/DitherLook (shaders/dither_look.tscn).
## Anything on a lower canvas layer than its parent CanvasLayer gets the effect.
##
## Per-room looks ("art era as a mechanic"):
##   - Give your room script `@export var dither_look: DitherLookSettings` and pick a .tres.
##     It is applied while the screen is faded out on entry. Rooms without one get `default_look`.
##   - To change era mid-room (a rule twist): DitherLook.request(get_tree(), other_look, 0.8)
##     dissolves to it through the dither pattern.

const GROUP := &"dither_look"
const SHADER := preload("res://shaders/dither_look.gdshader")

## The look used in rooms that don't set their own, and at startup.
@export var default_look: DitherLookSettings:
	set(v):
		default_look = v
		if look == null:
			look = v

## The look on screen now.
@export var look: DitherLookSettings:
	set(v):
		if look and look.changed.is_connected(_on_look_changed):
			look.changed.disconnect(_on_look_changed)
		look = v
		if look:
			look.changed.connect(_on_look_changed)
		_apply_side(&"a", look)
		_set_blend(0.0)

## Turn the effect off without removing the node.
@export var enabled: bool = true:
	set(v):
		enabled = v
		if _mat:
			_mat.set_shader_parameter(&"enabled", v)

## Follow Game.room_changed and apply each room's `dither_look` (or `default_look`).
@export var follow_rooms: bool = true

## Keep the image rock steady while an orthographic camera moves:
## the virtual pixel grid and the dither pattern are anchored to the world, and the camera is
## nudged (via h_offset / v_offset, never its transform) onto whole screen pixels so the 3D
## render itself doesn't swim. Turn off only to compare.
@export var stabilize: bool = true:
	set(v):
		stabilize = v
		if not v:
			_release_camera()

var _mat: ShaderMaterial
var _side_b: DitherLookSettings
var _tween: Tween
var _snapped_cam: Camera3D


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Run after cameras have moved this frame.
	process_priority = 1000


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_refresh_pixel_sizes)
	if look == null:
		look = default_look
	_apply_side(&"a", look)
	if Engine.is_editor_hint() or not follow_rooms:
		return
	var game := get_node_or_null(^"/root/Game")
	if game and game.has_signal(&"room_changed"):
		game.room_changed.connect(_on_room_changed)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_mat.set_shader_parameter(&"grid_offset", _stabilize_camera() if stabilize else Vector2.ZERO)


## Snaps the active ortho camera to whole screen pixels and returns its position in screen
## pixels (x right, y down), which the shader adds to its grid.
func _stabilize_camera() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam != _snapped_cam:
		_release_camera()
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return Vector2.ZERO
	var vp := get_viewport().get_visible_rect().size
	var span := vp.x if cam.keep_aspect == Camera3D.KEEP_WIDTH else vp.y
	var upp := cam.size / maxf(1.0, span)  # world units per screen pixel
	var b := cam.global_transform.basis
	var p := cam.global_position
	var x := p.dot(b.x.normalized()) / upp
	var y := p.dot(b.y.normalized()) / upp
	var sx := roundf(x)
	var sy := roundf(y)
	cam.h_offset = (sx - x) * upp
	cam.v_offset = (sy - y) * upp
	_snapped_cam = cam
	return Vector2(sx, -sy)


func _release_camera() -> void:
	if is_instance_valid(_snapped_cam):
		_snapped_cam.h_offset = 0.0
		_snapped_cam.v_offset = 0.0
	_snapped_cam = null


func _exit_tree() -> void:
	_release_camera()


## Dissolve to another look through the dither pattern. duration 0 = instant.
func transition_to(new_look: DitherLookSettings, duration: float = 0.8) -> void:
	if _tween:
		_tween.kill()
		_tween = null
		# Finish a half-done transition so side A is what's on screen.
		if _side_b and float(_mat.get_shader_parameter(&"blend")) > 0.5:
			_commit_b()
		_side_b = null
	if duration <= 0.0 or look == null or new_look == null:
		look = new_look
		return
	if new_look == look:
		_set_blend(0.0)
		return
	_side_b = new_look
	_apply_side(&"b", new_look)
	_set_blend(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_blend, 0.0, 1.0, duration)
	_tween.tween_callback(_commit_b)


## Find the DitherLook in the tree and change its look. Does nothing if there is none.
static func request(tree: SceneTree, new_look: DitherLookSettings, duration: float = 0.8) -> void:
	var node := tree.get_first_node_in_group(GROUP) as DitherLook
	if node:
		node.transition_to(new_look, duration)


func _on_room_changed(room: Node) -> void:
	var l = room.get(&"dither_look")
	transition_to(l if l is DitherLookSettings else default_look, 0.0)


func _commit_b() -> void:
	var b := _side_b
	_side_b = null
	_tween = null
	look = b  # setter copies to side A and resets blend


func _set_blend(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter(&"blend", v)


func _on_look_changed() -> void:
	_apply_side(&"a", look)


## Real pixels per virtual pixel. Whole numbers only, so virtual pixels stay square.
func _pixel_size_for(s: DitherLookSettings) -> float:
	var h := 360.0
	if is_inside_tree():
		h = get_viewport().get_visible_rect().size.y
	return maxf(1.0, roundf(h / float(maxi(1, s.virtual_height))))


func _apply_side(side: StringName, s: DitherLookSettings) -> void:
	if not _mat or not s:
		return
	_mat.set_shader_parameter(&"palette_" + side, s.make_palette_texture())
	_mat.set_shader_parameter(&"palette_size_" + side, clampi(s.palette.size(), 1, 32))
	_mat.set_shader_parameter(&"shape_" + side, Vector4(_pixel_size_for(s), s.dither_spread, s.bayer_size, s.accent_threshold))
	_mat.set_shader_parameter(&"grade_" + side, Vector4(s.contrast, s.brightness, s.saturation, s.grain))
	_mat.set_shader_parameter(&"soft_" + side, s.soft_sampling)


func _refresh_pixel_sizes() -> void:
	_apply_side(&"a", look)
	if _side_b:
		_apply_side(&"b", _side_b)
