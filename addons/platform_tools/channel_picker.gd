@tool
extends VBoxContainer
## Channel chooser used by the Switch popup and the inspector: a channel of this scope (only
## those are listed, by plain name, plus the current value if it links another area), none
## (world clock), or typed in: a new name for this scope, or `area:name` to link another area's
## channel, checked against the registry as it's typed.
## value() and `chosen` give full keys ("area:name", see Channels); store them with
## Channels.relative() so names in their own scope stay plain.

signal edited ## any change, for live validation
signal chosen(channel: StringName) ## a valid choice (a full key): an existing channel, none, or a confirmed new name

const Registry := preload("channel_registry.gd")

var allow_none := true ## offer "(none)": a track without a channel runs on the world clock
var _taken := {}
var _prefix := "" ## the scope being edited: what a plain name gets in front of it
var _options: OptionButton
var _row: HBoxContainer
var _name: LineEdit
var _use: Button
var _note: Label


func _init() -> void:
	_options = OptionButton.new()
	_options.fit_to_longest_item = false
	add_child(_options)
	_row = HBoxContainer.new()
	add_child(_row)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.placeholder_text = "new name, or area:name to link another area's"
	_row.add_child(_name)
	_use = Button.new()
	_use.text = "Use"
	_row.add_child(_use)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	_options.item_selected.connect(func(_i: int) -> void:
		_sync()
		if not is_new():
			chosen.emit(value()))
	_name.text_changed.connect(func(_t: String) -> void: _sync())
	_name.text_submitted.connect(func(_t: String) -> void: _confirm())
	_use.pressed.connect(_confirm)


## Lists the registry's channels for the scope of `context` and selects `current` (as stored
## there); else "New channel" named after `suggestion`.
func setup(current: StringName, suggestion: String, context: Node) -> void:
	_prefix = Channels.prefix(context) if context else ""
	_taken = Registry.channels()
	var key := Channels.key(context, current) if context else current
	_options.clear()
	if allow_none:
		_options.add_item("(none: world clock)")
		_options.set_item_metadata(_options.item_count - 1, "")
	var listed := _taken.keys().filter(func(k: String) -> bool: return k.begins_with(_prefix) and not k.trim_prefix(_prefix).contains("/"))
	if key != &"" and not listed.has(String(key)):
		listed.append(String(key)) # its current link to another area
	for k: String in listed:
		var shown := k.trim_prefix(_prefix) if k.begins_with(_prefix) else k
		var users: Array = _taken.get(k, [])
		_options.add_item("%s  (%s)" % [shown, ", ".join(users.map(func(p: String) -> String: return p.get_file()))] if users else shown)
		_options.set_item_metadata(_options.item_count - 1, k)
	_options.add_item("New channel...") # no metadata: the typed name
	var pick := _options.item_count - 1
	for i in _options.item_count:
		var m: Variant = _options.get_item_metadata(i)
		if m is String and m == String(key):
			pick = i
	_options.select(pick)
	_name.text = Registry.unique(suggestion, _taken, _prefix)
	_sync()


func is_new() -> bool:
	return _options.get_selected_metadata() == null


## The channel chosen, as a full key (the typed name when "New channel" is selected; check valid()).
func value() -> StringName:
	if not is_new():
		return StringName(_options.get_selected_metadata())
	var typed := _name.text.strip_edges()
	return StringName(typed if typed.contains(":") else _prefix + typed)


func valid() -> bool:
	return not is_new() or Registry.problem(_name.text.strip_edges(), _taken, _prefix).is_empty()


func _sync() -> void:
	var problem := Registry.problem(_name.text.strip_edges(), _taken, _prefix) if is_new() else ""
	_row.visible = is_new()
	_note.visible = is_new()
	_note.text = problem if problem else Registry.describe(value(), _taken)
	_note.modulate = Color(1, 0.55, 0.45) if problem else Color(0.55, 1, 0.6)
	_use.disabled = not problem.is_empty()
	edited.emit()


func _confirm() -> void:
	if is_new() and valid():
		chosen.emit(value())
