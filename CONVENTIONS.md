# Conventions

Read this before adding anything. Several people (and Claude threads) build this game in
parallel, each in its own folder, so the rules below are what keep us from stepping on each other.

Engine: **Godot 4.7** (GDScript, Forward+). The game has **no words**: no text in UI, rooms, or menus.

**The feel: small protagonist, big weird world.** A third-person camera behind a tiny figure, landscapes
hundreds of meters to kilometers across, landmarks that dwarf him, fog that swallows distance, and the
dither look over everything. Keep it original: our own places, shapes and palettes.

## Folders

| Folder | What lives there | Owner |
|---|---|---|
| `core/` | Game autoload, `Room`, `RoomSpawn`, `RoomExit`, `VistaZone` | foundation (change only with care) |
| `player/` | The little man | foundation; sprites thread swaps the visual |
| `camera/` | `FollowCamera` (third-person orbit) | foundation |
| `hub/` | The sand spiral hub (`hub/hub.tscn`, room id `hub`) | hub thread |
| `rooms/<room_id>/` | One folder per room, fully self-contained | one thread per room |
| `rooms/_template/` | Copy this to start a room. Never loaded by the game | foundation |
| `props/` | Shared props: `watching_set.tscn`, carried-ink objects in `props/carry/<ink>.tscn` | foundation + art |
| `boss/` | The face that moves only when unwatched | boss thread |
| `companions/` | The Stray (`companions/stray/stray.tscn`): drop it in any room. See its README | stray thread |
| `shaders/` | Dither / pixel post-process and shared shaders | shader thread |
| `art/` | Shared sprites, textures, palettes | sprites thread |
| `tools/` | Dev scripts and the smoke test | anyone |

**Stay in your folder.** If you need something changed in `core/`, `player/`, `camera/`, `main.tscn`
or `project.godot`, keep that change small and say why in the PR.
A room's own assets (textures, sounds, scripts) go inside its room folder, not in `art/`.

## Naming

- Folders and files: `snake_case` (`rooms/mirror_lake/room.tscn`, `face_boss.gd`).
- Room ids are the folder name, `snake_case`, no spaces. `hub` is reserved.
- Nodes in scenes: `PascalCase` (`ExitToHub`, `Floor`). Exception: `RoomSpawn` nodes are named
  after where the player comes from (`from_hub`, or a room id inside the hub).
- `class_name` only for things other folders use. Prefix nothing; keep names plain.
- Input actions: `move_left/right/up/down`, `look_left/right/up/down`, `run`, `focus`, `interact`, `pause`.
  Add new actions only if no existing one fits.

## The room contract

A room is **`rooms/<room_id>/room.tscn`** whose root node uses `core/room.gd` (or a script that `extends Room`).
That's all it takes to register: `Game.list_rooms()` finds every folder under `rooms/` that has a
`room.tscn` and skips folders starting with `_`. Nothing to add to a list, so parallel rooms never conflict.

Each room must have:

1. **At least one `RoomSpawn`** (a `Marker3D` with `core/room_spawn.gd`). Tick `is_default` on the one
   used when arriving from the hub. Its -Z axis is the direction the player faces.
2. **A way back.** Usually a `RoomExit` (an `Area3D` with `core/room_exit.gd` and a `CollisionShape3D`)
   with `target_room = hub`. Leave `target_spawn` empty and the player comes out at this room's door.
   You can also call `exit_to_hub()` from code (after a death, a fade, a rule twist).
3. **Ground with collision** on physics layer 1 (`world`).
4. **A landmark**, set as the room's `focus_target`: the huge thing the player orients by.
5. **Its own `WorldEnvironment`** with fog, so distance reads as distance.

Rooms must **not** contain the player or a camera. `Game` adds both after the room enters the tree:

```
Game.go_to(room_id, spawn)  ->  fade out, free old room
                            ->  instance rooms/<id>/room.tscn, add Player + FollowCamera
                            ->  room._on_room_entered(spawn), room_entered signal, fade in
```

### Breaking the rule

Each room breaks one rule. Do it from your room's script:

```gdscript
extends Room

func _on_room_entered(_spawn: StringName) -> void:
    Game.player.input_scale = Vector2(-1, -1)   # controls reversed
    Game.camera.yaw_degrees = 225               # view from the other side
```

Things you can bend without touching shared code:

- **Player** (`Game.player`): `model` (`play(&"caught")`, `set_tint(color)`; set `animation_locked` while you drive clips), `move_speed`, `run_speed`, `gravity`, `input_scale`, `controls_enabled`, `velocity`,
  `walking_changed` signal, `facing`.
- **Camera**: see the camera section below. Set `use_default_camera = false` to bring your own
  `Camera3D` and call `make_current()` yourself.
- **Room**: `clear_color`, `complete()` when the player solves it (the hub reads
  `Game.is_completed(id)`), `exit_to_hub()`.
- Lights and `WorldEnvironment`: put your own in the room scene.

Do not keep state in global variables. Anything that must survive leaving a room goes through `Game`
(today that's only `completed_rooms`; ask before adding more).

## Story state

The story is in the doc "Little Man: the silent through-line". The foundation holds its state on `Game`,
saved to `user://save.json` on every change.

- **Inks**: `Game.INKS` is `ember`, `salmon`, `crimson`. A mended room gives its ink to carry; the hub
  plants it. `Game.carry(ink)`, `Game.bring_home()` (returns the ink or `&""`), `Game.carried`,
  `Game.inks_home` (arrival order), `Game.is_ink_home(ink)`, `Game.all_inks_home()`,
  `Game.ink_progress()` (0 to 1). Signals: `ink_gained(ink)` when he picks one up,
  `ink_home(ink)` when it's planted, `carried_changed(ink)`.
- **Mending a room**: set the room root's `gives_ink` export and call `complete()`. That marks the room
  done, hands him the ink and fires `room_completed`.
- **Locking**: the room root's `required_inks` export. `Game.is_room_locked(id)`; locked rooms refuse
  `go_to`, and the hub shows their door shut. The mountain uses all three.
- **Carry slot**: `Game.player.carry_slot` shows what he carries and survives room travel (it reads
  `Game.carried`). Put the real object at `props/carry/<ink>.tscn` and it's used automatically.
- **Late shadow**: `Game.player.shadow_lag` (seconds) follows `Game.shadow_lag()`, 0.5 s with no inks
  home down to 0 with all three. Set `shadow_lag_from_story = false` to drive it yourself.
- **Flags**: `Game.set_flag(name, value)` / `Game.get_flag(name, default)` for small persistent facts
  (`opening_seen`, `ending_seen`). `Game.new_cycle()` clears inks, carried and rooms but keeps flags;
  `Game.reset_story()` wipes everything.
- **The watching television**: instance `props/watching_set.tscn` (class `WatchingSet`). Its eyes track
  the little man. `open()`, `droop(amount)`, `close()`, or set `mode` (`OPEN`, `DROOPING`, `CLOSED`).
  It closes by itself when its room calls `complete()` (`close_on_room_complete`). In the hub, tick
  `droop_with_inks` and it droops a third per ink and closes at three. Art can replace the meshes but
  keep the node names `Screen/LeftEye|RightEye/{White,Pupil,Lid}`.

## The little man

`player/model/` holds the approved rigged model (rust #a8452a, no face, faces +Z in the file) and its
clips: `idle`, `walk`, `run`, `carry_idle`, `carry_walk`, `climb`, `caught`. `LittleManModel` merges
them into one AnimationPlayer; the Player picks idle/walk/run (or the carry versions while
`Game.carried` is set) and scales playback to ground speed (`walk_anim_speed`, `run_anim_speed`).
For the Watcher catching him: `Game.player.animation_locked = true`, `Game.player.model.play(&"caught")`.
A region may recolour him with `Game.player.model.set_tint(Color(...))`; `LittleManModel.RUST` restores it.
He always casts a real shadow (the late one), never a blob. Indoors keep `camera_distance` small;
in open country push it out so he's a few pixels tall.

## Scale

**1 unit = 1 meter.** The little man is 1.7 m tall, walks at 3.5 m/s and runs at 9 m/s.

| Thing | Size |
|---|---|
| A room's playable ground | 300 m to 2 km across |
| A landmark | 50 to 300 m tall, often 200 m+ away |
| The hub ring of doors | 90 m radius, doors 40 m tall |
| Far backdrop layers | 1 to 3 km out (camera draws to 4 km) |

Fog does the work of making things feel far: start around `fog_density = 0.004` and tune per room.
For a skyline that should stay crisp through fog (distant mountains, a huge face on the horizon), use
a material with `disable_fog = true` on those far meshes or billboards.

## Camera

`Game.camera` is a `FollowCamera`: a perspective camera orbiting behind the little man.

- **Player controls**: mouse or right stick orbits. Holding `focus` (Q, right mouse, left trigger)
  turns the view toward the room's `focus_target` and zooms in a little. When the player walks
  without touching the camera, it drifts back behind them.
- **Framing**: it sits low with the horizon in the lower part of the frame and the little man in the
  lower third, so the sky and landmarks dominate. `frame_tilt_degrees` controls that.
- **Room exports** (on the room root): `camera_distance`, `camera_pitch_degrees`, `camera_fov`
  (lower FOV makes distant things loom), `camera_far`, `focus_target`. The player spawn's facing sets
  the starting direction, so point your default `RoomSpawn` at the landmark.
- **Vistas**: drop a `VistaZone` (an `Area3D` with `core/vista_zone.gd` and a shape) and set
  `look_target`. When the little man walks in, the camera pulls back `pull_back` meters, looks at the
  target until he's a few pixels tall, then hands control back. Use them for reveals.
- **Scripted shots**: `await Game.camera.play_shot(from, look_at, hold, blend)` for any fixed shot,
  `Game.camera.face_toward(point)` to turn instantly.
- **Being watched**: `Game.camera.is_point_visible(pos)` is true when a point is in the frustum and
  on screen. It ignores walls; raycast if occlusion matters. The face boss relies on it.

## Physics layers

1 `world` · 2 `player` · 3 `triggers` · 4 `enemies`. The player collides with 1 and 4.
`RoomExit` sits on 3 and watches 2.

## Look

Internal resolution is **640×360**, scaled up by whole numbers with nearest filtering, so it's chunky
by default. At this resolution and scale, the little man at a distance is a handful of pixels: that's the point. The dither post-process lives in `shaders/` and attaches under `Main/PostProcess`.
Rooms may pick their own palette and lighting; keep text and UI out.

## Running and checking

- Play: open the project in Godot and press F5. The mouse is captured; Esc frees it, click to recapture. Start in a room directly with
  `godot --path . -- --room=test_room`, or set `start_room` on `main.tscn`.
- Smoke test (run before every PR): `godot --headless --path . res://tools/smoke_test.tscn`.
  Exit code 0 means the hub, a room, the exit back, and the story hooks all work.
  It turns saving off, so it never touches your save.

## Git

- Branch per piece of work: `hub/spiral`, `room/<room_id>`, `boss/face`, `shader/dither`, `art/sprites`.
- PRs into `main`, small and inside your folder. Commit `.import` and `.uid` files; `.godot/` is ignored.
