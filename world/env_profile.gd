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
@export_group("Camera")
@export_range(0.0, 1.0) var shake := 0.0 ## camera shake while the player is in it (a storm), see CameraShake
@export_group("Time")
## The whole game's speed while the player is in it (a slow place), see SlowMo. The player slows too.
@export_range(0.05, 1.0) var time_scale := 1.0


## Blend overlapping zones on top of a base: stat % add up (same rule as progression), shake overlaps,
## wind and drag add, gravity and time scale multiply, water if any, temperature = last non-mild.
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
		out.time_scale *= e.time_scale
		out.shake = 1.0 - (1.0 - out.shake) * (1.0 - e.shake) # CameraShake's overlap rule
		out.water = out.water or e.water
		if e.temperature != Temp.MILD:
			out.temperature = e.temperature
		if e.resource_name:
			names.append(e.resource_name)
	out.resource_name = " + ".join(names)
	return out
