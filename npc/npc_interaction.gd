@tool
class_name NpcInteraction
extends Resource
## One thing an NPC can do with the player: a straight sequence of NpcSteps, started by the
## interact key (KEY, in the NPC's Talk zone) or by the player coming within `distance` (NEAR).
## The NPC plays the first available interaction of its list with that trigger, so list order is
## priority: later-game interactions (with `needs`) go above earlier ones.
## `resource_name` keeps a one-line summary, shown on the NPC's interactions array rows.

enum Trigger { KEY, NEAR }

## Memory key (how many times it played). Unique per NPC; the NPC Tools templates fill it in.
@export var id: StringName:
	set(v): id = v; _named()
@export var trigger := Trigger.KEY:
	set(v): trigger = v; notify_property_list_changed(); _named()
@export var distance := 4.0: ## NEAR: fires when the player comes this close (m)
	set(v): distance = v; _named()
@export var needs: PackedStringArray: ## story flags that must all be set (World.flags)
	set(v): needs = v; _named()
@export var once := false: ## plays a single time, ever
	set(v): once = v; _named()
## The player stands still (puppet) and the interact key advances the lines. Off: lines advance
## on their timers and the player keeps moving (a bark).
@export var locks_player := true:
	set(v): locks_player = v; _named()
@export var steps: Array[NpcStep] = []:
	set(v): steps = v; _named()


func _validate_property(property: Dictionary) -> void:
	if property.name == "distance" and trigger != Trigger.NEAR:
		property.usage &= ~PROPERTY_USAGE_EDITOR


## Whether it can play: every `needs` flag is set in `flags` (World.flags), and a `once`
## interaction hasn't played yet (`plays`: times played so far).
func available(flags: Dictionary, plays: int) -> bool:
	for n: String in needs:
		if flags.get(n, 0) <= 0:
			return false
	return not (once and plays > 0)


## One line for the inspector: `talk · key · once · needs chapter2 · 5 steps`. Defaults are left
## out (locking is shown only when it differs from the trigger's usual: KEY locks, NEAR doesn't).
func summary() -> String:
	var parts := PackedStringArray([String(id) if id else "?"])
	parts.append("key" if trigger == Trigger.KEY else "near %s m" % String.num(distance))
	if once:
		parts.append("once")
	if locks_player != (trigger == Trigger.KEY):
		parts.append("locks" if locks_player else "free")
	if not needs.is_empty():
		parts.append("needs " + ", ".join(needs))
	parts.append("%d step%s" % [steps.size(), "" if steps.size() == 1 else "s"])
	return " · ".join(parts)


func _named() -> void:
	resource_name = summary()
