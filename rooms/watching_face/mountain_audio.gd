extends Node
## Sound for the Watcher's mountain, following audio/AUDIO.md (the sound thread's direction).
##
## With the shared `Sound` autoload present it builds the agreed pieces: a non-spatial
## WatcherBroadcast that drains the world, a GiantVoice grinding on the face (heard late),
## a RoomAudio with the mountain bed and felt on the tie, and the library one-shots.
## Until that system is in the build it falls back to the room's own DreadSynth, so the
## room is never silent. The room only talks to this node.

const BROADCAST := "res://audio/watcher_broadcast.gd"
const GIANT_VOICE := "res://audio/giant_voice.gd"
const ROOM_AUDIO := "res://audio/room_audio.gd"

@export var synth_path: NodePath

var _sound: Node
var _broadcast: Node
var _grind: Node
var _ring: AudioStreamPlayer3D
var _synth: Node
var _seen_once := false


## Call from the room's _ready, after the face and land exist.
func setup(face: Node3D, on_felt: Callable) -> void:
	_sound = get_node_or_null(^"/root/Sound")
	_synth = get_node_or_null(synth_path)
	if _sound == null:
		return
	if _synth:
		_synth.queue_free()
		_synth = null
	var room_audio: Node = load(ROOM_AUDIO).new()
	room_audio.set(&"bed", &"bed_mountain")
	room_audio.set(&"surface", &"stone")
	room_audio.set(&"lateness", 1.5)
	add_child(room_audio)
	# Felt underfoot on the Watcher himself (his tie, his lapel), stone everywhere else.
	_sound.set(&"surface_resolver", func(pos: Vector3) -> StringName:
		return &"felt" if on_felt.call(pos) else &"stone")
	_broadcast = load(BROADCAST).new()
	_broadcast.set(&"spatial", false)
	_broadcast.set(&"drains_world", true)
	_broadcast.set(&"is_television", false)
	add_child(_broadcast)
	_grind = load(GIANT_VOICE).new()
	_grind.set(&"sound_id", &"giant_grind")
	_grind.set(&"size_m", face.call(&"head_radius") * 2.0)
	_grind.set(&"intensity", 0.0)
	face.add_child(_grind)
	_grind.position = face.call(&"centre") - face.global_position
	_ring = AudioStreamPlayer3D.new()
	_ring.stream = _sound.call(&"get_loop", &"phone_ring")
	_ring.bus = _sound.call(&"bus_for", &"phone_ring")
	_ring.unit_size = 12.0
	add_child(_ring)


func has_shared_sound() -> bool:
	return _sound != null


## Every frame. `ring_at` is the nearest telephone; `ring` is 0 when it should be quiet.
func update(proximity: float, stare: float, motion: float, ring: float, ring_at: Vector3) -> void:
	if _sound == null:
		if _synth:
			_synth.motion = motion
			_synth.stare = stare
			_synth.proximity = proximity
			_synth.ring = ring
		return
	_broadcast.set(&"presence", proximity)
	_broadcast.set(&"stare", stare)
	_grind.set(&"intensity", motion)
	if ring > 0.0:
		_ring.global_position = ring_at
		if not _ring.playing:
			_ring.play()
	elif _ring.playing:
		_ring.stop()


## It caught sight of him (first time per visit lands hard).
func seen() -> void:
	if _sound and not _seen_once:
		_seen_once = true
		_sound.call(&"play", &"stare_land")


## Looked back and found it had moved.
func revealed(strength: float) -> void:
	if _sound:
		_broadcast.call(&"glitch", lerpf(-14.0, -4.0, strength))
	elif _synth:
		_synth.sting(strength)


func planted(at: Vector3) -> void:
	if _sound:
		_sound.call(&"play_at", &"fire_ignite", at)
	elif _synth:
		_synth.sting(0.15)


func mic_turned(at: Vector3) -> void:
	if _sound:
		_sound.call(&"play_at", &"mic_swivel", at)


func caught() -> void:
	if _sound:
		_sound.call(&"play", &"statue_stiffen")
	elif _synth:
		_synth.slam()


## Rewind, then wake once the room is back. Bound to the autoload, so it outlives this room.
func rewind() -> void:
	if _sound:
		_sound.call(&"play", &"rewind")
		get_tree().create_timer(1.2).timeout.connect(Callable(_sound, &"play").bind(&"wake"))


## The ending: the lids grind shut, the broadcast winds down, then silence but his steps.
func eyes_close(face_centre: Vector3) -> void:
	if _sound:
		_sound.call(&"giant", &"eyelids_close", face_centre, 300.0)
		_grind.set(&"intensity", 0.0)
		_ring.stop()
		await _broadcast.call(&"close_eyes", 4.0)
		_sound.call(&"hush", 3.0)
	elif _synth:
		create_tween().tween_property(_synth, "volume_db", -80.0, 4.0)
