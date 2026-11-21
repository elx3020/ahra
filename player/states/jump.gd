extends PlayerState
## Airborne (rising or falling). Variable jump height, coyote jump, air dash,
## grab swing points, grab climbable walls, fall into water. Air speed carries incoming momentum.

var _cut := false


func enter(_prev: StringName) -> void:
	p.anim = &"jump"
	p.air_speed = maxf(p.planar().length(), p.walk_speed)
	# leaving a moving platform keeps its motion (planar part stays on as drift, like wind;
	# only a rising platform adds to the jump)
	p.carry = p.floor_velocity.slide(p.up_direction)
	p.velocity += p.carry + p.up_direction * maxf(p.floor_velocity.dot(p.up_direction), 0.0)
	# only a real, still-held jump can be cut short (not swing launches, wall jumps, falls)
	_cut = not (p.variable_jump and Input.is_action_pressed(&"jump"))
	p.variable_jump = false


func physics(delta: float) -> StringName:
	if not _cut and p.vspeed() > 0.0 and not Input.is_action_pressed(&"jump"):
		p.set_vspeed(p.vspeed() * p.jump_cut)
		_cut = true
	p.move_air(p.move_input(), delta)
	p.apply_gravity(delta)
	p.move_and_slide()

	if p.wants_jump(): # coyote
		p.do_jump()
		p.variable_jump = false
		_cut = false
	if Input.is_action_just_pressed(&"dash") and p.dash_cd <= 0.0 and p.air_dashes_left > 0 and p.held == null:
		return &"dash"
	if Input.is_action_just_pressed(&"attack") and p.melee_cd <= 0.0 and p.held == null:
		return &"melee"
	if Input.is_action_just_pressed(&"grab") and p.held == null:
		p.swing_point = p.find_swing_point()
		if p.swing_point:
			return &"swing"
	if p.can_climb():
		return &"climb"
	if p.vspeed() <= 0.0 and p.deep_water(): # only on the way down, so leaping out works
		return &"swim"
	if p.is_on_floor():
		return p.landed_state()
	return &""
