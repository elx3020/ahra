extends PlayerState
## Drains stamina (stamina_cost stat: mud/heat make it tiring).
## Empty stamina = exhausted: forced to walk until exhaust_time has passed.


func enter(_prev: StringName) -> void:
	p.anim = &"run"


func physics(delta: float) -> StringName:
	p.stamina -= p.run_cost * p.mult(&"stamina_cost") * delta
	if p.stamina <= 0.0:
		p.stamina = 0.0
		p.exhausted = true
		p.exhaust_t = p.exhaust_time
	var dir := p.move_input()
	var next := p.ground_step(dir, p.run_speed, delta)
	if next:
		return next
	if dir == Vector3.ZERO:
		return &"idle"
	return &"walk" if not p.can_run() else &""
