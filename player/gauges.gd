extends Control
## Stamina / oxygen bars floating next to the player on screen. Hidden while full.

@onready var player: Player = owner
@onready var stamina: ProgressBar = $Stamina
@onready var oxygen: ProgressBar = $Oxygen


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	position = cam.unproject_position(player.get_global_transform_interpolated().origin) + Vector2(30, -40)
	stamina.value = player.stamina / player.max_sp()
	stamina.visible = stamina.value < 0.999 or player.exhausted
	stamina.self_modulate = Color(1, 0.3, 0.3) if player.exhausted else Color.WHITE
	oxygen.value = player.oxygen / player.max_o2()
	oxygen.visible = oxygen.value < 0.999
