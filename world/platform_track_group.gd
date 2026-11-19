@tool
class_name PlatformTrackGroup
extends PlatformProgram
## Keeps PlatformTrackInstances (its direct children) organized: move or rotate it to move them
## all, and choose how the editor shows them (preview plays all of them). Two modes:
## - independent (circuit off): each track runs its own platform;
## - circuit: the tracks share one platform (the group's MovingPlatform child), which plays
##   each track's sequences in turn, in child order; the timing settings are the group's.
##   Turn it on in the inspector: the Platform Tools move the platform, drop the others and join
##   each track's end to the next one's start, halfway between them (also the last back to the
##   first when the circuit starts over).

@export var circuit := false: ## the tracks share one platform that rides them in order
	set(v):
		circuit = v
		notify_property_list_changed()
		for t in get_children():
			t.notify_property_list_changed()
@export var show_paths := true ## show the tracks' Path3D curves in the editor
@export var show_destination := true ## a ghost of the platform at the end of each path


var _warned := PackedStringArray()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var w := _get_configuration_warnings()
		if w != _warned:
			_warned = w
			update_configuration_warnings()


func plays() -> bool:
	return circuit


func tracks() -> Array:
	return get_children().filter(func(c: Node) -> bool: return c is PlatformTrackInstance)


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var plats := get_children().filter(func(c: Node) -> bool: return c is MovingPlatform).size()
	if circuit and plats != 1:
		out.append("A circuit needs exactly one MovingPlatform child, which rides every track (has %d)." % plats)
	elif not circuit and plats > 0:
		out.append("Only a circuit has a platform of its own: each track has its platform.")
	var ts := tracks()
	if circuit and after_last == End.START_OVER and ts.size() > 1 and ts[-1].path() and ts[0].path():
		var gap: float = ts[-1].last_point().distance_to(ts[0].first_point())
		if gap > 0.05:
			out.append("Starting over, the platform would jump %.2f m from the last track's end to the first's start (Reconnect joins them, or play backwards)." % gap)
	return out
