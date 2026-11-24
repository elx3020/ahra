extends GameArea
## The forest of enviroment_test.tscn as a playable area with a day/night cycle (the Weather node;
## at 9:46 its sun is deep_forest.blend's). The Canopy is a shadow-only plane 300 m up whose holes
## dapple the light: it slides along the ray from canopy_anchor to whichever light is up, so its
## shadow stays on the forest at every hour.

## Ground point the canopy's middle stays above, along the light (deep_forest.blend's placement).
@export var canopy_anchor := Vector3(0.646, 0.0, -5.561)

@onready var weather: Weather = $Weather
@onready var canopy: Node3D = $Canopy
@onready var canopy_height := canopy.position.y


func _ready() -> void:
	super()
	canopy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # moved every render frame


func _process(delta: float) -> void:
	super(delta)
	var to_light := weather.sun_direction if weather.sun_direction.y > 0.0 else -weather.sun_direction
	canopy.position = canopy_anchor + to_light * (canopy_height / maxf(to_light.y, 0.05))
