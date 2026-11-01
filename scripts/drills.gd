extends Control
## Drills screen: pick a technique from the tutorial to practise on a short
## run of boards, each opening just where that technique is needed.

signal drill_chosen(technique: String)
signal back

## The techniques, as the grader's steps name them (see main.gd's _technique).
const TECHNIQUES := ["confined", "group", "blocker"]

## Technique -> its button.
var buttons := {}
var back_button: Button
var _details := {}
var _box: VBoxContainer


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_box.add_theme_constant_override("separation", 10)
	center.add_child(_box)

	# TRANSLATORS: Practice runs of one solving technique at a time.
	var title := _label(tr("Drills"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var intro := _label(tr("Practise one technique at a time. Each board starts where it's needed."), 16)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.modulate = Color(1, 1, 1, 0.65)
	_box.add_child(intro)

	for technique: String in TECHNIQUES:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		_box.add_child(gap)
		var button := Button.new()
		button.text = technique_name(technique)
		button.custom_minimum_size.y = 56
		TextSize.set_font(button, 22)
		button.pressed.connect(drill_chosen.emit.bind(technique))
		_box.add_child(button)
		buttons[technique] = button
		var detail := _label("", 15)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.modulate = Color(1, 1, 1, 0.6)
		_box.add_child(detail)
		_details[technique] = detail

	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	_box.add_child(gap)
	back_button = Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size.y = 52
	TextSize.set_font(back_button, 20)
	back_button.pressed.connect(back.emit)
	_box.add_child(back_button)
	set_completed({})
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _box:
		_fit()


## As wide as reads comfortably, inside the screen's edges.
func _fit() -> void:
	_box.custom_minimum_size.x = clampf(size.x - 48.0, 0.0, 420.0)


## A technique's name, as the tutorial teaches it.
func technique_name(technique: String) -> String:
	match technique:
		"confined":
			# TRANSLATORS: A drill's name: a region inside one row or column claims that line.
			return tr("Claiming a line")
		"group":
			# TRANSLATORS: A drill's name: several regions inside as many lines.
			return tr("Groups")
	# TRANSLATORS: A drill's name: imagine a crown in a cell and see what it rules out.
	return tr("What if?")


## Shows each technique's description and how many of its drills were finished,
## from technique -> count.
func set_completed(completed: Dictionary) -> void:
	for technique: String in TECHNIQUES:
		var text := _description(technique)
		var count: int = completed.get(technique, 0)
		if count > 0:
			# TRANSLATORS: How many times a drill was finished.
			text += "\n" + tr_n("Completed %d time", "Completed %d times", count) % count
		_details[technique].text = text


func _description(technique: String) -> String:
	match technique:
		"confined":
			return tr("A region inside one row or column claims that line's crown.")
		"group":
			return tr("Two or more regions inside as many rows or columns claim them all.")
	return tr("A cell whose crown would leave a row, column or region with no room is ruled out.")


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	TextSize.set_font(label, font_size)
	return label
