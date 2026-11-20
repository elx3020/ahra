extends EnemyState
## Knocked back by a hit (Enemy.hit sets the velocity). No ledge check: a push can send it into a
## pit or deep water. Short, then back to the chase (idle without a target).

var _t := 0.0


func enter(_prev: StringName) -> void:
	e.anim = &"hurt"
	_t = e.hurt_time


func physics(delta: float) -> StringName:
	e.velocity = e.planar().move_toward(Vector3.ZERO, 8.0 * delta) + e.up_direction * e.vspeed()
	e.apply_gravity(delta)
	e.move_and_slide()
	_t -= delta
	if _t > 0.0:
		return &""
	if not e.is_on_floor() and not e.can(Enemy.Ability.FLY):
		e.goal = &"pursuit"
		return &"jump"
	return &"pursuit" if e.has_target() else &"idle"
