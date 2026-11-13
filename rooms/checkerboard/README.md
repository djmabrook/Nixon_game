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
| `tests/check_checkerboard.tscn` | Headless check of this room |

**Stone men** (`models/stone_littleman_a|c.glb`, from the art thread) are the men the stare caught
before him. Four mid-stride ones stand on black tiles along the route in, caught where the tide was
dragging them, and none stand on pink. Two looking up stand in the crater near the socket, facing
outward to where the eye passes. They never move and they stop rolling spheres, so they are shelter.

**Sound** uses the shared `Sound` system (see `audio/AUDIO.md`). `RoomAudio` sets `bed_checker` (its
tide breathes every 16 s) and hollow `tile` footsteps. The twelve nearest big spheres each get a
`GiantVoice` (`sphere_roll_loop`, sized by diameter, louder with speed). Landings are `giant_settle`
(`giant_boom` for cathedrals). The moon's warning and pull are `giant_groan` and `giant_rumble`
from its side of the horizon. The socket plays `ink_salmon_take` with `mend`. The shared television brings
its own broadcast, which powers off on the mend.

The room gives the **salmon** ink (`gives_ink`), which he carries out to the hub. A shared
watching television (`props/watching_set.tscn`) sits half buried near the entry and shuts its eyes
on the mend. `CraterVista` is a `VistaZone` on the approach to the crater.

Check: `godot --headless --path . res://rooms/checkerboard/tests/check_checkerboard.tscn`
