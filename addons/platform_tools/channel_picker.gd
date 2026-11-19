@tool
extends VBoxContainer
## Channel chooser used by the Switch popup and the inspector: an existing channel from the
## registry (shared on purpose; each entry says which scenes use it), none (world clock), or a
## new name, checked against the registry as it is typed.

signal edited ## any change, for live validation
signal chosen(channel: StringName) ## a valid choice: an existing channel, none, or a confirmed new name

const Registry := preload("channel_registry.gd")

var allow_none := true ## offer "(none)": a platform without a channel runs on the world clock
var _taken := {}
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
	_name.placeholder_text = "new channel name"
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


## Lists the registry's channels and selects `current`; else "New channel" named after `suggestion`.
func setup(current: StringName, suggestion: String) -> void:
	_taken = Registry.channels()
	_options.clear()
	if allow_none:
		_options.add_item("(none: world clock)")
		_options.set_item_metadata(_options.item_count - 1, "")
	for ch: String in _taken:
		_options.add_item("%s  (%s)" % [ch, ", ".join(_taken[ch].map(func(p: String) -> String: return p.get_file()))])
		_options.set_item_metadata(_options.item_count - 1, ch)
	_options.add_item("New channel...") # no metadata: the typed name
	var pick := _options.item_count - 1
	for i in _options.item_count:
		var m: Variant = _options.get_item_metadata(i)
		if m is String and m == String(current):
			pick = i
	_options.select(pick)
	_name.text = Registry.unique(suggestion, _taken)
	_sync()


func is_new() -> bool:
	return _options.get_selected_metadata() == null


## The channel chosen (the typed name when "New channel" is selected; check valid()).
func value() -> StringName:
	return StringName(_name.text.strip_edges()) if is_new() else StringName(_options.get_selected_metadata())


func valid() -> bool:
	return not is_new() or Registry.problem(_name.text.strip_edges(), _taken).is_empty()


func _sync() -> void:
	var problem := Registry.problem(_name.text.strip_edges(), _taken) if is_new() else ""
	_row.visible = is_new()
	_note.visible = is_new()
	_note.text = problem if problem else "Free: this name is not used anywhere yet"
	_note.modulate = Color(1, 0.55, 0.45) if problem else Color(0.55, 1, 0.6)
	_use.disabled = not problem.is_empty()
	edited.emit()


func _confirm() -> void:
	if is_new() and valid():
		chosen.emit(value())
