extends Control
## The in-game leaderboards, read from SilentWolf: today's daily, this week's
## weekly, The Climb and puzzles solved. On Android a button also opens the same
## board in Google Play Games.

signal back
## The player changed their leaderboard name.
signal name_changed(player_name: String)
## Open the Google Play Games board matching the `kind` tab.
signal play_games_chosen(kind: String)

const SilentWolf := preload("res://scripts/silent_wolf.gd")
const GOLD := Color("f4c542")
const KINDS := ["daily", "weekly", "climb", "solved"]

var client: SilentWolf
## Set by the game before show_board(): kind -> {"board": SilentWolf board name,
## "title": what it covers, "format": Callable turning a score into text}.
var boards := {}
var player_id := ""
## Colour of the player's own row; the game sets it to suit light or dark mode.
var highlight := GOLD

var name_entry: LineEdit
## Shown only where Google Play Games is available.
var play_games_button: Button
var _tabs := {}
var _subtitle: Label
var _status: Label
var _list: GridContainer
var _kind := "daily"
## Bumped by every load, so a slow answer for a board no longer shown is dropped.
var _load := 0


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(PRESET_FULL_RECT)
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.offset_left = -220
	column.offset_right = 220
	column.offset_top = 32
	column.offset_bottom = -24
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var title := _label(tr("Leaderboards"), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	column.add_child(tab_row)
	var group := ButtonGroup.new()
	# TRANSLATORS: Leaderboard tabs; keep them short, four share one row.
	var names := {"daily": tr("Daily"), "weekly": tr("Weekly"), "climb": tr("The Climb"), "solved": tr("Solved")}
	for kind: String in KINDS:
		var tab := Button.new()
		tab.text = names[kind]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 44
		tab.add_theme_font_size_override("font_size", 16)
		tab.add_theme_color_override("font_pressed_color", GOLD)
		tab.add_theme_color_override("font_hover_pressed_color", GOLD)
		tab.pressed.connect(show_board.bind(kind))
		tab_row.add_child(tab)
		_tabs[kind] = tab

	_subtitle = _label("", 17)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_status = _label("", 17)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_status)
	_list = GridContainer.new()
	_list.columns = 3
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 16)
	_list.add_theme_constant_override("v_separation", 6)
	inner.add_child(_list)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	column.add_child(name_row)
	name_row.add_child(_label(tr("Your name"), 17))
	name_entry = LineEdit.new()
	name_entry.max_length = SilentWolf.NAME_LENGTH
	name_entry.size_flags_horizontal = SIZE_EXPAND_FILL
	name_entry.custom_minimum_size.y = 40
	name_entry.add_theme_font_size_override("font_size", 18)
	name_entry.text_submitted.connect(func(_text: String) -> void: _commit_name())
	name_entry.focus_exited.connect(_commit_name)
	name_row.add_child(name_entry)
	var note := _label(tr("New scores go up under this name."), 14)
	note.modulate = Color(1, 1, 1, 0.6)
	column.add_child(note)

	play_games_button = Button.new()
	play_games_button.text = tr("Open in Google Play Games")
	play_games_button.custom_minimum_size = Vector2(0, 48)
	play_games_button.add_theme_font_size_override("font_size", 18)
	play_games_button.pressed.connect(func() -> void: play_games_chosen.emit(_kind))
	play_games_button.visible = false
	column.add_child(play_games_button)

	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.custom_minimum_size = Vector2(0, 52)
	back_button.add_theme_font_size_override("font_size", 20)
	back_button.pressed.connect(func() -> void:
		_commit_name()
		back.emit())
	column.add_child(back_button)


## Shows the `kind` board ("daily", "weekly", "climb" or "solved") and loads it.
func show_board(kind: String) -> void:
	_kind = kind
	for tab_kind: String in _tabs:
		_tabs[tab_kind].set_pressed_no_signal(tab_kind == kind)
	var info: Dictionary = boards.get(kind, {})
	_subtitle.text = info.get("title", "")
	for child in _list.get_children():
		child.queue_free()
	_status.text = tr("Loading…")
	_status.visible = true
	_load += 1
	var load_id := _load
	var entries: Variant = await client.fetch(info.board) if client and info.has("board") else null
	if load_id != _load:
		return
	if entries == null:
		_status.text = tr("Couldn't reach the leaderboard. Check your connection and try again.")
		return
	if entries.is_empty():
		_status.text = tr("No scores yet. Be the first!")
		return
	_status.visible = false
	var format: Callable = info.format
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var mine: bool = not player_id.is_empty() and entry.id == player_id
		var cells := [_label("%d" % (i + 1), 17), _label(entry.name, 17), _label(format.call(entry.score), 17)]
		cells[0].modulate = Color(1, 1, 1, 0.6)
		cells[1].size_flags_horizontal = SIZE_EXPAND_FILL
		cells[1].clip_text = true
		cells[2].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for cell: Label in cells:
			if mine:
				cell.add_theme_color_override("font_color", highlight)
				cell.modulate = Color.WHITE
			_list.add_child(cell)


## The board shown, for the game to know which tab to reopen.
func kind() -> String:
	return _kind


func _commit_name() -> void:
	var cleaned := SilentWolf.clean_name(name_entry.text)
	if cleaned.is_empty():
		return
	name_entry.text = cleaned
	name_changed.emit(cleaned)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
