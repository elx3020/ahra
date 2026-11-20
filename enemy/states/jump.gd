extends EnemyState
## Airborne: a solved jump (Enemy.launch, set before handing off) or a plain fall (pushed off,
## walked off a drop). No steering in flight. Landing returns to Enemy.goal.

var _t := 0.0
var _launched := false ## solved arcs use plain gravity, no env drag, so they land where aimed
var _flat := Vector3.ZERO ## a solved arc's planar velocity, re-applied each frame (see physics)


func enter(_prev: StringName) -> void:
	_t = 0.0
	_launched = e.launch != Vector3.ZERO
	if _launched:
		e.velocity = e.launch
		_flat = e.launch.slide(e.up_direction)
		e.launch = Vector3.ZERO
		e.anim = &"jump"
		e.cue.emit(&"jump")
	else:
		e.anim = &"fall"


func physics(delta: float) -> StringName:
	_t += delta
	if e.swimming() and e.goal != &"idle":
		return &"swim"
	if e.flail(delta): # fell into deep water it can't swim in
		return &""
	if _launched: # ballistic: a wall brushed on the way up (a bank, a ledge) doesn't eat the arc's speed
		e.velocity = _flat + e.up_direction * (e.vspeed() - e.gravity * delta)
	else:
		e.apply_gravity(delta)
	e.move_and_slide()
	if _t >= 0.05 and e.is_on_floor():
		e.cue.emit(&"land")
		return e.goal
	return &""
