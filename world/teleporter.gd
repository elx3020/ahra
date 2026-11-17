@tool
class_name Teleporter
extends Zone
## Instantly moves the player to `target`, keeping momentum.
## rotate_momentum: velocity is turned by the target's orientation relative to this pad.

@export var target: Node3D
@export var rotate_momentum := false


func _player_entered(p: Player) -> void:
	var r := Basis.IDENTITY
	if rotate_momentum:
		r = target.global_basis.orthonormalized() * global_basis.orthonormalized().inverse()
	p.teleport.call_deferred(target.global_position, r)
