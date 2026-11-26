extends PlayerState
## Locked in place for the interactable's duration while its animation plays.

var _t := 0.0


func enter(_prev: StringName) -> void:
	p.anim = &"interact"
	var to := (p.interactable.global_position - p.global_position).slide(p.up_direction)
	if to.length() > 0.1:
		p.facing = to.normalized()
	_t = p.interactable.interact(p)


func physics(delta: float) -> StringName:
	p.move_ground(Vector3.ZERO, 0.0, delta)
	p.apply_gravity(delta)
	p.slide()
	_t -= delta
	return &"idle" if _t <= 0.0 else &""
