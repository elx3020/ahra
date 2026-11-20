extends EnemyState
## Cinematic control: ignores the AI, the player, damage and ledges. Enemy.start_puppet(at) walks
## it to a mark (emits puppet_arrived there); end_puppet() hands back to the AI.


func physics(delta: float) -> StringName:
	var dir := Vector3.ZERO
	if e.puppet_target != null:
		var to: Vector3 = (e.puppet_target - e.global_position).slide(e.up_direction)
		if to.length() < 0.3:
			e.puppet_target = null
			e.puppet_arrived.emit()
		else:
			dir = to.normalized()
	e.anim = &"walk" if dir != Vector3.ZERO else &"idle"
	e.move_planar(dir, e.walk_speed, delta)
	e.apply_gravity(delta)
	e.move_and_slide()
	return &""
