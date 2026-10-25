extends Control
## Settings screen.

signal dark_mode_toggled(enabled: bool)
signal auto_cross_toggled(enabled: bool)
signal patterns_toggled(enabled: bool)
signal sound_toggled(enabled: bool)
## An empty locale means the device's language.
signal language_chosen(locale: String)
signal back

var dark_mode_toggle: CheckButton
var auto_cross_toggle: CheckButton
var patterns_toggle: CheckButton
var sound_toggle: CheckButton
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
