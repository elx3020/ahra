@tool
class_name PlatformSwitch
extends Interactable
## Press interact to drive every SWITCH platform on `channel`, in any area (state lives in World).

@export var channel: StringName
@export var run_time := 0.0 ## 0 = toggle on/off; > 0 = each press runs the channel this long
@export var on_color := Color(0.3, 1.0, 0.4, 0.5)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_mat.albedo_color = on_color if World.is_on(channel) else color


func interact(p: Player) -> float:
	World.press(channel, run_time)
	return super(p)
