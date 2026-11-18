extends GameArea
## Ten platform puzzles in series, alternating timing and switch puzzles. Each start pad is a
## checkpoint; keys 1-9 and 0 teleport to puzzles 1-10.

const PUZZLE_HELP := "WASD move | Shift run | Space jump | Q dash (Q then Space = dash-jump) | E switch | F grab (hold, swing)\n1-9, 0: teleport to puzzle 1-10 | [ ] previous / next | Backspace: restart this puzzle\n\n"


func help() -> String:
	return PUZZLE_HELP


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		warp((e.keycode - KEY_0 + 9) % 10) # 1 -> puzzle 1 ... 0 -> puzzle 10
		return
	super(e)
