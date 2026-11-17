extends Node3D
## Mechanics test level: iso camera follow, debug HUD, debug keys, bay warps, respawn.

const HELP := "WASD move | Shift run | Space jump | Q dash | E interact | F grab (hold, swing)\n1/2 hurt/heal | 3/4 register hit/miss (mood) | 5 level up (+10% all stats) | 6 reset progression\n[ ] warp between bays | Backspace respawn\n\n"

@onready var player: Player = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: Label = $HUD/Label
@onready var door: CSGBox3D = $Bays/Interact/Door
@onready var bays: Array[Node] = $Bays.get_children()

var _bay := 0


func _ready() -> void:
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0) # true isometric
	cam.global_position = player.global_position + cam.global_basis.z * 40.0


func _process(delta: float) -> void:
	var target := player.global_position + cam.global_basis.z * 40.0
	if cam.global_position.distance_to(target) > 8.0: # snap after teleports
		cam.global_position = target
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	if player.global_position.distance_to(Vector3(100, 0, 0)) > 200.0:
		warp(_bay)
	hud.text = HELP + "bay: %s\n" % bays[_bay].name + player.debug_text()


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
		KEY_BRACKETRIGHT: warp(_bay + 1)
		KEY_BRACKETLEFT: warp(_bay - 1)
		KEY_BACKSPACE: warp(_bay)


func warp(i: int) -> void:
	_bay = wrapi(i, 0, bays.size())
	player.end_puppet()
	player.set_gravity_dir(Vector3.DOWN)
	player.velocity = Vector3.ZERO
	player.teleport(bays[_bay].global_position + Vector3(0, 1, 6))


func _on_lever_used(_p: Player) -> void:
	door.visible = not door.visible
	door.use_collision = door.visible
