@tool
class_name GravityZone
extends Zone
## Sets the player's gravity direction on enter (sticky until another zone changes it).

@export var gravity_dir := Vector3.DOWN


func _player_entered(p: Player) -> void:
	p.set_gravity_dir(gravity_dir)
