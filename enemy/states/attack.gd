extends EnemyState
## Base melee attack: windup (stops and faces the target), one strike check, recovery, then the
## cooldown starts. Types replace this state with their own attack (the burrower's burst).
## Aborts to idle the moment the target is gone.

const STRIKE_TIME := 0.15 ## how long the `attack` anim shows before `attack_recover`

var _t := 0.0
var _struck := false


func enter(_prev: StringName) -> void:
	_t = 0.0
	_struck = false
	e.anim = &"attack_windup"
	e.cue.emit(&"attack_windup")


func physics(delta: float) -> StringName:
	if not e.has_target():
		return &"idle"
	_t += delta
	e.hold(delta)
	if not _struck:
		e.face(e.target_pos())
		if _t >= e.attack_windup:
			_strike()
		return &""
	if _t >= e.attack_windup + STRIKE_TIME:
		e.anim = &"attack_recover"
	if _t >= e.attack_windup + e.attack_recover:
		e.attack_cd = e.attack_cooldown
		return &"pursuit"
	return &""


## One check: the target within attack_reach and roughly in front.
func _strike() -> void:
	_struck = true
	e.anim = &"attack"
	e.cue.emit(&"attack")
	e.spend(e.attack_cost)
	var to := e.target_pos() - e.global_position
	var flat := to.slide(e.up_direction)
	if to.length() > e.attack_reach or flat.length() < 0.01 or e.facing.dot(flat.normalized()) < 0.5:
		return
	var hp := e.target.health
	e.target.damage(e.attack_damage, e.global_position)
	if e.target.health < hp:
		e.mood = minf(e.mood + 0.1, 1.0)
