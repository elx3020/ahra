extends EnemyState
## Standing still: stats regenerate, mood recovers. Falls (jump state) when there is no floor.


func physics(delta: float) -> StringName:
	if e.flail(delta):
		return &""
	if not e.is_on_floor():
		e.goal = &"idle"
		return &"jump"
	e.anim = &"idle"
	e.hold(delta)
	return &""
