extends PlayerState
## Melee swing: one hit check in front at 40% of melee_time (Player.melee_hit) that damages
## enemies and knocks them back by their weight. Slowed on the ground; air momentum kept in the air.
## ponytail: placeholder combat, one swing and no combos; the combat system comes later.

var _t := 0.0
var _done := false


func enter(_prev: StringName) -> void:
	p.anim = &"melee"
	p.melee_cd = p.melee_cooldown
	_t = 0.0
	_done = false


func physics(delta: float) -> StringName:
	_t += delta
	if p.is_on_floor():
		p.move_ground(p.move_input() * 0.3, p.walk_speed, delta)
	else:
		p.move_air(p.move_input(), delta)
	p.apply_gravity(delta)
	p.slide()
	if not _done and _t >= p.melee_time * 0.4:
		_done = true
		p.register_attack(p.melee_hit() > 0)
	return p.recover_state() if _t >= p.melee_time else &""
