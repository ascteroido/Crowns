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
const SilentWolf := preload("res://scripts/silent_wolf.gd")
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

	# Settings: dark mode recolours the screen and is saved.
	main._menu.settings_button.pressed.emit()
	_expect(main._settings.visible and not main._menu.visible, "settings opens from the menu")
	main._settings.dark_mode_toggle.button_pressed = true
	await _frames(3)
	_expect(main._background.color == main.DARK.background and main._view.dark, "dark mode applies")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "dark_mode", false) == true, "dark mode is saved")
	_screenshot("settings_dark.png")
	main._settings.back.emit()
	_expect(main._menu.visible and not main._settings.visible, "back returns to the menu")
	await _frames(2)
	_screenshot("menu_dark.png")
	main._show_settings()
	main._settings.dark_mode_toggle.button_pressed = false
	_expect(main._background.color == main.LIGHT.background and not main._view.dark, "light mode restores")
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
	await _frames(3)
	_screenshot("archive.png")
	archive.back.emit()
	_expect(main._menu.visible and not archive.visible, "archive back returns to the menu")

	main._menu.continue_button.pressed.emit()
	await _settle()
	_expect(main._mode == main.Mode.REGULAR and main._number == 2 and main._next_button.visible, "continue resumes the regular puzzles")
	main._on_dark_mode_toggled(true)
	await _right_click(view, Vector2i(0, 0))
	await _click(view, Vector2i(2, 2))
	await _frames(2)
	_screenshot("game_dark.png")
	main._on_dark_mode_toggled(false)

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
	for difficulty in [Generator.Difficulty.EASY, Generator.Difficulty.HARD]:
		graded._difficulty_picker.select(difficulty)
		graded._on_difficulty_selected(difficulty)
		await _settle()
		var b: Board = graded._board
		_expect(graded._number == 1 and Grader.grade(b.size, b.regions) == difficulty + 1,
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
	await _check_weekly()
	await _frames(2)
	await _check_puzzle_code()
	await _frames(2)
	await _check_prefetch()
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
	await _check_languages()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


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


func _check_puzzle_code() -> void:
	var sizes := [5, 6, 7, 8, 9, 10]
	_expect(PuzzleCode.encode(8, Generator.Difficulty.HARD, 142) == "8H-142", "codes read size, difficulty, number")
	_expect(PuzzleCode.decode("8H-142", sizes) == {"size": 8, "difficulty": Generator.Difficulty.HARD, "number": 142},
			"a code decodes")
	_expect(PuzzleCode.decode("Try this Crowns puzzle: 6e 12!", sizes).get("number") == 12
			and PuzzleCode.decode("10m#3", sizes).get("size") == 10, "codes are found loosely in pasted text")
	_expect(PuzzleCode.decode("4H-1", sizes).is_empty() and PuzzleCode.decode("8X-1", sizes).is_empty()
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


func _check_weekly() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	await _frames(3)
	var week: String = game._week_start()
	var start := Time.get_unix_time_from_datetime_string(week)
	var today := Time.get_unix_time_from_datetime_string(game._today())
	_expect(Time.get_datetime_dict_from_unix_time(start).weekday == Time.WEEKDAY_SUNDAY
			and today - start == game._weekday() * 86400, "the weekly challenge starts on the latest Sunday")
	var days_left: int = 7 - game._weekday()
	_expect(game._menu._weekly_detail.text.begins_with("Week of " + game._pretty_date(week))
			and game._menu._weekly_detail.text.ends_with("%d day%s left" % [days_left, "" if days_left == 1 else "s"]),
			"menu shows the week and the days left")

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

	# Play Games only exists on Android; elsewhere its buttons stay hidden and calls do nothing.
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
	_screenshot("stats.png")
	game._stats.back.emit()
	_expect(game._menu.visible and not game._stats.visible, "back returns from stats")
	game.queue_free()


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


func _check_languages() -> void:
	_expect(FileAccess.get_file_as_string("res://translations/crowns.pot") == UpdatePot.build(),
			"translations/crowns.pot is up to date (run tools/update_pot.gd)")

	var german := Translation.new()
	german.locale = "de"
	german.add_message("English", "Deutsch", "language name")
	german.add_message("Dark mode", "Dunkelmodus")
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
			and "language name\u0004English" in keys and "Dark mode" in keys, "the template's strings are all counted")
	_expect(Language.completion("en") == 1.0 and is_equal_approx(Language.completion("de"), 3.0 / keys.size()),
			"a translation's completion is its share of the template")

	picker.select(german_index)
	picker.item_selected.emit(german_index)
	await _frames(3)
	var fresh: Control = root.get_children().filter(func(node: Node) -> bool:
		return node.get("open_settings") == true and not node.is_queued_for_deletion()).back()
	_expect(fresh != null and not is_instance_valid(game), "choosing a language rebuilds the game")
	_expect(fresh._settings.visible and fresh._settings.dark_mode_toggle.text == "Dunkelmodus",
			"the rebuilt game shows Settings in the new language")
	_expect(fresh._puzzles(2) == "2 Rätsel" and fresh._settings.language_picker.selected == german_index, "plurals and the picker follow the language")
	var saved := ConfigFile.new()
	saved.load(TEST_SAVE)
	_expect(saved.get_value("settings", "language", "") == "de", "language choice is saved")

	fresh._settings.language_picker.item_selected.emit(0)
	await _frames(3)
	var english: Control = root.get_children().filter(func(node: Node) -> bool:
		return node.get("open_settings") == true and not node.is_queued_for_deletion()).back()
	_expect(english._settings.dark_mode_toggle.text == "Dark mode", "device language switches back")
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
	event.position = view.get_global_transform() * pos
	event.global_position = event.position
	Input.parse_input_event(event)


func _click(view: Control, cell: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	var pos := _cell_center(view, cell)
	_mouse_button(view, pos, true, button)
	await _frames(1)
	_mouse_button(view, pos, false, button)
	await _frames(1)


func _drag_row(view: Control, row: int) -> void:
	var cols: int = view.board.size
	_mouse_button(view, _cell_center(view, Vector2i(row, 0)), true)
	for col in range(1, cols):
		var motion := InputEventMouseMotion.new()
		motion.position = view.get_global_transform() * _cell_center(view, Vector2i(row, col))
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
		event.position = view.get_global_transform() * _cell_center(view, cell)
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
