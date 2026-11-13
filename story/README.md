# The opening and the ending

Wordless sequences that bookend the game, played inside the hub. Built from the approved
story, "Little Man: the silent through-line".

## What plays

**Title shore** (first hub load of every launch). Night beach held from out in the shallows, the
sea lapping, the ridge and the mountain beyond, one cursor blinking. Any button begins.
- Never played: he lies face-down in the wash.
- Part way through: he stands at the tideline; the camera swoops into the follow camera.
- After the ending: nobody is there. A line of his footprints leads out of the frame. Any button
  starts a new cycle (`Game.new_cycle()`) and another little man washes up beside them.

**Opening** (once).
1. The last wave goes over him, then the whole sea drains away down the beach and leaves the
   sand shining.
2. He twitches, pushes up, sags, pushes again, stands, and looks around.
3. The Stray blinks in like a caret far down the tideline and runs to him, then noses about.
4. Control. Walking inland he meets the first television (the hub's `WatchingSet`): the camera
   pushes in over his shoulder at the set, colour bleeds out of the frame, the Stray hides behind
   his legs, then one shot from right at the glass, his eyes-view of him.
5. The first long descent: well down the crater wall, the camera turns to look back up at him
   walking down, the rim behind him rising like a stadium.

**Ending** (`Story.begin_ending()`).
1. He rises out of the pit, unwinding the sinking spiral, as the sky pales.
2. Dawn on the tideline. The camera pulls back further than it ever has, to 1.5 km out and
   1.2 km up, until the whole land lies there: shore, the crater as an eye, the regions and the
   sleeping mountain. Then back down to him.
3. He walks along the tideline toward the sun, the Stray at his heel.
4. After about 26 m the camera stops following. It settles side-on and stays. The picture draws
   in from its edges onto bare paper, and he walks out of the picture onto the paper margin as a
   few pixels of rust ink. The Stray looks back once, at us, and follows. If the player lets go of
   the stick, he walks on by himself after 14 s.
5. The empty shore holds. Silence, then black. Then the title shore, with his footprints.

## Hooks

| Who | Call |
|---|---|
| The mountain room | `Story.begin_ending()` as he drops through the disc beyond the closed eyes |
| Anyone | `Story.is_playing()` while a sequence holds the player and camera; `Story.current_sequence()` |
| The hub (optional) | Marker3D nodes in group `story_anchor`: `shore_wake`, `first_tv`, `margin_exit`, `sun`. `set_dawn(on)`. `$InkState.is_playing()` is respected. |

Flags live on `Game` (`opening_seen`, `ending_seen`, `first_tv_seen`, `first_descent_seen`).

Everything is optional and found at runtime, so it runs on the placeholder hub too:
- The Stray is `res://companions/stray/stray.tscn` (PR #8) when present, otherwise a stand-in
  (`props/stray_standin.gd`) with the same calls.
- The television is the hub's own `WatchingSet` when it has one, otherwise one is placed.
- Sound goes through the `Sound` autoload (PR #7) when present: `bed_dawn` and `unhush` at dawn,
  `hush` at the paper. `story_audio.gd` adds the last wave and the drain under it, and is the
  whole soundscape when `Sound` is absent.
- The dither look switches to the `dawn` preset when the shader (PR #2) is in.

## Files

- `story.gd` the `Story` autoload: routing, flags, `begin_ending()`.
- `sequence.gd` shared camera and posing helpers; `title.gd`, `opening.gd`, `ending.gd`.
- `shore.gd` finds the wake spot, tideline, pit and sand height in any hub.
- `hub_dressing.gd` the tide wash, the television and the story sound, on every hub visit.
- `overlay.gd`, `paper.gdshader` the cursor prompt, the paper margin and the figures on it.
- `dawn_sky.gdshader` the sunrise. `props/` tide, footprints, the Stray stand-in.

## Checking

```
godot --headless --path . res://story/tests/story_test.tscn            # exit 0 = pass
xvfb-run godot --rendering-driver opengl3 --path . res://story/tests/story_test.tscn -- --shots=/tmp/story
godot --path . -- --story=title|opening|ending|none                   # force a sequence
```
The test plays the whole arc fast (title, opening, television, descent, ending, title with
footprints). It passes on foundation/core alone and merged with PRs #2, #4, #7 and #8.
