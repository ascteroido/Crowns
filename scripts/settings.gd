extends Control
## Settings screen.

signal theme_chosen(theme_name: String)
## A custom theme colour changed; `done` once the picker closes.
signal custom_colors_changed(background: Color, button: Color, done: bool)
## "theme" to match the theme, or one of the game's app icons.
signal app_icon_chosen(icon: String)
signal auto_cross_toggled(enabled: bool)
signal patterns_toggled(enabled: bool)
signal reduce_motion_toggled(enabled: bool)
signal timer_toggled(shown: bool)
## Whether wide layouts put the board on the right, beside the controls.
signal board_side_toggled(right: bool)
signal sound_toggled(enabled: bool)
## The volume slider moved; `preview` once it settles, to play a sample.
signal volume_changed(volume: float, preview: bool)
signal vibration_toggled(enabled: bool)
signal reminder_toggled(enabled: bool)
signal reminder_hour_chosen(hour: int)
## Debug builds only: show the reminder notification now.
signal test_reminder
signal silent_wolf_toggled(enabled: bool)
## An empty locale means the device's language.
signal language_chosen(locale: String)
signal how_to_play
signal back

## Theme names in picker order, matching the game's THEMES plus "custom".
const THEMES := ["light", "dark", "midnight", "forest", "contrast", "custom"]
## App icon choices in picker order: matching the theme, then each icon.
const APP_ICONS := ["theme", "classic", "dark", "midnight", "forest", "contrast"]

var theme_picker: OptionButton
var background_picker: ColorPickerButton
var button_color_picker: ColorPickerButton
## The custom theme's colours, shown only while it's chosen.
var _custom_row: HBoxContainer
var app_icon_picker: OptionButton
## Shown only where the icon can change (Android).
var _app_icon_row: HBoxContainer
var auto_cross_toggle: CheckButton
var patterns_toggle: CheckButton
var reduce_motion_toggle: CheckButton
var timer_toggle: CheckButton
var board_side_toggle: CheckButton
var sound_toggle: CheckButton
## Desktop and web only; phones have volume buttons.
var volume_slider: HSlider
var _volume_row: HBoxContainer
var _volume_dragging := false
## Shown only where the game can vibrate (Android).
var vibration_toggle: CheckButton
var reminder_toggle: CheckButton
var reminder_hour_picker: OptionButton
var _test_reminder_button: Button
## Shown only in builds with SilentWolf's key.
var silent_wolf_toggle: CheckButton
var _reminder_row: HBoxContainer
## Hour of each reminder_hour_picker item.
var _hours: Array[int] = []
var language_picker: OptionButton
## Locale of each language_picker item, "" for the device's language.
var _locales := PackedStringArray()
## The settings rows, split into two columns on wide screens.
var _rows: Array[Control] = []
var _box: VBoxContainer
var _columns: HBoxContainer
var _footer: BoxContainer
var _wide := false


func _ready() -> void:
	# Scrolls should the settings ever be taller than the screen.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Keeps what a gamepad or the keyboard selects in view.
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	center.add_child(outer)

	var title := Label.new()
	title.text = tr("Settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	outer.add_child(title)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 56)
	outer.add_child(_columns)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 280
	_box.add_theme_constant_override("separation", 16)
	_columns.add_child(_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	right.add_theme_constant_override("separation", 16)
	right.visible = false
	_columns.add_child(right)
	var box := _box

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	box.add_child(theme_row)
	# TRANSLATORS: The colour theme setting.
	theme_row.add_child(_row_label(tr("Theme")))
	theme_picker = OptionButton.new()
	theme_picker.add_theme_font_size_override("font_size", 20)
	# TRANSLATORS: Colour theme names.
	var names := {"light": tr("Light"), "dark": tr("Dark"), "midnight": tr("Midnight"), "forest": tr("Forest"),
			"contrast": tr("High contrast"), "custom": tr("Custom")}
	for theme_name: String in THEMES:
		theme_picker.add_item(names[theme_name])
	theme_picker.item_selected.connect(func(index: int) -> void: theme_chosen.emit(THEMES[index]))
	theme_row.add_child(theme_picker)

	_custom_row = HBoxContainer.new()
	_custom_row.add_theme_constant_override("separation", 10)
	_custom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_custom_row.visible = false
	box.add_child(_custom_row)
	# TRANSLATORS: The custom theme's colours: the page behind everything, and the buttons.
	_custom_row.add_child(_row_label(tr("Background")))
	background_picker = _color_button()
	_custom_row.add_child(background_picker)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	_custom_row.add_child(gap)
	_custom_row.add_child(_row_label(tr("Buttons")))
	button_color_picker = _color_button()
	_custom_row.add_child(button_color_picker)

	_app_icon_row = HBoxContainer.new()
	_app_icon_row.add_theme_constant_override("separation", 12)
	_app_icon_row.visible = false
	box.add_child(_app_icon_row)
	_app_icon_row.add_child(_row_label(tr("App icon")))
	app_icon_picker = OptionButton.new()
	app_icon_picker.add_theme_font_size_override("font_size", 20)
	# TRANSLATORS: App icon choices: following the colour theme, or the original purple icon.
	var icon_names := {"theme": tr("Match theme"), "classic": tr("Classic")}
	icon_names.merge(names)
	for icon: String in APP_ICONS:
		app_icon_picker.add_item(icon_names[icon])
	app_icon_picker.item_selected.connect(func(index: int) -> void: app_icon_chosen.emit(APP_ICONS[index]))
	_app_icon_row.add_child(app_icon_picker)

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

	reduce_motion_toggle = CheckButton.new()
	# TRANSLATORS: Turns off the board's animations, for players sensitive to motion.
	reduce_motion_toggle.text = tr("Disable animations")
	reduce_motion_toggle.add_theme_font_size_override("font_size", 20)
	reduce_motion_toggle.toggled.connect(reduce_motion_toggled.emit)
	box.add_child(reduce_motion_toggle)

	timer_toggle = CheckButton.new()
	timer_toggle.text = tr("Show timer")
	timer_toggle.add_theme_font_size_override("font_size", 20)
	timer_toggle.toggled.connect(timer_toggled.emit)
	box.add_child(timer_toggle)

	board_side_toggle = CheckButton.new()
	# TRANSLATORS: In the side-by-side layout of wide screens, put the board right of the buttons instead of left.
	board_side_toggle.text = tr("Board on the right (wide screens)")
	board_side_toggle.add_theme_font_size_override("font_size", 20)
	board_side_toggle.toggled.connect(board_side_toggled.emit)
	box.add_child(board_side_toggle)

	sound_toggle = CheckButton.new()
	sound_toggle.text = tr("Sound effects")
	sound_toggle.add_theme_font_size_override("font_size", 20)
	sound_toggle.toggled.connect(sound_toggled.emit)
	box.add_child(sound_toggle)

	_volume_row = HBoxContainer.new()
	_volume_row.add_theme_constant_override("separation", 12)
	_volume_row.visible = not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
	box.add_child(_volume_row)
	var volume_label := _row_label(tr("Volume"))
	volume_label.size_flags_horizontal = SIZE_FILL
	_volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.value = 100
	volume_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = SIZE_SHRINK_CENTER
	# A sample plays when the slider settles: on letting go, or at once for clicks and keys.
	volume_slider.drag_started.connect(func() -> void: _volume_dragging = true)
	volume_slider.drag_ended.connect(func(_changed: bool) -> void:
		_volume_dragging = false
		volume_changed.emit(volume_slider.value / 100.0, true))
	volume_slider.value_changed.connect(func(value: float) -> void:
		volume_changed.emit(value / 100.0, not _volume_dragging))
	_volume_row.add_child(volume_slider)

	vibration_toggle = CheckButton.new()
	vibration_toggle.text = tr("Vibration")
	vibration_toggle.add_theme_font_size_override("font_size", 20)
	vibration_toggle.toggled.connect(vibration_toggled.emit)
	vibration_toggle.visible = false
	box.add_child(vibration_toggle)

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

	silent_wolf_toggle = CheckButton.new()
	# TRANSLATORS: SilentWolf is the name of the leaderboard service; keep it as is.
	silent_wolf_toggle.text = tr("Online leaderboards (SilentWolf)")
	silent_wolf_toggle.add_theme_font_size_override("font_size", 20)
	silent_wolf_toggle.toggled.connect(silent_wolf_toggled.emit)
	silent_wolf_toggle.visible = false
	box.add_child(silent_wolf_toggle)

	# Debug builds only, so not translated.
	_test_reminder_button = Button.new()
	_test_reminder_button.text = "Send test reminder"
	_test_reminder_button.add_theme_font_size_override("font_size", 18)
	_test_reminder_button.pressed.connect(test_reminder.emit)
	_test_reminder_button.visible = false
	box.add_child(_test_reminder_button)

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

	_rows.assign(box.get_children())
	_footer = BoxContainer.new()
	_footer.vertical = true
	_footer.add_theme_constant_override("separation", 16)
	outer.add_child(_footer)

	var tutorial_button := Button.new()
	tutorial_button.text = tr("How to play")
	tutorial_button.custom_minimum_size = Vector2(0, 52)
	tutorial_button.add_theme_font_size_override("font_size", 20)
	tutorial_button.pressed.connect(how_to_play.emit)
	tutorial_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_footer.add_child(tutorial_button)

	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(back.emit)
	back_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_footer.add_child(back_button)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _box:
		_fit()


## One column on tall screens; on wide ones, the rows after the sound settings
## move to a second column beside them.
func _fit() -> void:
	var wide := size.x >= size.y * 1.25 and size.x >= 720.0
	if wide == _wide:
		return
	_wide = wide
	var right: VBoxContainer = _columns.get_child(1)
	var split := _rows.find(vibration_toggle)
	for index in range(split, _rows.size()):
		_rows[index].reparent(right if wide else _box, false)
	right.visible = wide
	# Side by side under the two columns; stacked under the one.
	_footer.vertical = not wide


## Selects `theme_name` and shows the custom colours, which only it uses.
func show_theme(theme_name: String, background: Color, button: Color) -> void:
	theme_picker.select(maxi(0, THEMES.find(theme_name)))
	background_picker.color = background
	button_color_picker.color = button
	_custom_row.visible = theme_name == "custom"


## Shows the app icon choice where the icon can change, with `icon` selected.
func show_app_icon(available: bool, icon: String) -> void:
	_app_icon_row.visible = available
	app_icon_picker.select(maxi(0, APP_ICONS.find(icon)))


## Sets the volume slider without signalling, greyed out while sound is off.
func show_volume(volume: float, enabled: bool) -> void:
	volume_slider.set_value_no_signal(volume * 100.0)
	volume_slider.editable = enabled
	volume_slider.modulate.a = 1.0 if enabled else 0.45


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 20)
	return label


## A swatch that opens a colour picker kept simple for phones: a colour wheel
## and a hex box, no alpha, presets or screen sampling.
func _color_button() -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.edit_alpha = false
	button.custom_minimum_size = Vector2(56, 40)
	var picker := button.get_picker()
	picker.picker_shape = ColorPicker.SHAPE_OKHSL_CIRCLE
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.hex_visible = true
	button.color_changed.connect(func(_color: Color) -> void: _emit_custom_colors(false))
	button.popup_closed.connect(_emit_custom_colors.bind(true))
	return button


func _emit_custom_colors(done: bool) -> void:
	custom_colors_changed.emit(background_picker.color, button_color_picker.color, done)


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
	_test_reminder_button.visible = available and OS.is_debug_build()
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
