# Sound direction

Read this before making anything that makes a noise. One system, one set of sounds, one set of
rules, so the lake, the plain, the spiral and the mountain sound like the same world.

## The four laws

1. **Nobody speaks.** No voice, no breath, no grunt, no murmur, no choir. Not the little man, not
   the Watcher, not the Stray. Bodies make contact sounds (steps, hands, cloth); nothing vocalises.
2. **The Watcher is an empty broadcast.** Mains hum, snow, and a held test tone. A channel with
   nothing on it. When he stares, the hum pulses like a slow heart and the tone rises out of the
   snow. That is all he ever "says".
3. **Giant things sound late and low.** Sound travels at 343 m/s, and we let it. A 300 m head
   that moves is heard a second later. Bigger is lower, slower to swell, slower to fade, duller
   with distance. Nothing huge starts or stops at once.
4. **When his eyes close, there is silence.** Not quiet: silence. The broadcast winds down like a
   set losing power and the world goes with it. At the end only the little man's own steps remain.

Two more that follow from the story:

- **The stare drains colour, in sound too.** Being looked at narrows the whole mix to a thin
  telephone band (about 320 to 650 Hz) while the broadcast stays whole. Safety is full range;
  danger is one-bit.
- **Inks are the only music.** Each ink is one note. Ember, salmon and crimson stack in fifths
  (D, A, E). Ultraviolet is the raised fourth (G#), the strange bright note of D lydian that only
  sounds right once the other three are home. Mending plays them; nothing else is scored.

## The mixer

`default_bus_layout.tres` (Godot loads it automatically):

| Bus | Sends to | What goes there | Effects |
|---|---|---|---|
| Master | | everything | hard limiter |
| Broadcast | Master | the Watcher: hum, hiss, tone, TV on/off, static | old-speaker low-pass. **Not drained by the stare.** |
| World | Master | everything else | the stare drain (low-pass + high-pass driven by `Sound.set_stare`) |
| Bed | World | each region's air | ducks under the Far bus (sidechain) |
| Near | World | the little man, his hands, small props, fire | small reverb, set per room |
| Far | World | giant things | air low-pass, vast reverb, set per room |
| Ink | World | ink notes, mends | hall reverb |

Ids pick their bus by prefix (`bed_` Bed, `broadcast_ tv_ static_ stare_` Broadcast,
`giant_ sphere_ eyelids_` Far, `ink_ mend` Ink, everything else Near). Don't make new buses
in a room: if you need one, ask in the sound thread.

## The API

`Sound` is an autoload (`audio/sound.gd`). Ids are files in `audio/library/` without the extension;
`step_sand` picks one of `step_sand_1..6` and never the same one twice.

```gdscript
Sound.play(&"pickup")                                  # 2D one-shot (things happening to him)
Sound.play_at(&"fire_ignite", fire.global_position)    # 3D one-shot, late by distance, dulled by air
Sound.giant(&"giant_footfall", foot_pos, 150.0)        # a 150 m thing: Far bus, lower, carries further
Sound.set_bed(&"bed_lake", -2.0)                       # crossfade the region's air (RoomAudio does this)
Sound.set_stare(0.7)                                   # drain the world (WatcherBroadcast does this)
Sound.hush(4.0)                                        # silence; keep_near=true keeps his steps
Sound.unhush(3.0)
Sound.delay_for(pos)                                   # seconds until a sound at pos is heard
```

Nodes:

- **`RoomAudio`** (`audio/room_audio.gd`): put one in your room scene. Sets the bed, footstep
  surface, lateness and reverb sizes when the room is entered. A room without one has no bed.
- **`GiantVoice`** (`audio/giant_voice.gd`, an `AudioStreamPlayer3D`): the continuous sound of a
  huge thing. Set `sound_id` and `size_m`, drive `intensity` every frame; the listener hears each
  change late, and big things swell and fade slowly.
- **`WatcherBroadcast`** (`audio/watcher_broadcast.gd`): every watching television, and the
  Watcher himself. Drive `presence` and `stare`; `await close_eyes(time)` winds it down to nothing.
  `spatial = false` for the mountain face (he is the sky); turn on `drains_world` on exactly one.

The shared television (`props/watching_set.tscn`) already carries a `WatcherBroadcast`: it hums
louder the more open its eyes are, stares (snow, a quicker pulse) within `stare_radius` meters,
and powers off with a CRT click when its lids shut. Rooms that place one get its sound for free.

Footsteps are automatic: `Sound` follows `Game.player` in every room and lands a step every
0.95 m walked (1.55 m run) on `Sound.surface`. For rooms with several grounds, set
`Sound.surface_resolver = func(pos): return &"water" if pos.y < 0.1 else &"stone"`.
`Sound.footsteps_enabled = false` while a room drives him.

## The library

All of it is synthesised by `audio/synth/build_library.py` (numpy + scipy, no recordings).
Re-run it to rebuild; it is deterministic. Beds are 48 s seamless loops.

| Group | Ids |
|---|---|
| Steps | `step_sand` `step_stone` `step_tile` (hollow ceramic, the checker plain) `step_water` `step_felt` (the tie road) |
| Hands | `hand_touch` `pickup` `putdown` `usher_glove` `cursor_tick` (the Stray) |
| Fire | `fire_loop` `fire_ignite` |
| Failure | `statue_stiffen` (caught, turns to stone) `rewind` `wake` (he always gets up) |
| Things turning to him | `phone_ring` (loops; no dial) `mic_swivel` `mic_feedback` |
| The Watcher | `broadcast_hum` `broadcast_hiss` `broadcast_tone` (loops) `tv_on` `tv_off` `static_burst` `stare_land` |
| Giants | `giant_footfall` `giant_boom` `giant_settle` `giant_grind` `giant_groan` `giant_rumble` `sphere_roll_loop` `eyelids_close` |
| Inks | `ink_<ember/salmon/crimson/ultraviolet>_take` (carried out) `ink_<ink>_home` (planted in the spiral) `mend` |
| Beds | `bed_hub_night` `bed_lake` (no broadcast: he turned his back) `bed_checker` (tide every 16 s) `bed_grid` `bed_mountain` `bed_dawn` |

A room may keep a sound of its own in its folder (`rooms/<id>/sfx/...`) and play it with
`Sound.play(stream)`, `Sound.play_at(stream, pos, 0, 1, {"bus": &"Far"})` and so on. If it could be
useful anywhere else, add it to the generator instead.

## Levels

Roughly, at the default 0 dB: beds sit around -24 dBFS RMS, steps -9 dB under that,
the broadcast hum -6 dB, snow -12 dB, the tone -22 dB. Ink and mends are the loudest thing in a
region and should be: they are the reward. Giants are loud close up and fall off by inverse
distance with an air filter. If something must be louder, raise it at the call, not in the file.

## Per room

| Room | Bed | Surface | Broadcast | Signature moments |
|---|---|---|---|---|
| Hub (spiral) | `bed_hub_night`, `bed_dawn` at the end | sand | the half-buried TV, spatial, `presence` by distance | `ink_<ink>_home` when an ink is planted, `giant_boom` when the pit blinks, `eyelids_close` (short, pitched up) for the blink itself |
| Lake | `bed_lake` | stone, water at the edge | only the near-shore TV; none from the mountain | `fire_ignite` + a `fire_loop` 3D player per fire, `giant_groan` (lateness 1.5) as the beacon's light climbs the head, `ink_ember_take`, `mend` |
| Checker plain | `bed_checker` | tile | the TV | spheres as `GiantVoice(sphere_roll_loop)` with `size_m` = diameter, `giant_settle`/`giant_boom` on landings, `giant_rumble` on the fourth-tide lift, `ink_salmon_take` + `mend` at the socket |
| Red Grid | `bed_grid` | stone | the TV | `giant_rumble` under the pupil, `giant_boom` when the circle falls, `ink_crimson_take` |
| Mountain (face) | `bed_mountain` | felt on the tie | the Watcher, `spatial = false`, `drains_world = true` | `giant_grind` (GiantVoice on the face) when it moves unseen, `stare_land` when it catches sight, `statue_stiffen` then `rewind` then `wake`, `eyelids_close` + `close_eyes()` + `Sound.hush()` at the end |

## Checking

`godot --headless --path . res://tools/audio_test.tscn` (exit code 0 = pass) checks the buses,
the library, distance delay, the stare drain, a television closing its eyes, a late giant and the
hush. Run it with the smoke test before a PR that touches sound.
