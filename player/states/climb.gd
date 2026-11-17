extends PlayerState
## Stuck to a "climbable" surface. Up/down climbs, left/right shimmies.
## Slippery walls (traction stat < 100%) slide you down; wind drifts you along the wall.
## Jump = wall jump, climbing past the top = ledge hop, shimmied/blown off a side = fall.

var _n := Vector3.ZERO


func enter(_prev: StringName) -> void:
	p.anim = &"climb"
	_n = p.get_wall_normal()
	p.velocity = Vector3.ZERO
	p.facing = -_n


func physics(delta: float) -> StringName:
	var up := p.up_direction.slide(_n).normalized()
	var side := _n.cross(up)
	if side.dot(p.cam_basis().x) < 0.0:
		side = -side
	var i := p.raw_input()
	p.anim = &"climb" if i != Vector2.ZERO else &"hang"
	var slip := p.climb_slip * maxf(0.0, 1.0 - p.mult(&"traction"))
	var target := (up * -i.y + side * i.x) * p.climb_speed * p.mult(&"climb")
	target += p.env.wind.slide(_n) * p.wind_response_ground - up * slip
	p.velocity = p.velocity.slide(_n).move_toward(target, p.climb_accel * delta) - _n * 2.0
	p.move_and_slide()

	if p.jump_buffer > 0.0:
		p.jump_buffer = 0.0
		p.velocity = _n * 6.0 + p.up_direction * p.jump_velocity() * 0.9
		p.facing = _n
		return &"jump"
	if not p.is_on_wall():
		if i.y < 0.0 and _wall_below(): # went over the top
			p.velocity = -_n * 3.0 + p.up_direction * 7.0
		return &"jump"
	if p.is_on_floor() and (i.y > 0.0 or i == Vector2.ZERO): # slid or climbed down to the floor
		return &"idle"
	_n = p.get_wall_normal()
	return &""


## Wall still in front at foot height => we passed the top edge, not a side edge.
func _wall_below() -> bool:
	return p.test_move(p.global_transform.translated(-p.up_direction * 0.8), -_n * 0.5)
