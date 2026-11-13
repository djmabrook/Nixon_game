# Surfing

The little man doesn't walk any more. Wherever a room has a `SurfTerrain`, he rides a board
over undulating ground: dunes that never move and swells that roll across it. Physics, look,
sound and camera all live in this folder, so every region surfs the same way.

## Controls

| | Keyboard + mouse | Gamepad |
|---|---|---|
| Carve | A / D | Left stick left / right |
| Tuck (go faster, pump) | W or Shift | Stick forward, RT or B |
| Brake / power slide | S | Stick back |
| Pop (ollie) | Hold Space to crouch, release to jump | Hold A, release |
| Spin / flip in the air | A / D spin, W / S flip | Left stick |
| Grab | Tuck in the air | Tuck in the air |
| Look around | Mouse | Right stick (eases back by itself) |

All of it goes through `SurfInput` (`surf_input.gd`). A touch layer for iPhone only has to set
`touch_active`, `touch_steer`, `touch_lean`, `touch_tuck` and `touch_jump`; nothing else changes.

## How it rides

- **Gravity along the slope**, air drag, sand friction. Nothing pushes him but the ground.
- **Pumping**: tuck on a downslope and it pulls harder; tuck on an upslope and it costs you.
  Down: tuck. Up: stand. That's how you build speed on rollers.
- **Carving**: the board turns, the velocity follows as fast as the edge grips (`grip`, in m/s²).
  Turn harder than that and he slides: spray, hiss, speed loss, a power slide.
- **Launching** is physical, never a trigger volume: when the ground drops away faster than gravity
  can follow (a crest at speed, a swell sinking under him), he leaves it. Releasing pop on a lip
  adds the ollie to it.
- **Air**: spin and flip; close to the ground the board settles toward a clean landing if you're
  within 45° (spin) or 65° (flip) and not fighting it.
- **Landing** keeps the speed along the slope. Match the slope (land on a downslope) and he gains a
  little. Sideways (> 58°), upside down (> 60°) or too hard (> 30 m/s into the ground) is a wipeout.
- **Wipeout**: every joint becomes a Verlet particle (`surf_ragdoll.gd`) braced by his bone lengths,
  tumbling on the live terrain, swells and all. The board flies off on its own. When he's still, he
  gets back up (`recover_time`) and the board slides back under his feet.
- **Flow** (0..1) grows with speed, air, clean tricks and gates; a wipeout halves it. It drives the
  trail's length and colour, the board's glow, the dithered world's ink cycling through the
  spectrum, and the soundtrack opening up. No numbers on screen, ever.

## Making a region surfable

1. Add a `SurfTerrain` node to the room (or a script that extends it, like `hub/hub_surf.gd`).
   Fill `static_waves` (dunes) and `moving_waves` (swells, max 8) with `SurfWave` resources:
   planar or radial (with spiral `arms`), wavelength, speed (0 = static), amplitude, sharpness and
   a radial window. Set `bounds_radius` to keep him in.
2. Your ground must agree with `SurfTerrain.static_height()`: build its mesh and collision from that
   (or set `base_func` to your own shape and add `static_extra()` to it, as the hub does).
3. Put `#include "res://surf/surf_waves.gdshaderinc"` in the ground shader and call
   `surf_displace(VERTEX, NORMAL, MODEL_MATRIX);` in `vertex()`, then `terrain.add_material(mat)`.
4. List the ground's body in `terrain.ground_bodies` so he passes over it (anything else on layer 1
   is an obstacle he can hit, bounce off, or be knocked down by).
5. `add_calm_spot(pos, radius)` around props standing on the sand, so swells don't swallow them.

That's it: when the room loads, the terrain gives him a board (`Surfer.attach`), a chase camera,
the trail, spray, sound. Rooms without a `SurfTerrain` still walk.

## Bending the rules (the rule each region breaks)

`Game.player.get_node("Surfer")` is the `Surfer`. Change its exports at runtime (gravity is on the
terrain), call `push(accel)` every physics frame for currents and conveyors, `boost(speed)` for
launch pads, `wipeout()` to knock him off. Signals: `launched`, `landed(quality, impact)`,
`trick_landed(half_spins, flips, airtime)`, `wiped_out`, `recovered`, `boosted`.
`FlowGate` (`flow_gate.gd`) is a ring of light: pass through it for speed, flow and a chime one step
up D lydian from the last.

Story sequences that take the player (`Story.is_playing()`) get him back on foot automatically and
put him back on the board when they let go.

## Music

Drop Alberto's tracks into `res://music/`: `<room_id>.ogg` for a region, `surf.ogg` for everywhere
else (mp3 and wav work too). They loop, crossfade between rooms, and play on the Music bus, whose
low-pass opens with flow. API: `Sound.play_music(stream_or_path)`, `Sound.set_music_intensity(x)`.

## Checking

- `godot --headless --path . res://surf/tests/surf_test.tscn` (exit 0 = pass): drop-in speed, staying
  on the moving surface, pop and landing, carving direction, wipeout, ragdoll on the sand, getting
  up, limb lengths, gates, and surfing into the pit to a room.
- Stills: `xvfb-run godot --rendering-method forward_plus --path . res://surf/tests/shots.tscn -- --out=DIR`
  (in the cloud container, Forward+ needs `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`).
