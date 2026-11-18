@tool
class_name PlatformSwitch
extends Interactable
## Press interact to change every platform on `channel`, in any area (state lives in World).
## Lights up while its effect is active (toggled, running, reversed, multiplier not 1).

enum Action {
	POWER, ## moving <-> stopped
	RUN, ## after `delay`, move for `run_time` seconds (pressing again restarts)
	REVERSE, ## flip direction: platforms retrace their motion
	SPEED, ## add `step` to the speed multiplier (negative step slows down)
	COOLDOWN, ## add `step` to the cooldown multiplier (negative step shortens the pause)
}

@export var channel: StringName
@export var action := Action.POWER
@export var delay := 0.0 ## RUN: seconds before the platforms start
@export var run_time := 6.0 ## RUN: seconds they move
@export var step := 0.5 ## SPEED / COOLDOWN: change per press
@export var limits := Vector2(0.25, 3.0) ## SPEED / COOLDOWN: the multiplier stays in this range
@export var on_color := Color(0.3, 1.0, 0.4, 0.5)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_mat.albedo_color = on_color if _lit() else color


func _lit() -> bool:
	var c: Dictionary = World.channels.get(channel, {})
	if c.is_empty():
		return false
	match action:
		Action.POWER: return c.flip
		Action.RUN: return World.time < c.run_end
		Action.REVERSE: return c.dir < 0.0
		Action.SPEED: return c.rates.x != 1.0
	return c.rates.y != 1.0


func interact(p: Player) -> float:
	match action:
		Action.POWER: World.toggle(channel)
		Action.RUN: World.run(channel, delay, run_time)
		Action.REVERSE: World.reverse(channel)
		_:
			var r := World.rates(channel)
			var i := 0 if action == Action.SPEED else 1
			r[i] = clampf(r[i] + step, limits.x, limits.y)
			World.set_rates(channel, r)
	return super(p)
