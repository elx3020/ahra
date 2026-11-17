class_name EnvProfile
extends Resource
## How a location affects the player. Name it via resource_name.
## `mods` are % changes to player stats (stack with progression bonuses);
## gravity/drag/wind are world physics, not player stats.

enum Temp { COLD, MILD, HOT }

@export var temperature := Temp.MILD
@export var mods := StatMods.new()
@export_group("Physics")
@export var gravity_mult := 1.0
@export var drag := 0.0 ## velocity damping per second (water, thick air)
@export var wind := Vector3.ZERO ## acceleration while airborne
