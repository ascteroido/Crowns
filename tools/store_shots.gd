extends SceneTree
## Takes store screenshots at 1080x1920:
##   godot --path . --script res://tools/store_shots.gd -- <out_dir> [play|itch]
## "play" shows the Play Games buttons and stops at eight, Google Play's limit;
## "itch" adds The Climb, the SilentWolf leaderboard screen (with made-up scores,
## nothing is sent), a tutorial lesson and a 1920x1080 wide-screen game.

const Board := preload("res://scripts/board.gd")
const Generator := preload("res://scripts/generator.gd")
const SilentWolf := preload("res://scripts/silent_wolf.gd")
const SAVE := "user://store_shots.cfg"
const SIZE := Vector2i(1080, 1920)
const WIDE_SIZE := Vector2i(1920, 1080)

var out_dir := ""
var itch := false
var viewport: SubViewport


func _init() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	itch = OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "itch"
	SilentWolf.offline = true
	# Silent, as it runs with a window.
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_seed_save()
	# The screen is too short for a 1920 px window, so render off screen, scaled
	# from the game's 640 px wide layout like the window's canvas_items stretch.
	viewport = SubViewport.new()
	viewport.size_2d_override_stretch = true
	viewport.oversampling = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_set_size(SIZE)
	root.add_child(viewport)

	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = SAVE
	main.first_run_tutorial = false
	viewport.add_child(main)
	# Portrait like a phone: no Exit. Play: the Play Games buttons; itch: SilentWolf.
	main._menu.exit_button.visible = false
	main._menu.leaderboards_button.visible = true
	main._stats.achievements_button.visible = not itch
	if itch:
		main._silent_wolf.api_key = "screenshots"
		_fake_scores(main)
	# Phones show neither the keyboard nor the gamepad help; this computer may have a gamepad.
	var help: Label = main._game_parts[5]
	var desktop_help := help.text
	help.text = help.text.get_slice("\n" + main.tr("Keys: arrows, Space: ×, Enter: crown, H: hint, Ctrl+Shift+Z: redo."), 0)
	main._pad_help.visible = false
	main._editor._pad_help.visible = false
	await _frames(5)
	await _shot("6_menu.png")

	# Stats scrolled down to the solve history graph.
	main._show_stats()
	await _frames(3)
	var scroll: ScrollContainer = main._stats.find_children("*", "ScrollContainer", true, false)[0]
	scroll.scroll_vertical = int(main._stats.history_graph.get_global_rect().end.y - scroll.size.y * 0.8)
	await _shot("7_stats.png")
	main._show_menu()

	# The puzzle editor with a finished design, checked and graded.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	var design: Dictionary = Generator.generate(7, Generator.Difficulty.MEDIUM, rng)
	main._progress.set_value("editor", "size", 7)
	main._progress.set_value("editor", "regions", design.regions)
	main._show_editor()
	main._editor._select_color(2)
	await _shot("8_editor.png")
	main._show_menu()

	if itch:
		main._show_leaderboards("daily")
		await _shot("10_leaderboards.png", 1200)
		main._show_menu()
		main._start_lesson(2)
		await _wait_ready(main)
		while main._tutorial_card < main._tutorial_cards().size():
			main._on_hint()
		await _shot("11_tutorial.png")
		main._show_menu()

	# A regular puzzle part way through, with auto crosses around the crowns.
	main._start(main.Mode.REGULAR)
	await _wait_ready(main)
	main._on_auto_cross_toggled(true)
	var board: Board = main._board

	# A teaching hint, skipping ahead past the simple "only one cell left" ones.
	for i in 60:
		main._on_hint()
		if not main._hint_label.text.contains("only one cell left"):
			break
		main._on_hint()
	print("hint: ", main._hint_label.text)
	_set_time(main, 131.0)
	await _shot("2_hint.png")
	main._clear_hint()
	main._on_clear()

	for row in [1, 4, 6]:
		main._apply([[Vector2i(row, board.solution[row]), Board.Mark.EMPTY, Board.Mark.CROWN]])
	_set_time(main, 98.0)
	await _shot("1_game.png")

	# The finished puzzle.
	main._hinted = false
	for row in board.size:
		var cell := Vector2i(row, board.solution[row])
		if board.get_mark(cell) != Board.Mark.CROWN:
			board.set_mark(cell, Board.Mark.CROWN)
	for change in board.auto_cross_changes():
		board.set_mark(change[0], change[2])
	main._elapsed = 187.0
	main._check_win()
	await _shot("5_solved.png", 1800)

	# The daily puzzle in dark mode with region patterns.
	main._show_menu()
	main._on_theme_chosen("dark")
	main._on_patterns_toggled(true)
	main._start(main.Mode.DAILY)
	await _wait_ready(main)
	board = main._board
	for row in [0, 3]:
		main._apply([[Vector2i(row, board.solution[row]), Board.Mark.EMPTY, Board.Mark.CROWN]])
	_set_time(main, 74.0)
	await _shot("3_daily_dark.png")

	# A big Hard+ board from the ready-made sets, in the Forest theme.
	main._show_menu()
	main._on_theme_chosen("forest")
	main._on_patterns_toggled(false)
	main._size = 12
	main._difficulty = Generator.Difficulty.HARD_PLUS
	main._number = 3
	main._start(main.Mode.REGULAR)
	await _wait_ready(main)
	_sync_pickers(main)
	board = main._board
	for row in [1, 4, 8, 10]:
		main._apply([[Vector2i(row, board.solution[row]), Board.Mark.EMPTY, Board.Mark.CROWN]])
	_set_time(main, 1264.0)
	await _shot("4_big_board.png")
	main._on_clear()
	main._on_theme_chosen("light")

	if itch:
		# The Climb, a few puzzles in.
		main._show_menu()
		main._run = {"seed": 271828, "level": 7, "elapsed": 612.0}
		main._start(main.Mode.CHALLENGE)
		await _wait_ready(main)
		board = main._board
		for row in [2, 5]:
			main._apply([[Vector2i(row, board.solution[row]), Board.Mark.EMPTY, Board.Mark.CROWN]])
		_set_time(main, 655.0)
		await _shot("9_climb.png")
		main._running = false
		main._run = {}

		# A wide window: the board beside the controls, in the Midnight theme.
		main._show_menu()
		main._on_theme_chosen("midnight")
		_set_size(WIDE_SIZE)
		# A computer: the keyboard help, but no gamepad plugged in.
		help.text = desktop_help
		main._size = 9
		main._difficulty = Generator.Difficulty.MEDIUM
		main._number = 5
		main._start(main.Mode.REGULAR)
		await _wait_ready(main)
		_sync_pickers(main)
		board = main._board
		for row in [0, 3, 7]:
			main._apply([[Vector2i(row, board.solution[row]), Board.Mark.EMPTY, Board.Mark.CROWN]])
		_set_time(main, 143.0)
		await _shot("12_wide.png")
		main._on_clear()
		main._on_theme_chosen("light")

	main._running = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()


## Example progress so the menu and stats screens aren't empty.
func _seed_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("last", "size", 8)
	cfg.set_value("last", "number", 12)
	cfg.set_value("last", "difficulty", 1)
	var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 7 * 3600 - 86400)
	cfg.set_value("stats", "last_daily", yesterday)
	cfg.set_value("stats", "streak", 12)
	cfg.set_value("stats", "longest_streak", 19)
	cfg.set_value("stats", "dailies_solved", 41)
	cfg.set_value("stats", "weeklies_solved", 6)
	var solved := {5: 9, 6: 14, 7: 22, 8: 11, 9: 6, 10: 3}
	var average := {5: 48.0, 6: 83.0, 7: 132.0, 8: 205.0, 9: 291.0, 10: 402.0}
	var best := {5: 21.0, 6: 37.0, 7: 64.0, 8: 118.0, 9: 176.0, 10: 254.0}
	for size: int in solved:
		cfg.set_value("stats", "solved_%d" % size, solved[size])
		cfg.set_value("stats", "timed_%d" % size, solved[size])
		cfg.set_value("stats", "time_%d" % size, average[size] * solved[size])
		cfg.set_value("stats", "best_%d" % size, best[size])
	# Recent 8x8 solves for the history graph, getting quicker.
	var now := Time.get_unix_time_from_system()
	var history := []
	var times := [262, 241, 250, 219, 233, 204, 226, 197, 188, 211, 179, 192, 168, 183, 159, 171, 152, 164, 147, 141]
	for i in times.size():
		history.append([now - (times.size() - i) * 86400.0, float(times[i]), [1, 1, 0, 1, 2, 1, 1, 2, 1, 0][i % 10]])
	cfg.set_value("history", "size_8", history)
	cfg.set_value("challenge", "best", 14)
	cfg.set_value("stats", "climb_runs", 23)
	cfg.set_value("stats", "climb_solved", 117)
	cfg.save(SAVE)


## Renders at `size`, scaled from the game's 640 px short side like the
## window's canvas_items stretch.
func _set_size(size: Vector2i) -> void:
	var scale := float(mini(size.x, size.y)) / 640.0
	viewport.size = size
	viewport.size_2d_override = Vector2i(roundi(size.x / scale), roundi(size.y / scale))
	viewport.oversampling_override = scale


## Made-up names and times for the leaderboard screenshot; nothing is sent.
func _fake_scores(main: Control) -> void:
	var names := ["Speedy", "QueenBee", "Marta", "Asc", "puzzler42", "Léa", "Kenji", "Olu", "Sam", "Ines",
			"Tomasz", "Priya", "Noor", "Felix"]
	var raw := []
	for i in names.size():
		raw.append({"pn": names[i], "s": -(51000 + i * 6100 + i * i * 700), "t": 1.0,
				"md": {"id": main._player_id() if names[i] == "Asc" else names[i]}})
	main._silent_wolf.fake_scores["daily-" + main._today()] = raw
	main._progress.set_value("online", "player_name", "Asc")


## Shows the size and difficulty set straight on main in its dropdowns.
func _sync_pickers(main: Control) -> void:
	main._size_picker.select(main._sizes.find(main._size))
	main._difficulty_picker.select(main._difficulty)


func _set_time(main: Control, seconds: float) -> void:
	main._elapsed = seconds
	main._running = false
	main._timer_label.text = main._format_time(seconds)


func _wait_ready(main: Control) -> void:
	await _frames(3)
	while main._generating:
		await _frames(1)
	# Let the tiles finish growing in.
	while main._view._reveal_at >= 0:
		await _frames(1)
	await _frames(3)


## Waits for fades, pops and the win panel to finish before capturing.
func _shot(file: String, settle_ms := 700) -> void:
	var until := Time.get_ticks_msec() + settle_ms
	while Time.get_ticks_msec() < until:
		await process_frame
	var image := viewport.get_texture().get_image()
	image.save_png(out_dir.path_join(file))
	print(file, " ", image.get_size())


func _frames(count: int) -> void:
	for i in count:
		await process_frame
