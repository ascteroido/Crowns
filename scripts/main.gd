extends Control
## Menu plus game screen: puzzle picker, timer, board, undo/clear/hint and the win overlay.

const Board := preload("res://scripts/board.gd")
const BoardView := preload("res://scripts/board_view.gd")
const Generator := preload("res://scripts/generator.gd")
const Menu := preload("res://scripts/menu.gd")
const Settings := preload("res://scripts/settings.gd")

const LIGHT := {"background": Color("f4f1ea"), "text": Color("1e1e1e"), "panel": Color("fffdf8")}
const DARK := {"background": Color("1c1c1e"), "text": Color("ebe8e1"), "panel": Color("2c2c2f")}

const SIZES := [5, 6, 7, 8, 9, 10]
const DEFAULT_SIZE := 7
const DAILY_SIZES := [7, 8, 9]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Where progress and best times are stored; tests point this elsewhere.
var save_path := "user://queens_progress.cfg"

var _board: Board
## Save key of the loaded board; stays put while `_number` or `_size` change for the next load.
var _board_key := ""
var _size := DEFAULT_SIZE
var _number := 1
## Playing the daily puzzle for `_daily_date` ("YYYY-MM-DD") instead of the numbered ones.
var _daily := false
var _daily_date := ""
var _elapsed := 0.0
var _running := false
var _generating := false
var _hinted := false
var _undo: Array = []
var _progress := ConfigFile.new()

var _theme := Theme.new()
var _background: ColorRect
var _panel_style := StyleBoxFlat.new()
var _menu: Menu
var _settings: Settings
var _game: Control
var _size_picker: OptionButton
var _prev_button: Button
var _next_button: Button
var _puzzle_label: Label
var _timer_label: Label
var _best_label: Label
var _view: BoardView
var _undo_button: Button
var _win_overlay: Control
var _win_label: Label
var _next_puzzle_button: Button


func _ready() -> void:
	_progress.load(save_path)
	_size = _progress.get_value("last", "size", DEFAULT_SIZE)
	_number = _progress.get_value("last", "number", 1)
	_build_ui()
	var dark: bool = _progress.get_value("settings", "dark_mode", false)
	_settings.dark_mode_toggle.set_pressed_no_signal(dark)
	_apply_dark_mode(dark)
	_view.auto_cross = _progress.get_value("settings", "auto_cross", false)
	_settings.auto_cross_toggle.set_pressed_no_signal(_view.auto_cross)
	_prune_old_dailies()
	_show_menu()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_board()


func _process(delta: float) -> void:
	if _running:
		_elapsed += delta
		_timer_label.text = _format_time(_elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible and event.is_action_pressed("ui_cancel"):
		_show_menu()
		get_viewport().set_input_as_handled()
	if not _game.visible:
		return
	if event.is_action_pressed("ui_undo"):
		_on_undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_show_menu()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	theme = _theme
	_background = ColorRect.new()
	_background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_background)

	_menu = Menu.new()
	_menu.set_anchors_preset(PRESET_FULL_RECT)
	_menu.continue_chosen.connect(_start_regular)
	_menu.daily_chosen.connect(_start_daily)
	_menu.settings_chosen.connect(_show_settings)
	add_child(_menu)

	_settings = Settings.new()
	_settings.set_anchors_preset(PRESET_FULL_RECT)
	_settings.visible = false
	_settings.dark_mode_toggled.connect(_on_dark_mode_toggled)
	_settings.auto_cross_toggled.connect(_on_auto_cross_toggled)
	_settings.back.connect(_show_menu)
	add_child(_settings)

	_game = Control.new()
	_game.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_game)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_game.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	header.add_child(_button("Menu", _show_menu))
	var title := _label("Crowns", 34)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_size_picker = OptionButton.new()
	for s: int in SIZES:
		_size_picker.add_item("%d×%d" % [s, s], s)
	_size_picker.select(maxi(0, SIZES.find(_size)))
	_size_picker.item_selected.connect(_on_size_selected)
	header.add_child(_size_picker)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	column.add_child(nav)
	_prev_button = _button("Prev", func() -> void: _go_to(_number - 1))
	nav.add_child(_prev_button)
	_puzzle_label = _label("", 20)
	_puzzle_label.custom_minimum_size.x = 120
	_puzzle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_puzzle_label)
	_next_button = _button("Next", func() -> void: _go_to(_number + 1))
	nav.add_child(_next_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_best_label = _label("", 16)
	_best_label.modulate = Color(1, 1, 1, 0.6)
	nav.add_child(_best_label)
	_timer_label = _label("0:00", 24)
	_timer_label.custom_minimum_size.x = 80
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nav.add_child(_timer_label)

	_view = BoardView.new()
	_view.size_flags_vertical = SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(300, 300)
	_view.edited.connect(_on_board_edited)
	column.add_child(_view)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_undo_button = _button("Undo", _on_undo)
	actions.add_child(_undo_button)
	actions.add_child(_button("Clear", _on_clear))
	actions.add_child(_button("Hint", _on_hint))

	var help := _label("Place one crown in every row, column and colour region. Crowns may not touch, even diagonally.\n"
			+ "Click: empty → × → crown.  Drag from empty to cross out, from × to erase.  Right click: crown.  Ctrl+Z: undo.", 14)
	help.modulate = Color(1, 1, 1, 0.65)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)

	_build_win_overlay()


func _build_win_overlay() -> void:
	_win_overlay = ColorRect.new()
	(_win_overlay as ColorRect).color = Color(0, 0, 0, 0.45)
	_win_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_win_overlay.visible = false
	_game.add_child(_win_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_win_overlay.add_child(center)
	var panel := PanelContainer.new()
	_panel_style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", _panel_style)
	center.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	inner.add_child(box)

	var heading := _label("Solved!", 32)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	_win_label = _label("", 18)
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	buttons.add_child(_button("Look at board", func() -> void: _win_overlay.visible = false))
	buttons.add_child(_button("Menu", _show_menu))
	_next_puzzle_button = _button("Next puzzle", func() -> void: _go_to(_number + 1))
	buttons.add_child(_next_puzzle_button)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90, 40)
	button.pressed.connect(on_pressed)
	return button


func _show_menu() -> void:
	if _generating:
		return
	_save_board()
	_running = false
	_game.visible = false
	_settings.visible = false
	_menu.visible = true
	var started := _progress.has_section("last")
	var today := _today()
	var best: float = _progress.get_value("best", _daily_key(today), INF)
	var daily_detail := "%s · %d×%d" % [_pretty_date(today), _daily_size(today), _daily_size(today)]
	if best != INF:
		daily_detail = "Solved in %s" % _format_time(best)
	elif _progress.get_value("solved", _daily_key(today), false):
		daily_detail = "Solved (hints used)"
	_menu.set_details("Continue" if started else "Play",
			"%d×%d · Puzzle #%d" % [_size, _size, _number], daily_detail)


func _show_settings() -> void:
	_menu.visible = false
	_settings.visible = true


func _on_dark_mode_toggled(enabled: bool) -> void:
	_apply_dark_mode(enabled)
	_progress.set_value("settings", "dark_mode", enabled)
	_progress.save(save_path)


func _on_auto_cross_toggled(enabled: bool) -> void:
	_view.auto_cross = enabled
	_progress.set_value("settings", "auto_cross", enabled)
	_progress.save(save_path)


func _apply_dark_mode(enabled: bool) -> void:
	var colors: Dictionary = DARK if enabled else LIGHT
	_background.color = colors.background
	_panel_style.bg_color = colors.panel
	_theme.set_color("font_color", "Label", colors.text)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_theme.set_color(state, "CheckButton", colors.text)
	# Godot's default buttons are translucent dark grey, which vanishes on the dark background.
	var fills := {"normal": Color("3a3a3e"), "hover": Color("4a4a4f"), "pressed": Color("2a2a2d"),
			"hover_pressed": Color("2a2a2d"), "disabled": Color("2a2a2d", 0.6)}
	for state: String in fills:
		if enabled:
			var box := StyleBoxFlat.new()
			box.bg_color = fills[state]
			box.set_corner_radius_all(3)
			box.set_content_margin_all(4)
			_theme.set_stylebox(state, "Button", box)
			# Keep the toggle switch borderless; it would otherwise inherit the button fill.
			_theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
		elif _theme.has_stylebox(state, "Button"):
			_theme.clear_stylebox(state, "Button")
			_theme.clear_stylebox(state, "CheckButton")
	_view.dark = enabled


func _start_regular() -> void:
	_daily = false
	_open_game()


func _start_daily() -> void:
	_daily = true
	_daily_date = _today()
	_open_game()


func _open_game() -> void:
	_menu.visible = false
	_game.visible = true
	_size_picker.visible = not _daily
	_prev_button.visible = not _daily
	_next_button.visible = not _daily
	_next_puzzle_button.visible = not _daily
	_load_puzzle()


func _load_puzzle() -> void:
	_save_board()
	_running = false
	_win_overlay.visible = false
	_view.interactive = false
	_generating = true
	_puzzle_label.text = "Generating…"
	# Let the label paint before the larger sizes block for a moment.
	await get_tree().process_frame
	await get_tree().process_frame

	var size := _daily_size(_daily_date) if _daily else _size
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["daily", _daily_date]) if _daily else hash([_size, _number])
	var puzzle := Generator.generate(size, rng)
	_board = Board.new(size, puzzle.regions, puzzle.solution)
	_board_key = _puzzle_key()
	_hinted = false
	_elapsed = 0.0
	var saved: Dictionary = _progress.get_value("in_progress", _board_key, {})
	if saved.get("marks", PackedInt32Array()).size() == _board.marks.size():
		_board.marks = saved.marks
		_elapsed = saved.elapsed
		_hinted = saved.hinted
	_view.board = _board
	_view.interactive = true
	_generating = false
	_undo.clear()
	_undo_button.disabled = true
	_timer_label.text = _format_time(_elapsed)
	_running = true
	_puzzle_label.text = "Daily · %s" % _pretty_date(_daily_date) if _daily else "Puzzle #%d" % _number
	_update_best()

	if not _daily:
		_progress.set_value("last", "size", _size)
		_progress.set_value("last", "number", _number)
		_progress.save(save_path)


func _go_to(number: int) -> void:
	if number < 1 or _generating or _daily:
		return
	_number = number
	_load_puzzle()


func _on_size_selected(index: int) -> void:
	if _generating:
		_size_picker.select(SIZES.find(_size))
		return
	_size = SIZES[index]
	_number = 1
	_load_puzzle()


func _on_board_edited(changes: Array) -> void:
	_undo.append(changes)
	_undo_button.disabled = false
	_check_win()
	_save_board()


## Stores the loaded board's marks and timer, or forgets them once it is solved.
func _save_board() -> void:
	if _board == null:
		return
	if _board.is_solved():
		if _progress.has_section_key("in_progress", _board_key):
			_progress.erase_section_key("in_progress", _board_key)
	else:
		_progress.set_value("in_progress", _board_key,
				{"marks": _board.marks, "elapsed": _elapsed, "hinted": _hinted})
	_progress.save(save_path)


func _prune_old_dailies() -> void:
	if not _progress.has_section("in_progress"):
		return
	for key in _progress.get_section_keys("in_progress"):
		if key.begins_with("daily_") and key != _daily_key(_today()):
			_progress.erase_section_key("in_progress", key)
	_progress.save(save_path)


func _on_undo() -> void:
	if _undo.is_empty() or not _view.interactive:
		return
	var changes: Array = _undo.pop_back()
	for i in range(changes.size() - 1, -1, -1):
		_board.set_mark(changes[i][0], changes[i][1])
	_undo_button.disabled = _undo.is_empty()
	_view.queue_redraw()
	_save_board()


func _on_clear() -> void:
	if not _view.interactive:
		return
	var changes := []
	var n := _board.size
	for i in _board.marks.size():
		if _board.marks[i] != Board.Mark.EMPTY:
			changes.append([Vector2i(i / n, i % n), _board.marks[i], Board.Mark.EMPTY])
	if changes.is_empty():
		return
	_apply(changes)


## Removes a misplaced crown if there is one, otherwise places a correct crown.
func _on_hint() -> void:
	if not _view.interactive:
		return
	_hinted = true
	for cell in _board.crowns():
		if _board.solution[cell.x] != cell.y:
			_apply([[cell, Board.Mark.CROWN, Board.Mark.EMPTY]])
			return
	for row in _board.size:
		var cell := Vector2i(row, _board.solution[row])
		if _board.get_mark(cell) != Board.Mark.CROWN:
			_apply([[cell, _board.get_mark(cell), Board.Mark.CROWN]])
			return


## Applies an undoable batch of [cell, old, new] changes made outside the board view.
func _apply(changes: Array) -> void:
	for change in changes:
		_board.set_mark(change[0], change[2])
	if _view.auto_cross:
		var auto := _board.auto_cross_changes()
		for change in auto:
			_board.set_mark(change[0], change[2])
		changes.append_array(auto)
	_view.queue_redraw()
	_on_board_edited(changes)


func _check_win() -> void:
	if not _board.is_solved():
		return
	_running = false
	_view.interactive = false
	var key := _puzzle_key()
	var best: float = _progress.get_value("best", key, INF)
	# Hinted solves don't count towards best times.
	var record := not _hinted and _elapsed < best
	if record:
		_progress.set_value("best", key, _elapsed)
	_progress.set_value("solved", key, true)
	_progress.save(save_path)
	var note := "  (hints used)" if _hinted else "  (new best!)" if record and best != INF else ""
	_win_label.text = "Time: %s%s" % [_format_time(_elapsed), note]
	_update_best()
	_win_overlay.visible = true


func _update_best() -> void:
	var best: float = _progress.get_value("best", _puzzle_key(), INF)
	_best_label.text = "" if best == INF else "Best %s" % _format_time(best)


func _puzzle_key() -> String:
	return _daily_key(_daily_date) if _daily else "%dx%d_%d" % [_size, _size, _number]


func _daily_key(date: String) -> String:
	return "daily_" + date


func _daily_size(date: String) -> int:
	return DAILY_SIZES[posmod(hash(["daily_size", date]), DAILY_SIZES.size())]


func _today() -> String:
	return Time.get_date_string_from_system()


## "2026-10-23" -> "Oct 23".
func _pretty_date(date: String) -> String:
	var parts := date.split("-")
	return "%s %d" % [MONTHS[parts[1].to_int() - 1], parts[2].to_int()]


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
