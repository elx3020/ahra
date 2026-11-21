@tool
class_name EnergySwitch
extends MovingPlatform
## A switch charged by the player's shots (Projectile calls shot()): each shot adds time_to_close
## seconds of energy, up to time_to_close * max_shots. It is on while it has energy, so its doors
## snap open, then slide shut as the energy drains (World.openness), slower for each extra shot.
## Energy is stored as world times, so it keeps draining while its area isn't loaded.
## Aim assist aims at it (group aim_target). It reuses MovingPlatform as a solid body shaped by
## ShapeSet (no track).

signal cue(name: StringName) ## charge, empty

@export var channel: StringName
@export var time_to_close := 4.0 ## seconds of energy per shot
@export var max_shots := 3 ## the energy cap is time_to_close * max_shots
@export var on_color := Color(0.4, 0.85, 1.0)

var _was_on := false


func _ready() -> void:
	super()
	add_to_group(&"door_switch")
	add_to_group(&"aim_target")


func _physics_process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	var f := fraction()
	_mat.albedo_color = color.lerp(on_color, f)
	_mat.emission_enabled = f > 0.0
	_mat.emission = on_color
	_mat.emission_energy_multiplier = 2.0 * f
	if _was_on and f <= 0.0:
		cue.emit(&"empty")
	_was_on = f > 0.0


## A shot landed: more energy, capped.
func shot() -> void:
	World.charge(Channels.key(self, channel), switch_id(), time_to_close, time_to_close * max_shots)
	cue.emit(&"charge")


func kind() -> String:
	return "energy"


## Its key in World.switches.
func switch_id() -> String:
	return Channels.id(self)


## Energy left, 0..1 of what it had at its last shot.
func fraction() -> float:
	return World.energy(switch_id())


func _get_configuration_warnings() -> PackedStringArray:
	if channel == &"":
		return PackedStringArray(["Set a channel: shooting the switch opens the doors on it."])
	return PackedStringArray()
