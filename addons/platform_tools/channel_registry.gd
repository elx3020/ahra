@tool
extends RefCounted
## Project-wide registry of platform channel keys ("area:name", see Channels). Plain names are
## scoped to their area (and scoped groups), so two areas never collide; a key used in several
## scenes is a deliberate cross-area link (`platforms_a:remote`). The picker lists only the
## edited scope's channels; the rest of the registry checks names and describes links.
## Built from every saved .tscn (its nodes' `channel` and their sequences' `end_signal`, resolved
## in their scope) plus the open scene's nodes (they may be unsaved), so it always matches what
## the scenes use and never needs cleaning up.
## ponytail: rereads the scene files on each call, and doesn't look inside instanced sub-scenes
## (their own file is read as its own area); cache by modified time if projects grow big.


## channel key -> the scene paths using it, sorted by key.
static func channels() -> Dictionary:
	var found := {}
	var open := EditorInterface.get_edited_scene_root()
	var open_path := open.scene_file_path if open else ""
	var files := []
	_scene_files(EditorInterface.get_resource_filesystem().get_filesystem(), files)
	for path: String in files:
		if path != open_path: # the open scene is read from its nodes below
			for key: String in keys_in(FileAccess.get_file_as_string(path), path):
				_add(found, key, path)
	if open:
		var here := open_path if open_path else "(unsaved scene)"
		for n in [open] + open.find_children("*", "", true, false):
			if (n is PlatformSwitch or n is PlatformProgram and n.plays()) and n.channel != &"":
				_add(found, Channels.key(n, n.channel), here)
			if n is PlatformTrackInstance:
				for q in n.sequences:
					if q and q.end_signal != &"":
						_add(found, Channels.key(n, q.end_signal), here)
	var names := found.keys()
	names.sort()
	var out := {}
	for k in names:
		out[k] = found[k]
	return out


## The channel keys a saved scene's text uses: its nodes' `channel`s and their sequences'
## `end_signal`s, resolved as Channels.key would (area_id or file name, then scoped groups).
static func keys_in(text: String, path: String) -> Array:
	var head := RegEx.create_from_string('^\\[node name="([^"]+)"(?:[^\\]]*? parent="([^"]*)")?')
	var res_id := RegEx.create_from_string(' id="([^"]+)"')
	var value := RegEx.create_from_string('^(\\w+) = (?:&"([^"]*)"|(.*))$')
	var refs := RegEx.create_from_string('SubResource\\("([^"]+)"\\)')
	var signals := {} # sub-resource id -> its end_signal
	var nodes := [] # [path, parent path, {property: value}]
	var res := ""
	for line in text.split("\n"):
		if line.begins_with("["):
			res = ""
			var h := head.search(line)
			if line.begins_with("[sub_resource"):
				res = res_id.search(line).get_string(1)
			elif h:
				var root := h.get_start(2) < 0
				var parent := h.get_string(2)
				var at := "." if root else (h.get_string(1) if parent == "." else parent + "/" + h.get_string(1))
				nodes.append([at, parent, {name = h.get_string(1)}])
			else:
				res = "-" # ext resources, connections...: not a node
			continue
		var m := value.search(line)
		if m == null:
			continue
		if res != "":
			if m.get_string(1) == "end_signal":
				signals[res] = m.get_string(2)
		elif not nodes.is_empty():
			nodes[-1][2][m.get_string(1)] = m.get_string(2) if m.get_start(2) >= 0 else m.get_string(3)
	var prefix := {} # node path -> what a plain name gets in front of it there
	var out := []
	for n: Array in nodes:
		var props: Dictionary = n[2]
		var p: String = (props.get("area_id", path.get_file().get_basename()) + ":") if n[0] == "." else prefix.get(n[1], "")
		if props.get("channel_scope") == "true":
			p += props.name + "/"
		prefix[n[0]] = p
		var used := [props.get("channel", "")]
		for r in refs.search_all(props.get("sequences", "")):
			used.append(signals.get(r.get_string(1), ""))
		for name: String in used:
			if name != "":
				out.append(name if name.contains(":") else p + name)
	return out


## Why `channel_name` can't be typed in at scope `prefix` ("" if it can). A plain name is a new
## channel of this scope (refused if the scope has it already: pick it from the list instead);
## `area:name` links to a channel of another area (it may exist already: that's the point).
static func problem(channel_name: String, taken: Dictionary, prefix: String) -> String:
	if channel_name.is_empty():
		return "Type a name for the new channel, or area:name to link another area's"
	var parts := channel_name.split(":")
	if parts.size() > 2 or not Array(parts).all(func(s: String) -> bool: return s.is_valid_ascii_identifier()):
		return "Use letters, digits and _ (not starting with a digit); area:name links another area's"
	var key := channel_name if parts.size() == 2 else prefix + channel_name
	if key.begins_with(prefix) and taken.has(key):
		return "Already used here: pick it from the list"
	return ""


## What typing channel `key` does: link to a used one (saying where), or start a new one.
static func describe(key: String, taken: Dictionary) -> String:
	if taken.has(key):
		return "Links to %s, used in %s" % [key, ", ".join(taken[key].map(func(p: String) -> String: return p.get_file()))]
	return "Free: %s isn't used yet" % key


## A free, valid plain name at scope `prefix` based on `base` ("My Lift" -> my_lift, then my_lift_2...).
static func unique(base: String, taken: Dictionary, prefix: String) -> String:
	var root := RegEx.create_from_string("[^a-z0-9_]+").sub(base.to_snake_case(), "_", true).strip_edges()
	if root.is_empty() or not root.is_valid_ascii_identifier():
		root = "ch_" + root
	var out := root
	var n := 2
	while taken.has(prefix + out):
		out = "%s_%d" % [root, n]
		n += 1
	return out


static func _add(found: Dictionary, channel_key: String, path: String) -> void:
	if not found.has(channel_key):
		found[channel_key] = []
	if not found[channel_key].has(path):
		found[channel_key].append(path)


static func _scene_files(dir: EditorFileSystemDirectory, out: Array) -> void:
	for i in dir.get_file_count():
		if dir.get_file_path(i).ends_with(".tscn"):
			out.append(dir.get_file_path(i))
	for i in dir.get_subdir_count():
		_scene_files(dir.get_subdir(i), out)
