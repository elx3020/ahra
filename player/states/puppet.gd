extends PlayerState
## Cinematic control: ignores player input. Scripts drive it via
## Player.start_puppet(target) / end_puppet(); emits puppet_arrived at the target.


func physics(delta: float) -> StringName:
	var dir := Vector3.ZERO
	if p.puppet_target != null:
		var to: Vector3 = (p.puppet_target - p.global_position).slide(p.up_direction)
		if to.length() < 0.3:
			p.puppet_target = null
			p.puppet_arrived.emit()
		else:
			dir = to.normalized()
	p.anim = &"walk" if dir != Vector3.ZERO else &"puppet"
	p.move_ground(dir, p.walk_speed, delta)
	p.apply_gravity(delta)
	p.slide()
	return &""
