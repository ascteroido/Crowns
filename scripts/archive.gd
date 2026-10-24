extends Control
## Daily puzzle archive: a month calendar of past dailies to play or replay.

signal day_chosen(date: String)
signal back

const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July", "August",
		"September", "October", "November", "December"]
const WEEKDAYS := ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
const SOLVED_COLOR := Color("8fd694")
const TODAY_COLOR := Color("f4c542")

## Returns {"solved": bool, "best": float (INF if untimed), "started": bool} for a date.
var status_for: Callable
## First and last playable dates, as "YYYY-MM-DD".
var first_date := ""
var last_date := ""

var prev_button: Button
var next_button: Button
var _month_label: Label
var _grid: GridContainer
var _summary: Label
var _year := 0
var _month := 0


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 460
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := _label("Archive", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var nav := HBoxContainer.new()
	box.add_child(nav)
	prev_button = _button("‹", func() -> void: _step_month(-1))
	nav.add_child(prev_button)
	_month_label = _label("", 24)
	_month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_month_label.size_flags_horizontal = SIZE_EXPAND_FILL
	nav.add_child(_month_label)
	next_button = _button("›", func() -> void: _step_month(1))
	nav.add_child(next_button)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)

	_summary = _label("", 16)
	_summary.modulate = Color(1, 1, 1, 0.65)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	box.add_child(back_button)


## Shows the month holding `date` ("YYYY-MM-DD").
func show_month_of(date: String) -> void:
	var parts := date.split("-")
	_year = parts[0].to_int()
	_month = parts[1].to_int()
	_refresh()


func _step_month(step: int) -> void:
	_month += step
	if _month < 1:
		_month = 12
		_year -= 1
	elif _month > 12:
		_month = 1
		_year += 1
	_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_month_label.text = "%s %d" % [MONTH_NAMES[_month - 1], _year]
	var first := "%04d-%02d-01" % [_year, _month]
	prev_button.disabled = first <= first_date
	next_button.disabled = "%04d-%02d-31" % [_year, _month] >= last_date

	for day in WEEKDAYS:
		var heading := _label(day, 15)
		heading.modulate = Color(1, 1, 1, 0.6)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(heading)
	var weekday: int = Time.get_date_dict_from_unix_time(Time.get_unix_time_from_datetime_string(first)).weekday
	for i in weekday:
		_grid.add_child(Control.new())

	var playable := 0
	var solved := 0
	for day in range(1, _days_in_month() + 1):
		var date := "%04d-%02d-%02d" % [_year, _month, day]
		var button := Button.new()
		button.custom_minimum_size = Vector2(60, 60)
		button.add_theme_font_size_override("font_size", 16)
		button.text = str(day)
		if date < first_date or date > last_date:
			button.disabled = true
		else:
			playable += 1
			var status: Dictionary = status_for.call(date)
			if status.solved:
				solved += 1
				button.text += "\n" + (_format_time(status.best) if status.best != INF else "✓")
				_set_font_color(button, SOLVED_COLOR)
			elif status.started:
				button.text += "\n•"
			if date == last_date:
				_set_font_color(button, TODAY_COLOR)
			button.pressed.connect(day_chosen.emit.bind(date))
		_grid.add_child(button)
	_summary.text = "Solved %d of %d this month" % [solved, playable] if playable > 0 else ""


func _days_in_month() -> int:
	var next_year := _year + 1 if _month == 12 else _year
	var next_month := 1 if _month == 12 else _month + 1
	var next_first := Time.get_unix_time_from_datetime_string("%04d-%02d-01" % [next_year, next_month])
	return Time.get_date_dict_from_unix_time(next_first - 86400).day


func _set_font_color(button: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(60, 48)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(on_pressed)
	return button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
