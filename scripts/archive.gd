extends Control
## Daily puzzle archive: a month calendar of past dailies to play or replay.
## Solved days wear a crown, and a month with every daily solved earns a trophy.

signal day_chosen(date: String)
signal back

const CrownArt := preload("res://scripts/crown_art.gd")
const CrownIcon := preload("res://scripts/crown_icon.gd")

## Solved days are filled green so they stand out from the purple buttons.
const SOLVED_FILLS := {"normal": Color("3d8a57"), "hover": Color("4a9c65"), "pressed": Color("327349")}
const TODAY_COLOR := Color("f4c542")

## Returns {"solved": bool, "best": float (INF if untimed), "started": bool} for a date.
var status_for: Callable
## First and last playable dates, as "YYYY-MM-DD".
var first_date := ""
var last_date := ""

var prev_button: Button
var next_button: Button
var _month_label: Label
## The month's trophy, beside its name once every daily in it is solved.
var _trophy: CrownIcon
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

	var title := _label(tr("Archive"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var nav := HBoxContainer.new()
	box.add_child(nav)
	prev_button = _button("‹", func() -> void: _step_month(-1))
	nav.add_child(prev_button)
	var heading := HBoxContainer.new()
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 8)
	nav.add_child(heading)
	_trophy = CrownIcon.new()
	_trophy.custom_minimum_size = Vector2(30, 30)
	_trophy.size_flags_vertical = SIZE_SHRINK_CENTER
	_trophy.visible = false
	heading.add_child(_trophy)
	_month_label = _label("", 24)
	heading.add_child(_month_label)
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
	back_button.text = tr("Back")
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
	# TRANSLATORS: The archive's heading, e.g. "October 2026".
	_month_label.text = tr("{month} {year}").format({"month": _month_names()[_month - 1], "year": _year})
	var first := "%04d-%02d-01" % [_year, _month]
	prev_button.disabled = first <= first_date
	next_button.disabled = "%04d-%02d-31" % [_year, _month] >= last_date

	for day in _weekdays():
		var heading := _label(day, 15)
		heading.modulate = Color(1, 1, 1, 0.6)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(heading)
	var weekday: int = Time.get_date_dict_from_unix_time(Time.get_unix_time_from_datetime_string(first)).weekday
	for i in weekday:
		_grid.add_child(Control.new())

	var playable := 0
	var solved := 0
	for day in range(1, days_in_month(_year, _month) + 1):
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
				for state: String in SOLVED_FILLS:
					var box := StyleBoxFlat.new()
					box.bg_color = SOLVED_FILLS[state]
					box.set_corner_radius_all(10)
					button.add_theme_stylebox_override(state, box)
				var crown := _DayCrown.new()
				crown.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
				crown.offset_left = -21
				crown.offset_right = -3
				crown.offset_top = 2
				crown.offset_bottom = 20
				crown.mouse_filter = MOUSE_FILTER_IGNORE
				button.add_child(crown)
			elif status.started:
				button.text += "\n•"
			if date == last_date:
				_set_font_color(button, TODAY_COLOR)
			button.pressed.connect(day_chosen.emit.bind(date))
		_grid.add_child(button)
	var complete := month_complete(_year, _month, first_date, last_date, status_for)
	_trophy.visible = complete
	if complete:
		_summary.text = tr("Every daily solved!")
	elif playable > 0 and solved == playable:
		# The month isn't over yet.
		_summary.text = tr("All solved so far")
	else:
		_summary.text = tr("Solved {solved} of {total} this month").format({"solved": solved, "total": playable}) \
				if playable > 0 else ""


## Whether every daily of a finished month is solved, counting from `first_date`
## for the month the dailies began. The month of `last_date` (today) isn't over.
static func month_complete(year: int, month: int, first_date: String, last_date: String, status_for: Callable) -> bool:
	# "-31" sorts after a month's last day whatever its length, so a month is
	# over once last_date passes it.
	var month_end := "%04d-%02d-31" % [year, month]
	if month_end < first_date or last_date <= month_end:
		return false
	for day in range(1, days_in_month(year, month) + 1):
		var date := "%04d-%02d-%02d" % [year, month, day]
		if date >= first_date and not status_for.call(date).solved:
			return false
	return true


func _month_names() -> Array[String]:
	return [tr("January"), tr("February"), tr("March"), tr("April"), tr("May"), tr("June"),
			tr("July"), tr("August"), tr("September"), tr("October"), tr("November"), tr("December")]


## Column headings, starting on Sunday.
func _weekdays() -> Array[String]:
	# TRANSLATORS: Two-letter weekday abbreviations for the archive calendar's columns.
	return [tr("Su"), tr("Mo"), tr("Tu"), tr("We"), tr("Th"), tr("Fr"), tr("Sa")]


static func days_in_month(year: int, month: int) -> int:
	var next_year := year + 1 if month == 12 else year
	var next_month := 1 if month == 12 else month + 1
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


## A small still crown in the corner of a solved day.
class _DayCrown extends Control:
	func _draw() -> void:
		var side := minf(size.x, size.y)
		CrownArt.draw(self, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
