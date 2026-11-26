extends SceneTree
## Headless suite for the camera shake (world/camera_shake.gd and its sources).
## Run: Godot_console.exe --headless --path . -s res://tests/shake_test.gd
## Optional filter: `-- rule camera` runs only those sections.

const SECTIONS := 1
const PLAYER := preload("res://player/player.tscn")
const ENEMY := preload("res://enemy/enemy.tscn")

var fails := 0
var sections := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame # the tree isn't running yet during _initialize
	var only := OS.get_cmdline_user_args()
	var all: Array[Callable] = [_test_rule]
	var ran := 0
	for t in all:
		if only.is_empty() or t.get_method().trim_prefix("_test_") in only:
			ran += 1
			CameraShake.clear()
			await t.call()
	_check(sections == ran and (not only.is_empty() or ran == SECTIONS), "all %d sections ran (%d)" % [ran, sections])
	print("SHAKE: ", "OK" if fails == 0 else "%d FAILED" % fails)
	quit(fails)


func _test_rule() -> void:
	var J := CameraShake.Feel.JOLT
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.5), "one shake of 0.5 = 0.5")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.75), "two equal shakes = 1 - (1 - a)^2")
	CameraShake.add(J, 0.5); CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(is_equal_approx(CameraShake.total, 0.875), "three = 0.875")
	for i in 20:
		CameraShake.add(J, 0.9 if i == 19 else 0.3)
	CameraShake.update(0.0, Vector3.ZERO, 0.0)
	_check(CameraShake.layers.size() == CameraShake.MAX_LAYERS and CameraShake.total <= 1.0, "cap: 8 layers, total <= 1")
	_check(CameraShake.layers.any(func(l: Dictionary) -> bool: return is_equal_approx(l.strength, 0.9)), "a full list replaces its weakest")
	CameraShake.clear()
	CameraShake.update(0.0, Vector3.ZERO, 0.0) # focus at the origin
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(100, 0, 0))
	_check(CameraShake.layers.is_empty(), "beyond the radius: no layer")
	CameraShake.add(CameraShake.Feel.THUMP, 0.5, Vector3(7, 0, 0))
	_check(CameraShake.layers.size() == 1 and is_equal_approx(CameraShake.layers[0].strength, 0.25), "linear falloff: half the 14 m radius = half")
	CameraShake.clear()
	CameraShake.add(J, 1.0)
	var t := 0.0
	while t < 0.31:
		CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
		t += 1.0 / 60.0
	_check(CameraShake.layers.is_empty(), "a JOLT is gone after its 0.3 s")
	# toggles
	var roll_seen := false
	CameraShake.add(J, 1.0)
	for i in 6:
		roll_seen = roll_seen or CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0).z != 0.0
	_check(not roll_seen, "tilt is off by default")
	ProjectSettings.set_setting(CameraShake.TILT, true)
	for i in 6:
		roll_seen = roll_seen or CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0).z != 0.0
	_check(roll_seen, "tilt on: the horizon rolls")
	ProjectSettings.set_setting(CameraShake.SLIDE, false)
	var off := CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	_check(off.x == 0.0 and off.y == 0.0, "slide off: no slide")
	ProjectSettings.set_setting(CameraShake.DISABLE, true)
	_check(CameraShake.update(1.0 / 60.0, Vector3.ZERO, 0.0) == Vector3.ZERO, "master off: nothing")
	ProjectSettings.set_setting(CameraShake.TILT, false)
	ProjectSettings.set_setting(CameraShake.SLIDE, true)
	ProjectSettings.set_setting(CameraShake.DISABLE, false)
	sections += 1


# --- waiting and checking -----------------------------------------------------------

func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
