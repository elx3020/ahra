extends SceneTree
## Headless suite for the enemy system (enemy/, the player's attacks, projectiles).
## Run: Godot_console.exe --headless --path . -s res://tests/enemy_test.gd
## Each section builds its own small course in code (see _course) so tests don't depend on
## the demo layout.

const SECTIONS := 12
const ENEMY := preload("res://enemy/enemy.tscn")
const PLAYER := preload("res://player/player.tscn")
const RUNNER := preload("res://enemy/runner/runner.tscn")
const BURROWER := preload("res://enemy/burrower/burrower.tscn")

var fails := 0
var sections := 0
var course: Node3D
var player: Player


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the tree isn't running yet during _initialize
	# optional filter: `-- pursuit swing_fly` runs only those sections
	var only := OS.get_cmdline_user_args()
	var all: Array[Callable] = [_test_core, _test_pursuit, _test_combat, _test_attack_flee, _test_jump_dash,
		_test_climb_swim, _test_swing_fly, _test_player_attacks, _test_types, _test_edges, _test_polish, _test_demo]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			await t.call()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
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


func _test_attack_flee() -> void:
	_course(Vector3(0, 1, 0))
	var e := _enemy(Vector3(3, 1, 0), {sight_radius = 10.0, attack_damage = 10.0, attack_cooldown = 1.5})
	var cues := []
	e.cue.connect(func(n: StringName) -> void: cues.append(n))
	var hp := player.health
	_check(await _wait_until(func() -> bool: return player.health < hp, 120), "attacks once in range")
	_check(player.health == hp - 10.0 and &"attack_windup" in cues and &"attack" in cues, "windup, strike for attack_damage, cues")
	_check(e.mood > e.base_mood and e.stamina < e.max_stamina, "a landed hit raises mood; attacking costs stamina")
	hp = player.health
	var frames := 0
	while player.health == hp and frames < 300:
		await _wait(1)
		frames += 1
	_check(frames >= int(e.attack_cooldown * 60.0), "the next strike waits out attack_cooldown (%d frames)" % frames)

	_course(Vector3(-30, 1, 0))
	var calm := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0, base_mood = 0.6})
	await _wait(5)
	calm.mood = 0.3
	await _wait(120)
	_check(calm.mood > 0.3 and calm.mood <= 0.6, "mood drifts back toward base_mood while idle")

	_course(Vector3(-5, 1, 0))
	var coward := _enemy(Vector3(0, 1, 0), {sight_radius = 20.0, lose_radius = 30.0, base_mood = 0.3, flee_mood = 0.2, attack_damage = 0.0})
	await _wait(10)
	coward.hit(1.0, 0.0, player.global_position)
	_check(await _wait_until(func() -> bool: return coward.state_name == &"flee", 30), "mood under flee_mood: flees")
	var d0 := coward.dist_to_target()
	await _wait(60)
	_check(coward.dist_to_target() > d0 + 2.0, "fleeing opens distance")

	_course(Vector3(-4, 1, 0), false)
	_box(Vector3(0, -0.5, 0), Vector3(10, 1, 6))
	var cornered := _enemy(Vector3(3, 1, 0), {sight_radius = 20.0, base_mood = 0.1, flee_mood = 0.2, attack_damage = 5.0})
	await _wait(120)
	_check(is_instance_valid(cornered) and cornered.global_position.y > 0.5 and cornered.state_name == &"flee", "cornered at the edge: holds its ground")
	player.teleport(cornered.global_position - Vector3(1.2, 0, 0))
	hp = player.health
	_check(await _wait_until(func() -> bool: return player.health < hp, 120), "cornered: attacks when the player comes close")

	_course(Vector3(-3, 1, 0))
	var actor := _enemy(Vector3(0, 1, 0), {sight_radius = 20.0})
	await _wait(5)
	var arrived := []
	actor.puppet_arrived.connect(func() -> void: arrived.append(true))
	actor.start_puppet(Vector3(6, 0, 0))
	var hp2 := actor.health
	actor.hit(10.0, 10.0, actor.global_position)
	_check(actor.health == hp2, "puppet ignores hits")
	var seen := await _watch([actor], 150)
	_check(arrived.size() == 1 and seen == [&"puppet"] and actor.global_position.x > 5.5, "puppet walks to its mark, ignores the player, emits puppet_arrived")
	actor.end_puppet()
	await _wait(2)
	_check(actor.state_name != &"puppet", "end_puppet hands back to the AI")
	sections += 1


func _test_jump_dash() -> void:
	var base := {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0}
	var jumper := base.merged({abilities = Enemy.Ability.JUMP, jump_height = 2.3, jump_reach = 6.5}, true)
	var dasher := base.merged({abilities = Enemy.Ability.DASH, dash_distance = 6.0}, true)
	var runs := [ # props, far block centre, size, player at, crosses, label
		[jumper, Vector3(9.5, -0.5, 0), Vector3(13, 1, 10), Vector3(10, 1, 0), true, "JUMP clears a 3 m gap"],
		[jumper, Vector3(13.5, -0.5, 0), Vector3(13, 1, 10), Vector3(14, 1, 0), false, "JUMP refuses a 7 m gap"],
		[jumper, Vector3(8, 0.75, 0), Vector3(16, 1.5, 10), Vector3(8, 2.5, 0), true, "JUMP gets onto a 1.5 m wall"],
		[jumper, Vector3(8, 1.5, 0), Vector3(16, 3, 10), Vector3(8, 4, 0), false, "JUMP refuses a 3 m wall"],
		[dasher, Vector3(9.5, -0.5, 0), Vector3(13, 1, 10), Vector3(10, 1, 0), true, "DASH crosses a level 3 m gap"],
		[dasher, Vector3(13.5, -0.5, 0), Vector3(13, 1, 10), Vector3(14, 1, 0), false, "DASH refuses a 7 m gap"],
	]
	for r: Array in runs:
		_course(r[3], false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_box(r[1], r[2])
		var e := _enemy(Vector3(-4, 1, 0), r[0])
		var near_x: float = r[1].x - r[2].x / 2.0
		var top: float = r[1].y + r[2].y / 2.0
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(e) and e.global_position.x > near_x + 0.3 and e.global_position.y > top and e.is_on_floor(), 300)
		_check(crossed == r[4] and is_instance_valid(e) and (crossed or e.global_position.x < 1.2 and e.global_position.y > 0.5), r[5])
	sections += 1


func _pool() -> void: # banks at x < 0 and x > 6 (tops y = 0), pool floor y = -4, surface y = -0.3
	_box(Vector3(-8, -2.5, 0), Vector3(16, 5, 10))
	_box(Vector3(14, -2.5, 0), Vector3(16, 5, 10))
	_box(Vector3(3, -4.5, 0), Vector3(6, 1, 10))
	_water(Vector3(3, -2.15, 0), Vector3(6, 3.7, 10))


func _test_climb_swim() -> void:
	var base := {sight_radius = 40.0, lose_radius = 50.0, attack_damage = 0.0}
	for climbable in [true, false]:
		_course(Vector3(8, 5, 0))
		_box(Vector3(8, 2, 0), Vector3(8, 4, 10), climbable) # 4 m block, face at x = 4
		var c := _enemy(Vector3(0, 1, 0), base.merged({abilities = Enemy.Ability.CLIMB}, true))
		var up := await _wait_until(func() -> bool: return c.global_position.y > 4.5 and c.is_on_floor(), 400)
		_check(up == climbable, "CLIMB scales a climbable 4 m wall" if climbable else "CLIMB can't scale a plain wall")

	for swims in [true, false]:
		_course(Vector3(12, 1, 0), false)
		_pool()
		var w := _enemy(Vector3(-4, 1, 0), base.merged({abilities = (Enemy.Ability.SWIM | Enemy.Ability.JUMP) if swims else 0, max_oxygen = 30.0}, true))
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(w) and w.global_position.x > 6.5 and w.is_on_floor(), 600)
		_check(crossed == swims, "SWIM + JUMP crosses the pool and climbs out" if swims else "no SWIM: stops at the pool")

	_course(Vector3(14, 1, 0), false)
	_pool()
	player.teleport(Vector3(3, -3, 0)) # stands on the pool floor (the player sinks when idle underwater)
	var diver := _enemy(Vector3(1, -2, 0), base.merged({abilities = Enemy.Ability.SWIM, max_oxygen = 2.0}, true))
	var causes := _deaths(diver)
	var low := INF
	for i in 300:
		await _wait(1)
		low = minf(low, diver.oxygen)
	_check(causes.is_empty() and low < diver.max_oxygen * 0.3 and diver.oxygen > low, "a swimmer low on oxygen surfaces to breathe instead of drowning")
	sections += 1


func _test_swing_fly() -> void:
	var base := {sight_radius = 30.0, lose_radius = 40.0, attack_damage = 0.0}
	for anchor in [true, false]:
		_course(Vector3(12, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_box(Vector3(16, -0.5, 0), Vector3(16, 1, 10)) # 8 m gap
		if anchor:
			var sp := SwingPoint.new()
			sp.position = Vector3(4, 6, 0)
			sp.grab_radius = 8.0
			course.add_child(sp)
		var sw := _enemy(Vector3(-3, 1, 0), base.merged({abilities = Enemy.Ability.SWING}, true))
		var crossed := await _wait_until(func() -> bool: return is_instance_valid(sw) and sw.global_position.x > 8.5 and sw.is_on_floor(), 400)
		_check(crossed == anchor, "SWING crosses an 8 m gap on a swing point" if anchor else "no swing point: SWING stops at the gap")

	_course(Vector3(14, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_box(Vector3(16, -0.5, 0), Vector3(16, 1, 10))
	var fl := _enemy(Vector3(-4, 1, 0), base.merged({abilities = Enemy.Ability.FLY, sight_radius = 0.0, hover_height = 2.5}, true))
	await _wait(120)
	var alt := fl.global_position.y - Enemy.HALF_HEIGHT
	_check(alt > 2.0 and alt < 3.0, "FLY hovers at hover_height (%.2f)" % alt)
	fl.sight_radius = 30.0
	_check(await _wait_until(func() -> bool: return fl.global_position.x > 9.0, 400), "FLY crosses an 8 m gap")
	fl.stun_on_hit = 1.0
	fl.hit(1.0, 0.0, fl.global_position)
	_check(fl.state_name == &"stun", "stun_on_hit stuns a flyer")
	_check(await _wait_until(func() -> bool: return fl.is_on_floor(), 90), "a stunned flyer drops to the ground")
	_check(await _wait_until(func() -> bool: return fl.global_position.y - Enemy.HALF_HEIGHT > 2.0, 200), "after the stun it flies back up")

	_course(Vector3(30, 1, 0))
	var winded := _enemy(Vector3(0, 1, 0), base.merged({abilities = Enemy.Ability.FLY, sight_radius = 60.0, lose_radius = 80.0, max_stamina = 10.0, fly_cost = 20.0, stun_time = 1.0}, true))
	_check(await _wait_until(func() -> bool: return winded.state_name == &"stun", 200), "a long flight ends in an exhaustion stun")
	_check(await _wait_until(func() -> bool: return winded.is_on_floor(), 90), "...and a drop to the ground")

	_course(Vector3(10, 1, 0))
	_box(Vector3(4, 10, 0), Vector3(1, 20, 30)) # 20 m wall across the floor
	var walled := _enemy(Vector3(-2, 1, 0), base.merged({abilities = Enemy.Ability.FLY}, true))
	var seen := await _watch([walled], 300)
	_check(&"idle" in seen and walled.global_position.x < 3.5, "FLY gives up at a wall too high to rise over")
	sections += 1


func _projectiles() -> Array:
	return course.get_children().filter(func(n: Node) -> bool: return n is Projectile)


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _wait(2)
	Input.action_release(action)


func _test_player_attacks() -> void:
	_check(InputMap.has_action(&"attack") and InputMap.has_action(&"shoot"), "attack and shoot input actions")
	_course(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	await _wait(20)
	var front := _enemy(Vector3(1.4, 1, 0), {sight_radius = 0.0, weight = 2.0})
	var back := _enemy(Vector3(-1.4, 1, 0), {sight_radius = 0.0})
	await _wait(10)
	await _press(&"attack")
	_check(player.state_name == &"melee", "attack starts the melee state")
	await _wait(30)
	_check(front.health == front.max_health - player.melee_damage and front.global_position.x > 1.6, "melee hits the enemy in front and pushes it")
	_check(back.health == back.max_health, "melee misses the enemy behind")
	_check(player.mood == 1.0, "a melee hit counts as a hit (mood)")
	player.melee_cd = 1.0
	await _press(&"attack")
	_check(player.state_name != &"melee", "no melee while on cooldown")
	front.queue_free()
	back.queue_free()

	var target := _enemy(Vector3(8, 1, 1.5), {sight_radius = 0.0}) # 11 degrees off the facing
	await _wait(10)
	await _press(&"shoot")
	_check(_projectiles().size() == 1, "shoot spawns one projectile")
	_check(await _wait_until(func() -> bool: return target.health < target.max_health, 30), "aim assist: the shot hits an enemy 11 degrees off the facing")
	await _wait(2)
	_check(_projectiles().is_empty(), "the projectile is freed on hit")
	target.queue_free()

	_box(Vector3(-6, 1, 0), Vector3(1, 2, 4))
	player.facing = Vector3.LEFT
	await _wait(20)
	await _press(&"shoot")
	_check(await _wait_until(func() -> bool: return _projectiles().is_empty(), 30), "a shot into a wall is freed")
	_check(is_equal_approx(player.mood, 2.0 / 3.0), "the miss counts (mood = hits / attacks)")
	player.damage(1.0, player.global_position + Vector3.RIGHT)
	await _press(&"shoot")
	_check(_projectiles().is_empty(), "no shooting while hurt")
	sections += 1


func _test_types() -> void:
	_course(Vector3(-30, 1, 0))
	var r := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0}, RUNNER)
	await _wait(10)
	_check(r.abilities == (Enemy.Ability.RUN | Enemy.Ability.JUMP) and r.weight == 3.0, "runner: RUN + JUMP, weight 3")
	r.hit(1.0, player.melee_push, r.global_position - Vector3(1, 0, 0))
	_check(absf(r.planar().length() - player.melee_push / 3.0) < 0.1, "runner flies back from a melee push")

	_course(Vector3(12, 1, 0), false)
	_pool()
	var dunk := _enemy(Vector3(-0.8, 1, 0), {sight_radius = 0.0}, RUNNER)
	var causes := _deaths(dunk)
	await _wait(10)
	dunk.hit(1.0, player.melee_push, dunk.global_position - Vector3(1, 0, 0))
	_check(await _gone(dunk, 420) and causes == [&"drown"], "runner shoved into deep water drowns")

	_course(Vector3(6, 1, 0))
	_box(Vector3(0, 1.5, 0), Vector3(1, 3, 30)) # wall across the floor
	var b: Burrower = _enemy(Vector3(-6, 1, 0), {sight_radius = 20.0, lose_radius = 30.0}, BURROWER)
	var cues := []
	b.cue.connect(func(n: StringName) -> void: cues.append(n))
	_check(await _wait_until(func() -> bool: return b.burrowed, 120) and b.collision_layer == 0, "burrower digs in: no collision underground")
	var hp := player.health
	_check(await _wait_until(func() -> bool: return not b.burrowed, 300), "...and surfaces")
	_check(b.global_position.x > 0.5 and (b.global_position - player.global_position).slide(Vector3.UP).length() < b.surface_radius + 0.5, "it passed under the wall and came up next to the player")
	_check(await _wait_until(func() -> bool: return player.health < hp, 30) and &"surface" in cues, "the surfacing burst hurts the player")
	_check(await _wait_until(func() -> bool: return b.state_name == &"stun", 60), "then it rests (stun)")
	b.hit(10.0, player.melee_push, b.global_position - Vector3(1, 0, 0))
	_check(b.planar().length() < 0.1 and b.health < b.max_health and b.state_name == &"stun", "resting burrower takes damage, stays down, can't be pushed")

	for kind in ["water", "gap"]:
		_course(Vector3(10, 1, 0), false)
		_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
		_far_side(kind)
		var b2: Burrower = _enemy(Vector3(-5, 1, 0), {sight_radius = 30.0, lose_radius = 40.0}, BURROWER)
		await _wait_until(func() -> bool: return b2.burrowed, 120)
		var seen := await _watch([b2], 240)
		_check(&"idle" in seen and b2.global_position.x < 1.2 and b2.global_position.y > 0.5, "burrower can't cross %s: surfaces on its side and gives up" % kind) # it retries after give_up_time, so it may be dug in again
	sections += 1


func _test_demo() -> void:
	if course:
		root.remove_child(course)
		course.queue_free()
		course = null
	var demo: Node = load("res://demo/enemies/enemies.tscn").instantiate()
	root.add_child(demo)
	await _wait(60)
	var enemies := get_nodes_in_group(&"enemy")
	var burrowers := enemies.filter(func(n: Node) -> bool: return n is Burrower)
	_check(enemies.size() == 5 and burrowers.size() == 2, "demo: 3 runners and 2 burrowers")
	_check(enemies.all(func(n: Enemy) -> bool: return n.state_name == &"idle" and n.health == n.max_health), "all idle at full health at the start")
	demo.queue_free()
	sections += 1


## Regression tests for the final review's findings.
func _test_edges() -> void:
	_course(Vector3(1.2, 1, 0)) # the player 0.7 m from the wall's face: no room between them
	_box(Vector3(0, 1.5, 0), Vector3(1, 3, 30))
	var bw: Burrower = _enemy(Vector3(-8, 1, 0), {sight_radius = 20.0, lose_radius = 30.0}, BURROWER)
	await _wait_until(func() -> bool: return bw.burrowed, 120)
	await _wait_until(func() -> bool: return not bw.burrowed, 300)
	var clear := bw.global_position.x > 0.85 and bw.cast(bw.global_position, player.global_position).is_empty()
	_check(clear, "a burrower by a wall surfaces clear of it, in sight of the player (x %.2f)" % bw.global_position.x)

	_course(Vector3(12, 1, 0), false)
	_box(Vector3(-8, -0.5, 0), Vector3(16, 1, 10))
	_box(Vector3(13.5, -0.5, 0), Vector3(12, 1, 10)) # 7.5 m gap
	var ice := EnvProfile.new()
	ice.mods.traction = -0.94
	_zone(Vector3(-8, 0.5, 0), Vector3(16, 1, 10), ice)
	var skater := _enemy(Vector3(-12, 1, 0), {abilities = Enemy.Ability.RUN, sight_radius = 40.0, lose_radius = 50.0, max_stamina = 1000.0})
	await _wait(300)
	_check(is_instance_valid(skater) and skater.global_position.x < 0.6 and skater.global_position.y > 0.5, "on ice it brakes before the gap")

	_course(Vector3(14, 1, 0), false)
	_pool()
	var floater := _enemy(Vector3(3, -3, 0), {abilities = Enemy.Ability.SWIM, sight_radius = 0.0, max_oxygen = 2.0})
	var causes := _deaths(floater)
	await _wait(300)
	_check(causes.is_empty() and is_instance_valid(floater) and floater.oxygen > 1.0, "an idle swimmer floats up to breathe")

	_course(Vector3(20, 1, 0), false)
	_box(Vector3(-8, -4.5, 0), Vector3(16, 9, 10))
	_box(Vector3(14, -4.5, 0), Vector3(16, 9, 10))
	_box(Vector3(3, -9.5, 0), Vector3(6, 1, 10)) # lake bed y = -9
	_water(Vector3(3, -4.65, 0), Vector3(6, 8.7, 10)) # surface y = -0.3
	var gull := _enemy(Vector3(3, 2, 0), {abilities = Enemy.Ability.FLY, sight_radius = 0.0, max_oxygen = 2.0})
	causes = _deaths(gull)
	await _wait(240)
	_check(causes.is_empty() and is_instance_valid(gull) and gull.global_position.y - Enemy.HALF_HEIGHT > 1.5, "a flyer over deep water hovers above the surface, not the bed")

	_course(Vector3(12, 1, 0), false)
	_pool()
	var fish := _enemy(Vector3(3, -1, 0), {abilities = Enemy.Ability.SWIM, sight_radius = 40.0, lose_radius = 50.0, attack_damage = 0.0, max_oxygen = 30.0})
	await _wait_until(func() -> bool: return fish.state_name == &"swim", 120)
	var max_x := -INF
	var gave_up := false
	for i in 700:
		await _wait(1)
		if not is_instance_valid(fish):
			break
		max_x = maxf(max_x, fish.global_position.x)
		gave_up = gave_up or fish.state_name == &"idle"
	_check(is_instance_valid(fish) and max_x < 6.0 and gave_up, "SWIM-only never leaves the water: gives up at the bank (max x %.2f)" % max_x)

	_course(Vector3(0, 1, 0))
	var tank := _enemy(Vector3(1.4, 1, 0), {weight = 40.0, sight_radius = 10.0, attack_damage = 10.0, attack_cooldown = 0.5})
	var hp := player.health
	var landed := false
	for i in 150:
		if i % 21 == 0 and is_instance_valid(tank):
			tank.hit(1.0, player.shoot_push, player.global_position)
		await _wait(1)
		if player.health < hp:
			landed = true
			break
	_check(landed, "a heavy enemy keeps attacking through a stream of light hits")

	_course(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	await _wait(10)
	var close := _enemy(Vector3(0.85, 1, 0), {sight_radius = 0.0})
	await _wait(10)
	await _press(&"shoot")
	_check(await _wait_until(func() -> bool: return close.health < close.max_health, 10), "a point-blank shot hits an enemy pressed against the player")
	sections += 1


## Regression tests for the minor review items.
func _test_polish() -> void:
	_course(Vector3(6, 1, 0))
	var b: Burrower = _enemy(Vector3(-6, 1, 0), {sight_radius = 20.0, lose_radius = 30.0}, BURROWER)
	await _wait_until(func() -> bool: return b.burrowed, 120)
	var causes := _deaths(b)
	b.died.connect(func(_c: StringName) -> void: b.die(&"hit")) # a listener that re-enters die()
	b.die(&"hit")
	_check(causes.size() == 1 and b.collision_layer == 0 and b.state_name == &"death", "die() is final: died once, no collision, even killed underground")
	b.stun(1.0)
	b.start_puppet(Vector3.ZERO)
	_check(b.state_name == &"death", "stun() and start_puppet() don't revive a dead enemy")

	_course(Vector3(-30, 1, 0))
	_box(Vector3(6, 1, 0), Vector3(1, 2, 4))
	var shooter := CharacterBody3D.new()
	course.add_child(shooter)
	var shot: Projectile = Player.PROJECTILE.instantiate()
	course.add_child(shot)
	shot.setup(Vector3(0, 1, 0), Vector3.RIGHT, 1.0, 0.0, shooter)
	shooter.free()
	_check(await _gone(shot, 30), "a projectile whose shooter is gone still flies and hits")

	_course(Vector3(0, 1, 0))
	player.facing = Vector3.RIGHT
	await _wait(10)
	_box(Vector3(3, 1, 0.9), Vector3(0.5, 2, 1.2)) # hides the enemy 13 degrees to one side
	var hidden := _enemy(Vector3(8, 1, 1.7), {sight_radius = 0.0})
	var actor := _enemy(Vector3(8, 1, -1.7), {sight_radius = 0.0})
	var mole: Burrower = _enemy(Vector3(10, 1, 0.5), {sight_radius = 0.0}, BURROWER)
	var mime := _enemy(Vector3(3, 1, 0), {sight_radius = 0.0}) # straight ahead
	await _wait(5)
	actor.start_puppet()
	mime.start_puppet()
	mole.set_burrowed(true)
	_check(player.aim_dir().is_equal_approx(player.facing), "aim assist skips enemies behind walls, in cutscenes and underground")
	await _press(&"shoot")
	await _wait_until(func() -> bool: return _projectiles().is_empty(), 30)
	_check(player.mood == 0.0 and hidden.health == hidden.max_health, "a hit the enemy ignores (puppet) counts as a miss")

	_course(Vector3(0, 1, 0))
	var hawk := _enemy(Vector3(6, 1, 0), {abilities = Enemy.Ability.FLY, sight_radius = 20.0, lose_radius = 30.0})
	var hp := player.health
	_check(await _wait_until(func() -> bool: return player.health < hp, 300), "a flyer with default numbers attacks from its hover point")

	_course(Vector3(8, 1, 0))
	_box(Vector3(3, 1.35, 0), Vector3(0.5, 0.5, 30)) # a beam above the chest ray, below the head
	var ducker := _enemy(Vector3(-2, 1, 0), {sight_radius = 30.0, lose_radius = 40.0})
	await _wait_until(func() -> bool: return ducker.state_name == &"pursuit", 60)
	_check(&"idle" in await _watch([ducker], 240), "pressing against something the probe can't see gives up the chase")

	_course(Vector3(12, 1, 0), false)
	_pool()
	_box(Vector3(40, -0.5, 0), Vector3(4, 1, 4))
	var eel := _enemy(Vector3(3, -1, 0), {abilities = Enemy.Ability.SWIM, sight_radius = 30.0, lose_radius = 20.0, attack_damage = 0.0, max_oxygen = 30.0})
	await _wait_until(func() -> bool: return eel.state_name == &"swim", 120)
	player.teleport(Vector3(40, 1, 0))
	_check(await _wait_until(func() -> bool: return eel.state_name == &"idle", 10), "a swimmer gives up once the player is past lose_radius")

	_course(Vector3(-30, 1, 0))
	var gale := EnvProfile.new()
	gale.wind = Vector3(10, 0, 0)
	_zone(Vector3(0, 1, 0), Vector3(10, 2, 10), gale)
	var leaf := _enemy(Vector3(0, 1, 0), {sight_radius = 0.0})
	var feather := _enemy(Vector3(0, 1, 8), {sight_radius = 0.0, weight = 0.0})
	var lazy := _enemy(Vector3(4, 1, 8), {sight_radius = 0.0, max_stamina = 0.0})
	await _wait(10)
	feather.hit(1.0, 10.0, feather.global_position - Vector3(1, 0, 0))
	await _wait(30)
	_check(leaf.planar().x > 1.0, "sideways wind pushes an idle enemy, as it does the player")
	_check(feather.velocity.is_finite() and lazy.state_name != &"stun", "weight 0 and max_stamina 0 don't break the enemy")

	_course(Vector3(30, 1, 0))
	var chase := {sight_radius = 60.0, lose_radius = 80.0, attack_damage = 0.0}
	var leader := _enemy(Vector3(22, 1, 0), chase)
	var tail := _enemy(Vector3(18, 1, 0.3), chase.merged({walk_speed = 5.0}, true)) # catches up with the leader's back
	_check(await _wait_until(func() -> bool: return tail.has_target() and tail.dist_to_target() < tail.attack_range + 1.0, 400) and is_instance_valid(leader), "a chaser stuck behind another works its way around")
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
	var water := EnvProfile.new()
	water.resource_name = "Water"
	water.water = true
	water.gravity_mult = 0.3
	water.drag = 1.2
	return _zone(at, size, water)


func _zone(at: Vector3, size: Vector3, profile: EnvProfile) -> EnvZone:
	var z := EnvZone.new()
	z.profile = profile
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
