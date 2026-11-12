@tool
class_name DitherLookSettings
extends Resource
## One "art era": a palette plus how coarse and how dithered the image is.
## Make one .tres per room (or reuse the presets in presets/) and hand it to DitherLook.

## Up to 32 colours. Order does not matter.
@export var palette: PackedColorArray = PackedColorArray([Color.BLACK, Color.WHITE]):
	set(v):
		palette = v
		emit_changed()

## How many virtual pixels tall the screen is. The game renders at 640x360, and this is
## rounded so each virtual pixel is a whole number of real ones: 360 (native), 180 (2x chunky),
## 120 (3x), 90 (4x).
@export_range(45, 1080, 1) var virtual_height: int = 180:
	set(v):
		virtual_height = v
		emit_changed()

## How far the Bayer pattern pushes colours. ~1.0 for 1-bit, ~0.15-0.35 for 16+ colours. 0 = flat posterize.
@export_range(0.0, 2.0, 0.01) var dither_spread: float = 0.3:
	set(v):
		dither_spread = v
		emit_changed()

## Bayer matrix size. 8x8 gives smooth gradients, 2x2 gives a coarse checker texture.
@export_enum("2x2:1", "4x4:2", "8x8:3") var bayer_size: int = 3:
	set(v):
		bayer_size = v
		emit_changed()

## Saturation a source pixel needs before strongly coloured palette entries may be used.
## 0 = off. ~0.35 keeps a mostly grey scene grey while a red fire stays red.
@export_range(0.0, 1.0, 0.01) var accent_threshold: float = 0.0:
	set(v):
		accent_threshold = v
		emit_changed()

@export_group("Grade (before quantising)")
@export_range(0.0, 3.0, 0.01) var contrast: float = 1.0:
	set(v):
		contrast = v
		emit_changed()
@export_range(-1.0, 1.0, 0.01) var brightness: float = 0.0:
	set(v):
		brightness = v
		emit_changed()
@export_range(0.0, 3.0, 0.01) var saturation: float = 1.0:
	set(v):
		saturation = v
		emit_changed()
## Per-pixel noise added to the threshold. Static and tied to the world, so it reads as
## paper or film texture and never flickers.
@export_range(0.0, 1.0, 0.01) var grain: float = 0.0:
	set(v):
		grain = v
		emit_changed()
## Average 4 samples per virtual pixel (less crawling) instead of one point sample (crisper thin lines).
@export var soft_sampling: bool = true:
	set(v):
		soft_sampling = v
		emit_changed()
## Photographic negative before quantising: light becomes dark, shadows read as solid ink.
@export var invert: bool = false:
	set(v):
		invert = v
		emit_changed()


@export_group("Depth haze (3D)")
## Number of flat haze layers between haze_start and haze_end. 0 = off.
## Distance reads as scale: a far mountain sits behind several clear sheets of air.
@export_range(0, 12, 1) var haze_steps: int = 0:
	set(v):
		haze_steps = v
		emit_changed()
@export var haze_color: Color = Color("dde1e0"):
	set(v):
		haze_color = v
		emit_changed()
## Metres. Layers are spaced logarithmically between start and end.
@export_range(1.0, 500.0, 0.5, "or_greater") var haze_start: float = 25.0:
	set(v):
		haze_start = v
		emit_changed()
@export_range(10.0, 20000.0, 1.0, "or_greater") var haze_end: float = 1600.0:
	set(v):
		haze_end = v
		emit_changed()
## How far the last layer goes toward haze_color. Below 1 keeps far silhouettes visible.
@export_range(0.0, 1.0, 0.01) var haze_amount: float = 0.85:
	set(v):
		haze_amount = v
		emit_changed()
## Band the sky too (off: the sky stays as rendered and far ridges sit against it).
@export var haze_sky: bool = false:
	set(v):
		haze_sky = v
		emit_changed()

@export_group("Silhouette outline (3D)")
## Ink line where something stands in front of much more distant things. 0 = off.
@export_range(0.0, 1.0, 0.01) var outline_strength: float = 0.0:
	set(v):
		outline_strength = v
		emit_changed()
@export var outline_color: Color = Color("17171a"):
	set(v):
		outline_color = v
		emit_changed()
## Only things at least this far away (metres) get the line, so landmarks do and props don't.
@export_range(0.0, 2000.0, 1.0, "or_greater") var outline_min_distance: float = 40.0:
	set(v):
		outline_min_distance = v
		emit_changed()
## How much further the background must be to count as an edge (1.6 = 60% further).
@export_range(1.05, 5.0, 0.01) var outline_depth_ratio: float = 1.6:
	set(v):
		outline_depth_ratio = v
		emit_changed()


func make_palette_texture() -> ImageTexture:
	var n := clampi(palette.size(), 1, 32)
	var img := Image.create(32, 1, false, Image.FORMAT_RGBA8)
	for i in n:
		img.set_pixel(i, 0, palette[i])
	return ImageTexture.create_from_image(img)
