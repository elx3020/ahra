extends PlayerState
## Stuck to a "climbable" surface. Up/down climbs, left/right shimmies.
## Jump = wall jump, reaching the top = ledge hop, down onto floor = let go.

var _n := Vector3.ZERO


func enter(_prev: StringName) -> void:
	p.anim = &"climb"
	_n = p.get_wall_normal()
	p.velocity = Vector3.ZERO
	p.facing = -_n


func physics(_delta: float) -> StringName:
	var up := p.up_direction.slide(_n).normalized()
	var side := _n.cross(up)
	if side.dot(p.cam_basis().x) < 0.0:
		side = -side
	var i := p.raw_input()
	p.velocity = (up * -i.y + side * i.x) * p.climb_speed * p.mult(&"climb") - _n * 2.0
	p.move_and_slide()

	if p.jump_buffer > 0.0:
		p.jump_buffer = 0.0
		p.velocity = _n * 6.0 + p.up_direction * p.jump_velocity() * 0.9
		p.facing = _n
		return &"jump"
	if not p.is_on_wall():
		if i.y < 0.0: # climbed past the top
			p.velocity = -_n * 3.0 + p.up_direction * 7.0
		return &"jump"
	if p.is_on_floor() and i.y > 0.0:
		return &"idle"
	_n = p.get_wall_normal()
	return &""
