class_name Enemy
extends CharacterBody3D
## Enemy body, built like Player: one RefCounted script per state in res://enemy/states/,
## physics() returns the next state's name. Motion is split into vertical (up_direction) and
## planar, as on the player.
##
## A type is an inherited scene of res://enemy/enemy.tscn: it tunes the exports below and may
## replace any state in _init() (`states[&"pursuit"] = preload("my_pursuit.gd").new()`).
## Presentation reads `anim` (polled), `cue` (one-shot events) and `died`; see docs/enemies.md.
##
## ponytail: the motion helpers repeat Player's (about 40 lines) so the player stays untouched;
## move them to a shared base class once a third kind of body appears.

signal died(cause: StringName)
signal cue(name: StringName) ## one-shot presentation events (sound, VFX); gameplay never waits on them
signal puppet_arrived

enum Ability { JUMP = 1, DASH = 2, FLY = 4, RUN = 8, CLIMB = 16, SWIM = 32, SWING = 64 }

## ponytail: HALF_HEIGHT and HEAD are sized for the 1.6 m capsule (probe, water depth, jump solve);
## make them exports when an enemy of another size appears.
const HALF_HEIGHT := 0.8 ## body centre above the feet
const HEAD := 0.6 ## head above the body centre, for breathing
const KILL_DEPTH := 60.0 ## this far below its spawn point = death by fall (scenes without a Void)
const MIN_KNOCK := 1.0 ## knockback slower than this (m/s) doesn't move the enemy

@export_flags("Jump", "Dash", "Fly", "Run", "Climb", "Swim", "Swing") var abilities := 0
@export_group("Stats")
@export var max_health := 50.0
@export_range(0.0, 1.0) var armor := 0.0 ## fraction of incoming damage blocked
@export_range(0.1, 1000.0, 0.1, "or_greater") var weight := 5.0 ## knockback speed = push / weight
@export_range(1.0, 1000.0, 1.0, "or_greater") var max_stamina := 100.0
@export var stamina_regen := 25.0
@export var max_oxygen := 4.0 ## seconds of breath with the head under water
@export var oxygen_regen := 4.0
@export var attack_cooldown := 1.2
@export_range(0.0, 1.0) var base_mood := 0.6 ## starting aggression; mood drifts back to it
@export_range(0.0, 1.0) var flee_mood := 0.2 ## flees below this; 0 = never flees
@export var invuln_time := 0.3 ## hits are ignored this long after a hit
@export var hurt_time := 0.35
@export var stun_time := 2.0 ## stun when stamina runs out
@export var stun_on_hit := 0.0 ## seconds a hit stuns instead of hurting (flyers); 0 = never
@export_group("Senses")
@export var sight_radius := 10.0 ## the chase starts inside it
@export var lose_radius := 16.0 ## the chase ends outside it
@export var attack_range := 1.6
@export var give_up_time := 1.5 ## after giving up a chase, wait this long before chasing again
@export var memory_time := 3.0 ## seconds a player out of sight is still chased (toward where it was last seen)
@export_group("Ground")
@export var walk_speed := 3.0
@export var run_speed := 6.0
@export var accel := 40.0
@export var wind_response := 0.2 ## sideways wind becomes this fraction of drift speed, as Player's wind_response_ground
@export var safe_drop := 1.2 ## deepest drop it walks off
@export var gravity := 32.0
@export var max_fall_speed := 30.0
@export var fall_damage_speed := 18.0 ## landing faster than this costs health
@export var fall_damage := 2.0 ## health per m/s over fall_damage_speed
@export_group("Moves")
@export var jump_height := 1.8
@export var jump_reach := 4.0 ## longest jump on level ground, run-up from the probe point included
@export var dash_speed := 14.0
@export var dash_distance := 4.0
@export var climb_speed := 2.5
@export var swim_speed := 3.0
@export var fly_speed := 5.0
@export var hover_height := 2.5 ## flyers keep their feet this high above the ground
@export_group("Costs")
@export var run_cost := 20.0 ## stamina per second
@export var fly_cost := 10.0 ## stamina per second while chasing
@export var dash_cost := 25.0
@export var attack_cost := 15.0
@export_group("Attack")
@export var attack_damage := 10.0
@export var attack_windup := 0.35
@export var attack_recover := 0.4
@export var attack_reach := 1.8
@export_group("Areas")
@export var patrol_area: EnemyArea ## roams it while it hasn't spotted the player; may be shared
@export var chase_area: EnemyArea ## a leash: chases only inside it (its border is a ledge); may be shared
@export var patrol_pause := Vector2(1.0, 3.0) ## seconds of rest at each patrol spot (min, max)
@export var sleep_off_screen := true ## off screen: no thinking, physics only
@export var screen_margin := 4.0 ## metres around the body that still count as on screen
@export_group("Look")
@export var color := Color(0.85, 0.25, 0.2)
@export var show_debug := true ## state and stats on a label above the enemy

var health := 0.0
var stamina := 0.0
var oxygen := 0.0
var mood := 0.0
var invuln := 0.0
var attack_cd := 0.0
var give_up := 0.0 ## counts down after a chase was given up; no new chase until it's out
var stun_for := 0.0 ## duration of the next stun state
var goal: StringName = &"idle" ## the state a move (jump, dash, climb, swim, swing) returns to
var launch := Vector3.ZERO ## velocity the jump state starts with; zero = plain fall
var move_to := Vector3.ZERO ## a move's destination (landing spot, wall point...)
var swing_point: SwingPoint
var target: Player
var home := Vector3.ZERO ## spawn point
var facing := Vector3.FORWARD
var anim: StringName = &"idle"
var death_cause: StringName ## &"fall", &"drown", &"hit"
var env: EnvProfile ## every EnvZone the enemy is in, blended (EnvProfile.combine)
var water_zone: EnvZone
var puppet_target: Variant = null
var _envs: Array[EnvProfile] = []
var _drained := false ## stamina was spent since the last tick: no regen this tick
var _fall_speed := 0.0 ## fastest downward speed since leaving the floor
var _stuck := 0.0 ## fly_toward: seconds pressed against a wall at the height cap
var _anchor := Vector3.ZERO ## moving_on: where the enemy last got somewhere
var _still := 0.0 ## moving_on: seconds since then
var _excl: Array[RID] = [] ## cast's exclude list, rebuilt once per physics frame
var _excl_frame := -1
var _label: Label3D
var rng := RandomNumberGenerator.new() ## patrol picks; tests seed it

var states: Dictionary[StringName, EnemyState] = {
	&"idle": preload("states/idle.gd").new(),
	&"pursuit": preload("states/pursuit.gd").new(),
	&"attack": preload("states/attack.gd").new(),
	&"flee": preload("states/flee.gd").new(),
	&"hurt": preload("states/hurt.gd").new(),
	&"stun": preload("states/stun.gd").new(),
	&"jump": preload("states/jump.gd").new(),
	&"dash": preload("states/dash.gd").new(),
	&"climb": preload("states/climb.gd").new(),
	&"swim": preload("states/swim.gd").new(),
	&"swing": preload("states/swing.gd").new(),
	&"death": preload("states/death.gd").new(),
	&"puppet": preload("states/puppet.gd").new(),
}


## What the ground ahead looks like (see probe).
class Probe:
	var kind: StringName ## &"open", &"wall", &"gap", &"water"
	var height := 0.0 ## wall: its top above the feet; INF = taller than a jump could clear
	var climbable := false
	var point := Vector3.ZERO ## wall: the hit point; otherwise the probed edge point at feet height
	var normal := Vector3.ZERO ## wall normal
	var landing: Variant = null ## gap: a feet point on the far side, or null
var state: EnemyState
var state_name: StringName

@onready var _visual: Node3D = $Visual
@onready var _visual_base := _visual.position


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	oxygen = max_oxygen
	mood = base_mood
	home = global_position
	rng.randomize()
	add_to_group(&"enemy")
	env = EnvProfile.combine(EnvProfile.new(), _envs)
	var body := get_node_or_null(^"Visual/Body") as MeshInstance3D
	if body and body.material_override is StandardMaterial3D:
		(body.material_override as StandardMaterial3D).albedo_color = color
	if show_debug:
		_label = Label3D.new()
		_label.position = up_direction * 1.4
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.pixel_size = 0.004
		_label.font_size = 36
		_label.outline_size = 10
		add_child(_label)
	for s: EnemyState in states.values():
		s.e = self
	change_state(&"idle")


func change_state(next: StringName) -> void:
	if state:
		state.exit()
	var prev := state_name
	state_name = next
	state = states[next]
	state.enter(prev)


func _physics_process(delta: float) -> void:
	invuln -= delta
	attack_cd -= delta
	give_up -= delta
	_tick_stats(delta)
	if max_stamina > 0.0 and stamina <= 0.0 and state_name not in [&"stun", &"death", &"puppet"]:
		stun(stun_time) # exhausted: the timed opening
	var next := state.physics(delta)
	if next:
		change_state(next)
	_fall_damage()
	_orient(delta)
	_animate(delta)
	if _label:
		_label.text = debug_text()


func _tick_stats(delta: float) -> void:
	if not _drained:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
	_drained = false
	if state_name == &"death":
		return
	if water_depth() > HEAD:
		oxygen -= delta
		if oxygen <= 0.0:
			oxygen = 0.0
			die(&"drown")
			return
	else:
		oxygen = minf(oxygen + oxygen_regen * delta, max_oxygen)
	if state_name in [&"idle", &"flee", &"stun"]:
		mood = move_toward(mood, base_mood, 0.05 * delta)
	if (home - global_position).dot(up_direction) > KILL_DEPTH:
		die(&"fall")


func can(a: int) -> bool:
	return (abilities & a) != 0


# --- motion helpers (used by states) -------------------------------------------------

func vspeed() -> float:
	return velocity.dot(up_direction)


func planar() -> Vector3:
	return velocity - up_direction * vspeed()


func set_vspeed(v: float) -> void:
	velocity = planar() + up_direction * v


## Accelerates the planar velocity toward dir * speed (scaled by the env speed stat), plus the
## sideways wind's drift, as on the player.
func move_planar(dir: Vector3, speed: float, delta: float) -> void:
	if dir.length() > 0.1:
		facing = dir.normalized()
	var rate := accel * mult(&"traction")
	var drift := env.wind.slide(up_direction) * wind_response
	velocity = planar().move_toward(dir * speed * mult(&"speed") + drift, rate * delta) + up_direction * vspeed()


## Gravity (no fall multiplier, so solved jumps stay exact), wind lift and drag.
func apply_gravity(delta: float) -> void:
	var g := gravity * env.gravity_mult
	set_vspeed(maxf(vspeed() + (env.wind.dot(up_direction) - g) * delta, -max_fall_speed))
	velocity -= velocity * minf(env.drag * delta, 1.0)


## Stops in place. A flyer hovers at hover_height above the ground (or water), a swimmer floats up
## until its head is out; both without gravity. With `fall`, gravity always applies (stunned
## flyers drop).
func hold(delta: float, fall := false) -> void:
	if not fall and can(Ability.FLY):
		var alt := altitude()
		var vy := 0.0 if alt == INF else clampf((hover_height - alt) * 4.0, -fly_speed, fly_speed)
		velocity = planar().move_toward(Vector3.ZERO, accel * delta) + up_direction * move_toward(vspeed(), vy, 20.0 * delta)
	elif not fall and swimming():
		var rise := water_zone.surface_height(up_direction) - 0.3 - global_position.dot(up_direction) # head out: breathing
		var vy := clampf(rise * 2.0, -swim_speed, swim_speed * 0.5)
		velocity = planar().move_toward(Vector3.ZERO, 20.0 * delta) + up_direction * move_toward(vspeed(), vy, 20.0 * delta)
	else:
		move_planar(Vector3.ZERO, 0.0, delta)
		apply_gravity(delta)
	move_and_slide()


## Feet height above the ground below, or above the water over it (INF over a void).
func altitude() -> float:
	var up := up_direction
	var hit := cast(global_position, global_position - up * (hover_height + 10.0))
	if not hit:
		return INF
	var ground: float = (hit.position as Vector3).dot(up)
	var w := water_at(hit.position + up * 0.1)
	if w:
		ground = maxf(ground, w.surface_height(up))
	return global_position.dot(up) - HALF_HEIGHT - ground


## FLY: heads for `point` in 3D without gravity, at least hover_height above the ground below.
## A wall in the way: climbs straight up it, up to hover_height + 6 above the ground; pressed
## against a wall at that cap for 1 s -> &"blocked".
func fly_toward(point: Vector3, delta: float) -> StringName:
	var up := up_direction
	var cap := hover_height + 6.0
	var alt := altitude()
	var want := point
	if alt != INF:
		var ground := global_position.dot(up) - HALF_HEIGHT - alt
		var h := clampf(want.dot(up), ground + hover_height + HALF_HEIGHT, ground + cap + HALF_HEIGHT)
		want += up * (h - want.dot(up))
	face(want)
	var aim := (want - global_position).limit_length(1.0) * fly_speed
	if is_on_wall(): # keep a light push into the wall so the contact holds while climbing
		aim = (want - global_position).slide(up).limit_length(1.0) + up * (fly_speed if alt < cap else 0.0)
	velocity = velocity.move_toward(aim * mult(&"speed"), accel * delta)
	move_and_slide()
	anim = &"fly"
	_stuck = _stuck + delta if is_on_wall() and alt >= cap - 0.3 else 0.0
	if _stuck > 1.0:
		_stuck = 0.0
		return &"blocked"
	return &""


## A SWIM enemy with its body centre more than 0.2 m under the surface (floating with the head out
## counts): it swims instead of falling.
func swimming() -> bool:
	return can(Ability.SWIM) and water_depth() > 0.2


## A SWIM-only enemy lives in water and never leaves it: dry ground is a ledge to it.
func water_bound() -> bool:
	return abilities == Ability.SWIM


## A non-swimmer in deep water can't act: it flails and sinks (and drowns when its oxygen runs
## out). Idle, pursuit and flee call this first and do nothing else while it returns true.
func flail(delta: float) -> bool:
	if can(Ability.SWIM) or not deep_water():
		return false
	anim = &"flail"
	hold(delta, true)
	return true


func spend(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_drained = true


func face(point: Vector3) -> void:
	var f := (point - global_position).slide(up_direction)
	if f.length() > 0.01:
		facing = f.normalized()


# --- reading the ground (reactive traversal) ------------------------------------------

## One step toward `point`: moves when the ground ahead is open, hands off to a move state
## (returns its name, with `goal` set to the current state), or returns &"blocked".
func step_toward(point: Vector3, delta: float) -> StringName:
	if can(Ability.FLY):
		spend(fly_cost * delta)
		return fly_toward(point + up_direction * hover_height, delta)
	var to := (point - global_position).slide(up_direction)
	if to.length() < 0.05: # straight above or below: nothing to steer toward
		hold(delta)
		return &""
	var dir := to.normalized()
	var p := probe(dir)
	var up := up_direction
	var feet := global_position - up * HALF_HEIGHT
	match p.kind:
		&"open":
			if not water_bound() or water_at(p.point + up * 0.1):
				_walk(dir, delta)
				return &""
		&"water":
			if can(Ability.SWIM): # walk in; the states hand off to swim once it's deep
				_walk(dir, delta)
				return &""
		&"gap":
			if p.landing != null:
				var land: Vector3 = p.landing + dir * 0.4
				if can(Ability.JUMP):
					var v: Variant = solve_jump(land)
					if v != null:
						launch = v
						return _hand_off(&"jump")
				var rise := (land - feet).dot(up)
				if can(Ability.DASH) and rise >= -safe_drop and rise <= 0.3 and (land - feet).slide(up).length() <= dash_distance:
					move_to = land
					return _hand_off(&"dash")
			if can(Ability.SWING):
				var sp := _swing_point_ahead(dir, feet)
				if sp:
					var reach := (sp.global_position - global_position).slide(up).length()
					var far: Variant = find_landing(dir, 1.5, 2.0 * reach + 1.5)
					if far != null:
						swing_point = sp
						move_to = far + dir * 0.4
						return _hand_off(&"swing")
		&"wall":
			if can(Ability.CLIMB) and p.climbable and (point - feet).dot(up) > 0.5:
				move_to = p.point
				return _hand_off(&"climb")
			if can(Ability.JUMP) and p.height <= jump_height - 0.3:
				var top := p.point + dir * 0.6
				top += up * (feet.dot(up) + p.height - top.dot(up)) # raised to the wall's top
				var v: Variant = solve_jump(top)
				if v != null:
					launch = v
					return _hand_off(&"jump")
	facing = dir
	hold(delta)
	anim = &"blocked"
	return &"blocked"


func _walk(dir: Vector3, delta: float) -> void:
	var running := can(Ability.RUN)
	move_planar(dir, run_speed if running else walk_speed, delta)
	if running:
		spend(run_cost * delta)
	apply_gravity(delta)
	move_and_slide()
	anim = &"run" if running else &"walk"


## Nearest SwingPoint within its grab_radius, at least 1 m above the feet and ahead along `dir`.
func _swing_point_ahead(dir: Vector3, feet: Vector3) -> SwingPoint:
	var best: SwingPoint
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(&"swing_point"):
		var sp := n as SwingPoint
		var off := sp.global_position - global_position
		var ahead := off.slide(up_direction).dot(dir) > 0.0
		if ahead and off.length() < minf(sp.grab_radius, best_d) and (sp.global_position - feet).dot(up_direction) > 1.0:
			best = sp
			best_d = off.length()
	return best


## Hands off to a move state, which returns to the current state when it ends.
func _hand_off(move: StringName) -> StringName:
	goal = state_name
	return move


## Launch velocity of a ballistic arc from the body centre to the feet point `to`, peaking `h`
## above the start, under plain gravity (launched jumps ignore the environment, see the jump
## state). The caller keeps h at least 0.3 above the rise.
func arc_to(to: Vector3, h: float) -> Vector3:
	var d := to + up_direction * HALF_HEIGHT - global_position
	var rise := d.dot(up_direction)
	var vy := sqrt(2.0 * gravity * h)
	var t := vy / gravity + sqrt(2.0 * maxf(h - rise, 0.0) / gravity)
	return d.slide(up_direction) / t + up_direction * vy


## A full-height jump to the feet point `to`, or null when it's too high or beyond jump_reach.
func solve_jump(to: Vector3) -> Variant:
	var rise := (to + up_direction * HALF_HEIGHT - global_position).dot(up_direction)
	if rise + 0.3 > jump_height:
		return null
	var v := arc_to(to, jump_height)
	var max_flat := jump_reach / (2.0 * sqrt(2.0 * gravity * jump_height) / gravity) # covers jump_reach on level ground
	return null if v.slide(up_direction).length() > max_flat else v


## ponytail: a few rays and a test per enemy per physics frame (the exclude list is cached per
## frame); throttle probing if a scene holds many more than tens of enemies.
## Looks just past the body's edge along `dir` (planar, normalized). Rays skip the player and
## every enemy: they're bodies to bump into or attack, not terrain.
## CSG collision is a hollow trimesh, so rays ignore back faces (a ray starting inside a block
## passes out of it) and a wall's height is bounded by a ray at jump height, not a point query.
func probe(dir: Vector3) -> Probe:
	var p := Probe.new()
	var up := up_direction
	var feet := global_position - up * HALF_HEIGHT
	var v := planar().length()
	var grip := maxf(accel * mult(&"traction"), 1.0)
	# on slippery ground stopping takes longer: look ahead by the extra braking distance
	var look := 0.6 + v * 0.1 + maxf(0.0, v * v * (0.5 / grip - 0.5 / accel))
	var reach := 0.4 + look
	for h: float in [0.3, HALF_HEIGHT]: # knees, chest
		var hit := cast(feet + up * h, feet + up * h + dir * reach)
		if hit and (hit.normal as Vector3).dot(up) < 0.7:
			p.kind = &"wall"
			p.point = hit.position
			p.normal = hit.normal
			p.climbable = (hit.collider as Node).is_in_group(&"climbable")
			p.height = _wall_height(feet, dir, reach)
			return p
	var edge := feet + dir * reach
	p.point = edge
	var ground := cast(edge + up * 0.5, edge - up * (safe_drop + 0.05))
	if ground:
		p.kind = &"water" if deep_water_at(ground.position) else &"open"
		return p
	if water_at(edge - up * 0.5):
		p.kind = &"water"
		return p
	p.kind = &"gap"
	p.landing = find_landing(dir, reach + 0.5, maxf(jump_reach, dash_distance))
	return p


## First ground point, sampled every 0.5 m from `near` to `far` along `dir`, that isn't under
## deep water; null if none.
func find_landing(dir: Vector3, near: float, far: float) -> Variant:
	var up := up_direction
	var feet := global_position - up * HALF_HEIGHT
	var d := near
	while d <= far:
		var at := feet + dir * d
		var hit := cast(at + up * (jump_height + 0.3), at - up * safe_drop)
		if hit and not deep_water_at(hit.position):
			return hit.position
		d += 0.5
	return null


## Deep water over this ground point: an enemy standing there would have its head under.
func deep_water_at(ground: Vector3) -> bool:
	var w := water_at(ground + up_direction * 0.1)
	return w != null and w.surface_height(up_direction) - ground.dot(up_direction) > HALF_HEIGHT + HEAD


## The water EnvZone containing `point`, or null.
func water_at(point: Vector3) -> EnvZone:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = point
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r: Dictionary in get_world_3d().direct_space_state.intersect_point(q, 8):
		var z := r.collider as EnvZone
		if z and z.profile and z.profile.water:
			return z
	return null


## Top of the wall ahead above the feet; INF when a ray at jump height still hits it.
func _wall_height(feet: Vector3, dir: Vector3, reach: float) -> float:
	var up := up_direction
	var high := feet + up * (jump_height + 0.5)
	if cast(high, high + dir * (reach + 0.15)):
		return INF
	var top := cast(high + dir * (reach + 0.15), feet - up * 0.1 + dir * (reach + 0.15))
	return (top.position - feet).dot(up) if top else INF


## Room for the body with its centre at `center`: nothing solid overlaps it, the player and other
## enemies included. CSG blocks are hollow, so a body fully inside one isn't caught here.
func fits_at(center: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = (get_node(^"Collision") as CollisionShape3D).shape
	q.transform = Transform3D(global_basis.orthonormalized(), center)
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## A ray that skips the player and every enemy and ignores back faces (see probe).
func cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, _exclude())
	q.hit_back_faces = false
	return get_world_3d().direct_space_state.intersect_ray(q)


func _exclude() -> Array[RID]:
	if _excl_frame != Engine.get_physics_frames():
		_excl_frame = Engine.get_physics_frames()
		_excl = [get_rid()]
		for group: StringName in [&"enemy", &"player"]:
			for n: Node in get_tree().get_nodes_in_group(group):
				if n is CollisionObject3D:
					_excl.append((n as CollisionObject3D).get_rid())
	return _excl


# --- environment ---------------------------------------------------------------------

## Multiplier for a StatMods stat from the environment: 1 + env% (enemies have no progression).
func mult(stat: StringName) -> float:
	return maxf(0.0, 1.0 + env.mods.get(stat))


## Called by EnvZones on enter/exit, as for the player.
func add_env(e: EnvProfile) -> void:
	_envs.append(e)
	env = EnvProfile.combine(EnvProfile.new(), _envs)


func remove_env(e: EnvProfile) -> void:
	_envs.erase(e)
	env = EnvProfile.combine(EnvProfile.new(), _envs)


## Distance of the body centre below the water surface. -INF when not in water.
func water_depth() -> float:
	if water_zone == null:
		return -INF
	return water_zone.surface_height(up_direction) - global_position.dot(up_direction)


## Head under water.
func deep_water() -> bool:
	return water_depth() > HEAD


# --- target --------------------------------------------------------------------------

## The player, while it can be chased (not dead, not in a cutscene).
func has_target() -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		target = get_tree().get_first_node_in_group(&"player") as Player
	return target != null and target.state_name not in [&"death", &"puppet"]


func target_pos() -> Vector3:
	return target.global_position


func dist_to_target() -> float:
	return global_position.distance_to(target.global_position)


## Where the enemy attacks from: the target itself, or for a flyer the point hover_height above
## it (flyers strike down from their hover point; a type can replace `attack` with a swoop).
func attack_point() -> Vector3:
	return target_pos() + up_direction * hover_height if can(Ability.FLY) else target_pos()


func in_attack_range() -> bool:
	return global_position.distance_to(attack_point()) <= attack_range


## Chase watchdog for what the probe can't see (a curb under the knee ray, a beam over the chest
## ray, a bank too high to leap): false once the enemy has been trying to move for 1.5 s without
## getting 0.3 m anywhere. Measures the enemy's own motion, so a target running away at the same
## speed doesn't trip it. Chasing states call reset_watchdog() on enter.
func moving_on(delta: float) -> bool:
	if global_position.distance_to(_anchor) > 0.3:
		_anchor = global_position
		_still = 0.0
	else:
		_still += delta
	return _still < 1.5


func reset_watchdog() -> void:
	_anchor = global_position
	_still = 0.0


# --- damage, stun, death -------------------------------------------------------------

## The way anything hurts an enemy. Damage is reduced by armor; knockback is push / weight away
## from `from`. Under MIN_KNOCK the hit is only a flinch (the hurt cue): the enemy carries on, so
## heavy enemies can't be stun-locked. Ignored while dead, in puppet, or for invuln_time after a
## hit. A running stun keeps going: it's the player's opening. stun_on_hit > 0 stuns instead of
## hurting (shoot a flyer down, then melee it).
## Returns whether the hit landed.
func hit(damage: float, push: float, from: Vector3) -> bool:
	if state_name in [&"death", &"puppet"] or invuln > 0.0:
		return false
	invuln = invuln_time
	health -= damage * (1.0 - armor)
	mood = maxf(mood - 0.15, 0.0)
	cue.emit(&"hurt")
	if health <= 0.0:
		die(&"hit")
		return true
	var knock := push / maxf(weight, 0.1)
	if knock >= MIN_KNOCK:
		var away := (global_position - from).slide(up_direction)
		away = away.normalized() if away.length() > 0.01 else -facing
		velocity = away * knock + up_direction * knock * 0.4
	if state_name == &"stun":
		return true
	if stun_on_hit > 0.0:
		stun(stun_on_hit)
	elif knock >= MIN_KNOCK:
		change_state(&"hurt")
	return true


## For callers outside a state's physics (hits, level scripts). Inside a state, set stun_for and
## return &"stun" instead.
func stun(seconds: float) -> void:
	if state_name in [&"death", &"puppet"]:
		return
	stun_for = seconds
	change_state(&"stun")



## Cinematic control: ignores the AI, the player, damage and ledges. With `at`, walks there and
## emits puppet_arrived.
func start_puppet(at: Variant = null) -> void:
	if state_name == &"death":
		return
	puppet_target = at
	change_state(&"puppet")


func end_puppet() -> void:
	if state_name == &"puppet":
		change_state(&"idle")


## cause: &"fall" (pits, the void), &"drown" (out of oxygen), &"hit" (health 0).
## The body drops out of collision (layer 0, mask kept so it still lands) and frees itself
## after the death state.
func die(cause: StringName) -> void:
	if state_name == &"death":
		return
	death_cause = cause
	health = 0.0
	change_state(&"death") # first: a state's exit() (a burrower surfacing) can't undo what follows, and a listener re-entering die() finds it dead
	collision_layer = 0
	cue.emit(&"death")
	died.emit(cause)


## Landing faster than fall_damage_speed costs health.
func _fall_damage() -> void:
	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, -vspeed())
		return
	if _fall_speed > fall_damage_speed and state_name != &"death":
		health -= (_fall_speed - fall_damage_speed) * fall_damage
		if health <= 0.0:
			die(&"fall")
	_fall_speed = 0.0


func debug_text() -> String:
	return "%s\nhp %d  st %d\nmood %.2f  o2 %.1f" % [state_name, health, stamina, mood, oxygen]


# --- presentation --------------------------------------------------------------------

func _orient(delta: float) -> void:
	var f := facing.slide(up_direction)
	if f.length() < 0.01:
		return
	facing = f.normalized()
	var look := Basis.looking_at(facing, up_direction)
	global_basis = global_basis.slerp(look, 1.0 - exp(-12.0 * delta)).orthonormalized()


## Placeholder "animation" on the capsule so states are visible.
## ponytail: procedural squash/tilt stand-in; replace with an AnimationTree keyed on `anim`
## (docs/enemies.md).
func _animate(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var sc := Vector3.ONE
	var off := 0.0
	var tilt := 0.0
	match anim:
		&"walk": off = absf(sin(t * 10.0)) * 0.05
		&"run", &"flee": off = absf(sin(t * 14.0)) * 0.08; tilt = -0.25
		&"jump": sc = Vector3(0.85, 1.2, 0.85)
		&"fall": sc = Vector3(0.95, 1.08, 0.95)
		&"dash": sc = Vector3(0.7, 0.7, 1.6)
		&"climb": off = sin(t * 8.0) * 0.08
		&"swim": tilt = -0.9; off = sin(t * 4.0) * 0.06
		&"flail": tilt = -0.6; off = sin(t * 30.0) * 0.1
		&"swing": tilt = 0.4
		&"fly": off = sin(t * 6.0) * 0.1
		&"attack_windup": sc = Vector3(1.1, 0.85, 1.1); tilt = 0.3
		&"attack": sc = Vector3(0.9, 1.0, 1.4); tilt = -0.5
		&"attack_recover": tilt = -0.2
		&"hurt": sc = Vector3(1.2, 0.75, 1.2); tilt = 0.5
		&"stun": sc = Vector3(1.1, 0.7, 1.1); tilt = sin(t * 3.0) * 0.2
		&"cower": sc = Vector3(1.1, 0.7, 1.1); tilt = 0.3
		&"blocked": tilt = sin(t * 4.0) * 0.15
		&"burrow_in", &"surface": sc = Vector3(1.25, 0.6, 1.25)
		&"death_fall": sc = Vector3(0.6, 1.5, 0.6)
		&"death_drown": tilt = 1.4
		&"death_hit": sc = Vector3(1.3, 0.35, 1.3); tilt = -1.2
	var k := 1.0 - exp(-15.0 * delta)
	_visual.position = _visual_base + up_direction * off
	_visual.scale = _visual.scale.lerp(sc, k)
	_visual.rotation.x = lerpf(_visual.rotation.x, tilt, k)
