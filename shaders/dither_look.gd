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
const DEPTH_SHADER := preload("res://shaders/dither_depth.gdshader")

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
		_update_depth_pass()

## Story hook: 0..1 bleeds the frame down to the current palette's darkest and lightest inks
## (e.g. while the Watcher stares). Tween it freely.
@export_range(0.0, 1.0, 0.01) var drain: float = 0.0:
	set(v):
		drain = v
		if _mat:
			_mat.set_shader_parameter(&"drain", v)

## Follow Game.room_changed and apply each room's `dither_look` (or `default_look`).
@export var follow_rooms: bool = true

## Keep the dither steady while the camera moves. Turn off only to compare.
## Orthographic: the pixel grid and pattern are anchored to the world and the camera is nudged
## (h_offset / v_offset, never its transform) onto whole screen pixels.
## Perspective: the grid and pattern follow the turn of the view, so orbiting and looking around
## carry them with the scenery (distant terrain, sky and fog stay put; near ground drifts a
## little as the camera travels).
@export var stabilize: bool = true:
	set(v):
		stabilize = v
		if not v:
			_release_camera()

var _mat: ShaderMaterial
var _side_b: DitherLookSettings
var _tween: Tween
var _snapped_cam: Camera3D
var _depth_quad: MeshInstance3D
var _depth_mat: ShaderMaterial
var _blend := 0.0
var _ink_override := Color(0, 0, 0, 0)


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
	if not Engine.is_editor_hint():
		_make_depth_pass()
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
	var offset := Vector2.ZERO
	if stabilize:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
			_release_camera()
			offset = _track_perspective(cam)
		else:
			offset = _stabilize_camera()
	if _depth_mat:
		var c3 := get_viewport().get_camera_3d()
		if c3:
			_depth_mat.set_shader_parameter(&"far_clip", c3.far)
	_mat.set_shader_parameter(&"grid_offset", offset)


var _persp_cam: Camera3D
var _persp_fwd := Vector3.ZERO
var _persp_shift := Vector2.ZERO


## Perspective: measure how far the centre of the view slid across the screen since last frame
## (where last frame's view direction lands now) and accumulate it. Shifting the grid and the
## pattern by that whole-pixel amount makes them turn with the world, without rotating the
## pattern against the pixel grid (which would cause moire).
func _track_perspective(cam: Camera3D) -> Vector2:
	var b := cam.global_transform.basis.orthonormalized()
	var fwd := -b.z
	if cam != _persp_cam:
		_persp_cam = cam
		_persp_fwd = fwd
	var vp := get_viewport().get_visible_rect().size
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var focal := (vp.y * 0.5) / t if cam.keep_aspect == Camera3D.KEEP_HEIGHT else (vp.x * 0.5) / t
	var v := b.inverse() * _persp_fwd
	if v.z < -0.2:  # a jump of more than ~78 degrees in one frame is a cut: start fresh
		_persp_shift -= Vector2(v.x / -v.z, -v.y / -v.z) * focal
	_persp_fwd = fwd
	return _persp_shift.round()


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


## Close to another look with two eyelids (top and bottom, almond shaped, dithered lash line).
## For a television or the Watcher shutting its eyes; pass a near-black look to blink out.
func eyelids_to(new_look: DitherLookSettings, duration: float = 0.6) -> void:
	transition_to(new_look, duration, 1)


## The reverse: lids open from the middle row onto the new look.
func eyelids_open_to(new_look: DitherLookSettings, duration: float = 0.6) -> void:
	transition_to(new_look, duration, 2)


## Dissolve to another look through the dither pattern. duration 0 = instant.
## wipe: 0 = dissolve, 1 = eyelids closing, 2 = eyelids opening.
func transition_to(new_look: DitherLookSettings, duration: float = 0.8, wipe: int = 0) -> void:
	_mat.set_shader_parameter(&"wipe_mode", wipe)
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


## The current region's living ink (the look's `ink`, or a temporary override). Other code can
## borrow it, e.g. to tint the Stray's arrow tip: `DitherLook.current_ink(get_tree())`.
## Returns transparent black when the look has no ink.
static func current_ink(tree: SceneTree) -> Color:
	var node := tree.get_first_node_in_group(GROUP) as DitherLook
	if node == null or node.look == null:
		return Color(0, 0, 0, 0)
	return node._ink_override if node._ink_override.a > 0.0 else node.look.ink


## Swap the living ink for `seconds` (0 = until cleared with Color(0,0,0,0)).
func set_ink_override(c: Color, seconds: float = 0.0) -> void:
	_ink_override = c
	_apply_side(&"a", look)
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if _ink_override == c:
			_ink_override = Color(0, 0, 0, 0)
			_apply_side(&"a", look)


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
	_blend = v
	if _mat:
		_mat.set_shader_parameter(&"blend", v)
	_update_depth_pass()


func _on_look_changed() -> void:
	_apply_side(&"a", look)
	_update_depth_pass()


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
	_mat.set_shader_parameter(&"invert_" + side, s.invert)
	var ink := s.ink
	if side == &"a" and _ink_override.a > 0.0:
		ink = _ink_override
	_mat.set_shader_parameter(&"ink_" + side, Vector4(ink.r, ink.g, ink.b, 1.0 if ink.a > 0.0 else 0.0))
	_mat.set_shader_parameter(&"ink_key_" + side, Vector3(s.ink_min_saturation, s.ink_min_brightness, s.ink_hue_range / 360.0))


func _refresh_pixel_sizes() -> void:
	_apply_side(&"a", look)
	if _side_b:
		_apply_side(&"b", _side_b)


# ---------------------------------------------------------------- depth pass (haze bands, outlines)

func _make_depth_pass() -> void:
	_depth_mat = ShaderMaterial.new()
	_depth_mat.shader = DEPTH_SHADER
	_depth_mat.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	_depth_quad = MeshInstance3D.new()
	_depth_quad.name = "DepthPass"
	_depth_quad.mesh = quad
	_depth_quad.material_override = _depth_mat
	_depth_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_depth_quad.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	_depth_quad.extra_cull_margin = 16384.0
	_depth_quad.visible = false
	add_child(_depth_quad, false, Node.INTERNAL_MODE_BACK)
	_update_depth_pass()


func _update_depth_pass() -> void:
	if not _depth_mat or not look:
		return
	var a := look
	var b := _side_b if _side_b else look
	var t := _blend if _side_b else 0.0
	var steps := a.haze_steps if t < 0.5 else b.haze_steps
	var amount := lerpf(a.haze_amount if a.haze_steps > 0 else 0.0, b.haze_amount if b.haze_steps > 0 else 0.0, t)
	var ink := lerpf(a.outline_strength, b.outline_strength, t)
	# The Compatibility renderer tone-maps 3D materials inline, which breaks this pass's
	# read-back; it needs Forward+ or Mobile (the game uses Forward+).
	var supported := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_depth_quad.visible = supported and enabled and ((steps > 0 and amount > 0.0) or ink > 0.0)
	_depth_mat.set_shader_parameter(&"haze", Vector4(steps, lerpf(a.haze_start, b.haze_start, t), lerpf(a.haze_end, b.haze_end, t), amount))
	_depth_mat.set_shader_parameter(&"haze_color", a.haze_color.lerp(b.haze_color, t))
	_depth_mat.set_shader_parameter(&"haze_sky", a.haze_sky if t < 0.5 else b.haze_sky)
	_depth_mat.set_shader_parameter(&"outline", Vector4(ink, maxf(1.0, _pixel_size_for(a if t < 0.5 else b)), lerpf(a.outline_min_distance, b.outline_min_distance, t), lerpf(a.outline_depth_ratio, b.outline_depth_ratio, t)))
	_depth_mat.set_shader_parameter(&"outline_color", a.outline_color.lerp(b.outline_color, t))
