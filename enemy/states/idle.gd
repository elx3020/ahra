extends EnemyState
## Standing still: stats regenerate, mood recovers. Falls (jump state) when there is no floor.
## Sees the player inside sight_radius -> pursuit, unless a give-up timer is running.


func physics(delta: float) -> StringName:
	if e.flail(delta):
		return &""
	if not e.is_on_floor() and not e.swimming():
		e.goal = &"idle"
		return &"jump"
	if e.give_up <= 0.0 and e.has_target() and e.dist_to_target() <= e.sight_radius:
		return &"pursuit"
	e.anim = &"idle"
	e.hold(delta)
	return &""
