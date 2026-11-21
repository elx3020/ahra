@tool
class_name GravityZone
extends Zone
## Sets the gravity direction of whatever enters (sticky until another zone changes it): the
## player, enemies, NPCs and weights.

@export var gravity_dir := Vector3.DOWN


func _player_entered(p: Player) -> void:
	p.set_gravity_dir(gravity_dir)


func _enemy_entered(e: Enemy) -> void:
	e.set_gravity_dir(gravity_dir)


func _npc_entered(n: Node3D) -> void:
	n.set_gravity_dir(gravity_dir)


func _weight_entered(w: WeightBody) -> void:
	w.set_gravity_dir(gravity_dir)
