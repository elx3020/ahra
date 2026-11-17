@tool
class_name EnvZone
extends Zone
## Applies an EnvProfile (mud, ice, wind, water, hot, cold...) while the player is inside.

@export var profile: EnvProfile


func _player_entered(p: Player) -> void:
	p.envs.append(profile)


func _player_exited(p: Player) -> void:
	p.envs.erase(profile)
