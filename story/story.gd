extends Node
## The wordless opening and ending. Autoloaded as `Story`.
##
## Story watches Game.room_changed. When the hub loads it decides what plays there:
##
##   first hub load of a launch  -> the title shore (a held shot, any button begins)
##   then, first time ever       -> the opening: washed up, the Stray, the first television,
##                                  and the first long descent into the spiral
##   after Story.begin_ending()  -> the ending: dawn, the widest pull-back, and the walk off
##                                  the picture onto the paper margin
##
## After the ending the title shore shows a line of his footprints leading off the frame,
## on that launch and every launch after.
##
## Other threads only need two calls:
##   Story.begin_ending()   the mountain room calls this when he drops through the disc
##   Story.is_playing()     true while a sequence has taken the player and camera
##
## Testing: `godot --path . -- --story=title|opening|ending|none` forces a sequence
## (none skips the title too). See story/README.md.

signal sequence_started(name: StringName)
signal sequence_finished(name: StringName)

const TITLE_SCRIPT := preload("res://story/title.gd")
const OPENING_SCRIPT := preload("res://story/opening.gd")
const ENDING_SCRIPT := preload("res://story/ending.gd")
const DRESSING_SCRIPT := preload("res://story/hub_dressing.gd")

## Flags that survive relaunching (Game.set_flag / Game.get_flag).
const FLAG_OPENING_SEEN := &"opening_seen"
const FLAG_ENDING_SEEN := &"ending_seen"
const FLAG_FIRST_TV_SEEN := &"first_tv_seen"
const FLAG_FIRST_DESCENT_SEEN := &"first_descent_seen"

## Set false (e.g. from a test) to skip everything and leave the hub to itself.
var enabled := true
## Every sequence's timings are multiplied by this (tests run them fast).
var time_scale := 1.0

var _forced: StringName = &""
var _title_shown := false
var _pending_ending := false
var _active: Node = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--story="):
			_forced = StringName(arg.trim_prefix("--story="))
	if _forced == &"none":
		enabled = false
	Game.room_changed.connect(_on_room_changed)


## True while a sequence holds the player and camera.
func is_playing() -> bool:
	return is_instance_valid(_active) and _active.has_method(&"is_holding") and _active.call(&"is_holding")


## The name of the running sequence, or &"".
func current_sequence() -> StringName:
	return _active.get(&"sequence_name") if is_instance_valid(_active) else &""


## The mountain room calls this as he drops through the disc beyond the closed eyes.
## Travels to the hub, which wakes at dawn for the ending.
func begin_ending() -> void:
	_pending_ending = true
	await Game.go_to_hub()


## The next hub load opens on the title shore (the ending calls this before it leaves).
func show_title_next() -> void:
	_title_shown = false


# --- Flags (saved by Game in user://save.json) ---------------------------------------

func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return Game.get_flag(flag, default)


func set_flag(flag: StringName, value: Variant = true) -> void:
	Game.set_flag(flag, value)


## A new cycle after the ending: inks and rooms are forgotten, the ending is remembered.
func reset_for_new_cycle() -> void:
	for f in [FLAG_OPENING_SEEN, FLAG_FIRST_TV_SEEN, FLAG_FIRST_DESCENT_SEEN]:
		Game.set_flag(f, false)
	Game.new_cycle()


# --- Routing ------------------------------------------------------------------------

func _on_room_changed(room: Room) -> void:
	if is_instance_valid(_active):
		_active.queue_free()
		_active = null
	if not enabled or room == null or room.room_id != Game.HUB_ID:
		_title_shown = true   # starting straight in a room skips the title
		return

	var dressing := DRESSING_SCRIPT.new()
	room.add_child(dressing)

	var what := _choose(room)
	match what:
		&"ending":
			_pending_ending = false
			_start(ENDING_SCRIPT, room)
		&"title":
			_title_shown = true
			_start(TITLE_SCRIPT, room)
		&"opening":
			_start(OPENING_SCRIPT, room)
		_:
			# Ordinary hub visit: the opening's later beats (first television, first
			# descent) keep listening until they have played once.
			if not get_flag(FLAG_FIRST_TV_SEEN) or not get_flag(FLAG_FIRST_DESCENT_SEEN):
				_start(OPENING_SCRIPT, room, {skip_wake = true})


func _choose(_room: Room) -> StringName:
	if _forced in [&"title", &"opening", &"ending"]:
		var f := _forced
		_forced = &""
		_title_shown = true
		return f
	if _pending_ending:
		return &"ending"
	if not _title_shown:
		return &"title"
	return &""


func _start(script: GDScript, room: Room, props := {}) -> Node:
	var seq: Node = script.new()
	seq.set(&"time_scale", time_scale)
	for k in props:
		seq.set(k, props[k])
	seq.name = "Story_%s" % String(seq.get(&"sequence_name")).capitalize()
	room.add_child(seq)
	_active = seq
	sequence_started.emit(seq.get(&"sequence_name"))
	seq.tree_exiting.connect(func() -> void:
		if _active == seq:
			_active = null
	)
	if seq.has_signal(&"finished"):
		seq.connect(&"finished", _on_sequence_finished.bind(seq), CONNECT_ONE_SHOT)
	return seq


func _on_sequence_finished(next: StringName, seq: Node) -> void:
	var done: StringName = seq.get(&"sequence_name")
	sequence_finished.emit(done)
	var room := Game.current_room
	if not is_instance_valid(room):
		return
	match next:
		&"opening":
			seq.queue_free()
			_start(OPENING_SCRIPT, room)
		&"continue":
			seq.queue_free()
			if not get_flag(FLAG_FIRST_TV_SEEN) or not get_flag(FLAG_FIRST_DESCENT_SEEN):
				_start(OPENING_SCRIPT, room, {skip_wake = true})
		&"title":
			seq.queue_free()
			_start(TITLE_SCRIPT, room)
		_:
			pass
