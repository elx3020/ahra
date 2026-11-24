extends Node3D
## PBR material showcase. The Weather node runs the day/night cycle (sun, moon, sky, lamps at dusk)
## and its time panel. Global illumination is the baked VoxelGI (re-bake it after moving the static
## geometry). Drag to orbit, mouse wheel to zoom.

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		pivot.rotation.y -= e.relative.x * 0.005
		pivot.rotation.x = clampf(pivot.rotation.x - e.relative.y * 0.005, -1.45, -0.05)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom := 0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
		camera.position.z = clampf(camera.position.z * zoom, 3.0, 40.0)
