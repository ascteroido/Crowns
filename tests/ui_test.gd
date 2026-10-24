extends SceneTree
## Drives the game screen with simulated clicks:
##   godot --path . --script res://tests/ui_test.gd [-- screenshot_dir]
## Saves screenshots when a directory is given and a renderer is available.

const Board := preload("res://scripts/board.gd")
const Generator := preload("res://scripts/generator.gd")
const Grader := preload("res://scripts/grader.gd")
const TEST_SAVE := "user://test_progress.cfg"

var failures := 0
var shot_dir := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		shot_dir = args[0]
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = TEST_SAVE
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
	await _frames(10)
	var view: Control = main._view
	var board: Board = main._board
	_expect(board != null and view.interactive, "puzzle generated and board accepts input")

	# Slow clicks cycle empty -> cross -> crown -> empty.
	var target := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "first click crosses")
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "second click places a crown")
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.EMPTY, "third click empties")

	# A double tap places a crown whatever the cell held.
	await _slow_click(view, target)
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "double tap on empty places a crown")
	await _slow_click(view, target)
	await _slow_click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "slow taps keep cycling")
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
	await _frames(10)
	_expect(main._number == 2 and not main._win_overlay.visible and main._board != board, "next puzzle loads")
	_screenshot("next.png")

	# Back to the menu, then the daily puzzle.
	main._show_menu()
	_expect(main._menu.visible and not main._running, "menu button returns to the menu and pauses")
	_expect(main._menu.continue_button.text == "Continue", "menu offers Continue once started")
	main._menu.daily_button.pressed.emit()
	await _frames(10)
	var daily: Board = main._board
	_expect(main._mode == main.Mode.DAILY and main.DAILY_SIZES.has(daily.size), "daily puzzle loads with a daily size")
	_expect(not main._size_picker.visible and not main._next_button.visible, "daily hides size and navigation")
	_expect(main._puzzle_label.text.begins_with("Daily"), "daily label shown")
	_screenshot("daily.png")

	main._show_menu()
	main._menu.daily_button.pressed.emit()
	await _frames(10)
	_expect(main._board.regions == daily.regions, "daily puzzle is the same when reopened")
	_solve_with_hints(main)
	await _frames(3)
	_expect(main._win_overlay.visible and not main._next_puzzle_button.visible, "daily win has no next puzzle")
	main._show_menu()
	_expect(main._menu._daily_detail.text == "Solved (hints used)", "menu shows the daily as solved")

	main._menu.continue_button.pressed.emit()
	await _frames(10)
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
	await _frames(10)
	_expect(main._board.marks == in_progress, "marks restored after visiting the menu")
	_expect(main._elapsed >= 42.0 and main._elapsed < 43.0, "timer restored after visiting the menu")
	main._go_to(3)
	await _frames(10)
	_expect(not main._board.marks.has(Board.Mark.CROWN), "another puzzle starts from its own board")
	main._go_to(2)
	await _frames(10)
	_expect(main._board.marks == in_progress, "marks restored after switching puzzles")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	main.queue_free()
	await _frames(2)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.save_path = TEST_SAVE
	root.add_child(reopened)
	await _frames(3)
	reopened._menu.continue_button.pressed.emit()
	await _frames(10)
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
	await _frames(10)
	var medium_regions: PackedInt32Array = graded._board.regions
	_expect(graded._difficulty_picker.visible and graded._difficulty == Generator.Difficulty.MEDIUM, "regular puzzles default to Medium")
	for difficulty in [Generator.Difficulty.EASY, Generator.Difficulty.HARD]:
		graded._difficulty_picker.select(difficulty)
		graded._on_difficulty_selected(difficulty)
		await _frames(10)
		var b: Board = graded._board
		_expect(graded._number == 1 and Grader.grade(b.size, b.regions) == difficulty + 1,
				"%s puzzle grades as %s" % [Generator.DIFFICULTY_NAMES[difficulty], Generator.DIFFICULTY_NAMES[difficulty]])
		_expect(graded._puzzle_key().contains(Generator.DIFFICULTY_NAMES[difficulty].to_lower()), "save key includes the difficulty")
	_screenshot("hard.png")
	graded._show_menu()
	_expect(graded._menu._continue_detail.text.contains("Hard"), "menu shows the chosen difficulty")
	graded._menu.daily_button.pressed.emit()
	await _frames(10)
	_expect(not graded._difficulty_picker.visible, "daily hides the difficulty picker")
	graded.queue_free()
	await _frames(2)
	await _check_challenge()

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
	await _frames(10)
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
	_expect(game._progress.get_value("challenge", "best", 0) == 1, "best run counts the solved puzzle")
	game._elapsed = 30.0
	game._run.elapsed = 30.0
	game._next_puzzle_button.pressed.emit()
	await _frames(10)
	board = game._board
	_expect(game._puzzle_label.text.begins_with("The Climb #2") and game._elapsed >= 30.0, "next puzzle continues the run")

	# Leaving mid-run keeps the run and its board.
	await _click(view, Vector2i(0, 0))
	var marks: PackedInt32Array = board.marks.duplicate()
	game._show_menu()
	_expect(game._menu._challenge_detail.text == "Run in progress · Puzzle 2", "menu offers the run in progress")
	game._menu.challenge_button.pressed.emit()
	await _frames(10)
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
	await _frames(10)
	_expect(game._run.level == 1 and game._board.size == 5 and view.mistake == Vector2i(-1, -1), "a new run starts from the first puzzle")
	_expect(game.CHALLENGE_STAGES[-1] == [10, Generator.Difficulty.HARD], "challenge ramps up to 10x10 Hard")
	game._run.level = 99
	_expect(game._challenge_stage() == game.CHALLENGE_STAGES[-1], "the last stage repeats")
	game.queue_free()


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
