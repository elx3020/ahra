extends EnemyState
## Standing still: stats regenerate, mood recovers. Falls (jump state) when there is no floor.
## Sees the player (Enemy.sees_target: in range and in plain view) -> pursuit, unless a give-up
## timer is running.
## With a patrol area, rests for a random time in patrol_pause, then roams (patrol).

var _pause := 0.0


func enter(_prev: StringName) -> void:
	_pause = e.rng.randf_range(e.patrol_pause.x, e.patrol_pause.y)


func physics(delta: float) -> StringName:
	if e.flail(delta):
		return &""
	if not e.is_on_floor() and not e.swimming() and not e.can(Enemy.Ability.FLY):
		e.goal = &"idle"
		return &"jump"
	if e.give_up <= 0.0 and e.sees_target():
		return &"pursuit"
	_pause -= delta
	if _pause <= 0.0 and is_instance_valid(e.patrol_area):
		return &"patrol"
	e.anim = &"fly" if e.can(Enemy.Ability.FLY) else &"idle"
	e.hold(delta)
	return &""
