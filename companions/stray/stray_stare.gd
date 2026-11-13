@tool
class_name StrayStare
extends Marker3D
## Marks something that looks: a television with eyes, the Watcher's eyes.
## Put it where the eyes are and keep `awake` in step with the eyes.
##
## Awake, it scares the Stray: it hides behind the little man's legs, turned edge-on
## so it nearly vanishes (or, with EDGE_ON, just turns thin and keeps following).
## Asleep (the region is mended, the eyes closed), the Stray curls up beside it
## when the little man lingers nearby.

enum Reaction {
	HIDE_BEHIND,  ## Tuck behind his legs, trembling, peeking out now and then.
	EDGE_ON,  ## Keep following but turn edge-on to it. For huge far stares like the Watcher.
}

## Fired when `awake` changes.
signal awake_changed(is_awake: bool)

@export var awake := true:
	set(value):
		if awake == value:
			return
		awake = value
		awake_changed.emit(value)
@export var reaction := Reaction.HIDE_BEHIND
## While awake: the Stray reacts when the little man is this close (meters).
@export var fear_radius := 30.0
## While asleep: the Stray curls up here when the little man lingers this close.
@export var rest_radius := 16.0
## Where the Stray lies down, relative to this marker. Zero = beside it, on the
## little man's side.
@export var curl_offset := Vector3.ZERO


## When the parent is a WatchingSet, `awake` follows its eyes (open or drooping = awake).
@export var follow_watching_set := true

var _set: WatchingSet


func _ready() -> void:
	add_to_group(&"stray_stare")
	if Engine.is_editor_hint():
		gizmo_extents = 1.0
		return
	_set = get_parent() as WatchingSet
	set_process(_set != null and follow_watching_set)


func _process(_delta: float) -> void:
	if _set:
		awake = _set.mode != WatchingSet.Mode.CLOSED


## The spot the Stray curls up on, for a little man standing at `player_pos`.
func curl_spot(player_pos: Vector3) -> Vector3:
	if curl_offset != Vector3.ZERO:
		return global_position + global_basis * curl_offset
	var away := player_pos - global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = global_basis.z
	return global_position + away.normalized() * 1.6
