extends RefCounted
## Finds the places the story needs inside whatever hub is loaded, so the sequences
## work with the placeholder hub, the spiral hub, and whatever it becomes.
##
## A hub can name places outright with Marker3D nodes in the group "story_anchor":
##   shore_wake   where he washes up, on the tideline (its -Z faces inland)
##   first_tv     where the first television sits (optional)
##   margin_exit  a far point along the tideline he walks toward at dawn
##   sun          where the sun stands at dawn (its position, or a far point in its direction)
## Anything missing is worked out from the hub's default spawn, its "Vortex" (the pit)
## and its "Sea" node, by walking out from the pit until the sand meets the water.

const ANCHOR_GROUP := &"story_anchor"
const WORLD_MASK := 1

var room: Node3D
var pit := Vector3.ZERO
var sea_level := 0.0
## Where he lies when he washes up, standing on the sand.
var wake := Vector3.ZERO
## Unit vector pointing inland (toward the pit) at the wake spot, flat.
var inland := Vector3.FORWARD
## Unit vector along the tideline (inland × up), flat. He walks this way at dawn.
var along := Vector3.RIGHT
## How high the shore sand is around the wake spot.
var shore_height := 0.0


func _init(r: Node3D) -> void:
	room = r


## Call once the room's bodies are in the physics space (after one physics frame).
func survey() -> void:
	var vortex := room.get_node_or_null(^"Vortex") as Node3D
	pit = vortex.global_position if vortex else room.global_position
	var sea := room.get_node_or_null(^"Sea") as Node3D
	sea_level = sea.global_position.y if sea else room.global_position.y - 1.0

	var a_wake := anchor(&"shore_wake")
	if a_wake:
		wake = ground(a_wake.global_position)
		inland = _flat(-a_wake.global_basis.z)
	else:
		_find_tideline()
	along = inland.cross(Vector3.UP).normalized()
	var a_margin := anchor(&"margin_exit")
	if a_margin:
		var to := _flat(a_margin.global_position - wake)
		if to != Vector3.ZERO:
			along = to
	shore_height = wake.y


## A named anchor in the room, or null.
func anchor(anchor_name: StringName) -> Node3D:
	for n in room.get_tree().get_nodes_in_group(ANCHOR_GROUP):
		if n is Node3D and n.name == anchor_name and room.is_ancestor_of(n):
			return n
	return null


## The sand under a point (a straight-down ray on the world layer). Falls back to the point.
## `probe_up` is how far above `p` the ray starts: keep it small near the shore so a tall
## invisible wall's top is never mistaken for sand.
func ground(p: Vector3, probe_up := 400.0) -> Vector3:
	var hit := ground_hit(p, probe_up)
	return hit.position if not hit.is_empty() else p


## The sand near the shore: probes from just above the wake spot's height.
func sand(p: Vector3) -> Vector3:
	return ground(Vector3(p.x, wake.y, p.z), 6.0)


func ground_hit(p: Vector3, probe_up := 400.0) -> Dictionary:
	var space := room.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * probe_up, p + Vector3.DOWN * 600.0, WORLD_MASK)
	q.hit_back_faces = false
	var hit := space.intersect_ray(q)
	# Ignore thin vertical walls (a shore wall's top): we want sand.
	if not hit.is_empty() and (hit.normal as Vector3).y < 0.5:
		q.from = hit.position + Vector3.DOWN * 0.5
		hit = space.intersect_ray(q)
	return hit


## A point on the shore: `out` metres seaward of the wake spot (negative goes inland)
## and `side` metres along the tideline, standing on the sand.
func shore_point(side: float, out := 0.0) -> Vector3:
	return sand(wake + along * side - inland * out)


## Walk out from the pit through the default spawn until the sand dips under the sea or
## a wall stops us; the wake spot sits a few steps inland of that.
func _find_tideline() -> void:
	var start: Vector3 = room.global_position
	var r := room as Room
	if r:
		var sp := r.get_spawn()
		if sp:
			start = sp.global_position
	var out := _flat(start - pit)
	if out == Vector3.ZERO:
		out = Vector3.BACK
	inland = -out
	var space := room.get_world_3d().direct_space_state
	var last := ground(start)
	var step := 2.0
	for i in 400:
		var probe := ground_hit(last + out * step)
		if probe.is_empty():
			break   # the ground just ends (a small or placeholder hub)
		var nxt: Vector3 = probe.position
		# A wall (the hub's invisible shore wall, a cliff) ends the walk.
		var q := PhysicsRayQueryParameters3D.create(last + Vector3.UP * 1.0, nxt + Vector3.UP * 1.0, WORLD_MASK)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() or nxt.y < sea_level + 0.35 or absf(nxt.y - last.y) > 3.0:
			break
		last = nxt
	wake = ground(last - out * 4.0)


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO
