extends Control
## Menu plus game screen: puzzle picker, timer, board, undo/clear/hint and the win overlay.

const Board := preload("res://scripts/board.gd")
const BoardView := preload("res://scripts/board_view.gd")
const Generator := preload("res://scripts/generator.gd")
const Solver := preload("res://scripts/solver.gd")
const Grader := preload("res://scripts/grader.gd")
const Menu := preload("res://scripts/menu.gd")
const Settings := preload("res://scripts/settings.gd")
const Stats := preload("res://scripts/stats.gd")
const Archive := preload("res://scripts/archive.gd")
const PlayGames := preload("res://scripts/play_games.gd")
const Sounds := preload("res://scripts/sounds.gd")
const Haptics := preload("res://scripts/haptics.gd")
const CrownIcon := preload("res://scripts/crown_icon.gd")
const Language := preload("res://scripts/language.gd")
const Reminder := preload("res://scripts/reminder.gd")
const CloudSave := preload("res://scripts/cloud_save.gd")
const PuzzleCode := preload("res://scripts/puzzle_code.gd")
const PuzzlePack := preload("res://scripts/puzzle_pack.gd")
const SilentWolf := preload("res://scripts/silent_wolf.gd")
const Leaderboards := preload("res://scripts/leaderboards.gd")
## Symbols the default font lacks (→, ✓). Desktops and phones borrow them from
## system fonts, but browsers can't, so the web build needs them bundled.
const SYMBOLS := preload("res://fonts/DejaVuSans-symbols.ttf")
## Arabic and Hebrew, for the same reason: the web build can't borrow system fonts.
const SCRIPTS: Array[Font] = [preload("res://fonts/NotoSansArabic-Regular.ttf"),
		preload("res://fonts/NotoSansHebrew-Regular.ttf")]

const LIGHT := {"background": Color("f4f1ea"), "text": Color("1e1e1e"), "panel": Color("fffdf8")}
const DARK := {"background": Color("1c1c1e"), "text": Color("ebe8e1"), "panel": Color("2c2c2f")}
## Button fills, matching the purple of the app icon; deeper in dark mode.
const BUTTON_LIGHT := {"normal": Color("5b4a9e"), "hover": Color("6b59b3"), "pressed": Color("483a85"),
		"hover_pressed": Color("483a85"), "disabled": Color("5b4a9e", 0.45)}
const BUTTON_DARK := {"normal": Color("46397f"), "hover": Color("554794"), "pressed": Color("372c66"),
		"hover_pressed": Color("372c66"), "disabled": Color("46397f", 0.45)}
const GOLD := Color("f4c542")
## Toggle switch tracks when off; when on they take the button purple.
const SWITCH_OFF_LIGHT := Color("bdb6a8")
const SWITCH_OFF_DARK := Color("55545b")
## Screens fade in over this many seconds.
const FADE := 0.15

enum Mode { REGULAR, DAILY, CHALLENGE, WEEKLY, TUTORIAL, SPEED }

## Sizes generated on the spot; larger ones come from pre-made packs (PuzzlePack).
const SIZES := [5, 6, 7, 8, 9, 10]
const DEFAULT_SIZE := 7
const DAILY_SIZES := [7, 8, 9]
const DEFAULT_DIFFICULTY := Generator.Difficulty.MEDIUM
const DAILY_DIFFICULTY := Generator.Difficulty.MEDIUM
const DAILY_UTC_OFFSET := -7 * 3600
## The first daily puzzle in the archive.
const DAILY_FIRST := "2026-10-01"
## The weekly challenge: one large, hard puzzle for everyone each week.
const WEEKLY_SIZE := 10
const WEEKLY_DIFFICULTY := Generator.Difficulty.HARD
## [size, difficulty] for each challenge puzzle; the last one repeats.
const CHALLENGE_STAGES := [
	[5, Generator.Difficulty.EASY], [5, Generator.Difficulty.EASY], [6, Generator.Difficulty.EASY],
	[6, Generator.Difficulty.MEDIUM], [6, Generator.Difficulty.MEDIUM], [7, Generator.Difficulty.MEDIUM],
	[7, Generator.Difficulty.MEDIUM], [7, Generator.Difficulty.HARD], [8, Generator.Difficulty.MEDIUM],
	[8, Generator.Difficulty.HARD], [8, Generator.Difficulty.HARD], [9, Generator.Difficulty.MEDIUM],
	[9, Generator.Difficulty.HARD], [9, Generator.Difficulty.HARD], [10, Generator.Difficulty.HARD],
]
const CHALLENGE_KEY := "challenge"
## [size, difficulty] for each board of a speed run, played on one clock.
const SPEED_STAGES := [
	[5, Generator.Difficulty.EASY], [5, Generator.Difficulty.EASY], [6, Generator.Difficulty.EASY],
	[6, Generator.Difficulty.MEDIUM], [7, Generator.Difficulty.MEDIUM],
]
const SPEED_KEY := "speed"
## Seconds between a speed run's boards, with the clock stopped: long enough
## for the victory wave on the largest board.
const SPEED_PAUSE := 0.9
## The tutorial's lessons: puzzles as a letter per region, row by row, and the
## technique each teaches. The first, a 5×5 that opens on a one-cell region,
## solves with "only one cell left" steps alone. The others start part-solved,
## just before their technique is first needed (see _lesson_marks), and finish
## with simple steps.
const LESSONS := [
	{"layout": ["EEBBB", "EEDDB", "EEDDA", "ECDDD", "EEDDD"], "technique": ""},
	{"layout": ["FFFFFF", "CFFFFF", "CEEEDD", "CCEEDD", "CEEEDB", "AAEEBB"], "technique": "confined"},
	{"layout": ["DDDCCCC", "DDFCCCC", "DBFFFCC", "BBFFFCC", "EBBGFFF", "EBBGFFA", "EGGGFFF"], "technique": "group"},
	{"layout": ["EBBBBB", "EEFFBB", "AABBBB", "AACCCB", "AACCCB", "AADCCC"], "technique": "blocker"},
]
## Hours the daily reminder can be set to, in local time.
const REMINDER_HOURS := [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22]
const DEFAULT_REMINDER_HOUR := 19
## Save section for streaks and per-size totals.
const STATS := "stats"
## The player's SilentWolf identity ("player_id", "player_name") and scores not yet sent.
const ONLINE := "online"

## Where progress and best times are stored; tests point this elsewhere.
var save_path := "user://queens_progress.cfg"
## Opens on Settings instead of the menu, for the rebuild after a language change.
var open_settings := false
## Starts the tutorial when there's no save yet, i.e. on a first launch.
var first_run_tutorial := true

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
## First day ("YYYY-MM-DD", a Sunday) of the weekly challenge being played.
var _week := ""
## Current challenge run: {"seed": int, "level": puzzle number, "elapsed": run time
## before this puzzle}. Empty when no run is going.
var _run := {}
## Current speed run, like `_run` but never saved: leaving abandons it. Its
## "level" goes past SPEED_STAGES once the run is finished.
var _speed_run := {}
var _elapsed := 0.0
var _running := false
## The timer only counts while the window has focus.
var _focused := true
var _generating := false
## Every size on offer: SIZES, then the larger ones that have packs.
var _sizes: Array[int] = []
## Puzzles generate on a worker thread where there are threads (not the web build).
var _threads := OS.has_feature("threads")
## The puzzle most likely to be played next, generating in the background while
## this one is played: {"spec": _puzzle_spec() of it, "task": WorkerThreadPool
## task, "result": the puzzle once the task is done}. Empty when there's none.
var _prefetch := {}
## Worker tasks not yet waited on, which WorkerThreadPool needs for each one.
var _tasks := {}
var _hinted := false
## Hint on show: {"message": String, "focus", "targets": cell indices, "changes":
## the [cell, old, new] batch Apply hint makes}. Empty when none is showing.
var _hint := {}
var _undo: Array = []
## The tutorial's intro card on show; past the last card, the guided solve.
var _tutorial_card := 0
## The tutorial lesson being played, an index into LESSONS.
var _lesson := 0
var _progress := ConfigFile.new()

var _theme := Theme.new()
var _background: ColorRect
var _panel_style := StyleBoxFlat.new()
var _menu: Menu
var _settings: Settings
var _stats: Stats
var _archive: Archive
var _play_games: PlayGames
var _reminder: Reminder
## Desktop and web leaderboards; Android uses Play Games instead.
var _silent_wolf: SilentWolf
var _leaderboards: Leaderboards
## Whether the leaderboards were opened from a solved puzzle, so Back returns there.
var _leaderboards_from_game := false
## Set once the cloud save has been fetched and merged; uploads wait for it, so
## a fresh install never overwrites progress saved from another device.
var _cloud_ready := false
var _sounds: Sounds
var _haptics: Haptics
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
var _clear_button: Button
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
## Start playing, offered beside Next lesson once the tutorial's basics are done.
var _win_play_button: Button
var _code_button: Button
## The puzzle code panel: this puzzle's code to share, and a box to enter a friend's.
var _code_overlay: Control
var _code_label: Label
var _code_copy_button: Button
var _code_entry: LineEdit
var _code_error: Label
## Whether the timer was running when the code panel opened, to resume it on close.
var _code_paused := false


func _ready() -> void:
	var first_launch := not FileAccess.file_exists(save_path)
	_progress.load(save_path)
	var font := ThemeDB.fallback_font
	for fallback: Font in [SYMBOLS] + SCRIPTS:
		if fallback not in font.fallbacks:
			font.fallbacks.append(fallback)
	_size = _progress.get_value("last", "size", DEFAULT_SIZE)
	_number = _progress.get_value("last", "number", 1)
	_difficulty = _progress.get_value("last", "difficulty", DEFAULT_DIFFICULTY)
	_run = _progress.get_value(CHALLENGE_KEY, "run", {})
	Language.apply(_progress.get_value("settings", "language", ""))
	# Text is translated with tr() as it's set, so Godot mustn't translate it again.
	auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
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
	_haptics.enabled = _progress.get_value("settings", "vibration", true)
	_settings.vibration_toggle.visible = _haptics.available()
	_settings.vibration_toggle.set_pressed_no_signal(_haptics.enabled)
	var names := {}
	for locale in Language.locales():
		names[locale] = Language.native_name(locale)
		# Translations show how far along they are, e.g. "Esperanto (69%)".
		if locale != Language.SOURCE:
			names[locale] += " (%d%%)" % floori(Language.completion(locale) * 100.0)
	_settings.set_languages(names, _progress.get_value("settings", "language", ""))
	_settings.set_reminder(_reminder.available(), _progress.get_value("settings", "reminder", false), REMINDER_HOURS,
			_progress.get_value("settings", "reminder_hour", DEFAULT_REMINDER_HOUR))
	# Again on every start: this refreshes the text's language and the alarm after an update.
	_update_reminder()
	_show_menu()
	if open_settings:
		_show_settings()
	elif first_launch and first_run_tutorial:
		_start_lesson(0)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_board()
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_upload_progress()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_focused = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_focused = true


func _exit_tree() -> void:
	for task: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()


func _process(delta: float) -> void:
	# Tidy up background puzzles that finished after nothing wanted them.
	for task: int in _tasks.keys():
		if _tasks[task] == false and WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(task)
	if _running and _focused:
		_elapsed += delta
		_timer_label.text = _format_time(_elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if (_settings.visible or _stats.visible or _archive.visible) and event.is_action_pressed("ui_cancel"):
		_show_menu()
		get_viewport().set_input_as_handled()
	if _leaderboards.visible and event.is_action_pressed("ui_cancel"):
		_close_leaderboards()
		get_viewport().set_input_as_handled()
		return
	if not _game.visible:
		return
	if event.is_action_pressed("ui_undo") and not _code_overlay.visible:
		_on_undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _code_overlay.visible:
		_hide_code()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_leave_game()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	theme = _theme
	_sounds = Sounds.new()
	add_child(_sounds)
	_haptics = Haptics.new()
	add_child(_haptics)
	_background = ColorRect.new()
	_background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_background)

	_menu = Menu.new()
	_menu.set_anchors_preset(PRESET_FULL_RECT)
	_menu.continue_chosen.connect(_start.bind(Mode.REGULAR))
	_menu.daily_chosen.connect(_start.bind(Mode.DAILY))
	_menu.archive_chosen.connect(_show_archive)
	_menu.weekly_chosen.connect(_start.bind(Mode.WEEKLY))
	_menu.challenge_chosen.connect(_start.bind(Mode.CHALLENGE))
	_menu.speed_chosen.connect(_start.bind(Mode.SPEED))
	_menu.stats_chosen.connect(_show_stats)
	_menu.leaderboards_chosen.connect(_show_leaderboards.bind("daily"))
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
	_settings.vibration_toggled.connect(_on_vibration_toggled)
	_settings.reminder_toggled.connect(_on_reminder_toggled)
	_settings.reminder_hour_chosen.connect(_on_reminder_hour_chosen)
	_settings.test_reminder.connect(_on_test_reminder)
	_settings.language_chosen.connect(_on_language_chosen)
	_settings.how_to_play.connect(_start_lesson.bind(0))
	_settings.back.connect(_show_menu)
	add_child(_settings)

	_stats = Stats.new()
	_stats.set_anchors_preset(PRESET_FULL_RECT)
	_stats.visible = false
	_stats.back.connect(_show_menu)
	_stats.achievements_chosen.connect(func() -> void: _play_games.show_achievements())
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
	_reminder = Reminder.new()
	add_child(_reminder)
	_reminder.permission_answered.connect(_on_reminder_permission)
	_silent_wolf = SilentWolf.new()
	add_child(_silent_wolf)
	_silent_wolf.pending = _progress.get_value(ONLINE, "pending", [])
	_silent_wolf.pending_changed.connect(func(pending: Array) -> void:
		_progress.set_value(ONLINE, "pending", pending)
		_progress.save(save_path))
	_leaderboards = Leaderboards.new()
	_leaderboards.set_anchors_preset(PRESET_FULL_RECT)
	_leaderboards.visible = false
	_leaderboards.client = _silent_wolf
	_leaderboards.back.connect(_close_leaderboards)
	_leaderboards.name_changed.connect(func(player_name: String) -> void:
		_progress.set_value(ONLINE, "player_name", player_name)
		_progress.save(save_path))
	add_child(_leaderboards)
	_settings.silent_wolf_toggle.visible = _silent_wolf.available()
	_settings.silent_wolf_toggle.set_pressed_no_signal(_progress.get_value("settings", "silent_wolf", true))
	_settings.silent_wolf_toggled.connect(_on_silent_wolf_toggled)
	_settings.timer_toggle.set_pressed_no_signal(_progress.get_value("settings", "show_timer", true))
	_settings.timer_toggled.connect(_on_timer_toggled)
	if _silent_wolf_on():
		# Scores that couldn't be sent last time, e.g. while offline.
		_silent_wolf.retry()
	_menu.leaderboards_button.visible = _has_leaderboards()
	_stats.achievements_button.visible = _play_games.available()
	_play_games.signed_in.connect(_on_signed_in)
	_play_games.cloud_loaded.connect(_on_cloud_loaded)

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
	_back_button = _button(tr("Menu"), _leave_game)
	header.add_child(_back_button)
	var title := _label("Crowns", 34)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_sizes.assign(SIZES)
	for size in PuzzlePack.sizes():
		if size not in _sizes:
			_sizes.append(size)
	_size_picker = OptionButton.new()
	for s: int in _sizes:
		_size_picker.add_item("%d×%d" % [s, s], s)
	_size_picker.select(maxi(0, _sizes.find(_size)))
	_size_picker.item_selected.connect(_on_size_selected)
	header.add_child(_size_picker)
	_difficulty_picker = OptionButton.new()
	for difficulty in Generator.DIFFICULTY_NAMES.size():
		_difficulty_picker.add_item(_difficulty_name(difficulty))
	_difficulty_picker.select(_difficulty)
	_difficulty_picker.item_selected.connect(_on_difficulty_selected)
	header.add_child(_difficulty_picker)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	column.add_child(nav)
	_prev_button = _button(tr("Prev"), func() -> void: _go_to(_number - 1))
	nav.add_child(_prev_button)
	_puzzle_label = _label("", 20)
	_puzzle_label.custom_minimum_size.x = 120
	_puzzle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_puzzle_label)
	_next_button = _button(tr("Next"), func() -> void: _go_to(_number + 1))
	nav.add_child(_next_button)
	# TRANSLATORS: Opens the puzzle code panel, to share this puzzle or enter a friend's.
	_code_button = _button(tr("Code"), _show_code)
	nav.add_child(_code_button)
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
	_undo_button = _button(tr("Undo"), _on_undo)
	actions.add_child(_undo_button)
	_clear_button = _button(tr("Clear"), _on_clear)
	actions.add_child(_clear_button)
	_hint_button = _button(tr("Hint"), _on_hint)
	_hint_button.custom_minimum_size.x = 120
	actions.add_child(_hint_button)

	_hint_label = _label("", 16)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Room for two lines kept even when empty, so the board doesn't resize as hints come and go.
	_hint_label.custom_minimum_size.y = 46
	column.add_child(_hint_label)

	var help := _label(tr("Place one crown in every row, column and colour region. Crowns may not touch, even diagonally.")
			+ "\n" + tr("Tap: × or clear.  Double tap: crown.  Drag from empty to cross out, from × to erase.  Right click: crown.  Ctrl+Z: undo."), 14)
	help.modulate = Color(1, 1, 1, 0.65)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)

	_build_win_overlay()
	_build_code_overlay()


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
	_win_heading = _label(tr("Solved!"), 32)
	_win_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_heading)
	_win_label = _label("", 18)
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_win_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	buttons.add_child(_button(tr("Look at board"), _hide_overlay))
	_win_back_button = _button(tr("Menu"), _leave_game)
	buttons.add_child(_win_back_button)
	_next_puzzle_button = _button(tr("Next puzzle"), _on_next_puzzle)
	buttons.add_child(_next_puzzle_button)
	_win_play_button = _button(tr("Start playing"), _start.bind(Mode.REGULAR))
	_win_play_button.visible = false
	buttons.add_child(_win_play_button)
	_win_leaderboard_button = _button(tr("Leaderboard"), _show_mode_leaderboard)
	_win_leaderboard_button.visible = _has_leaderboards()
	buttons.add_child(_win_leaderboard_button)


func _build_code_overlay() -> void:
	_code_overlay = ColorRect.new()
	(_code_overlay as ColorRect).color = Color(0, 0, 0, 0.45)
	_code_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_code_overlay.visible = false
	_game.add_child(_code_overlay)

	# Kept near the top so the on-screen keyboard doesn't cover the entry box.
	var top := MarginContainer.new()
	top.set_anchors_preset(PRESET_FULL_RECT)
	top.add_theme_constant_override("margin_top", 110)
	_code_overlay.add_child(top)
	var center := CenterContainer.new()
	center.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style)
	center.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 380
	inner.add_child(box)

	var heading := _label(tr("Puzzle code"), 28)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	_code_label = _label("", 40)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_code_label)
	var note := _label(tr("Share it so friends can play this same board."), 16)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	_code_copy_button = _button(tr("Copy code"), _copy_code)
	_code_copy_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	box.add_child(_code_copy_button)

	box.add_child(HSeparator.new())
	var enter := _label(tr("Got a code from a friend?"), 18)
	enter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(enter)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_code_entry = LineEdit.new()
	# TRANSLATORS: Placeholder in the box for entering a puzzle code; keep the code itself as is.
	_code_entry.placeholder_text = tr("e.g. %s") % PuzzleCode.encode(8, 1, 142)
	_code_entry.size_flags_horizontal = SIZE_EXPAND_FILL
	_code_entry.custom_minimum_size.y = 40
	_code_entry.add_theme_font_size_override("font_size", 20)
	_code_entry.text_submitted.connect(func(_text: String) -> void: _enter_code())
	_code_entry.text_changed.connect(func(_text: String) -> void: _code_error.visible = false)
	row.add_child(_code_entry)
	row.add_child(_button(tr("Play"), _enter_code))
	_code_error = _label(tr("That isn't a puzzle code."), 16)
	_code_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_error.add_theme_color_override("font_color", BoardView.CONFLICT_COLOR)
	_code_error.visible = false
	box.add_child(_code_error)

	var close := _button(tr("Close"), _hide_code)
	close.size_flags_horizontal = SIZE_SHRINK_CENTER
	box.add_child(close)


func _show_code() -> void:
	if _generating or _mode != Mode.REGULAR:
		return
	_code_label.text = PuzzleCode.encode(_size, _difficulty, _number)
	_code_copy_button.text = tr("Copy code")
	_code_entry.text = ""
	_code_error.visible = false
	_code_paused = _running
	_running = false
	_code_overlay.visible = true


func _hide_code() -> void:
	if not _code_overlay.visible:
		return
	_code_overlay.visible = false
	_code_entry.release_focus()
	if _code_paused:
		_running = true
		_code_paused = false


func _copy_code() -> void:
	# TRANSLATORS: Copied to share a puzzle; %s is its code, e.g. 8H-142. Keep the code as is.
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(tr("Try this Crowns puzzle: %s") % _code_label.text)
	_code_copy_button.text = tr("Copied!")


func _enter_code() -> void:
	var code := PuzzleCode.decode(_code_entry.text, _sizes)
	if code.is_empty():
		_code_error.visible = true
		return
	_code_paused = false
	_hide_code()
	_size = code["size"]
	_difficulty = code["difficulty"]
	_number = code["number"]
	_size_picker.select(_sizes.find(_size))
	_difficulty_picker.select(_difficulty)
	_load_puzzle()


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


## Sounds and vibration for each cell the player changes; auto crosses stay quiet.
func _on_marked(_cell: Vector2i, old_mark: int, new_mark: int) -> void:
	match new_mark:
		Board.Mark.CROWN:
			_sounds.play("crown")
			_haptics.crown()
		Board.Mark.CROSS:
			_sounds.play("cross")
			_haptics.cross()
		Board.Mark.EMPTY:
			if old_mark in [Board.Mark.CROSS, Board.Mark.CROWN]:
				_sounds.play("erase")


## One sound for a batch made outside the board, like an applied hint or Clear.
func _play_changes(changes: Array) -> void:
	if changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROWN):
		_sounds.play("crown")
		_haptics.crown()
	elif changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROSS):
		_sounds.play("cross")
		_haptics.cross()
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
	_leaderboards.visible = false
	_fade_in(_menu)
	var started := _progress.has_section("last")
	var today := _today()
	var best: float = _progress.get_value("best", _daily_key(today), INF)
	var daily_detail := "%s · %d×%d · %s" % [_pretty_date(today), _daily_size(today), _daily_size(today),
			_difficulty_name(DAILY_DIFFICULTY)]
	if best != INF:
		daily_detail = tr("Solved in %s") % _format_time(best)
	elif _progress.get_value("solved", _daily_key(today), false):
		daily_detail = tr("Solved (hints used)")
	var streak := _current_streak()
	if streak > 0:
		daily_detail += " · " + tr_n("%d day streak", "%d days streak", streak) % streak
	var week := _week_start()
	var days_left := 7 - _weekday()
	var weekly_best: float = _progress.get_value("best", _weekly_key(week), INF)
	# TRANSLATORS: %s is a short date, the Sunday the weekly challenge starts, e.g. "Oct 25".
	var weekly_detail := "%s · %d×%d · %s" % [tr("Week of %s") % _pretty_date(week), WEEKLY_SIZE, WEEKLY_SIZE,
			_difficulty_name(WEEKLY_DIFFICULTY)]
	if weekly_best != INF:
		weekly_detail = tr("Solved in %s") % _format_time(weekly_best)
	elif _progress.get_value("solved", _weekly_key(week), false):
		weekly_detail = tr("Solved (hints used)")
	weekly_detail += " · " + tr_n("%d day left", "%d days left", days_left) % days_left
	var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
	var challenge_detail := tr("One life, no hints")
	if not _run.is_empty():
		challenge_detail = tr("Run in progress · Puzzle %d") % _run.level
	elif best_run > 0:
		challenge_detail = tr("Best run: %s") % _puzzles(best_run)
	var speed_best: float = _progress.get_value(SPEED_KEY, "best", INF)
	var boards := SPEED_STAGES.size()
	var speed_detail := tr_n("%d board, one clock", "%d boards, one clock", boards) % boards if speed_best == INF \
			else tr("Best: %s") % _format_time(speed_best)
	_menu.set_details(tr("Continue") if started else tr("Play"),
			"%d×%d · %s · %s" % [_size, _size, _difficulty_name(_difficulty), tr("Puzzle #%d") % _number],
			daily_detail, weekly_detail, challenge_detail, speed_detail)


## Back to the archive for puzzles opened from it, otherwise to the menu.
func _leave_game() -> void:
	if _mode == Mode.TUTORIAL:
		_set_tutorial_done()
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


## Finished months with every daily solved, as the archive's trophies show them.
func _perfect_months() -> int:
	var today := _today()
	var year := DAILY_FIRST.substr(0, 4).to_int()
	var month := DAILY_FIRST.substr(5, 2).to_int()
	var count := 0
	while "%04d-%02d-01" % [year, month] <= today:
		if Archive.month_complete(year, month, DAILY_FIRST, today, _daily_status):
			count += 1
		month += 1
		if month > 12:
			month = 1
			year += 1
	return count


func _daily_status(date: String) -> Dictionary:
	var key := _daily_key(date)
	return {"solved": _progress.get_value("solved", key, false), "best": _progress.get_value("best", key, INF),
			"started": _progress.has_section_key("in_progress", key)}


func _exit() -> void:
	_save_board()
	get_tree().quit()


func _show_stats() -> void:
	var daily := [
		[tr("Current streak"), _days(_current_streak())],
		[tr("Longest streak"), _days(_progress.get_value(STATS, "longest_streak", 0))],
		[tr("Dailies solved"), _progress.get_value(STATS, "dailies_solved", 0)],
		# TRANSLATORS: Months with every daily puzzle solved.
		[tr("Perfect months"), _perfect_months()],
		[tr("Weeklies solved"), _progress.get_value(STATS, "weeklies_solved", 0)],
	]
	var sizes := []
	for size: int in _sizes:
		var timed: int = _progress.get_value(STATS, "timed_%d" % size, 0)
		var total: float = _progress.get_value(STATS, "time_%d" % size, 0.0)
		var best: float = _progress.get_value(STATS, "best_%d" % size, INF)
		sizes.append(["%d×%d" % [size, size], _progress.get_value(STATS, "solved_%d" % size, 0),
				_format_time(total / timed) if timed > 0 else "–", _format_time(best) if best != INF else "–"])
	var climb := [
		[tr("Best run"), _puzzles(_progress.get_value(CHALLENGE_KEY, "best", 0))],
		[tr("Runs played"), _progress.get_value(STATS, "climb_runs", 0)],
		[tr("Puzzles cleared"), _progress.get_value(STATS, "climb_solved", 0)],
	]
	var speed_best: float = _progress.get_value(SPEED_KEY, "best", INF)
	var speed := [
		[tr("Best time"), _format_time(speed_best) if speed_best != INF else "–"],
		[tr("Runs played"), _progress.get_value(STATS, "speed_runs", 0)],
		[tr("Runs finished"), _progress.get_value(STATS, "speed_finished", 0)],
	]
	_stats.set_stats(daily, sizes, climb, speed)
	_menu.visible = false
	_fade_in(_stats)


## Counts a puzzle's first solve; only solves without hints count towards times.
## Returns the size and difficulty's record this solve beat, or INF when it set
## none or there was none to beat.
func _record_solve(size: int, difficulty: int, hinted: bool, seconds: float) -> float:
	_add_stat("solved_%d" % size, 1)
	if hinted:
		return INF
	_add_stat("timed_%d" % size, 1)
	_add_stat("time_%d" % size, seconds)
	if seconds < _progress.get_value(STATS, "best_%d" % size, INF):
		_progress.set_value(STATS, "best_%d" % size, seconds)
	var record := _size_record(size, difficulty)
	if seconds >= record:
		return INF
	_progress.set_value(STATS, _record_key(size, difficulty), seconds)
	return record


func _record_key(size: int, difficulty: int) -> String:
	return "best_%d_%s" % [size, Generator.DIFFICULTY_NAMES[difficulty].to_lower()]


## The fastest first solve without hints at this size and difficulty, or INF.
## Saves from before records were kept get one worked out from their best times.
func _size_record(size: int, difficulty: int) -> float:
	var key := _record_key(size, difficulty)
	if _progress.has_section_key(STATS, key):
		return _progress.get_value(STATS, key)
	var record := INF
	var regular := RegEx.create_from_string("^(\\d+)x\\d+_(.+)_\\d+$")
	for puzzle: String in (_progress.get_section_keys("best") if _progress.has_section("best") else PackedStringArray()):
		var at := [-1, -1]
		var found := regular.search(puzzle)
		if found:
			at = [found.get_string(1).to_int(), Generator.DIFFICULTY_NAMES.map(func(name: String) -> String:
				return name.to_lower()).find(found.get_string(2))]
		elif puzzle.begins_with("daily_"):
			at = [_daily_size(puzzle.trim_prefix("daily_")), DAILY_DIFFICULTY]
		elif puzzle.begins_with("weekly_"):
			at = [WEEKLY_SIZE, WEEKLY_DIFFICULTY]
		if at == [size, difficulty]:
			record = minf(record, _progress.get_value("best", puzzle))
	if record != INF:
		_progress.set_value(STATS, key, record)
	return record


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


func _on_reminder_toggled(enabled: bool) -> void:
	# Android 13 and up ask first; the answer arrives in _on_reminder_permission.
	if enabled and not _reminder.request_permission():
		_settings.show_reminder_enabled(false)
		return
	_set_reminder(enabled)


func _on_reminder_permission(granted: bool) -> void:
	_settings.show_reminder_enabled(granted)
	if granted:
		_set_reminder(true)


func _set_reminder(enabled: bool) -> void:
	_settings.show_reminder_enabled(enabled)
	_progress.set_value("settings", "reminder", enabled)
	_progress.save(save_path)
	_update_reminder()


func _on_reminder_hour_chosen(hour: int) -> void:
	_progress.set_value("settings", "reminder_hour", hour)
	_progress.save(save_path)
	_update_reminder()


## Sets the reminder's alarm, skipping today once today's daily is solved.
func _update_reminder() -> void:
	if not _progress.get_value("settings", "reminder", false):
		_reminder.cancel()
		return
	var not_before := 0
	if _progress.get_value("solved", _daily_key(_today()), false):
		not_before = _next_daily_time()
	_reminder.schedule(_progress.get_value("settings", "reminder_hour", DEFAULT_REMINDER_HOUR), 0, not_before,
			tr("Daily reminder"), "Crowns", tr("Today's daily puzzle is ready."))


## Debug builds' test button: the reminder notification now, asking for permission first if needed.
func _on_test_reminder() -> void:
	if _reminder.request_permission():
		_reminder.show_now(tr("Daily reminder"), "Crowns", tr("Today's daily puzzle is ready."))


func _on_vibration_toggled(enabled: bool) -> void:
	_haptics.enabled = enabled
	_progress.set_value("settings", "vibration", enabled)
	_progress.save(save_path)


func _on_patterns_toggled(enabled: bool) -> void:
	_view.patterns = enabled
	_progress.set_value("settings", "patterns", enabled)
	_progress.save(save_path)


## Saves the choice, then rebuilds every screen in the new language, back on Settings.
func _on_language_chosen(locale: String) -> void:
	_progress.set_value("settings", "language", locale)
	_save_board()
	_progress.save(save_path)
	Language.apply(locale)
	var fresh: Control = load(scene_file_path).instantiate()
	fresh.save_path = save_path
	fresh.open_settings = true
	add_sibling(fresh)
	if get_tree().current_scene == self:
		get_tree().current_scene = fresh
	queue_free()


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
		# Right-to-left layouts draw dropdowns with these instead.
		_theme.set_stylebox(state + "_mirrored", "OptionButton", box)
		# Keep the toggle switch borderless; it would otherwise inherit the button fill.
		_theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# Switches drawn to match, so they read clearly on or off against either background.
	var off: Color = SWITCH_OFF_DARK if enabled else SWITCH_OFF_LIGHT
	for mirrored in [false, true]:
		var suffix := "_mirrored" if mirrored else ""
		_theme.set_icon("checked" + suffix, "CheckButton", _switch_icon(fills.normal, not mirrored))
		_theme.set_icon("unchecked" + suffix, "CheckButton", _switch_icon(off, mirrored))
		_theme.set_icon("checked_disabled" + suffix, "CheckButton", _switch_icon(fills.disabled, not mirrored))
		_theme.set_icon("unchecked_disabled" + suffix, "CheckButton", _switch_icon(Color(off, 0.45), mirrored))
	# Text boxes, like the puzzle code entry: the page colour inset in the panel.
	for state in ["normal", "focus"]:
		var field := StyleBoxFlat.new()
		field.bg_color = colors.background
		field.set_corner_radius_all(10)
		field.set_border_width_all(2)
		field.border_color = fills.normal if state == "focus" else Color(colors.text, 0.2)
		field.content_margin_left = 12
		field.content_margin_right = 12
		_theme.set_stylebox(state, "LineEdit", field)
	_theme.set_color("font_color", "LineEdit", colors.text)
	_theme.set_color("font_placeholder_color", "LineEdit", Color(colors.text, 0.4))
	_theme.set_color("caret_color", "LineEdit", colors.text)
	_theme.set_color("selection_color", "LineEdit", Color(fills.normal, 0.35))
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
	# The player's own row: gold reads on the dark page, purple on the light one.
	_leaderboards.highlight = GOLD if enabled else BUTTON_LIGHT.normal


## A toggle switch: a rounded `track` with a white knob at the right or left end.
func _switch_icon(track: Color, knob_right: bool) -> DPITexture:
	var svg := ("<svg xmlns='http://www.w3.org/2000/svg' width='44' height='24'>"
			+ "<rect width='44' height='24' rx='12' fill='#%s' fill-opacity='%.2f'/>"
			+ "<circle cx='%d' cy='12' r='9' fill='#ffffff' fill-opacity='%.2f'/></svg>") % [
			track.to_html(false), track.a, 32 if knob_right else 12, 0.6 + 0.4 * track.a]
	return DPITexture.create_from_string(svg)


## `date` picks a past daily from the archive; otherwise the daily is today's.
func _start(mode: Mode, date := "") -> void:
	_mode = mode
	_from_archive = not date.is_empty()
	var tutorial := mode == Mode.TUTORIAL
	_back_button.text = tr("Back") if _from_archive else tr("Skip") if tutorial else tr("Menu")
	_win_back_button.text = tr("Menu") if tutorial else _back_button.text
	if mode == Mode.DAILY:
		_daily_date = date if _from_archive else _today()
		_daily_live = _daily_date == _today()
	elif mode == Mode.WEEKLY:
		_week = _week_start()
	elif mode == Mode.CHALLENGE and _run.is_empty():
		_new_run()
	elif mode == Mode.SPEED:
		_new_speed_run()
	elif tutorial:
		_tutorial_card = 0
	_menu.visible = false
	_archive.visible = false
	_settings.visible = false
	_leaderboards.visible = false
	_fade_in(_game)
	var regular := mode == Mode.REGULAR
	_size_picker.visible = regular
	_difficulty_picker.visible = regular
	_prev_button.visible = regular
	_next_button.visible = regular
	_code_button.visible = regular
	_code_overlay.visible = false
	_hint_button.visible = mode not in [Mode.CHALLENGE, Mode.SPEED]
	# The tutorial is untimed, and its Hint button turns the intro cards.
	_clear_button.visible = not tutorial
	_win_play_button.visible = false
	# The basics teach crossing out by hand; the advanced lessons do it for the player.
	_view.auto_cross = _progress.get_value("settings", "auto_cross", false) or (tutorial and _lesson > 0)
	_undo_button.visible = true
	_update_clock()
	_load_puzzle()


## [size, difficulty, seed] of the puzzle to play in the current mode, or of the
## one `ahead` places after it.
func _puzzle_spec(ahead := 0) -> Array:
	match _mode:
		Mode.DAILY:
			return [_daily_size(_daily_date), DAILY_DIFFICULTY, hash(["daily", _daily_date])]
		Mode.WEEKLY:
			return [WEEKLY_SIZE, WEEKLY_DIFFICULTY, hash(["weekly", _week])]
		Mode.CHALLENGE:
			var stage := _challenge_stage(ahead)
			return [stage[0], stage[1], hash([_run.seed, _run.level + ahead])]
		Mode.SPEED:
			var stage: Array = SPEED_STAGES[mini(_speed_run.level + ahead, SPEED_STAGES.size()) - 1]
			return [stage[0], stage[1], hash([_speed_run.seed, _speed_run.level + ahead])]
	# The puzzle number comes last, for sizes read from a pack.
	return [_size, _difficulty, hash([_size, _difficulty, _number + ahead]), _number + ahead]


## Whether `size` comes from a pre-made pack rather than the generator.
func _from_pack(size: int) -> bool:
	return size not in SIZES


## The puzzle for `spec`: the one generated ahead if it matches, otherwise made now.
func _generate(spec: Array) -> Dictionary:
	if _from_pack(spec[0]):
		return PuzzlePack.puzzle(spec[0], spec[1], spec[3])
	if not _prefetch.is_empty() and _prefetch.spec == spec:
		var job := _prefetch
		_prefetch = {}
		return await _finish(job)
	if not _threads:
		return Generator.generate(spec[0], spec[1], _seeded(spec[2]))
	return await _finish(_start_job(spec))


## Starts generating the next regular puzzle, or the next level of The Climb or
## a speed run, while this one is played, so Next doesn't have to wait for it.
func _prefetch_next() -> void:
	if not _threads or _mode not in [Mode.REGULAR, Mode.CHALLENGE, Mode.SPEED] \
			or (_mode == Mode.CHALLENGE and _run.is_empty()) \
			or (_mode == Mode.SPEED and _speed_run.level >= SPEED_STAGES.size()):
		return
	var spec := _puzzle_spec(1)
	# Pack puzzles load at once, so there's nothing to get ahead on.
	if _from_pack(spec[0]):
		return
	if not _prefetch.is_empty():
		if _prefetch.spec == spec:
			return
		_tasks[_prefetch.task] = false
	_prefetch = _start_job(spec)


func _start_job(spec: Array) -> Dictionary:
	var job := _make_job(spec)
	_tasks[job.task] = true
	return job


## Static so the worker's function holds nothing of this node, which may be
## freed (a language change rebuilds it) while the worker runs.
static func _make_job(spec: Array) -> Dictionary:
	var result := {}
	var rng := _seeded(spec[2])
	var task := WorkerThreadPool.add_task(func() -> void:
		result.merge(Generator.generate(spec[0], spec[1], rng)))
	return {"spec": spec, "task": task, "result": result}


## Waits for `job` without blocking the screen, then hands over its puzzle.
func _finish(job: Dictionary) -> Dictionary:
	while not WorkerThreadPool.is_task_completed(job.task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(job.task)
	_tasks.erase(job.task)
	return job.result


static func _seeded(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _new_run() -> void:
	_run = {"seed": randi(), "level": 1, "elapsed": 0.0}
	_progress.set_value(CHALLENGE_KEY, "run", _run)
	_add_stat("climb_runs", 1)
	_progress.save(save_path)


func _new_speed_run() -> void:
	_speed_run = {"seed": randi(), "level": 1, "elapsed": 0.0}
	_add_stat("speed_runs", 1)
	_progress.save(save_path)


func _load_puzzle() -> void:
	_save_board()
	_running = false
	_hide_overlay()
	_win_leaderboard_button.visible = _has_mode_leaderboard()
	_view.interactive = false
	_generating = true
	_puzzle_label.text = tr("Generating…")
	if not _threads:
		# Let the label paint before the larger sizes block for a moment.
		await get_tree().process_frame
		await get_tree().process_frame

	if _mode == Mode.REGULAR and _size not in _sizes:
		# A size whose pack this build lacks, e.g. from a save made elsewhere.
		_size = DEFAULT_SIZE
		_number = 1
		_size_picker.select(_sizes.find(_size))
	var size: int
	var puzzle: Dictionary
	if _mode == Mode.TUTORIAL:
		puzzle = _lesson_puzzle()
		size = LESSONS[_lesson].layout.size()
	else:
		var spec := _puzzle_spec()
		size = spec[0]
		puzzle = await _generate(spec)
	_board = Board.new(size, puzzle.regions, puzzle.solution)
	_board_key = _puzzle_key()
	_hinted = false
	_elapsed = _run.elapsed if _mode == Mode.CHALLENGE else _speed_run.elapsed if _mode == Mode.SPEED else 0.0
	var saved: Dictionary = {} if _board_key.is_empty() else _progress.get_value("in_progress", _board_key, {})
	# Only restore onto the same layout, in case puzzle generation has changed since.
	if saved.get("regions", PackedInt32Array()) == _board.regions:
		_board.marks = saved.marks
		_elapsed = saved.elapsed
		_hinted = saved.hinted
	if _mode == Mode.TUTORIAL:
		_board.marks = _lesson_marks()
	_view.board = _board
	_prefetch_next()
	_view.reveal()
	_sounds.play("reveal")
	_clear_hint()
	_view.interactive = true
	_generating = false
	_undo.clear()
	_undo_button.disabled = true
	_timer_label.text = _format_time(_elapsed)
	_running = true
	match _mode:
		Mode.REGULAR:
			_puzzle_label.text = tr("Puzzle #%d") % _number
		Mode.DAILY:
			_puzzle_label.text = tr("Daily · %s") % _pretty_date(_daily_date)
		Mode.WEEKLY:
			_puzzle_label.text = tr("Weekly · %s") % _pretty_date(_week)
		Mode.CHALLENGE:
			_puzzle_label.text = tr("The Climb #%d · %s") % [_run.level, _difficulty_name(_challenge_stage()[1])]
		Mode.SPEED:
			# TRANSLATORS: The board being played in a speed run, e.g. "Speed run · 2 of 5".
			_puzzle_label.text = tr("Speed run · {board} of {boards}").format(
					{"board": _speed_run.level, "boards": SPEED_STAGES.size()})
		Mode.TUTORIAL:
			_puzzle_label.text = tr("How to play") if _lesson == 0 \
					else tr("Technique %d of %d") % [_lesson, LESSONS.size() - 1]
			_update_tutorial()
	_update_best()

	if _mode == Mode.REGULAR:
		_progress.set_value("last", "size", _size)
		_progress.set_value("last", "number", _number)
		_progress.set_value("last", "difficulty", _difficulty)
		_progress.save(save_path)


## [size, difficulty] of The Climb's current level, or the one `ahead` of it.
func _challenge_stage(ahead := 0) -> Array:
	return CHALLENGE_STAGES[mini(_run.level + ahead, CHALLENGE_STAGES.size()) - 1]


func _go_to(number: int) -> void:
	if number < 1 or _generating or _mode != Mode.REGULAR:
		return
	_number = number
	_load_puzzle()


func _on_next_puzzle() -> void:
	if _mode == Mode.TUTORIAL:
		if _lesson < LESSONS.size() - 1:
			_start_lesson(_lesson + 1)
		else:
			_start(Mode.REGULAR)
		return
	if _mode == Mode.REGULAR:
		_go_to(_number + 1)
		return
	if _mode == Mode.CHALLENGE and _run.is_empty():
		_new_run()
	if _mode == Mode.SPEED and _speed_run.level > SPEED_STAGES.size():
		_new_speed_run()
	_load_puzzle()


func _on_size_selected(index: int) -> void:
	if _generating:
		_size_picker.select(_sizes.find(_size))
		return
	_size = _sizes[index]
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
	if _mode == Mode.TUTORIAL:
		_update_tutorial()


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
	if _mode == Mode.TUTORIAL:
		_update_tutorial()


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
	if _mode == Mode.TUTORIAL:
		_tutorial_card += 1
		_update_tutorial()
		return
	if not _view.interactive or _mode in [Mode.CHALLENGE, Mode.SPEED]:
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
	_hint_button.text = tr("Apply hint")


func _clear_hint() -> void:
	_hint = {}
	_hint_label.text = ""
	_view.hint_focus = PackedInt32Array()
	_view.hint_targets = PackedInt32Array()
	_hint_button.text = tr("Hint")


## Points out a mistake if there is one, otherwise the easiest deduction left.
func _find_hint() -> Dictionary:
	var n := _board.size
	for cell in _board.crowns():
		if _board.solution[cell.x] != cell.y:
			return _make_hint(tr("This crown isn't part of the solution."), [cell], [[cell, Board.Mark.CROWN, Board.Mark.EMPTY]])
	for row in n:
		var cell := Vector2i(row, _board.solution[row])
		if _board.is_cross(cell):
			return _make_hint(tr("This cell is crossed out, but it needs a crown."), [cell],
					[[cell, _board.get_mark(cell), Board.Mark.EMPTY]])

	var step := Grader.next_step(n, _board.regions, _board.marks)
	if step.is_empty():
		for row in n:
			var cell := Vector2i(row, _board.solution[row])
			if _board.get_mark(cell) != Board.Mark.CROWN:
				return _make_hint(tr("There's no simple deduction from here, so here's a crown."), [cell],
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


func _start_lesson(lesson: int) -> void:
	_lesson = lesson
	_start(Mode.TUTORIAL)


func _lesson_puzzle() -> Dictionary:
	var layout: Array = LESSONS[_lesson].layout
	var regions := PackedInt32Array()
	for line: String in layout:
		for letter in line:
			regions.append(letter.unicode_at(0) - "A".unicode_at(0))
	return {"regions": regions, "solution": Solver.find_solutions(layout.size(), regions, 1)[0]}


## The lesson's starting marks: its puzzle solved step by step, each crown's
## ruled-out cells crossed, up to the first step that needs the lesson's technique.
func _lesson_marks() -> PackedInt32Array:
	var technique: String = LESSONS[_lesson].technique
	var scratch := Board.new(_board.size, _board.regions, _board.solution)
	while not technique.is_empty():
		var step := Grader.next_step(scratch.size, scratch.regions, scratch.marks)
		if step.is_empty() or _technique(step) == technique:
			break
		for cell: int in step.cross:
			scratch.marks[cell] = Board.Mark.CROSS
		if step.crown >= 0:
			scratch.marks[step.crown] = Board.Mark.CROWN
			for change in scratch.auto_cross_changes():
				scratch.set_mark(change[0], Board.Mark.CROSS)
	return scratch.marks


## A grader step's technique as the lessons name them: "confined" for one group
## inside another, "group" for several.
func _technique(step: Dictionary) -> String:
	if step.rule == "confined" and step.from.size() > 1:
		return "group"
	return step.rule


func _tutorial_cards() -> Array[String]:
	match LESSONS[_lesson].technique:
		"confined":
			return [tr("Harder puzzles need more than \"only one cell left\". These lessons show the techniques the hints use, starting with claiming a line."),
					tr("If all of a region's open cells lie in one row, its crown must be in that row. That uses up the row's crown, so cross out the rest of the row. The same works for columns, and for a row that lies inside one region.")]
		"group":
			return [tr("Groups: if two regions fit entirely within two rows, their crowns use up both rows' crowns. Cross out every other cell in those rows. It works for three regions in three rows too, and for columns.")]
		"blocker":
			return [tr("What if? Imagine a crown in a cell. If it would rule out every open cell left in some row, column or region, that cell can't hold a crown. Cross it out.")]
	return [tr("Welcome to Crowns! Place one crown in every row, every column and every colour region."),
			tr("Crowns can never touch each other, not even diagonally.")]


## Shows the tutorial's next step: an intro card, a mistake to fix, the cells a
## crown rules out, or the next crown and why it goes there. It's worked out from
## the board each time, so undo and stray taps can't throw it off.
func _update_tutorial() -> void:
	var cards := _tutorial_cards()
	var on_card := _tutorial_card < cards.size()
	_hint_button.visible = on_card
	_undo_button.visible = not on_card
	_view.interactive = not on_card
	if on_card:
		_hint_button.text = tr("Next")
		_show_tutorial_step(cards[_tutorial_card], PackedInt32Array(), PackedInt32Array())
		return
	if _board.is_solved():
		return
	var hint := _find_hint()
	if hint.changes[0][2] == Board.Mark.EMPTY:
		_show_tutorial_step(hint.message + " " + tr("Tap it to clear it."), hint.focus, hint.targets)
		return
	var ruled_out := PackedInt32Array()
	for change in _board.auto_cross_changes():
		if change[2] == Board.Mark.AUTO_CROSS:
			ruled_out.append(_board.index(change[0]))
	if not ruled_out.is_empty():
		var focus := ruled_out.duplicate()
		for crown in _board.crowns():
			focus.append(_board.index(crown))
		var text := tr("A crown rules out the rest of its row, column and region, and every cell touching it. Tap each highlighted cell to cross it out, or drag across them.")
		if _board.crowns().size() > 1:
			text = tr("Cross out the cells the new crown rules out. (Auto-place × in Settings can do this for you.)")
		_show_tutorial_step(text, focus, ruled_out)
		return
	# Crossing hints already say what to cross out.
	var places_crown: bool = hint.changes.any(func(c: Array) -> bool: return c[2] == Board.Mark.CROWN)
	_show_tutorial_step(hint.message + (" " + tr("Double tap it to place a crown.") if places_crown else ""),
			hint.focus, hint.targets)


func _show_tutorial_step(text: String, focus: PackedInt32Array, targets: PackedInt32Array) -> void:
	_hint_label.text = text
	_view.hint_focus = focus
	_view.hint_targets = targets


func _set_tutorial_done() -> void:
	_progress.set_value("settings", "tutorial_done", true)
	_progress.save(save_path)


func _make_hint(message: String, targets: Array, changes: Array) -> Dictionary:
	var indices := PackedInt32Array()
	for cell: Vector2i in targets:
		indices.append(_board.index(cell))
	return {"message": message, "focus": indices, "targets": indices, "changes": changes}


## The deduction behind a hint, as a sentence. Groups are named by _group_name(s),
## like "row 3" or "the purple and blue regions".
func _explain(step: Dictionary) -> String:
	return _upper_first(_explain_step(step))


func _explain_step(step: Dictionary) -> String:
	var from: Array = step.from
	match step.rule:
		"single":
			# TRANSLATORS: {group} is a row, column or region, e.g. "row 3" or "the purple region".
			return tr("{group} has only one cell left that can hold its crown.").format({"group": _group_name(from[0])})
		"blocker":
			var cell: int = step.cross[0]
			return tr("A crown in row {row}, column {column} would rule out every open cell left in {group}, so cross it out.") \
					.format({"row": cell / _board.size + 1, "column": cell % _board.size + 1, "group": _group_name(from[0])})
	var to: Array = step.to
	if from.size() == 1:
		# TRANSLATORS: {a} and {b} are a row, column or region, e.g. "the purple region".
		return tr("{a}'s open cells all lie in {b}, so {b}'s crown must come from {a}. Cross out the rest of {b}.") \
				.format({"a": _group_name(from[0]), "b": _group_name(to[0])})
	# TRANSLATORS: {a} and {b} are several rows, columns or regions, e.g. "rows 2 and 3"; {count} is at least 2.
	return tr("{a} only have open cells in {b}, so their {count} crowns fill {b}. Cross out everything else in {b}.") \
			.format({"a": _group_names(from), "b": _group_names(to), "count": from.size()})


func _upper_first(text: String) -> String:
	return text[0].to_upper() + text.substr(1)


func _group_name(group: int) -> String:
	var index := Grader.group_index(_board.size, group)
	match Grader.group_kind(_board.size, group):
		Grader.Kind.ROW:
			return tr("row %d") % (index + 1)
		Grader.Kind.COLUMN:
			return tr("column %d") % (index + 1)
	# TRANSLATORS: %s is a region colour, e.g. "purple".
	return tr("the %s region") % _view.region_name(index)


## "rows 2 and 3", "the purple, blue and green regions".
func _group_names(groups: Array) -> String:
	var parts: Array[String] = []
	for group: int in groups:
		var index := Grader.group_index(_board.size, group)
		if Grader.group_kind(_board.size, group) == Grader.Kind.REGION:
			parts.append(_view.region_name(index))
		else:
			parts.append(str(index + 1))
	# TRANSLATORS: Joins a list, e.g. "2, 3 and 4": {items} is all but the last item, joined by the list separator.
	var listed := tr("{items} and {last}").format({"items": tr(", ", "list separator").join(parts.slice(0, -1)),
			"last": parts[-1]})
	match Grader.group_kind(_board.size, groups[0]):
		Grader.Kind.ROW:
			return tr("rows %s") % listed
		Grader.Kind.COLUMN:
			return tr("columns %s") % listed
	# TRANSLATORS: %s lists region colours, e.g. "purple and blue".
	return tr("the %s regions") % listed


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
	_haptics.win()
	_win_crown.visible = true
	_win_heading.text = tr("Solved!")
	# The daily and weekly are one puzzle each, so only they have no next one.
	_next_puzzle_button.visible = _mode in [Mode.REGULAR, Mode.CHALLENGE, Mode.SPEED]
	_next_puzzle_button.text = tr("Next puzzle")
	if _mode == Mode.TUTORIAL:
		_set_tutorial_done()
		var last := _lesson == LESSONS.size() - 1
		_win_label.text = tr("You solved your first puzzle!") if _lesson == 0 \
				else tr("That's every technique the hints use.") if last else tr("Lesson complete!")
		_next_puzzle_button.text = tr("Start playing") if last else tr("Next lesson")
		_next_puzzle_button.visible = true
		# After the basics, new players can go straight to playing.
		_win_play_button.visible = _lesson == 0
		_win_leaderboard_button.visible = false
		_show_win_overlay()
		return
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
		_submit_online("climb", solved)
		_progress.save(save_path)
		_on_progress_made()
		_win_label.text = _run_summary(solved)
		_update_best()
		_show_win_overlay()
		return
	if _mode == Mode.SPEED:
		_speed_solved()
		return
	var key := _puzzle_key()
	var difficulty: int = _puzzle_spec()[1]
	# Before this solve's time is saved, which a record worked out from old saves would count.
	_size_record(_board.size, difficulty)
	var best: float = _progress.get_value("best", key, INF)
	# Hinted solves don't count towards best times.
	var record := not _hinted and _elapsed < best
	if record:
		_progress.set_value("best", key, _elapsed)
	# A record this first solve beat, or INF; replays of a known board don't count.
	var beaten := INF
	if not _progress.get_value("solved", key, false):
		beaten = _record_solve(_board.size, difficulty, _hinted, _elapsed)
		match _mode:
			Mode.DAILY:
				# Archive dailies count as solves, but not towards streaks or the daily board.
				if _daily_live:
					_record_daily(_daily_date)
			Mode.WEEKLY:
				_add_stat("weeklies_solved", 1)
			_:
				if not _hinted:
					_add_stat("puzzles_unhinted", 1)
					_play_games.submit_solved(_progress.get_value(STATS, "puzzles_unhinted", 0))
					_submit_online("solved", _progress.get_value(STATS, "puzzles_unhinted", 0))
	if not _hinted:
		if _mode == Mode.DAILY and _daily_live:
			_play_games.submit_daily_time(_elapsed)
			_submit_online(SilentWolf.daily_board(_daily_date), SilentWolf.time_score(_elapsed))
		elif _mode == Mode.WEEKLY and _week == _week_start():
			# Once the week has turned over, the board only holds the new week's times.
			_play_games.submit_weekly_time(_elapsed)
			_submit_online(SilentWolf.weekly_board(_week), SilentWolf.time_score(_elapsed))
	_progress.set_value("solved", key, true)
	_progress.save(save_path)
	if _mode == Mode.DAILY:
		# No reminder for today's daily once it's solved.
		_update_reminder()
	_on_progress_made()
	var note := "  " + tr("(hints used)") if _hinted else "  " + tr("(new best!)") if record and best != INF else ""
	_win_label.text = tr("Time: %s") % _format_time(_elapsed) + note
	if beaten != INF:
		# TRANSLATORS: Shown on solving faster than ever at a size and difficulty, e.g. "New 8×8 Hard record!"
		_win_label.text += "\n" + tr("New {size} {difficulty} record!").format({
			"size": "%d×%d" % [_board.size, _board.size], "difficulty": _difficulty_name(difficulty)}) \
				+ "\n" + tr("Previous best: %s") % _format_time(beaten)
	_update_best()
	_show_win_overlay()


## A speed run's board is solved: on to the next after a short pause, or the
## run's result after the last.
func _speed_solved() -> void:
	_speed_run.elapsed = _elapsed
	_speed_run.level += 1
	if _speed_run.level <= SPEED_STAGES.size():
		var run := _speed_run
		await get_tree().create_timer(SPEED_PAUSE).timeout
		# Unless the player left, or started over, in the meantime.
		if _speed_run == run and _mode == Mode.SPEED and _game.visible:
			_load_puzzle()
		return
	var best: float = _progress.get_value(SPEED_KEY, "best", INF)
	if _elapsed < best:
		_progress.set_value(SPEED_KEY, "best", _elapsed)
	_add_stat("speed_finished", 1)
	_progress.save(save_path)
	_on_progress_made()
	_win_heading.text = tr("Finished!")
	var note := "  " + tr("(new best!)") if _elapsed < best and best != INF else ""
	_win_label.text = tr("Time: %s") % _format_time(_elapsed) + note
	if _elapsed >= best:
		_win_label.text += "\n" + tr("Best: %s") % _format_time(best)
	_next_puzzle_button.text = tr("New run")
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
	_win_heading.text = tr("Out of lives")
	var note := "  " + tr("(best run!)") if solved > 0 and solved >= best_run else ""
	_win_label.text = tr("That crown doesn't belong there.") + "\n" + _run_summary(solved) + note
	_next_puzzle_button.visible = true
	_next_puzzle_button.text = tr("New run")
	_update_best()
	_show_overlay(0.4)


## "3 puzzles solved · 4:05" for The Climb's panels.
func _run_summary(solved: int) -> String:
	return tr_n("%d puzzle solved", "%d puzzles solved", solved) % solved + " · " + _format_time(_elapsed)


## Achievements and the cloud save catch up after a solve.
func _on_progress_made() -> void:
	_check_achievements()
	_upload_progress()


func _on_signed_in() -> void:
	# Earlier progress counts too, e.g. achievements earned before they existed.
	_check_achievements()
	_play_games.load_cloud()


## Merges the cloud save into this device's progress, then uploads the result.
func _on_cloud_loaded(data: PackedByteArray) -> void:
	var remote := CloudSave.unpack(data)
	if remote:
		var had_last := _progress.has_section("last")
		CloudSave.merge(_progress, remote)
		_progress.save(save_path)
		# A first start on this device carries on where the other one was.
		if not had_last and _progress.has_section("last"):
			_size = _progress.get_value("last", "size", DEFAULT_SIZE)
			_number = _progress.get_value("last", "number", 1)
			_difficulty = _progress.get_value("last", "difficulty", DEFAULT_DIFFICULTY)
		if _run.is_empty():
			_run = _progress.get_value(CHALLENGE_KEY, "run", {})
		if _menu.visible:
			_show_menu()
		elif _board != null:
			_update_best()
		_check_achievements()
	_cloud_ready = true
	_upload_progress()


func _upload_progress() -> void:
	if not _cloud_ready:
		return
	var solved := CloudSave.solved_count(_progress)
	_play_games.save_cloud(CloudSave.pack(_progress), _puzzles(solved), solved)


## Unlocks every achievement the saved progress has earned. Play Games ignores
## repeats, so this simply runs after each solve and at sign-in.
func _check_achievements() -> void:
	var earned := _earned_achievements()
	for name: String in earned:
		if earned[name]:
			_play_games.unlock(name)


## Achievement name -> whether the progress has earned it. Best times are only
## kept for solves without hints, which several of these rely on.
func _earned_achievements() -> Dictionary:
	var bests := _progress.get_section_keys("best") if _progress.has_section("best") else PackedStringArray()
	var climb_best: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
	var longest: int = _progress.get_value(STATS, "longest_streak", 0)
	var hard := false
	var quick := false
	for key in bests:
		# The weekly challenge is always Hard.
		hard = hard or key.contains("_hard_") or key.contains("_hard+_") or key.begins_with("weekly_")
		quick = quick or (key.begins_with("daily_") and _progress.get_value("best", key) < 60.0)
	var solved := CloudSave.solved_count(_progress)
	return {
		"first_crown": solved > 0,
		"unaided": not bests.is_empty() or climb_best > 0,
		"hard": hard,
		# The Climb's 15th puzzle is a 10×10.
		"big_board": _progress.get_value(STATS, "solved_10", 0) > 0 or climb_best >= 15,
		"weekly": _progress.get_value(STATS, "weeklies_solved", 0) > 0,
		"streak_7": longest >= 7,
		"streak_30": longest >= 30,
		"climb_10": climb_best >= 10,
		"climb_25": climb_best >= 25,
		"quick": quick,
		"century": solved >= 100,
	}


## Whether scores go to SilentWolf: in builds with its key (all but Google Play's),
## unless turned off in Settings.
func _silent_wolf_on() -> bool:
	return _silent_wolf.available() and _progress.get_value("settings", "silent_wolf", true)


## Whether there are any leaderboards: SilentWolf's, or Play Games' on Android.
func _has_leaderboards() -> bool:
	return _silent_wolf_on() or _play_games.available()


func _on_silent_wolf_toggled(enabled: bool) -> void:
	_progress.set_value("settings", "silent_wolf", enabled)
	_progress.save(save_path)
	_menu.leaderboards_button.visible = _has_leaderboards()
	if enabled:
		_silent_wolf.retry()


## Whether the mode being played has a board to open from the win panel.
func _has_mode_leaderboard() -> bool:
	match _mode:
		Mode.DAILY:
			# Past dailies aren't on the daily board, which only shows today's times.
			return _has_leaderboards() and _daily_live
		Mode.WEEKLY:
			return _play_games.has_weekly() or _silent_wolf_on()
		Mode.SPEED:
			# No speed board yet; runs only keep a personal best.
			return false
	return _has_leaderboards()


## Opens the board for the mode just played.
func _show_mode_leaderboard() -> void:
	var kind := "solved"
	match _mode:
		Mode.DAILY:
			kind = "daily"
		Mode.WEEKLY:
			kind = "weekly"
		Mode.CHALLENGE:
			kind = "climb"
	if _silent_wolf_on():
		_leaderboards_from_game = true
		_game.visible = false
		_open_leaderboards(kind)
		return
	_show_play_games_board(kind)


## Opens Play Games' own board for `kind` ("daily", "weekly", "climb" or "solved").
func _show_play_games_board(kind: String) -> void:
	match kind:
		"daily":
			_play_games.show_daily()
		"weekly":
			_play_games.show_weekly()
		"climb":
			_play_games.show_climb()
		_:
			_play_games.show_solved()


## The leaderboards from the menu: ours with SilentWolf, otherwise Play Games' own.
func _show_leaderboards(kind: String) -> void:
	if not _silent_wolf_on():
		_play_games.show_all()
		return
	if _generating:
		return
	_leaderboards_from_game = false
	for screen: Control in [_menu, _settings, _stats, _archive]:
		screen.visible = false
	_open_leaderboards(kind)


func _open_leaderboards(kind: String) -> void:
	_running = false
	_leaderboards.player_id = _player_id()
	_leaderboards.name_entry.text = _player_name()
	var times := func(score: int) -> String: return _format_time(-score / 1000.0)
	_leaderboards.boards = {
		"daily": {"board": SilentWolf.daily_board(_today()), "title": _pretty_date(_today()), "format": times},
		"weekly": {"board": SilentWolf.weekly_board(_week_start()),
				"title": tr("Week of %s") % _pretty_date(_week_start()), "format": times},
		"climb": {"board": "climb", "title": tr("Best runs"), "format": _puzzles},
		"solved": {"board": "solved", "title": tr("Puzzles solved without hints"), "format": func(score: int) -> String:
			return "%d" % score},
	}
	_fade_in(_leaderboards)
	_leaderboards.show_board(kind)


func _close_leaderboards() -> void:
	_leaderboards.visible = false
	if _leaderboards_from_game:
		_leaderboards_from_game = false
		_fade_in(_game)
	else:
		_show_menu()


## Sends a score to the SilentWolf board `board`; Play Games gets its own copy.
func _submit_online(board: String, score: int) -> void:
	if _silent_wolf_on():
		_silent_wolf.submit(board, _player_id(), _player_name(), score)


## A random id for this player's scores, made on first use.
func _player_id() -> String:
	if not _progress.has_section_key(ONLINE, "player_id"):
		_progress.set_value(ONLINE, "player_id", Crypto.new().generate_random_bytes(8).hex_encode())
		_progress.save(save_path)
	return _progress.get_value(ONLINE, "player_id")


## The name shown on the boards; "Player 1234" until the player picks one.
func _player_name() -> String:
	if not _progress.has_section_key(ONLINE, "player_name"):
		_progress.set_value(ONLINE, "player_name", "Player %d" % randi_range(1000, 9999))
		_progress.save(save_path)
	return _progress.get_value(ONLINE, "player_name")


## The timer and best time show unless hidden in Settings; lessons are untimed.
## Hidden, the clock still runs, so times and leaderboards work as usual.
func _update_clock() -> void:
	var shown: bool = _mode != Mode.TUTORIAL and _progress.get_value("settings", "show_timer", true)
	_timer_label.visible = shown
	_best_label.visible = shown


func _on_timer_toggled(shown: bool) -> void:
	_progress.set_value("settings", "show_timer", shown)
	_progress.save(save_path)
	_update_clock()


func _update_best() -> void:
	if _mode == Mode.CHALLENGE:
		var best_run: int = _progress.get_value(CHALLENGE_KEY, "best", 0)
		_best_label.text = "" if best_run == 0 else tr("Best run %d") % best_run
		return
	if _mode == Mode.SPEED:
		var best_run: float = _progress.get_value(SPEED_KEY, "best", INF)
		_best_label.text = "" if best_run == INF else tr("Best %s") % _format_time(best_run)
		return
	var best: float = _progress.get_value("best", _puzzle_key(), INF)
	_best_label.text = "" if best == INF else tr("Best %s") % _format_time(best)


func _puzzle_key() -> String:
	match _mode:
		Mode.DAILY:
			return _daily_key(_daily_date)
		Mode.WEEKLY:
			return _weekly_key(_week)
		Mode.CHALLENGE:
			return CHALLENGE_KEY
		Mode.TUTORIAL, Mode.SPEED:
			# Nothing from the tutorial or a speed run is saved.
			return ""
	return "%dx%d_%s_%d" % [_size, _size, Generator.DIFFICULTY_NAMES[_difficulty].to_lower(), _number]


func _daily_key(date: String) -> String:
	return "daily_" + date


func _weekly_key(week: String) -> String:
	return "weekly_" + week


func _daily_size(date: String) -> int:
	return DAILY_SIZES[posmod(hash(["daily_size", date]), DAILY_SIZES.size())]


## The daily puzzle's date. It changes at midnight UTC−7 for everyone, the
## moment Google Play Games resets its daily leaderboards.
func _today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + DAILY_UTC_OFFSET)


## The weekly challenge's first day: the latest Sunday on the daily calendar, so
## weeks turn over with Play Games' weekly leaderboards, Saturday midnight UTC−7.
func _week_start() -> String:
	var now := int(Time.get_unix_time_from_system()) + DAILY_UTC_OFFSET
	return Time.get_date_string_from_unix_time(now - _weekday() * 86400)


## Unix time when the next daily puzzle comes out: midnight UTC−7.
func _next_daily_time() -> int:
	var now := int(Time.get_unix_time_from_system()) + DAILY_UTC_OFFSET
	return (now / 86400 + 1) * 86400 - DAILY_UTC_OFFSET


## Today's day of the week on the daily calendar, from 0 for Sunday to 6 for Saturday.
func _weekday() -> int:
	return Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + DAILY_UTC_OFFSET).weekday


## "2026-10-23" -> "Oct 23".
func _pretty_date(date: String) -> String:
	var parts := date.split("-")
	var months: Array[String] = [tr("Jan", "short month"), tr("Feb", "short month"), tr("Mar", "short month"),
			tr("Apr", "short month"), tr("May", "short month"), tr("Jun", "short month"), tr("Jul", "short month"),
			tr("Aug", "short month"), tr("Sep", "short month"), tr("Oct", "short month"), tr("Nov", "short month"),
			tr("Dec", "short month")]
	# TRANSLATORS: A short date, e.g. "Oct 23".
	return tr("{month} {day}", "short date").format({"month": months[parts[1].to_int() - 1], "day": parts[2].to_int()})


## Difficulty names as shown; Generator.DIFFICULTY_NAMES stay English for save keys.
func _difficulty_name(difficulty: int) -> String:
	return [tr("Easy"), tr("Medium"), tr("Hard"), tr("Hard+")][difficulty]


func _puzzles(count: int) -> String:
	return tr_n("%d puzzle", "%d puzzles", count) % count


func _days(count: int) -> String:
	return tr_n("%d day", "%d days", count) % count


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
