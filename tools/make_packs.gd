extends SceneTree
## Builds or extends the pre-made puzzle packs in res://puzzles/ (see
## scripts/puzzle_pack.gd), using every CPU core:
##   godot --headless --path . --script res://tools/make_packs.gd -- <count> [sizes] [minutes] [threads]
## e.g. "-- 500 11,12,13,14 120 20" fills each pack up to 500 puzzles, for at most
## two hours, on 20 threads (default: every core; minutes 0 means no limit). Packs are saved every few seconds, so stopping early loses little
## and running again carries on. Existing puzzles are never changed or reordered.

const Generator := preload("res://scripts/generator.gd")
const PuzzlePack := preload("res://scripts/puzzle_pack.gd")
const SAVE_EVERY_MS := 10000

var _target := 0
var _combos := []
## [size, difficulty] -> puzzles in the pack, old then new.
var _packs := {}
## [size, difficulty] -> region layouts already in the pack, to skip repeats.
var _seen := {}
var _dirty := {}
var _stop := false
var _mutex := Mutex.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_target = args[0].to_int() if args.size() > 0 else 100
	var sizes := Array(args[1].split(",")).map(func(s: String) -> int: return s.to_int()) \
			if args.size() > 1 else [11, 12, 13, 14]
	var minutes := args[2].to_float() if args.size() > 2 else 0.0
	var workers := args[3].to_int() if args.size() > 3 else OS.get_processor_count()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PuzzlePack.DIR))
	for size: int in sizes:
		for difficulty in Generator.DIFFICULTY_NAMES.size():
			var combo := [size, difficulty]
			var file := ProjectSettings.globalize_path(PuzzlePack.path(size, difficulty))
			var puzzles := PuzzlePack.decode_all(FileAccess.get_file_as_bytes(file)) if FileAccess.file_exists(file) else []
			_combos.append(combo)
			_packs[combo] = puzzles
			_seen[combo] = {}
			for puzzle: Dictionary in puzzles:
				_seen[combo][puzzle.regions] = true
	_report()

	var start := Time.get_ticks_msec()
	# High priority, or Godot runs it on only a share of the cores.
	var group := WorkerThreadPool.add_group_task(_work, workers, workers, true)
	var last_save := start
	while not WorkerThreadPool.is_group_task_completed(group):
		await process_frame
		var now := Time.get_ticks_msec()
		if minutes > 0.0 and now - start > minutes * 60000.0 and not _stop:
			print("Time's up; finishing the puzzles in progress.")
			_stop = true
		if now - last_save > SAVE_EVERY_MS:
			last_save = now
			_save()
			_progress(now - start)
	WorkerThreadPool.wait_for_group_task_completion(group)
	_save()
	_report()
	quit()


## One worker: keeps making puzzles for whichever pack is furthest from its target.
func _work(worker: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rng.seed += worker
	while not _stop:
		var combo := _next_combo()
		if combo.is_empty():
			return
		var puzzle := Generator.generate(combo[0], combo[1], rng)
		_mutex.lock()
		if not _seen[combo].has(puzzle.regions) and _packs[combo].size() < _target:
			_seen[combo][puzzle.regions] = true
			_packs[combo].append(puzzle)
			_dirty[combo] = true
		_mutex.unlock()


## The unfinished pack with the fewest puzzles, or [] when all are full.
func _next_combo() -> Array:
	_mutex.lock()
	var best := []
	for combo: Array in _combos:
		var have: int = _packs[combo].size()
		if have < _target and (best.is_empty() or have < _packs[best].size()):
			best = combo
	_mutex.unlock()
	return best


func _save() -> void:
	_mutex.lock()
	for combo: Array in _dirty.keys():
		var bytes := PuzzlePack.encode(combo[0], combo[1], _packs[combo])
		var file := FileAccess.open(ProjectSettings.globalize_path(PuzzlePack.path(combo[0], combo[1])), FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
	_dirty.clear()
	_mutex.unlock()


## One line of counts per save, to follow a long run from its log.
func _progress(elapsed_ms: int) -> void:
	_mutex.lock()
	var counts := _combos.map(func(combo: Array) -> String:
		return "%d%s:%d" % [combo[0], "EMHX"[combo[1]], _packs[combo].size()])
	_mutex.unlock()
	print("%dm%02ds  %s" % [elapsed_ms / 60000, elapsed_ms / 1000 % 60, " ".join(counts)])


func _report() -> void:
	for combo: Array in _combos:
		print("%d×%d %s: %d" % [combo[0], combo[0], Generator.DIFFICULTY_NAMES[combo[1]], _packs[combo].size()])
