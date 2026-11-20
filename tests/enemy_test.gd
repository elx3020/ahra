extends SceneTree
## Headless suite for the enemy system (enemy/, the player's attacks, projectiles).
## Run: Godot_console.exe --headless --path . -s res://tests/enemy_test.gd
## Each section builds its own small course in code (see _course) so tests don't depend on
## the demo layout.

const SECTIONS := 3
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
	await _test_pursuit()
	await _test_combat()
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


func _far_side(kind: String) -> void: # home plateau ends at x = 0; the player waits at x = 10
	match kind:
		"gap": _box(Vector3(10, -0.5, 0), Vector3(12, 1, 10)) # 4 m gap
		"wall":
			_box(Vector3(8, -0.5, 0), Vector3(16, 1, 10))
			_box(Vector3(2, 1.5, 0), Vector3(1, 3, 10)) # 3 m wall
		"water":
			_box(Vector3(8, -0.5, 0), Vector3(16, 1, 10))
			_water(Vector3(3, 1.5, 0), Vector3(4, 3, 10)) # 3 m deep over the floor
		"cliff": _box(Vector3(8, -2.5, 0), Vector3(16, 1, 10)) # 2 m drop, beyond safe_drop
		"step": _box(Vector3(8, -1.5, 0), Vector3(16, 1, 10)) # 1 m drop, within safe_drop


func _test_pursuit() -> void:
	_course(Vector3(-30, 1, 0))
	var e := _enemy(Vector3(-20, 1, 0), {sight_radius = 8.0, lose_radius = 14.0, attack_damage = 0.0})
	await _wait(20)
	_check(e.state_name == &"idle", "idle while the player is outside sight_radius")
	player.teleport(Vector3(-26, 1, 0))
	_check(await _wait_until(func() -> bool: return e.state_name == &"pursuit", 10), "pursuit once the player is inside sight_radius")
	await _wait(20)
	_check(absf(e.planar().length() - e.walk_speed) < 0.2, "chases at walk_speed without RUN")
	_check(await _wait_until(func() -> bool: return e.dist_to_target() < e.attack_range, 180) and e.state_name != &"idle", "closes in without reading the player as a wall") # pursuit, or attack from Task 4 on
	player.teleport(Vector3(0, 1, 0))
	_check(await _wait_until(func() -> bool: return e.state_name == &"idle", 60), "idle once the player is past lose_radius") # an attack under way finishes first

	_course(Vector3(30, 1, 0))
	var chase := {sight_radius = 60.0, lose_radius = 80.0, attack_damage = 0.0, max_stamina = 1000.0}
	var runner := _enemy(Vector3(20, 1, 2), chase.merged({abilities = Enemy.Ability.RUN}, true))
	var other := _enemy(Vector3(20, 1, -2), chase)
	await _wait(20)
	_check(absf(runner.planar().length() - runner.run_speed) < 0.2 and runner.stamina < runner.max_stamina, "RUN chases at run_speed and spends stamina")
	var mud := EnvProfile.new()
	mud.mods.speed = -0.5
	other.add_env(mud)
	await _wait(15)
	_check(absf(other.planar().length() - other.walk_speed * 0.5) < 0.2, "mud halves the chase speed")
	other.remove_env(mud)
	_check(&"idle" not in await _watch([runner, other], 300), "two chasers bump into each other without giving up")

	for kind in ["gap", "wall", "water", "cliff"]:
		_course(Vector3(10, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_far_side(kind)
		var b := _enemy(Vector3(-4, 1, 0), {sight_radius = 30.0, lose_radius = 40.0})
		await _wait_until(func() -> bool: return b.state_name == &"pursuit", 60) # it spawns idle
		var stopped := await _wait_until(func() -> bool: return b.state_name == &"idle", 150)
		await _wait(int(b.give_up_time * 60.0) - 15)
		_check(stopped and b.state_name == &"idle", "%s: gives up the chase and waits out give_up_time" % kind)
		await _wait(120)
		_check(is_instance_valid(b) and b.global_position.x < 1.2 and b.global_position.y > 0.5 and b.oxygen == b.max_oxygen, "%s: never crosses or falls in" % kind)
	_course(Vector3(10, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_far_side("step")
	var s := _enemy(Vector3(-4, 1, 0), {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0})
	_check(await _wait_until(func() -> bool: return s.global_position.x > 2.0, 240), "walks down a drop within safe_drop")

	_course(Vector3(-30, 1, 0))
	var under := _enemy(Vector3(0, 1, 0), {sight_radius = 10.0, attack_damage = 0.0})
	await _wait(10)
	player.teleport(Vector3(0, 3.2, 0)) # lands on the enemy's head
	await _wait(60)
	_check(under.global_position.is_finite() and under.velocity.is_finite(), "target straight above: no NaN")
	player.teleport(Vector3(3, 1, 0))
	await _wait(20)
	player.die(&"hit")
	_check(await _wait_until(func() -> bool: return under.state_name == &"idle", 5), "player dead: the chase stops")
	player.get_parent().remove_child(player)
	player.queue_free()
	await _wait(5)
	_check(under.state_name == &"idle" and not under.has_target(), "target freed: idle, no errors")
	sections += 1


func _test_combat() -> void:
	_course(Vector3(-30, 1, 0))
	var a := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0, max_health = 100.0, armor = 0.5, weight = 2.0})
	await _wait(10)
	a.hit(20.0, 20.0, a.global_position - Vector3(1, 0, 0))
	_check(is_equal_approx(a.health, 90.0), "armor 0.5 halves damage")
	_check(a.state_name == &"hurt" and absf(a.planar().length() - 10.0) < 0.5 and a.planar().x > 0.0, "knockback = push / weight, away from the hit")
	_check(a.mood < a.base_mood, "getting hurt lowers mood")
	a.hit(20.0, 20.0, a.global_position)
	_check(is_equal_approx(a.health, 90.0), "hits inside invuln_time are ignored")
	var heavy := _enemy(Vector3(0, 1, 5), {sight_radius = 0.0, weight = 40.0})
	await _wait(10)
	heavy.hit(5.0, 20.0, heavy.global_position - Vector3(1, 0, 0))
	await _wait(1)
	_check(heavy.planar().length() < 0.1 and heavy.health < heavy.max_health, "push / weight under 1 m/s: hurt but not moved")
	var causes := _deaths(heavy)
	await _wait(30)
	heavy.hit(999.0, 0.0, heavy.global_position)
	_check(causes == [&"hit"] and heavy.collision_layer == 0, "health 0: death by hit, body drops out of collision")
	heavy.hit(999.0, 0.0, heavy.global_position)
	_check(causes == [&"hit"], "hits on a dead enemy are ignored")

	_course(Vector3(-20, 1, 0), false)
	_box(Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	var shoved := _enemy(Vector3(2, 1, 0), {sight_radius = 0.0, weight = 2.0})
	causes = _deaths(shoved)
	await _wait(10)
	shoved.hit(1.0, 24.0, shoved.global_position - Vector3(1, 0, 0))
	_check(await _gone(shoved, 240) and causes == [&"fall"], "a push carries it off the ledge into the pit")

	_course(Vector3(-30, 1, 0))
	var high := _enemy(Vector3(0, 14, 0), {sight_radius = 0.0})
	var low := _enemy(Vector3(4, 2.5, 0), {sight_radius = 0.0})
	await _wait(120)
	_check(high.health < high.max_health and low.health == low.max_health, "hard landings cost health, short drops don't")

	_course(Vector3(30, 1, 0))
	var tired := _enemy(Vector3(0, 1, 0), {abilities = Enemy.Ability.RUN, max_stamina = 20.0, run_cost = 20.0, stun_time = 1.0, sight_radius = 60.0, lose_radius = 80.0})
	_check(await _wait_until(func() -> bool: return tired.state_name == &"stun", 120), "running out of stamina stuns")
	await _wait(15) # slows from run_speed at accel first
	_check(tired.planar().length() < 0.2 and tired.anim == &"stun", "a stunned ground enemy rests in place")
	_check(await _wait_until(func() -> bool: return tired.state_name != &"stun", 70) and tired.stamina == tired.max_stamina, "stun ends after stun_time with full stamina")

	_course(Vector3(-30, 1, 0))
	var s := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0})
	await _wait(10)
	s.stun(1.0)
	await _wait(30)
	s.hit(1.0, 0.0, s.global_position)
	_check(s.state_name == &"stun", "a hit during a stun doesn't end it")
	_check(await _wait_until(func() -> bool: return s.state_name != &"stun", 40), "...or restart it")
	var dizzy := _enemy(Vector3(0, 1, 4), {sight_radius = 0.0, stun_on_hit = 1.0})
	await _wait(10)
	dizzy.hit(1.0, 0.0, dizzy.global_position)
	_check(dizzy.state_name == &"stun", "stun_on_hit: a hit stuns instead of hurting")
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
