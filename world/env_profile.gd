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
