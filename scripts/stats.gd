extends Control
## Stats screen: daily streaks, solves and times per size, and The Climb.

signal back

var _box: VBoxContainer
var _content: VBoxContainer


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 380
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)

	var title := _label(tr("Stats"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_box.add_child(_content)

	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	_box.add_child(back_button)


## `daily` and `climb` are [label, value] pairs; `sizes` rows are
## [size label, solved, average, best].
func set_stats(daily: Array, sizes: Array, climb: Array) -> void:
	for child in _content.get_children():
		child.queue_free()
	_section(tr("Daily"), _pairs(daily))
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 24)
	table.add_theme_constant_override("v_separation", 4)
	for heading in [tr("Size"), tr("Solved"), tr("Average"), tr("Best")]:
		var cell := _table_cell(heading, 15, table.get_child_count())
		cell.modulate = Color(1, 1, 1, 0.6)
		table.add_child(cell)
	for row: Array in sizes:
		for value in row:
			table.add_child(_table_cell(str(value), 17, table.get_child_count()))
	_section(tr("Puzzles"), table)
	_section(tr("The Climb"), _pairs(climb))


func _section(heading: String, body: Control) -> void:
	var label := _label(heading, 22)
	_content.add_child(label)
	_content.add_child(body)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_content.add_child(gap)


func _pairs(pairs: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	for pair: Array in pairs:
		var name := _label(pair[0], 17)
		name.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_child(name)
		var value := _label(str(pair[1]), 17)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	return grid


## Fills the width like the label/value lists, with numbers right-aligned.
func _table_cell(text: String, font_size: int, index: int) -> Label:
	var label := _label(text, font_size)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	if index % 4 > 0:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
