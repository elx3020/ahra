extends GameArea
## NPC demo: a greeter (bark, once intro, repeat with versions), progression (Smith waits for the
## bell the Ringer rings), a performer walking between marks and a doorman who steps aside for good,
## and Mara, who leaves for the dock. 7 forgets everything (story flags and NPC memory), 8 reloads
## the scene to show what NPCs remember.

const NPC_HELP := "7 clear story flags and NPC memory | 8 reload the scene (NPCs remember)\n"


func help() -> String:
	return HELP.trim_suffix("\n") + NPC_HELP + "\n"


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_7:
				World.reset_story()
				return
			KEY_8:
				get_tree().reload_current_scene()
				return
	super(e)
