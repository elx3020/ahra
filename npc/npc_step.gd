@tool
class_name NpcStep
extends Resource
## One step of an NpcInteraction. Steps run back to back until one waits (a line waiting for the
## interact key, a walk, a timed wait), so a "beat" is everything up to the next wait.
## `kind` picks what the step does; the inspector shows only that kind's fields (FIELDS), and
## `resource_name` keeps a one-line summary, which the inspector shows on the steps array rows.

enum Kind { SAY, ANIM, FACE, LOOK, MOVE, SOUND, WAIT, FLAG, LEAVE }
enum Look { PLAYER, MARK, AHEAD }

## The fields each kind uses; the others are hidden in the inspector.
const FIELDS := {
	Kind.SAY: ["lines", "time"],
	Kind.ANIM: ["anim", "time"],
	Kind.FACE: ["face"],
	Kind.LOOK: ["look", "mark"],
	Kind.MOVE: ["mark", "run", "wait"],
	Kind.SOUND: ["sound", "sound_wait"],
	Kind.WAIT: ["time"],
	Kind.FLAG: ["flag", "value"],
	Kind.LEAVE: ["flag", "fade"],
}
const ALL := ["lines", "time", "anim", "face", "look", "mark", "run", "wait", "sound", "sound_wait", "flag", "value", "fade"]

@export var kind := Kind.SAY:
	set(v): kind = v; notify_property_list_changed(); _named()
## SAY: versions of the line; one is picked at random, never the one shown last time.
@export var lines: PackedStringArray:
	set(v): lines = v; _named()
## SAY: seconds a line shows when the interaction doesn't lock the player (0: from its length).
## ANIM: seconds to hold before the next step (0: go on at once). WAIT: seconds (0: the key).
@export var time := 0.0:
	set(v): time = v; _named()
@export var anim: StringName: ## ANIM: the `anim` the NPC plays until another step changes it
	set(v): anim = v; _named()
@export var face: StringName: ## FACE: the expression, until another step changes it
	set(v): face = v; _named()
@export var look := Look.PLAYER: ## LOOK: what the head follows for the rest of the interaction
	set(v): look = v; _named()
@export var mark: StringName: ## MOVE / LOOK: a Marker3D under the NPC's Marks, by name
	set(v): mark = v; _named()
@export var run := false: ## MOVE: run instead of walk
	set(v): run = v; _named()
@export var wait := true: ## MOVE: wait for the arrival; off: the next step starts while walking
	set(v): wait = v; _named()
@export var sound: AudioStream: ## SOUND: played on the NPC's Voice
	set(v): sound = v; _named()
@export var sound_wait := false: ## SOUND: wait until it ends
	set(v): sound_wait = v; _named()
@export var flag: StringName: ## FLAG: the story flag to set. LEAVE: set when the NPC leaves (optional)
	set(v): flag = v; _named()
@export var value := 1: ## FLAG: the value (0 clears)
	set(v): value = v; _named()
@export var fade := 0.4: ## LEAVE: seconds of each half of the fade to black
	set(v): fade = v; _named()


func _validate_property(property: Dictionary) -> void:
	if property.name in ALL and property.name not in FIELDS[kind]:
		property.usage &= ~PROPERTY_USAGE_EDITOR


## One line for the inspector: `say "Hello, stranger." (+2)`, `move → Well (run)`...
func summary() -> String:
	match kind:
		Kind.SAY:
			if lines.is_empty():
				return "say (no lines)"
			var first := lines[0] if lines[0].length() <= 32 else lines[0].left(31) + "…"
			return 'say "%s"' % first + (" (+%d)" % (lines.size() - 1) if lines.size() > 1 else "")
		Kind.ANIM:
			return "anim %s" % anim + (" %.1fs" % time if time > 0.0 else "")
		Kind.FACE:
			return "face %s" % face
		Kind.LOOK:
			return "look " + ["player", "mark %s" % mark, "ahead"][look]
		Kind.MOVE:
			return "move → %s" % mark + (" (run)" if run else "") + ("" if wait else " (no wait)")
		Kind.SOUND:
			if sound == null:
				return "sound none"
			return "sound " + (sound.resource_path.get_file() if sound.resource_path.begins_with("res://") else "(embedded)")
		Kind.WAIT:
			return "wait key" if time <= 0.0 else "wait %.1fs" % time
		Kind.FLAG:
			return "flag %s = %d" % [flag, value]
		Kind.LEAVE:
			return "leave" + (" → %s" % flag if flag else "")
	return "?"


## A random index into `lines`, never `last` when there are two or more (-1 when empty).
func pick_line(last: int) -> int:
	var n := lines.size()
	if n == 0:
		return -1
	if n == 1 or last < 0 or last >= n:
		return randi() % n
	return (last + 1 + randi() % (n - 1)) % n


## How long `text` shows when nobody presses the key: `time`, or 1 s plus 0.04 s per character.
func say_time(text: String) -> float:
	return time if time > 0.0 else 1.0 + 0.04 * text.length()


func _named() -> void:
	resource_name = summary()
