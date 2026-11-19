class_name GameArea
extends Node3D
## Root of a playable area (one scene of the game): iso camera follow, debug HUD and keys,
## bay warps, out-of-bounds death, and the spawn point when arriving through a SceneDoor.
## Needs children Player, Camera and HUD/Label; Bays (optional) are the warp targets.

const HELP := "WASD move | Shift run | Space jump / swim up | C/Ctrl swim down | Q dash | E interact | F grab (hold, swing)\n1/2 damage/heal | 3/4 register hit/miss (mood) | 5 level up (+10% all stats) | 6 reset progression\n[ ] warp between bays | Backspace back to bay start\n\n"

@export var bounds_center := Vector3.ZERO
@export var bounds_radius := 200.0 ## farther than this from bounds_center = fall death
@export var area_id: StringName ## scopes its platform channels: `lift` here is `area_id:lift` (empty: the scene file's name)

@onready var player: Player = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: Label = $HUD/Label
@onready var bays: Array = $Bays.get_children() if has_node(^"Bays") else []


func _ready() -> void:
	var spawn: Node3D = get_node_or_null(String(World.spawn)) if World.spawn else null
	World.spawn = &""
	if spawn:
		player.teleport(spawn.global_position)
		player.checkpoint = spawn.global_position
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
	if player.global_position.distance_to(bounds_center) > bounds_radius:
		player.die(&"fall") # lost in the sky (flipped gravity) or past the void
	var bay := "bay: %s\n" % bays[_bay()].name if bays else ""
	hud.text = help() + bay + player.debug_text() + World.debug_text()


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


## Controls shown at the top of the HUD.
func help() -> String:
	return HELP


## Debug warp to a bay's "Start" marker, or 6 m in front of its origin.
## Not a checkpoint: deaths still respawn at the area start.
func warp(i: int) -> void:
	if bays:
		var bay: Node3D = bays[wrapi(i, 0, bays.size())]
		var start: Node3D = bay.get_node_or_null(^"Start")
		player.respawn(start.global_position if start else bay.global_position + Vector3(0, 1, 6))


func _bay() -> int:
	var best := 0
	for i in bays.size():
		if absf(bays[i].global_position.x - player.global_position.x) < absf(bays[best].global_position.x - player.global_position.x):
			best = i
	return best
