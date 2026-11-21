@tool
class_name Interactable
extends Zone
## Press interact inside the zone. Player plays the interact anim for `duration`.
## The player keeps every zone it stands in (`Player.interactables`) and answers the nearest
## one whose can_interact() is true, so overlapping zones don't fight over the press.

signal used(player: Player)

@export var duration := 0.6


## False while the zone has nothing to do (an NPC with nothing to say): the player passes it over.
func can_interact() -> bool:
	return true


func _player_entered(p: Player) -> void:
	if self not in p.interactables:
		p.interactables.append(self)


func _player_exited(p: Player) -> void:
	p.interactables.erase(self)
	if p.interactable == self:
		p.interactable = null


func interact(p: Player) -> float:
	used.emit(p)
	return duration
