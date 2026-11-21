@tool
class_name Door
extends MovingPlatform
## A sliding door: open while every switch on its `channel` is on (World.openness), slid by
## `open_offset` (in its own axes). It opens over open_time; closing follows a draining energy
## switch exactly, else takes open_time. A closing door never crushes: whoever is in the doorway
## is moved out to the nearer side first.
## It reuses MovingPlatform as a solid body shaped by ShapeSet (shapes, colour, surface); there is
## no track. Its amount is a function of World's switch state, so it is right when an area loads.

signal cue(name: StringName) ## open, close, locked (open for good: its channel is solved)

@export var channel: StringName:
	set(v):
		channel = v
		update_configuration_warnings()
@export var open_offset := Vector3(0, 3, 0) ## slide when fully open, in the door's own axes
@export var open_time := 0.4 ## seconds to open, and to close when plates release

var amount := 0.0 ## 0 shut .. 1 open

var _closed := Vector3.ZERO ## position when shut
var _was_locked := false


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_closed = position
	amount = World.openness(_key()) # in place before any physics move: no sweep on load
	_place()
	_was_locked = locked()


func _physics_process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	var target := World.openness(_key())
	var rate := delta / maxf(open_time, 0.01)
	var next := amount
	if target > amount:
		next = move_toward(amount, target, rate)
	elif target < amount:
		next = maxf(target, amount - rate)
		_push_out(next)
	if next != amount:
		if amount == 0.0:
			cue.emit(&"open")
		elif next == 0.0:
			cue.emit(&"close")
		amount = next
		_place()
	var l := locked()
	if l and not _was_locked:
		cue.emit(&"locked")
	_was_locked = l


## Open for good: every switch on its channel is a locked latch plate.
func locked() -> bool:
	return channel != &"" and World.solved(_key())


func _key() -> StringName:
	return Channels.key(self, channel)


func _place() -> void:
	position = _closed + basis * open_offset * amount


## Before closing to `next`: everything the door would overlap there goes out of the doorway, to
## the side of the door's thinnest axis (across the slide) its centre is on.
func _push_out(next: float) -> void:
	var to := global_transform
	to.origin += global_basis * open_offset * (next - amount)
	var box := ShapeSet.bounds(self)
	var slide := open_offset.normalized()
	var axis := -1
	for i in 3:
		var a := Vector3.ZERO
		a[i] = 1.0
		if absf(a.dot(slide)) < 0.5 and (axis < 0 or box.size[i] < box.size[axis]):
			axis = i
	if axis < 0:
		return
	var local_n := Vector3.ZERO
	local_n[axis] = 1.0
	var n := (to.basis * local_n).normalized()
	var plane := to * box.get_center()
	var keep := box.size[axis] * 0.5 + 0.6
	var space := get_world_3d().direct_space_state
	var moved := {}
	for cs in shapes():
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = to * cs.transform
		q.exclude = [get_rid()]
		for hit: Dictionary in space.intersect_shape(q, 8):
			var b := hit.collider as Node3D
			if b == null or moved.has(b) or not (b is CharacterBody3D or (b is WeightBody and b.carrier == null)):
				continue
			moved[b] = true
			var d := (b.global_position - plane).dot(n)
			var side := 1.0 if d >= 0.0 else -1.0
			if absf(d) >= keep:
				continue
			var dest := b.global_position + n * (side * keep - d)
			if b is Player:
				(b as Player).teleport(dest)
			else:
				b.global_position = dest
				b.reset_physics_interpolation()


func _get_configuration_warnings() -> PackedStringArray:
	if channel == &"":
		return PackedStringArray(["Set a channel: the door opens when every switch on it is on."])
	if is_inside_tree() and not _has_switches():
		return PackedStringArray(["No switch uses channel %s (in any saved scene or this one): the door would never open." % _key()])
	return PackedStringArray()


## Some switch uses the channel: the baked registry (every saved scene) or a loaded one. Not
## through World: the autoload doesn't run in the editor.
func _has_switches() -> bool:
	var key := _key()
	if ResourceLoader.exists(SwitchRegistry.PATH):
		var reg := load(SwitchRegistry.PATH) as SwitchRegistry
		if reg and reg.channels.has(String(key)):
			return true
	return get_tree().get_nodes_in_group(&"door_switch").any(func(n: Node) -> bool:
		return Channels.key(n, n.channel) == key)
