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

const HEAD := 0.8 ## head height above the body center, for breathing checks

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
@export_group("Wind")
## Wind push becomes a drift speed the player steers against: drift = wind * response.
@export var wind_response_ground := 0.2
@export var wind_response_air := 0.4
@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.3
@export var air_dashes := 1
@export_group("Climb, Swing & Swim")
@export var climb_speed := 3.5
@export var climb_accel := 40.0
@export var climb_slip := 3.0 ## slide-down speed on a wall with 0% traction
@export var swing_force := 14.0
@export var swing_launch := 0.6 ## jump-release boost, fraction of a dry-land jump's speed
@export var swim_speed := 4.0
@export var swim_accel := 20.0
@export var swim_sink := 1.0 ## sink speed when not swimming up/down
@export var float_depth := 0.5 ## body center depth when floating at the surface
@export_group("Stats")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var run_cost := 18.0 ## stamina/s while running
@export var stamina_regen := 30.0
@export var exhaust_time := 2.0 ## seconds running is locked after stamina hits 0
@export var max_oxygen := 12.0 ## seconds of breath underwater
@export var oxygen_regen := 6.0 ## per second while breathing
@export var mood_window := 20 ## mood = hit ratio over the last N attacks
@export_group("Damage")
@export var invuln_time := 1.0 ## i-frames after a hit
@export var hurt_time := 0.35 ## stun duration of the hurt state
@export var knockback := 6.0
@export var knockback_up := 4.0
@export var respawn_invuln := 1.5
@export_group("")
@export var ambient: EnvProfile ## environment used outside of any EnvZone
@export var progression := StatMods.new() ## permanent % bonuses earned in play; this is what gets saved

var health := 0.0
var stamina := 0.0
var oxygen := 0.0
var exhausted := false
var exhaust_t := 0.0
var invuln := 0.0
var death_cause: StringName ## &"fall", &"drown", &"hit": picks the death animation
var checkpoint := Vector3.ZERO ## respawn point; level start for now
var mood := 0.5
var gravity_dir := Vector3.DOWN
var facing := Vector3.FORWARD
var anim: StringName = &"idle"
var env: EnvProfile ## ambient + every zone the player is in, blended (EnvProfile.combine)
var _envs: Array[EnvProfile] = []
var water_zone: EnvZone ## set by water EnvZones; gives the surface height
var interactable: Interactable
var swing_point: SwingPoint
var puppet_target: Variant = null
var air_speed := 0.0
var air_dashes_left := 0
var coyote := 0.0
var jump_buffer := 0.0
var variable_jump := false ## set by do_jump: only real jumps get cut short on release
var launched := false ## slingshot release: ignores drag (water) until the apex
var dash_cd := 0.0
var _attacks: Array[bool] = []

var states: Dictionary[StringName, PlayerState] = {
	&"idle": preload("states/idle.gd").new(),
	&"walk": preload("states/walk.gd").new(),
	&"run": preload("states/run.gd").new(),
	&"dash": preload("states/dash.gd").new(),
	&"jump": preload("states/jump.gd").new(),
	&"climb": preload("states/climb.gd").new(),
	&"swing": preload("states/swing.gd").new(),
	&"swim": preload("states/swim.gd").new(),
	&"interact": preload("states/interact.gd").new(),
	&"puppet": preload("states/puppet.gd").new(),
	&"hurt": preload("states/hurt.gd").new(),
	&"death": preload("states/death.gd").new(),
}
var state: PlayerState
var state_name: StringName

@onready var _visual: Node3D = $Visual
@onready var _visual_base := _visual.position
@onready var _mat: StandardMaterial3D = $Visual/Body.material_override


func _ready() -> void:
	if ambient == null:
		ambient = EnvProfile.new()
	env = EnvProfile.combine(ambient, _envs)
	health = max_hp()
	stamina = max_sp()
	oxygen = max_o2()
	checkpoint = global_position
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
	invuln -= delta
	_tick_stats(delta)

	var next := state.physics(delta)
	if next:
		change_state(next)
	_orient(delta)
	_animate(delta)


func _tick_stats(delta: float) -> void:
	if state_name != &"run":
		stamina += stamina_regen * mult(&"stamina_regen") * delta
	stamina = minf(stamina, max_sp())
	health = minf(health, max_hp())
	if exhausted:
		exhaust_t -= delta
		exhausted = exhaust_t > 0.0
	if water_depth() > HEAD:
		oxygen -= delta
		if oxygen <= 0.0:
			oxygen = 0.0
			die(&"drown")
	else:
		oxygen = minf(oxygen + oxygen_regen * delta, max_o2())


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


func move_planar(dir: Vector3, speed: float, rate: float, delta: float, drift := Vector3.ZERO) -> void:
	if dir.length() > 0.1:
		facing = dir.normalized()
	velocity = planar().move_toward(dir * speed + drift, rate * delta) + up_direction * vspeed()


func move_ground(dir: Vector3, speed: float, delta: float) -> void:
	var rate := (accel if dir != Vector3.ZERO else decel) * mult(&"traction")
	move_planar(dir, speed * mult(&"speed"), rate, delta, wind_drift(wind_response_ground))


func move_air(dir: Vector3, delta: float) -> void:
	move_planar(dir, air_speed, air_accel if dir != Vector3.ZERO else air_decel, delta, wind_drift(wind_response_air))


## Wind along the walking plane as a drift velocity (always on: ground and air).
func wind_drift(response: float) -> Vector3:
	return env.wind.slide(up_direction) * response


## Gravity, wind lift (the part of the wind along up) and drag.
func apply_gravity(delta: float) -> void:
	var e := env
	var g := gravity * e.gravity_mult * (fall_gravity_mult if vspeed() < 0.0 else 1.0)
	set_vspeed(maxf(vspeed() + (e.wind.dot(up_direction) - g) * delta, -max_fall_speed))
	if launched and vspeed() <= 0.0:
		launched = false
	var damp := 0.0 if launched else minf(e.drag * delta, 1.0)
	velocity -= velocity * damp
	air_speed -= air_speed * damp # carried air momentum is slowed by water/thick air too


func jump_velocity(e: EnvProfile = null) -> float:
	if e == null:
		e = env
	return sqrt(2.0 * gravity * e.gravity_mult * jump_height * mult(&"jump", e))


func wants_jump() -> bool:
	return jump_buffer > 0.0 and coyote > 0.0


func do_jump() -> void:
	set_vspeed(jump_velocity())
	jump_buffer = 0.0
	coyote = 0.0
	variable_jump = true


## Distance of the body center below the water surface. -INF when not in water.
func water_depth() -> float:
	if water_zone == null:
		return -INF
	return water_zone.surface_height(up_direction) - global_position.dot(up_direction)


func deep_water() -> bool:
	return water_depth() > float_depth


## Shared move + transitions for idle/walk/run. Returns the next state or &"".
func ground_step(dir: Vector3, speed: float, delta: float) -> StringName:
	move_ground(dir, speed, delta)
	apply_gravity(delta)
	move_and_slide()
	if wants_jump():
		if deep_water(): # jump on the bottom = start swimming up
			jump_buffer = 0.0
			return &"swim"
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


## Where to go when a non-controllable state (hurt, dash...) ends.
func recover_state() -> StringName:
	if deep_water():
		return &"swim"
	return landed_state() if is_on_floor() else &"jump"


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


## Called by EnvZones on enter/exit. Overlapping zones all apply at once.
func add_env(e: EnvProfile) -> void:
	_envs.append(e)
	env = EnvProfile.combine(ambient, _envs)


func remove_env(e: EnvProfile) -> void:
	_envs.erase(e)
	env = EnvProfile.combine(ambient, _envs)


# --- damage, death, respawn -------------------------------------------------------

## Hurts the player: hurt state + knockback + i-frames. Health 0 = death by hit.
## Ignored while invulnerable, dead or in a cinematic. `from`: hit source position.
func damage(amount: float, from: Variant = null) -> void:
	if amount <= 0.0 or invuln > 0.0 or state_name in [&"death", &"puppet"]:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		die(&"hit")
		return
	invuln = invuln_time
	var away := -facing
	if from != null:
		var d: Vector3 = (global_position - from).slide(up_direction)
		if d.length() > 0.01:
			away = d.normalized()
	velocity = away * knockback + up_direction * knockback_up
	change_state(&"hurt")


func heal(amount: float) -> void:
	health = minf(health + amount, max_hp())


## cause: &"fall" (pits/void), &"drown" (out of oxygen), &"hit" (health 0).
## The death state plays the matching animation, then respawns at the checkpoint.
func die(cause: StringName) -> void:
	if state_name == &"death":
		return
	death_cause = cause
	health = 0.0
	change_state(&"death")


## Back to life at `at` (default: checkpoint) with full health/stamina/oxygen.
func respawn(at: Variant = null) -> void:
	set_gravity_dir(Vector3.DOWN)
	velocity = Vector3.ZERO
	teleport(checkpoint if at == null else at)
	health = max_hp()
	stamina = max_sp()
	oxygen = max_o2()
	exhausted = false
	invuln = respawn_invuln
	change_state(&"idle")


# --- stats -------------------------------------------------------------------

## Multiplier for a StatMods stat: 1 + progression% + environment% (current env by default).
## Additive: +20% progression and -30% environment => x0.9 of base.
func mult(stat: StringName, e: EnvProfile = null) -> float:
	if e == null:
		e = env
	return maxf(0.0, 1.0 + progression.get(stat) + e.mods.get(stat))


## Permanent upgrade (pickups, level-ups). pct is a fraction: 0.1 = +10%.
func grant(stat: StringName, pct: float) -> void:
	assert(stat in progression, "unknown stat %s" % stat)
	progression.set(stat, progression.get(stat) + pct)


func max_hp() -> float:
	return max_health * mult(&"max_health")


func max_sp() -> float:
	return max_stamina * mult(&"max_stamina")


func max_o2() -> float:
	return max_oxygen * mult(&"max_oxygen")


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
	return "state: %s\nanim: %s\nenv: %s\nhp: %d%s  mood: %d%%\nstamina: %d%s  oxygen: %.1fs\ngravity: %s\nspeed: %.1f" % [
		state_name, anim, env.resource_name if env.resource_name else "ambient",
		health, " (invulnerable)" if invuln > 0.0 else "", mood * 100,
		stamina, " (exhausted %.1fs)" % exhaust_t if exhausted else "", oxygen,
		gravity_dir, velocity.length()] + _stats_text()


func _stats_text() -> String:
	var out := ""
	for s in StatMods.names():
		var prog: float = progression.get(s)
		var e: float = env.mods.get(s)
		if prog != 0.0 or e != 0.0:
			out += "\n  %s: %+d%% prog %+d%% env = x%.2f" % [s, roundi(prog * 100), roundi(e * 100), mult(s)]
	return "\nstats:" + (out if out else " all base")


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
		&"swim": tilt = -0.9; off.y = sin(t * 4.0) * 0.06
		&"interact": sc.y = 1.0 + sin(t * 20.0) * 0.1; tilt = -0.4
		&"puppet": sc.y = 1.0 + sin(t * 2.0) * 0.02
		&"hurt": sc = Vector3(1.2, 0.75, 1.2); tilt = 0.5
		&"death_fall": sc = Vector3(0.6, 1.5, 0.6); off.x = sin(t * 30.0) * 0.1 # flailing
		&"death_drown": sc = Vector3(1.0, 0.9, 1.0); tilt = 1.4 # limp, face up
		&"death_hit": sc = Vector3(1.3, 0.35, 1.3); tilt = -1.2 # collapse
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
	_visual.visible = invuln <= 0.0 or fmod(t, 0.1) < 0.05 # blink during i-frames
	var col := Color(0.35, 0.45, 0.85).lerp(Color(1.0, 0.75, 0.2), mood)
	_mat.albedo_color = col.darkened(0.6) if state_name == &"death" else col
