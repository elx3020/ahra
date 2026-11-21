@tool
class_name NpcTalk
extends Interactable
## The talk zone of an Npc (its parent): pressing interact inside it starts the NPC's first
## available KEY interaction. The shape is edited like any zone's (Shape Tools).


func npc() -> Npc:
	return get_parent() as Npc


## The player only answers this zone while the NPC has something to say (Npc.can_talk).
func can_interact() -> bool:
	return npc() != null and npc().can_talk()


## Starts the talk deferred, so the player's interact state finishes entering (it turns the player
## toward the zone) before the NPC puts the player in its puppet state. No interact animation.
func interact(_p: Player) -> float:
	npc().start_talk.call_deferred()
	return 0.0
