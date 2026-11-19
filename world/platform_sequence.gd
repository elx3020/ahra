@tool
class_name PlatformSequence
extends Resource
## One step of a track's program (PlatformTrackInstance.sequences, played in order): moves the
## platform between two anchors of the track's path, through the anchors between them.
## A trip goes start -> end (one way) or start -> end -> start (round trip); several one-way
## trips alternate direction. The platform pauses `start_wait` at the start anchor before each
## departure and `end_wait` at the end anchor on each arrival. Each sequence starts where the
## previous one left the platform (the track keeps `start_anchor` in step).
## trips = 0 repeats forever (it must be the last sequence): round trip forever = ping-pong,
## a full lap forever on a closed path = loop.

@export var start_anchor := 0 ## first sequence only: later ones start where the previous one leaves the platform
@export var end_anchor := 1 ## differs from start_anchor, except on a closed path: the same anchor = a full lap
@export var round_trip := false ## a trip goes there and back (off: one way)
@export_range(0, 100, 1, "or_greater") var trips := 1 ## 0 = forever
@export var speed := 2.0 ## m/s (times the channel's speed multiplier)
@export var start_wait := 0.5 ## seconds at the start anchor before each departure
@export var end_wait := 0.5 ## seconds at the end anchor on each arrival

var locked := false ## set by the track: start_anchor follows the previous sequence


func _validate_property(p: Dictionary) -> void:
	if p.name == "start_anchor" and locked:
		p.usage |= PROPERTY_USAGE_READ_ONLY


## The anchor it leaves the platform at (a forever sequence never does).
func finish_anchor() -> int:
	if start_anchor == end_anchor:
		return start_anchor
	return end_anchor if trips * (2 if round_trip else 1) % 2 == 1 else start_anchor


## Its legs alternate direction (always, except one-way full laps).
func turns() -> bool:
	return round_trip or start_anchor != end_anchor
