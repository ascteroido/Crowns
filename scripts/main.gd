extends Control
## Menu plus game screen: puzzle picker, timer, board, undo/clear/hint and the win overlay.

const Board := preload("res://scripts/board.gd")
const BoardView := preload("res://scripts/board_view.gd")
const Generator := preload("res://scripts/generator.gd")
const Grader := preload("res://scripts/grader.gd")
const Menu := preload("res://scripts/menu.gd")
const Settings := preload("res://scripts/settings.gd")
const Stats := preload("res://scripts/stats.gd")
const Archive := preload("res://scripts/archive.gd")
const PlayGames := preload("res://scripts/play_games.gd")
const Sounds := preload("res://scripts/sounds.gd")
const CrownIcon := preload("res://scripts/crown_icon.gd")

const LIGHT := {"background": Color("f4f1ea"), "text": Color("1e1e1e"), "panel": Color("fffdf8")}
const DARK := {"background": Color("1c1c1e"), "text": Color("ebe8e1"), "panel": Color("2c2c2f")}
## Button fills, matching the purple of the app icon; deeper in dark mode.
const BUTTON_LIGHT := {"normal": Color("5b4a9e"), "hover": Color("6b59b3"), "pressed": Color("483a85"),
		"hover_pressed": Color("483a85"), "disabled": Color("5b4a9e", 0.45)}
const BUTTON_DARK := {"normal": Color("46397f"), "hover": Color("554794"), "pressed": Color("372c66"),
		"hover_pressed": Color("372c66"), "disabled": Color("46397f", 0.45)}
const GOLD := Color("f4c542")
## Screens fade in over this many seconds.
const FADE := 0.15

enum Mode { REGULAR, DAILY, CHALLENGE }

const SIZES := [5, 6, 7, 8, 9, 10]
const DEFAULT_SIZE := 7
const DAILY_SIZES := [7, 8, 9]
const DEFAULT_DIFFICULTY := Generator.Difficulty.MEDIUM
const DAILY_DIFFICULTY := Generator.Difficulty.MEDIUM
const DAILY_UTC_OFFSET := -7 * 3600
## The first daily puzzle in the archive.
const DAILY_FIRST := "2026-10-01"
## [size, difficulty] for each challenge puzzle; the last one repeats.
const CHALLENGE_STAGES := [
	[5, Generator.Difficulty.EASY], [5, Generator.Difficulty.EASY], [6, Generator.Difficulty.EASY],
	[6, Generator.Difficulty.MEDIUM], [6, Generator.Difficulty.MEDIUM], [7, Generator.Difficulty.MEDIUM],
	[7, Generator.Difficulty.MEDIUM], [7, Generator.Difficulty.HARD], [8, Generator.Difficulty.MEDIUM],
	[8, Generator.Difficulty.HARD], [8, Generator.Difficulty.HARD], [9, Generator.Difficulty.MEDIUM],
	[9, Generator.Difficulty.HARD], [9, Generator.Difficulty.HARD], [10, Generator.Difficulty.HARD],
]
const CHALLENGE_KEY := "challenge"
## Save section for streaks and per-size totals.
const STATS := "stats"
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Where progress and best times are stored; tests point this elsewhere.
var save_path := "user://queens_progress.cfg"

var _board: Board
## Save key of the loaded board; stays put while `_number` or `_size` change for
## the next load. Empty once a challenge run has ended, so nothing is saved.
var _board_key := ""
var _mode := Mode.REGULAR
var _size := DEFAULT_SIZE
var _difficulty: int = DEFAULT_DIFFICULTY
var _number := 1
## Date ("YYYY-MM-DD") of the daily puzzle being played.
var _daily_date := ""
## Opened from the archive, so leaving the game returns there.
var _from_archive := false
## Counts towards streaks and the daily leaderboard: today's daily, or one
## started before the date rolled over.
var _daily_live := true
## Current challenge run: {"seed": int, "level": puzzle number, "elapsed": run time
## before this puzzle}. Empty when no run is going.
var _run := {}
var _elapsed := 0.0
var _running := false
## The timer only counts while the window has focus.
var _focused := true
var _generating := false
var _hinted := false
## Hint on show: {"message": String, "focus", "targets": cell indices, "changes":
## the [cell, old, new] batch Apply hint makes}. Empty when none is showing.
var _hint := {}
var _undo: Array = []
var _progress := ConfigFile.new()

var _theme := Theme.new()
var _background: ColorRect
var _panel_style := StyleBoxFlat.new()
var _menu: Menu
var _settings: Settings
var _stats: Stats
var _archive: Archive
var _play_games: PlayGames
var _sounds: Sounds
var _game: Control
var _back_button: Button
var _win_back_button: Button
var _size_picker: OptionButton
var _difficulty_picker: OptionButton
var _prev_button: Button
var _next_button: Button
var _puzzle_label: Label
var _timer_label: Label
var _best_label: Label
var _view: BoardView
var _undo_button: Button
var _hint_button: Button
var _hint_label: Label
var _win_overlay: Control
var _win_panel: PanelContainer
var _win_crown: CrownIcon
var _overlay_tween: Tween
var _win_heading: Label
var _win_label: Label
var _next_puzzle_button: Button
var _win_leaderboard_button: Button


func _ready() -> void:
	_progress.load(save_path)
	_size = _progress.get_value("last", "size", DEFAULT_SIZE)
	_number = _progress.get_value("last", "number", 1)
	_difficulty = _progress.get_value("last", "difficulty", DEFAULT_DIFFICULTY)
	_run = _progress.get_value(CHALLENGE_KEY, "run", {})
	# Every button, whenever it's made, clicks when pressed.
	get_tree().node_added.connect(_on_node_added)
	_build_ui()
	var dark: bool = _progress.get_value("settings", "dark_mode", false)
	_settings.dark_mode_toggle.set_pressed_no_signal(dark)
	_apply_dark_mode(dark)
	_view.auto_cross = _progress.get_value("settings", "auto_cross", false)
	_settings.auto_cross_toggle.set_pressed_no_signal(_view.auto_cross)
	_view.patterns = _progress.get_value("settings", "patterns", false)
	_settings.patterns_toggle.set_pressed_no_signal(_view.patterns)
	_sounds.enabled = _progress.get_value("settings", "sound", true)
	_settings.sound_toggle.set_pressed_no_signal(_sounds.enabled)
	_show_menu()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_board()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_focused = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_focused = true


func _process(delta: float) -> void:
	if _running and _focused:
		_elapsed += delta
		_timer_label.text = _format_time(_elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if (_settings.visible or _stats.visible or _archive.visible) and event.is_action_pressed("ui_cancel"):
		_show_menu()
		get_viewport().set_input_as_handled()
	if not _game.visible:
		return
	if event.is_action_pressed("ui_undo"):
		_on_undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_leave_game()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	theme = _theme
	_sounds = Sounds.new()
	add_child(_sounds)
	_background = ColorRect.new()
	_background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_background)

	_menu = Menu.new()
	_menu.set_anchors_preset(PRESET_FULL_RECT)
	_menu.continue_chosen.connect(_start.bind(Mode.REGULAR))
	_menu.daily_chosen.connect(_start.bind(Mode.DAILY))
	_menu.archive_chosen.connect(_show_archive)
	_menu.challenge_chosen.connect(_start.bind(Mode.CHALLENGE))
	_menu.stats_chosen.connect(_show_stats)
	_menu.leaderboards_chosen.connect(func() -> void: _play_games.show_all())
	_menu.settings_chosen.connect(_show_settings)
	_menu.exit_chosen.connect(_exit)
	add_child(_menu)

	_settings = Settings.new()
	_settings.set_anchors_preset(PRESET_FULL_RECT)
	_settings.visible = false
	_settings.dark_mode_toggled.connect(_on_dark_mode_toggled)
	_settings.auto_cross_toggled.connect(_on_auto_cross_toggled)
	_settings.patterns_toggled.connect(_on_patterns_toggled)
	_settings.sound_toggled.connect(_on_sound_toggled)
	_settings.back.connect(_show_menu)
	add_child(_settings)

	_stats = Stats.new()
	_stats.set_anchors_preset(PRESET_FULL_RECT)
	_stats.visible = false
	_stats.back.connect(_show_menu)
	add_child(_stats)

	_archive = Archive.new()
	_archive.set_anchors_preset(PRESET_FULL_RECT)
	_archive.visible = false
	_archive.status_for = _daily_status
	_archive.day_chosen.connect(func(date: String) -> void: _start(Mode.DAILY, date))
	_archive.back.connect(_show_menu)
	add_child(_archive)

	_play_games = PlayGames.new()
	add_child(_play_games)
	_menu.leaderboards_button.visible = _play_games.available()

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
	_back_button = _button("Menu", _leave_game)
	header.add_child(_back_button)
	var title := _label("Crowns", 34)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_size_picker = OptionButton.new()
	for s: int in SIZES:
		_size_picker.add_item("%d×%d" % [s, s], s)
	_size_picker.select(maxi(0, SIZES.find(_size)))
	_size_picker.item_selected.connect(_on_size_selected)
	header.add_child(_size_picker)
	_difficulty_picker = OptionButton.new()
	for name: String in Generator.DIFFICULTY_NAMES:
		_difficulty_picker.add_item(name)
	_difficulty_picker.select(_difficulty)
	_difficulty_picker.item_selected.connect(_on_difficulty_selected)
	header.add_child(_difficulty_picker)

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
	_view.marked.connect(_on_marked)
	column.add_child(_view)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_undo_button = _button("Undo", _on_undo)
	actions.add_child(_undo_button)
	actions.add_child(_button("Clear", _on_clear))
	_hint_button = _button("Hint", _on_hint)
	_hint_button.custom_minimum_size.x = 120
	actions.add_child(_hint_button)

	_hint_label = _label("", 16)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Room for two lines kept even when empty, so the board doesn't resize as hints come and go.
	_hint_label.custom_minimum_size.y = 46
	column.add_child(_hint_label)

	var help := _label("Place one crown in every row, column and colour region. Crowns may not touch, even diagonally.\n"
			+ "Tap: empty → × → crown.  Double tap: crown.  Drag from empty to cross out, from × to erase.  Right click: crown.  Ctrl+Z: undo.", 14)
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
	_win_panel = panel
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

	_win_crown = CrownIcon.new()
	_win_crown.custom_minimum_size = Vector2(0, 56)
	box.add_child(_win_crown)
	_win_heading = _label("Solved!", 32)
	_win_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_heading)
	_win_label = _label("", 18)
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	buttons.add_child(_button("Look at board", _hide_overlay))
	_win_back_button = _button("Menu", _leave_game)
	buttons.add_child(_win_back_button)
	_next_puzzle_button = _button("Next puzzle", _on_next_puzzle)
	buttons.add_child(_next_puzzle_button)
	_win_leaderboard_button = _button("Leaderboard", _show_mode_leaderboard)
	_win_leaderboard_button.visible = _play_games.available()
	buttons.add_child(_win_leaderboard_button)


## Fades the win (or run over) panel in after `delay` seconds, springing it up to size.
func _show_overlay(delay: float) -> void:
	_hide_overlay()
	_win_overlay.visible = true
	_win_overlay.modulate.a = 0.0
	_overlay_tween = create_tween()
	_overlay_tween.tween_interval(delay)
	_overlay_tween.tween_callback(func() -> void:
		_win_panel.pivot_offset = _win_panel.size / 2.0
		_win_panel.scale = Vector2(0.85, 0.85)
		_win_crown.hop())
	_overlay_tween.tween_property(_win_overlay, "modulate:a", 1.0, 0.2)
	_overlay_tween.parallel().tween_property(_win_panel, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_overlay() -> void:
	if _overlay_tween:
		_overlay_tween.kill()
	_win_overlay.visible = false
	_win_overlay.modulate.a = 1.0
	_win_panel.scale = Vector2.ONE


func _fade_in(screen: Control) -> void:
	screen.visible = true
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, FADE)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(_sounds.play.bind("click"))


## Sounds for each cell the player changes; auto crosses stay quiet.
func _on_marked(_cell: Vector2i, old_mark: int, new_mark: int) -> void:
	match new_mark:
		Board.Mark.CROWN:
			_sounds.play("crown")
		Board.Mark.CROSS:
			_sounds.play("cross")
		Board.Mark.EMPTY:
			if old_mark in [Board.Mark.CROSS, Board.Mark.CROWN]:
				_sounds.play("erase")


## One sound for a batch made outside the board, like an applied hint or Clear.
func _play_changes(changes: Array) -> void:
	if changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROWN):
		_sounds.play("crown")
	elif changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROSS):
		_sounds.play("cross")
	else:
		_sounds.play("erase")


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
	_stats.visible = false
	_archive.visible = false
	_fade_in(_menu)
	var started := _progress.has_section("last")
	var today := _today()
	var best: float = _progress.get_value("best", _daily_key(today), INF)
	var daily_detail := "%s · %d×%d · %s" % [_pretty_date(today), _daily_size(today), _daily_size(today),
			Generator.DIFFICULTY_NAMES[DAILY_DIFFICULTY]]
	if best != INF:
		daily_detail = "Solved in %s" % _format_time(best)
	elif _progress.get_value("solved", _daily_key(today), false):
		daily_detail = "Solved (hints used)"
	var streak := _current_streak()
	if streak > 0:
		daily_detail += " · %s streak" % _days(streak)
	var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
	var challenge_detail := "One life, no hints"
	if not _run.is_empty():
		challenge_detail = "Run in progress · Puzzle %d" % _run.level
	elif best_run > 0:
		challenge_detail = "Best run: %s" % _puzzles(best_run)
	_menu.set_details("Continue" if started else "Play",
			"%d×%d · %s · Puzzle #%d" % [_size, _size, Generator.DIFFICULTY_NAMES[_difficulty], _number],
			daily_detail, challenge_detail)


## Back to the archive for puzzles opened from it, otherwise to the menu.
func _leave_game() -> void:
	if _mode == Mode.DAILY and _from_archive:
		_show_archive()
	else:
		_show_menu()


func _show_archive() -> void:
	if _generating:
		return
	_save_board()
	_running = false
	_game.visible = false
	_menu.visible = false
	_archive.first_date = DAILY_FIRST
	_archive.last_date = _today()
	_archive.show_month_of(_daily_date if _game_is_archive_daily() else _today())
	_fade_in(_archive)


func _game_is_archive_daily() -> bool:
	return _board != null and _mode == Mode.DAILY and _from_archive


func _daily_status(date: String) -> Dictionary:
	var key := _daily_key(date)
	return {"solved": _progress.get_value("solved", key, false), "best": _progress.get_value("best", key, INF),
			"started": _progress.has_section_key("in_progress", key)}


func _exit() -> void:
	_save_board()
	get_tree().quit()


func _show_stats() -> void:
	var daily := [
		["Current streak", _days(_current_streak())],
		["Longest streak", _days(_progress.get_value(STATS, "longest_streak", 0))],
		["Dailies solved", _progress.get_value(STATS, "dailies_solved", 0)],
	]
	var sizes := []
	for size: int in SIZES:
		var timed: int = _progress.get_value(STATS, "timed_%d" % size, 0)
		var total: float = _progress.get_value(STATS, "time_%d" % size, 0.0)
		var best: float = _progress.get_value(STATS, "best_%d" % size, INF)
		sizes.append(["%d×%d" % [size, size], _progress.get_value(STATS, "solved_%d" % size, 0),
				_format_time(total / timed) if timed > 0 else "–", _format_time(best) if best != INF else "–"])
	var climb := [
		["Best run", _puzzles(_progress.get_value(CHALLENGE_KEY, "best", 0))],
		["Runs played", _progress.get_value(STATS, "climb_runs", 0)],
		["Puzzles cleared", _progress.get_value(STATS, "climb_solved", 0)],
	]
	_stats.set_stats(daily, sizes, climb)
	_menu.visible = false
	_fade_in(_stats)


## Counts a puzzle's first solve; only solves without hints count towards times.
func _record_solve(size: int, hinted: bool, seconds: float) -> void:
	_add_stat("solved_%d" % size, 1)
	if hinted:
		return
	_add_stat("timed_%d" % size, 1)
	_add_stat("time_%d" % size, seconds)
	if seconds < _progress.get_value(STATS, "best_%d" % size, INF):
		_progress.set_value(STATS, "best_%d" % size, seconds)


## Extends the streak when the previous solved daily was the day before.
func _record_daily(date: String) -> void:
	_add_stat("dailies_solved", 1)
	var last: String = _progress.get_value(STATS, "last_daily", "")
	var streak: int = _progress.get_value(STATS, "streak", 0)
	streak = streak + 1 if last == _day_before(date) else 1
	_progress.set_value(STATS, "streak", streak)
	_progress.set_value(STATS, "last_daily", date)
	if streak > _progress.get_value(STATS, "longest_streak", 0):
		_progress.set_value(STATS, "longest_streak", streak)


## The streak stays alive until a whole day passes without solving the daily.
func _current_streak() -> int:
	var last: String = _progress.get_value(STATS, "last_daily", "")
	var today := _today()
	if last != today and last != _day_before(today):
		return 0
	return _progress.get_value(STATS, "streak", 0)


func _add_stat(key: String, amount: Variant) -> void:
	_progress.set_value(STATS, key, _progress.get_value(STATS, key, 0) + amount)


func _day_before(date: String) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(date) - 86400)


func _show_settings() -> void:
	_menu.visible = false
	_fade_in(_settings)


func _on_dark_mode_toggled(enabled: bool) -> void:
	_apply_dark_mode(enabled)
	_progress.set_value("settings", "dark_mode", enabled)
	_progress.save(save_path)


func _on_auto_cross_toggled(enabled: bool) -> void:
	_view.auto_cross = enabled
	_progress.set_value("settings", "auto_cross", enabled)
	_progress.save(save_path)


func _on_sound_toggled(enabled: bool) -> void:
	_sounds.enabled = enabled
	_progress.set_value("settings", "sound", enabled)
	_progress.save(save_path)


func _on_patterns_toggled(enabled: bool) -> void:
	_view.patterns = enabled
	_progress.set_value("settings", "patterns", enabled)
	_progress.save(save_path)


func _apply_dark_mode(enabled: bool) -> void:
	var colors: Dictionary = DARK if enabled else LIGHT
	_background.color = colors.background
	_panel_style.bg_color = colors.panel
	_theme.set_color("font_color", "Label", colors.text)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_theme.set_color(state, "CheckButton", colors.text)
		_theme.set_color(state, "Button", Color.WHITE)
	_theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	# Rounded purple buttons; dropdowns pick these up too.
	var fills: Dictionary = BUTTON_DARK if enabled else BUTTON_LIGHT
	for state: String in fills:
		var box := StyleBoxFlat.new()
		box.bg_color = fills[state]
		box.set_corner_radius_all(10)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		_theme.set_stylebox(state, "Button", box)
		# Keep the toggle switch borderless; it would otherwise inherit the button fill.
		_theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# The size and difficulty dropdown lists.
	var menu_panel := StyleBoxFlat.new()
	menu_panel.bg_color = fills.pressed
	menu_panel.set_corner_radius_all(10)
	menu_panel.set_content_margin_all(6)
	_theme.set_stylebox("panel", "PopupMenu", menu_panel)
	var menu_hover := StyleBoxFlat.new()
	menu_hover.bg_color = fills.hover
	menu_hover.set_corner_radius_all(6)
	_theme.set_stylebox("hover", "PopupMenu", menu_hover)
	_theme.set_color("font_color", "PopupMenu", Color.WHITE)
	_theme.set_color("font_hover_color", "PopupMenu", GOLD)
	_view.dark = enabled


## `date` picks a past daily from the archive; otherwise the daily is today's.
func _start(mode: Mode, date := "") -> void:
	_mode = mode
	_from_archive = not date.is_empty()
	_back_button.text = "Back" if _from_archive else "Menu"
	_win_back_button.text = _back_button.text
	if mode == Mode.DAILY:
		_daily_date = date if _from_archive else _today()
		_daily_live = _daily_date == _today()
	elif mode == Mode.CHALLENGE and _run.is_empty():
		_new_run()
	_menu.visible = false
	_archive.visible = false
	_fade_in(_game)
	var regular := mode == Mode.REGULAR
	_size_picker.visible = regular
	_difficulty_picker.visible = regular
	_prev_button.visible = regular
	_next_button.visible = regular
	_hint_button.visible = mode != Mode.CHALLENGE
	_load_puzzle()


func _new_run() -> void:
	_run = {"seed": randi(), "level": 1, "elapsed": 0.0}
	_progress.set_value(CHALLENGE_KEY, "run", _run)
	_add_stat("climb_runs", 1)
	_progress.save(save_path)


func _load_puzzle() -> void:
	_save_board()
	_running = false
	_hide_overlay()
	# Past dailies aren't on the daily board, which only shows today's times.
	_win_leaderboard_button.visible = _play_games.available() and (_mode != Mode.DAILY or _daily_live)
	_view.interactive = false
	_generating = true
	_puzzle_label.text = "Generating…"
	# Let the label paint before the larger sizes block for a moment.
	await get_tree().process_frame
	await get_tree().process_frame

	var size := _size
	var difficulty := _difficulty
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_size, _difficulty, _number])
	if _mode == Mode.DAILY:
		size = _daily_size(_daily_date)
		difficulty = DAILY_DIFFICULTY
		rng.seed = hash(["daily", _daily_date])
	elif _mode == Mode.CHALLENGE:
		var stage: Array = _challenge_stage()
		size = stage[0]
		difficulty = stage[1]
		rng.seed = hash([_run.seed, _run.level])
	var puzzle := Generator.generate(size, difficulty, rng)
	_board = Board.new(size, puzzle.regions, puzzle.solution)
	_board_key = _puzzle_key()
	_hinted = false
	_elapsed = _run.elapsed if _mode == Mode.CHALLENGE else 0.0
	var saved: Dictionary = _progress.get_value("in_progress", _board_key, {})
	# Only restore onto the same layout, in case puzzle generation has changed since.
	if saved.get("regions", PackedInt32Array()) == _board.regions:
		_board.marks = saved.marks
		_elapsed = saved.elapsed
		_hinted = saved.hinted
	_view.board = _board
	_clear_hint()
	_view.interactive = true
	_generating = false
	_undo.clear()
	_undo_button.disabled = true
	_timer_label.text = _format_time(_elapsed)
	_running = true
	match _mode:
		Mode.REGULAR:
			_puzzle_label.text = "Puzzle #%d" % _number
		Mode.DAILY:
			_puzzle_label.text = "Daily · %s" % _pretty_date(_daily_date)
		Mode.CHALLENGE:
			_puzzle_label.text = "The Climb #%d · %s" % [_run.level, Generator.DIFFICULTY_NAMES[difficulty]]
	_update_best()

	if _mode == Mode.REGULAR:
		_progress.set_value("last", "size", _size)
		_progress.set_value("last", "number", _number)
		_progress.set_value("last", "difficulty", _difficulty)
		_progress.save(save_path)


func _challenge_stage() -> Array:
	return CHALLENGE_STAGES[mini(_run.level, CHALLENGE_STAGES.size()) - 1]


func _go_to(number: int) -> void:
	if number < 1 or _generating or _mode != Mode.REGULAR:
		return
	_number = number
	_load_puzzle()


func _on_next_puzzle() -> void:
	if _mode == Mode.REGULAR:
		_go_to(_number + 1)
		return
	if _mode == Mode.CHALLENGE and _run.is_empty():
		_new_run()
	_load_puzzle()


func _on_size_selected(index: int) -> void:
	if _generating:
		_size_picker.select(SIZES.find(_size))
		return
	_size = SIZES[index]
	_number = 1
	_load_puzzle()


func _on_difficulty_selected(index: int) -> void:
	if _generating:
		_difficulty_picker.select(_difficulty)
		return
	_difficulty = index
	_number = 1
	_load_puzzle()


func _on_board_edited(changes: Array) -> void:
	_clear_hint()
	_undo.append(changes)
	_undo_button.disabled = false
	if _mode == Mode.CHALLENGE:
		for change in changes:
			var cell: Vector2i = change[0]
			if change[2] == Board.Mark.CROWN and _board.solution[cell.x] != cell.y:
				_end_run(cell)
				return
	if changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROWN) and _board.conflicts().has(1):
		_sounds.play("conflict")
	_check_win()
	_save_board()


## Stores the loaded board's marks and timer, or forgets them once it is solved.
func _save_board() -> void:
	if _board == null or _board_key.is_empty():
		return
	if _board.is_solved():
		if _progress.has_section_key("in_progress", _board_key):
			_progress.erase_section_key("in_progress", _board_key)
	else:
		_progress.set_value("in_progress", _board_key,
				{"regions": _board.regions, "marks": _board.marks, "elapsed": _elapsed, "hinted": _hinted})
	_progress.save(save_path)


func _on_undo() -> void:
	if _undo.is_empty() or not _view.interactive:
		return
	_clear_hint()
	_sounds.play("erase")
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


## First press explains the next deduction; pressing again (Apply hint) carries it out.
func _on_hint() -> void:
	if not _view.interactive or _mode == Mode.CHALLENGE:
		return
	if not _hint.is_empty():
		_apply(_hint.changes.duplicate())
		return
	_hinted = true
	_sounds.play("hint")
	_hint = _find_hint()
	_hint_label.text = _hint.message
	_view.hint_focus = _hint.focus
	_view.hint_targets = _hint.targets
	_hint_button.text = "Apply hint"


func _clear_hint() -> void:
	_hint = {}
	_hint_label.text = ""
	_view.hint_focus = PackedInt32Array()
	_view.hint_targets = PackedInt32Array()
	_hint_button.text = "Hint"


## Points out a mistake if there is one, otherwise the easiest deduction left.
func _find_hint() -> Dictionary:
	var n := _board.size
	for cell in _board.crowns():
		if _board.solution[cell.x] != cell.y:
			return _make_hint("This crown isn't part of the solution.", [cell], [[cell, Board.Mark.CROWN, Board.Mark.EMPTY]])
	for row in n:
		var cell := Vector2i(row, _board.solution[row])
		if _board.is_cross(cell):
			return _make_hint("This cell is crossed out, but it needs a crown.", [cell],
					[[cell, _board.get_mark(cell), Board.Mark.EMPTY]])

	var step := Grader.next_step(n, _board.regions, _board.marks)
	if step.is_empty():
		for row in n:
			var cell := Vector2i(row, _board.solution[row])
			if _board.get_mark(cell) != Board.Mark.CROWN:
				return _make_hint("There's no simple deduction from here, so here's a crown.", [cell],
						[[cell, _board.get_mark(cell), Board.Mark.CROWN]])
	var changes := []
	var targets: Array[Vector2i] = []
	if step.crown >= 0:
		var cell := Vector2i(step.crown / n, step.crown % n)
		changes.append([cell, _board.get_mark(cell), Board.Mark.CROWN])
		targets.append(cell)
	for i: int in step.cross:
		var cell := Vector2i(i / n, i % n)
		changes.append([cell, _board.get_mark(cell), Board.Mark.CROSS])
		targets.append(cell)
	var hint := _make_hint(_explain(step), targets, changes)
	hint.focus = step.focus
	return hint


func _make_hint(message: String, targets: Array, changes: Array) -> Dictionary:
	var indices := PackedInt32Array()
	for cell: Vector2i in targets:
		indices.append(_board.index(cell))
	return {"message": message, "focus": indices, "targets": indices, "changes": changes}


func _explain(step: Dictionary) -> String:
	var from: Array = step.from
	match step.rule:
		"single":
			return "%s has only one cell left that can hold its crown." % _upper_first(_group_name(from[0]))
		"blocker":
			var cell: int = step.cross[0]
			return "A crown in row %d, column %d would rule out every open cell left in %s, so cross it out." \
					% [cell / _board.size + 1, cell % _board.size + 1, _group_name(from[0])]
	var to: Array = step.to
	if from.size() == 1:
		var a := _group_name(from[0])
		var b := _group_name(to[0])
		return "%s's open cells all lie in %s, so %s's crown must come from %s. Cross out the rest of %s." \
				% [_upper_first(a), b, b, a, b]
	var a := _group_names(from)
	var b := _group_names(to)
	return "%s only have open cells in %s, so their %d crowns fill %s. Cross out everything else in %s." \
			% [_upper_first(a), b, from.size(), b, b]


func _upper_first(text: String) -> String:
	return text[0].to_upper() + text.substr(1)


func _group_name(group: int) -> String:
	var index := Grader.group_index(_board.size, group)
	match Grader.group_kind(_board.size, group):
		Grader.Kind.ROW:
			return "row %d" % (index + 1)
		Grader.Kind.COLUMN:
			return "column %d" % (index + 1)
	return "the %s region" % BoardView.REGION_NAMES[index % BoardView.REGION_NAMES.size()]


## "rows 2 and 3", "the purple, blue and green regions".
func _group_names(groups: Array) -> String:
	var parts: Array[String] = []
	for group: int in groups:
		var index := Grader.group_index(_board.size, group)
		if Grader.group_kind(_board.size, group) == Grader.Kind.REGION:
			parts.append(BoardView.REGION_NAMES[index % BoardView.REGION_NAMES.size()])
		else:
			parts.append(str(index + 1))
	var listed := ", ".join(parts.slice(0, -1)) + " and " + parts[-1]
	match Grader.group_kind(_board.size, groups[0]):
		Grader.Kind.ROW:
			return "rows " + listed
		Grader.Kind.COLUMN:
			return "columns " + listed
	return "the %s regions" % listed


## Applies an undoable batch of [cell, old, new] changes made outside the board view.
func _apply(changes: Array) -> void:
	_play_changes(changes)
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
	_view.celebrate()
	_sounds.play("win")
	_win_crown.visible = true
	_win_heading.text = "Solved!"
	_next_puzzle_button.visible = _mode != Mode.DAILY
	_next_puzzle_button.text = "Next puzzle"
	if _mode == Mode.CHALLENGE:
		var solved: int = _run.level
		var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
		if solved > best_run:
			_progress.set_value(CHALLENGE_KEY, "best", solved)
		_run.level += 1
		_run.elapsed = _elapsed
		_progress.set_value(CHALLENGE_KEY, "run", _run)
		_add_stat("climb_solved", 1)
		_play_games.submit_climb(solved)
		_progress.save(save_path)
		_win_label.text = "%s solved · %s" % [_puzzles(solved), _format_time(_elapsed)]
		_update_best()
		_show_win_overlay()
		return
	var key := _puzzle_key()
	var best: float = _progress.get_value("best", key, INF)
	# Hinted solves don't count towards best times.
	var record := not _hinted and _elapsed < best
	if record:
		_progress.set_value("best", key, _elapsed)
	if not _progress.get_value("solved", key, false):
		_record_solve(_board.size, _hinted, _elapsed)
		# Archive dailies count as solves, but not towards streaks or the daily board.
		if _mode == Mode.DAILY:
			if _daily_live:
				_record_daily(_daily_date)
		elif not _hinted:
			_add_stat("puzzles_unhinted", 1)
			_play_games.submit_solved(_progress.get_value(STATS, "puzzles_unhinted", 0))
	if _mode == Mode.DAILY and _daily_live and not _hinted:
		_play_games.submit_daily_time(_elapsed)
	_progress.set_value("solved", key, true)
	_progress.save(save_path)
	var note := "  (hints used)" if _hinted else "  (new best!)" if record and best != INF else ""
	_win_label.text = "Time: %s%s" % [_format_time(_elapsed), note]
	_update_best()
	_show_win_overlay()


## The panel waits for most of the crowns' victory wave first.
func _show_win_overlay() -> void:
	_show_overlay(_view.celebration_ms() / 1000.0 * 0.7)


## A wrong crown ends the challenge run.
func _end_run(mistake: Vector2i) -> void:
	_running = false
	_view.interactive = false
	_view.mistake = mistake
	var solved: int = _run.level - 1
	var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
	_run = {}
	_board_key = ""
	_progress.erase_section_key(CHALLENGE_KEY, "run")
	if _progress.has_section_key("in_progress", CHALLENGE_KEY):
		_progress.erase_section_key("in_progress", CHALLENGE_KEY)
	_progress.save(save_path)
	_sounds.play("fail")
	_win_crown.visible = false
	_win_heading.text = "Out of lives"
	var note := "  (best run!)" if solved > 0 and solved >= best_run else ""
	_win_label.text = "That crown doesn't belong there.\n%s solved · %s%s" % [_puzzles(solved), _format_time(_elapsed), note]
	_next_puzzle_button.visible = true
	_next_puzzle_button.text = "New run"
	_update_best()
	_show_overlay(0.4)


## Opens the Play Games board for the mode just played.
func _show_mode_leaderboard() -> void:
	match _mode:
		Mode.DAILY:
			_play_games.show_daily()
		Mode.CHALLENGE:
			_play_games.show_climb()
		_:
			_play_games.show_solved()


func _update_best() -> void:
	if _mode == Mode.CHALLENGE:
		var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
		_best_label.text = "" if best_run == 0 else "Best run %d" % best_run
		return
	var best: float = _progress.get_value("best", _puzzle_key(), INF)
	_best_label.text = "" if best == INF else "Best %s" % _format_time(best)


func _puzzle_key() -> String:
	match _mode:
		Mode.DAILY:
			return _daily_key(_daily_date)
		Mode.CHALLENGE:
			return CHALLENGE_KEY
	return "%dx%d_%s_%d" % [_size, _size, Generator.DIFFICULTY_NAMES[_difficulty].to_lower(), _number]


func _daily_key(date: String) -> String:
	return "daily_" + date


func _daily_size(date: String) -> int:
	return DAILY_SIZES[posmod(hash(["daily_size", date]), DAILY_SIZES.size())]


## The daily puzzle's date. It changes at midnight UTC−7 for everyone, the
## moment Google Play Games resets its daily leaderboards.
func _today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + DAILY_UTC_OFFSET)


## "2026-10-23" -> "Oct 23".
func _pretty_date(date: String) -> String:
	var parts := date.split("-")
	return "%s %d" % [MONTHS[parts[1].to_int() - 1], parts[2].to_int()]


func _puzzles(count: int) -> String:
	return "%d puzzle%s" % [count, "" if count == 1 else "s"]


func _days(count: int) -> String:
	return "%d day%s" % [count, "" if count == 1 else "s"]


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
