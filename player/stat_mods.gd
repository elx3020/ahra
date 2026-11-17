class_name StatMods
extends Resource
## Percentage modifiers on the player's base stats. 0.2 = +20%, -0.3 = -30%.
## Used for permanent progression (Player.progression, the thing to save) and for
## environment effects (EnvProfile.mods). All sources are summed, then applied to base:
##   final = base * (1 + progression% + environment%)
## Base values themselves are the design-tuned exports on Player (not saved).

@export var speed := 0.0 ## walk_speed, run_speed
@export var traction := 0.0 ## ground accel/decel; negative = slippery
@export var jump := 0.0 ## jump_height
@export var dash := 0.0 ## dash_time (= dash distance)
@export var climb := 0.0 ## climb_speed
@export var swing := 0.0 ## swing_force
@export var max_health := 0.0
@export var max_stamina := 0.0
@export var stamina_regen := 0.0
@export var stamina_cost := 0.0 ## run_cost; positive = more tiring


## Names of all stats, for UI/debug/save code.
static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for prop in (StatMods.new() as Object).get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(prop.name)
	return out
