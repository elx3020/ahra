class_name PlayerState
extends RefCounted
## Base player state. physics() returns the next state's name, or &"" to stay.

var p: Player


func enter(_prev: StringName) -> void:
	pass


func exit() -> void:
	pass


func physics(_delta: float) -> StringName:
	return &""
