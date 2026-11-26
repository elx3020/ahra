extends GameArea
## Slow motion demo: hit-stops on runners and a brute, a slow area (EnvProfile.time_scale 0.4) and
## a bullet time bay (V). Key 9 flips the hit-stop toggle (project setting ahra/time/disable_hit_stop)
## while playing; key 1 (damage) shows the hurt stop.


func help() -> String:
	return super() + "9 hit slow-down (%s)\n\n" % ("off" if ProjectSettings.get_setting(SlowMo.DISABLE, false) else "on")


func _unhandled_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_9:
		ProjectSettings.set_setting(SlowMo.DISABLE, not ProjectSettings.get_setting(SlowMo.DISABLE, false))
		return
	super(e)
