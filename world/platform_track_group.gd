@tool
class_name PlatformTrackGroup
extends Node3D
## Container for PlatformTrackInstances (its direct children): move or rotate it to move the
## whole set, and choose how the editor shows its tracks. Each instance reads these settings.

@export var preview := false ## animate the group's platforms in the editor, all on one clock
@export var show_paths := true ## show the tracks' Path3D curves in the editor
@export var show_destination := true ## a ghost of each platform at the end of its path(s)
