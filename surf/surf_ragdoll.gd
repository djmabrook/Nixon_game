class_name SurfRagdoll
extends RefCounted
## The wipeout. Every joint of the little man becomes a particle (Verlet), held together by
## his bone lengths, braced so the pelvis, chest and head stay solid while the spine, neck,
## shoulders, hips, elbows and knees give. It tumbles on the live SurfTerrain, swells and all,
## and RiderRig.apply() turns the particles back into bone rotations every frame.

const SUBSTEPS := 3
const ITERATIONS := 8

## Rigid groups: every pair inside a group keeps its distance.
const RIGID := [
	[&"Hips", &"LeftUpLeg", &"RightUpLeg", &"Spine02"],
	[&"Spine01", &"Spine", &"neck", &"LeftShoulder", &"RightShoulder", &"LeftArm", &"RightArm"],
	[&"neck", &"Head", &"head_end", &"headfront"],
	[&"LeftLeg", &"LeftFoot", &"LeftToeBase"],
	[&"RightLeg", &"RightFoot", &"RightToeBase"],
]
## Soft links [a, b, stiffness]: the spine and neck bend but spring back a little.
const SOFT := [
	[&"LeftUpLeg", &"LeftArm", 0.08], [&"RightUpLeg", &"RightArm", 0.08],
	[&"LeftUpLeg", &"RightArm", 0.05], [&"RightUpLeg", &"LeftArm", 0.05],
	[&"Spine", &"Head", 0.25], [&"Hips", &"neck", 0.06],
]
## Joint limits as minimum distances [a, b, fraction of rest]: knees and elbows can't fold
## flat, the head can't fold into the hips, legs can't cross through each other.
const MIN_DIST := [
	[&"LeftUpLeg", &"LeftFoot", 0.45], [&"RightUpLeg", &"RightFoot", 0.45],
	[&"LeftArm", &"LeftHand", 0.35], [&"RightArm", &"RightHand", 0.35],
	[&"Hips", &"Head", 0.7], [&"Hips", &"head_end", 0.7],
	[&"LeftFoot", &"RightFoot", 0.25], [&"LeftLeg", &"RightLeg", 0.3],
	[&"LeftHand", &"Hips", 0.25], [&"RightHand", &"Hips", 0.25],
]
## Particle radius by joint, metres (how far it sits off the ground).
const RADIUS := {&"Hips": 0.13, &"Spine01": 0.13, &"Spine": 0.14, &"Head": 0.12, &"head_end": 0.08,
	&"LeftUpLeg": 0.09, &"RightUpLeg": 0.09, &"Spine02": 0.13}

var rig: RiderRig
var terrain: SurfTerrain
var pos := PackedVector3Array()
var prev := PackedVector3Array()
var radius := PackedFloat32Array()
var gravity := 17.0
## Sliding friction on sand (Coulomb coefficient: 0.5 slows a slide by half a g).
var friction := 0.55
var bounce := 0.18
## Total seconds simulated, and seconds spent nearly still.
var age := 0.0
var still := 0.0
## Biggest impact this frame (m/s), for sound and shake.
var last_impact := 0.0

var _links: Array = []   # [a, b, rest, stiffness, min_only]


func _init(r: RiderRig, t: SurfTerrain) -> void:
	rig = r
	terrain = t
	gravity = t.gravity if t else 17.0


## Start from the current pose (world joints) moving at `vel`, tumbling around `spin` (rad/s).
func start(points: PackedVector3Array, vel: Vector3, spin: Vector3, dt: float) -> void:
	pos = points.duplicate()
	prev.resize(pos.size())
	radius.resize(pos.size())
	var com := Vector3.ZERO
	for p in pos:
		com += p
	com /= maxf(pos.size(), 1)
	var h := dt / SUBSTEPS   # Verlet velocity is per substep
	for i in pos.size():
		var v := vel + spin.cross(pos[i] - com)
		prev[i] = pos[i] - v * h
		radius[i] = RADIUS.get(StringName(rig.skel.get_bone_name(i)), 0.06)
	_links.clear()
	for i in pos.size():
		var par := rig.parent[i]
		if par >= 0:
			_link(par, i, 1.0, false)
	for g in RIGID:
		for a in g.size():
			for b in range(a + 1, g.size()):
				_link(rig.bone(g[a]), rig.bone(g[b]), 1.0, false)
	for s in SOFT:
		_link(rig.bone(s[0]), rig.bone(s[1]), s[2], false)
	for m in MIN_DIST:
		var a := rig.bone(m[0])
		var b := rig.bone(m[1])
		if a >= 0 and b >= 0:
			_links.append([a, b, pos[a].distance_to(pos[b]) * m[2], 1.0, true])
	age = 0.0
	still = 0.0


func _link(a: int, b: int, stiff: float, min_only: bool) -> void:
	if a < 0 or b < 0 or a == b:
		return
	_links.append([a, b, pos[a].distance_to(pos[b]), stiff, min_only])


func step(delta: float) -> void:
	last_impact = 0.0
	var h := delta / SUBSTEPS
	for _s in SUBSTEPS:
		_integrate(h)
		for _i in ITERATIONS:
			_solve_links()
		_collide(h)
	age += delta
	if center_velocity(delta).length() < 1.2:
		still += delta
	else:
		still = 0.0


func _integrate(h: float) -> void:
	var g := Vector3(0, -gravity, 0) * h * h
	for i in pos.size():
		var p := pos[i]
		var v := (p - prev[i]) * 0.998
		prev[i] = p
		pos[i] = p + v + g


func _solve_links() -> void:
	for l in _links:
		var a: int = l[0]
		var b: int = l[1]
		var d := pos[b] - pos[a]
		var len := d.length()
		if len < 1e-6:
			continue
		var rest: float = l[2]
		if l[4] and len >= rest:
			continue
		var diff := (len - rest) / len * 0.5 * float(l[3])
		pos[a] += d * diff
		pos[b] -= d * diff


func _collide(h: float) -> void:
	if terrain == null:
		return
	for i in pos.size():
		var p := pos[i]
		var xz := Vector2(p.x, p.z)
		var gy := terrain.height(xz) + radius[i]
		if p.y >= gy:
			continue
		var n := terrain.normal(xz)
		var v := p - prev[i]
		p.y = gy
		var vn := n * v.dot(n)
		var vt := v - vn
		var into := -v.dot(n) / h
		last_impact = maxf(last_impact, into)
		# Sand: Coulomb friction (decelerates sliding by friction * g), a little bounce on hard hits.
		var slow := friction * gravity * h * h
		vt = vt - vt.normalized() * minf(vt.length(), slow) if vt.length_squared() > 1e-12 else vt
		var out_v := vt - vn * (bounce if into > 3.0 else 0.0)
		pos[i] = p
		prev[i] = p - out_v


## Where the body is (the pelvis).
func center() -> Vector3:
	return pos[rig.bone(&"Hips")] if not pos.is_empty() else Vector3.ZERO


func center_velocity(delta: float) -> Vector3:
	var i := rig.bone(&"Hips")
	if pos.is_empty() or i < 0:
		return Vector3.ZERO
	return (pos[i] - prev[i]) / maxf(delta / SUBSTEPS, 1e-4)


## Facing of the body on the ground (pelvis to chest, flattened), for getting up.
func lying_direction() -> Vector3:
	var d := pos[rig.bone(&"neck")] - pos[rig.bone(&"Hips")]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-4 else Vector3.FORWARD
