extends Control
## Title screen: continue the numbered puzzles or play today's daily puzzle.

signal continue_chosen
signal daily_chosen
signal challenge_chosen
signal settings_chosen

var continue_button: Button
var daily_button: Button
var challenge_button: Button
var settings_button: Button
var _continue_detail: Label
var _daily_detail: Label
var _challenge_detail: Label


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := _label("Crowns", 48)
	box.add_child(title)
	var tagline := _label("One crown per row, column and region.", 15)
	tagline.modulate = Color(1, 1, 1, 0.65)
	box.add_child(tagline)
	box.add_child(_gap(24))

	continue_button = _button("Continue", continue_chosen.emit)
	box.add_child(continue_button)
	_continue_detail = _label("", 14)
	_continue_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_continue_detail)
	box.add_child(_gap(8))

	daily_button = _button("Daily puzzle", daily_chosen.emit)
	box.add_child(daily_button)
	_daily_detail = _label("", 14)
	_daily_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_daily_detail)
	box.add_child(_gap(8))

	challenge_button = _button("The Climb", challenge_chosen.emit)
	box.add_child(challenge_button)
	_challenge_detail = _label("", 14)
	_challenge_detail.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_challenge_detail)
	box.add_child(_gap(8))

	settings_button = _button("Settings", settings_chosen.emit)
	box.add_child(settings_button)


func set_details(continue_title: String, continue_detail: String, daily_detail: String, challenge_detail: String) -> void:
	continue_button.text = continue_title
	_continue_detail.text = continue_detail
	_daily_detail.text = daily_detail
	_challenge_detail.text = challenge_detail


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(on_pressed)
	return button


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap
