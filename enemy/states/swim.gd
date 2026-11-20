extends EnemyState
## SWIM in deep water: moves in 3D toward the target (away from it when fleeing), the body kept
## just under the surface at most, so the head stays out when the target is on land. Low on
## oxygen it goes up to breathe. Leaps onto a bank (Enemy.solve_jump) when the target is on land;
## a SWIM-only enemy (Enemy.water_bound) gives up at the bank instead.

var _breathe := false


func enter(_prev: StringName) -> void:
	_breathe = false
	e.reset_watchdog()
	e.anim = &"swim"


func physics(delta: float) -> StringName:
	if not e.swimming():
		return e.goal
	var patrolling := e.goal == &"patrol" and e.aim_override != null
	if not patrolling and (not e.has_target() or e.dist_to_target() > e.lose_radius):
		e.goal = &"idle"
		return &"idle"
	var up := e.up_direction
	var top := e.water_zone.surface_height(up) - 0.3 # body centre here: head above water
	var here := e.global_position
	var chasing := e.goal == &"pursuit" or e.goal == &"flee"
	var sees := e.sees_target()
	if chasing and not sees and e.seen_ago > e.memory_time:
		return _give_up()
	var aim: Vector3 = e.aim_override if patrolling else (e.target_pos() if sees or not chasing else e.last_seen)
	if patrolling and (aim - here).slide(up).length() < 0.5:
		return e.goal
	if e.goal == &"flee":
		aim = here + (here - aim).slide(up).normalized() * 4.0
	var breath_time := maxf(top - here.dot(up), 0.0) / (e.swim_speed * e.mult(&"swim")) + 0.5
	if e.oxygen < maxf(e.max_oxygen * 0.3, breath_time):
		_breathe = true
	elif e.oxygen > e.max_oxygen * 0.8:
		_breathe = false
	var h := top if _breathe else minf(aim.dot(up), top)
	var want := aim + up * (h - aim.dot(up))
	e.face(want)
	e.velocity = e.velocity.move_toward((want - here).limit_length(1.0) * e.swim_speed * e.mult(&"swim"), 20.0 * delta)
	e.move_and_slide()
	e.anim = &"swim"
	if chasing and e.leashed(e.chase_area, here + (want - here).slide(up).limit_length(1.0) * 0.6 - up * Enemy.HALF_HEIGHT):
		return _give_up() # the chase area's border

	if e.goal == &"pursuit" and sees and not _breathe and e.in_attack_range() and e.attack_cd <= 0.0 \
			and e.oxygen > breath_time + e.attack_windup + e.attack_recover:
		return &"attack"
	var land := aim + up * 0.1 if patrolling else e.target_pos()
	if e.water_at(land) == null: # target (or patrol spot) on land: leap onto the bank ahead
		var dir := (aim - here).slide(up).normalized()
		if dir != Vector3.ZERO and e.test_move(e.global_transform, dir * 0.6):
			if e.water_bound(): # the bank is as far as it goes
				e.give_up = e.give_up_time
				e.cue.emit(&"blocked")
				return &"idle"
			var probe := here + dir * 1.0
			var hit := e.cast(probe + up * (e.jump_height + 0.5), probe - up * 1.0)
			if hit and (hit.position as Vector3).dot(up) > top:
				var v: Variant = e.solve_jump(hit.position + dir * 0.8)
				if v != null:
					e.launch = v
					return &"jump"
			if not e.moving_on(delta): # pressed against a bank too high to leap
				e.give_up = e.give_up_time
				e.cue.emit(&"blocked")
				return &"idle"
	return &""


func _give_up() -> StringName:
	e.give_up = e.give_up_time
	e.cue.emit(&"blocked")
	return &"idle"
