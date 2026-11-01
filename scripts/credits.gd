extends Control
## Credits screen: who made what, under which licence, with each licence's
## full text a tap away. The same list as CREDITS.md in the repository.

signal back

const SOURCE := "https://github.com/ascteroido/Crowns"
const CC_BY := ["CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"]
const CC_BY_SA := ["CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"]
const CC0 := ["CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"]

var back_button: Button
var _box: VBoxContainer


func _ready() -> void:
	visibility_changed.connect(_build)


## Built when first shown, so it costs nothing at startup.
func _build() -> void:
	if not visible or _box:
		return
	# Scrolls, since the licences are long.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	center.add_child(_box)

	var title := _label(tr("Credits"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)

	_heading("Crowns")
	_text(tr("Crowns is free software: you can share and change it under the GNU General Public License, version 3 or later. It comes with no warranty."))
	_links([[tr("Source code"), SOURCE]])
	_licence("GNU General Public License v3.0", _file.bind("res://LICENSE"))
	_text(tr("The app icon and other artwork are licensed under %s.") % CC_BY_SA[0])
	_links([CC_BY_SA])

	# TRANSLATORS: Credits heading over the sound effects' authors.
	_heading(tr("Sounds"))
	_sound("Item Pickup", "Strechy", "https://freesound.org/people/Strechy/sounds/654251/", CC_BY)
	_sound("Puzzle piece picked up from table", "el_boss", "https://freesound.org/people/el_boss/sounds/560699/", CC0)
	_sound("Mastodon trumpet", "vintprox", "https://freesound.org/people/vintprox/sounds/854137/", CC0)

	# TRANSLATORS: Credits heading over the fonts' authors.
	_heading(tr("Fonts"))
	_text("DejaVu Sans, by Bitstream and the DejaVu authors")
	_licence(tr("DejaVu fonts licence"), _file.bind("res://fonts/DejaVuSans-LICENSE.txt"))
	_text("Noto Sans Arabic and Noto Sans Hebrew, by the Noto Project Authors")
	_licence("SIL Open Font License 1.1", _file.bind("res://fonts/Noto-LICENSE.txt"))

	# TRANSLATORS: Credits heading over the game engine and libraries.
	_heading(tr("Software"))
	_text(tr("Made with Godot Engine."))
	_links([["godotengine.org", "https://godotengine.org"]])
	_licence("Godot Engine (MIT License)", Engine.get_license_text)
	_licence(tr("Godot's third-party components"), _engine_components)
	if OS.has_feature("play_store"):
		_text("Godot Play Game Services, by Jacob Ibáñez Sánchez")
		_licence("MIT License", _file.bind("res://addons/GodotPlayGameServices/LICENSE"))

	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_box.add_child(gap)
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
	_box.custom_minimum_size.x = clampf(size.x - 32.0, 0.0, 560.0)


func _sound(title: String, author: String, url: String, licence: Array) -> void:
	# TRANSLATORS: A sound's credit, e.g. "Item Pickup by Strechy".
	_text(tr("{title} by {author}").format({"title": title, "author": author}))
	_links([["freesound.org", url], licence])


func _heading(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_box.add_child(gap)
	_box.add_child(_label(text, 24))


func _text(text: String) -> void:
	var label := _label(text, 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(label)


## A row of links, each [text, url], opened in the browser.
func _links(links: Array) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	for link: Array in links:
		var button := LinkButton.new()
		button.text = link[0]
		button.tooltip_text = link[1]
		button.focus_mode = FOCUS_ALL
		TextSize.set_font(button, 15)
		button.pressed.connect(OS.shell_open.bind(link[1]))
		row.add_child(button)
	_box.add_child(row)


## A licence's name as a button that shows or hides its full text, from
## `text` (a Callable returning it). The text is only laid out once opened,
## as the long ones would slow every theme and text size change.
func _licence(name: String, text: Callable) -> void:
	var button := Button.new()
	button.text = "▸ " + name
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	TextSize.set_font(button, 15)
	_box.add_child(button)
	var body := _label("", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.modulate = Color(1, 1, 1, 0.75)
	body.visible = false
	_box.add_child(body)
	button.pressed.connect(func() -> void:
		body.visible = not body.visible
		body.text = (text.call() as String).strip_edges() if body.visible else ""
		button.text = ("▾ " if body.visible else "▸ ") + name)


## The licences of the libraries built into Godot, grouped by licence.
func _engine_components() -> String:
	var parts := PackedStringArray()
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component.parts:
			parts.append("%s\n© %s\n%s" % [component.name, "\n© ".join(part.copyright), part.license])
	var licences: Dictionary = Engine.get_license_info()
	for licence: String in licences:
		parts.append("―― %s ――\n%s" % [licence, licences[licence]])
	return "\n\n".join(parts)


func _file(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	TextSize.set_font(label, font_size)
	return label
