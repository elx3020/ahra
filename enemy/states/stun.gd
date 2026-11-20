extends EnemyState
## The player's timed opening: flyers fall to the ground, ground enemies rest in place. Hits land
## (damage, knockback) without ending or restarting it. Ends with full stamina.
## Enter with Enemy.stun(seconds), or set stun_for and return &"stun" from a state.

var _t := 0.0


func enter(_prev: StringName) -> void:
	_t = e.stun_for
	e.anim = &"stun"
	e.cue.emit(&"stun")


func physics(delta: float) -> StringName:
	e.hold(delta, true)
	_t -= delta
	if _t > 0.0:
		return &""
	e.stamina = e.max_stamina
	return &"idle"
