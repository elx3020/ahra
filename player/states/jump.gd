extends PlayerState
## Airborne (rising or falling). Variable jump height, coyote jump, air dash,
## grab swing points, grab climbable walls, fall into water. Air speed carries incoming momentum.

var _cut := false


func enter(_prev: StringName) -> void:
	p.anim = &"jump"
	p.air_speed = maxf(p.planar().length(), p.walk_speed)
	_cut = not Input.is_action_pressed(&"jump") # only a held jump can be cut short


func physics(delta: float) -> StringName:
	if not _cut and p.vspeed() > 0.0 and not Input.is_action_pressed(&"jump"):
		p.set_vspeed(p.vspeed() * p.jump_cut)
		_cut = true
	p.move_air(p.move_input(), delta)
	p.apply_gravity(delta)
	p.move_and_slide()

	if p.wants_jump(): # coyote
		p.do_jump()
		_cut = false
	if Input.is_action_just_pressed(&"dash") and p.dash_cd <= 0.0 and p.air_dashes_left > 0:
		return &"dash"
	if Input.is_action_just_pressed(&"grab"):
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
