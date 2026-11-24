extends GameArea
## The forest of enviroment_test.tscn as a playable area with a day/night cycle (the Weather node;
## at 9:46 its sun is deep_forest.blend's). The Canopy is a shadow-only plane 300 m up whose holes
## dapple the light: it slides along the ray from canopy_anchor to whichever light is up, so its
## shadow stays on the forest at every hour.

## Ground point the canopy's middle stays above, along the light (deep_forest.blend's placement).

@onready var weather: Weather = $Weather


func _ready() -> void:
	super()


func _process(delta: float) -> void:
	super(delta)
