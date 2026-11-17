@tool
class_name CutsceneTrigger
extends Zone
## Minimal cinematic: puppets the player to `walk_to`, holds, then gives control back.
## ponytail: no timeout if walk_to is unreachable; add one when real cutscenes exist.

@export var walk_to: Node3D
@export var hold := 1.0

var _busy := false


func _player_entered(p: Player) -> void:
	if _busy:
		return
	_busy = true
	p.start_puppet(walk_to.global_position)
	await p.puppet_arrived
	await get_tree().create_timer(hold).timeout
	p.end_puppet()
	_busy = false
