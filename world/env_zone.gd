@tool
class_name EnvZone
extends Zone
## Applies an EnvProfile (mud, ice, wind, water, hot, cold...) while the player or an enemy is inside.

@export var profile: EnvProfile


func _player_entered(p: Player) -> void:
	p.add_env(profile)
	if profile.water:
		p.water_zone = self


func _player_exited(p: Player) -> void:
	p.remove_env(profile)
	if p.water_zone == self:
		p.water_zone = null


func _enemy_entered(e: Enemy) -> void:
	e.add_env(profile)
	if profile.water:
		e.water_zone = self


func _enemy_exited(e: Enemy) -> void:
	e.remove_env(profile)
	if e.water_zone == self:
		e.water_zone = null


## Height of the zone's top measured along `up` (works for any gravity direction).
## ponytail: the top of the shapes' bounding box, so a water sphere's surface is flat at its
## highest point; sample the shape under the player if round water ever matters.
func surface_height(up: Vector3) -> float:
	var b := bounds()
	var top := -INF
	for i in 8:
		top = maxf(top, to_global(b.get_endpoint(i)).dot(up))
	return top
