extends EnemyState
## Running away while mood is under flee_mood, with the chase's ledge and water rules. Cornered
## (blocked) it holds its ground facing the player and attacks if the player comes close. Out of
## lose_radius it stops to recover; once mood is back above flee_mood + 0.2 -> idle.


func physics(delta: float) -> StringName:
	if e.flail(delta):
		return &""
	if not e.has_target():
		return &"idle"
	if e.swimming():
		e.goal = &"flee"
		return &"swim"
	if not e.is_on_floor():
		e.goal = &"flee"
		return &"jump"
	var d := e.dist_to_target()
	if d > e.lose_radius:
		if e.mood > e.flee_mood + 0.2:
			return &"idle"
		e.anim = &"cower"
		e.hold(delta)
		return &""
	var away := (e.global_position - e.target_pos()).slide(e.up_direction)
	if away.length() < 0.05:
		away = -e.facing
	var next := e.step_toward(e.global_position + away.normalized() * 4.0, delta)
	if next == &"blocked": # cornered
		e.face(e.target_pos())
		e.anim = &"cower"
		return &"attack" if d <= e.attack_range and e.attack_cd <= 0.0 else &""
	if next == &"":
		e.anim = &"flee"
	return next
