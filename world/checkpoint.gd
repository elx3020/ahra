@tool
class_name Checkpoint
extends Zone
## Entering makes this the player's respawn point: the zone's floor (bottom face) + 1 m.


func _player_entered(p: Player) -> void:
	p.checkpoint = global_position + Vector3(0, 1.0 - size.y * 0.5, 0)
