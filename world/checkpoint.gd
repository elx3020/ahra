@tool
class_name Checkpoint
extends Zone
## Entering makes this the player's respawn point: 1 m above the middle of the zone's floor
## (the bottom of its shapes).
## ponytail: assumes the zone is not rotated.


func _player_entered(p: Player) -> void:
	var b := bounds()
	var c := b.get_center()
	p.checkpoint = to_global(Vector3(c.x, b.position.y, c.z)) + Vector3.UP
