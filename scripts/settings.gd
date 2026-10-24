extends Control
## Settings screen.

signal dark_mode_toggled(enabled: bool)
signal auto_cross_toggled(enabled: bool)
signal patterns_toggled(enabled: bool)
signal back

var dark_mode_toggle: CheckButton
var auto_cross_toggle: CheckButton
var patterns_toggle: CheckButton


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	dark_mode_toggle = CheckButton.new()
	dark_mode_toggle.text = "Dark mode"
	dark_mode_toggle.add_theme_font_size_override("font_size", 20)
	dark_mode_toggle.toggled.connect(dark_mode_toggled.emit)
	box.add_child(dark_mode_toggle)

	auto_cross_toggle = CheckButton.new()
	auto_cross_toggle.text = "Auto-place × around crowns"
	auto_cross_toggle.add_theme_font_size_override("font_size", 20)
	auto_cross_toggle.toggled.connect(auto_cross_toggled.emit)
	box.add_child(auto_cross_toggle)

	patterns_toggle = CheckButton.new()
	patterns_toggle.text = "Region patterns"
	patterns_toggle.add_theme_font_size_override("font_size", 20)
	patterns_toggle.toggled.connect(patterns_toggled.emit)
	box.add_child(patterns_toggle)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	box.add_child(back_button)
