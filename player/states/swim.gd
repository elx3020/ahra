extends PlayerState
## In deep water. Hold jump = swim up (stops at the surface), hold descend = swim down,
## neither = float at the surface / slowly sink below it. Jump at the surface = leap out.
## Grab works underwater too (swing points below the surface).


func enter(_prev: StringName) -> void:
	p.drop_held() # can't swim with a weight
	p.anim = &"swim"


func physics(delta: float) -> StringName:
	if p.water_zone == null: # left the water (e.g. swam out through a side)
		return &"jump"
	var depth := p.water_depth()
	var at_surface := depth <= p.float_depth + 0.3
	var target := 0.0 if at_surface else -p.swim_sink
	if Input.is_action_pressed(&"jump"):
		target = p.swim_speed
	elif Input.is_action_pressed(&"descend"):
		target = -p.swim_speed
	var m := p.mult(&"swim")
	p.set_vspeed(move_toward(p.vspeed(), target * m, p.swim_accel * delta))
	if depth < p.float_depth and p.vspeed() > 0.0: # never rise past the surface
		p.global_position -= p.up_direction * (p.float_depth - depth)
		p.set_vspeed(0.0)
	p.move_planar(p.move_input(), p.swim_speed * m, p.swim_accel, delta)
	p.slide()

	if at_surface and p.jump_buffer > 0.0:
		p.jump_buffer = 0.0
		p.set_vspeed(p.jump_velocity(p.ambient)) # leap with dry-land strength
		return &"jump"
	if Input.is_action_just_pressed(&"dash") and p.dash_cd <= 0.0:
		return &"dash"
	if Input.is_action_just_pressed(&"grab"):
		p.swing_point = p.find_swing_point()
		if p.swing_point:
			return &"swing"
	if p.is_on_floor() and target <= 0.0:
		return p.landed_state()
	return &""
