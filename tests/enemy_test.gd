extends SceneTree
## Headless suite for the enemy system (enemy/, the player's attacks, projectiles).
## Run: Godot_console.exe --headless --path . -s res://tests/enemy_test.gd
## Each section builds its own small course in code (see _course) so tests don't depend on
## the demo layout.

const SECTIONS := 1
const ENEMY := preload("res://enemy/enemy.tscn")
const PLAYER := preload("res://player/player.tscn")

var fails := 0
var sections := 0
var course: Node3D
var player: Player


func _initialize() -> void:
	_run()


func _run() -> void:
	await _test_core()
	_check(sections == SECTIONS, "all %d sections ran (%d)" % [SECTIONS, sections])
	print("ENEMIES: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _test_core() -> void:
	_course()
	var e := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0})
	await _wait(30)
	_check(e.state_name == &"idle" and e.is_on_floor(), "enemy settles idle on the floor")
	_check(e.health == e.max_health and e.stamina == e.max_stamina and e.oxygen == e.max_oxygen and e.mood == e.base_mood, "stats start full")
	_check(e.is_in_group(&"enemy") and player.is_in_group(&"player") and e.has_target() and e.target == player, "groups; the player is the target")
	var mud := EnvProfile.new()
	mud.mods.speed = -0.5
	e.add_env(mud)
	_check(is_equal_approx(e.mult(&"speed"), 0.5), "env stat mods reach enemies")
	e.remove_env(mud)

	_kill(Vector3(10, 0.5, 0), Vector3(3, 1, 3))
	var faller := _enemy(Vector3(10, 4, 0), {sight_radius = 0.0})
	var causes := _deaths(faller)
	var seen := await _watch([faller], 10)
	_check(&"jump" in seen, "airborne enemies are in the jump state")
	_check(await _gone(faller, 240) and causes == [&"fall"], "kill zone: death by fall, then freed")

	_water(Vector3(-10, 1.5, 0), Vector3(4, 3, 4))
	var sinker := _enemy(Vector3(-10, 1, 0), {sight_radius = 0.0, max_oxygen = 1.0})
	causes = _deaths(sinker)
	await _wait(10)
	_check(sinker.anim == &"flail" and sinker.oxygen < sinker.max_oxygen, "non-swimmer in deep water flails, oxygen drains")
	_check(await _gone(sinker, 300) and causes == [&"drown"], "non-swimmer drowns")

	var lost := _enemy(Vector3(20, 1, 0), {sight_radius = 0.0})
	causes = _deaths(lost)
	await _wait(5)
	lost.global_position = lost.home - Vector3(0, Enemy.KILL_DEPTH + 1.0, 0)
	await _wait(3)
	_check(causes == [&"fall"], "60 m below its spawn = death by fall")
	sections += 1


# --- course building ---------------------------------------------------------------

## Replaces the course: a void kill zone, an optional 80x30 floor (top y = 0), a pad under
## the player and the player itself.
func _course(player_at := Vector3(-30, 1, 0), with_floor := true) -> void:
	if course:
		root.remove_child(course) # out of the tree now: the old player leaves its group at once
		course.queue_free()
	course = Node3D.new()
	root.add_child(course)
	_kill(Vector3(0, -15, 0), Vector3(200, 2, 200))
	if with_floor:
		_box(Vector3(0, -0.5, 0), Vector3(80, 1, 30))
	_box(player_at - Vector3(0, 1.5, 0), Vector3(4, 1, 4))
	player = PLAYER.instantiate()
	player.position = player_at
	course.add_child(player)


func _box(at: Vector3, size: Vector3, climbable := false) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = at
	b.use_collision = true
	if climbable:
		b.add_to_group(&"climbable")
	course.add_child(b)
	return b


func _water(at: Vector3, size: Vector3) -> EnvZone:
	var z := EnvZone.new()
	z.profile = EnvProfile.new()
	z.profile.resource_name = "Water"
	z.profile.water = true
	z.profile.gravity_mult = 0.3
	z.profile.drag = 1.2
	z.position = at
	course.add_child(z)
	var box := BoxShape3D.new()
	box.size = size
	z.add_shape(box)
	return z


func _kill(at: Vector3, size: Vector3) -> KillZone:
	var z := KillZone.new()
	z.position = at
	course.add_child(z)
	var box := BoxShape3D.new()
	box.size = size
	z.add_shape(box)
	return z


## Props are set before the enemy enters the tree, so its _ready sees them.
func _enemy(at: Vector3, props := {}, scene: PackedScene = ENEMY) -> Enemy:
	var e: Enemy = scene.instantiate()
	e.show_debug = false
	for k: String in props:
		e.set(k, props[k])
	e.position = at
	course.add_child(e)
	return e


# --- waiting and checking -----------------------------------------------------------

func _deaths(e: Enemy) -> Array:
	var out := []
	e.died.connect(func(cause: StringName) -> void: out.append(cause))
	return out


func _gone(o: Object, frames: int) -> bool:
	var id := o.get_instance_id() # capturing `o` itself errors once it's freed
	return await _wait_until(func() -> bool: return not is_instance_id_valid(id), frames)


## Distinct states the enemies pass through, in order of first appearance.
func _watch(enemies: Array, frames: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in frames:
		await physics_frame
		for e: Variant in enemies:
			if is_instance_valid(e) and e.state_name not in out:
				out.append(e.state_name)
	return out


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _wait_until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
