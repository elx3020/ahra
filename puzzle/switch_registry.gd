class_name SwitchRegistry
extends Resource
## Every door switch in every saved scene, by channel: what a door counts, so a switch in an area
## the player hasn't visited yet still keeps its door shut (it counts as off). Baked by the
## Platform Tools plugin on each scene save (channel_registry.gd), read by World at startup.

const PATH := "res://world/switch_registry.tres"

## channel key ("area:name", see Channels) -> Array of [switch id (Channels.id), kind], kind being
## "hold", "latch" or "energy".
@export var channels := {}
