extends PlayerState
## Pendulum on a SwingPoint while "grab" is held. Rope length fixed at grab time.
## Input pumps the swing; jump = slingshot release (dry-land strength, so it also works
## underwater), letting go of grab keeps momentum only.

var _len := 0.0


func enter(_prev: StringName) -> void:
	p.anim = &"swing"
	_len = maxf(p.global_position.distance_to(p.swing_point.global_position), 1.5)


func exit() -> void:
	p.swing_point.hide_rope()
	p.swing_point = null


func physics(delta: float) -> StringName:
	var anchor := p.swing_point.global_position
	p.velocity += (p.gravity_dir * p.gravity * p.env.gravity_mult + p.env.wind) * delta
	p.velocity += p.move_input() * p.swing_force * p.mult(&"swing") * delta
	p.velocity -= p.velocity * minf(p.env.drag * delta, 1.0)
	p.slide()

	var off := p.global_position - anchor
	if off.length() > _len: # rope constraint: pull back, remove outward speed
		var r := off.normalized()
		p.global_position = anchor + r * _len
		p.velocity -= r * maxf(p.velocity.dot(r), 0.0)
	if p.planar().length() > 0.5:
		p.facing = p.planar().normalized()
	p.swing_point.show_rope(p.global_position)

	if p.jump_buffer > 0.0: # slingshot along the swing, never into the ground
		p.jump_buffer = 0.0
		var dir := p.velocity.normalized() if p.velocity.length() > 0.5 else p.up_direction
		if dir.dot(p.up_direction) < 0.0:
			dir = dir.slide(p.up_direction).normalized()
		p.velocity += dir * p.jump_velocity(p.ambient) * p.swing_launch
		p.launched = true
		return &"jump"
	if not Input.is_action_pressed(&"grab"):
		return &"jump"
	if p.is_on_floor():
		return &"idle"
	return &""
