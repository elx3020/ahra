@tool
class_name Interactable
extends Zone
## Press interact inside the zone. Player plays the interact anim for `duration`.

signal used(player: Player)

@export var duration := 0.6


func _player_entered(p: Player) -> void:
	p.interactable = self


func _player_exited(p: Player) -> void:
	if p.interactable == self:
		p.interactable = null


func interact(p: Player) -> float:
	used.emit(p)
	return duration
