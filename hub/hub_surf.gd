@tool
extends SurfTerrain
## The crater as a place to surf. The old sand funnel is still the shape (SandVortex), with
## dunes swept onto it and swells that never stop moving:
##
## - Inside the crater, spiral ridges wind down the wall (the same hand as the grooves), and
##   rings breathe OUT of the pit and run up the wall to the rim. Catch one and it carries you
##   up the wall; meet it at the lip and it throws you into the sky over the crater.
## - Outside, counter-spiralled dunes roll down to the beach, and swells run IN from the
##   shore and climb to the ridge. Both trains meet at the crest, which boils.
## - The pit floor and the beach stay calm, so the portal and the shore still read.
##
## SandVortex bakes the static dunes into its mesh and collision; the sand shader draws the
## moving swells (surf/surf_waves.gdshaderinc) from the numbers below.


func _init() -> void:
	gravity = 17.0
	bounds_radius = 990.0
	static_waves = [
		_radial(7.0, 150.0, 0.0, 4.5, 0.3, 75.0, 170.0, 430.0, 494.0),       # spiral ridges down the wall
		_radial(-5.0, 120.0, 0.0, 6.5, 0.45, 515.0, 585.0, 880.0, 975.0),    # counter-spiral dunes outside
		_planar(Vector2(0.6, 0.8), 175.0, 0.0, 4.0, 0.2, 520.0, 610.0, 900.0, 985.0),
	]
	moving_waves = [
		_radial(0.0, 78.0, 15.0, 3.0, 0.6, 48.0, 120.0, 455.0, 500.0),       # the pit exhales
		_radial(1.0, 64.0, 15.0, 1.6, 0.4, 48.0, 120.0, 455.0, 500.0),       # a twist in it, makes sets
		_radial(0.0, 92.0, -12.0, 3.4, 0.55, 505.0, 560.0, 930.0, 985.0),    # the shore breathes in
		_planar(Vector2(-0.8, 0.6), 140.0, 9.0, 1.4, 0.3, 515.0, 600.0, 920.0, 980.0),
	]


static func _radial(arms: float, wavelength: float, speed: float, amp: float, sharp: float,
		in0: float, in1: float, out0: float, out1: float) -> SurfWave:
	var w := SurfWave.new()
	w.kind = SurfWave.Kind.RADIAL
	w.arms = arms
	w.wavelength = wavelength
	w.speed = speed
	w.amplitude = amp
	w.sharpness = sharp
	w.inner_start = in0
	w.inner_full = in1
	w.outer_full = out0
	w.outer_end = out1
	return w


static func _planar(dir: Vector2, wavelength: float, speed: float, amp: float, sharp: float,
		in0 := 0.0, in1 := 0.0, out0 := 0.0, out1 := 0.0) -> SurfWave:
	var w := SurfWave.new()
	w.kind = SurfWave.Kind.PLANAR
	w.direction = dir
	w.wavelength = wavelength
	w.speed = speed
	w.amplitude = amp
	w.sharpness = sharp
	w.inner_start = in0
	w.inner_full = in1
	w.outer_full = out0
	w.outer_end = out1
	return w
