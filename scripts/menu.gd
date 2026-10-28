extends Control
## Title screen: continue the numbered puzzles, play today's daily puzzle or a past one,
## this week's weekly challenge, The Climb or a speed run, or make a puzzle.

const CrownIcon := preload("res://scripts/crown_icon.gd")

signal continue_chosen
signal daily_chosen
signal archive_chosen
signal weekly_chosen
signal challenge_chosen
signal speed_chosen
signal stats_chosen
signal create_chosen
signal leaderboards_chosen
signal settings_chosen
signal exit_chosen

var continue_button: Button
var daily_button: Button
var archive_button: Button
var weekly_button: Button
var challenge_button: Button
var speed_button: Button
var stats_button: Button
var create_button: Button
var leaderboards_button: Button
var settings_button: Button
var exit_button: Button
var _continue_detail: Label
var _daily_detail: Label
var _weekly_detail: Label
var _challenge_detail: Label
var _speed_detail: Label
## The menu's sections: title, puzzles, then the rest. Down one column on tall
## screens (_box), or side by side on wide ones (_row).
var _sections := []
var _box: VBoxContainer
## Space under the title, which only the single column needs.
var _title_gap: Control
var _row: HBoxContainer
var _wide := false
## [control, property, size at the desktop window's height], scaled up on bigger screens.
var _scaled := []


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_scale(_box, "separation", 10)
	center.add_child(_box)
	_row = HBoxContainer.new()
	_scale(_row, "separation", 48)
	_row.visible = false
	center.add_child(_row)
	for i in 3:
		var section := VBoxContainer.new()
		section.size_flags_vertical = SIZE_SHRINK_CENTER
		_scale(section, "width", 320)
		_scale(section, "separation", 10)
		_sections.append(section)
		_box.add_child(section)
	var box: VBoxContainer = _sections[0]

	var crown := CrownIcon.new()
	_scale(crown, "height", 64)
	box.add_child(crown)
	var title := _label("Crowns", 48)
	box.add_child(title)
	var tagline := _label(tr("One crown per row, column and region."), 15)
	tagline.modulate = Color(1, 1, 1, 0.65)
	box.add_child(tagline)
	_title_gap = _gap(24)
	box.add_child(_title_gap)

	box = _sections[1]
	continue_button = _button(tr("Continue"), continue_chosen.emit)
	box.add_child(continue_button)
	_continue_detail = _label("", 14)
	_continue_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_continue_detail)
	box.add_child(_gap(8))

	var daily_row := HBoxContainer.new()
	_scale(daily_row, "separation", 10)
	box.add_child(daily_row)
	daily_button = _button(tr("Daily puzzle"), daily_chosen.emit)
	daily_button.size_flags_horizontal = SIZE_EXPAND_FILL
	daily_row.add_child(daily_button)
	archive_button = _button(tr("Archive"), archive_chosen.emit)
	_scale(archive_button, "width", 110)
	daily_row.add_child(archive_button)
	_daily_detail = _label("", 14)
	_daily_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_daily_detail)
	box.add_child(_gap(8))

	weekly_button = _button(tr("Weekly challenge"), weekly_chosen.emit)
	box.add_child(weekly_button)
	_weekly_detail = _label("", 14)
	_weekly_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_weekly_detail)
	box.add_child(_gap(8))

	box = _sections[2]

	# The Climb and speed runs share a row, each with its detail beneath.
	var runs_row := HBoxContainer.new()
	_scale(runs_row, "separation", 10)
	box.add_child(runs_row)
	var details_row := HBoxContainer.new()
	_scale(details_row, "separation", 10)
	box.add_child(details_row)
	challenge_button = _button(tr("The Climb"), challenge_chosen.emit)
	speed_button = _button(tr("Speed run"), speed_chosen.emit)
	_challenge_detail = _label("", 14)
	_speed_detail = _label("", 14)
	for button: Button in [challenge_button, speed_button]:
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		runs_row.add_child(button)
	for detail: Label in [_challenge_detail, _speed_detail]:
		detail.modulate = Color(1, 1, 1, 0.6)
		detail.size_flags_horizontal = SIZE_EXPAND_FILL
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details_row.add_child(detail)
	box.add_child(_gap(8))

	# Shown only where Google Play Games is available.
	leaderboards_button = _button(tr("Leaderboards"), leaderboards_chosen.emit)
	leaderboards_button.visible = false
	box.add_child(leaderboards_button)

	# Side by side, so the menu still fits the desktop window.
	var options_row := HBoxContainer.new()
	_scale(options_row, "separation", 10)
	box.add_child(options_row)
	stats_button = _button(tr("Stats"), stats_chosen.emit)
	stats_button.size_flags_horizontal = SIZE_EXPAND_FILL
	options_row.add_child(stats_button)
	# TRANSLATORS: Opens the puzzle editor.
	create_button = _button(tr("Create"), create_chosen.emit)
	create_button.size_flags_horizontal = SIZE_EXPAND_FILL
	options_row.add_child(create_button)
	settings_button = _button(tr("Settings"), settings_chosen.emit)
	settings_button.size_flags_horizontal = SIZE_EXPAND_FILL
	options_row.add_child(settings_button)

	# Phones and browsers leave closing apps to the system.
	exit_button = _button(tr("Exit"), exit_chosen.emit)
	exit_button.visible = OS.has_feature("pc")
	box.add_child(exit_button)
	# Buttons that come and go change the menu's height, so it's refitted.
	leaderboards_button.visibility_changed.connect(_fit)
	exit_button.visibility_changed.connect(_fit)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


## Lays the menu out in one column on tall screens, or its sections side by
## side on wide ones, then grows it to fill big phone screens; the 860 px desktop
## window keeps the base sizes. Never past what fits, so every button stays on screen.
func _fit() -> void:
	if not _box:
		return
	var wide := size.x >= size.y * 1.25
	if wide != _wide:
		_wide = wide
		var into: BoxContainer = _row if wide else _box
		for section in _sections:
			section.reparent(into, false)
		_row.visible = wide
		_box.visible = not wide
		_title_gap.visible = not wide
	var factor := clampf(maxf(size.x, size.y) / 860.0, 1.0, 1.6)
	if size.y > 0.0:
		_apply(1.0)
		var base := (_row if _wide else _box).get_combined_minimum_size()
		if base.y > 0.0:
			factor = minf(factor, (size.y - 48.0) / base.y)
		if base.x > 0.0:
			factor = minf(factor, (size.x - 48.0) / base.x)
	_apply(factor)


func _apply(factor: float) -> void:
	for entry: Array in _scaled:
		var control: Control = entry[0]
		var value := roundi(entry[2] * factor)
		match entry[1]:
			"width":
				# Leave a margin at the screen edges, once the menu has a size.
				if control in _sections and not _wide and size.x > 0.0:
					value = mini(value, int(size.x) - 48)
				control.custom_minimum_size.x = value
			"height":
				control.custom_minimum_size.y = value
			"separation":
				control.add_theme_constant_override("separation", value)
			"font":
				control.add_theme_font_size_override("font_size", value)


func _scale(control: Control, property: String, base: int) -> void:
	_scaled.append([control, property, base])


func set_details(continue_title: String, continue_detail: String, daily_detail: String, weekly_detail: String,
		challenge_detail: String, speed_detail: String) -> void:
	continue_button.text = continue_title
	_continue_detail.text = continue_detail
	_daily_detail.text = daily_detail
	_weekly_detail.text = weekly_detail
	_challenge_detail.text = challenge_detail
	_speed_detail.text = speed_detail


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scale(label, "font", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_scale(button, "height", 62)
	_scale(button, "font", 23)
	button.pressed.connect(on_pressed)
	return button


func _gap(height: float) -> Control:
	var gap := Control.new()
	_scale(gap, "height", roundi(height))
	return gap
