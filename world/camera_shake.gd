class_name CameraShake
extends RefCounted
## Camera shake, static only: anything calls `CameraShake.add(feel, strength, at)` and GameArea
## turns `update()` into the camera's view offsets (slide) and a roll on its steady basis (tilt).
## Each shake is a short-lived layer with its own feel, so a footstep in a storm still reads as a
## footstep. Layers are summed strongest first, each scaled by what the stronger ones left, so the
## total intensity `1 - Π(1 - i)` never passes 1 (two shakes of 0.5 = 0.75, three = 0.875).
## A sustained level (the player's EnvProfile.shake) adds one never-ending SWAY layer.
## Toggles are project settings, read every update: DISABLE (master), SLIDE, TILT.
## Must not reference the World autoload (Enemy and MovingPlatform call it; -s tests compile it first).

enum Feel { JOLT, THUMP, SLAM, SWAY }

const DISABLE := "ahra/camera/disable_shake"
const SLIDE := "ahra/camera/shake_slide"
const TILT := "ahra/camera/shake_tilt"
const MAX_SLIDE := 0.025 ## full shake: the view slides this fraction of its height
const MAX_TILT := 0.026 ## full shake: the horizon rolls this many radians (~1.5°)
const MAX_LAYERS := 8
const MIN_STRENGTH := 0.02 ## weaker shakes (after falloff) add no layer
const EASE := 2.0 ## sustained level change per second
## length (s), default falloff radius (m, 0 = felt everywhere), noise frequency
const FEELS := {
	Feel.JOLT: {length = 0.3, radius = 0.0, freq = 25.0}, ## player hit: sharp jitter
	Feel.THUMP: {length = 0.2, radius = 14.0, freq = 20.0}, ## footstep: one dip down and back
	Feel.SLAM: {length = 0.6, radius = 18.0, freq = 18.0}, ## crusher: deep dip, rattling tail
	Feel.SWAY: {length = INF, radius = 0.0, freq = 3.0}, ## environment: slow wandering
}

static var layers: Array[Dictionary] = [] ## {feel, strength, age, id}
static var sustained_level := 0.0 ## eased toward the `sustained` given to update
static var focus := Vector3.ZERO ## where falloff is measured from (the player), set by update
static var roll := 0.0 ## the last roll update returned (steady() takes it out)
static var total := 0.0 ## combined intensity after the last update, 0..1
static var _noise: FastNoiseLite


## A one-off shake. `strength` 0..1; with `at` it falls off linearly to 0 at `radius` from the
## focus (0 = the feel's default radius). When 8 layers run, it replaces the weakest if stronger.
## ponytail: replacing the weakest is the ceiling; queue them if more than 8 sources ever overlap.
static func add(feel: Feel, strength: float, at: Variant = null, radius := 0.0) -> void:
	var s := clampf(strength, 0.0, 1.0)
	var r: float = radius if radius > 0.0 else FEELS[feel].radius
	if at != null and r > 0.0:
		s *= clampf(1.0 - focus.distance_to(at) / r, 0.0, 1.0)
	if s < MIN_STRENGTH:
		return
	var layer := {feel = feel, strength = s, age = 0.0, id = randi() % 10000}
	if layers.size() < MAX_LAYERS:
		layers.append(layer)
		return
	var weakest := 0
	for i in layers.size():
		if _intensity(layers[i]) < _intensity(layers[weakest]):
			weakest = i
	if s > _intensity(layers[weakest]):
		layers[weakest] = layer


## Ages the layers by `delta` and combines them. Returns x, y: slide as a fraction of the view
## height; z: roll in radians, after the toggles.
static func update(delta: float, at_focus: Vector3, sustained: float) -> Vector3:
	focus = at_focus
	sustained_level = move_toward(sustained_level, clampf(sustained, 0.0, 1.0), EASE * delta)
	for i in range(layers.size() - 1, -1, -1):
		layers[i].age += delta
		if layers[i].age >= FEELS[layers[i].feel].length:
			layers.remove_at(i)
	var live: Array = [] # [intensity, unit motion]
	for l in layers:
		live.append([_intensity(l), _motion(l.feel, l.age, l.id)])
	if sustained_level > 0.0:
		live.append([sustained_level, _motion(Feel.SWAY, Time.get_ticks_msec() * 0.001, 0)])
	live.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var left := 1.0
	var out := Vector3.ZERO
	for e: Array in live:
		out += e[1] * e[0] * left
		left *= 1.0 - e[0]
	total = 1.0 - left
	var off: bool = ProjectSettings.get_setting(DISABLE, false)
	var slide: bool = not off and ProjectSettings.get_setting(SLIDE, true)
	var tilt: bool = not off and ProjectSettings.get_setting(TILT, false)
	var s := Vector3(out.x * MAX_SLIDE, out.y * MAX_SLIDE, 0.0) if slide else Vector3.ZERO
	s.z = out.z * MAX_TILT if tilt else 0.0
	roll = s.z
	return s


## `b` (the camera's basis) with the last applied roll taken out: what movement should read.
static func steady(b: Basis) -> Basis:
	return b * Basis(Vector3.BACK, -roll)


static func clear() -> void:
	layers.clear()
	sustained_level = 0.0
	roll = 0.0
	total = 0.0


static func _intensity(l: Dictionary) -> float:
	var x: float = l.age / FEELS[l.feel].length
	return l.strength * (1.0 - x) * (1.0 - x)


## The feel's motion at `age`, about -1..1 on each axis (x, y slide, z roll).
static func _motion(feel: Feel, age: float, id: int) -> Vector3:
	var f: float = FEELS[feel].freq
	var n := Vector3(_n(id, 0, age * f), _n(id, 1, age * f), _n(id, 2, age * f))
	match feel:
		Feel.THUMP:
			return Vector3(0.2 * n.x, -sin(PI * age / FEELS[feel].length), 0.2 * n.z)
		Feel.SLAM:
			var dip: float = FEELS[feel].length * 0.25
			return Vector3(0.2 * n.x, -sin(PI * age / dip), 0.2 * n.z) if age < dip else n
		Feel.SWAY:
			return n + 0.3 * Vector3(_n(id, 3, age * f * 3.0), _n(id, 4, age * f * 3.0), _n(id, 5, age * f * 3.0))
	return n # JOLT


static func _n(id: int, axis: int, x: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 1.0
	return _noise.get_noise_2d(x, id + axis * 101.3)
