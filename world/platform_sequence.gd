@tool
class_name PlatformSequence
extends Node
## One step of a MovingPlatform's program (a child of the platform; children play in order):
## `laps` passes along `path`, each after a `lap_wait` pause, then a `sequence_wait` pause.
## A pass is the path's length from its start point: on an open path lap 1 reaches the end
## and lap 2 is back at the start; on a closed path every lap goes round once.

@export var path: Path3D ## empty = the platform's parent Path3D
@export_range(1, 100, 1, "or_greater") var laps := 1
@export var speed := 2.0 ## m/s (times the channel's speed multiplier)
@export var lap_wait := 0.5 ## pause before each lap; the first one doubles as a start delay
@export var sequence_wait := 0.0 ## pause after the last lap


func _validate_property(p: Dictionary) -> void:
	# a platform with shared_waits uses its own lap_wait / sequence_wait for every sequence
	if p.name in ["lap_wait", "sequence_wait"] and get_parent() and get_parent().get("shared_waits"):
		p.usage = PROPERTY_USAGE_NO_EDITOR
