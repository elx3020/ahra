@tool
extends Node3D
## Harness for editor-side tests (plugins, inspector, gizmos, undo), which can't run under -s:
## the test scene is opened in the headless editor with a user flag, e.g.
## Godot_console.exe --headless --path . -e res://tests/shape_editor_test.tscn -- --shape-editor-test
## A test extends this, sets `flag` and `label` in _init and overrides run(), which must set
## `finished` at its end. It prints "<label>: OK" or "N FAILED" and quits with the failure count.
## Opening the scene normally does nothing.

var flag := ""
var label := ""
var failed := 0
var finished := false ## run() got to the end (a script error stops it silently)


func _ready() -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has(flag):
		return
	await get_tree().create_timer(2.0).timeout
	await run()
	check(finished, "ran to the end")
	print(label, ": ", "OK" if failed == 0 else "%d FAILED" % failed)
	# the editor saved this scene into its reopen list when it opened it: take it back out, so
	# your next editor session doesn't reopen it; then close it, dropping the test's edits
	var layout := EditorInterface.get_editor_paths().get_project_settings_dir().path_join("editor_layout.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(layout) == OK:
		var open: PackedStringArray = cfg.get_value("EditorNode", "open_scenes", PackedStringArray())
		open.erase(scene_file_path)
		cfg.set_value("EditorNode", "open_scenes", open)
		if cfg.get_value("EditorNode", "current_scene", "") == scene_file_path:
			cfg.set_value("EditorNode", "current_scene", open[-1] if open else "")
		cfg.save(layout)
	get_tree().quit(failed)
	EditorInterface.close_scene()


func run() -> void:
	pass


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failed += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## For what nodes update in _physics_process (a process frame can be shorter than a physics tick).
func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
