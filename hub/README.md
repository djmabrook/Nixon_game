# The spiral hub

A night beach where the sand sinks into a whirlpool about a kilometre across (1 unit = 1 m).
You arrive on the shore facing a 120 m dune ridge with a column of embers rising behind it.
Top the ridge and the camera pulls far back over the crater, a slate-grey whirlpool sinking
180 m to a stadium-sized glowing pit.

Every room under `rooms/` gets its own glowing groove that starts at a towering ember beacon
on the beach, climbs the dune and spirals down to its own slice of the pit's rim. Walking with
a groove, the sand carries you. The first walk down takes about a minute; after that the groove
is a slide. Step into the pit and the sand swallows the little man into that room. When he
comes back he's set down a little way up the same groove. Add a room folder and a new groove
appears. Bring a room's ink home and its groove runs full (see Story below).

| File | What it is |
|---|---|
| `hub.tscn` / `hub.gd` | The scene and the arm layout, return spawns, pull, slides, camera framing, sinking |
| `sand_vortex.gd` | Builds the beach, dune ridge, crater and pit mesh, its collision and the shore wall |
| `sand.gdshader` | Flowing spiral ridges, the room grooves, the pit and its hot rim |
| `sea.gdshader`, `night_sky.gdshader` | The night sea and the starry sky with the red horizon |
| `vortex.gd` | The pit: one `RoomExit` that picks the room by which slice you enter |
| `hub_story.gd` | The story state (`InkState` node): drained start, plantings, the eye, the mountain groove, dawn |
| `landmarks.gd` | Far horizon layers you can switch on: Watcher mountain (on), beacon, pink storm, black disc |
| `footprints.gd` | His fading trail in the sand, so you can always find him |
| `props/` | Placeholder palm and ember beacon (swap for real models, keep the exports) |
| `tests/hub_test.tscn` | Headless check: every groove leads to its room and back |
| `tests/shots.tscn` | Dev only: saves screenshots along groove 0 (`-- --out=<dir>`) |

## Story

The hub follows the approved through-line, reading the foundation's ink state on `Game`:

- **Arrival:** drained to black, bone and sand. Palms and sea are black, beacons unlit, and each
  groove is a dry channel with a faint dotted pulse of its room's ink running inward. A
  half-buried television (`WatchingSet`) watches from the shore and droops a third per ink.
- **Coming home with an ink:** the hub calls `Game.bring_home()` and plays the planting. The camera
  rises over the groove, the ink fills it from the pit to its beacon, then the ink lights what it
  owns. Ember lights every beacon in turn and starts the ember column and the far beacon tower.
  Salmon brings in the pink storm. Crimson turns the islets and horizon crimson and removes the
  black disc. Sea, sand and palms get a third of their colour back. Finished grooves run full.
- **All three:** three rings of ink circle the pit in arrival order, it blinks, and the mountain's
  groove (any room whose `required_inks` is all three) uncoils in ultraviolet toward the Watcher.
- **Dawn:** `set_dawn(true)` (or the `dawn` flag). The sun rises where the palm shadows always
  pointed, everything is in full colour, and the Watcher's lights go out.
- **For the opening and ending:** Marker3D anchors in group `story_anchor` under `StoryAnchors`
  (`shore_wake`, `first_tv`, `margin_exit`), `set_dawn(on)`, and the `Vortex` node for the pit.

To preview a state, run `tests/shots.tscn -- --state=drained|planting|full|dawn`.

Tuning lives in exports on the `Hub` node (*Feel* and *Camera framing*), on `SandVortex`
(crater shape) and on `Landmarks` (which layers show). Run before a hub PR:

```
godot --headless --path . res://tools/smoke_test.tscn
godot --headless --path . res://hub/tests/hub_test.tscn
```

Which grooves have been ridden is kept on `Game` as metadata (`hub_ridden_grooves`) until the
foundation's saved state has a place for it.
