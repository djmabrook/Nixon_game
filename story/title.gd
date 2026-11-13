extends "res://story/sequence.gd"
## The title shore. No words: the night beach held from out in the shallows, the sea
## lapping, the dune ridge and the Watcher's mountain beyond, and one cursor blinking.
## Any button begins.
##
## What lies on the shore says where you are in the story:
##   never played            -> he lies face-down in the wash
##   part way through        -> he stands at the tideline looking at the mountain
##   after the ending        -> nobody; a line of his footprints leads off the frame

const OVERLAY := preload("res://story/overlay.gd")
const TRAIL := preload("res://story/props/footprint_trail.gd")

## Headless runs press "begin" by themselves after this many seconds.
var auto_advance := 1.0

var _waiting := false
var _overlay: CanvasLayer
var _mode := &"fresh"


func _init() -> void:
	sequence_name = &"title"


func _ready() -> void:
	hold()
	var dressing: Node = room().get_node(^"StoryDressing")
	await dressing.wait_surveyed()
	shore = dressing.shore
	var p := Game.player
	if Story.get_flag(Story.FLAG_ENDING_SEEN):
		_mode = &"after_ending"
	elif Story.get_flag(Story.FLAG_OPENING_SEEN):
		_mode = &"returning"

	match _mode:
		&"fresh":
			place_player(shore.wake, shore.inland)
			pose_prone(p)
		&"returning":
			place_player(shore.shore_point(0.0, -2.0), shore.inland)
		&"after_ending":
			p.visual.visible = false
			_lay_footprints(dressing)

	_overlay = OVERLAY.new()
	_overlay.name = "TitleOverlay"
	add_child(_overlay)

	# Out in the shallows, low, looking up the beach at the ridge. After the ending the
	# camera sits lower and nearer, so his prints run past it and out of the right edge.
	var look := shore.wake + shore.inland * 70.0 + Vector3.UP * 26.0
	if _mode == &"after_ending":
		var start := shore.shore_point(-6.0, -1.0)
		var eye := shore.sand(start + shore.along * 7.0 - shore.inland * 8.0) + Vector3.UP * 2.0
		look = start + shore.along * 3.0 + shore.inland * 30.0 + Vector3.UP * 7.0
		cut(eye, look, 46.0)
		glide(eye - shore.inland * 1.5 + Vector3.UP * 0.3, look + Vector3.UP * 1.0, 45.0, 44.0)
	else:
		cut(title_eye(shore), look, 44.0)
		glide(title_eye(shore) + shore.inland * 6.0 + Vector3.UP * 0.6, look + Vector3.UP * 4.0, 45.0, 42.0)
	(dressing.audio as Node).set(&"surf", 1.0)

	await wait(2.0)
	create_tween().tween_property(_overlay, "prompt_alpha", 1.0, 1.5)
	_waiting = true
	if is_headless():
		await wait(auto_advance)
		if _waiting:
			_begin()


## Where the title camera sits, for this shore. The opening starts from the same place.
static func title_eye(s) -> Vector3:
	return s.wake - s.inland * 30.0 + s.along * 10.0 + Vector3.UP * (s.shore_height - s.wake.y + 3.4)


func _input(event: InputEvent) -> void:
	if not _waiting:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		_begin()


func _begin() -> void:
	_waiting = false
	create_tween().tween_property(_overlay, "prompt_alpha", 0.0, 0.4)
	match _mode:
		&"fresh":
			finished.emit(&"opening")
		&"after_ending":
			# Another little man washes up beside the old footprints.
			Story.reset_for_new_cycle()
			Game.player.visual.visible = true
			place_player(shore.wake, shore.inland)
			pose_prone(Game.player)
			finished.emit(&"opening")
		_:
			await release(2.6)
			finished.emit(&"continue")


func _lay_footprints(dressing: Node) -> void:
	var trail: MultiMeshInstance3D = TRAIL.new()
	trail.name = "LastFootprints"
	dressing.add_child(trail)
	trail.global_transform = Transform3D.IDENTITY
	# From where he stood, along the tideline and out of the picture.
	var start := shore.shore_point(-6.0, -1.0)
	trail.lay(start, shore.along, 140, shore.sand, 0.0)
