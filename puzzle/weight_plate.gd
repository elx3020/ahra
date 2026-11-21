@tool
class_name WeightPlate
extends Zone
## A pressure plate: on while something rests on its face. The player, an enemy, an NPC or a
## weight (not a carried one) counts when its gravity points into the plate, so a plate on a wall
## or a ceiling works once gravity sends something onto it. One body is enough.
## HOLD: on only while pressed. LATCH: springs back up until every switch on its channel is on at
## the same moment, then locks on for good (World._check_lock). Doors on the same channel open when
## all its switches are on (World.openness). Its state lives in World.switches, so it survives scene
## changes: an area unloading leaves it as it was, and a loading plate waits WARMUP frames (restored
## weights settle) before it reads what rests on it.
## Its shapes are the detection volume: a thin slab over the plate's face; its up is its basis Y.

signal cue(name: StringName) ## press, release, lock

enum Mode { HOLD, LATCH }

const WARMUP := 3 ## physics frames after loading before it reads what rests on it

@export var channel: StringName:
	set(v):
		channel = v
		update_configuration_warnings()
@export var mode := Mode.HOLD
@export var on_color := Color(0.3, 1.0, 0.4, 0.5)
@export var locked_color := Color(1.0, 0.8, 0.3, 0.5)

var pressed := false ## something rests on it now

var _warm := WARMUP
var _synced := false ## pressed has been taken from World's saved state
var _was_locked := false


func _ready() -> void:
	super()
	add_to_group(&"door_switch")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _warm > 0:
		_warm -= 1
		return
	if not _synced: # what the area left it as: no cue for a plate that is still pressed
		_synced = true
		pressed = World.switches.get(switch_id(), {}).get("on", false)
		_was_locked = _locked()
	var now := get_overlapping_bodies().any(counts)
	if now != pressed:
		pressed = now
		World.press(Channels.key(self, channel), switch_id(), pressed)
		cue.emit(&"press" if pressed else &"release")
	var locked := _locked()
	if locked and not _was_locked:
		cue.emit(&"lock")
	_was_locked = locked
	_paint()


## "hold" or "latch": how World and the switch registry tell plates apart.
func kind() -> String:
	return "latch" if mode == Mode.LATCH else "hold"


## Its key in World.switches.
func switch_id() -> String:
	return Channels.id(self)


func is_on() -> bool:
	return World.switch_on(switch_id())


## Whether `b` presses the plate: a character or a weight that isn't carried, whose gravity points
## into the plate's face.
func counts(b: Node3D) -> bool:
	var g: Vector3
	if b is WeightBody:
		var w := b as WeightBody
		if w.carrier != null or w.gone:
			return false
		g = w.gravity_dir
	elif b is Player or b is Enemy or b.is_in_group(&"npc"):
		g = -(b as CharacterBody3D).up_direction
	else:
		return false
	return g.dot(global_basis.y.normalized()) < -0.7


func _locked() -> bool:
	return World.switches.get(switch_id(), {}).get("locked", false)


## Locked / on / off colours; the drawn slab sinks a little while on.
func _paint() -> void:
	var on := is_on()
	_mat.albedo_color = locked_color if _locked() else (on_color if on else color)
	for cs in shapes():
		for m in cs.get_children(true):
			if m.name == ShapeSet.MESH:
				(m as Node3D).position = cs.basis.inverse() * Vector3.DOWN * (0.05 if on else 0.0)


func _get_configuration_warnings() -> PackedStringArray:
	if channel == &"":
		return PackedStringArray(["Set a channel: the doors on it open when every switch on it is on."])
	return PackedStringArray()
