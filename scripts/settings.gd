extends Control
## Settings screen.

signal dark_mode_toggled(enabled: bool)
signal auto_cross_toggled(enabled: bool)
signal patterns_toggled(enabled: bool)
signal sound_toggled(enabled: bool)
signal reminder_toggled(enabled: bool)
signal reminder_hour_chosen(hour: int)
## An empty locale means the device's language.
signal language_chosen(locale: String)
signal back

var dark_mode_toggle: CheckButton
var auto_cross_toggle: CheckButton
var patterns_toggle: CheckButton
var sound_toggle: CheckButton
var reminder_toggle: CheckButton
var reminder_hour_picker: OptionButton
var _reminder_row: HBoxContainer
## Hour of each reminder_hour_picker item.
var _hours: Array[int] = []
var language_picker: OptionButton
## Locale of each language_picker item, "" for the device's language.
var _locales := PackedStringArray()


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = tr("Settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	dark_mode_toggle = CheckButton.new()
	dark_mode_toggle.text = tr("Dark mode")
	dark_mode_toggle.add_theme_font_size_override("font_size", 20)
	dark_mode_toggle.toggled.connect(dark_mode_toggled.emit)
	box.add_child(dark_mode_toggle)

	auto_cross_toggle = CheckButton.new()
	auto_cross_toggle.text = tr("Auto-place × around crowns")
	auto_cross_toggle.add_theme_font_size_override("font_size", 20)
	auto_cross_toggle.toggled.connect(auto_cross_toggled.emit)
	box.add_child(auto_cross_toggle)

	patterns_toggle = CheckButton.new()
	patterns_toggle.text = tr("Region patterns")
	patterns_toggle.add_theme_font_size_override("font_size", 20)
	patterns_toggle.toggled.connect(patterns_toggled.emit)
	box.add_child(patterns_toggle)

	sound_toggle = CheckButton.new()
	sound_toggle.text = tr("Sound effects")
	sound_toggle.add_theme_font_size_override("font_size", 20)
	sound_toggle.toggled.connect(sound_toggled.emit)
	box.add_child(sound_toggle)

	# Shown only where the game can notify (Android); see set_reminder.
	reminder_toggle = CheckButton.new()
	reminder_toggle.text = tr("Daily reminder")
	reminder_toggle.add_theme_font_size_override("font_size", 20)
	reminder_toggle.toggled.connect(reminder_toggled.emit)
	reminder_toggle.visible = false
	box.add_child(reminder_toggle)
	_reminder_row = HBoxContainer.new()
	_reminder_row.add_theme_constant_override("separation", 12)
	_reminder_row.visible = false
	box.add_child(_reminder_row)
	var reminder_label := Label.new()
	reminder_label.text = tr("Remind me at")
	reminder_label.size_flags_horizontal = SIZE_EXPAND_FILL
	reminder_label.add_theme_font_size_override("font_size", 20)
	_reminder_row.add_child(reminder_label)
	reminder_hour_picker = OptionButton.new()
	reminder_hour_picker.add_theme_font_size_override("font_size", 20)
	reminder_hour_picker.item_selected.connect(func(index: int) -> void: reminder_hour_chosen.emit(_hours[index]))
	_reminder_row.add_child(reminder_hour_picker)

	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 12)
	box.add_child(language_row)
	var language_label := Label.new()
	language_label.text = tr("Language")
	language_label.size_flags_horizontal = SIZE_EXPAND_FILL
	language_label.add_theme_font_size_override("font_size", 20)
	language_row.add_child(language_label)
	language_picker = OptionButton.new()
	language_picker.add_theme_font_size_override("font_size", 20)
	language_picker.item_selected.connect(func(index: int) -> void: language_chosen.emit(_locales[index]))
	language_row.add_child(language_picker)

	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	box.add_child(back_button)


## Fills the language picker with `names` (locale -> name) and selects `current`.
func set_languages(names: Dictionary, current: String) -> void:
	language_picker.clear()
	_locales = PackedStringArray([""])
	language_picker.add_item(tr("Device language"))
	for locale: String in names:
		_locales.append(locale)
		language_picker.add_item(names[locale])
	language_picker.select(maxi(0, _locales.find(current)))


## Shows the reminder settings when `available`, offering `hours` with `hour` selected.
func set_reminder(available: bool, enabled: bool, hours: Array, hour: int) -> void:
	reminder_toggle.visible = available
	reminder_toggle.set_pressed_no_signal(enabled)
	_reminder_row.visible = available
	reminder_hour_picker.clear()
	_hours.assign(hours)
	for h in _hours:
		reminder_hour_picker.add_item(_hour_name(h))
	reminder_hour_picker.select(maxi(0, _hours.find(hour)))
	show_reminder_enabled(enabled)


## Turns the toggle on or off without signalling, e.g. when permission is refused.
func show_reminder_enabled(enabled: bool) -> void:
	reminder_toggle.set_pressed_no_signal(enabled)
	reminder_hour_picker.disabled = not enabled


## "7:00 PM", or "19:00" in languages that use a 24-hour clock.
func _hour_name(hour: int) -> String:
	# TRANSLATORS: Write "24-hour" if your language shows times like 19:00, or leave "12-hour" for 7:00 PM.
	if tr("12-hour", "clock") == "24-hour":
		return "%d:00" % hour
	# TRANSLATORS: A time on a 12-hour clock; %d is the hour, 1 to 12.
	return (tr("%d:00 AM") if hour < 12 else tr("%d:00 PM")) % (posmod(hour - 1, 12) + 1)
