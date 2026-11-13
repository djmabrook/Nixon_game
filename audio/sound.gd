extends Node
## The game's one audio system. Autoloaded as `Sound`. Read audio/AUDIO.md first.
##
## Everything that makes a noise goes through here or through the nodes next to it
## (RoomAudio, GiantVoice, WatcherBroadcast), so every room sounds like the same world:
##
##   Sound.play(&"pickup")                              # a 2D one-shot near the little man
##   Sound.play_at(&"fire_ignite", pos)                 # a 3D one-shot, arrives late with distance
##   Sound.giant(&"giant_footfall", pos, 120.0)         # a 120 m thing: later, lower, longer
##   Sound.set_bed(&"bed_lake")                         # the region's air (RoomAudio does this)
##   Sound.set_stare(0.8)                               # the stare drains the world's colour
##   Sound.hush(4.0)                                    # his eyes close: silence
##
## Sound ids are file names in res://audio/library/ without the extension. Ids ending
## in _1, _2 ... are variants: play(&"step_sand") picks one and never repeats the last.

signal hushed(is_hushed: bool)

const LIBRARY_DIR := "res://audio/library"
## Real speed of sound. At 340 m/s a 300 m landmark is a full second late.
const SPEED_OF_SOUND := 343.0
const SILENT_DB := -80.0

## Which bus a sound id goes to, by prefix. First match wins; the default is Near.
const BUS_BY_PREFIX := [
	["bed_", &"Bed"],
	["broadcast_", &"Broadcast"], ["tv_", &"Broadcast"], ["static_", &"Broadcast"], ["stare_", &"Broadcast"],
	["giant_", &"Far"], ["sphere_", &"Far"], ["eyelids_", &"Far"],
	["ink_", &"Ink"], ["mend", &"Ink"],
]

## Per-region tuning, set by RoomAudio. Multiplies the delay of every positioned sound.
## 1.0 is physical. Rooms that want giants to feel even further can go to 1.5 or 2.
var lateness := 1.0
## Footstep surface: sand, stone, tile, water or felt (any `step_<surface>_N` in the library).
var surface := &"stone"
## Optional Callable(world_pos: Vector3) -> StringName, for rooms with several surfaces.
var surface_resolver: Callable
## Footsteps on/off and their level. Rooms that take control of the little man may mute them.
var footsteps_enabled := true
var footsteps_db := -9.0

var _streams := {}          # id -> AudioStream
var _variants := {}         # base id -> Array[StringName]
var _last_variant := {}     # base id -> StringName
var _bed_players: Array[AudioStreamPlayer] = []
var _bed_index := 0
var _bed_id := &""
var _stare := 0.0
var _hushed := false
var _hush_tween: Tween
var _footsteps: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_index_library()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Bed"
		p.volume_db = SILENT_DB
		add_child(p)
		_bed_players.append(p)
	_footsteps = preload("res://audio/footsteps.gd").new()
	add_child(_footsteps)
	var game := get_node_or_null(^"/root/Game")
	if game:
		game.room_changed.connect(_on_room_changed)


# ------------------------------------------------------------------ library

## Every id in the library (variants listed under their full names, e.g. step_sand_3).
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _streams:
		out.append(k)
	out.sort()
	return out


func has_sound(id: StringName) -> bool:
	return _streams.has(id) or _variants.has(id)


## The stream for an id. A variant base id (step_sand) returns a random variant,
## never the same one twice in a row.
func get_stream(id: StringName) -> AudioStream:
	if _variants.has(id):
		var list: Array = _variants[id]
		var pick: StringName = list[_rng.randi() % list.size()]
		if list.size() > 1 and pick == _last_variant.get(id, &""):
			pick = list[(list.find(pick) + 1) % list.size()]
		_last_variant[id] = pick
		return _streams[pick]
	if _streams.has(id):
		return _streams[id]
	push_warning("Sound: no sound '%s' in %s" % [id, LIBRARY_DIR])
	return null


func bus_for(id: StringName) -> StringName:
	var s := String(id)
	for pair in BUS_BY_PREFIX:
		if s.begins_with(pair[0]):
			return pair[1]
	return &"Near"


# ------------------------------------------------------------------ playing

## A one-shot with no position: UI-less moments, things happening to the little man himself.
## `stream_or_id` is a library id or any AudioStream. Returns the player (already playing).
func play(stream_or_id: Variant, volume_db := 0.0, pitch := 1.0, bus := &"") -> AudioStreamPlayer:
	var stream := _resolve(stream_or_id)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus if bus != &"" else _bus_of(stream_or_id)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A one-shot at a point in the world. It arrives late (distance / speed of sound) and the
## air dulls it with distance. The player is parented to the current room, so it dies with it.
## Options: `bus`, `unit_size` (meters at which it is at full volume), `max_distance`,
## `delay` (seconds, overrides the computed lateness).
func play_at(stream_or_id: Variant, at: Vector3, volume_db := 0.0, pitch := 1.0, options := {}) -> void:
	var stream := _resolve(stream_or_id)
	if stream == null:
		return
	var bus: StringName = options.get("bus", _bus_of(stream_or_id))
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	p.unit_size = options.get("unit_size", 10.0)
	p.max_distance = options.get("max_distance", 0.0)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	# Air: high frequencies fall away with distance.
	p.attenuation_filter_cutoff_hz = options.get("air_cutoff_hz", 5000.0 if bus != &"Far" else 1600.0)
	p.attenuation_filter_db = options.get("air_db", -24.0 if bus != &"Far" else -40.0)
	var parent: Node = _world_parent()
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	var delay: float = options.get("delay", delay_for(at))
	if delay <= 0.01:
		p.play()
	else:
		# The timer lives inside the player, so a room freed mid-wait takes both with it.
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = delay
		timer.autostart = true
		timer.timeout.connect(p.play)
		p.add_child(timer)


## A giant thing: `size_m` is how big it is (a 2 m boulder, a 70 m sphere, a 300 m head).
## Bigger means lower, longer and audible from further. Always on the Far bus, always late.
func giant(stream_or_id: Variant, at: Vector3, size_m := 50.0, volume_db := 0.0) -> void:
	play_at(stream_or_id, at, volume_db, giant_pitch(size_m), {
		"bus": &"Far",
		"unit_size": clampf(size_m * 0.6, 5.0, 400.0),
	})


## How late a sound at `at` arrives at the listener, in seconds.
func delay_for(at: Vector3) -> float:
	var ears := listener_position()
	return ears.distance_to(at) / SPEED_OF_SOUND * lateness


## Pitch for a thing of a given size. Halves roughly every 16x in size; 20 m is 1.0.
func giant_pitch(size_m: float) -> float:
	return clampf(pow(20.0 / maxf(size_m, 0.5), 0.25), 0.35, 1.6)


func listener_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		return cam.global_position
	var game := get_node_or_null(^"/root/Game")
	if game and is_instance_valid(game.player):
		return game.player.global_position
	return Vector3.ZERO


# ------------------------------------------------------------------ beds

## Crossfade the region's air to a looping bed. Empty id fades the bed out.
func set_bed(stream_or_id: Variant, volume_db := 0.0, fade := 2.5) -> void:
	var id := StringName(stream_or_id) if stream_or_id is StringName or stream_or_id is String else &"<stream>"
	if id == _bed_id and id != &"<stream>" and _bed_players[_bed_index].playing:
		create_tween().tween_property(_bed_players[_bed_index], "volume_db", volume_db, fade)
		return
	_bed_id = id
	var old := _bed_players[_bed_index]
	if old.playing:
		var t := create_tween()
		t.tween_property(old, "volume_db", SILENT_DB, fade)
		t.tween_callback(old.stop)
	if id == &"":
		return
	_bed_index = 1 - _bed_index
	var p := _bed_players[_bed_index]
	var stream := _resolve(stream_or_id)
	if stream == null:
		return
	_set_loop(stream)
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play(_rng.randf() * maxf(stream.get_length() - 1.0, 0.0))
	create_tween().tween_property(p, "volume_db", volume_db, fade).set_trans(Tween.TRANS_SINE)


func bed_id() -> StringName:
	return _bed_id


## A looping stream (for your own AudioStreamPlayer/3D): loop is switched on for you.
func get_loop(id: StringName) -> AudioStream:
	var s := get_stream(id)
	if s:
		_set_loop(s)
	return s


# ------------------------------------------------------------------ the stare

## 0 = unwatched, full colour. 1 = stared at: the world drains to a thin one-bit band and only
## the broadcast stays whole. WatcherBroadcast calls this for you when `drains_world` is on.
func set_stare(amount: float) -> void:
	_stare = clampf(amount, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(&"World")
	if bus < 0:
		return
	var k := _stare * _stare * (3.0 - 2.0 * _stare)
	var lowpass := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	var highpass := AudioServer.get_bus_effect(bus, 1) as AudioEffectHighPassFilter
	if lowpass:
		lowpass.cutoff_hz = 20000.0 * pow(650.0 / 20000.0, k)
	if highpass:
		highpass.cutoff_hz = 10.0 * pow(320.0 / 10.0, k)
	AudioServer.set_bus_volume_db(bus, -6.0 * k)


func get_stare() -> float:
	return _stare


# ------------------------------------------------------------------ silence

## His eyes close and the world goes quiet. Every bus fades to nothing over `time` seconds.
## With `keep_near`, the little man's own steps stay: the walk past the sleeping face.
func hush(time := 4.0, keep_near := true) -> void:
	_hushed = true
	_tween_buses({&"Broadcast": SILENT_DB, &"Bed": SILENT_DB, &"Far": SILENT_DB, &"Ink": SILENT_DB,
		&"Near": 0.0 if keep_near else SILENT_DB}, time)
	hushed.emit(true)


## Bring the world back (dawn, a new room).
func unhush(time := 3.0) -> void:
	_hushed = false
	_tween_buses({&"Broadcast": 0.0, &"Bed": 0.0, &"Far": 0.0, &"Ink": 0.0, &"Near": 0.0}, time)
	hushed.emit(false)


func is_hushed() -> bool:
	return _hushed


# ------------------------------------------------------------------ rooms

func _on_room_changed(room: Node) -> void:
	# Each room starts unwatched and audible; RoomAudio (if any) then sets its own air.
	set_stare(0.0)
	if _hushed:
		unhush(1.5)
	lateness = 1.0
	surface = &"stone"
	surface_resolver = Callable()
	footsteps_enabled = true
	var cfg: RoomAudio = null
	for n in room.find_children("*", "Node", true, false):
		if n is RoomAudio:
			cfg = n
			break
	if cfg:
		cfg.apply()
	else:
		set_bed(&"", 0.0, 1.5)
	var game := get_node_or_null(^"/root/Game")
	if game and is_instance_valid(game.player):
		_footsteps.attach(game.player)


# ------------------------------------------------------------------ internals

func _index_library() -> void:
	var files := ResourceLoader.list_directory(LIBRARY_DIR) if ResourceLoader.has_method(&"list_directory") else DirAccess.get_files_at(LIBRARY_DIR)
	for f in files:
		var file := String(f).trim_suffix(".import").trim_suffix(".remap")
		if not (file.ends_with(".wav") or file.ends_with(".ogg")):
			continue
		var id := StringName(file.get_basename())
		if _streams.has(id):
			continue
		var stream := load(LIBRARY_DIR + "/" + file) as AudioStream
		if stream == null:
			continue
		_streams[id] = stream
		var parts := String(id).rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			var base := StringName(parts[0])
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(id)


func _resolve(stream_or_id: Variant) -> AudioStream:
	if stream_or_id is AudioStream:
		return stream_or_id
	return get_stream(StringName(stream_or_id))


func _bus_of(stream_or_id: Variant) -> StringName:
	if stream_or_id is AudioStream:
		return &"Near"
	return bus_for(StringName(stream_or_id))


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _world_parent() -> Node:
	var game := get_node_or_null(^"/root/Game")
	if game and is_instance_valid(game.current_room):
		return game.current_room
	return self


func _tween_buses(targets: Dictionary, time: float) -> void:
	if _hush_tween and _hush_tween.is_valid():
		_hush_tween.kill()
	_hush_tween = create_tween().set_parallel(true)
	for bus_name in targets:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var from := AudioServer.get_bus_volume_db(bus)
		var to: float = targets[bus_name]
		# Fade in linear amplitude, which sounds even; dB tweens die too fast at the end.
		_hush_tween.tween_method(func(v: float) -> void:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.00001))),
			db_to_linear(from), db_to_linear(to), time).set_trans(Tween.TRANS_SINE)
