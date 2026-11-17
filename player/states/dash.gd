extends PlayerState
## Fixed-velocity burst, no gravity. Duration (= distance) scaled by the dash stat.
## Jumping during a ground dash keeps the dash speed (dash-jump).

var _t := 0.0
var _dir := Vector3.ZERO


func enter(_prev: StringName) -> void:
	p.anim = &"dash"
	var i := p.move_input()
	_dir = i.normalized() if i != Vector3.ZERO else p.facing
	p.facing = _dir
	if not p.is_on_floor():
		p.air_dashes_left -= 1
	_t = p.dash_time * p.mult(&"dash")
	p.dash_cd = p.dash_cooldown + _t


func physics(delta: float) -> StringName:
	p.velocity = _dir * p.dash_speed
	if p.wants_jump():
		p.do_jump()
		return &"jump"
	p.move_and_slide()
	_t -= delta
	if _t > 0.0:
		return &""
	p.velocity = p.velocity.limit_length(p.run_speed)
	return p.landed_state() if p.is_on_floor() else &"jump"
