extends Node3D
## PBR material showcase. A day/night cycle moves the sun and moon, tints the procedural sky
## and turns the lamps on at dusk. Global illumination is the baked VoxelGI (re-bake it after moving
## the static geometry). Drag to orbit, mouse wheel to zoom.

## Hour of day, 0-24. The sun rises in the east (+X) at 6 and sets at 18.
@export_range(0.0, 24.0, 0.01) var hour := 10.0
## Clock speed in game hours per real second; 0 stops the clock.
@export_range(0.0, 4.0, 0.01) var hours_per_second := 0.2
## Tilts the sun's path towards +Z (south), so noon shadows don't fall straight down.
@export_range(1.0, 80.0) var sun_tilt_degrees := 35.0
@export var sun_energy := 1.0
@export var moon_energy := 0.15
@export var lamp_energy := 2.0
## Sky and sunlight colours, sampled by sun height: 0 = midnight, 0.5 = horizon, 1 = zenith.
@export var sky_top: Gradient
@export var sky_horizon: Gradient
@export var sun_color: Gradient

@onready var env: Environment = $WorldEnvironment.environment
@onready var sky: ProceduralSkyMaterial = env.sky.sky_material
@onready var sun: DirectionalLight3D = $Sun
@onready var moon: DirectionalLight3D = $Moon
@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera
@onready var time_slider: HSlider = %TimeSlider
@onready var speed_slider: HSlider = %SpeedSlider
@onready var time_label: Label = %TimeLabel


func _ready() -> void:
	speed_slider.value = hours_per_second
	time_slider.value_changed.connect(func(v: float) -> void: hour = v)
	speed_slider.value_changed.connect(func(v: float) -> void: hours_per_second = v)


func _process(delta: float) -> void:
	hour = fposmod(hour + hours_per_second * delta, 24.0)
	time_slider.set_value_no_signal(hour)
	time_label.text = "Time %02d:%02d    speed %.2f h/s" % [int(hour), int(fmod(hour, 1.0) * 60.0), hours_per_second]
	apply_time()


## Places the sun and moon for `hour` and fades the lights and sky to match. Returns the sun height (-1..1).
func apply_time() -> float:
	var a := (hour - 6.0) / 24.0 * TAU
	var tilt := deg_to_rad(sun_tilt_degrees)
	var to_sun := Vector3(cos(a), sin(a) * cos(tilt), sin(a) * sin(tilt))
	var h := to_sun.y
	var night := 1.0 - smoothstep(-0.1, 0.05, h)
	_aim(sun, to_sun, sun_energy * smoothstep(-0.02, 0.1, h))
	_aim(moon, -to_sun, moon_energy * night)
	for lamp: Light3D in $Lamps.get_children():
		lamp.light_energy = lamp_energy * night
		lamp.visible = night > 0.0
	var t := (h + 1.0) * 0.5
	sun.light_color = sun_color.sample(t)
	sky.sky_top_color = sky_top.sample(t)
	sky.sky_horizon_color = sky_horizon.sample(t)
	sky.ground_horizon_color = sky.sky_horizon_color
	sky.ground_bottom_color = sky.sky_horizon_color.darkened(0.8)
	return h


func _aim(light: DirectionalLight3D, to_light: Vector3, energy: float) -> void:
	light.visible = energy > 0.0
	light.light_energy = energy
	light.basis = Basis.looking_at(-to_light)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		pivot.rotation.y -= e.relative.x * 0.005
		pivot.rotation.x = clampf(pivot.rotation.x - e.relative.y * 0.005, -1.45, -0.05)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom := 0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
		camera.position.z = clampf(camera.position.z * zoom, 3.0, 40.0)
