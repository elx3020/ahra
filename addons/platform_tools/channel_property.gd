@tool
extends EditorProperty
## Inspector editor for `channel` on tracks, circuits and PlatformSwitches, and a sequence's
## `end_signal`: the channel picker (this scope's channels, other areas', none, or a new
## collision-checked name) in place of a plain text field. A channel of the node's own scope is
## stored as its plain name, another area's as its full key. Undoable (through the inspector).

const ChannelPicker := preload("channel_picker.gd")

var _picker: VBoxContainer


func _init() -> void:
	_picker = ChannelPicker.new()
	_picker.chosen.connect(func(key: StringName) -> void:
		var stored := Channels.relative(_context(), key)
		if stored != get_edited_object().get(get_edited_property()):
			emit_changed(get_edited_property(), stored))
	add_child(_picker)
	set_bottom_editor(_picker)
	add_focusable(_picker)


func _update_property() -> void:
	var o := get_edited_object()
	_picker.allow_none = not o is PlatformSwitch # a switch needs a channel to control
	_picker.setup(o.get(get_edited_property()), String(o.name) if o is Node else "signal", _context())


## The node whose scope the name is in: the edited node, or for a sequence the track being
## inspected (else the scene root).
func _context() -> Node:
	var o := get_edited_object()
	if o is Node:
		return o
	var shown := EditorInterface.get_inspector().get_edited_object()
	return shown if shown is Node else EditorInterface.get_edited_scene_root()
