@tool
class_name SceneDoor
extends Zone
## Walk in to go to another area; the player appears at the node named `spawn` there.

@export_file("*.tscn") var scene: String
@export var spawn: StringName


func _player_entered(_p: Player) -> void:
	World.spawn = spawn
	get_tree().change_scene_to_file.call_deferred(scene)
