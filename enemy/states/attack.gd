extends EnemyState
## Base melee attack: windup (stops and faces the target), one strike check, recovery, then the
## cooldown starts. Types replace this state with their own attack (the burrower's burst).
## Aborts to idle the moment the target is gone, and back to pursuit once it has been out of sight
## for 0.5 s (pursuit heads for where it was last seen).

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
	if not e.sees_target() and e.seen_ago > 0.5:
		return &"pursuit"
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


## One check: the attack point (Enemy.attack_point) within attack_reach and, for ground enemies,
## the target roughly in front. Flyers strike down from their hover point.
func _strike() -> void:
	_struck = true
	e.anim = &"attack"
	e.cue.emit(&"attack")
	e.spend(e.attack_cost)
	if e.global_position.distance_to(e.attack_point()) > e.attack_reach:
		return
	if not e.can(Enemy.Ability.FLY):
		var flat := (e.target_pos() - e.global_position).slide(e.up_direction)
		if flat.length() < 0.01 or e.facing.dot(flat.normalized()) < 0.5:
			return
	var hp := e.target.health
	e.target.damage(e.attack_damage, e.global_position)
	if e.target.health < hp:
		e.mood = minf(e.mood + 0.1, 1.0)
