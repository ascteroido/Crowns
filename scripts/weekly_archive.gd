extends Control
## Weekly archive: every weekly challenge so far, newest first, to play or replay.
## Solved weeks are filled green and wear a crown, as solved days do in the
## daily archive.

signal week_chosen(week: String)
signal back

const Archive := preload("res://scripts/archive.gd")

var back_button: Button
var _list: VBoxContainer
var _box: VBoxContainer


func _ready() -> void:
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
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)

	# TRANSLATORS: The heading over past weekly challenges.
	var title := _label(tr("Weekly archive"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_box.add_child(_list)

	back_button = Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size.y = 52
	TextSize.set_font(back_button, 20)
	back_button.pressed.connect(back.emit)
	_box.add_child(back_button)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _box:
		_fit()


## As wide as reads comfortably, inside the screen's edges.
func _fit() -> void:
	_box.custom_minimum_size.x = clampf(size.x - 48.0, 0.0, 420.0)


## Lists the weeks, each {"week": its Monday, "title", "detail", "solved", "current"},
## newest first.
func set_weeks(weeks: Array) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for week: Dictionary in weeks:
		var button := Button.new()
		button.text = week.title + ("\n" + week.detail if not week.detail.is_empty() else "")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 64
		TextSize.set_font(button, 18)
		if week.solved:
			for state: String in Archive.SOLVED_FILLS:
				# The theme's button, recoloured, so the text lines up with the other weeks'.
				var box := get_theme_stylebox(state, "Button").duplicate()
				if box is StyleBoxFlat:
					(box as StyleBoxFlat).bg_color = Archive.SOLVED_FILLS[state]
				button.add_theme_stylebox_override(state, box)
			var crown := Archive._DayCrown.new()
			crown.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
			crown.offset_left = -44
			crown.offset_right = -14
			crown.mouse_filter = MOUSE_FILTER_IGNORE
			button.add_child(crown)
		if week.current:
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				button.add_theme_color_override(state, Archive.TODAY_COLOR)
		button.pressed.connect(week_chosen.emit.bind(week.week))
		_list.add_child(button)


## The first week's button, for the gamepad and keyboard to start on.
func first_button() -> Button:
	return _list.get_child(0) if _list.get_child_count() > 0 else back_button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	TextSize.set_font(label, font_size)
	return label
