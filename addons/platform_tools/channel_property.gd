@tool
extends EditorProperty
## Inspector editor for `channel` on MovingPlatforms and PlatformSwitches: the channel picker
## (registry channels, none, or a new collision-checked name) in place of a plain text field.
## Changes go through the inspector, so they are undoable.

const ChannelPicker := preload("channel_picker.gd")

var _picker: VBoxContainer


func _init() -> void:
	_picker = ChannelPicker.new()
	_picker.chosen.connect(func(ch: StringName) -> void:
		if ch != get_edited_object().get(get_edited_property()):
			emit_changed(get_edited_property(), ch))
	add_child(_picker)
	set_bottom_editor(_picker)
	add_focusable(_picker)


func _update_property() -> void:
	var o := get_edited_object()
	_picker.allow_none = o is MovingPlatform # a switch needs a channel to control
	_picker.setup(o.get(get_edited_property()), String(o.name))
