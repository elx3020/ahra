extends GameArea
## Stress demo: 250 runners on a flat world-boundary (plane) floor. Each roams the patrol area of
## its quadrant (four shared EnemyAreas of different shapes) and chases only inside one shared chase
## area. Off-screen runners sleep; the HUD counts the awake ones.
## Grid cells are taken outermost-first, so the middle stays clear for the player.
## Set SHOW_DEBUG to true to restore the per-enemy state labels.

const ENEMY: PackedScene = preload("res://enemy/runner/runner.tscn")
const COUNT := 250
const COLS := 16
const ROWS := 16
const SPACING := 5.5
const SHOW_DEBUG := false

@onready var enemies: Node3D = $Enemies
@onready var chase: EnemyArea = $Areas/Chase
@onready var patrols: Array = [$Areas/PatrolNE, $Areas/PatrolNW, $Areas/PatrolSE, $Areas/PatrolSW]


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
		enemy.patrol_area = _patrol_for(spots[i])
		enemy.chase_area = chase
		enemies.add_child(enemy)


## The patrol area of the quadrant `p` is in: NE (+x, -z), NW (-x, -z), SE (+x, +z), SW (-x, +z).
func _patrol_for(p: Vector3) -> EnemyArea:
	return patrols[(0 if p.x >= 0.0 else 1) + (0 if p.z < 0.0 else 2)]


func help() -> String:
	var awake := enemies.get_children().filter(func(n: Node) -> bool: return not (n as Enemy).asleep).size()
	return HELP + "awake: %d / %d\n" % [awake, COUNT]
