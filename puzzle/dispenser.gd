@tool
class_name Dispenser
extends Node3D
## Keeps `count` weights of `weight_scene` in play for a puzzle, so it can't run out of them: a
## weight that is lost (destroyed, or freed by anything) is replaced after respawn_delay. Once its
## channel is solved (World.solved: its latch plates locked the doors open) it stops for good; the
## weights already out stay. Weights come out one at a time at its position, each when the spot is
## clear. They are its children (Weight1, Weight2...), and it remembers which exist
## (World.bodies), so a reload recreates them; GameArea puts them back where they were.

signal cue(name: StringName) ## spawn

@export var channel: StringName ## stops for good once this channel is solved; empty: never stops
@export var weight_scene: PackedScene = preload("res://puzzle/box.tscn")
@export var count := 1
@export var respawn_delay := 2.0

var _weights := {} ## name -> the weight (may be freed: checked every physics frame)
var _timers: Array[float] = [] ## seconds left before each lost weight is replaced
var _probe: Array = [] ## [shape, local transform] of the weight scene's shapes: the spawn spot check


func _ready() -> void:
	if Engine.is_editor_hint() or weight_scene == null:
		return
	var t := weight_scene.instantiate()
	for cs in ShapeSet.of(t):
		_probe.append([cs.shape, cs.transform])
	t.free()
	for n: String in World.bodies.get(_id(), {}).get("alive", PackedStringArray()):
		_spawn(n) # back where they were: GameArea restores them right after


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or weight_scene == null:
		return
	for n: String in _weights.keys():
		var w: Variant = _weights[n]
		if not is_instance_valid(w) or w.gone or w.is_queued_for_deletion():
			_weights.erase(n)
			World.bodies.erase(_id() + "/" + n)
			_timers.append(respawn_delay)
			_remember()
	if channel != &"" and World.solved(Channels.key(self, channel)):
		return
	for i in _timers.size():
		_timers[i] -= delta
	_timers.assign(_timers.filter(func(t: float) -> bool: return t > 0.0))
	if _weights.size() + _timers.size() < count and _spot_clear():
		_spawn(_free_name())
		cue.emit(&"spawn")


## Its live weights, Weight1 first.
func weights() -> Array[WeightBody]:
	var out: Array[WeightBody] = []
	var names := _weights.keys()
	names.sort()
	for n: String in names:
		var w: Variant = _weights[n]
		if is_instance_valid(w) and not w.gone:
			out.append(w)
	return out


func _spawn(n: String) -> void:
	var w: WeightBody = weight_scene.instantiate()
	w.name = n
	w.dispensed = true
	add_child(w)
	_weights[n] = w
	_remember()


func _free_name() -> String:
	var i := 1
	while _weights.has("Weight%d" % i) or has_node(NodePath("Weight%d" % i)): # a freed one may linger this frame
		i += 1
	return "Weight%d" % i


## Nothing where a new weight would appear.
func _spot_clear() -> bool:
	var space := get_world_3d().direct_space_state
	for s: Array in _probe:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = s[0]
		q.transform = global_transform * (s[1] as Transform3D)
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


func _remember() -> void:
	World.bodies[_id()] = {alive = PackedStringArray(_weights.keys())}


func _id() -> String:
	return Channels.id(self)


func _get_configuration_warnings() -> PackedStringArray:
	if weight_scene == null:
		return PackedStringArray(["Set weight_scene (puzzle/box.tscn, puzzle/ball.tscn...)."])
	return PackedStringArray()
