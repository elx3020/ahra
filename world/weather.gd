class_name Weather
extends Node
## Time of day for an area, and the home of its weather to come. Moves the sun and moon with the
## hour, colours the procedural sky and the sunlight, turns lamps on at dusk, and publishes the
## state as global shader uniforms (project.godot [shader_globals]) that any shader can read:
##   sun_direction  vec3   towards the sun, world space (below the horizon at night)
##   sun_color      color  the sunlight colour
##   daylight       float  1 by day, 0 by night
##   time_of_day    float  hour / 24
## Weather state (rain, wind...) belongs here too, as exports published the same way.
## ponytail: the hour lives in this node, so each area starts at its own; move it to World (and the
## save) when areas share one clock.

## Hour of day, 0-24. The sun rises in the east (+X) at 6 and sets at 18.
@export_range(0.0, 24.0, 0.01) var hour := 10.0
## Clock speed in game hours per real second; 0 stops the clock.
@export_range(0.0, 4.0, 0.01) var hours_per_second := 0.2
## Leans the sun's path towards +Z (negative: towards -Z), so noon shadows don't fall straight down.
@export_range(-80.0, 80.0) var sun_tilt_degrees := 35.0
@export var sun_energy := 1.0
@export var moon_energy := 0.15
@export var lamp_energy := 2.0
## Sky and sunlight colours, sampled by sun height: 0 = midnight, 0.5 = horizon, 1 = zenith.
@export var sky_top: Gradient
@export var sky_horizon: Gradient
@export var sun_color: Gradient
## How much of the horizon colour the sky's lower half gets. 0 = black, for areas whose floor hides
## it from every surface (otherwise ambient light comes up through the ground).
@export_range(0.0, 1.0) var ground_light := 1.0
@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
## Its sky must be a ProceduralSkyMaterial.
@export var world_environment: WorldEnvironment
## Optional: its Light3D children turn on at dusk.
@export var lamps: Node
## Debug panel (bottom right) with hour and clock speed sliders.
@export var show_panel := true

## Direction towards the sun, world space.
var sun_direction := Vector3.UP
var _time_slider: HSlider
var _time_label: Label


func _ready() -> void:
	# moved every render frame, not on physics ticks
	sun.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	moon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if show_panel:
		_make_panel()
	apply()


func _process(delta: float) -> void:
	hour = fposmod(hour + hours_per_second * delta, 24.0)
	apply()


## Places the sun and moon for `hour`, fades the lights and sky to match, publishes the globals.
func apply() -> void:
	var a := (hour - 6.0) / 24.0 * TAU
	var tilt := deg_to_rad(sun_tilt_degrees)
	sun_direction = Vector3(cos(a), sin(a) * cos(tilt), sin(a) * sin(tilt))
	var h := sun_direction.y
	var daylight := smoothstep(-0.02, 0.1, h)
	var night := 1.0 - smoothstep(-0.1, 0.05, h)
	_aim(sun, sun_direction, sun_energy * daylight)
	_aim(moon, -sun_direction, moon_energy * night)
	if lamps:
		for lamp: Light3D in lamps.get_children():
			lamp.light_energy = lamp_energy * night
			lamp.visible = night > 0.0
	var t := (h + 1.0) * 0.5
	sun.light_color = sun_color.sample(t)
	var sky := world_environment.environment.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = sky_top.sample(t)
	sky.sky_horizon_color = sky_horizon.sample(t)
	sky.ground_horizon_color = Color.BLACK.lerp(sky.sky_horizon_color, ground_light)
	sky.ground_bottom_color = Color.BLACK.lerp(sky.sky_horizon_color.darkened(0.8), ground_light)
	RenderingServer.global_shader_parameter_set(&"sun_direction", sun_direction)
	RenderingServer.global_shader_parameter_set(&"sun_color", sun.light_color)
	RenderingServer.global_shader_parameter_set(&"daylight", daylight)
	RenderingServer.global_shader_parameter_set(&"time_of_day", hour / 24.0)
	if _time_slider:
		_time_slider.set_value_no_signal(hour)
		_time_label.text = "Time %02d:%02d    speed %.2f h/s" % [int(hour), int(fmod(hour, 1.0) * 60.0), hours_per_second]


func _aim(light: DirectionalLight3D, to_light: Vector3, energy: float) -> void:
	light.visible = energy > 0.0
	light.light_energy = energy
	light.basis = Basis.looking_at(-to_light)


func _make_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_time_label = Label.new()
	box.add_child(_time_label)
	_time_slider = _slider(box, 24.0, func(v: float) -> void: hour = v)
	var speed_label := Label.new()
	speed_label.text = "Clock speed (hours per second)"
	box.add_child(speed_label)
	_slider(box, 4.0, func(v: float) -> void: hours_per_second = v).value = hours_per_second
	# bottom right (clear of GameArea's debug text), sized now that it has its contents
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)


func _slider(box: VBoxContainer, max_value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.max_value = max_value
	s.step = 0.01
	s.custom_minimum_size.x = 300.0
	s.focus_mode = Control.FOCUS_NONE # keys keep driving the game
	s.value_changed.connect(on_change)
	box.add_child(s)
	return s
