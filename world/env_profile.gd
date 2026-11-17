class_name EnvProfile
extends Resource
## How a location affects the player. Name it via resource_name.
## `mods` are % changes to player stats (stack with progression bonuses);
## gravity/drag/wind/water are world physics, not player stats.

enum Temp { COLD, MILD, HOT }

@export var temperature := Temp.MILD
@export var mods := StatMods.new()
@export_group("Physics")
@export var water := false ## swimmable; the EnvZone's top face is the surface
@export var gravity_mult := 1.0
@export var drag := 0.0 ## velocity damping per second (water, thick air)
## Acceleration, always applied. Along the walking plane it pushes the player
## (on ground and in air, see Player.wind_response_*); along up it is lift.
@export var wind := Vector3.ZERO


## Blend overlapping zones on top of a base: stat % add up (same rule as progression),
## wind and drag add, gravity multiplies, water if any, temperature = last non-mild.
static func combine(base: EnvProfile, layers: Array[EnvProfile]) -> EnvProfile:
	var out := EnvProfile.new()
	var names := PackedStringArray()
	var stats := StatMods.names()
	for e: EnvProfile in [base] + layers:
		for s in stats:
			out.mods.set(s, out.mods.get(s) + e.mods.get(s))
		out.wind += e.wind
		out.drag += e.drag
		out.gravity_mult *= e.gravity_mult
		out.water = out.water or e.water
		if e.temperature != Temp.MILD:
			out.temperature = e.temperature
		if e.resource_name:
			names.append(e.resource_name)
	out.resource_name = " + ".join(names)
	return out
