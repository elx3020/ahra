@tool
class_name NpcTalk
extends Interactable
## The talk zone of an Npc (its parent): pressing interact inside it starts the NPC's first
## available KEY interaction. The shape is edited like any zone's (Shape Tools).


func can_interact() -> bool:
	return false
