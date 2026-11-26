class_name GameArea
extends Node3D
## Root of a playable area (one scene of the game): iso camera follow, debug HUD and keys,
## bay warps, out-of-bounds death, and the spawn point when arriving through a SceneDoor.
## Needs children Player, Camera and HUD/Label; Bays (optional) are the warp targets.
## The Camera is authored orthographic; its `size` is the view height at the player. At runtime it
## becomes a narrow perspective camera far away (pseudo-iso), because Godot's GI pass (VoxelGI,
## SDFGI) samples mirrored positions with orthographic cameras (godot#60522).

const FOV := 10.0 ## degrees: narrow enough to read as isometric
const CLIP := 40.0 ## the near plane sits this far from the player, toward the camera
const HELP := "WASD move | Shift run | Space jump / swim up | C/Ctrl swim down | Q dash | E interact | F grab (hold, swing) | J/LMB melee | K/RMB shoot | R carry / put down | T throw\n1/2 damage/heal | 3/4 register hit/miss (mood) | 5 level up (+10% all stats) | 6 reset progression\n[ ] warp between bays | Backspace back to bay start\n\n"

@export var bounds_center := Vector3.ZERO
@export var bounds_radius := 200.0 ## farther than this from bounds_center = fall death
@export var area_id: StringName ## scopes its platform channels: `lift` here is `area_id:lift` (empty: the scene file's name)

@onready var player: Player = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: Label = $HUD/Label
@onready var bays: Array = $Bays.get_children() if has_node(^"Bays") else []
var cam_distance := 0.0
## The camera's rotation without shake. ponytail: code that rotates the camera sets this, not the
## camera: _process puts the shake's roll on top of it every frame.
var _steady_basis := Basis.IDENTITY


func _ready() -> void:
	var spawn: Node3D = get_node_or_null(String(World.spawn)) if World.spawn else null
	World.spawn = &""
	CameraShake.clear() # no shake carries across a scene change
	SlowMo.clear() # nor a hit-stop or bullet time
	if spawn:
		player.teleport(spawn.global_position)
		player.checkpoint = spawn.global_position
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0) # true isometric
	_steady_basis = cam.global_basis
	cam_distance = cam.size * 0.5 / tan(deg_to_rad(FOV * 0.5))
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = FOV
	cam.near = maxf(cam_distance - CLIP, 0.05)
	# Shadow distances count from the camera: shift them so they cover what they did from the old ortho
	# camera, CLIP away. ponytail: PSSM splits lose every shadow nearer than the player with this far,
	# narrow camera (Godot 4.7), so one orthogonal split covers the slab; sharper far shadows need that fixed.
	for light: DirectionalLight3D in find_children("*", "DirectionalLight3D", true, false):
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		light.directional_shadow_max_distance += cam.near
	cam.global_position = player.global_position + cam.global_basis.z * cam_distance
	# camera moves every render frame itself, following the player's interpolated position
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_restore_weights()


func _process(_delta: float) -> void:
	# The camera runs on real time: it keeps up with a full-speed player in bullet time, and a hit
	# shake plays at full speed during a hit-stop. Not `delta / Engine.time_scale`: that is wrong in
	# a frame where SlowMo just changed the scale.
	var real := SlowMo.real_delta
	var target := player.get_global_transform_interpolated().origin + cam.global_basis.z * cam_distance
	if cam.global_position.distance_to(target) > 8.0: # snap after teleports
		cam.global_position = target
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-8.0 * real))
	_shake(real)
	SlowMo.area = player.env.time_scale if player.env else 1.0 # a slow place slows the whole game
	if player.global_position.distance_to(bounds_center) > bounds_radius:
		player.die(&"fall") # lost in the sky (flipped gravity) or past the void
	for n in get_tree().get_nodes_in_group(&"weight"):
		var w := n as WeightBody
		if not w.gone and w.global_position.distance_to(bounds_center) > bounds_radius:
			w.destroy()
	var bay := "bay: %s\n" % bays[_bay()].name if bays else ""
	hud.text = help() + bay + player.debug_text() + World.debug_text()


## Camera shake on its own layer: the slide goes into the built-in view offsets (the camera node
## doesn't move, so the follow above and any zoom never meet it), the tilt onto _steady_basis.
func _shake(delta: float) -> void:
	var s := CameraShake.update(delta, player.get_global_transform_interpolated().origin, player.env.shake if player.env else 0.0)
	var h := view_height()
	cam.h_offset = s.x * h
	cam.v_offset = s.y * h
	cam.global_basis = _steady_basis * Basis(Vector3.BACK, s.z)


## Height of the view at the player, from the camera's live fov: shakes read the same at any zoom.
func view_height() -> float:
	return 2.0 * cam.global_position.distance_to(player.global_position) * tan(deg_to_rad(cam.fov) * 0.5)


## Remembers every weight's place, gravity and pose (World.bodies), so the area finds them where
## they were. ponytail: writes every weight every physics frame; write only awake ones if weights
## get many.
func _physics_process(_delta: float) -> void:
	for n in get_tree().get_nodes_in_group(&"weight"):
		var w := n as WeightBody
		if not w.gone and not w.is_queued_for_deletion():
			World.bodies[Channels.placement_id(w)] = w.state()


## Puts the area's weights back as they were left: placed ones where they were (or gone for good if
## destroyed), dispensed ones too (their Dispenser recreated them in its _ready, before this).
func _restore_weights() -> void:
	for n in get_tree().get_nodes_in_group(&"weight"):
		var w := n as WeightBody
		if not is_ancestor_of(w):
			continue
		var id := Channels.placement_id(w)
		var mem: Dictionary = World.bodies.get(id, {})
		if mem.get("gone", false):
			w.gone = true
			w.queue_free()
			continue
		if mem.has("pos"):
			w.restore(mem)
		if not w.dispensed:
			w.destroyed.connect(func() -> void: World.bodies[id] = {gone = true})


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
