extends Control
## Title screen: continue the numbered puzzles, play today's daily puzzle or a past one,
## this week's weekly challenge or The Climb.

const CrownIcon := preload("res://scripts/crown_icon.gd")

signal continue_chosen
signal daily_chosen
signal archive_chosen
signal weekly_chosen
signal challenge_chosen
signal stats_chosen
signal leaderboards_chosen
signal settings_chosen
signal exit_chosen

var continue_button: Button
var daily_button: Button
var archive_button: Button
var weekly_button: Button
var challenge_button: Button
var stats_button: Button
var leaderboards_button: Button
var settings_button: Button
var exit_button: Button
var _continue_detail: Label
var _daily_detail: Label
var _weekly_detail: Label
var _challenge_detail: Label
var _box: VBoxContainer
## [control, property, size at the desktop window's height], scaled up on taller screens.
var _scaled := []


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	_box = box
	_scale(box, "width", 320)
	_scale(box, "separation", 10)
	center.add_child(box)

	var crown := CrownIcon.new()
	_scale(crown, "height", 64)
	box.add_child(crown)
	var title := _label("Crowns", 48)
	box.add_child(title)
	var tagline := _label(tr("One crown per row, column and region."), 15)
	tagline.modulate = Color(1, 1, 1, 0.65)
	box.add_child(tagline)
	box.add_child(_gap(24))

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

	challenge_button = _button(tr("The Climb"), challenge_chosen.emit)
	box.add_child(challenge_button)
	_challenge_detail = _label("", 14)
	_challenge_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_challenge_detail)
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


## Grows the menu to fill tall phone screens; the 860 px desktop window keeps the
## base sizes. Never past what fits, so every button stays on screen.
func _fit() -> void:
	var factor := clampf(size.y / 860.0, 1.0, 1.6)
	if size.y > 0.0 and _box:
		_apply(1.0)
		var base := _box.get_combined_minimum_size().y
		if base > 0.0:
			factor = minf(factor, (size.y - 48.0) / base)
	_apply(factor)


func _apply(factor: float) -> void:
	for entry: Array in _scaled:
		var control: Control = entry[0]
		var value := roundi(entry[2] * factor)
		match entry[1]:
			"width":
				# Leave a margin at the screen edges, once the menu has a size.
				if control == _box and size.x > 0.0:
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
		challenge_detail: String) -> void:
	continue_button.text = continue_title
	_continue_detail.text = continue_detail
	_daily_detail.text = daily_detail
	_weekly_detail.text = weekly_detail
	_challenge_detail.text = challenge_detail


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
