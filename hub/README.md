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
appears. Finish a room (`Room.complete()`) and its groove and beacon go dark.

| File | What it is |
|---|---|
| `hub.tscn` / `hub.gd` | The scene and the arm layout, return spawns, pull, slides, camera framing, sinking |
| `sand_vortex.gd` | Builds the beach, dune ridge, crater and pit mesh, its collision and the shore wall |
| `sand.gdshader` | Flowing spiral ridges, the room grooves, the pit and its hot rim |
| `sea.gdshader`, `night_sky.gdshader` | The night sea and the starry sky with the red horizon |
| `vortex.gd` | The pit: one `RoomExit` that picks the room by which slice you enter |
| `landmarks.gd` | Far horizon layers you can switch on: Watcher mountain (on), beacon, pink storm, black disc |
| `footprints.gd` | His fading trail in the sand, so you can always find him |
| `props/` | Placeholder palm and ember beacon (swap for real models, keep the exports) |
| `tests/hub_test.tscn` | Headless check: every groove leads to its room and back |
| `tests/shots.tscn` | Dev only: saves screenshots along groove 0 (`-- --out=<dir>`) |

Tuning lives in exports on the `Hub` node (*Feel* and *Camera framing*), on `SandVortex`
(crater shape) and on `Landmarks` (which layers show). Run before a hub PR:

```
godot --headless --path . res://tools/smoke_test.tscn
godot --headless --path . res://hub/tests/hub_test.tscn
```

Which grooves have been ridden is kept on `Game` as metadata (`hub_ridden_grooves`) until the
foundation's saved state has a place for it.
