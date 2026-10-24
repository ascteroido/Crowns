extends SceneTree
## Drives the game screen with simulated clicks:
##   godot --path . --script res://tests/ui_test.gd [-- screenshot_dir]
## Saves screenshots when a directory is given and a renderer is available.

const Board := preload("res://scripts/board.gd")
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

	# Click empty -> cross -> crown -> empty.
	var target := Vector2i(0, (board.solution[0] + 2) % board.size)
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROSS, "first click crosses")
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.CROWN, "second click places a crown")
	await _click(view, target)
	_expect(board.get_mark(target) == Board.Mark.EMPTY, "third click empties")

	# Drag across the bottom row crosses every cell in one undo step.
	var undo_before: int = main._undo.size()
	var last := board.size - 1
	await _drag_row(view, last)
	_expect(_count_row(board, last, Board.Mark.CROSS) == board.size, "drag crossed the whole row")
	_expect(main._undo.size() == undo_before + 1, "drag is a single undo step")

	# Dragging from a cross erases every cross it passes, also in one undo step.
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

	# Solve through hints and check the win overlay.
	for i in board.size:
		main._on_hint()
	await _frames(3)
	_expect(board.is_solved(), "hints solve the puzzle")
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
	_expect(main._daily and main.DAILY_SIZES.has(daily.size), "daily puzzle loads with a daily size")
	_expect(not main._size_picker.visible and not main._next_button.visible, "daily hides size and navigation")
	_expect(main._puzzle_label.text.begins_with("Daily"), "daily label shown")
	_screenshot("daily.png")

	main._show_menu()
	main._menu.daily_button.pressed.emit()
	await _frames(10)
	_expect(main._board.regions == daily.regions, "daily puzzle is the same when reopened")
	for i in main._board.size:
		main._on_hint()
	await _frames(3)
	_expect(main._win_overlay.visible and not main._next_puzzle_button.visible, "daily win has no next puzzle")
	main._show_menu()
	_expect(main._menu._daily_detail.text == "Solved (hints used)", "menu shows the daily as solved")

	main._menu.continue_button.pressed.emit()
	await _frames(10)
	_expect(not main._daily and main._number == 2 and main._next_button.visible, "continue resumes the regular puzzles")
	main._on_dark_mode_toggled(true)
	await _right_click(view, Vector2i(0, 0))
	await _click(view, Vector2i(2, 2))
	await _frames(2)
	_screenshot("game_dark.png")
	main._on_dark_mode_toggled(false)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


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
