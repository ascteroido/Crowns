extends SceneTree
## Checks puzzle packs made elsewhere (tools/make_packs.gd) and copies the sound
## part of each into the game's packs:
##   godot --headless --path . --script res://tools/check_packs.gd -- <from_dir>
## A puzzle passes with exactly one solution, matching the one stored, the
## grade of its pack, and no repeat earlier in the pack. Packs only grow at the
## end and their numbers must never change, so only puzzles not yet in the
## game's pack are checked, and a bad one stops its pack there (and is
## reported) rather than being skipped. Prints one line per pack that grew,
## and exits with 1 if any puzzle failed.

const Generator := preload("res://scripts/generator.gd")
const Solver := preload("res://scripts/solver.gd")
const PuzzlePack := preload("res://scripts/puzzle_pack.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var from: String = args[0] if args.size() > 0 else ""
	var failed := false
	var files := DirAccess.get_files_at(from)
	if files.is_empty():
		printerr("No packs in %s" % from)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PuzzlePack.DIR))
	for file in files:
		if not file.ends_with(".pack"):
			continue
		var incoming := FileAccess.get_file_as_bytes(from.path_join(file))
		if incoming.size() < PuzzlePack.HEADER:
			continue
		var size := incoming[5]
		var difficulty := incoming[6]
		var target := ProjectSettings.globalize_path(PuzzlePack.DIR.path_join(file))
		var kept := PuzzlePack.decode_all(FileAccess.get_file_as_bytes(target)) if FileAccess.file_exists(target) else []
		var puzzles := PuzzlePack.decode_all(incoming)
		# A cut-short download only holds the puzzles that arrived whole.
		puzzles.resize(mini(puzzles.size(), (incoming.size() - PuzzlePack.HEADER) / PuzzlePack.entry_size(size)))
		var label := "%d×%d %s" % [size, size, Generator.DIFFICULTY_NAMES[difficulty]]
		if puzzles.size() < kept.size() or puzzles.slice(0, kept.size()) != kept:
			printerr("%s: the source no longer starts with the %d puzzles already kept; left as is" % [label, kept.size()])
			failed = true
			continue
		var seen := {}
		for puzzle: Dictionary in kept:
			seen[puzzle.regions] = true
		var good := kept.size()
		for number in range(kept.size(), puzzles.size()):
			var problem := _problem(size, difficulty, puzzles[number], seen)
			if not problem.is_empty():
				printerr("%s #%d %s; keeping the %d before it" % [label, number + 1, problem, good])
				failed = true
				break
			seen[puzzles[number].regions] = true
			good += 1
		if good > kept.size():
			var bytes := PuzzlePack.encode(size, difficulty, puzzles.slice(0, good))
			# Written whole, then moved into place, so the game never reads half a pack.
			var partial := target + ".partial"
			var out := FileAccess.open(partial, FileAccess.WRITE)
			out.store_buffer(bytes)
			out.close()
			DirAccess.rename_absolute(partial, target)
			print("%s: %d → %d" % [label, kept.size(), good])
	quit(1 if failed else 0)


## Why `puzzle` doesn't belong in its pack, or "" when it does.
func _problem(size: int, difficulty: int, puzzle: Dictionary, seen: Dictionary) -> String:
	if seen.has(puzzle.regions):
		return "repeats an earlier puzzle"
	var found := Solver.find_solutions(size, puzzle.regions, 2)
	if found.size() != 1:
		return "has %d solutions" % found.size() if found.size() < 2 else "has more than one solution"
	if found[0] != puzzle.solution:
		return "stores the wrong solution"
	if not Generator.rates_as(size, puzzle.regions, difficulty):
		return "doesn't grade as %s" % Generator.DIFFICULTY_NAMES[difficulty]
	return ""
