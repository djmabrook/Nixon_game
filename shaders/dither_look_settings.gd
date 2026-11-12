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


func make_palette_texture() -> ImageTexture:
	var n := clampi(palette.size(), 1, 32)
	var img := Image.create(32, 1, false, Image.FORMAT_RGBA8)
	for i in n:
		img.set_pixel(i, 0, palette[i])
	return ImageTexture.create_from_image(img)
