extends PlayerState
## Standing still. Anim key varies with environment temperature, health and mood.


func physics(delta: float) -> StringName:
	p.anim = p.idle_anim()
	var next := p.ground_step(Vector3.ZERO, 0.0, delta)
	if next:
		return next
	if p.raw_input() != Vector2.ZERO:
		return &"run" if p.can_run() else &"walk"
	return &""
