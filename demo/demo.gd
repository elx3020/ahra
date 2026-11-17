extends Node3D
## Mechanics test level: iso camera follow, debug HUD, debug keys, bay warps.

const HELP := "WASD move | Shift run | Space jump / swim up | C/Ctrl swim down | Q dash | E interact | F grab (hold, swing)\n1/2 damage/heal | 3/4 register hit/miss (mood) | 5 level up (+10% all stats) | 6 reset progression\n[ ] warp between bays | Backspace back to bay start\n\n"

@onready var player: Player = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: Label = $HUD/Label
@onready var door: CSGBox3D = $Bays/Interact/Door
@onready var bays: Array[Node] = $Bays.get_children()


func _ready() -> void:
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0) # true isometric
	cam.global_position = player.global_position + cam.global_basis.z * 40.0
	# camera moves every render frame itself, following the player's interpolated position
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	var target := player.get_global_transform_interpolated().origin + cam.global_basis.z * 40.0
	if cam.global_position.distance_to(target) > 8.0: # snap after teleports
		cam.global_position = target
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	if player.global_position.distance_to(Vector3(100, 0, 0)) > 200.0:
		player.die(&"fall") # lost in the sky (flipped gravity) or past the void
	hud.text = HELP + "bay: %s\n" % bays[_bay()].name + player.debug_text()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_1: player.damage(15)
		KEY_2: player.heal(15)
		KEY_3: player.register_attack(true)
		KEY_4: player.register_attack(false)
		KEY_5:
			for stat in StatMods.names():
				player.grant(stat, 0.1)
		KEY_6: player.progression = StatMods.new()
		KEY_BRACKETRIGHT: warp(_bay() + 1)
		KEY_BRACKETLEFT: warp(_bay() - 1)
		KEY_BACKSPACE: warp(_bay())


## Debug warp (not a checkpoint: deaths still respawn at the level start).
func warp(i: int) -> void:
	player.respawn(bays[wrapi(i, 0, bays.size())].global_position + Vector3(0, 1, 6))


func _bay() -> int:
	var best := 0
	for i in bays.size():
		if absf(bays[i].global_position.x - player.global_position.x) < absf(bays[best].global_position.x - player.global_position.x):
			best = i
	return best


func _on_lever_used(_p: Player) -> void:
	door.visible = not door.visible
	door.use_collision = door.visible
