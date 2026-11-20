extends EnemyState
## Cause-specific death (Enemy.death_cause: fall / drown / hit), then the enemy frees itself.
## Physics keeps running, so a body falling into a pit keeps falling.

const DURATION := {&"fall": 1.0, &"drown": 2.5, &"hit": 1.5}

var _t := 0.0


func enter(_prev: StringName) -> void:
	e.anim = StringName("death_%s" % e.death_cause)
	_t = DURATION.get(e.death_cause, 1.5)


func physics(delta: float) -> StringName:
	e.hold(delta, true)
	_t -= delta
	if _t <= 0.0:
		e.queue_free()
	return &""
