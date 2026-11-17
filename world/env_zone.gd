@tool
class_name EnvZone
extends Zone
## Applies an EnvProfile (mud, ice, wind, water, hot, cold...) while the player is inside.

@export var profile: EnvProfile


func _player_entered(p: Player) -> void:
	p.add_env(profile)
	if profile.water:
		p.water_zone = self


func _player_exited(p: Player) -> void:
	p.remove_env(profile)
	if p.water_zone == self:
		p.water_zone = null


## Height of the box's top face measured along `up` (works for any gravity direction).
## ponytail: assumes the zone is not rotated.
func surface_height(up: Vector3) -> float:
	return global_position.dot(up) + absf(size.dot(up.abs())) * 0.5
