extends EnemyState
## Airborne: a solved jump (Enemy.launch, set before handing off) or a plain fall (pushed off,
## walked off a drop). No steering in flight. Landing returns to Enemy.goal.

var _t := 0.0


func enter(_prev: StringName) -> void:
	_t = 0.0
	if e.launch != Vector3.ZERO:
		e.velocity = e.launch
		e.launch = Vector3.ZERO
		e.anim = &"jump"
		e.cue.emit(&"jump")
	else:
		e.anim = &"fall"


func physics(delta: float) -> StringName:
	_t += delta
	if e.flail(delta): # fell into deep water it can't swim in
		return &""
	e.apply_gravity(delta)
	e.move_and_slide()
	if _t >= 0.05 and e.is_on_floor():
		e.cue.emit(&"land")
		return e.goal
	return &""
