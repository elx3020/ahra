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

const HALF_HEIGHT := 0.8 ## body centre above the feet
const HEAD := 0.6 ## head above the body centre, for breathing
const KILL_DEPTH := 60.0 ## this far below its spawn point = death by fall (scenes without a Void)
const MIN_KNOCK := 1.0 ## knockback slower than this (m/s) doesn't move the enemy

@export_flags("Jump", "Dash", "Fly", "Run", "Climb", "Swim", "Swing") var abilities := 0
@export_group("Stats")
@export var max_health := 50.0
@export_range(0.0, 1.0) var armor := 0.0 ## fraction of incoming damage blocked
@export var weight := 5.0 ## knockback speed = push / weight
@export var max_stamina := 100.0
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
@export_group("Ground")
@export var walk_speed := 3.0
@export var run_speed := 6.0
@export var accel := 40.0
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
var _label: Label3D

var states: Dictionary[StringName, EnemyState] = {
	&"idle": preload("states/idle.gd").new(),
	&"jump": preload("states/jump.gd").new(),
	&"death": preload("states/death.gd").new(),
}
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
	var next := state.physics(delta)
	if next:
		change_state(next)
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


## Accelerates the planar velocity toward dir * speed (scaled by the env speed stat).
func move_planar(dir: Vector3, speed: float, delta: float) -> void:
	if dir.length() > 0.1:
		facing = dir.normalized()
	var rate := accel * mult(&"traction")
	velocity = planar().move_toward(dir * speed * mult(&"speed"), rate * delta) + up_direction * vspeed()


## Gravity (no fall multiplier, so solved jumps stay exact), wind lift and drag.
func apply_gravity(delta: float) -> void:
	var g := gravity * env.gravity_mult
	set_vspeed(maxf(vspeed() + (env.wind.dot(up_direction) - g) * delta, -max_fall_speed))
	velocity -= velocity * minf(env.drag * delta, 1.0)


## Stops in place. With `fall`, gravity always applies.
func hold(delta: float, _fall := false) -> void:
	move_planar(Vector3.ZERO, 0.0, delta)
	apply_gravity(delta)
	move_and_slide()


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


# --- damage, death -------------------------------------------------------------------

## cause: &"fall" (pits, the void), &"drown" (out of oxygen), &"hit" (health 0).
## The body drops out of collision (layer 0, mask kept so it still lands) and frees itself
## after the death state.
func die(cause: StringName) -> void:
	if state_name == &"death":
		return
	death_cause = cause
	health = 0.0
	collision_layer = 0
	cue.emit(&"death")
	died.emit(cause)
	change_state(&"death")


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
