class_name EnemyState
extends RefCounted
## Base enemy state. physics() returns the next state's name, or &"" to stay.
## Types replace a state by swapping its entry in Enemy.states (see Enemy).

var e: Enemy


func enter(_prev: StringName) -> void:
	pass


func exit() -> void:
	pass


func physics(_delta: float) -> StringName:
	return &""
