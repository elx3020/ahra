extends PlayerState
## Brief stun + knockback after taking damage (velocity is set by Player.damage).
## Invulnerability is the separate Player.invuln timer: it outlasts this state
## and the player blinks while it runs.

var _t := 0.0


func enter(_prev: StringName) -> void:
	p.anim = &"hurt"
	_t = p.hurt_time


func physics(delta: float) -> StringName:
	p.move_planar(Vector3.ZERO, 0.0, 8.0, delta)
	p.apply_gravity(delta)
	p.slide()
	_t -= delta
	return p.recover_state() if _t <= 0.0 else &""
