extends PlayerState


func enter(_prev: StringName) -> void:
	p.anim = &"walk"


func physics(delta: float) -> StringName:
	var dir := p.move_input()
	var next := p.ground_step(dir, p.walk_speed, delta)
	if next:
		return next
	if dir == Vector3.ZERO:
		return &"idle"
	return &"run" if p.can_run() else &""
