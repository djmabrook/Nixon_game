extends CanvasLayer
## The story's 2D layer, drawn above the dither look so it stays clean:
## - the title's prompt (a lone blinking cursor, no words),
## - the paper margin the picture shrinks onto at the end,
## - the little man and the Stray as tiny figures once they step off the picture.

const BONE := Color(0.937, 0.902, 0.847)
const INK := Color(0.051, 0.043, 0.039)
const RUST := Color(0.659, 0.271, 0.165)

## Picture rect in UV (x0, y0, x1, y1) and how much paper shows.
var rect := Vector4(0, 0, 1, 1):
	set(v):
		rect = v
		if _paper_mat:
			_paper_mat.set_shader_parameter("rect", v)
var paper_reveal := 0.0:
	set(v):
		paper_reveal = v
		if _paper_mat:
			_paper_mat.set_shader_parameter("reveal", v)
var prompt_alpha := 0.0
## A black curtain over everything (dips to black between beats).
var curtain := 0.0:
	set(v):
		curtain = v
		if _curtain:
			_curtain.color.a = v

var _paper: ColorRect
var _paper_mat: ShaderMaterial
var _draw: Node2D
var _curtain: ColorRect
var _t := 0.0

## Figures on the paper: dictionaries {kind, pos, vel, height, phase, prints:[]}.
var figures: Array[Dictionary] = []


func _init() -> void:
	layer = 60


func _ready() -> void:
	_paper = ColorRect.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paper_mat = ShaderMaterial.new()
	_paper_mat.shader = preload("res://story/paper.gdshader")
	_paper.material = _paper_mat
	add_child(_paper)
	rect = rect
	paper_reveal = paper_reveal
	_draw = Node2D.new()
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	_curtain = ColorRect.new()
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.color = Color(0, 0, 0, curtain)
	add_child(_curtain)


func screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	_t += delta
	_paper_mat.set_shader_parameter("screen_px", screen_size())
	for f in figures:
		f.pos += f.vel * delta
		f.phase += delta * (f.vel.length() / maxf(f.height * 0.5, 1.0))
		if f.kind == &"man":
			# Prints on the paper, one per step, a little ink left behind.
			var step_i := int(f.phase / PI)
			if step_i != f.last_step:
				f.last_step = step_i
				var side := Vector2(-f.vel.y, f.vel.x).normalized() * (1.0 if step_i % 2 == 0 else -1.0)
				f.prints.append(f.pos + side * 1.0)
	_draw.queue_redraw()


## Put a tiny figure on the paper at screen position `pos`, walking at `vel` px/s.
func add_figure(kind: StringName, pos: Vector2, vel: Vector2, height: float) -> Dictionary:
	var f := {kind = kind, pos = pos, vel = vel, height = maxf(height, 6.0), phase = 0.0, prints = [], last_step = -1}
	figures.append(f)
	return f


func _on_draw() -> void:
	var size := screen_size()
	# Title prompt: the cursor caret, blinking. Nothing to read.
	if prompt_alpha > 0.01:
		var on := fmod(_t, 1.1) < 0.65
		if on:
			var c := Vector2(roundf(size.x * 0.5), roundf(size.y * 0.86))
			_cursor(c, 9.0, prompt_alpha)
	for f in figures:
		for pr in f.prints:
			_draw.draw_rect(Rect2((pr as Vector2).round(), Vector2(1, 1)), Color(INK, 0.55))
		if f.kind == &"man":
			_man(f.pos, f.height, f.phase, f.vel.x < 0.0)
		else:
			_cursor(f.pos + Vector2(0, -f.height), f.height, 1.0, sin(f.phase * 2.0) * 0.8)


## The little man as a few pixels: no face, a boxy jacket, legs scissoring.
func _man(feet: Vector2, h: float, phase: float, _left: bool) -> void:
	var f := feet.round()
	var head: float = maxf(roundf(h * 0.16), 2.0)
	var body_h: float = roundf(h * 0.42)
	var leg_h: float = h - head - body_h
	var w: float = maxf(roundf(h * 0.28), 3.0)
	var swing: float = sin(phase) * leg_h * 0.35
	var bob: float = roundf(absf(sin(phase)) * 0.6)
	var top: float = f.y - h - bob
	_draw.draw_rect(Rect2(f.x - roundf(head * 0.5), top, head, head), RUST)
	_draw.draw_rect(Rect2(f.x - roundf(w * 0.5), top + head, w, body_h), RUST)
	var lw: float = maxf(roundf(w * 0.35), 1.0)
	_draw.draw_rect(Rect2(roundf(f.x - lw - swing * 0.5), top + head + body_h, lw, leg_h + bob), RUST)
	_draw.draw_rect(Rect2(roundf(f.x + swing * 0.5), top + head + body_h, lw, leg_h + bob), RUST)


## The Stray's shape: an arrow cursor, bone face with an ink rim.
func _cursor(tip: Vector2, h: float, alpha: float, tilt := 0.0) -> void:
	var s := h / 16.0
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(0, 14), Vector2(3.5, 10.5), Vector2(6, 16),
		Vector2(8, 15), Vector2(5.5, 9.5), Vector2(10, 9.5)])
	var out := PackedVector2Array()
	for p in pts:
		out.append(tip.round() + (p * s).rotated(tilt * 0.15))
	_draw.draw_colored_polygon(out, Color(BONE, alpha))
	out.append(out[0])
	_draw.draw_polyline(out, Color(INK, alpha), 1.0)
