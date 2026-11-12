@tool
class_name StrayInterest
extends Marker3D
## Something worth looking at. Drop one into a room (on a landmark, a door, a hidden
## object) and the Stray will run ahead and point at it when the little man comes near.
##
## The Stray points with its tip, clicks, and waits until the player turns the camera
## toward the thing, then hops with pleasure and moves on.

## Fired when the Stray starts pointing here.
signal pointed
## Fired when the player looked where the Stray pointed.
signal acknowledged

## The Stray notices this when the little man is within this many meters.
@export var notice_radius := 40.0
## Higher wins when several things are in range.
@export var priority := 1.0
## Point only once per visit to the room.
@export var once := true
## Seconds before it can point here again (when `once` is off).
@export var cooldown := 30.0
## Off = the Stray ignores it (switch it on when a puzzle step makes it matter).
@export var enabled := true

var _last_time := -INF
var _done := false


func _ready() -> void:
	add_to_group(&"stray_interest")
	if Engine.is_editor_hint():
		gizmo_extents = 2.0


func can_notice(from: Vector3, now: float) -> bool:
	if not enabled or _done:
		return false
	if now - _last_time < cooldown:
		return false
	return global_position.distance_to(from) <= notice_radius


func mark_pointed(now: float) -> void:
	_last_time = now
	if once:
		_done = true
	pointed.emit()


## Let the Stray point here again (for example after a rule twist moves it).
func reset() -> void:
	_done = false
	_last_time = -INF
