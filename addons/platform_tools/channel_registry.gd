@tool
extends RefCounted
## Project-wide registry of platform channel names. World keeps one state per channel for the
## whole game, so the same name in two scenes links their platforms and switches: a new name
## must not collide by accident (sharing one is done by picking it from the list).
## Built from every saved .tscn (its `channel = &"..."` lines) plus the open scene's nodes (they
## may be unsaved), so it always matches what the scenes use and never needs cleaning up.
## ponytail: rereads the scene files on each call; cache by modified time if projects grow big.


## channel name -> the scene paths using it, sorted by name.
static func channels() -> Dictionary:
	var found := {}
	var open := EditorInterface.get_edited_scene_root()
	var open_path := open.scene_file_path if open else ""
	var files := []
	_scene_files(EditorInterface.get_resource_filesystem().get_filesystem(), files)
	var line := RegEx.create_from_string("(?m)^(?:channel|end_signal) = &\"([^\"]+)\"$")
	for path: String in files:
		if path != open_path: # the open scene is read from its nodes below
			for m in line.search_all(FileAccess.get_file_as_string(path)):
				_add(found, m.get_string(1), path)
	if open:
		for n in [open] + open.find_children("*", "", true, false):
			if (n is PlatformSwitch or n is PlatformProgram and n.plays()) and n.channel != &"":
				_add(found, String(n.channel), open_path if open_path else "(unsaved scene)")
			if n is PlatformTrackInstance:
				for q in n.sequences:
					if q and q.end_signal != &"":
						_add(found, String(q.end_signal), open_path if open_path else "(unsaved scene)")
	var names := found.keys()
	names.sort()
	var out := {}
	for k in names:
		out[k] = found[k]
	return out


## Why `channel_name` can't be registered as a new channel ("" if it can).
static func problem(channel_name: String, taken: Dictionary) -> String:
	if channel_name.is_empty():
		return "Type a name for the new channel"
	if not channel_name.is_valid_ascii_identifier():
		return "Use letters, digits and _ (not starting with a digit)"
	if taken.has(channel_name):
		return "Already used in %s: pick it from the list to share it on purpose" % ", ".join(taken[channel_name].map(func(p: String) -> String: return p.get_file()))
	return ""


## A free, valid channel name based on `base` ("My Lift" -> my_lift, then my_lift_2...).
static func unique(base: String, taken: Dictionary) -> String:
	var root := RegEx.create_from_string("[^a-z0-9_]+").sub(base.to_snake_case(), "_", true).strip_edges()
	if root.is_empty() or not root.is_valid_ascii_identifier():
		root = "ch_" + root
	var out := root
	var n := 2
	while taken.has(out):
		out = "%s_%d" % [root, n]
		n += 1
	return out


static func _add(found: Dictionary, channel_name: String, path: String) -> void:
	if not found.has(channel_name):
		found[channel_name] = []
	if not found[channel_name].has(path):
		found[channel_name].append(path)


static func _scene_files(dir: EditorFileSystemDirectory, out: Array) -> void:
	for i in dir.get_file_count():
		if dir.get_file_path(i).ends_with(".tscn"):
			out.append(dir.get_file_path(i))
	for i in dir.get_subdir_count():
		_scene_files(dir.get_subdir(i), out)
