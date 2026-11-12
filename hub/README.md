# The spiral hub

A night beach where the sand sinks into a vortex. Every room under `rooms/` gets its own
glowing groove that spirals down to its own slice of the pit's rim. Walk a groove into the
pit and the sand swallows the little man into that room; come back and he is set down a few
steps up the same groove. Add a room folder and a new groove appears. Finish a room
(`Room.complete()`) and its groove and ember stake go dark.

| File | What it is |
|---|---|
| `hub.tscn` / `hub.gd` | The scene and the arm layout, return spawns, pull, camera zoom, sinking sequence |
| `sand_vortex.gd` | Builds the funnel mesh, its collision and the shore wall (also in the editor) |
| `sand.gdshader` | Flowing spiral ridges, the room grooves, the pit and its hot rim |
| `sea.gdshader` | The ring of night sea |
| `vortex.gd` | The pit: one `RoomExit` that picks the room by which slice you enter |
| `props/` | Placeholder palm and ember stake (swap for real models, keep the exports) |
| `tests/hub_test.tscn` | Headless check: every groove leads to its room and back |
| `tests/shots.tscn` | Dev only: saves three screenshots (`-- --out=<dir>`) |

Feel knobs are exported on the `Hub` node under *Feel* (pull, swirl, arrival grace,
camera zoom, sink time). Run before a hub PR:

```
godot --headless --path . res://tools/smoke_test.tscn
godot --headless --path . res://hub/tests/hub_test.tscn
```

Swapping in real art: the funnel shape lives in `sand_vortex.gd` and the look in
`sand.gdshader`, so a sand texture can go into the shader without touching collision.
Palms and stakes are self-contained scenes in `props/`.
