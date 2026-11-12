# Checker Plain

**The broken rule is gravity.** A pink and black plain runs to every horizon. A red
moon, the Watcher's eye, hangs low and circles it, and "down" always points at the moon.

- **The tide.** The moon comes round to a new bearing (warning: the eye opens, the horizon
  flares, the black tiles shiver, a rising tone plays). Then it pulls. On **black tiles** the
  little man is dragged toward the moon; **pink tiles** hold him. Wind streaks and flowing
  lines on the black tiles show which way down is.
- **The herds.** About 150 spheres, from marbles to cathedrals (up to about 72 m tall), migrate
  with each tide. Big ones are capped slow, so a cathedral takes many seconds to pass, with a
  low shake that grows as it nears. He can push anything up to 2.5 m radius.
- **The lift.** On every fourth tide the eye looks up and everything rises at once, giants
  included. The first lift plays a low vista shot.
- **The goal.** The pale sphere starts beside him at the edge. Escort it about 200 m to the
  crater at the centre, across several tides, and drop it in the socket. Anything else is
  spat back out. Giants are kept out of the crater.
- **The mend.** The eye shuts and sets, the tide stops for good, the spheres settle, pink
  footing blooms under his feet, and an exit ring opens in the crater. The room stays mended
  on later visits. The ring at the spawn always leads back to the hub.

| File | What it does |
|---|---|
| `room.tscn` / `checkerboard.gd` | Room root: tide loop, moon, herds, drift and shoving, lift, mend |
| `board.gd` | Builds the plain, the crater bowl and the socket from inspector numbers (visible in the editor) |
| `checker_sphere.gd` | A sphere: set `radius` (and `is_key`), and it builds its own mesh and collision |
| `checker_floor.gdshader` | Filtered checker to the horizon, flow lines, ripple, pink footing |
| `checker_sphere.gdshader`, `dream_sky.gdshader` | Sphere checker; the sky with the storm band and the moon eye |
| `room_sfx.gd` | Synthesized placeholder sounds (no audio files); swap entries in `sounds` for real samples |
| `tests/check_checkerboard.tscn` | Headless check of this room |

Hooks for other threads: `TVSpot` marks where the shared watching-television prop should sit
near the entry, and `CraterVista` is a `VistaZone` on the approach to the crater.

Check: `godot --headless --path . res://rooms/checkerboard/tests/check_checkerboard.tscn`
