extends EnemyState
## CLIMB: walks to the "climbable" wall at Enemy.move_to, climbs it, and hops over the top.
## ponytail: climbs up only; climbing down from an edge comes when a level needs it.

var _n := Vector3.ZERO
var _on := false
var _t := 0.0


func enter(_prev: StringName) -> void:
	_n = (e.global_position - e.move_to).slide(e.up_direction).normalized()
	_on = false
	_t = 0.0
	e.facing = -_n
	e.anim = &"climb"


func physics(delta: float) -> StringName:
	var up := e.up_direction
	_t += delta
	if not _on: # still walking up to the wall
		e.move_planar(-_n, e.walk_speed, delta)
		e.apply_gravity(delta)
		e.move_and_slide()
		if e.is_on_wall():
			_on = true
			_n = e.get_wall_normal()
		return e.goal if _t > 2.0 else &""
	e.velocity = up.slide(_n).normalized() * e.climb_speed * e.mult(&"climb") - _n
	e.move_and_slide()
	if e.is_on_wall():
		_n = e.get_wall_normal()
		return &""
	e.velocity = -_n * 3.0 + up * 5.0 # past the top: hop onto it
	return &"jump"
