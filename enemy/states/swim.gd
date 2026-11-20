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
	if not e.has_target() or e.dist_to_target() > e.lose_radius:
		e.goal = &"idle"
		return &"idle"
	var up := e.up_direction
	var top := e.water_zone.surface_height(up) - 0.3 # body centre here: head above water
	var here := e.global_position
	var aim := e.target_pos()
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

	if e.goal == &"pursuit" and not _breathe and e.in_attack_range() and e.attack_cd <= 0.0 \
			and e.oxygen > breath_time + e.attack_windup + e.attack_recover:
		return &"attack"
	if e.water_at(e.target_pos()) == null: # target on land: leap onto the bank ahead
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
