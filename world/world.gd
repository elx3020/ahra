extends Node
## Autoload "World": state that outlives scene changes. The world clock and the
## platform activation channels live here, so every area computes its platforms from
## the same timeline. Saving the game = saving `time` and `channels` (plain data).

var time := 0.0 ## world seconds; pauses with the tree, keeps running across scene changes
var spawn: StringName ## marker the next area puts the player at (set by SceneDoor)
## channel -> [completed active seconds, window start, window end]. One window at a time,
## end = INF while a toggle is on. Platforms on a channel move only inside its windows.
var channels := {}


func _physics_process(delta: float) -> void:
	time += delta


## Seconds a channel has been on in total, up to now.
func active_time(channel: StringName) -> float:
	var c: Array = channels.get(channel, [0.0, 0.0, 0.0])
	return c[0] + maxf(0.0, minf(time, c[2]) - c[1])


func is_on(channel: StringName) -> bool:
	return channel in channels and time < channels[channel][2]


## A switch press. run_time 0 = toggle on/off; > 0 = on for run_time seconds (re-press restarts).
func press(channel: StringName, run_time := 0.0) -> void:
	var done := active_time(channel)
	var end := time + run_time if run_time > 0.0 else (time if is_on(channel) else INF)
	channels[channel] = [done, time, end]
