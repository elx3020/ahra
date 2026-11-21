extends GameArea
## Switch puzzle demo, two linked areas (switches_a, switches_b): weight plates (hold, latch),
## doors, an energy switch, weights to push, carry (R) and throw (T), dispensers, gravity zones on
## everything, and a door whose latch plates are in both areas. 7 forgets every switch and weight,
## 8 reloads the area to show what is remembered.

const SWITCH_HELP := "K shoot energy switches | 7 forget switches and weights | 8 reload the area (it remembers)\n"


func help() -> String:
	return HELP.trim_suffix("\n") + SWITCH_HELP + "\n"


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_7:
				World.switches.clear()
				World.bodies.clear()
				get_tree().reload_current_scene()
				return
			KEY_8:
				get_tree().reload_current_scene()
				return
	super(e)
