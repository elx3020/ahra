extends GameArea
## Stress demo: 150 runners on a flat world-boundary (plane) floor.
## Grid cells are taken outermost-first, so the middle stays clear for the player.
## Set SHOW_DEBUG to true to restore the per-enemy state labels.

const ENEMY: PackedScene = preload("res://enemy/runner/runner.tscn")
const COUNT := 150
const COLS := 16
const ROWS := 11
const SPACING := 3.5
const SHOW_DEBUG := false

@onready var enemies: Node3D = $Enemies


func _ready() -> void:
	super._ready()
	var spots: Array[Vector3] = []
	for row in ROWS:
		for col in COLS:
			spots.append(Vector3(
				(col - (COLS - 1) * 0.5) * SPACING,
				1.0,
				(row - (ROWS - 1) * 0.5) * SPACING
			))
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.length_squared() > b.length_squared()
	)
	for i in COUNT:
		var enemy := ENEMY.instantiate() as Enemy
		enemy.position = spots[i]
		enemy.show_debug = SHOW_DEBUG
		enemies.add_child(enemy)
