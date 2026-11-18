extends GameArea
## Mechanics test level: one bay per mechanic. Camera, HUD, keys and warps live in GameArea.

@onready var door: CSGBox3D = $Bays/Interact/Door


func _on_lever_used(_p: Player) -> void:
	door.visible = not door.visible
	door.use_collision = door.visible
