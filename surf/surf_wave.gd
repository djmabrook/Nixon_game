@tool
class_name SurfWave
extends Resource
## One swell on a SurfTerrain. Static swells (speed 0) are baked into the ground mesh and
## its collision; moving ones are added in the vertex shader (surf_waves.gdshaderinc) and
## by SurfTerrain.height() with exactly the same formula, so what you see is what you ride.

enum Kind { PLANAR, RADIAL }

## PLANAR: parallel crests travelling along `direction`.
## RADIAL: rings (or spiral arms, see `arms`) around `center`, travelling outward when
## `speed` is positive.
@export var kind: Kind = Kind.PLANAR
@export var direction := Vector2(1, 0)
@export var center := Vector2.ZERO
## RADIAL only: number of spiral arms. 0 = plain rings.
@export var arms := 0.0
## Crest to crest, metres.
@export var wavelength := 80.0
## Metres per second along `direction` (or outward). 0 = a fixed dune.
@export var speed := 0.0
## Half the crest-to-trough height, metres.
@export var amplitude := 4.0
## 0 = a sine. Toward 1 the crests sharpen into lips and the troughs flatten, like real swell.
@export_range(0.0, 1.0) var sharpness := 0.0
@export var phase := 0.0
@export_group("Window")
## The swell fades in between these distances from `center` and out between the outer pair.
## Leave inner_full at 0 for no inner fade; leave outer_end at 0 for no outer fade.
@export var inner_start := 0.0
@export var inner_full := 0.0
@export var outer_full := 0.0
@export var outer_end := 0.0


func height(xz: Vector2, t: float) -> float:
	var d := xz - center
	var r := d.length()
	var w := 1.0
	if inner_full > 0.0:
		w *= smoothstep(inner_start, inner_full, r)
	if outer_end > 0.0:
		w *= 1.0 - smoothstep(outer_full, outer_end, r)
	if w <= 0.0:
		return 0.0
	var k := TAU / maxf(wavelength, 0.01)
	var ph: float
	if kind == Kind.RADIAL:
		ph = k * r - k * speed * t + arms * atan2(d.y, d.x) + phase
	else:
		ph = k * xz.dot(direction.normalized()) - k * speed * t + phase
	var u := 0.5 + 0.5 * sin(ph)
	var v := pow(u, 1.0 + 3.0 * sharpness)
	return amplitude * (2.0 * v - 1.0) * w


## Packed for the shader: 4 vec4 per wave.
func pack() -> Array[Vector4]:
	var dn := direction.normalized()
	return [
		Vector4(float(kind), center.x, center.y, arms),
		Vector4(wavelength, speed, amplitude, sharpness),
		Vector4(inner_start, inner_full, outer_full, outer_end),
		Vector4(dn.x, dn.y, phase, 0.0),
	]
