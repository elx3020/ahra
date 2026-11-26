extends GameArea
## Camera shake demo: a storm zone, a brute's footsteps, two crushers out of phase. Keys flip the
## shake toggles (project settings ahra/camera/*) while playing; key 1 (damage) shows the hit shake.

const TOGGLES := {KEY_9: CameraShake.SLIDE, KEY_0: CameraShake.TILT, KEY_MINUS: CameraShake.DISABLE}


func help() -> String:
	var on := func(key: String) -> String: return "on" if ProjectSettings.get_setting(key) else "off"
	return super() + "9 slide (%s) | 0 tilt (%s) | - disable shake (%s)\n\n" % [on.call(CameraShake.SLIDE), on.call(CameraShake.TILT), on.call(CameraShake.DISABLE)]


func _unhandled_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and TOGGLES.has(k.keycode):
		var key: String = TOGGLES[k.keycode]
		ProjectSettings.set_setting(key, not ProjectSettings.get_setting(key))
		return
	super(e)
