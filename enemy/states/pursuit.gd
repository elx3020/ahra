extends EnemyState
## Chasing the player. Each step reads the ground ahead (Enemy.step_toward): it moves, hands off
## to a move state, or gives up where it can't go on and waits out give_up_time in idle. Trying to
## move without getting anywhere (Enemy.moving_on) counts as can't go on.


func enter(_prev: StringName) -> void:
	e.reset_watchdog()


func physics(delta: float) -> StringName:
	if e.flail(delta):
		return &""
	if not e.has_target() or e.dist_to_target() > e.lose_radius:
		return &"idle"
	if e.mood < e.flee_mood:
		return &"flee"
	if e.swimming():
		e.goal = &"pursuit"
		return &"swim"
	if not e.is_on_floor() and not e.can(Enemy.Ability.FLY):
		e.goal = &"pursuit"
		return &"jump"
	if e.in_attack_range():
		if e.attack_cd <= 0.0:
			return &"attack"
		e.face(e.target_pos())
		e.anim = &"idle"
		e.hold(delta)
		return &""
	var next := e.step_toward(e.target_pos(), delta)
	if next == &"" and not e.moving_on(delta):
		next = &"blocked"
	if next == &"blocked":
		e.give_up = e.give_up_time
		e.cue.emit(&"blocked")
		return &"idle"
	return next
