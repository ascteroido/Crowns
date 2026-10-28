extends Control
## Stats screen: daily streaks and weekly solves, solves and times per size,
## recent solve times as a graph, The Climb and speed runs.

const HistoryGraph := preload("res://scripts/history_graph.gd")

signal back
signal achievements_chosen

var _box: VBoxContainer
var _content: VBoxContainer
## Shown only where Google Play Games is available.
var achievements_button: Button
## The solve history section's size picker and graph.
var history_picker: OptionButton
var history_graph: HistoryGraph
var _history_summary: Label
## Size -> [unix time, seconds, difficulty] per solve, oldest first.
var _histories := {}
var _format: Callable
var _difficulty_names: Array = []


func _ready() -> void:
	# Scrolls when it's taller than the screen, as on phones.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
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

	achievements_button = Button.new()
	achievements_button.text = tr("Achievements")
	achievements_button.custom_minimum_size = Vector2(0, 52)
	achievements_button.add_theme_font_size_override("font_size", 20)
	achievements_button.pressed.connect(achievements_chosen.emit)
	achievements_button.visible = false
	_box.add_child(achievements_button)

	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	_box.add_child(back_button)


## `daily`, `climb` and `speed` are [label, value] pairs; `sizes` rows are
## [size label, solved, average, best].
func set_stats(daily: Array, sizes: Array, climb: Array, speed: Array) -> void:
	for child in _content.get_children():
		child.queue_free()
	_section(tr("Daily and weekly"), _pairs(daily))
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
	_section(tr("Solve history"), _history_section())
	_section(tr("The Climb"), _pairs(climb))
	_section(tr("Speed run"), _pairs(speed))


## The recent solves to graph, by size, and how to show times and difficulties.
## Call before set_stats, which builds the section from them.
func set_history(histories: Dictionary, format: Callable, difficulty_names: Array) -> void:
	_histories = histories
	_format = format
	_difficulty_names = difficulty_names


## A size picker over a graph of that size's recent solves, or a note until there are any.
func _history_section() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var sizes := _histories.keys().filter(func(size: int) -> bool: return not _histories[size].is_empty())
	sizes.sort()
	if sizes.is_empty():
		history_picker = null
		history_graph = null
		var note := _label(tr("Solve a puzzle without hints to start a graph of your times."), 16)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate = Color(1, 1, 1, 0.6)
		column.add_child(note)
		return column
	history_picker = OptionButton.new()
	for size: int in sizes:
		history_picker.add_item("%d×%d" % [size, size], size)
	history_picker.item_selected.connect(func(_index: int) -> void: _show_history())
	column.add_child(history_picker)
	history_graph = HistoryGraph.new()
	history_graph.format = _format
	column.add_child(history_graph)
	_history_summary = _label("", 15)
	_history_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_summary.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_history_summary)
	column.add_child(_legend())
	# Opens on the size solved most recently.
	var latest := sizes.duplicate()
	latest.sort_custom(func(a: int, b: int) -> bool: return _histories[a][-1][0] > _histories[b][-1][0])
	history_picker.select(sizes.find(latest[0]))
	_show_history()
	return column


func _show_history() -> void:
	var entries: Array = _histories[history_picker.get_selected_id()]
	history_graph.entries = entries
	var times := entries.map(func(entry: Array) -> float: return entry[1])
	var average: float = times.reduce(func(sum: float, seconds: float) -> float: return sum + seconds, 0.0) / times.size()
	# TRANSLATORS: Under the solve history graph, e.g. "Last 12 solves · average 2:31 · fastest 1:48".
	# The graph draws the average as a dashed line and rings the fastest solve.
	_history_summary.text = tr_n("Last %d solve", "Last %d solves", entries.size()) % entries.size() \
			+ " · " + tr("average %s · fastest %s") % [_format.call(average), _format.call(times.min())]


## The difficulty colours of the graph's dots.
func _legend() -> HFlowContainer:
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 14)
	for difficulty in _difficulty_names.size():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var dot := ColorRect.new()
		dot.color = HistoryGraph.DIFFICULTY_COLORS[difficulty]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = SIZE_SHRINK_CENTER
		item.add_child(dot)
		item.add_child(_label(_difficulty_names[difficulty], 14))
		legend.add_child(item)
	return legend


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
