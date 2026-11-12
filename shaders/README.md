# Dither look

The game's pixel post-process. It takes the finished 640×360 frame, snaps it to chunky
virtual pixels, adds an ordered (Bayer) dither and maps every pixel to a small palette.

![six presets](docs/preview.png)

It is already wired in: `main.tscn` → `Main/PostProcess/DitherLook` (`shaders/dither_look.tscn`).

## Giving a room its own era

Add this to your room script and pick a `.tres` in the inspector:

```gdscript
extends Room

@export var dither_look: DitherLookSettings
```

It is applied while the screen is faded out, so the room opens already in its era. Rooms
without one get `default_look` (the sand spiral palette).

To change era mid-room (a rule twist, a memory, the face waking up), dissolve through the
dither pattern itself:

```gdscript
DitherLook.request(get_tree(), preload("res://shaders/presets/lakeside_1bit.tres"), 0.8)
```

## Making a look

Duplicate a preset in `presets/` (or New Resource → `DitherLookSettings`) into your room folder.

| Setting | What it does |
|---|---|
| `palette` | Up to 32 colours. This is the era. |
| `virtual_height` | 360 = native, 180 = 2× chunky, 120 = 3×, 90 = 4×. |
| `dither_spread` | ~0.9 for 1-bit, 0.2–0.35 for 8–16 colours, 0 = flat posterize. |
| `bayer_size` | 8×8 smooth gradients, 4×4 more console-like, 2×2 coarse. |
| `accent_threshold` | ~0.4 keeps a grey scene grey while saturated things (a fire) keep their colour. |
| `contrast` / `brightness` / `saturation` | Grade before the palette is applied. |
| `grain` | Static, world-anchored noise in the threshold. Paper/film texture, never flickers. |
| `soft_sampling` | Averages each virtual pixel (calm). Off = crisper thin lines (grids). |

Presets, each palette pulled from one of the reference stills:
`lakeside_1bit`, `sand_spiral_16bit`, `y2k_red_grid`, `pink_checker`, `cloud_sky`, `purple_face_grid`.

## Stable in motion

With `stabilize` on (default), the virtual pixel grid and the Bayer pattern are anchored to the
world, and the ortho camera is nudged onto whole screen pixels through `h_offset`/`v_offset`
(its transform is never touched). Panning the camera then slides the image instead of making
the dither crawl. Measured on the demo after a 7.37 × 3.61 px pan: 0.26% of pixels change
with it on, 17.7% with it off.

## Demo

Open `shaders/demo/dither_demo.tscn` and press F6. Keys 1–6 switch looks with the dissolve,
0 toggles the effect, WASD walks. Screenshots:
`godot --path . res://shaders/demo/dither_demo.tscn -- --shots=/tmp/shots`
