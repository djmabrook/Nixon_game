# Checkerboard

From the pink and black checkered-spheres still. **The broken rule is gravity.**

"Down" swings across the board like a tide. Black tiles let it take the little man;
pink tiles hold him. The checkered balls roll wherever down is, and every fourth tide
down lets go and the balls float. Roll a small ball into the glowing socket to finish
the room (`complete()`). The big balls don't fit. The exit ring on the spawn platform
always leads back to the hub.

How a cycle reads without words: an edge of the board blinks red and the black tiles
shiver (warning), a low surge plays, the edge burns and lines flow across the black
tiles toward it (pull), then it fades (calm).

| File | What it does |
|---|---|
| `room.tscn` / `checkerboard.gd` | Room root, the tide loop, player drift and shoving, camera lean/shake, completion |
| `board.gd` | Builds floor, rim, socket pit, edge strips from `tiles`, `tile_size`, `socket_tile` (editor-visible) |
| `checker_sphere.gd` | A ball: set `radius` and colors, it builds its own mesh and collision |
| `checker_floor.gdshader` | World-space checker, flow lines, ripple |
| `checker_sphere.gdshader`, `dream_sky.gdshader` | Ball checker and the pink storm sky that hangs behind the camera |
| `room_sfx.gd` | Synthesized placeholder sounds (no audio files); swap entries in `sounds` for real samples |
| `tests/check_checkerboard.tscn` | Headless check of this room |

Tuning lives in the inspector on the room root (tide timing and strength) and on `Board`.
Balls collide with physics layer 5 too: the invisible gate across the entry gap keeps them
on the board without blocking the little man.

Check: `godot --headless --path . res://rooms/checkerboard/tests/check_checkerboard.tscn`
