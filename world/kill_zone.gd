@tool
class_name KillZone
extends Zone
## Instant death on touch: pits, the void, lava, spikes... `cause` picks the death animation.

@export var cause: StringName = &"fall"


func _player_entered(p: Player) -> void:
	p.die(cause)


func _enemy_entered(e: Enemy) -> void:
	e.die(cause)
