# Conventions

Read this before adding anything. Several people (and Claude threads) build this game in
parallel, each in its own folder, so the rules below are what keep us from stepping on each other.

Engine: **Godot 4.3+** (GDScript, Forward+). The game has **no words**: no text in UI, rooms, or menus.

## Folders

| Folder | What lives there | Owner |
|---|---|---|
| `core/` | Game autoload, `Room`, `RoomSpawn`, `RoomExit` | foundation (change only with care) |
| `player/` | The little man | foundation; sprites thread swaps the visual |
| `camera/` | `IsoCamera` | foundation |
| `hub/` | The sand spiral hub (`hub/hub.tscn`, room id `hub`) | hub thread |
| `rooms/<room_id>/` | One folder per room, fully self-contained | one thread per room |
| `rooms/_template/` | Copy this to start a room. Never loaded by the game | foundation |
| `boss/` | The face that moves only when unwatched | boss thread |
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
- Input actions: `move_left`, `move_right`, `move_up`, `move_down`, `interact`, `pause`.
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

Rooms must **not** contain the player or a camera. `Game` adds both after the room enters the tree:

```
Game.go_to(room_id, spawn)  ->  fade out, free old room
                            ->  instance rooms/<id>/room.tscn, add Player + IsoCamera
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

- **Player** (`Game.player`): `move_speed`, `gravity`, `input_scale`, `controls_enabled`, `velocity`,
  `walking_changed` signal, `facing`.
- **Camera**: the room's `camera_size`, `camera_yaw_degrees`, `camera_pitch_degrees` exports, or
  `Game.camera` at runtime (`follow_smoothing`, `target`, `is_point_visible()`). Set
  `use_default_camera = false` to bring your own `Camera3D` and call `make_current()` yourself.
- **Room**: `clear_color`, `complete()` when the player solves it (the hub reads
  `Game.is_completed(id)`), `exit_to_hub()`.
- Lights and `WorldEnvironment`: put your own in the room scene.

Do not keep state in global variables. Anything that must survive leaving a room goes through `Game`
(today that's only `completed_rooms`; ask before adding more).

## Physics layers

1 `world` · 2 `player` · 3 `triggers` · 4 `enemies`. The player collides with 1 and 4.
`RoomExit` sits on 3 and watches 2.

## Look

Internal resolution is **640×360**, scaled up by whole numbers with nearest filtering, so it's chunky
by default. The dither post-process lives in `shaders/` and attaches under `Main/PostProcess`.
Rooms may pick their own palette and lighting; keep text and UI out.

## Running and checking

- Play: open the project in Godot and press F5. Start in a room directly with
  `godot --path . -- --room=test_room`, or set `start_room` on `main.tscn`.
- Smoke test (run before every PR): `godot --headless --path . res://tools/smoke_test.tscn`.
  Exit code 0 means the hub, a room, and the exit back all work.

## Git

- Branch per piece of work: `hub/spiral`, `room/<room_id>`, `boss/face`, `shader/dither`, `art/sprites`.
- PRs into `main`, small and inside your folder. Commit `.import` and `.uid` files; `.godot/` is ignored.
