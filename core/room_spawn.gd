@tool
class_name RoomSpawn
extends Marker3D
## Where the player appears when entering a room. Its -Z axis is the facing.
## Name it after where the player comes from (e.g. "from_hub", or a room id in the hub).

## Used when Game.go_to() is called without a spawn name.
@export var is_default := false
