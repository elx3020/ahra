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
signal cue(name: StringName) ## one-shot presentation events: lift, put_down, throw, blocked (no room to put down)

const HEAD := 0.8 ## head height above the body center, for breathing checks
const PROJECTILE := preload("res://world/projectile.tscn")
const SHOOT_STATES: Array[StringName] = [&"idle", &"walk", &"run", &"jump", &"swim"]

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
## ponytail: placeholder combat (one melee swing, one straight shot); the combat system comes later.
@export_group("Attack")
@export var melee_damage := 10.0
@export var melee_push := 24.0 ## knockback impulse: an enemy flies back at push / weight
@export var melee_time := 0.3
@export var melee_cooldown := 0.4
@export var melee_reach := 1.0 ## centre of the hit sphere, in front of the player
@export var melee_radius := 0.9
@export var shoot_damage := 5.0
@export var shoot_push := 6.0
@export var shoot_speed := 30.0
@export var shoot_cooldown := 0.35
@export var shoot_range := 20.0 ## aim assist reach
@export_group("Carry")
@export var carry_reach := 1.2 ## a weight within this (and 60 degrees of facing) can be lifted; put down this far in front
@export var carry_cost := 6.0 ## stamina/s per 10 weight while carrying
@export var carry_slow := 0.03 ## walk speed x 1 / (1 + weight * carry_slow) while carrying
@export var throw_speed := 12.0 ## x clamp(10 / weight, 0.3, 1.5)
@export var hold_height := 1.5 ## carried weight's centre above the body centre
@export var push_strength := 6.0 ## walking into a weight pushes it at walk speed * push_strength / weight (at most x1)
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
var interactable: Interactable ## what interact reaches: the nearest usable zone, picked each physics frame
var interactables: Array[Interactable] = [] ## every Interactable zone the player stands in
var _released := -1 ## physics frame end_puppet() ran: the press that ended a talk reaches nothing else
var swing_point: SwingPoint
var puppet_target: Variant = null
var air_speed := 0.0
var air_dashes_left := 0
var coyote := 0.0
var jump_buffer := 0.0
var variable_jump := false ## set by do_jump: only real jumps get cut short on release
var launched := false ## slingshot release: ignores drag (water) until the apex
var floor_velocity := Vector3.ZERO ## velocity of the moving platform under the player (last frame)
var carry := Vector3.ZERO ## platform velocity kept after jumping/walking off it (air drift, like wind)
var dash_cd := 0.0
var melee_cd := 0.0
var shoot_cd := 0.0
var _attacks: Array[bool] = []
var held: WeightBody ## the weight being carried (frozen, collision off, over the head)
var _held_layers := Vector2i.ZERO ## its collision layer and mask, restored on release

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
	&"melee": preload("states/melee.gd").new(),
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
	add_to_group(&"player") # enemies find their target through this group
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING # the jump state carries it instead (see carry)
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
	melee_cd -= delta
	shoot_cd -= delta
	invuln -= delta
	_tick_stats(delta)
	if Input.is_action_just_pressed(&"shoot") and shoot_cd <= 0.0 and state_name in SHOOT_STATES and held == null:
		shoot()

	if Input.is_action_just_pressed(&"carry"):
		if held:
			put_down()
		else:
			lift()
	elif held and Input.is_action_just_pressed(&"throw"):
		throw_held()

	interactable = _pick_interactable()
	if state_name == &"puppet": # held by a talk or a cutscene: nothing else answers interact
		interactable = null
	var next := state.physics(delta)
	WeightBody.push_from(self, push_strength, walk_speed)
	if next:
		change_state(next)
	floor_velocity = get_platform_velocity() if is_on_floor() else Vector3.ZERO
	_hold()
	_orient(delta)
	_animate(delta)


## The nearest zone in `interactables` that can_interact(), or null. Freed zones (gone without
## an exit signal) are dropped first: a typed array can't erase a freed object.
func _pick_interactable() -> Interactable:
	interactables.assign(interactables.filter(func(z: Variant) -> bool: return is_instance_valid(z)))
	var best: Interactable = null
	var best_d := INF
	for z in interactables:
		var d := global_position.distance_squared_to(z.global_position)
		if d < best_d and z.can_interact():
			best = z
			best_d = d
	return best


func _tick_stats(delta: float) -> void:
	if held != null and not is_instance_valid(held):
		held = null # freed by other code while carried
	if held:
		stamina -= carry_cost * held.weight / 10.0 * mult(&"stamina_cost") * delta
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
			exhaust_t = exhaust_time
			drop_held()
	elif state_name != &"run":
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
	return CameraShake.steady(cam.global_basis) if cam else Basis.IDENTITY # without the shake's roll


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
	return Input.is_action_pressed(&"run") and not exhausted and held == null


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
	move_planar(dir, speed * mult(&"speed") * carry_factor(), rate, delta, wind_drift(wind_response_ground))


func move_air(dir: Vector3, delta: float) -> void:
	move_planar(dir, air_speed, air_accel if dir != Vector3.ZERO else air_decel, delta, wind_drift(wind_response_air) + carry)


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
	if Input.is_action_just_pressed(&"dash") and dash_cd <= 0.0 and held == null:
		return &"dash"
	if Input.is_action_just_pressed(&"attack") and melee_cd <= 0.0 and held == null:
		return &"melee"
	if interactable and Input.is_action_just_pressed(&"interact") and Engine.get_physics_frames() > _released:
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
	if held or not is_on_wall() or move_input().dot(-get_wall_normal()) < 0.3:
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


# --- attacks -------------------------------------------------------------------

## The melee swing's hit check: every enemy in a sphere in front. Returns how many hits landed.
func melee_hit() -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = melee_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, global_position + facing * melee_reach)
	q.exclude = [get_rid()]
	var seen: Array[Enemy] = []
	var landed := 0
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var e := r.collider as Enemy
		if e and e not in seen:
			seen.append(e)
			if e.hit(melee_damage, melee_push, global_position):
				landed += 1
	return landed


## Fires a Projectile from the chest along aim_dir().
func shoot() -> Projectile:
	shoot_cd = shoot_cooldown
	var b: Projectile = PROJECTILE.instantiate()
	b.speed = shoot_speed
	get_parent().add_child(b)
	b.setup(global_position + up_direction * 0.3 + facing * 0.6, aim_dir(), shoot_damage, shoot_push, self)
	return b


## The facing, or toward the nearest enemy within shoot_range and 25 degrees of it that a shot
## can hit: in sight, not underground (no collision layer), dead or in a cutscene (aim assist, so
## shots don't sail over or under enemies on iso terrain).
func aim_dir() -> Vector3:
	var from := global_position + up_direction * 0.3
	var best := facing
	var best_d := shoot_range
	for n: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Enemy
		var to := e.global_position - from
		if e.collision_layer == 0 or e.state_name in [&"death", &"puppet"]:
			continue
		if to.length() < best_d and facing.angle_to(to.slide(up_direction)) <= deg_to_rad(25.0) \
				and e.cast(from, e.global_position).is_empty(): # cast skips bodies: terrain in the way
			best = to.normalized()
			best_d = to.length()
	var space := get_world_3d().direct_space_state
	for n: Node in get_tree().get_nodes_in_group(&"aim_target"): # energy switches
		var t := n as Node3D
		var to := t.global_position - from
		if to.length() < best_d and facing.angle_to(to.slide(up_direction)) <= deg_to_rad(25.0):
			var ray := PhysicsRayQueryParameters3D.create(from, t.global_position, 0xFFFFFFFF, [get_rid()])
			if space.intersect_ray(ray).get("collider") == t: # in sight
				best = to.normalized()
				best_d = to.length()
	return best


# --- carrying weights ---------------------------------------------------------

## The weight `carry` would lift: the nearest one within reach and 60 degrees of facing, about
## level with the player and in sight (not through a door), not carried and not the one under the
## player's feet.
func weight_in_reach() -> WeightBody:
	var under := []
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(up_direction) > 0.7:
			under.append(c.get_collider())
	var best: WeightBody
	var best_d := carry_reach + 0.25
	for n: Node in get_tree().get_nodes_in_group(&"weight"):
		var w := n as WeightBody
		if w == null or w.carrier != null or w.gone or w in under:
			continue
		var to := w.global_position - global_position
		var flat := to.slide(up_direction)
		if flat.length() <= best_d and absf(to.dot(up_direction)) < 1.2 and flat.length() > 0.05 				and facing.angle_to(flat) <= deg_to_rad(60.0):
			var sight := PhysicsRayQueryParameters3D.create(global_position + up_direction * 0.3, w.global_position, 0xFFFFFFFF, [get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(sight).get("collider") == w: # not through a door or a wall
				best = w
				best_d = flat.length()
	return best


## Picks up the weight in reach (from the ground states, not while exhausted).
func lift() -> bool:
	if held or exhausted or state_name not in [&"idle", &"walk", &"run"]:
		return false
	var w := weight_in_reach()
	if w == null:
		return false
	held = w
	w.carrier = self
	_held_layers = Vector2i(w.collision_layer, w.collision_mask)
	w.collision_layer = 0
	w.collision_mask = 0
	w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	w.freeze = true
	cue.emit(&"lift")
	return true


## Sets the carried weight down on the ground carry_reach in front. False (and a `blocked` cue)
## when it doesn't fit there.
func put_down() -> bool:
	if held == null:
		return false
	var half := ShapeSet.bounds(held).size.y * 0.5
	var spot := global_position + facing * carry_reach
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(spot + up_direction * 1.0, spot - up_direction * 3.0, _held_layers.y, [get_rid()])
	var ground := space.intersect_ray(ray)
	if ground:
		spot = ground.position + up_direction * (half + 0.02)
	var at := Transform3D(global_basis, spot)
	# a wall between the player and the spot: CSG collision is a hollow trimesh, so a shape whose
	# centre ends up inside a wall overlaps none of its (front) faces; the line from here catches it
	var line := PhysicsRayQueryParameters3D.create(global_position, spot, _held_layers.y, [get_rid()])
	if space.intersect_ray(line):
		cue.emit(&"blocked")
		return false
	for cs in ShapeSet.of(held):
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = at * cs.transform
		q.collision_mask = _held_layers.y
		q.exclude = [get_rid()]
		if not space.intersect_shape(q, 1).is_empty():
			cue.emit(&"blocked")
			return false
	_release(at, Vector3.ZERO)
	cue.emit(&"put_down")
	return true


## Throws the carried weight forward and up; lighter ones fly farther.
func throw_held() -> void:
	if held == null:
		return
	var v := (facing + up_direction * 0.5).normalized() * throw_speed * clampf(10.0 / held.weight, 0.3, 1.5) + planar()
	_release(held.global_transform, v)
	cue.emit(&"throw")


## Lets go of the carried weight where it is, with the player's velocity (hurt, death, water...).
func drop_held() -> void:
	if held != null and not is_instance_valid(held):
		held = null
	if held:
		_release(held.global_transform, velocity)


## Walk speed multiplier while carrying: heavier is slower.
func carry_factor() -> float:
	return 1.0 / (1.0 + held.weight * carry_slow) if held else 1.0


## Keeps the carried weight over the head; it takes the player's gravity when let go.
func _hold() -> void:
	if held != null and not is_instance_valid(held):
		held = null
	if held:
		held.global_transform = Transform3D(global_basis, global_position + up_direction * hold_height)
	if state_name == &"walk":
		anim = &"carry_walk" if held else &"walk"
	elif state_name == &"idle" and held:
		anim = &"carry_idle"


func _release(at: Transform3D, v: Vector3) -> void:
	var w := held
	held = null
	w.carrier = null
	w.global_transform = at
	w.collision_layer = _held_layers.x
	w.collision_mask = _held_layers.y
	w.freeze = false
	w.set_gravity_dir(gravity_dir)
	w.linear_velocity = v
	w.angular_velocity = Vector3.ZERO
	w.reset_physics_interpolation()


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
		_released = Engine.get_physics_frames()


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
	drop_held()
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
	drop_held()
	death_cause = cause
	health = 0.0
	change_state(&"death")


## Back to life at `at` (default: checkpoint) with full health/stamina/oxygen.
func respawn(at: Variant = null) -> void:
	set_gravity_dir(Vector3.DOWN)
	velocity = Vector3.ZERO
	floor_velocity = Vector3.ZERO # don't inherit the last platform's motion
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
		&"melee": sc = Vector3(1.15, 0.9, 1.15); tilt = -0.5
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
	if ProjectSettings.get_setting("ahra/animation/disable_squash_tilt", false):
		sc = Vector3.ONE; off = Vector3.ZERO; tilt = 0.0
	var k := 1.0 - exp(-15.0 * delta)
	_visual.position = _visual_base + off
	_visual.scale = _visual.scale.lerp(sc, k)
	_visual.rotation.x = lerpf(_visual.rotation.x, tilt, k)
	_visual.visible = invuln <= 0.0 or fmod(t, 0.1) < 0.05 # blink during i-frames
	var col := Color(0.35, 0.45, 0.85).lerp(Color(1.0, 0.75, 0.2), mood)
	_mat.albedo_color = col.darkened(0.6) if state_name == &"death" else col
