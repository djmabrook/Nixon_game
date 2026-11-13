class_name RiderRig
extends RefCounted
## Poses the little man's skeleton from a set of joint positions, one per bone.
##
## Everything procedural about the rider goes through here: the surf stance (built by
## stance() from a few numbers like crouch and carve), the ragdoll (SurfRagdoll moves the
## joints as particles) and the get-up blend between them. apply() turns joint positions
## into bone rotations, keeping each bone's twist from its parent so limbs never corkscrew.
##
## Body coordinates used by stance(): x = his left, y = up, z = his forward (toe side).
## On the board he stands sideways: his left foot at the nose (regular stance).

const N_HIPS := &"Hips"
## Bones whose rotation comes from two directions (up and a side) rather than one.
const FRAME_BONES := {
	&"Hips": [&"Spine02", &"RightUpLeg", &"LeftUpLeg", false],
	&"Spine": [&"neck", &"RightArm", &"LeftArm", false],
	&"Head": [&"head_end", &"headfront", &"Head", true],   # up, forward (side computed)
}
## Bone -> the joint its direction points at.
const AIM := {
	&"Spine02": &"Spine01", &"Spine01": &"Spine", &"neck": &"Head",
	&"LeftShoulder": &"LeftArm", &"LeftArm": &"LeftForeArm", &"LeftForeArm": &"LeftHand",
	&"RightShoulder": &"RightArm", &"RightArm": &"RightForeArm", &"RightForeArm": &"RightHand",
	&"LeftUpLeg": &"LeftLeg", &"LeftLeg": &"LeftFoot", &"LeftFoot": &"LeftToeBase",
	&"RightUpLeg": &"RightLeg", &"RightLeg": &"RightFoot", &"RightFoot": &"RightToeBase",
}
## Height of the board's deck above the ground contact, metres.
const DECK := 0.075
## Body basis in the board's local space (board: -Z nose, +X toe side, +Y up).
const BODY_ON_BOARD := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))

var skel: Skeleton3D
var count := 0
var idx := {}                    # bone name -> index
var parent := PackedInt32Array()
var aim := PackedInt32Array()     # index -> aimed child, or -1
var rest_g: Array[Transform3D] = []
var cur_g: Array[Transform3D] = []
## Rest joint positions in body coordinates, metres, origin on the ground between the feet.
var rest_body := PackedVector3Array()
## Metres per skeleton unit.
var unit := 0.01
var thigh := 0.4
var shin := 0.4
var upper_arm := 0.25
var forearm := 0.25
var hip_height := 0.95


static func find_skeleton(model: Node) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


func _init(skeleton: Skeleton3D) -> void:
	skel = skeleton
	count = skel.get_bone_count()
	parent.resize(count)
	aim.resize(count)
	for i in count:
		idx[StringName(skel.get_bone_name(i))] = i
		parent[i] = skel.get_bone_parent(i)
		rest_g.append(skel.get_bone_global_rest(i))
		cur_g.append(rest_g[i])
		aim[i] = -1
	for k in AIM:
		if idx.has(k) and idx.has(AIM[k]):
			aim[idx[k]] = idx[AIM[k]]
	# Scale from the skeleton to metres (the figure is 1.7 m tall in the world).
	var head_top := _rest(&"head_end").y
	var foot := (_rest(&"LeftToeBase") + _rest(&"RightToeBase")) * 0.5
	var world_scale := skel.global_transform.basis.get_scale().y
	unit = world_scale if world_scale > 0.0 and world_scale < 0.5 else 1.7 / maxf(head_top, 0.001)
	# Body coordinates: x = left (+X in the file), y = up, z = forward (+Z in the file).
	var origin := Vector3(0.0, 0.0, foot.z)
	rest_body.resize(count)
	for i in count:
		rest_body[i] = (rest_g[i].origin - origin) * unit
	hip_height = rest_body[idx[&"Hips"]].y
	thigh = _len(&"LeftUpLeg", &"LeftLeg")
	shin = _len(&"LeftLeg", &"LeftFoot")
	upper_arm = _len(&"LeftArm", &"LeftForeArm")
	forearm = _len(&"LeftForeArm", &"LeftHand")


func _rest(n: StringName) -> Vector3:
	return rest_g[idx[n]].origin


func _len(a: StringName, b: StringName) -> float:
	return rest_body[idx[a]].distance_to(rest_body[idx[b]])


func bone(n: StringName) -> int:
	return idx.get(n, -1)


## Joint positions (world) of the skeleton as it is posed right now.
func current_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	var xf := skel.global_transform
	for i in count:
		out[i] = xf * skel.get_bone_global_pose(i).origin
	return out


## Pose the skeleton so each bone sits at points[i] (world space).
func apply(points: PackedVector3Array) -> void:
	if points.size() != count:
		return
	var inv := skel.global_transform.affine_inverse()
	var p := PackedVector3Array()
	p.resize(count)
	for i in count:
		p[i] = inv * points[i]
	for i in count:
		var par := parent[i]
		var rb := rest_g[i].basis
		var pred: Basis
		if par < 0:
			pred = rb
		else:
			pred = cur_g[par].basis * (rest_g[par].basis.inverse() * rb)
		var basis := pred
		var name := StringName(skel.get_bone_name(i))
		if FRAME_BONES.has(name):
			var f: Array = FRAME_BONES[name]
			var a := bone(f[0])
			var b := bone(f[1])
			var c := bone(f[2])
			if f[3]:
				# Head: up toward head_end, forward toward the face.
				basis = _frame_rot(rest_g[a].origin - rest_g[i].origin, rest_g[b].origin - rest_g[i].origin,
					p[a] - p[i], p[b] - p[i], true) * rb
			else:
				basis = _frame_rot(rest_g[a].origin - rest_g[i].origin, rest_g[b].origin - rest_g[c].origin,
					p[a] - p[i], p[b] - p[c], false) * rb
		elif aim[i] >= 0:
			var ch := aim[i]
			var want := p[ch] - p[i]
			var had := pred * (rb.inverse() * (rest_g[ch].origin - rest_g[i].origin))
			basis = _arc(had, want) * pred
		basis = basis.orthonormalized().scaled(rb.get_scale())
		cur_g[i] = Transform3D(basis, p[i])
		skel.set_bone_global_pose(i, cur_g[i])


static func _arc(from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 1e-10 or to.length_squared() < 1e-10:
		return Basis()
	var a := from.normalized()
	var b := to.normalized()
	var d := a.dot(b)
	if d > 0.99999:
		return Basis()
	if d < -0.99999:
		var axis := a.cross(Vector3.UP)
		if axis.length_squared() < 1e-6:
			axis = a.cross(Vector3.RIGHT)
		return Basis(axis.normalized(), PI)
	return Basis(Quaternion(a, b))


## Rotation taking a rest frame (up, side) onto a current one. With `fwd_mode` the second
## vector is a forward direction instead of a side.
static func _frame_rot(up0: Vector3, s0: Vector3, up1: Vector3, s1: Vector3, fwd_mode: bool) -> Basis:
	var f0 := _frame(up0, s0, fwd_mode)
	var f1 := _frame(up1, s1, fwd_mode)
	return f1 * f0.transposed()


static func _frame(up: Vector3, other: Vector3, fwd_mode: bool) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	var o := other - y * other.dot(y)
	if o.length_squared() < 1e-8:
		o = y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	o = o.normalized()
	if fwd_mode:
		var x := y.cross(o)
		return Basis(x, y, o)
	var z := o.cross(y)
	return Basis(o, y, z)


## Two-bone IK: from root `a` reaching `t` with segment lengths l1, l2; the middle joint bends
## toward `pole`. Returns [middle, end].
static func ik2(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var to := t - a
	var d := clampf(to.length(), 0.001, (l1 + l2) * 0.999)
	var dir := to.normalized() if to.length_squared() > 1e-8 else Vector3.DOWN
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var mid := a + dir * x + side * h
	return [mid, a + dir * d]


## The surf stance, in body coordinates (metres). The rider's look:
##  crouch 0..1   how low he rides (tuck, landing squash, charging a pop)
##  shift -1..1   weight toward the nose (+) or the tail (-)
##  carve -1..1   which way he's leaning into a turn (arms lift on that side)
##  air 0..1      airborne: arms open up, he floats
##  grab 0..1     in the air with a tuck: front hand reaches down to the toe edge
##  look 0..1     how far his head turns toward the nose (where he's going)
##  t             seconds, for small living motion
func stance(crouch: float, shift: float, carve: float, air: float, grab: float, look: float, t: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		out[i] = rest_body[i]
	var ankle := rest_body[bone(&"LeftFoot")].y + DECK
	var c := clampf(crouch, 0.0, 1.0)
	var breathe := sin(t * 1.7) * 0.012 * (1.0 - air)
	var stance_half := 0.29
	# Feet on the deck, across the board, front foot angled to the nose.
	var lf := Vector3(stance_half, ankle, 0.03)
	var rf := Vector3(-stance_half, ankle, 0.03)
	# Pelvis.
	var hips := Vector3(0.07 * shift, hip_height * (1.0 - 0.36 * c) + breathe, -0.09 * c)
	var pelvis_yaw := Basis(Vector3.UP, 0.22 + 0.1 * shift)
	var r_hips := rest_body[bone(&"Hips")]
	_put(out, &"Hips", hips)
	for leg in [[&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase", lf, 1.0],
			[&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase", rf, -1.0]]:
		var hip: Vector3 = hips + pelvis_yaw * (rest_body[bone(leg[0])] - r_hips)
		var foot: Vector3 = leg[4]
		var pole := Vector3(0.28 * leg[5], 0.0, 1.0)   # knees over the toes, a little bowed out
		var k := ik2(hip, foot, thigh, shin, pole)
		_put(out, leg[0], hip)
		_put(out, leg[1], k[0])
		_put(out, leg[2], k[1])
		var toe_off: Vector3 = rest_body[bone(leg[3])] - rest_body[bone(leg[2])]
		_put(out, leg[3], k[1] + Basis(Vector3.UP, 0.25 * leg[5]) * toe_off)
	# Torso: turned toward the nose, bent forward as he crouches, tipped by weight shift.
	var yaw := 0.5 + 0.15 * look
	var pitch := 0.14 + 0.5 * c - 0.1 * air
	var roll := -0.14 * shift
	var r_torso := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	var low := Basis().slerp(r_torso, 0.4)
	_put(out, &"Spine02", hips + low * (rest_body[bone(&"Spine02")] - r_hips))
	for n in [&"Spine01", &"Spine", &"neck", &"Head", &"head_end", &"headfront",
			&"LeftShoulder", &"LeftArm", &"RightShoulder", &"RightArm"]:
		_put(out, n, hips + r_torso * (rest_body[bone(n)] - r_hips))
	# Head: looks ahead over the front shoulder, level with the horizon.
	var head := out[bone(&"Head")]
	var r_head := r_torso * Basis(Vector3.UP, 0.55 * look) * Basis(Vector3.RIGHT, -pitch * 0.75)
	for n in [&"head_end", &"headfront"]:
		_put(out, n, head + r_head * (rest_body[bone(n)] - rest_body[bone(&"Head")]))
	# Arms: out for balance, the turning side lifts, open wide in the air.
	var reach := (upper_arm + forearm) * 0.93
	var flail := sin(t * 9.0) * 0.18 * air
	var lc := maxf(-carve, 0.0)
	var rc := maxf(carve, 0.0)
	var front_dir := Vector3(0.8, -0.32 + 0.55 * lc + 0.7 * air + flail, 0.32).normalized()
	var back_dir := Vector3(-0.85, -0.42 + 0.55 * rc + 0.6 * air - flail, 0.12).normalized()
	var ls := out[bone(&"LeftArm")]
	var rs := out[bone(&"RightArm")]
	var lh := ls + front_dir * reach
	var rh := rs + back_dir * reach
	# Grab: front hand to the toe edge between the feet.
	if grab > 0.0:
		lh = lh.lerp(Vector3(0.06, DECK + 0.05, 0.24), clampf(grab, 0.0, 1.0))
	var la := ik2(ls, lh, upper_arm, forearm, Vector3(0.0, -1.0, -0.5))
	var ra := ik2(rs, rh, upper_arm, forearm, Vector3(0.0, -1.0, -0.6))
	_put(out, &"LeftForeArm", la[0])
	_put(out, &"LeftHand", la[1])
	_put(out, &"RightForeArm", ra[0])
	_put(out, &"RightHand", ra[1])
	return out


func _put(arr: PackedVector3Array, n: StringName, v: Vector3) -> void:
	var i := bone(n)
	if i >= 0:
		arr[i] = v


## Body coordinates -> world, for a board standing at `board` (its global transform).
static func body_to_world(body: PackedVector3Array, board: Transform3D) -> PackedVector3Array:
	var xf := board * Transform3D(BODY_ON_BOARD, Vector3.ZERO)
	var out := PackedVector3Array()
	out.resize(body.size())
	for i in body.size():
		out[i] = xf * body[i]
	return out
