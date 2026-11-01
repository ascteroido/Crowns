extends SceneTree
## Drives the game screen with simulated clicks:
##   godot --path . --script res://tests/ui_test.gd [-- screenshot_dir]
## Saves screenshots when a directory is given and a renderer is available.

const Board := preload("res://scripts/board.gd")
const BoardViewScript := preload("res://scripts/board_view.gd")
const Generator := preload("res://scripts/generator.gd")
const Grader := preload("res://scripts/grader.gd")
const Language := preload("res://scripts/language.gd")
const CloudSave := preload("res://scripts/cloud_save.gd")
const PuzzleCode := preload("res://scripts/puzzle_code.gd")
const CustomPuzzle := preload("res://scripts/custom_puzzle.gd")
const SilentWolf := preload("res://scripts/silent_wolf.gd")
const Archive := preload("res://scripts/archive.gd")
const BoardImage := preload("res://scripts/board_image.gd")
const Updater := preload("res://scripts/updater.gd")
const UpdatePot := preload("res://tools/update_pot.gd")
const TEST_SAVE := "user://test_progress.cfg"

var failures := 0
var shot_dir := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		shot_dir = args[0]
	_run.call_deferred()


func _run() -> void:
	# Never post to the real leaderboards from tests.
	SilentWolf.offline = true
	# Silent, as these also run with a window for screenshots.
	AudioServer.set_bus_mute(0, true)
	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = TEST_SAVE
	# The tutorial's own test covers a first launch.
	main.first_run_tutorial = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	# Headless windows default to 64x64, which would drop clicks outside it.
	root.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	root.add_child(main)
	await _frames(3)
	_expect(main._menu.visible and not main._game.visible and main._board == null, "starts on the menu")
	_expect(main._menu.continue_button.text == "Play", "fresh save offers Play")
	_expect(main._menu.exit_button.visible == OS.has_feature("pc"), "exit shows on desktop only")
	_expect(main._menu.exit_chosen.is_connected(main._exit), "exit button closes the game")
	main._menu.leaderboards_button.visible = true
	main._menu.exit_button.visible = true
	await _frames(3)
	var menu_box: Rect2 = main._menu._box.get_global_rect()
	_expect(menu_box.position.y >= 0.0 and menu_box.end.y <= main._menu.size.y,
			"the menu shrinks to fit when every button shows")
	main._menu.leaderboards_button.visible = false
	main._menu.exit_button.visible = OS.has_feature("pc")
	_screenshot("menu.png")

	# Settings: a theme recolours the screen and is saved.
	main._menu.settings_button.pressed.emit()
	_expect(main._settings.visible and not main._menu.visible, "settings opens from the menu")
	var picker: OptionButton = main._settings.theme_picker
	_expect(picker.selected == 0 and not main._settings._custom_row.visible, "the light theme comes first")
	picker.select(1)
	picker.item_selected.emit(1)
	await _frames(3)
	_expect(main._background.color == main.THEMES.dark.background and main._view.dark, "the dark theme applies")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "theme", "") == "dark", "the theme is saved")
	_screenshot("settings_dark.png")
	main._settings.back.emit()
	_expect(main._menu.visible and not main._settings.visible, "back returns to the menu")
	await _frames(2)
	_screenshot("menu_dark.png")
	main._show_settings()

	# High contrast: yellow buttons need dark text.
	var contrast: int = main._settings.themes.find("contrast")
	picker.select(contrast)
	picker.item_selected.emit(contrast)
	_expect(main._background.color == Color.BLACK and main._theme.get_color("font_color", "Button") == main.THEMES.light.text,
			"high contrast has dark text on its light buttons")

	# Custom starts from the theme on screen, then follows the picked colours.
	var custom: int = main._settings.themes.find("custom")
	picker.select(custom)
	picker.item_selected.emit(custom)
	_expect(main._settings._custom_row.visible and main._settings.background_picker.color == Color.BLACK,
			"custom shows its colours, starting from the last theme")
	main._settings.background_picker.color = Color("f0e0f0")
	main._settings.button_color_picker.color = Color("204060")
	main._settings._emit_custom_colors(false)
	_expect(main._background.color == Color("f0e0f0") and not main._view.dark
			and main._theme.get_color("font_color", "Label") == main.THEMES.light.text
			and main._theme.get_color("font_color", "Button") == Color.WHITE, "a light custom page gets dark text, a dark button white")
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "custom_background", Color.BLACK) == Color.BLACK, "colours save once picking is done")
	main._settings._emit_custom_colors(true)
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "theme", "") == "custom"
			and saved.get_value("settings", "custom_background", Color.BLACK) == Color("f0e0f0"), "custom colours are saved")
	main._settings.background_picker.color = Color("102030")
	main._settings._emit_custom_colors(true)
	_expect(main._view.dark and main._theme.get_color("font_color", "Label") == main.THEMES.dark.text,
			"a dark custom page gets light text and a dimmed board")
	_screenshot("settings_custom.png")

	# Volume, on computers: saved, and greyed out while sound is off.
	var slider: HSlider = main._settings.volume_slider
	_expect(main._settings._volume_row.visible and slider.value == 100 and main._sounds.volume == 1.0,
			"computers get a volume slider, full by default")
	slider.value = 40
	saved.load(TEST_SAVE)
	_expect(is_equal_approx(main._sounds.volume, 0.4) and is_equal_approx(saved.get_value("settings", "volume", 1.0), 0.4)
			and is_equal_approx(main._sounds._players[0].volume_db, linear_to_db(0.4)), "the volume slider sets and saves the volume")
	main._settings.sound_toggle.button_pressed = false
	_expect(not slider.editable, "the slider is off while sound is")
	main._settings.sound_toggle.button_pressed = true
	_expect(slider.editable, "the slider comes back with sound")
	slider.value = 100

	# The app icon follows the theme unless chosen; it can only change on Android.
	_expect(not main._settings._app_icon_row.visible and not main._app_icon.available(), "the app icon choice is Android only")
	_expect(main._app_icon_for("theme", "midnight") == "midnight" and main._app_icon_for("theme", "light") == "classic"
			and main._app_icon_for("theme", "custom") == "classic" and main._app_icon_for("forest", "dark") == "forest",
			"the app icon matches the theme, or the chosen one")
	_expect(main._settings.APP_ICONS.slice(1) == main.AppIcon.ICONS, "Settings offers every app icon")

	# System follows the device's light or dark mode, where it has one.
	_expect(not main._settings.themes.has("system") or DisplayServer.is_dark_mode_supported(),
			"System is only offered where the device has a dark mode")
	var had_system: bool = main._system_theme
	main._system_theme = true
	var device_dark := [true]
	main._system_dark = func() -> bool: return device_dark[0]
	main._on_theme_chosen("system")
	_expect(main._background.color == main.THEMES.dark.background and main._view.dark, "System follows a dark device")
	device_dark[0] = false
	main._on_system_theme_changed()
	_expect(main._background.color == main.THEMES.light.background and not main._view.dark,
			"and turns light when the device does")
	main._progress.erase_section_key("settings", "theme")
	_expect(main._theme_name() == "system", "new players follow the device")
	main._system_theme = false
	main._progress.set_value("settings", "theme", "system")
	_expect(main._theme_name() == "light", "without a device dark mode, System falls back to light")
	main._system_theme = had_system
	main._system_dark = func() -> bool: return DisplayServer.is_dark_mode()
	main._progress.set_value("settings", "theme", "light")

	# Saves from before themes keep their dark mode.
	main._progress.erase_section_key("settings", "theme")
	main._progress.set_value("settings", "dark_mode", true)
	_expect(main._theme_name() == "dark", "an old dark mode save opens in the dark theme")
	main._progress.erase_section_key("settings", "dark_mode")
	picker.select(0)
	picker.item_selected.emit(0)
	_expect(main._background.color == main.THEMES.light.background and not main._view.dark
			and not main._settings._custom_row.visible, "the light theme restores")
	main._show_menu()

	main._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = main._view
	var board: Board = main._board
	_expect(board != null and view.interactive, "puzzle generated and board accepts input")
	_expect(view._reveal_at >= 0, "a new puzzle grows its tiles in")
	var reveal_end: float = Time.get_ticks_msec() + view.reveal_ms() + 50
	while Time.get_ticks_msec() < reveal_end:
		await _frames(1)
	await _frames(1)
	_expect(view._reveal_at == -1, "the reveal finishes")

	# A slow click crosses out an empty cell and clears anything else.
	var target := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "first click crosses")
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.EMPTY, "a slow click on a cross clears it")
	await _right_click(view, target)
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.EMPTY, "a slow click on a crown clears it")

	# A double tap places a crown whatever the cell held.
	await _slow_click(view, target)
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "double tap on empty places a crown")
	await _slow_click(view, target)
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "slow taps clear the crown, then cross")
	await _slow_click(view, target)
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "double tap on a cross places a crown")
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.EMPTY, "a third quick tap cycles normally")
	view._tap_time = -view.DOUBLE_TAP_MS
	await _touch(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "a touchscreen tap crosses")
	await _touch(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "a touchscreen double tap places a crown")
	main._on_clear()

	# Drag across the bottom row crosses every cell in one undo step.
	var undo_before: int = main._undo.size()
	var last := board.size - 1
	await _drag_row(view, last)
	_expect(_count_row(board, last, Board.Mark.CROSS) == board.size, "drag crossed the whole row")
	_expect(main._undo.size() == undo_before + 1, "drag is a single undo step")

	# Dragging from a cross erases every cross it passes, also in one undo step.
	# Pressing the drag's first cell right after a drag is not a double tap.
	await _drag_row(view, last)
	_expect(_count_row(board, last, Board.Mark.EMPTY) == board.size, "drag from a cross erased the row")
	_expect(main._undo.size() == undo_before + 2, "erase drag is a single undo step")
	main._on_undo()
	_expect(_count_row(board, last, Board.Mark.CROSS) == board.size, "undo restores the erased crosses")
	main._on_undo()
	_expect(board.get_mark(Vector2i(last, 3)) == Board.Mark.EMPTY, "undo removes the dragged crosses")

	# A swipe too fast for a motion event per cell still marks every cell it crosses.
	await _drag_row(view, last, true)
	_expect(_count_row(board, last, Board.Mark.CROSS) == board.size, "a fast swipe crosses every cell")
	await _drag_row(view, last, true)
	_expect(_count_row(board, last, Board.Mark.EMPTY) == board.size, "a fast swipe from a cross erases every cross")

	# Auto crosses: a crown rules out its row, column, region and neighbours.
	main._on_auto_cross_toggled(true)
	var manual := Vector2i(last, 0)
	await _click(view, manual)
	var crown := Vector2i(0, board.solution[0])
	undo_before = main._undo.size()
	await _right_click(view, crown)
	var all_ruled_out := true
	for row in board.size:
		for col in board.size:
			var cell := Vector2i(row, col)
			var ruled_out := row == crown.x or col == crown.y or board.region_at(cell) == board.region_at(crown) \
					or (absi(row - crown.x) <= 1 and absi(col - crown.y) <= 1)
			if ruled_out and cell != crown and cell != manual and board.get_mark(cell) != Board.Mark.AUTO_CROSS:
				all_ruled_out = false
	_expect(all_ruled_out, "placing a crown auto-crosses the cells it rules out")
	_expect(main._undo.size() == undo_before + 1, "crown and its auto crosses are one undo step")
	await _frames(2)
	_screenshot("auto_cross.png")
	await _right_click(view, crown)
	_expect(not board.marks.has(Board.Mark.AUTO_CROSS), "removing the crown removes its auto crosses")
	_expect(board.get_mark(manual) == Board.Mark.CROSS, "manual crosses survive crown removal")
	main._on_undo()
	_expect(board.get_mark(crown) == Board.Mark.CROWN and board.marks.has(Board.Mark.AUTO_CROSS), "undo restores crown and auto crosses")
	main._on_undo()
	_expect(not board.marks.has(Board.Mark.AUTO_CROSS) and board.get_mark(crown) == Board.Mark.EMPTY, "undo removes crown and auto crosses together")
	for i in 100:
		if board.marks.has(Board.Mark.CROWN):
			break
		main._on_hint()
		main._on_hint()
	_expect(board.marks.has(Board.Mark.AUTO_CROSS), "hinted crowns auto-cross too")
	main._on_clear()
	main._on_auto_cross_toggled(false)

	# Two touching crowns show as a conflict.
	await _right_click(view, Vector2i(0, 0))
	await _right_click(view, Vector2i(1, 1))
	_expect(board.conflicts()[0] == 1, "touching crowns are flagged in the UI board")
	await _frames(3)
	_screenshot("conflict.png")
	main._on_clear()

	# A hint explains a deduction first and only changes the board when applied.
	main._on_hint()
	var before: PackedInt32Array = board.marks.duplicate()
	_expect(not main._hint_label.text.is_empty(), "hint shows an explanation")
	_expect(main._hint_label.text[0] == main._hint_label.text[0].to_upper(), "explanation starts with a capital")
	_expect(not view.hint_targets.is_empty() and board.marks == before, "hint highlights cells without changing the board")
	_expect(main._hint_button.text == "Apply hint", "hint button offers to apply")
	await _frames(2)
	_screenshot("hint.png")
	var targets: PackedInt32Array = view.hint_targets
	main._on_hint()
	var applied := true
	for i in targets:
		if board.marks[i] == before[i]:
			applied = false
	_expect(applied and main._hint_label.text.is_empty() and main._hint_button.text == "Hint", "applying a hint changes the highlighted cells")
	main._on_hint()
	# A long hint can take a third line and shrink the board; click where it ends up.
	await _frames(1)
	await _click(view, Vector2i(board.size - 1, board.size - 1))
	_expect(main._hint_label.text.is_empty() and view.hint_targets.is_empty(), "editing the board dismisses the hint")
	main._on_clear()

	# Mistakes are pointed out before any deduction.
	var bad_crown := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _right_click(view, bad_crown)
	main._on_hint()
	_expect(main._hint_label.text == "This crown isn't part of the solution." and view.hint_targets == PackedInt32Array([board.index(bad_crown)]),
			"hint points out a wrong crown")
	main._on_hint()
	_expect(board.get_mark(bad_crown) == Board.Mark.EMPTY, "applying removes the wrong crown")
	var needed := Vector2i(1, board.solution[1])
	await _slow_click(view, needed)
	main._on_hint()
	_expect(main._hint_label.text == "This cell is crossed out, but it needs a crown.", "hint points out a wrong cross")
	main._on_hint()
	_expect(board.get_mark(needed) == Board.Mark.EMPTY, "applying removes the wrong cross")
	main._on_clear()

	# Solve through hints and check the win overlay.
	var steps := _solve_with_hints(main)
	await _frames(3)
	_expect(board.is_solved(), "hints solve the puzzle (%d steps)" % steps)
	_expect(main._win_overlay.visible and not view.interactive, "win overlay shows and board locks")
	_expect(main._best_label.text.is_empty(), "hinted solve does not record a best time")
	_screenshot("solved.png")

	main._go_to(main._number + 1)
	await _settle()
	_expect(main._number == 2 and not main._win_overlay.visible and main._board != board, "next puzzle loads")
	_screenshot("next.png")

	# Back to the menu, then the daily puzzle.
	main._show_menu()
	_expect(main._menu.visible and not main._running, "menu button returns to the menu and pauses")
	_expect(main._menu.continue_button.text == "Continue", "menu offers Continue once started")
	main._menu.daily_button.pressed.emit()
	await _settle()
	var daily: Board = main._board
	_expect(main._mode == main.Mode.DAILY and main.DAILY_SIZES.has(daily.size), "daily puzzle loads with a daily size")
	_expect(not main._size_picker.visible and not main._next_button.visible, "daily hides size and navigation")
	_expect(main._puzzle_label.text.begins_with("Daily"), "daily label shown")
	_screenshot("daily.png")

	main._show_menu()
	main._menu.daily_button.pressed.emit()
	await _settle()
	_expect(main._board.regions == daily.regions, "daily puzzle is the same when reopened")
	_solve_with_hints(main)
	await _frames(3)
	_expect(main._win_overlay.visible and not main._next_puzzle_button.visible, "daily win has no next puzzle")
	main._show_menu()
	_expect(main._menu._daily_detail.text.begins_with("Solved (hints used)"), "menu shows the daily as solved")

	# The archive: a calendar of past dailies that don't touch the streak.
	var today: String = main._today()
	var yesterday: String = main._day_before(today)
	main._menu.archive_button.pressed.emit()
	await _frames(2)
	var archive: Control = main._archive
	_expect(archive.visible and not main._menu.visible, "archive opens from the menu")
	_expect(archive.next_button.disabled, "archive can't go past the current month")
	_expect(_archive_day(archive, today).text.ends_with("✓"), "archive marks today's solved daily")
	archive.day_chosen.emit(yesterday)
	await _settle()
	_expect(main._mode == main.Mode.DAILY and main._daily_date == yesterday and main._board.regions != daily.regions,
			"archive opens a past daily")
	_expect(main._puzzle_label.text.ends_with(main._pretty_date(yesterday)) and main._back_button.text == "Back",
			"past daily shows its date and a Back button")
	await _slow_click(view, Vector2i(0, 0))
	main._leave_game()
	await _frames(2)
	_expect(archive.visible and not main._menu.visible, "leaving a past daily returns to the archive")
	archive.show_month_of(yesterday)
	_expect(_archive_day(archive, yesterday).text.ends_with("•"), "archive marks a started daily")
	archive.day_chosen.emit(yesterday)
	await _settle()
	_expect(main._board.get_mark(Vector2i(0, 0)) == Board.Mark.CROSS, "past daily progress is kept")
	var streak_before: int = main._progress.get_value("stats", "streak", 0)
	_solve_with_hints(main)
	await _frames(3)
	_expect(main._win_overlay.visible and main._progress.get_value("solved", main._daily_key(yesterday), false),
			"past daily can be solved")
	_expect(main._progress.get_value("stats", "streak", 0) == streak_before
			and main._progress.get_value("stats", "dailies_solved", 0) == 1, "past dailies don't count towards streaks")
	main._progress.set_value("best", main._daily_key(yesterday), 95.0)
	main._leave_game()
	archive.show_month_of(yesterday)
	_expect(_archive_day(archive, yesterday).text.ends_with("1:35"), "archive shows a past daily's best time")
	var crowned := _archive_day(archive, yesterday).get_children().filter(func(c: Node) -> bool:
		return c.get_script() != null)
	_expect(crowned.size() == 1, "a solved day wears a crown")
	_expect(not archive._trophy.visible, "the current month isn't over, so it has no trophy yet")

	# Trophies, with made-up dates: every daily of a finished month solved.
	var solved_days := {}
	var status := func(date: String) -> Dictionary:
		return {"solved": solved_days.has(date), "best": INF, "started": false}
	for day in range(15, 31):
		solved_days["2026-09-%02d" % day] = true
	_expect(Archive.month_complete(2026, 9, "2026-09-15", "2026-10-03", status),
			"a finished month with every daily solved earns a trophy, counting from the first daily")
	_expect(not Archive.month_complete(2026, 9, "2026-09-15", "2026-09-30", status), "but not while it's still going")
	solved_days.erase("2026-09-20")
	_expect(not Archive.month_complete(2026, 9, "2026-09-15", "2026-10-03", status), "a missed day means no trophy")
	solved_days["2026-09-20"] = true
	for day in range(1, 32):
		solved_days["2026-02-%02d" % day] = true
	_expect(Archive.month_complete(2026, 2, "2026-01-01", "2026-10-03", status), "short months end on their last day")
	var saved_status: Callable = archive.status_for
	var saved_first: String = archive.first_date
	var saved_last: String = archive.last_date
	archive.status_for = status
	archive.first_date = "2026-09-15"
	archive.last_date = "2026-10-03"
	archive.show_month_of("2026-09-20")
	await _frames(2)
	_expect(archive._trophy.visible and archive._summary.text == "Every daily solved!", "the archive shows the trophy")
	_screenshot("archive_trophy.png")
	archive.status_for = saved_status
	archive.first_date = saved_first
	archive.last_date = saved_last
	archive.show_month_of(yesterday)
	_expect(main._perfect_months() == 0, "no perfect months yet")
	await _frames(3)
	_screenshot("archive.png")
	archive.back.emit()
	_expect(main._menu.visible and not archive.visible, "archive back returns to the menu")

	main._menu.continue_button.pressed.emit()
	await _settle()
	_expect(main._mode == main.Mode.REGULAR and main._number == 2 and main._next_button.visible, "continue resumes the regular puzzles")
	main._on_theme_chosen("dark")
	await _right_click(view, Vector2i(0, 0))
	await _click(view, Vector2i(2, 2))
	await _frames(2)
	_screenshot("game_dark.png")
	main._on_theme_chosen("light")

	# The timer stops while the window is unfocused or the app is in the background.
	for pair in [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN],
			[Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]]:
		main._notification(pair[0])
		var paused_at: float = main._elapsed
		await _frames(5)
		_expect(main._elapsed == paused_at, "timer pauses on notification %d" % pair[0])
		main._notification(pair[1])
		await _frames(5)
		_expect(main._elapsed > paused_at, "timer resumes on notification %d" % pair[1])

	# The board in progress survives leaving it, switching puzzles and restarting.
	var solved_one := ConfigFile.new()
	solved_one.load(TEST_SAVE)
	_expect(not solved_one.has_section_key("in_progress", "%dx%d_medium_1" % [main._size, main._size]), "solved puzzle keeps no saved board")
	var in_progress: PackedInt32Array = main._board.marks.duplicate()
	main._elapsed = 42.0
	main._show_menu()
	main._menu.continue_button.pressed.emit()
	await _settle()
	_expect(main._board.marks == in_progress, "marks restored after visiting the menu")
	_expect(main._elapsed >= 42.0 and main._elapsed < 43.0, "timer restored after visiting the menu")
	main._go_to(3)
	await _settle()
	_expect(not main._board.marks.has(Board.Mark.CROWN), "another puzzle starts from its own board")
	main._go_to(2)
	await _settle()
	_expect(main._board.marks == in_progress, "marks restored after switching puzzles")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	main.queue_free()
	await _frames(2)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.save_path = TEST_SAVE
	root.add_child(reopened)
	await _frames(3)
	reopened._menu.continue_button.pressed.emit()
	await _settle()
	_expect(reopened._number == 2 and reopened._board.marks == in_progress, "marks restored after a restart")
	_expect(reopened._elapsed >= 42.0, "timer restored after a restart")
	reopened.queue_free()
	await _frames(2)

	# Difficulty picks a graded puzzle and keeps its own boards.
	var graded: Control = load("res://main.tscn").instantiate()
	graded.save_path = TEST_SAVE
	root.add_child(graded)
	await _frames(3)
	graded._menu.continue_button.pressed.emit()
	await _settle()
	var medium_regions: PackedInt32Array = graded._board.regions
	_expect(graded._difficulty_picker.visible and graded._difficulty == Generator.Difficulty.MEDIUM, "regular puzzles default to Medium")
	_expect(graded._difficulty_picker.item_count == 4 and graded._difficulty_picker.get_item_text(3) == "Hard+",
			"Hard+ is offered after Hard")
	for difficulty in [Generator.Difficulty.EASY, Generator.Difficulty.HARD, Generator.Difficulty.HARD_PLUS]:
		graded._difficulty_picker.select(difficulty)
		graded._on_difficulty_selected(difficulty)
		await _settle()
		var b: Board = graded._board
		_expect(graded._number == 1 and Generator.rates_as(b.size, b.regions, difficulty),
				"%s puzzle grades as %s" % [Generator.DIFFICULTY_NAMES[difficulty], Generator.DIFFICULTY_NAMES[difficulty]])
		_expect(graded._puzzle_key().contains(Generator.DIFFICULTY_NAMES[difficulty].to_lower()), "save key includes the difficulty")
	_screenshot("hard.png")
	graded._show_menu()
	_expect(graded._menu._continue_detail.text.contains("Hard"), "menu shows the chosen difficulty")
	graded._menu.daily_button.pressed.emit()
	await _settle()
	_expect(not graded._difficulty_picker.visible, "daily hides the difficulty picker")
	graded.queue_free()
	await _frames(2)
	await _check_challenge()
	await _frames(2)
	await _check_speed()
	await _frames(2)
	await _check_keyboard()
	await _frames(2)
	await _check_mistakes()
	await _frames(2)
	await _check_editor()
	await _frames(2)
	await _check_wide_layout()
	await _frames(2)
	await _check_gamepad()
	await _frames(2)
	await _check_weekly()
	await _frames(2)
	await _check_weekly_archive()
	await _frames(2)
	await _check_puzzle_code()
	await _frames(2)
	await _check_prefetch()
	await _frames(2)
	await _check_records()
	await _frames(2)
	await _check_silent_wolf()
	await _frames(2)
	await _check_timer_setting()
	await _frames(2)
	await _check_reminder()
	await _frames(2)
	_check_cloud_save()
	await _check_tutorial()
	await _frames(2)
	await _check_achievements()
	await _frames(2)
	await _check_stats()
	await _frames(2)
	await _check_patterns()
	await _frames(2)
	await _check_reduce_motion()
	await _frames(2)
	await _check_text_size()
	await _frames(2)
	await _check_pinch_zoom()
	await _frames(2)
	await _check_go_back()
	await _frames(2)
	await _check_solution()
	await _frames(2)
	await _check_calendar()
	await _frames(2)
	await _check_backup()
	await _frames(2)
	await _check_credits()
	await _frames(2)
	await _check_dim_finished()
	await _frames(2)
	_check_colour_names()
	await _frames(2)
	await _check_updater()
	await _frames(2)
	await _check_home_screen()
	await _frames(2)
	await _check_stats_export()
	await _frames(2)
	await _check_drills()
	await _frames(2)
	await _check_languages()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(1)


func _pad_press(button: JoyButton) -> void:
	await _pad_button(button, true)
	await _pad_button(button, false)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await _frames(1)


func _check_gamepad() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game.get_viewport().gui_release_focus()
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	_expect(game.get_viewport().gui_get_focus_owner() == game._menu.continue_button,
			"a gamepad's first press focuses the menu's first button")
	var ring := game._menu.continue_button.get_theme_stylebox("focus") as StyleBoxFlat
	_expect(ring != null and not ring.draw_center and ring.border_width_top > 0,
			"the focused button wears a ring")
	var ring_shown := func() -> bool: return game._menu.continue_button.get_theme_stylebox("focus") is StyleBoxFlat
	var click := func() -> void:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = Vector2(2, 2)
		for pressed in [true, false]:
			event.pressed = pressed
			Input.parse_input_event(event.duplicate())
		# Controls see theme changes a couple of frames later.
		await _frames(3)
	await click.call()
	_expect(not ring_shown.call(), "clicking or tapping hides the ring")
	await _pad_press(JOY_BUTTON_LEFT_STICK)
	await _frames(3)
	_expect(ring_shown.call(), "a gamepad shows the ring again")
	await click.call()
	await _key(KEY_SHIFT)
	await _frames(3)
	_expect(ring_shown.call(), "so does the keyboard")
	game._menu.continue_button.grab_focus()
	await _pad_press(JOY_BUTTON_A)
	await _settle()
	_expect(game._game.visible, "A presses the focused button")
	var view: Control = game._view
	var board: Board = game._board
	board.clear()
	game._undo.clear()
	view.grab_focus()
	view.cursor = Vector2i.ZERO
	view._cursor_shown = false
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	_expect(view.cursor_shown() and view.cursor == Vector2i.ZERO, "the first press shows the cursor without moving it")
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	_expect(view.cursor == Vector2i(0, 1), "the D-pad moves the cursor")
	await _pad_press(JOY_BUTTON_A)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.CROSS, "A crosses out")
	await _pad_press(JOY_BUTTON_Y)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.CROWN, "Y places a crown")
	await _pad_press(JOY_BUTTON_X)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.EMPTY, "X empties the cell")

	# Holding A while moving crosses out the way, as one move.
	var moves: int = game._undo.size()
	await _pad_button(JOY_BUTTON_A, true)
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	await _pad_button(JOY_BUTTON_A, false)
	var swept := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
	_expect(swept.all(func(cell: Vector2i) -> bool: return board.get_mark(cell) == Board.Mark.CROSS)
			and game._undo.size() == moves + 1, "holding A while moving crosses out each cell, as one move")
	# And from a cross, it clears them.
	await _pad_button(JOY_BUTTON_A, true)
	await _pad_press(JOY_BUTTON_DPAD_UP)
	await _pad_button(JOY_BUTTON_A, false)
	_expect(board.get_mark(Vector2i(2, 1)) == Board.Mark.EMPTY and board.get_mark(Vector2i(1, 1)) == Board.Mark.EMPTY
			and board.get_mark(Vector2i(0, 1)) == Board.Mark.CROSS, "holding A from a cross clears the way")
	await _pad_press(JOY_BUTTON_LEFT_SHOULDER)
	_expect(board.get_mark(Vector2i(1, 1)) == Board.Mark.CROSS, "LB undoes")
	await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	_expect(board.get_mark(Vector2i(1, 1)) == Board.Mark.EMPTY, "RB redoes")

	# The stick moves once per lean, not once per event.
	view.cursor = Vector2i(3, 3)
	await _pad_axis(JOY_AXIS_LEFT_X, 0.9)
	await _pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await _pad_axis(JOY_AXIS_LEFT_X, 0.0)
	_expect(view.cursor == Vector2i(3, 4), "a stick lean moves the cursor one cell")
	await _pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	_expect(view.cursor == Vector2i(2, 4), "the stick moves up and down too")
	# Held, it repeats.
	await _pad_button(JOY_BUTTON_DPAD_LEFT, true)
	await _wait_ms(view.REPEAT_DELAY_MS + view.REPEAT_EVERY_MS * 2 + 30)
	await _pad_button(JOY_BUTTON_DPAD_LEFT, false)
	_expect(view.cursor.y <= 1, "a held direction repeats")
	await _pad_button(JOY_BUTTON_DPAD_LEFT, true)
	await _wait_ms(view.REPEAT_DELAY_MS + view.REPEAT_EVERY_MS * 6)
	await _pad_button(JOY_BUTTON_DPAD_LEFT, false)
	_expect(view.cursor == Vector2i(2, 0), "a held direction stops at the edge")
	await _pad_press(JOY_BUTTON_DPAD_LEFT)
	_expect(view.cursor == Vector2i(2, board.size - 1), "pressing left at the edge wraps to the right side")
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	_expect(view.cursor == Vector2i(2, 0), "and right wraps back")
	await _pad_press(JOY_BUTTON_DPAD_UP)
	await _pad_press(JOY_BUTTON_DPAD_UP)
	await _pad_press(JOY_BUTTON_DPAD_UP)
	_expect(view.cursor == Vector2i(board.size - 1, 0), "pressing up at the top wraps to the bottom")
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	_expect(view.cursor == Vector2i(0, 0), "and down wraps back")

	await _pad_press(JOY_BUTTON_BACK)
	_expect(not game._hint_label.text.is_empty(), "Select asks for a hint")
	await _pad_press(JOY_BUTTON_START)
	_expect(game.get_viewport().gui_get_focus_owner() == game._hint_button, "Start moves to the buttons")
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	_expect(game.get_viewport().gui_get_focus_owner() == game._check_button, "the D-pad moves between them")
	await _pad_press(JOY_BUTTON_B)
	_expect(view.has_focus() and game._hint_button.focus_mode == Control.FOCUS_NONE and game._game.visible,
			"B goes back to the board, and the buttons stop taking focus")
	await _pad_press(JOY_BUTTON_B)
	await _frames(2)
	_expect(game._menu.visible, "B on the board goes back to the menu")

	game._show_editor()
	await _frames(3)
	var color: int = game._editor._color
	await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	_expect(game._editor._color == color + 1, "RB picks the editor's next colour")
	await _pad_press(JOY_BUTTON_LEFT_SHOULDER)
	await _pad_press(JOY_BUTTON_LEFT_SHOULDER)
	_expect(game._editor._color == wrapi(color - 1, 0, game._editor._size), "LB goes back, wrapping round")
	game._editor.view.grab_focus()
	game._editor.view.cursor = Vector2i.ZERO
	game._editor.view._cursor_shown = true
	await _pad_button(JOY_BUTTON_A, true)
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	await _pad_button(JOY_BUTTON_A, false)
	var painted: PackedInt32Array = game._editor.view.board.regions
	_expect(painted[0] == game._editor._color and painted[1] == game._editor._color, "A paints, and keeps painting while held")
	await _pad_press(JOY_BUTTON_B)
	await _frames(2)
	_expect(game._menu.visible, "B leaves the editor")
	game.queue_free()


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


func _check_wide_layout() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	_expect(view.get_parent() == game._column, "a tall screen keeps the one-column layout")
	var portrait := root.size
	root.size = Vector2i(1600, 900)
	await _frames(3)
	_expect(view.get_parent() == game._wide_row and game._hint_button.get_parent().get_parent() == game._side,
			"a wide screen puts the board beside the controls")
	_expect(game.get_window().content_scale_size == Vector2i(860, 640),
			"a wide window turns the base size on its side, so the interface keeps its size")
	_expect(view.size.x >= 480 and view.size.x + game.SIDE_WIDTH <= game._game.size.x,
			"the wide layout's board fills the space beside the controls")
	_expect(game._wide_row.get_child(0) == view, "the board starts on the left")
	game._settings.board_side_toggle.button_pressed = true
	await _frames(2)
	_expect(game._wide_row.get_child(-1) == view and game._progress.get_value("settings", "board_right") == true,
			"the setting moves the board to the right")
	var crown_cell := Vector2i(0, game._board.solution[0])
	await _right_click(view, crown_cell)
	_expect(game._board.get_mark(crown_cell) == Board.Mark.CROWN, "the board still plays in the wide layout")
	root.size = Vector2i(1200, 900)
	await _frames(3)
	_expect(view.get_parent() == game._column, "a 4:3 screen, too narrow for a good board beside the controls, keeps the column")
	root.size = Vector2i(2560, 1600)
	await _frames(3)
	_expect(view.get_parent() == game._wide_row, "a 16:10 tablet on its side gets the wide layout")
	game._show_menu()
	await _frames(2)
	_expect(game._menu._row.visible and game._menu._sections.all(func(section: Control) -> bool:
			return section.get_parent() == game._menu._row), "the menu spreads into columns on wide screens")
	var menu_rect: Rect2 = game._menu._row.get_global_rect()
	_expect(menu_rect.position.y >= 0.0 and menu_rect.end.y <= game._menu.size.y, "the wide menu fits the screen")
	game._show_settings()
	await _frames(2)
	_expect(game._settings.vibration_toggle.get_parent() != game._settings._box, "settings split into two columns on wide screens")
	game._show_stats()
	await _frames(2)
	_expect(not game._stats._content.vertical, "stats sit in two columns on wide screens")
	root.size = portrait
	await _frames(3)
	_expect(game.get_window().content_scale_size == Vector2i(640, 860), "a tall window keeps the base size upright")
	_expect(game._settings.vibration_toggle.get_parent() == game._settings._box and not game._menu._row.visible,
			"settings and the menu go back to one column")
	_expect(game._stats._content.vertical, "stats go back to one column")
	game._show_editor()
	root.size = Vector2i(1600, 900)
	await _frames(3)
	_expect(game._editor._wide_row.get_child(-1) == game._editor.view, "the editor's board follows the side setting")
	game._settings.board_side_toggle.button_pressed = false
	_expect(game._editor._wide_row.get_child(0) == game._editor.view, "and moves back to the left")
	root.size = portrait
	await _frames(3)
	_expect(view.get_parent() == game._column and game._column.get_child(2) == view
			and game._column.get_child(0).get_child(0) == game._back_button, "turning back puts everything in its column again")
	game._board.clear()
	game.queue_free()


## Applies hints until solved, checking no hint ever makes a wrong mark. Returns the step count.
func _solve_with_hints(game: Control) -> int:
	var board: Board = game._board
	var steps := 0
	var sound := true
	while not board.is_solved() and steps < 300:
		game._on_hint()
		var fallback: bool = game._hint_label.text.begins_with("There's no simple deduction")
		game._on_hint()
		steps += 1
		_expect(not fallback, "every hint is a deduction")
		for row in board.size:
			for col in board.size:
				var cell := Vector2i(row, col)
				var is_solution: bool = board.solution[row] == col
				if (board.get_mark(cell) == Board.Mark.CROWN and not is_solution) or (board.is_cross(cell) and is_solution):
					sound = false
	_expect(sound, "hints never make a wrong mark")
	return steps


func _check_challenge() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(game._menu._challenge_detail.text == "One life, no hints", "menu introduces the challenge")
	game._menu.challenge_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	var board: Board = game._board
	_expect(game._mode == game.Mode.CHALLENGE and not game._hint_button.visible, "challenge hides hints")
	_expect(not game._size_picker.visible and not game._prev_button.visible, "challenge hides puzzle pickers")
	_expect(board.size == 5 and Grader.grade(5, board.regions) == 1, "challenge starts with an easy 5x5")

	# Solving advances the run and keeps the run's time going.
	for row in board.size:
		await _right_click(view, Vector2i(row, board.solution[row]))
	await _frames(2)
	_expect(game._win_overlay.visible and game._run.level == 2, "solving moves the run to puzzle 2")
	_expect(game._next_puzzle_button.visible and game._next_puzzle_button.text == "Next puzzle",
			"a cleared Climb puzzle offers the next one")
	_expect(game._progress.get_value("challenge", "best", 0) == 1, "best run counts the solved puzzle")
	game._elapsed = 30.0
	game._run.elapsed = 30.0
	game._next_puzzle_button.pressed.emit()
	await _settle()
	board = game._board
	_expect(game._puzzle_label.text.begins_with("The Climb #2") and game._elapsed >= 30.0, "next puzzle continues the run")

	# Leaving mid-run keeps the run and its board.
	await _click(view, Vector2i(0, 0))
	var marks: PackedInt32Array = board.marks.duplicate()
	game._show_menu()
	_expect(game._menu._challenge_detail.text == "Run in progress · Puzzle 2", "menu offers the run in progress")
	game._menu.challenge_button.pressed.emit()
	await _settle()
	board = game._board
	_expect(game._run.level == 2 and board.marks == marks, "challenge resumes the same puzzle and board")

	# Undo still works for crosses, but a wrong crown ends the run.
	var wrong := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _right_click(view, wrong)
	_expect(not view.interactive and game._win_heading.text == "Out of lives", "a wrong crown ends the run")
	_expect(view.mistake == wrong, "the wrong crown is marked")
	_expect(game._run.is_empty() and not game._progress.has_section_key("challenge", "run"), "the run is cleared")
	_expect(not game._progress.has_section_key("in_progress", "challenge"), "the run's board is not kept")
	_expect(game._win_label.text.contains("1 puzzle solved"), "game over shows the score")
	await _frames(2)
	_screenshot("challenge_over.png")
	game._show_menu()
	_expect(game._menu._challenge_detail.text == "Best run: 1 puzzle", "menu shows the best run")

	game._menu.challenge_button.pressed.emit()
	await _settle()
	_expect(game._run.level == 1 and game._board.size == 5 and view.mistake == Vector2i(-1, -1), "a new run starts from the first puzzle")
	_expect(game.CHALLENGE_STAGES[-1] == [10, Generator.Difficulty.HARD], "challenge ramps up to 10x10 Hard")
	game._run.level = 99
	_expect(game._challenge_stage() == game.CHALLENGE_STAGES[-1], "the last stage repeats")
	game.queue_free()


func _check_speed() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var progress: ConfigFile = game._progress
	var boards: int = game.SPEED_STAGES.size()
	_expect(game._menu._speed_detail.text == "%d boards, one clock" % boards, "menu introduces speed runs")
	game._menu.speed_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	_expect(game._mode == game.Mode.SPEED and not game._hint_button.visible and not game._size_picker.visible,
			"speed runs hide hints and puzzle pickers")
	_expect(game._puzzle_label.text == "Speed run · 1 of %d" % boards, "the label counts the boards")
	_expect(not game._win_leaderboard_button.visible, "speed runs have no leaderboard")

	# Each board flows into the next on the same clock, which stops in between.
	for level in boards:
		var board: Board = game._board
		var stage: Array = game.SPEED_STAGES[level]
		_expect(board.size == stage[0] and Generator.rates_as(board.size, board.regions, stage[1]),
				"speed board %d is a %dx%d %s" % [level + 1, stage[0], stage[0], Generator.DIFFICULTY_NAMES[stage[1]]])
		game._elapsed = 10.0 * (level + 1)
		for row in board.size:
			await _right_click(view, Vector2i(row, board.solution[row]))
		if level == boards - 1:
			break
		_expect(not game._win_overlay.visible and not game._running, "a solved board pauses without the win panel")
		await create_timer(game.SPEED_PAUSE + 0.1).timeout
		await _settle()
		_expect(game._speed_run.level == level + 2 and game._elapsed >= 10.0 * (level + 1),
				"board %d follows on with the run's time" % (level + 2))
	await _frames(2)
	var total := 10.0 * boards
	_expect(game._win_overlay.visible and game._win_heading.text == "Finished!"
			and game._win_label.text == "Time: %s" % game._format_time(total), "the last board shows the run's time")
	# The clock also runs for the frames the clicks take.
	var best: float = progress.get_value("speed", "best", INF)
	_expect(best >= total and best < total + 1.0, "the run's time is the best")
	_expect(game._best_label.text == "Best %s" % game._format_time(total), "the game shows the best run")
	_expect(game._next_puzzle_button.visible and game._next_puzzle_button.text == "New run", "a finished run offers a new one")
	_screenshot("speed_finished.png")

	# A slower run doesn't replace the best, and the panel says what it was.
	game._next_puzzle_button.pressed.emit()
	await _settle()
	_expect(game._speed_run.level == 1 and game._elapsed < 1.0, "a new run starts from the first board at 0:00")
	game._speed_run.level = boards
	game._speed_run.elapsed = 100.0
	game._load_puzzle()
	await _settle()
	for row in game._board.size:
		await _right_click(view, Vector2i(row, game._board.solution[row]))
	await _frames(2)
	_expect(progress.get_value("speed", "best", INF) == best
			and game._win_label.text.contains("Best: %s" % game._format_time(total)), "a slower run keeps the best")

	# Leaving between boards abandons the run, and nothing about it is saved.
	game._next_puzzle_button.pressed.emit()
	await _settle()
	for row in game._board.size:
		await _right_click(view, Vector2i(row, game._board.solution[row]))
	game._show_menu()
	await create_timer(game.SPEED_PAUSE + 0.1).timeout
	_expect(game._menu.visible and not game._game.visible, "leaving between boards stays on the menu")
	_expect(not progress.has_section_key("in_progress", "speed") and not progress.has_section_key("in_progress", ""),
			"speed boards aren't kept")
	_expect(game._menu._speed_detail.text == "Best: %s" % game._format_time(total), "menu shows the best run")
	_expect(progress.get_value("stats", "speed_runs", 0) == 3 and progress.get_value("stats", "speed_finished", 0) == 2,
			"runs played and finished are counted")
	game._menu.speed_button.pressed.emit()
	await _settle()
	_expect(game._speed_run.level == 1 and game._board.size == game.SPEED_STAGES[0][0], "the menu starts a fresh run")
	game.queue_free()


func _check_keyboard() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	var board: Board = game._board
	game._on_clear()
	game._undo.clear()
	await _frames(1)
	_expect(view.has_focus() and not view.cursor_shown(), "the board takes the keyboard, cursor hidden")

	# The first key only shows the cursor; then keys move it and mark cells.
	view.cursor = Vector2i.ZERO
	await _key(KEY_RIGHT)
	_expect(view.cursor_shown() and view.cursor == Vector2i.ZERO and board.marks.count(Board.Mark.EMPTY) == board.marks.size(),
			"the first key shows the cursor without acting")
	await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	_expect(view.cursor == Vector2i(1, 1), "arrow keys move the cursor")
	await _key(KEY_UP)
	await _key(KEY_LEFT)
	_expect(view.cursor == Vector2i.ZERO, "arrow keys move back to the corner")
	await _key(KEY_LEFT)
	_expect(view.cursor == Vector2i(0, board.size - 1), "left off the edge wraps to the right side")
	await _key(KEY_RIGHT)
	_expect(view.cursor == Vector2i.ZERO, "right off the edge wraps to the left side")
	await _key(KEY_UP)
	_expect(view.cursor == Vector2i(board.size - 1, 0), "up off the top wraps to the bottom")
	await _key(KEY_DOWN)
	_expect(view.cursor == Vector2i.ZERO, "down off the bottom wraps to the top")
	# A held key repeating stops at the edge instead of going round and round.
	var held := InputEventKey.new()
	held.keycode = KEY_LEFT
	held.physical_keycode = KEY_LEFT
	held.pressed = true
	held.echo = true
	Input.parse_input_event(held)
	await _frames(1)
	await _key(KEY_LEFT)
	_expect(view.cursor == Vector2i(0, board.size - 1), "a held key doesn't wrap")
	await _key(KEY_RIGHT)
	await _key(KEY_SPACE)
	_expect(board.get_mark(Vector2i.ZERO) == Board.Mark.CROSS, "Space crosses out")
	await _key(KEY_SPACE)
	_expect(board.get_mark(Vector2i.ZERO) == Board.Mark.EMPTY, "Space again clears the cross")
	await _key(KEY_ENTER)
	_expect(board.get_mark(Vector2i.ZERO) == Board.Mark.CROWN, "Enter places a crown")
	await _key(KEY_BACKSPACE)
	_expect(board.get_mark(Vector2i.ZERO) == Board.Mark.EMPTY, "Backspace empties the cell")
	await _key(KEY_RIGHT, true)
	await _key(KEY_RIGHT, true)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.CROSS and board.get_mark(Vector2i(0, 2)) == Board.Mark.CROSS,
			"Shift+arrows cross out the cells passed")

	# Undo and redo, by keys and buttons.
	_expect(game._redo_button.disabled, "nothing to redo yet")
	await _key(KEY_Z, false, true)
	_expect(board.get_mark(Vector2i(0, 2)) == Board.Mark.EMPTY and not game._redo_button.disabled, "Ctrl+Z undoes")
	await _key(KEY_Z, false, true)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.EMPTY, "Ctrl+Z undoes again")
	await _key(KEY_Z, true, true)
	_expect(board.get_mark(Vector2i(0, 1)) == Board.Mark.CROSS and board.get_mark(Vector2i(0, 2)) == Board.Mark.EMPTY,
			"Ctrl+Shift+Z redoes one step")
	game._redo_button.pressed.emit()
	_expect(board.get_mark(Vector2i(0, 2)) == Board.Mark.CROSS and game._redo_button.disabled, "the Redo button redoes the rest")
	await _key(KEY_Z, false, true)
	await _key(KEY_SPACE)
	_expect(game._redo_button.disabled and game._redo.is_empty(), "a new move clears redo")
	_expect(view.has_focus(), "buttons leave the keyboard with the board")

	# H asks for a hint; a click hides the cursor.
	await _key(KEY_H)
	_expect(not game._hint_label.text.is_empty(), "H gives a hint")
	await _click(view, Vector2i(board.size - 1, board.size - 1))
	_expect(not view.cursor_shown(), "a click hides the cursor")
	game._on_clear()
	await _frames(1)

	# Solve by keyboard, then Enter goes on to the next puzzle.
	var number: int = game._number
	await _key(KEY_DOWN)
	for row in board.size:
		var target := Vector2i(row, board.solution[row])
		while view.cursor.x < target.x:
			await _key(KEY_DOWN)
		while view.cursor.y < target.y:
			await _key(KEY_RIGHT)
		while view.cursor.y > target.y:
			await _key(KEY_LEFT)
		await _key(KEY_C)
	_expect(board.is_solved() and game._win_overlay.visible, "the keyboard can solve a puzzle")
	await _overlay_shown(game)
	_expect(game._next_puzzle_button.has_focus(), "the win panel's Next puzzle takes the keyboard")
	await _key(KEY_ENTER)
	await _settle()
	_expect(game._number == number + 1 and view.has_focus(), "Enter moves on, and the board has the keyboard again")
	game.queue_free()


func _check_mistakes() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	var board: Board = game._board
	game._on_clear()
	game._hinted = false
	_expect(game._check_button.visible, "regular puzzles offer Check")
	game._check_button.pressed.emit()
	_expect(game._hint_label.text == "No mistakes so far." and game._hinted, "Check on a clean board, counted as a hint")

	# A wrong crown and a crossed-out crown cell are two mistakes, without saying where.
	var wrong := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _right_click(view, wrong)
	var needed := Vector2i(board.size - 1, board.solution[board.size - 1])
	await _slow_click(view, needed)
	_expect(game._hint_label.text.is_empty(), "a move clears Check's message")
	game._check_button.pressed.emit()
	_expect(game._hint_label.text == "2 mistakes so far." and view.hint_targets.is_empty(),
			"Check counts mistakes without pointing them out")
	game._on_clear()

	# The auto crosses a wrong crown brings don't count again.
	game._on_auto_cross_toggled(true)
	await _right_click(view, wrong)
	game._check_button.pressed.emit()
	_expect(game._hint_label.text == "1 mistake so far.", "a wrong crown's auto crosses aren't extra mistakes")
	game._on_auto_cross_toggled(false)
	game._on_clear()

	for mode in [game.Mode.CHALLENGE, game.Mode.SPEED, game.Mode.TUTORIAL]:
		game._start(mode)
		await _settle()
		_expect(not game._check_button.visible, "no Check in mode %d" % mode)
	game.queue_free()


## Waits for the win panel to finish appearing, which takes longer on a busy
## machine than any fixed wait would allow for.
func _overlay_shown(game: Control) -> void:
	var started := Time.get_ticks_msec()
	while game._overlay_tween and game._overlay_tween.is_running() and Time.get_ticks_msec() - started < 10000:
		await process_frame


func _check_editor() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var progress: ConfigFile = game._progress
	var solved_before: int = progress.get_value("stats", "solved_5", 0)
	game._menu.create_button.pressed.emit()
	await _frames(3)
	var editor: Control = game._editor
	_expect(editor.visible and not game._menu.visible and editor.view.has_focus(), "Create opens the editor")
	editor.size_picker.select(0)
	editor.size_picker.item_selected.emit(0)
	await _frames(2)
	var view: Control = editor.view
	_expect(view.board.size == 5 and editor.status_label.text == "25 cells left to paint."
			and editor.play_button.disabled and editor.share_button.disabled, "a blank board says what's left")

	# Painting by dragging along rows, one colour each.
	for row in 4:
		editor._palette.get_child(row).pressed.emit()
		await _drag_row(view, row)
	_expect(view.board.regions.slice(0, 5) == PackedInt32Array([0, 0, 0, 0, 0])
			and editor.status_label.text == "5 cells left to paint.", "dragging paints the cells in the chosen colour")
	editor._palette.get_child(3).pressed.emit()
	await _drag_row(view, 4)
	_expect(editor.status_label.text == "1 colour isn't used yet.", "every colour must be used")
	editor._palette.get_child(4).pressed.emit()
	await _drag_row(view, 4)
	_expect(editor.status_label.text.begins_with("More than one solution"), "stripes have many solutions")
	await _click(view, Vector2i(0, 0))
	_expect(editor.status_label.text == "The grey region is split in two. Each colour needs to be one piece.",
			"a split region is named")
	_expect(progress.get_value("editor", "size", 0) == 5 and progress.get_value("editor", "regions", PackedInt32Array())[0] == 4,
			"the draft is kept")

	# A fair layout can be played and shared.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var puzzle := Generator.generate(5, Generator.Difficulty.EASY, rng)
	editor.open(5, puzzle.regions)
	# As painting it would, keep it as the draft.
	editor.changed.emit(5, editor.view.board.regions)
	_expect(editor.status_label.text == "One solution · Easy" and not editor.play_button.disabled, "a fair layout shows its difficulty")
	var code: String = editor.code()
	editor.share_button.pressed.emit()
	_expect(editor.status_label.text == code and editor.share_button.text == "Copied!", "Share shows the code")
	editor.play_button.pressed.emit()
	await _settle()
	_expect(game._mode == game.Mode.CUSTOM and game._game.visible and game._puzzle_label.text == "Custom puzzle · Easy"
			and game._back_button.text == "Back" and game._code_button.visible and not game._size_picker.visible,
			"Play opens the puzzle")
	game._show_code()
	_expect(game._code_label.text == code, "the code panel shows the custom code")
	game._hide_code()
	var board: Board = game._board
	game._elapsed = 30.0
	for row in board.size:
		await _right_click(game._view, Vector2i(row, board.solution[row]))
	await _frames(2)
	_expect(game._win_overlay.visible and game._win_label.text == "Time: 0:30", "a custom puzzle can be solved")
	_expect(progress.get_value("best", "custom_" + code, INF) < 31.0 and progress.get_value("stats", "solved_5", 0) == solved_before,
			"custom solves keep a best time but count for no stats")
	game._win_back_button.pressed.emit()
	await _frames(2)
	_expect(editor.visible and editor.code() == code, "Back returns to the editor and its draft")

	# Friends open it from the code; a numbered code goes back to regular play.
	game._menu.continue_button.pressed.emit()
	await _settle()
	game._show_code()
	game._code_entry.text = "Try this Crowns puzzle: %s" % code
	game._enter_code()
	await _settle()
	_expect(game._mode == game.Mode.CUSTOM and game._board.regions == CustomPuzzle.canonical(puzzle.regions)
			and game._back_button.text == "Menu", "a custom code from a friend opens the puzzle")
	game._show_code()
	game._code_entry.text = "6E-3"
	game._enter_code()
	await _settle()
	_expect(game._mode == game.Mode.REGULAR and game._size == 6 and game._number == 3, "a numbered code returns to regular play")
	game._show_code()
	# All one colour: a real layout, but not a fair puzzle.
	game._code_entry.text = "5C-AAAAAAAAAAAAAA"
	game._enter_code()
	_expect(game._code_error.visible and game._mode == game.Mode.REGULAR, "a custom code without one solution is refused")
	game._hide_code()
	game.queue_free()


func _key(keycode: Key, shift := false, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)


func _check_puzzle_code() -> void:
	var sizes := [5, 6, 7, 8, 9, 10]
	_expect(PuzzleCode.encode(8, Generator.Difficulty.HARD, 142) == "8H-142", "codes read size, difficulty, number")
	_expect(PuzzleCode.encode(8, Generator.Difficulty.HARD_PLUS, 3) == "8X-3"
			and PuzzleCode.decode("8x-3", sizes).get("difficulty") == Generator.Difficulty.HARD_PLUS,
			"Hard+ codes use X, as Hard has H")
	_expect(PuzzleCode.decode("8H-142", sizes) == {"size": 8, "difficulty": Generator.Difficulty.HARD, "number": 142},
			"a code decodes")
	_expect(PuzzleCode.decode("Try this Crowns puzzle: 6e 12!", sizes).get("number") == 12
			and PuzzleCode.decode("10m#3", sizes).get("size") == 10, "codes are found loosely in pasted text")
	_expect(PuzzleCode.decode("4H-1", sizes).is_empty() and PuzzleCode.decode("8Q-1", sizes).is_empty()
			and PuzzleCode.decode("8H-0", sizes).is_empty() and PuzzleCode.decode("hello", sizes).is_empty(),
			"bad codes are refused")

	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._start(game.Mode.REGULAR)
	await _settle()
	_expect(game._code_button.visible, "regular puzzles offer a code")
	game._show_code()
	_expect(game._code_overlay.visible and not game._running, "the code panel opens and pauses the timer")
	_expect(game._code_label.text == PuzzleCode.encode(game._size, game._difficulty, game._number),
			"the panel shows this puzzle's code")
	game._copy_code()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_expect(DisplayServer.clipboard_get().contains(game._code_label.text), "copying puts the code on the clipboard")
	_expect(game._code_copy_button.text == "Copied!", "the copy button confirms")
	game._code_entry.text = "nonsense"
	game._enter_code()
	_expect(game._code_overlay.visible and game._code_error.visible, "a bad code shows an error")
	game._hide_code()
	_expect(not game._code_overlay.visible and game._running, "closing resumes the timer")

	game._show_code()
	game._code_entry.text = "9h-77"
	game._enter_code()
	await _settle()
	var regions: PackedInt32Array = game._board.regions
	_expect(not game._code_overlay.visible and game._size == 9 and game._difficulty == Generator.Difficulty.HARD
			and game._number == 77 and game._puzzle_label.text == "Puzzle #77", "entering a code opens that puzzle")
	_expect(game._size_picker.get_selected_id() == 9 and game._difficulty_picker.selected == Generator.Difficulty.HARD,
			"the pickers follow the code")
	game._go_to(76)
	await _settle()
	game._go_to(77)
	await _settle()
	_expect(game._board.regions == regions, "a code gives the same board as browsing to it")

	game._start(game.Mode.WEEKLY)
	await _settle()
	_expect(not game._code_button.visible, "only regular puzzles have codes")
	game.queue_free()


func _check_prefetch() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._start(game.Mode.REGULAR)
	await _settle()
	var next: Array = game._puzzle_spec(1)
	_expect(game._prefetch.get("spec") == next, "the next regular puzzle generates in the background")
	while not WorkerThreadPool.is_task_completed(game._prefetch.task):
		await process_frame
	var number: int = game._number
	game._go_to(number + 1)
	_expect(not game._generating and game._number == number + 1, "Next is instant once the next puzzle is ready")
	var rng := RandomNumberGenerator.new()
	rng.seed = next[2]
	_expect(game._board.regions == Generator.generate(next[0], next[1], rng).regions,
			"the background puzzle is the same as one made on the spot")
	_expect(game._prefetch.get("spec") == game._puzzle_spec(1), "and the one after starts generating")

	game._go_to(number)
	await _settle()
	_expect(game._prefetch.get("spec") == game._puzzle_spec(1) and game._tasks.size() >= 1,
			"going back replaces the guess")
	game._start(game.Mode.CHALLENGE)
	await _settle()
	_expect(game._prefetch.get("spec") == game._puzzle_spec(1) and game._puzzle_spec(1)[2] == hash([game._run.seed, game._run.level + 1]),
			"The Climb generates its next level in the background")
	game._start(game.Mode.DAILY)
	await _settle()
	game.queue_free()
	await _frames(2)
	_expect(not is_instance_valid(game), "a game with background work still running closes cleanly")


func _check_silent_wolf() -> void:
	_expect(SilentWolf.clean_name("  Ada\nLovelace the Great  ") == "Ada Lovelace the" and SilentWolf.time_score(61.5) == -61500,
			"names are trimmed to one short line and times become negative milliseconds")
	var raw := [
		{"pn": "Ada", "s": -90000, "t": 1.0, "md": {"id": "a"}},
		{"pn": "Ada L", "s": -70000, "t": 2.0, "md": {"id": "a"}},
		{"pn": "Ada", "s": -80000, "t": 3.0, "md": {"id": "b"}},
		{"pn": "Old", "s": -60000, "t": 0.5},
	]
	var ranked := SilentWolf.best_per_player(raw)
	_expect(ranked.map(func(entry: Dictionary) -> String: return "%s %d" % [entry.name, entry.score])
			== ["Old -60000", "Ada L -70000", "Ada -80000"],
			"each player keeps their best score under their latest name, and same names stay apart by id")

	# Solves here would change the stats later checks count on, so the save is put back after.
	var before := FileAccess.get_file_as_string(TEST_SAVE)
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var wolf: SilentWolf = game._silent_wolf
	_expect(not wolf.available() and not game._has_leaderboards() and not game._settings.silent_wolf_toggle.visible,
			"without a key there are no SilentWolf boards or setting")
	wolf.api_key = "test"
	_expect(game._silent_wolf_on() and game._has_leaderboards(), "with a key, SilentWolf is on by default")
	game._menu.leaderboards_button.visible = true

	game._start(game.Mode.DAILY)
	await _settle()
	var board: Board = game._board
	game._elapsed = 83.4
	for row in board.size:
		await _right_click(game._view, Vector2i(row, board.solution[row]))
	await _frames(2)
	var id: String = game._player_id()
	var player_name: String = game._player_name()
	_expect(id.length() == 16 and player_name.begins_with("Player "), "players get a random id and a placeholder name")
	var daily_saves := wolf.sent.filter(func(request: Array) -> bool:
		return request.slice(0, 4) == ["save", "daily-" + game._today(), id, player_name])
	_expect(daily_saves.size() == 1 and absi(daily_saves[0][4] + 83400) < 1000, "today's daily time goes to today's board")
	_expect(game._win_leaderboard_button.visible, "the win panel offers the leaderboard")

	wolf.fake_scores["daily-" + game._today()] = [
		{"pn": "Speedy", "s": -50000, "t": 1.0, "md": {"id": "x"}},
		{"pn": player_name, "s": -83400, "t": 2.0, "md": {"id": id}},
	]
	game._win_leaderboard_button.pressed.emit()
	await _frames(3)
	var screen: Control = game._leaderboards
	_expect(screen.visible and not game._game.visible and screen.kind() == "daily", "it opens on the daily board")
	var cells: Array = screen._list.get_children().map(func(label: Label) -> String: return label.text)
	_expect(cells == ["1", "Speedy", "0:50", "2", player_name, "1:23"], "the board lists ranks, names and times")
	_expect(screen._list.get_child(4).has_theme_color_override("font_color"), "the player's own row stands out")
	_screenshot("leaderboard.png")

	screen.name_entry.text = "  Crowned One  "
	screen.name_entry.text_submitted.emit(screen.name_entry.text)
	_expect(game._player_name() == "Crowned One", "the player can rename themselves")
	screen._tabs["climb"].pressed.emit()
	await _frames(2)
	_expect(screen.kind() == "climb" and screen._status.text == "No scores yet. Be the first!", "empty boards say so")
	screen.back.emit()
	await _frames(2)
	_expect(game._game.visible and game._win_overlay.visible and not screen.visible,
			"back returns to the solved puzzle")

	game._start(game.Mode.CHALLENGE)
	await _settle()
	board = game._board
	for row in board.size:
		await _right_click(game._view, Vector2i(row, board.solution[row]))
	await _frames(2)
	_expect(["save", "climb", id, "Crowned One", 1] in wolf.sent, "Climb runs go up under the new name")

	wolf.pending = [["solved", id, "Crowned One", 3]]
	wolf.api_key = ""
	await wolf.retry()
	_expect(wolf.pending.size() == 1, "scores wait while the boards can't be reached")
	wolf.api_key = "test"
	await wolf.retry()
	_expect(wolf.pending.is_empty() and ["save", "solved", id, "Crowned One", 3] in wolf.sent, "and go up later")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("online", "pending", null) == [], "waiting scores are saved, so they survive a restart")

	game._show_menu()
	game._menu.leaderboards_chosen.emit()
	await _frames(2)
	_expect(screen.visible and not game._menu.visible, "the menu opens the leaderboards")
	screen.back.emit()
	await _frames(2)
	_expect(game._menu.visible and not screen.visible, "and back returns to the menu")

	# The Settings switch, for Android players who only want Google Play Games.
	game._on_silent_wolf_toggled(false)
	var sent_before := wolf.sent.size()
	game._submit_online("solved", 9)
	_expect(not game._silent_wolf_on() and wolf.sent.size() == sent_before and not game._menu.leaderboards_button.visible,
			"turning SilentWolf off stops sending scores and, without Play Games, hides the leaderboards")
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "silent_wolf", true) == false, "the choice is saved")
	game._on_silent_wolf_toggled(true)
	_expect(game._silent_wolf_on() and game._menu.leaderboards_button.visible, "and turning it back on restores them")
	game.queue_free()
	await _frames(2)
	var restore := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	restore.store_string(before)
	restore.close()


func _check_timer_setting() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(game._settings.timer_toggle.button_pressed, "the timer shows by default")
	game._start(game.Mode.REGULAR)
	await _settle()
	_expect(game._timer_label.visible and game._best_label.visible, "puzzles show the timer")
	game._settings.timer_toggle.button_pressed = false
	_expect(not game._timer_label.visible and not game._best_label.visible, "the setting hides the timer at once")
	_expect(game._progress.get_value("settings", "show_timer", true) == false, "and is saved")
	var elapsed: float = game._elapsed
	await _frames(10)
	_expect(game._elapsed > elapsed, "the clock keeps running while hidden")
	game._start(game.Mode.DAILY)
	await _settle()
	_expect(not game._timer_label.visible, "and stays hidden in other modes")
	game._settings.timer_toggle.button_pressed = true
	_expect(game._timer_label.visible, "turning it back on shows it again")
	game.queue_free()


func _check_records() -> void:
	var before := FileAccess.get_file_as_string(TEST_SAVE)
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var progress: ConfigFile = game._progress
	# An older save: best times but no records kept yet.
	progress.set_value("best", "6x6_hard_801", 150.0)
	progress.set_value("best", "6x6_hard_802", 140.0)
	progress.set_value("best", "6x6_medium_801", 30.0)
	_expect(game._size_record(6, Generator.Difficulty.HARD) == 140.0 and progress.get_value("stats", "best_6_hard") == 140.0,
			"a record is worked out from an old save's best times, per size and difficulty")
	var solve := func(number: int, seconds: float, size := 6, difficulty := Generator.Difficulty.HARD) -> void:
		game._size = size
		game._difficulty = difficulty
		game._number = number
		game._start(game.Mode.REGULAR)
		await _settle()
		var board: Board = game._board
		for row in board.size:
			board.set_mark(Vector2i(row, board.solution[row]), Board.Mark.CROWN)
		game._elapsed = seconds
		game._check_win()
		await _frames(2)
	await solve.call(803, 150.0)
	_expect(not game._win_label.text.contains("record"), "a slower solve sets no record")
	await solve.call(804, 95.0)
	_expect(game._win_label.text.contains("New 6×6 Hard record!") and game._win_label.text.contains("Previous best: 2:20"),
			"a faster first solve announces the record and the time it beat")
	_expect(progress.get_value("stats", "best_6_hard") == 95.0, "and keeps it")
	progress.set_value("solved", "6x6_hard_805", true)
	await solve.call(805, 50.0)
	_expect(not game._win_label.text.contains("record") and progress.get_value("stats", "best_6_hard") == 95.0,
			"replaying a puzzle already solved can't set a record")
	await solve.call(806, 20.0, 7, Generator.Difficulty.EASY)
	_expect(not game._win_label.text.contains("record"), "the first solve at a size and difficulty sets one quietly")
	game.queue_free()
	await _frames(2)
	var restore := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	restore.store_string(before)
	restore.close()


func _check_weekly() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var week: String = game._week_start()
	var start := Time.get_unix_time_from_datetime_string(week)
	var today := Time.get_unix_time_from_datetime_string(game._today())
	_expect(Time.get_datetime_dict_from_unix_time(start).weekday == Time.WEEKDAY_MONDAY
			and today - start == game._days_into_week() * 86400 and today - start < 7 * 86400,
			"the weekly challenge starts on the latest Monday")
	var days_left: int = 7 - game._days_into_week()
	_expect(game._menu._weekly_detail.text.begins_with("Week of " + game._pretty_date(week))
			and game._menu._weekly_detail.text.ends_with("%d day%s left" % [days_left, "" if days_left == 1 else "s"]),
			"menu shows the week and the days left")
	game._sunday_weeks = true
	var play_week: String = game._week_start()
	var play_start := Time.get_unix_time_from_datetime_string(game._week_first_day(play_week))
	_expect(Time.get_datetime_dict_from_unix_time(play_start).weekday == Time.WEEKDAY_SUNDAY
			and today - play_start == game._weekday() * 86400 and today - play_start < 7 * 86400,
			"the Play build's week starts on the latest Sunday, with Play Games' leaderboards")
	var next_monday := Time.get_date_string_from_unix_time(start + 7 * 86400)
	_expect(play_week == (next_monday if game._weekday() == Time.WEEKDAY_SUNDAY else week),
			"and plays the same puzzle, named by its Monday, from a day earlier")
	game._sunday_weeks = false

	game._menu.weekly_button.pressed.emit()
	await _settle()
	var board: Board = game._board
	_expect(game._mode == game.Mode.WEEKLY and board.size == game.WEEKLY_SIZE
			and Grader.grade(board.size, board.regions) == Generator.Difficulty.HARD + 1, "the weekly is a hard 10x10")
	_expect(game._hint_button.visible and not game._size_picker.visible and not game._next_button.visible,
			"the weekly allows hints and hides puzzle pickers")
	_expect(game._puzzle_label.text == "Weekly · " + game._pretty_date(week), "weekly label shows the week")
	_screenshot("weekly.png")
	await _click(game._view, Vector2i(0, 0))
	game._show_menu()
	game._menu.weekly_button.pressed.emit()
	await _settle()
	_expect(game._board.regions == board.regions and game._board.get_mark(Vector2i(0, 0)) == Board.Mark.CROSS,
			"the weekly is the same puzzle when reopened, with its progress")

	var unhinted: int = game._progress.get_value("stats", "puzzles_unhinted", 0)
	board = game._board
	game._elapsed = 300.0
	for row in board.size:
		await _right_click(game._view, Vector2i(row, board.solution[row]))
	await _frames(2)
	_expect(game._win_overlay.visible and not game._next_puzzle_button.visible, "weekly win has no next puzzle")
	_expect(game._progress.get_value("best", game._weekly_key(week), INF) < 301.0
			and game._progress.get_value("stats", "weeklies_solved", 0) == 1, "the weekly time and solve are recorded")
	_expect(game._progress.get_value("stats", "puzzles_unhinted", 0) == unhinted,
			"the weekly doesn't count towards the numbered puzzles' leaderboard")
	game._show_menu()
	_expect(game._menu._weekly_detail.text.begins_with("Solved in 5:00"), "menu shows the weekly as solved")
	await _frames(3)
	_screenshot("menu_weekly.png")
	game.queue_free()


func _check_weekly_archive() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var current: String = game._week_start()
	var last_week := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(current) - 7 * 86400)
	game._menu.weekly_archive_button.pressed.emit()
	await _frames(3)
	var archive: Control = game._weekly_archive
	_expect(archive.visible and not game._menu.visible, "the weekly Archive button opens the weekly archive")
	var buttons: Array = archive._list.get_children()
	var weeks := (Time.get_unix_time_from_datetime_string(current)
			- Time.get_unix_time_from_datetime_string(game.WEEKLY_FIRST)) / (7 * 86400) + 1
	_expect(buttons.size() == weeks, "every week from the first is listed")
	_expect((buttons[0] as Button).text.begins_with("Week of " + game._pretty_date(current))
			and "This week" in (buttons[0] as Button).text, "newest first, starting with this week")
	_expect((buttons[-1] as Button).text.begins_with("Week of " + game._pretty_date(game.WEEKLY_FIRST)),
			"oldest last")

	var solved_before: int = game._progress.get_value("stats", "weeklies_solved", 0)
	(buttons[1] as Button).pressed.emit()
	await _settle()
	_expect(game._mode == game.Mode.WEEKLY and game._week == last_week, "a past week opens its own puzzle")
	_expect(game._puzzle_label.text == "Weekly · " + game._pretty_date(last_week), "the label names that week")
	var spec: Array = game._puzzle_spec()
	_expect(spec[2] == hash(["weekly", last_week]), "the same puzzle everyone had that week")
	_expect(not game._has_mode_leaderboard(), "past weeks have no leaderboard")
	var board: Board = game._board
	for row in board.size:
		await _right_click(game._view, Vector2i(row, board.solution[row]))
	await _frames(2)
	_expect(game._win_overlay.visible and game._win_back_button.text == "Back", "a past week can be solved")
	_expect(game._progress.get_value("solved", game._weekly_key(last_week), false), "and its solve is saved")
	_expect(game._progress.get_value("stats", "weeklies_solved", 0) == solved_before,
			"past weeks don't count towards the weekly achievements")
	game._leave_game()
	await _frames(3)
	_expect(archive.visible and not game._game.visible, "leaving a past week goes back to the weekly archive")
	var solved_button: Button = archive._list.get_child(1)
	_expect("Solved" in solved_button.text and solved_button.get_child_count() > 0, "a solved week wears a crown")
	_screenshot("weekly_archive.png")
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not archive.visible, "back from the weekly archive goes to the menu")
	game.queue_free()
	await _frames(2)


func _check_reminder() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var settings: Control = game._settings
	# Notifications need the Android plugin, so here the settings stay hidden and calls do nothing.
	_expect(not game._reminder.available() and not settings.reminder_toggle.visible and not settings._reminder_row.visible,
			"reminder settings are hidden off Android")
	# Vibration is Android-only too, but its setting still saves.
	_expect(not game._haptics.available() and not settings.vibration_toggle.visible, "vibration setting is hidden off Android")
	settings.vibration_toggle.button_pressed = false
	_expect(not game._haptics.enabled and game._progress.get_value("settings", "vibration", true) == false,
			"turning vibration off saves it")
	settings.vibration_toggle.button_pressed = true
	game._haptics.win()
	game._haptics.crown()
	_expect(game._haptics.WIN_PATTERN.all(func(pulse: Array) -> bool: return pulse[0] + pulse[1] <= 1000),
			"the win vibration fits within the win sound")
	_expect(settings._hour_name(7) == "7:00 AM" and settings._hour_name(12) == "12:00 PM"
			and settings._hour_name(19) == "7:00 PM", "reminder times use a 12-hour clock in English")
	_expect(settings.reminder_hour_picker.get_item_text(settings.reminder_hour_picker.selected) == "7:00 PM",
			"the reminder defaults to 7 PM")
	settings.reminder_toggle.button_pressed = true
	_expect(game._progress.get_value("settings", "reminder", false) and not settings.reminder_hour_picker.disabled,
			"turning the reminder on saves it and enables the time")
	settings.reminder_hour_picker.select(1)
	settings.reminder_hour_picker.item_selected.emit(1)
	_expect(game._progress.get_value("settings", "reminder_hour", 0) == game.REMINDER_HOURS[1], "the reminder time is saved")
	settings.reminder_toggle.button_pressed = false
	_expect(not game._progress.get_value("settings", "reminder", true) and settings.reminder_hour_picker.disabled,
			"turning the reminder off saves it and disables the time")
	var now := int(Time.get_unix_time_from_system())
	var next: int = game._next_daily_time()
	_expect(next > now and next - now <= 86400 and Time.get_date_string_from_unix_time(next - 7 * 3600) != game._today()
			and Time.get_datetime_dict_from_unix_time(next - 7 * 3600).hour == 0, "the next daily comes out at midnight UTC-7")
	game.queue_free()


func _check_tutorial() -> void:
	const SAVE := "user://tutorial_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = SAVE
	root.add_child(game)
	await _frames(5)
	var view: Control = game._view
	_expect(game._mode == game.Mode.TUTORIAL and game._game.visible and not game._menu.visible,
			"a first launch starts the tutorial")
	_expect(game._back_button.text == "Skip" and not game._timer_label.visible and not game._clear_button.visible,
			"the tutorial is untimed and can be skipped")
	_expect(game._hint_label.text.begins_with("Welcome to Crowns") and game._hint_button.text == "Next"
			and not view.interactive and not game._undo_button.visible, "the tutorial opens on an intro card")
	game._hint_button.pressed.emit()
	game._hint_button.pressed.emit()
	var board: Board = game._board
	_expect(view.interactive and not game._hint_button.visible and view.hint_targets.size() == 1
			and game._hint_label.text.ends_with("Double tap it to place a crown."), "after the cards, the first crown is shown")
	_expect(board.regions.count(board.region_at(Vector2i(view.hint_targets[0] / 5, view.hint_targets[0] % 5))) == 1,
			"the first crown goes in a one-cell region")

	# A wrong crown is pointed out, and undo puts things back.
	var wrong := Vector2i(0, (board.solution[0] + 2) % 5)
	await _right_click(view, wrong)
	_expect(game._hint_label.text.begins_with("This crown isn't part of the solution."), "the tutorial points out a mistake")
	game._on_undo()
	_expect(game._hint_label.text.ends_with("Double tap it to place a crown."), "undo returns to the step")

	# Follow every step: crowns where shown, crosses on the cells a crown rules out.
	var steps := 0
	var crossing_steps := 0
	while not board.is_solved() and steps < 40:
		steps += 1
		var targets: PackedInt32Array = view.hint_targets
		var crown: bool = game._hint_label.text.ends_with("place a crown.")
		if not crown:
			crossing_steps += 1
		for i in targets:
			var cell := Vector2i(i / 5, i % 5)
			if crown:
				await _slow_click(view, cell)
				await _click(view, cell)
			else:
				await _slow_click(view, cell)
	await _frames(3)
	_expect(board.is_solved() and crossing_steps >= 2, "following the steps solves the puzzle, crossing out along the way")
	_expect(game._win_overlay.visible and game._next_puzzle_button.text == "Next lesson" and game._win_play_button.visible
			and not game._win_leaderboard_button.visible and game._win_back_button.text == "Menu",
			"the basics end offering the next lesson or playing")
	var saved := ConfigFile.new()
	saved.load(SAVE)
	_expect(saved.get_value("settings", "tutorial_done", false) and not saved.has_section("solved")
			and not saved.has_section("in_progress"), "the tutorial is marked done and records nothing else")
	game._win_play_button.pressed.emit()
	await _settle()
	_expect(game._mode == game.Mode.REGULAR and game._timer_label.visible and game._clear_button.visible
			and game._hint_button.text == "Hint" and not game._view.auto_cross, "Start playing opens a regular puzzle")

	# The advanced lessons: each opens on its technique, then finishes with simple steps.
	var openings := {"confined": "'s open cells all lie in row", "group": "regions only have open cells in rows",
			"blocker": "would rule out every open cell left in"}
	for lesson in range(1, game.LESSONS.size()):
		game._start_lesson(lesson)
		await _frames(5)
		_expect(game._puzzle_label.text == "Technique %d of 3" % lesson and game._view.auto_cross, "lesson %d starts" % lesson)
		while game._hint_button.visible:
			game._hint_button.pressed.emit()
		var lesson_board: Board = game._board
		_expect(game._hint_label.text.contains(openings[game.LESSONS[lesson].technique]),
				"lesson %d opens on its technique" % lesson)
		var moves := 0
		while not lesson_board.is_solved() and moves < 30:
			moves += 1
			var crown: bool = game._hint_label.text.ends_with("place a crown.")
			var changes := []
			for i in game._view.hint_targets:
				var cell := Vector2i(i / lesson_board.size, i % lesson_board.size)
				changes.append([cell, lesson_board.get_mark(cell), Board.Mark.CROWN if crown else Board.Mark.CROSS])
			game._apply(changes)
		await _frames(3)
		var last: bool = lesson == game.LESSONS.size() - 1
		_expect(lesson_board.is_solved() and game._next_puzzle_button.text == ("Start playing" if last else "Next lesson")
				and not game._win_play_button.visible, "lesson %d can be finished by following it" % lesson)
	game._next_puzzle_button.pressed.emit()
	await _settle()
	_expect(game._mode == game.Mode.REGULAR, "the last lesson's Start playing opens a regular puzzle")
	game.queue_free()
	await _frames(2)

	# Later launches go to the menu; Settings replays the tutorial.
	game = load("res://main.tscn").instantiate()
	game.save_path = SAVE
	root.add_child(game)
	await _frames(5)
	_expect(game._menu.visible and game._mode != game.Mode.TUTORIAL, "the tutorial only starts by itself once")
	game._show_settings()
	game._settings.how_to_play.emit()
	await _frames(5)
	_expect(game._mode == game.Mode.TUTORIAL and not game._settings.visible and game._tutorial_card == 0,
			"How to play replays the tutorial")
	game._leave_game()
	_expect(game._menu.visible, "skipping returns to the menu")
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _check_cloud_save() -> void:
	var local := ConfigFile.new()
	local.set_value("settings", "dark_mode", true)
	local.set_value("solved", "7x7_medium_1", true)
	local.set_value("best", "7x7_medium_1", 50.0)
	local.set_value("best", "daily_2026-10-20", 80.0)
	local.set_value("stats", "solved_7", 3)
	local.set_value("stats", "timed_7", 2)
	local.set_value("stats", "time_7", 100.0)
	local.set_value("stats", "best_7", 40.0)
	local.set_value("stats", "streak", 2)
	local.set_value("stats", "last_daily", "2026-10-20")
	local.set_value("stats", "longest_streak", 2)
	local.set_value("in_progress", "8x8_easy_2", {"marks": "here"})
	local.set_value("challenge", "best", 3)

	var remote := ConfigFile.new()
	remote.set_value("settings", "dark_mode", false)
	remote.set_value("solved", "9x9_hard_1", true)
	remote.set_value("best", "7x7_medium_1", 70.0)
	remote.set_value("best", "daily_2026-10-20", 60.0)
	remote.set_value("stats", "solved_7", 1)
	remote.set_value("stats", "timed_7", 5)
	remote.set_value("stats", "time_7", 400.0)
	remote.set_value("stats", "best_7", 45.0)
	remote.set_value("stats", "streak", 6)
	remote.set_value("stats", "last_daily", "2026-10-22")
	remote.set_value("stats", "longest_streak", 6)
	remote.set_value("stats", "weeklies_solved", 1)
	remote.set_value("in_progress", "8x8_easy_2", {"marks": "there"})
	remote.set_value("in_progress", "9x9_hard_1", {"marks": "solved already"})
	remote.set_value("in_progress", "6x6_easy_4", {"marks": "new"})
	remote.set_value("challenge", "best", 8)
	remote.set_value("challenge", "run", {"level": 4})
	remote.set_value("speed", "best", 70.0)
	local.set_value("speed", "best", 90.0)
	local.set_value("history", "size_7", [[100, 50.0, 1], [300, 40.0, 1]])
	var long_history := []
	for i in 40:
		long_history.append([1000 + i, 30.0 + i, 0])
	local.set_value("history", "size_8", long_history)
	remote.set_value("history", "size_7", [[200, 70.0, 2], [300, 40.0, 1]])
	remote.set_value("history", "size_8", [[2000, 25.0, 3]])

	var packed := CloudSave.pack(remote)
	var unpacked := CloudSave.unpack(packed)
	_expect(unpacked != null and not unpacked.has_section("settings")
			and unpacked.get_value("stats", "time_7") == 400.0, "the cloud save round-trips without settings")
	_expect(CloudSave.unpack(PackedByteArray()) == null, "an empty cloud save is ignored")

	CloudSave.merge(local, unpacked)
	_expect(local.get_value("solved", "7x7_medium_1") and local.get_value("solved", "9x9_hard_1"), "solves from both devices are kept")
	_expect(local.get_value("best", "7x7_medium_1") == 50.0 and local.get_value("best", "daily_2026-10-20") == 60.0,
			"the faster best time wins")
	_expect(local.get_value("stats", "solved_7") == 3 and local.get_value("stats", "weeklies_solved") == 1,
			"counts keep the higher value")
	_expect(local.get_value("stats", "timed_7") == 5 and local.get_value("stats", "time_7") == 400.0
			and local.get_value("stats", "best_7") == 40.0, "timed totals move together and the best size time wins")
	_expect(local.get_value("stats", "streak") == 6 and local.get_value("stats", "last_daily") == "2026-10-22"
			and local.get_value("stats", "longest_streak") == 6, "the most recent streak wins")
	_expect(local.get_value("in_progress", "8x8_easy_2").marks == "here"
			and local.get_value("in_progress", "6x6_easy_4").marks == "new"
			and not local.has_section_key("in_progress", "9x9_hard_1"), "boards in progress merge, skipping solved ones")
	_expect(local.get_value("challenge", "best") == 8 and local.get_value("challenge", "run").level == 4,
			"The Climb's best and a run from the other device carry over")
	_expect(local.get_value("speed", "best") == 70.0, "the faster speed run wins")
	_expect(local.get_value("history", "size_7") == [[100, 50.0, 1], [200, 70.0, 2], [300, 40.0, 1]],
			"solve histories merge in order without repeating shared solves")
	var merged_8: Array = local.get_value("history", "size_8")
	_expect(merged_8.size() == CloudSave.HISTORY_LENGTH and merged_8[-1] == [2000, 25.0, 3] and merged_8[0][0] == 1011,
			"a merged history keeps only the most recent solves")
	_expect(local.get_value("settings", "dark_mode") == true, "settings stay with the device")
	_expect(CloudSave.solved_count(local) == 2, "the save's progress counts solves")


func _check_achievements() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(not game._stats.achievements_button.visible, "the achievements button is hidden off Android")
	var names: Array = game._earned_achievements().keys()
	names.sort()
	var ids: Array = game.PlayGames.ACHIEVEMENTS.keys()
	ids.sort()
	_expect(names == ids, "every achievement has an ID slot")

	var progress := ConfigFile.new()
	game._progress = progress
	var earned: Dictionary = game._earned_achievements()
	_expect(earned.values().all(func(value: bool) -> bool: return not value), "a fresh save has no achievements")
	progress.set_value("solved", "5x5_easy_1", true)
	progress.set_value("best", "7x7_hard_2", 200.0)
	progress.set_value("best", "daily_2026-10-01", 59.0)
	progress.set_value("stats", "longest_streak", 7)
	progress.set_value("challenge", "best", 25)
	earned = game._earned_achievements()
	_expect(earned.first_crown and earned.unaided and earned.hard and earned.quick and earned.streak_7
			and earned.climb_10 and earned.climb_25 and earned.big_board, "achievements follow the saved progress")
	_expect(not earned.streak_30 and not earned.weekly and not earned.century, "unearned achievements stay locked")
	for i in 99:
		progress.set_value("solved", "puzzle_%d" % i, true)
	_expect(game._earned_achievements().century, "100 solves earn Hundred Crowns")
	_expect(not earned.tutorial and not earned.custom and not earned.hard_plus and not earned.every_size
			and not earned.perfect_month and not earned.thousand, "the newer achievements start locked")
	progress.set_value("settings", "tutorial_done", true)
	progress.set_value("solved", "custom_ABC", true)
	progress.set_value("best", "12x12_hard+_3", 900.0)
	progress.set_value("stats", "speed_finished", 1)
	progress.set_value("stats", "weeklies_solved", 10)
	progress.set_value("stats", "longest_streak", 100)
	for size in range(5, 15):
		progress.set_value("stats", "solved_%d" % size, 1)
	earned = game._earned_achievements()
	_expect(earned.tutorial and earned.custom and earned.hard_plus and earned.speed_run and earned.weekly_10
			and earned.giant and earned.every_size and earned.streak_100, "the newer achievements follow the saved progress")
	progress.set_value("stats", "solved_9", 0)
	_expect(not game._earned_achievements().every_size, "Every Size needs every size")
	for i in 900:
		progress.set_value("solved", "more_%d" % i, true)
	_expect(game._earned_achievements().thousand, "1,000 solves earn Thousand Crowns")
	game.queue_free()


func _check_stats() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var progress: ConfigFile = game._progress

	# Earlier in this run: a hinted 7x7, a hinted daily and two Climb runs with one clear.
	_expect(progress.get_value("stats", "solved_7", 0) >= 1 and progress.get_value("stats", "timed_7", 0) == 0,
			"hinted solves count as solved but not timed")
	_expect(progress.get_value("stats", "dailies_solved", 0) == 1 and game._current_streak() == 1, "solving the daily starts a streak")
	_expect(game._menu._daily_detail.text.ends_with("1 day streak"), "menu shows the daily streak")
	_expect(progress.get_value("stats", "climb_runs", 0) == 2 and progress.get_value("stats", "climb_solved", 0) == 1,
			"Climb runs and clears are counted")

	# An unhinted solve is timed; solving the same puzzle again isn't counted twice.
	game._menu.continue_button.pressed.emit()
	await _settle()
	game._size_picker.select(0)
	game._on_size_selected(0)
	await _settle()
	for attempt in 2:
		var board: Board = game._board
		game._elapsed = 40.0
		for row in board.size:
			await _right_click(game._view, Vector2i(row, board.solution[row]))
		game._go_to(1)
		await _settle()
	_expect(progress.get_value("stats", "solved_5", 0) == 1, "a puzzle counts once however often it's solved")
	_expect(progress.get_value("stats", "timed_5", 0) == 1 and progress.get_value("stats", "best_5", INF) < 41.0,
			"unhinted solves record their time")
	_expect(progress.get_value("stats", "puzzles_unhinted", 0) == 1, "unhinted numbered solves are counted for the leaderboard")
	var history: Array = progress.get_value("history", "size_5", [])
	_expect(history.size() == 1 and history[0][1] < 41.0 and history[0][2] == game._difficulty_picker.selected,
			"a timed solve joins its size's history, with its difficulty")
	_expect(progress.get_value("history", "size_7", []).is_empty(), "hinted solves stay out of the history")

	# Play Games only exists on Android; elsewhere its buttons stay hidden and calls do nothing.
	_expect(not game._settings._test_reminder_button.visible, "the test reminder button needs reminders (Android)")
	_expect(not game._play_games.available() and not game._menu.leaderboards_button.visible
			and not game._win_leaderboard_button.visible, "leaderboard buttons are hidden off Android")
	var utc_minus_7 := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 7 * 3600)
	_expect(game._today() == utc_minus_7, "the daily date follows UTC-7")

	# Streak dates.
	_expect(game._day_before("2026-03-01") == "2026-02-28" and game._day_before("2028-03-01") == "2028-02-29"
			and game._day_before("2027-01-01") == "2026-12-31", "the day before handles month, leap year and year ends")
	var today: String = game._today()
	progress.set_value("stats", "last_daily", game._day_before(today))
	progress.set_value("stats", "streak", 4)
	_expect(game._current_streak() == 4, "a streak survives until today's daily is due")
	game._record_daily(today)
	_expect(game._current_streak() == 5 and progress.get_value("stats", "longest_streak", 0) == 5, "solving the next day extends the streak")
	progress.set_value("stats", "last_daily", game._day_before(game._day_before(today)))
	_expect(game._current_streak() == 0, "missing a day breaks the streak")
	game._record_daily(today)
	_expect(progress.get_value("stats", "streak", 0) == 1 and progress.get_value("stats", "longest_streak", 0) == 5,
			"a new streak starts at 1 and keeps the longest")

	game._show_menu()
	game._menu.stats_button.pressed.emit()
	await _frames(3)
	_expect(game._stats.visible and not game._menu.visible, "stats opens from the menu")
	var texts := []
	for label in game._stats.find_children("*", "Label", true, false):
		texts.append(label.text)
	_expect(texts.has("5×5") and texts.has("0:40") and texts.has("5 days"), "stats screen shows sizes, times and streaks")
	_expect(texts.has("Weeklies solved"), "stats screen counts weekly solves")
	var stats: Control = game._stats
	_expect(stats.history_picker != null and stats.history_picker.get_selected_id() == 5
			and stats.history_graph.entries.size() == 1, "the solve history opens on the size solved last")
	_expect(texts.any(func(text: String) -> bool: return text.begins_with("Last 1 solve · average 0:40")),
			"the history sums up its solves")
	for i in 3:
		game._record_solve(6, 1, false, 60.0 + i)
	game._show_stats()
	await _frames(2)
	var picker: OptionButton = game._stats.history_picker
	_expect(picker.item_count == game._progress.get_section_keys("history").size() and picker.get_selected_id() == 6,
			"each size with solves gets a graph, the newest first")
	picker.select(picker.get_item_index(5))
	picker.item_selected.emit(picker.get_item_index(5))
	_expect(game._stats.history_graph.entries.size() == 1, "picking a size shows its own solves")
	_screenshot("stats.png")
	game._stats.back.emit()
	_expect(game._menu.visible and not game._stats.visible, "back returns from stats")
	game.queue_free()


func _check_reduce_motion() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.settings_button.pressed.emit()
	game._settings.reduce_motion_toggle.button_pressed = true
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(game._view.reduce_motion and game._editor.view.reduce_motion
			and saved.get_value("settings", "reduce_motion", false) == true, "reduce motion turns on from settings and is saved")
	game.queue_free()
	await _frames(2)

	game = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(game._settings.reduce_motion_toggle.button_pressed and game._view.reduce_motion, "reduce motion stays on after a restart")
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	_expect(view._reveal_at < 0, "with reduced motion the board appears without the reveal")
	game._on_clear()
	await _frames(1)
	await _click(view, Vector2i(0, 0))
	await _frames(1)
	_expect(view._pops.is_empty() and game._board.get_mark(Vector2i(0, 0)) != Board.Mark.EMPTY,
			"marks appear without popping in")
	view.celebrate()
	_expect(view._celebrate_at < 0, "no win wave")
	game._show_win_overlay()
	await _wait_ms(700)
	await _frames(2)
	_expect(game._win_overlay.visible and game._win_panel.scale == Vector2.ONE, "the win panel appears without springing")
	game._hide_overlay()
	# Later checks play this puzzle again from its saved state.
	game._on_clear()
	game._menu.settings_button.pressed.emit()
	game._settings.reduce_motion_toggle.button_pressed = false
	_expect(not view.reduce_motion, "reduce motion turns off again")
	game.queue_free()
	await _frames(2)


func _check_text_size() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var picker: OptionButton = game._settings.text_size_picker
	_expect(picker.get_theme_font_size("font_size") == 20 and game._theme.default_font_size == 16,
			"text starts at its normal size")
	game._menu.settings_button.pressed.emit()
	picker.select(TextSize.NAMES.find("larger"))
	picker.item_selected.emit(picker.selected)
	await _frames(2)
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(picker.get_theme_font_size("font_size") == 26 and game._theme.default_font_size == 21
			and saved.get_value("settings", "text_size", "") == "larger", "larger text resizes what's on screen and is saved")
	game.queue_free()
	await _frames(2)

	game = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	picker = game._settings.text_size_picker
	_expect(picker.selected == TextSize.NAMES.find("larger") and picker.get_theme_font_size("font_size") == 26,
			"larger text stays after a restart")
	game._menu.stats_button.pressed.emit()
	await _frames(2)
	var title: Label = game._stats.find_children("*", "Label", true, false)[0]
	_expect(title.get_theme_font_size("font_size") == TextSize.scaled(title.get_meta(&"base_font_size"))
			and TextSize.scaled(20) == 26, "text made later is larger too")
	picker.select(TextSize.NAMES.find("normal"))
	picker.item_selected.emit(picker.selected)
	_expect(picker.get_theme_font_size("font_size") == 20 and game._theme.default_font_size == 16,
			"text goes back to normal")
	game.queue_free()
	await _frames(2)


func _check_pinch_zoom() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(not game._view.zoomable and not game._editor.view.zoomable, "pinch to zoom starts off")
	game._settings.pinch_zoom_toggle.button_pressed = true
	_expect(game._view.zoomable and game._editor.view.zoomable, "the setting turns pinch to zoom on")
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	view._reveal_at = -1
	game._on_clear()
	await _frames(1)
	var size: int = view.board.size
	var cell_px: float = view._cell_size()
	var first := _cell_center(view, Vector2i(2, 2))
	var second := _cell_center(view, Vector2i(3, 3))
	_finger(view, 0, first, true)
	await _frames(1)
	_expect(view.board.get_mark(Vector2i(2, 2)) == Board.Mark.CROSS, "one finger still crosses out")
	_finger(view, 1, second, true)
	await _frames(1)
	_expect(view._pinching and view.board.get_mark(Vector2i(2, 2)) == Board.Mark.EMPTY,
			"a second finger starts a pinch and takes back the first finger's cross")
	for step in range(1, 6):
		_finger(view, 1, second + Vector2(step, step) * cell_px * 0.4, true, true)
		await _frames(1)
	_expect(view._zoom > 1.5 and view._cell_size() > cell_px * 1.5 and view.clip_contents, "spreading the fingers zooms in")
	_finger(view, 0, first, false)
	_finger(view, 1, second, false)
	await _frames(2)
	_expect(not view._pinching and view.board.marks.count(Board.Mark.EMPTY) == size * size,
			"the pinch leaves no marks behind")
	var middle: Vector2i = view._cell_at(view._base_origin() + Vector2.ONE * view._base_cell_size() * size / 2.0)
	await _slow_click(view, middle)
	_expect(view.board.get_mark(middle) == Board.Mark.CROSS
			and view.board.marks.count(Board.Mark.CROSS) == 1, "taps land on the zoomed cell")
	var base: Vector2 = view._base_origin()
	var side: float = view._base_cell_size() * size
	view.grab_focus()
	await _key(KEY_RIGHT)
	for i in size:
		await _key(KEY_DOWN)
		await _key(KEY_RIGHT)
	var corner: Vector2 = view._origin() + Vector2(view.cursor.y + 1, view.cursor.x + 1) * view._cell_size()
	_expect(corner.x <= base.x + side + 0.5 and corner.y <= base.y + side + 0.5, "the keyboard cursor stays in view")
	# A hint on screen leaves the zoom alone; one off screen zooms out to show it.
	view._zoom = 3.0
	view._offset = Vector2.ZERO
	view.clip_contents = true
	view.hint_targets = PackedInt32Array([0])
	_expect(view._zoom == 3.0, "a hint on screen keeps the zoom")
	view.hint_targets = PackedInt32Array([size * size - 1])
	await _wait_ms(view.ZOOM_OUT_MS + 150)
	_expect(view._zoom == 1.0 and not view.clip_contents, "a hint off screen zooms out")
	view.reduce_motion = true
	view._zoom = 3.0
	view.clip_contents = true
	view.mistake = Vector2i(size - 1, size - 1)
	_expect(view._zoom == 1.0, "so does a mistake, at once without animations")
	view.reduce_motion = false
	view.mistake = Vector2i(-1, -1)
	game._clear_hint()
	game._on_clear()
	view.board = view.board
	_expect(view._zoom == 1.0 and not view.clip_contents, "a new board starts unzoomed")

	game._settings.pinch_zoom_toggle.button_pressed = false
	_finger(view, 0, first, true)
	_finger(view, 1, second, true)
	await _frames(1)
	_expect(not view._pinching and not view.zoomable, "with pinch to zoom off, two fingers don't zoom")
	_finger(view, 0, first, false)
	_finger(view, 1, second, false)
	await _frames(2)
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "pinch_zoom", true) == false, "turning pinch to zoom off is saved")
	game._on_clear()
	game.queue_free()
	await _frames(2)


func _check_backup() -> void:
	# A sizeable save: a year of calendar and plenty of solves.
	var other := ConfigFile.new()
	for i in 365:
		other.set_value("calendar", Time.get_date_string_from_unix_time(1767225600 + i * 86400), i % 9)
	for i in 400:
		other.set_value("solved", "7x7_medium_%d" % i, true)
		other.set_value("best", "7x7_medium_%d" % i, 60.0 + i)
	other.set_value("stats", "solved_7", 400)
	other.set_value("settings", "theme", "forest")
	var code := CloudSave.backup_code(other)
	var back := CloudSave.from_backup_code(code)
	_expect(code.begins_with("CROWNS1:") and back != null and back.get_value("stats", "solved_7") == 400
			and back.get_value("best", "7x7_medium_399") == 459.0 and not back.has_section("settings"),
			"a backup code carries progress but not settings")
	_expect(code.length() < 20000, "a big save's backup code stays short enough to paste (%d characters)" % code.length())
	var mangled := code.substr(0, 40) + "\n " + code.substr(40, 100) + "\r\n" + code.substr(140) + "  "
	_expect(CloudSave.from_backup_code(mangled) != null, "spaces and line breaks in a pasted code are ignored")
	for bad in ["", "hello", "CROWNS1:12:abc", code.substr(0, code.length() - 30), "CROWNS1:x:" + code.split(":")[2]]:
		_expect(CloudSave.from_backup_code(bad) == null, "a broken code is refused: " + bad.left(20))

	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.settings_button.pressed.emit()
	await _frames(2)
	var settings: Control = game._settings
	game._progress.set_value("best", "7x7_medium_0", 30.0)
	var solved_before: int = game._progress.get_value("stats", "solved_7", 0)
	settings.backup_restore_button.pressed.emit()
	_expect(settings._restore_box.visible, "Restore opens a box to paste the code into")
	settings.backup_entry.text = "not a code"
	settings._restore_box.find_children("*", "Button", true, false)[-1].pressed.emit()
	_expect(settings._backup_status.visible and settings._restore_box.visible
			and settings._backup_status.text.begins_with("That isn't"), "a wrong code says so")
	settings.backup_entry.text = code
	settings._restore_box.find_children("*", "Button", true, false)[-1].pressed.emit()
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(not settings._restore_box.visible and settings._backup_status.text == "Progress restored."
			and saved.get_value("solved", "7x7_medium_399", false) and saved.get_value("stats", "solved_7", 0) == maxi(400, solved_before)
			and saved.get_value("best", "7x7_medium_0") == 30.0 and saved.get_value("settings", "theme", "") != "forest",
			"restoring adds the backup's progress, keeps the better records, and leaves settings alone")
	settings.backup_copy_button.pressed.emit()
	_expect(settings.backup_copy_button.text == "Copied!" and settings._backup_status.visible, "Copy code confirms it")
	game._show_menu()
	game._show_settings()
	_expect(settings.backup_copy_button.text == "Copy code" and not settings._backup_status.visible,
			"Settings opens fresh")
	for i in 400:
		game._progress.erase_section_key("solved", "7x7_medium_%d" % i)
		game._progress.erase_section_key("best", "7x7_medium_%d" % i)
	game._progress.set_value("stats", "solved_7", solved_before)
	game._progress.erase_section("calendar")
	game._progress.save(TEST_SAVE)
	game._show_menu()
	game.queue_free()
	await _frames(2)


func _check_calendar() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var today := Time.get_date_string_from_system()
	game._progress.erase_section(game.CALENDAR)
	# Earlier checks' solves are set aside, to count only these.
	var histories := {}
	for key in game._progress.get_section_keys(game.HISTORY):
		histories[key] = game._progress.get_value(game.HISTORY, key)
	game._progress.erase_section(game.HISTORY)
	# An older save: solves in the history and a daily, but no calendar yet.
	var noon: int = Time.get_unix_time_from_datetime_string(today + "T12:00:00") \
			- Time.get_time_zone_from_system().bias * 60
	game._progress.set_value(game.HISTORY, "size_99", [[noon, 60.0, 0], [noon, 70.0, 0]])
	game._progress.set_value("solved", "daily_2026-01-05", true)
	game._fill_calendar()
	_expect(game._progress.get_value(game.CALENDAR, today, 0) == 2
			and game._progress.get_value(game.CALENDAR, "2026-01-05", 0) == 1,
			"the calendar fills in from older saves' solve history and dailies")
	game._progress.erase_section(game.HISTORY)
	for key: String in histories:
		game._progress.set_value(game.HISTORY, key, histories[key])
	game._progress.erase_section_key("solved", "daily_2026-01-05")
	game._menu.continue_button.pressed.emit()
	await _settle()
	var board: Board = game._board
	for row in board.size:
		board.set_mark(Vector2i(row, board.solution[row]), Board.Mark.CROWN)
	game._check_win()
	_expect(game._progress.get_value(game.CALENDAR, today, 0) == 3, "a solve adds to today's square")
	game._hide_overlay()
	game._leave_game()
	game._menu.stats_button.pressed.emit()
	await _frames(3)
	var heatmap: Control = game._stats.heatmap
	_expect(heatmap != null and heatmap.today == today and heatmap.days.get(today, 0) == 3
			and heatmap.size.x > 0 and heatmap.custom_minimum_size.y > 0, "Stats shows the year of days played")
	var texts: Array = game._stats.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	var since := Time.get_unix_time_from_datetime_string(today) - 364 * 86400
	var played: int = heatmap.days.keys().filter(func(date: String) -> bool:
			return Time.get_unix_time_from_datetime_string(date) >= since).size()
	_expect(texts.has("Days played") and texts.has("%d days in the last year" % played) and played >= 2,
			"and how many days had a solve")
	_expect(heatmap.level(0) == 0 and heatmap.level(1) == 1 and heatmap.level(3) == 2 and heatmap.level(50) == 4,
			"more solves shade a day darker")
	var cell: float = heatmap.size.x / heatmap.WEEKS
	var weekday: int = Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(today)).weekday
	var spot := Vector2((heatmap.WEEKS - 0.5) * cell, heatmap._label_height() + (weekday + 0.5) * cell)
	_expect(heatmap._get_tooltip(spot) == game._pretty_date(today) + " · 3 puzzles", "today's square says what was solved")
	_screenshot("stats_calendar.png")

	var local := ConfigFile.new()
	local.set_value("calendar", today, 2)
	var remote := ConfigFile.new()
	remote.set_value("calendar", today, 5)
	remote.set_value("calendar", "2026-01-05", 1)
	CloudSave.merge(local, remote)
	CloudSave.merge(local, remote)
	_expect(local.get_value("calendar", today) == 5 and local.get_value("calendar", "2026-01-05") == 1,
			"the calendar merges across devices without counting twice")
	game._progress.erase_section(game.CALENDAR)
	game._progress.save(TEST_SAVE)
	game.queue_free()
	await _frames(2)


func _check_solution() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.continue_button.pressed.emit()
	await _settle()
	var view: Control = game._view
	var board: Board = game._board
	var key: String = game._board_key
	var was_solved: bool = game._progress.get_value("solved", key, false)
	game._on_clear()
	game._hinted = false
	_expect(game._solution_button.visible and game._solution_button.text == "Solution", "regular puzzles offer the solution")
	await _click(view, Vector2i(0, 0))
	game._solution_button.pressed.emit()
	_expect(game._solution_overlay.visible and not game._running, "Solution asks first, pausing the clock")
	game._keep_trying_button.pressed.emit()
	_expect(not game._solution_overlay.visible and game._running and not game._revealed
			and board.get_mark(Vector2i(0, 0)) != Board.Mark.EMPTY, "Keep trying goes back to the board as it was")
	game._solution_button.pressed.emit()
	game._reveal_solution()
	var shown := true
	for row in board.size:
		for col in board.size:
			var crown := board.get_mark(Vector2i(row, col)) == Board.Mark.CROWN
			shown = shown and crown == (board.solution[row] == col)
	_expect(shown and game._revealed and not view.interactive and not game._running and game._hinted,
			"Show solution fills in the crowns and stops the puzzle")
	_expect(game._progress.get_value("revealed", key, false) and game._progress.get_value("solved", key, false) == was_solved
			and not game._win_overlay.visible, "a given-up puzzle isn't solved, and is remembered")
	_expect(game._solution_button.text == "Try again", "the button offers to try again")
	game._solution_button.pressed.emit()
	_expect(view.interactive and game._running and board.marks.count(Board.Mark.EMPTY) == board.size * board.size
			and game._hinted, "Try again starts over on an empty board, still hinted")
	game._leave_game()
	game._menu.continue_button.pressed.emit()
	await _settle()
	_expect(game._hinted and game._solution_button.text == "Solution", "reopening a given-up puzzle keeps it hinted")
	for mode in [game.Mode.CHALLENGE, game.Mode.SPEED]:
		game._leave_game()
		game._start(mode)
		await _settle()
		_expect(not game._solution_button.visible, "no solution in The Climb or speed runs")
	game._leave_game()
	game._progress.erase_section("revealed")
	game._progress.save(TEST_SAVE)
	game.queue_free()
	await _frames(2)


func _check_credits() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(game._menu.credits_button.is_visible_in_tree(), "the menu has a Credits button")
	game._menu.credits_button.pressed.emit()
	await _frames(3)
	var credits: Control = game._credits
	_expect(credits.visible and not game._menu.visible, "Credits opens its screen")
	var texts := PackedStringArray()
	var licences: Array[Button] = []
	for node in credits.find_children("*", "", true, false):
		if node is Label:
			texts.append((node as Label).text)
		elif node is LinkButton:
			texts.append((node as LinkButton).tooltip_text)
		elif node is Button and (node as Button).text.begins_with("▸"):
			licences.append(node)
	_expect(licences.size() >= 5, "each licence's text can be shown")
	for licence in licences:
		var body: Label = licence.get_parent().get_child(licence.get_index() + 1)
		_expect(not body.visible and body.text.is_empty(), "licence texts start hidden and unbuilt")
		licence.pressed.emit()
		_expect(body.visible and licence.text.begins_with("▾"), "a licence's button shows its text")
		texts.append(body.text)
	var all := "\n".join(texts)
	for needle in ["Strechy", "creativecommons.org/licenses/by/4.0/", "GNU GENERAL PUBLIC LICENSE",
			"SIL OPEN FONT LICENSE", "Bitstream", "Juan Linietsky", "FreeType"]:
		_expect(needle in all, "Credits include " + needle)
	licences[0].pressed.emit()
	_expect(not licences[0].get_parent().get_child(licences[0].get_index() + 1).visible, "and hides it again")
	await _frames(2)
	_expect(credits.size.x >= credits.get_child(0).get_combined_minimum_size().x,
			"Credits fit the screen's width")
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not credits.visible, "back from Credits goes to the menu")
	game.queue_free()
	await _frames(2)


func _check_go_back() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(not ProjectSettings.get_setting("application/config/quit_on_go_back"),
			"Android's back gesture doesn't quit by itself")
	game._menu.settings_button.pressed.emit()
	await _frames(2)
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not game._settings.visible, "back from Settings goes to the menu")
	game._menu.continue_button.pressed.emit()
	await _settle()
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not game._game.visible, "back from a puzzle goes to the menu")
	game._menu.create_button.pressed.emit()
	await _frames(3)
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not game._editor.visible, "back from the editor goes to the menu")
	_expect(not Input.is_action_pressed("ui_cancel"), "back leaves no key held")
	game.queue_free()
	await _frames(2)


## Presses, moves or lifts finger `index` at `pos` in `view`.
func _finger(view: Control, index: int, pos: Vector2, down: bool, drag := false) -> void:
	var event: InputEvent
	if drag:
		event = InputEventScreenDrag.new()
	else:
		event = InputEventScreenTouch.new()
		event.pressed = down
	event.index = index
	event.position = _to_window(view, pos)
	Input.parse_input_event(event)


func _check_patterns() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	game._menu.settings_button.pressed.emit()
	game._settings.patterns_toggle.button_pressed = true
	_expect(game._view.patterns, "region patterns turn on from settings")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "patterns", false) == true, "region patterns setting is saved")
	game._settings.patterns_toggle.button_pressed = false
	game.queue_free()
	await _frames(2)

	# Every pattern side by side: one region per row of a 14x14 board.
	var regions := PackedInt32Array()
	for row in 14:
		for col in 14:
			regions.append(row)
	var board := Board.new(14, regions, PackedInt32Array())
	board.set_mark(Vector2i(2, 3), Board.Mark.CROSS)
	board.set_mark(Vector2i(5, 8), Board.Mark.CROWN)
	board.set_mark(Vector2i(9, 1), Board.Mark.AUTO_CROSS)
	var view := BoardViewScript.new()
	view.size = Vector2(root.size)
	view.patterns = true
	root.add_child(view)
	view.board = board
	await _frames(3)
	_screenshot("patterns.png")
	view.queue_free()


func _check_drills() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var main_script: Script = game.get_script()
	# Each technique's boards open just where it's the easiest step left.
	for technique: String in ["confined", "group", "blocker"]:
		for seed in 3:
			var puzzle: Dictionary = main_script._make_drill([technique, 6, seed])
			var step := Grader.next_step(6, puzzle.regions, puzzle.marks)
			_expect(main_script._technique(step) == technique, "a %s drill starts where it's needed" % technique)

	_expect(game._menu.drills_button.is_visible_in_tree(), "the menu has Drills")
	game._menu.drills_button.pressed.emit()
	await _frames(3)
	_expect(game._drills.visible and not game._menu.visible, "Drills opens its screen")
	game._drills.buttons["group"].pressed.emit()
	await _settle()
	_expect(game._mode == game.Mode.DRILL and game._game.visible, "picking a technique starts its drill")
	_expect(game._puzzle_label.text == "Groups · 1 of 5", "the label names the drill and counts its boards")
	_expect(game._hint_label.text.begins_with("Groups:"), "the board opens with how the technique works")
	_expect(game._hint_button.visible and game._check_button.visible, "drills have hints and checks")
	_expect(not game._solution_button.visible and not game._clear_button.visible and not game._timer_label.visible,
			"drills have no solution, clear or clock")
	_expect(game._view.auto_cross, "drills cross out around crowns")
	var step := Grader.next_step(game._board.size, game._board.regions, game._board.marks)
	_expect(game._technique(step) == "group", "the board needs the drill's technique next")
	_expect(game._board_key.is_empty(), "drills aren't saved")
	var solved_before: int = game._progress.get_value("stats", "solved_6", 0)
	var sizes := []
	for board in 5:
		sizes.append(game._board.size)
		_solve_with_hints(game)
		await _frames(2)
		_expect(game._next_puzzle_button.visible, "each drill board has a next step")
		if board < 4:
			_expect(game._win_label.text == "Board %d of 5 done." % (board + 1), "the panel counts the boards")
			game._on_next_puzzle()
			await _settle()
	_expect(sizes == [6, 6, 7, 7, 8], "a drill's boards grow")
	_expect(game._win_label.text == "Drill complete!" and game._next_puzzle_button.text == "Again",
			"the last board finishes the drill")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("drills", "completed", {}).get("group", 0) == 1, "finished drills are counted")
	_expect(saved.get_value("stats", "solved_6", 0) == solved_before, "drill boards aren't counted as solves")
	game._on_next_puzzle()
	await _settle()
	_expect(game._puzzle_label.text == "Groups · 1 of 5", "Again starts the drill over")
	game._leave_game()
	await _frames(3)
	_expect(game._drills.visible and not game._game.visible, "leaving a drill goes back to Drills")
	_expect("Completed 1 time" in game._drills._details["group"].text, "Drills shows finished drills")
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)
	_expect(game._menu.visible and not game._drills.visible, "back from Drills goes to the menu")
	game.queue_free()
	await _frames(2)


func _check_stats_export() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var progress: ConfigFile = game._progress
	var saved := ConfigFile.new()
	for section in progress.get_sections():
		for key in progress.get_section_keys(section):
			saved.set_value(section, key, progress.get_value(section, key))
	for section in ["solved", "best", "solved_on"]:
		if progress.has_section(section):
			progress.erase_section(section)
	progress.set_value("solved", "7x7_hard_12", true)
	progress.set_value("best", "7x7_hard_12", 125.4)
	progress.set_value("solved_on", "7x7_hard_12", "2026-10-30")
	progress.set_value("solved", "daily_2026-10-23", true)
	progress.set_value("solved", "weekly_2026-10-26", true)
	progress.set_value("best", "weekly_2026-10-26", 600.0)
	progress.set_value("solved_on", "weekly_2026-10-26", "2026-10-28")
	progress.set_value("solved", "custom_6C-AbC_d", true)
	var lines: PackedStringArray = game._stats_csv().strip_edges().split("\n")
	_expect(lines[0] == "mode,puzzle,size,difficulty,solved_on,best_time,best_seconds,hints", "the CSV has a header")
	_expect(lines.size() == 5, "a row per solved puzzle")
	var daily_size: int = game._daily_size("2026-10-23")
	_expect(lines[1] == "Custom,6C-AbC_d,6,,,,,yes" and lines[2] == "Daily,2026-10-23,%d,Medium,,,,yes" % daily_size,
			"undated solves come first, with what's known about them")
	_expect(lines[3] == "Weekly,%s,10,Hard,2026-10-28,10:00,600.0,no" % game._week_first_day("2026-10-26"),
			"weeklies show their week and best time")
	_expect(lines[4] == "Puzzle,#12,7,Hard,2026-10-30,2:05,125.4,no", "numbered puzzles show their number")
	_expect(game._csv_field("a,b \"c\"") == "\"a,b \"\"c\"\"\"", "fields with commas or quotes are quoted")

	game._mark_solved("8x8_easy_3")
	_expect(progress.get_value("solved_on", "8x8_easy_3") == Time.get_date_string_from_system(), "solves note their day")
	progress.set_value("solved_on", "8x8_easy_3", "2026-10-01")
	game._mark_solved("8x8_easy_3")
	_expect(progress.get_value("solved_on", "8x8_easy_3") == "2026-10-01", "replays keep the first solve's day")
	var remote := ConfigFile.new()
	remote.set_value("solved_on", "8x8_easy_3", "2026-09-30")
	remote.set_value("solved_on", "7x7_hard_12", "2026-11-01")
	CloudSave.merge(progress, remote)
	_expect(progress.get_value("solved_on", "8x8_easy_3") == "2026-09-30"
			and progress.get_value("solved_on", "7x7_hard_12") == "2026-10-30", "merging keeps the earlier day")

	var path := ProjectSettings.globalize_path("user://test_export.csv")
	_expect(game._write_text(path, "a,b\n") and FileAccess.get_file_as_string(path) == "a,b\n", "the export writes its file")
	DirAccess.remove_absolute(path)
	game._menu.stats_button.pressed.emit()
	await _frames(2)
	_expect(game._stats.export_button.is_visible_in_tree(), "Stats has an export button")
	game._stats.show_export_result(true)
	_expect(game._stats._export_status.visible and game._stats._export_status.text == "Stats saved.", "it says the file was saved")
	game._show_menu()
	game._menu.stats_button.pressed.emit()
	_expect(not game._stats._export_status.visible, "the message is gone next time")

	for section in ["solved", "best", "solved_on"]:
		if progress.has_section(section):
			progress.erase_section(section)
		for key in saved.get_section_keys(section) if saved.has_section(section) else PackedStringArray():
			progress.set_value(section, key, saved.get_value(section, key))
	progress.save(TEST_SAVE)
	game.queue_free()
	await _frames(2)


## Stands in for the Android plugin: hands out `next_open` and keeps what it was given.
class FakeHomeScreen extends "res://scripts/home_screen.gd":
	var next_open := ""
	var shortcuts: Array = []
	var widget: Array = []
	var folder := ""

	func available() -> bool:
		return true

	func set_shortcuts(daily: String, weekly: String, resume: String) -> void:
		shortcuts = [daily, weekly, resume]

	func take_open() -> String:
		var open := next_open
		next_open = ""
		return open

	func update_widget(title: String, ready_text: String, solved_date: String, solved_text: String,
			streak_date: String, streak_text: String, offset: int, board_folder: String) -> void:
		widget = [title, ready_text, solved_date, solved_text, streak_date, streak_text, offset]
		folder = board_folder


func _check_home_screen() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var fake := FakeHomeScreen.new()
	game._home_screen = fake
	game._update_home_screen()
	_expect(fake.shortcuts == ["Daily puzzle", "Weekly challenge", "Continue"], "the shortcuts are labelled")
	var today: String = game._today()
	var progress: ConfigFile = game._progress
	var saved_streak: Array = [progress.get_value("stats", "streak", 0), progress.get_value("stats", "last_daily", ""),
			progress.get_value("solved", game._daily_key(today), false), progress.get_value("best", game._daily_key(today), INF)]
	progress.set_value("stats", "streak", 3)
	progress.set_value("stats", "last_daily", game._day_before(today))
	progress.set_value("solved", game._daily_key(today), false)
	game._update_home_screen()
	_expect(fake.widget == ["Daily puzzle", "Ready to play", "", "Solved (hints used)", game._day_before(today),
			"3 days streak", game.DAILY_UTC_OFFSET], "the widget offers today's daily and the streak")
	progress.set_value("solved", game._daily_key(today), true)
	progress.set_value("best", game._daily_key(today), 245.0)
	game._update_home_screen()
	_expect(fake.widget[2] == today and fake.widget[3] == "Solved in 4:05", "and shows it solved")
	while game._drawing_widget_boards:
		await process_frame
	var board_file: String = fake.folder.path_join("daily-%s.png" % today)
	var image := Image.load_from_file(board_file)
	_expect(image != null and image.get_width() == BoardImage.SIDE, "the widget gets today's board drawn")
	var later := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) + 6 * 86400)
	var later_size: int = game._daily_size(later)
	_expect(FileAccess.file_exists(fake.folder.path_join("daily-%s.png" % later))
			and FileAccess.get_file_as_string(fake.folder.path_join("daily-%s.txt" % later)) == "%d×%d · Medium" % [later_size, later_size],
			"and the coming week's, with each day's size and difficulty")
	# The board drawn is the daily's: the same regions colour the same tiles.
	var daily: Dictionary = Generator.generate(game._daily_size(today), game.DAILY_DIFFICULTY, game._seeded(hash(["daily", today])))
	var n: int = game._daily_size(today)
	var cell := float(BoardImage.SIDE) / n
	var same := true
	for i in n * n:
		for j in n * n:
			var a := image.get_pixel(int((i % n + 0.5) * cell), int((i / n + 0.5) * cell))
			var b := image.get_pixel(int((j % n + 0.5) * cell), int((j / n + 0.5) * cell))
			if (daily.regions[i] == daily.regions[j]) != a.is_equal_approx(b):
				same = false
	_expect(same, "the drawn board is today's daily")
	var stale: String = fake.folder.path_join("daily-2000-01-01.png")
	FileAccess.open(stale, FileAccess.WRITE).store_string("x")
	game._update_home_screen()
	_expect(not FileAccess.file_exists(stale), "past days' boards are cleared away")
	for file in DirAccess.get_files_at(fake.folder):
		DirAccess.remove_absolute(fake.folder.path_join(file))

	game._menu.stats_button.pressed.emit()
	await _frames(2)
	fake.next_open = "weekly"
	game._open_requested()
	await _settle()
	_expect(game._mode == game.Mode.WEEKLY and game._game.visible and not game._stats.visible,
			"a shortcut opens the weekly from any screen")
	fake.next_open = "daily"
	game._open_requested()
	await _settle()
	_expect(game._mode == game.Mode.DAILY and game._daily_date == today and not game._from_archive,
			"the widget and the reminder open today's daily")
	fake.next_open = "continue"
	game._open_requested()
	await _settle()
	_expect(game._mode == game.Mode.REGULAR and game._game.visible, "Continue opens the numbered puzzles")
	game._open_requested()
	await _frames(2)
	_expect(game._mode == game.Mode.REGULAR, "nothing asked, nothing changes")

	progress.set_value("stats", "streak", saved_streak[0])
	progress.set_value("stats", "last_daily", saved_streak[1])
	progress.set_value("solved", game._daily_key(today), saved_streak[2])
	if saved_streak[3] == INF:
		progress.erase_section_key("best", game._daily_key(today))
	else:
		progress.set_value("best", game._daily_key(today), saved_streak[3])
	game._show_menu()
	progress.save(TEST_SAVE)
	game.queue_free()
	await _frames(2)


func _check_updater() -> void:
	_expect(Updater.is_newer("1.1", "1.0") and Updater.is_newer("1.10", "1.9") and Updater.is_newer("2.0", "1.9.9")
			and not Updater.is_newer("1.0", "1.0") and not Updater.is_newer("0.3", "1.0") and Updater.is_newer("1.0.1", "1.0"),
			"versions compare part by part")
	var apk := func(version: String) -> Array:
		return [{"name": "Crowns-%s-android.apk" % version, "browser_download_url": "https://example.test/%s.apk" % version},
				{"name": "Crowns-%s-linux-x86_64.tar.gz" % version, "browser_download_url": "https://example.test/linux"}]
	var releases := [
		{"tag_name": "v1.3", "draft": true, "prerelease": false, "html_url": "draft", "assets": apk.call("1.3")},
		{"tag_name": "v1.2", "draft": false, "prerelease": true, "html_url": "https://example.test/v1.2", "assets": apk.call("1.2")},
		{"tag_name": "v1.10", "draft": false, "prerelease": false, "html_url": "https://example.test/v1.10", "assets": []},
		{"tag_name": "v1.0", "draft": false, "prerelease": false, "html_url": "https://example.test/v1.0", "assets": apk.call("1.0")},
	]
	_expect(Updater.newest(releases, "1.0", true) == {"version": "1.2", "page": "https://example.test/v1.2",
			"apk": "https://example.test/1.2.apk"}, "Android takes the newest release with an APK, prereleases too, not drafts")
	_expect(Updater.newest(releases, "1.0", false).version == "1.10", "desktop takes the newest release")
	_expect(Updater.newest(releases, "1.10", false).is_empty() and Updater.newest(null, "1.0", false).is_empty()
			and Updater.newest({"message": "rate limited"}, "1.0", true).is_empty(), "nothing newer, nothing found")

	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(not game._updater.available() and not game._settings.check_updates_toggle.visible,
			"the editor and tests never check for updates")
	_expect(not game._menu.update_bar.visible, "no update, no bar")
	game._updater.release = Updater.newest(releases, "1.0", false)
	game._on_update_found("1.10")
	await _frames(2)
	_expect(game._menu.update_bar.visible and game._menu._update_label.text == "Version 1.10 is out"
			and game._menu.update_button.text == "Download", "a newer version shows on the menu")
	var menu_box: Rect2 = game._menu._box.get_global_rect()
	_expect(menu_box.position.y >= 0.0 and menu_box.end.y <= game._menu.size.y, "the menu still fits with the update bar")
	game._on_update_downloaded("")
	_expect(game._menu._update_label.text == "Couldn't download the update" and game._menu.update_button.text == "Try again"
			and not game._menu.update_button.disabled, "a failed download can be tried again")
	game._settings.check_updates_toggle.button_pressed = false
	_expect(not game._menu.update_bar.visible and game._progress.get_value("settings", "check_updates") == false,
			"turning checks off hides the bar")
	game._settings.check_updates_toggle.button_pressed = true
	game.queue_free()
	await _frames(2)


func _check_colour_names() -> void:
	var view := BoardViewScript.new()
	root.add_child(view)
	var swedish := Translation.new()
	swedish.locale = "sv"
	swedish.add_message("purple", "lila")
	swedish.add_message("orange", "orangea")
	swedish.add_message("orange", "orange", "colour alone")
	swedish.add_message("the %s region", "den %s regionen")
	TranslationServer.add_translation(swedish)
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("sv")
	_expect(view.region_name(1) == "orangea" and view.colour_name(1) == "orange",
			"colours have one form inside \"the %s region\" and another on their own")
	_expect(view.colour_name(0) == "lila", "an untranslated colour on its own uses the in-phrase form")
	_expect(view.tr("the %s region") % view.region_name(1) == "den orangea regionen", "the article is the translator's")
	TranslationServer.set_locale(locale)
	TranslationServer.remove_translation(swedish)
	_expect(view.colour_name(2) == "blue" and view.region_name(2) == "blue", "English uses the same word for both")
	view.queue_free()


func _check_dim_finished() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	_expect(not game._view.dim_finished, "dimming finished lines is off by default")
	game._settings.dim_finished_toggle.button_pressed = true
	_expect(game._view.dim_finished, "dimming finished lines turns on from settings")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "dim_finished", false) == true, "the dimming setting is saved")
	game._settings.dim_finished_toggle.button_pressed = false
	game.queue_free()
	await _frames(2)

	# Regions are the rows of a 5x5 board; crowns are the solution's.
	var regions := PackedInt32Array()
	for row in 5:
		for col in 5:
			regions.append(row)
	var solution := PackedInt32Array([0, 2, 4, 1, 3])
	var board := Board.new(5, regions, solution)
	var view := BoardViewScript.new()
	view.board = board
	view.dim_finished = true
	_expect(view._finished_cells().count(1) == 0, "nothing is dimmed on an empty board")
	board.set_mark(Vector2i(0, 0), Board.Mark.CROWN)
	var finished := view._finished_cells()
	_expect(finished[board.index(Vector2i(0, 4))] == 1, "a crown's row is finished")
	_expect(finished[board.index(Vector2i(4, 0))] == 1, "a crown's column is finished")
	_expect(finished[board.index(Vector2i(1, 1))] == 0, "cells outside its lines stay open")
	_expect(finished.count(1) == 9, "a crown finishes its row and column, here also its region")
	view.size = Vector2(root.size)
	root.add_child(view)
	await _frames(3)
	_screenshot("dim_finished.png")
	view.queue_free()


func _check_languages() -> void:
	_expect(FileAccess.get_file_as_string("res://translations/crowns.pot") == UpdatePot.build(),
			"translations/crowns.pot is up to date (run tools/update_pot.gd)")

	var german := Translation.new()
	german.locale = "de"
	german.add_message("English", "Deutsch", "language name")
	german.add_message("Dark", "Dunkel")
	german.add_plural_message("%d puzzle", PackedStringArray(["%d Rätsel", "%d Rätsel"]))
	TranslationServer.add_translation(german)

	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var picker: OptionButton = game._settings.language_picker
	var items := []
	for i in picker.item_count:
		items.append(picker.get_item_text(i))
	# The shipped translations are listed too, so only the test's German is checked by name.
	var german_index := items.find("Deutsch (%d%%)" % floori(300.0 / Language.template_keys().size()))
	_expect(items.slice(0, 2) == ["Device language", "English"] and german_index > 1
			and items.size() == Language.locales().size() + 1, "language picker lists the languages by their own names")
	_expect(picker.selected == 0, "language follows the device by default")
	var keys := Language.template_keys()
	# Every msgid but the header's empty one.
	_expect(keys.size() == FileAccess.get_file_as_string(Language.TEMPLATE).count("\nmsgid ") - 1
			and "language name\u0004English" in keys and "Dark" in keys, "the template's strings are all counted")
	_expect(Language.completion("en") == 1.0 and is_equal_approx(Language.completion("de"), 3.0 / keys.size()),
			"a translation's completion is its share of the template")

	picker.select(german_index)
	picker.item_selected.emit(german_index)
	await _frames(3)
	var fresh: Control = root.get_children().filter(func(node: Node) -> bool:
		return node.get("open_settings") == true and not node.is_queued_for_deletion()).back()
	_expect(fresh != null and not is_instance_valid(game), "choosing a language rebuilds the game")
	_expect(fresh._settings.visible and fresh._settings.theme_picker.get_item_text(1) == "Dunkel",
			"the rebuilt game shows Settings in the new language")
	_expect(fresh._puzzles(2) == "2 Rätsel" and fresh._settings.language_picker.selected == german_index, "plurals and the picker follow the language")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "language", "") == "de", "language choice is saved")

	_expect(fresh.get_viewport().gui_get_focus_owner() == null, "a language tapped in leaves nothing selected")

	# Chosen with a gamepad or the keyboard: the picker stays selected after the rebuild.
	fresh._settings.language_picker.grab_focus()
	fresh._settings.language_picker.item_selected.emit(0)
	await _frames(3)
	var english: Control = root.get_children().filter(func(node: Node) -> bool:
		return node.get("open_settings") == true and not node.is_queued_for_deletion()).back()
	_expect(english._settings.theme_picker.get_item_text(1) == "Dark", "device language switches back")
	_expect(english.get_viewport().gui_get_focus_owner() == english._settings.language_picker,
			"a language chosen with a gamepad keeps the language picker selected")
	_expect(not english.is_layout_rtl(), "English lays out left to right")
	english.queue_free()
	TranslationServer.remove_translation(german)
	await _frames(2)

	# Right-to-left: the layout mirrors, but the board and its numbering don't.
	var arabic := Translation.new()
	arabic.locale = "ar"
	arabic.add_message("English", "العربية", "language name")
	TranslationServer.add_translation(arabic)
	var saved_rtl := ConfigFile.new()
	saved_rtl.load(TEST_SAVE)
	saved_rtl.set_value("settings", "language", "ar")
	saved_rtl.save(TEST_SAVE)
	var rtl: Control = load("res://main.tscn").instantiate()
	rtl.save_path = TEST_SAVE
	root.add_child(rtl)
	await _frames(3)
	# Arrows like the archive's ‹ › need nothing: right-to-left text mirrors them itself.
	_expect(rtl.is_layout_rtl() and rtl._menu.is_layout_rtl(), "Arabic lays out right to left")
	_expect(rtl.theme.get_stylebox("normal_mirrored", "OptionButton") == rtl.theme.get_stylebox("normal", "Button"),
			"dropdowns keep their style when mirrored")
	_expect(ThemeDB.fallback_font.fallbacks.any(func(font: Font) -> bool:
			return font.has_char("ا".unicode_at(0))) and ThemeDB.fallback_font.fallbacks.any(func(font: Font) -> bool:
			return font.has_char("א".unicode_at(0))), "Arabic and Hebrew letters are bundled")
	rtl._start(rtl.Mode.REGULAR)
	await _settle()
	var view: Control = rtl._view
	var pressed := Vector2i(0, 0)
	await _slow_click(view, pressed)
	_expect(rtl._board.get_mark(pressed) == Board.Mark.CROSS, "the board isn't mirrored: column 1 stays on the left")
	saved_rtl.load(TEST_SAVE)
	saved_rtl.set_value("settings", "language", "")
	saved_rtl.save(TEST_SAVE)
	rtl.queue_free()
	TranslationServer.remove_translation(arabic)
	await _frames(2)


func _archive_day(archive: Control, date: String) -> Button:
	var day := str(date.split("-")[2].to_int())
	for child in archive._grid.get_children():
		if child is Button and child.text.get_slice("\n", 0) == day:
			return child
	return null


func _cell_center(view: Control, cell: Vector2i) -> Vector2:
	var cs: float = view._cell_size()
	return view._origin() + (Vector2(cell.y, cell.x) + Vector2(0.5, 0.5)) * cs


func _mouse_button(view: Control, pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _to_window(view, pos)
	event.global_position = event.position
	Input.parse_input_event(event)


## A point in `view` as the window sees it, through any scaling of the interface.
func _to_window(view: Control, pos: Vector2) -> Vector2:
	return view.get_viewport().get_final_transform() * view.get_global_transform_with_canvas() * pos


func _click(view: Control, cell: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	var pos := _cell_center(view, cell)
	_mouse_button(view, pos, true, button)
	await _frames(1)
	_mouse_button(view, pos, false, button)
	await _frames(1)


## Drags along `row` from its first cell to its last, with a motion event on
## every cell, or only one at the far end when `fast`.
func _drag_row(view: Control, row: int, fast := false) -> void:
	var cols: int = view.board.size
	_mouse_button(view, _cell_center(view, Vector2i(row, 0)), true)
	for col in range(cols - 1 if fast else 1, cols):
		var motion := InputEventMouseMotion.new()
		motion.position = _to_window(view, _cell_center(view, Vector2i(row, col)))
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await _frames(1)
	_mouse_button(view, _cell_center(view, Vector2i(row, cols - 1)), false)
	await _frames(2)


func _count_row(board: Board, row: int, mark: int) -> int:
	var count := 0
	for col in board.size:
		if board.get_mark(Vector2i(row, col)) == mark:
			count += 1
	return count


func _touch(view: Control, cell: Vector2i) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.pressed = pressed
		event.position = _to_window(view, _cell_center(view, cell))
		Input.parse_input_event(event)
		await _frames(1)


## A click long enough after the previous one that it can't count as a double tap.
func _slow_click(view: Control, cell: Vector2i) -> void:
	view._tap_time = -view.DOUBLE_TAP_MS
	await _click(view, cell)


func _right_click(view: Control, cell: Vector2i) -> void:
	await _click(view, cell, MOUSE_BUTTON_RIGHT)


## Waits a few frames, then for any game still generating its puzzle in the background.
func _settle() -> void:
	await _frames(10)
	while root.get_children().any(func(node: Node) -> bool: return node.get("_generating") == true):
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _screenshot(file: String) -> void:
	if shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(shot_dir.path_join(file))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
