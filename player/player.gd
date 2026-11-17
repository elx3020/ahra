class_name Player
extends CharacterBody3D
## Player controller. Shared movement helpers + stats live here; per-state
## behaviour lives in res://player/states/ (one script per state).
## Gravity can point anywhere: motion is split into "vertical" (along up_direction)
## and "planar" (perpendicular to it), so walking on walls/ceilings needs no special case.
##
## Stats: the exports below are BASE values. Gameplay reads them through mult(stat):
##   final = base * (1 + progression% + environment%)   (see StatMods)

signal puppet_arrived

@export_group("Ground")
@export var walk_speed := 4.5
@export var run_speed := 8.5
@export var accel := 70.0
@export var decel := 90.0
@export_group("Air")
@export var jump_height := 2.6
@export var gravity := 32.0
@export var fall_gravity_mult := 1.7
@export var max_fall_speed := 30.0
@export var air_accel := 40.0
@export var air_decel := 6.0 ## low so momentum (dash, teleport) carries through the air
@export_range(0.0, 1.0) var jump_cut := 0.45 ## vertical speed kept when jump is released early
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12
@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.3
@export var air_dashes := 1
@export_group("Climb & Swing")
@export var climb_speed := 3.5
@export var swing_force := 14.0
@export_group("Stats")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var run_cost := 18.0 ## stamina/s while running
@export var stamina_regen := 30.0
@export var mood_window := 20 ## mood = hit ratio over the last N attacks
@export var ambient: EnvProfile ## environment used outside of any EnvZone
@export var progression := StatMods.new() ## permanent % bonuses earned in play; this is what gets saved

var health := 0.0
var stamina := 0.0
var exhausted := false
var mood := 0.5
var gravity_dir := Vector3.DOWN
var facing := Vector3.FORWARD
var anim: StringName = &"idle"
var envs: Array[EnvProfile] = [] ## pushed/popped by EnvZones; the last one entered wins
var interactable: Interactable
var swing_point: SwingPoint
var puppet_target: Variant = null
var air_speed := 0.0
var air_dashes_left := 0
var coyote := 0.0
var jump_buffer := 0.0
var dash_cd := 0.0
var _attacks: Array[bool] = []

var env: EnvProfile:
	get: return envs.back() if not envs.is_empty() else ambient

var states: Dictionary[StringName, PlayerState] = {
	&"idle": preload("states/idle.gd").new(),
	&"walk": preload("states/walk.gd").new(),
	&"run": preload("states/run.gd").new(),
	&"dash": preload("states/dash.gd").new(),
	&"jump": preload("states/jump.gd").new(),
	&"climb": preload("states/climb.gd").new(),
	&"swing": preload("states/swing.gd").new(),
	&"interact": preload("states/interact.gd").new(),
	&"puppet": preload("states/puppet.gd").new(),
}
var state: PlayerState
var state_name: StringName

@onready var _visual: Node3D = $Visual
@onready var _visual_base := _visual.position
@onready var _mat: StandardMaterial3D = $Visual/Body.material_override


func _ready() -> void:
	if ambient == null:
		ambient = EnvProfile.new()
	health = max_hp()
	stamina = max_sp()
	for s in states.values():
		s.p = self
	change_state(&"idle")


func change_state(next: StringName) -> void:
	if state:
		state.exit()
	var prev := state_name
	state_name = next
	state = states[next]
	state.enter(prev)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		coyote = coyote_time
		air_dashes_left = air_dashes
	else:
		coyote -= delta
	jump_buffer = jump_buffer_time if Input.is_action_just_pressed(&"jump") else jump_buffer - delta
	dash_cd -= delta
	if state_name != &"run":
		stamina += stamina_regen * mult(&"stamina_regen") * delta
	stamina = minf(stamina, max_sp())
	health = minf(health, max_hp())
	if exhausted and stamina > max_sp() * 0.3:
		exhausted = false

	var next := state.physics(delta)
	if next:
		change_state(next)
	_orient(delta)
	_animate(delta)


# --- input ---------------------------------------------------------------

func raw_input() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func cam_basis() -> Basis:
	var cam := get_viewport().get_camera_3d()
	return cam.global_basis if cam else Basis.IDENTITY


## Stick input mapped onto the current walking plane, camera-relative.
## Uses the camera's up vector as "forward": for a tilted iso camera it points
## away from the viewer on floors/ceilings and "up" on walls facing the camera.
func move_input() -> Vector3:
	var i := raw_input()
	if i == Vector2.ZERO:
		return Vector3.ZERO
	var b := cam_basis()
	var right := b.x.slide(up_direction).normalized()
	var fwd := b.y.slide(up_direction)
	if fwd.length() < 0.2:
		fwd = -b.z.slide(up_direction)
	return (right * i.x - fwd.normalized() * i.y).limit_length(1.0)


func can_run() -> bool:
	return Input.is_action_pressed(&"run") and not exhausted


# --- movement helpers (used by states) -------------------------------------

func vspeed() -> float:
	return velocity.dot(up_direction)


func planar() -> Vector3:
	return velocity - up_direction * vspeed()


func set_vspeed(v: float) -> void:
	velocity = planar() + up_direction * v


func move_planar(dir: Vector3, speed: float, rate: float, delta: float) -> void:
	if dir.length() > 0.1:
		facing = dir.normalized()
	velocity = planar().move_toward(dir * speed, rate * delta) + up_direction * vspeed()


func move_ground(dir: Vector3, speed: float, delta: float) -> void:
	move_planar(dir, speed * mult(&"speed"), (accel if dir != Vector3.ZERO else decel) * mult(&"traction"), delta)


func move_air(dir: Vector3, delta: float) -> void:
	move_planar(dir, air_speed, air_accel if dir != Vector3.ZERO else air_decel, delta)


func apply_gravity(delta: float) -> void:
	var e := env
	var g := gravity * e.gravity_mult * (fall_gravity_mult if vspeed() < 0.0 else 1.0)
	set_vspeed(maxf(vspeed() - g * delta, -max_fall_speed))
	if not is_on_floor():
		velocity += e.wind * delta
	velocity -= velocity * minf(e.drag * delta, 1.0)


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * env.gravity_mult * jump_height * mult(&"jump"))


func wants_jump() -> bool:
	return jump_buffer > 0.0 and coyote > 0.0


func do_jump() -> void:
	set_vspeed(jump_velocity())
	jump_buffer = 0.0
	coyote = 0.0


## Shared move + transitions for idle/walk/run. Returns the next state or &"".
func ground_step(dir: Vector3, speed: float, delta: float) -> StringName:
	move_ground(dir, speed, delta)
	apply_gravity(delta)
	move_and_slide()
	if wants_jump():
		do_jump()
		return &"jump"
	if not is_on_floor():
		return &"jump"
	if Input.is_action_just_pressed(&"dash") and dash_cd <= 0.0:
		return &"dash"
	if interactable and Input.is_action_just_pressed(&"interact"):
		return &"interact"
	if can_climb():
		return &"climb"
	return &""


func landed_state() -> StringName:
	if raw_input() == Vector2.ZERO:
		return &"idle"
	return &"run" if can_run() else &"walk"


func can_climb() -> bool:
	if not is_on_wall() or move_input().dot(-get_wall_normal()) < 0.3:
		return false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c is Node and c.is_in_group(&"climbable"):
			return true
	return false


func find_swing_point() -> SwingPoint:
	var best: SwingPoint
	var best_d := INF
	for s: SwingPoint in get_tree().get_nodes_in_group(&"swing_point"):
		var d := global_position.distance_to(s.global_position)
		if d < s.grab_radius and d < best_d:
			best = s
			best_d = d
	return best


# --- special mechanics -------------------------------------------------------

## Instant relocation. Velocity is kept (optionally rotated, e.g. portal-style).
func teleport(pos: Vector3, rotate_by := Basis.IDENTITY) -> void:
	global_position = pos
	reset_physics_interpolation() # no smear across the jump
	velocity = rotate_by * velocity
	facing = rotate_by * facing


## Any direction works: DOWN (normal), UP (ceiling), FORWARD = -z (wall)...
## Momentum is kept, so the player "falls" toward the new floor.
func set_gravity_dir(dir: Vector3) -> void:
	gravity_dir = dir.normalized()
	up_direction = -gravity_dir


func start_puppet(target: Variant = null) -> void:
	puppet_target = target
	change_state(&"puppet")


func end_puppet() -> void:
	if state_name == &"puppet":
		change_state(&"idle")


# --- stats -------------------------------------------------------------------

## Multiplier for a StatMods stat: 1 + progression% + current environment%.
## Additive: +20% progression and -30% environment => x0.9 of base.
func mult(stat: StringName) -> float:
	return maxf(0.0, 1.0 + progression.get(stat) + env.mods.get(stat))


## Permanent upgrade (pickups, level-ups). pct is a fraction: 0.1 = +10%.
func grant(stat: StringName, pct: float) -> void:
	assert(stat in progression, "unknown stat %s" % stat)
	progression.set(stat, progression.get(stat) + pct)


func max_hp() -> float:
	return max_health * mult(&"max_health")


func max_sp() -> float:
	return max_stamina * mult(&"max_stamina")


func damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, max_hp())


func heal(amount: float) -> void:
	damage(-amount)


func register_attack(hit: bool) -> void:
	_attacks.append(hit)
	if _attacks.size() > mood_window:
		_attacks.pop_front()
	mood = float(_attacks.count(true)) / _attacks.size()


## e.g. &"idle_hot_low_sad". Feed straight into an AnimationPlayer/Tree once real anims exist.
func idle_anim() -> StringName:
	var temp: String = ["cold", "mild", "hot"][env.temperature]
	return StringName("idle_%s_%s_%s" % [temp, _tier(health / max_hp(), "low", "mid", "full"), _tier(mood, "sad", "calm", "happy")])


static func _tier(v: float, lo: String, mid: String, hi: String) -> String:
	return lo if v < 0.34 else (mid if v < 0.67 else hi)


func debug_text() -> String:
	return "state: %s\nanim: %s\nenv: %s\nhp: %d  mood: %d%%  stamina: %d%s\ngravity: %s\nspeed: %.1f" % [
		state_name, anim, env.resource_name if env.resource_name else "ambient",
		health, mood * 100, stamina, " (exhausted)" if exhausted else "",
		gravity_dir, velocity.length()] + _stats_text()


func _stats_text() -> String:
	var out := ""
	for s in StatMods.names():
		var prog: float = progression.get(s)
		var e: float = env.mods.get(s)
		if prog != 0.0 or e != 0.0:
			out += "
  %s: %+d%% prog %+d%% env = x%.2f" % [s, roundi(prog * 100), roundi(e * 100), mult(s)]
	return "
stats:" + (out if out else " all base")


# --- presentation --------------------------------------------------------------

func _orient(delta: float) -> void:
	# keep facing on the walking plane (gravity changes can make it parallel to up)
	for v in [facing, -global_basis.z, global_basis.y]:
		var f: Vector3 = v.slide(up_direction)
		if f.length() > 0.01:
			facing = f.normalized()
			break
	var target := Basis.looking_at(facing, up_direction)
	global_basis = global_basis.slerp(target, 1.0 - exp(-18.0 * delta)).orthonormalized()


## Placeholder "animation" on the capsule so state/anim variants are visible.
## Runs in the physics tick (not _process) so physics interpolation smooths it too.
## ponytail: procedural squash/tilt stand-in, replace with AnimationTree keyed by `anim`.
func _animate(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var hp := health / max_hp()
	var sc := Vector3.ONE
	var off := Vector3.ZERO
	var tilt := 0.0
	match anim:
		&"walk": off.y = absf(sin(t * 10.0)) * 0.06
		&"run": off.y = absf(sin(t * 14.0)) * 0.1; tilt = -0.25
		&"dash": sc = Vector3(0.7, 0.7, 1.6)
		&"jump": sc = Vector3(0.85, 1.2, 0.85)
		&"climb": off.y = sin(t * 8.0) * 0.08
		&"hang": sc = Vector3(0.95, 1.06, 0.95)
		&"swing": tilt = 0.4
		&"interact": sc.y = 1.0 + sin(t * 20.0) * 0.1; tilt = -0.4
		&"puppet": sc.y = 1.0 + sin(t * 2.0) * 0.02
		_: # idle_<temp>_<health>_<mood>
			var temp := env.temperature
			sc.y = lerpf(0.8, 1.0, hp) + sin(t * [5.0, 2.5, 1.2][temp]) * [0.02, 0.03, 0.06][temp]
			if temp == EnvProfile.Temp.COLD:
				off.x = sin(t * 60.0) * 0.03 # shiver
			if hp < 0.34:
				tilt = -0.3 # slumped
	var k := 1.0 - exp(-15.0 * delta)
	_visual.position = _visual_base + off
	_visual.scale = _visual.scale.lerp(sc, k)
	_visual.rotation.x = lerpf(_visual.rotation.x, tilt, k)
	_mat.albedo_color = Color(0.35, 0.45, 0.85).lerp(Color(1.0, 0.75, 0.2), mood)
