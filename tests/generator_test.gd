extends SceneTree
## Headless check for the generator and board rules:
##   godot --headless --path . --script res://tests/generator_test.gd

const Board := preload("res://scripts/board.gd")
const Generator := preload("res://scripts/generator.gd")
const Solver := preload("res://scripts/solver.gd")
const Grader := preload("res://scripts/grader.gd")
const PuzzlePack := preload("res://scripts/puzzle_pack.gd")

const PUZZLES_PER_SIZE := 10

var failures := 0


func _init() -> void:
	for difficulty in Generator.DIFFICULTY_NAMES.size():
		var name: String = Generator.DIFFICULTY_NAMES[difficulty]
		for size in range(5, 11):
			var started := Time.get_ticks_msec()
			var slowest := 0
			for number in PUZZLES_PER_SIZE:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([size, difficulty, number])
				var t := Time.get_ticks_msec()
				var puzzle := Generator.generate(size, difficulty, rng)
				slowest = maxi(slowest, Time.get_ticks_msec() - t)
				var label := "%s %dx%d #%d" % [name, size, size, number]
				_check_puzzle(size, puzzle, label)
				_expect(Generator.rates_as(size, puzzle.regions, difficulty), label + " grades as " + name)
			print("%s %dx%d: %d puzzles, avg %d ms, slowest %d ms" % [name, size, size, PUZZLES_PER_SIZE,
					(Time.get_ticks_msec() - started) / PUZZLES_PER_SIZE, slowest])

	_check_search()
	_check_rules()
	_check_grader()
	_check_packs()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check_puzzle(size: int, puzzle: Dictionary, label: String) -> void:
	var regions: PackedInt32Array = puzzle.regions
	var solution: PackedInt32Array = puzzle.solution
	var found := Solver.find_solutions(size, regions, 2)
	_expect(found.size() == 1, label + " has exactly one solution")
	_expect(found.size() > 0 and found[0] == solution, label + " solver matches stored solution")

	var board := Board.new(size, regions, solution)
	for row in size:
		board.set_mark(Vector2i(row, solution[row]), Board.Mark.CROWN)
	_expect(board.is_solved(), label + " stored solution satisfies the board rules")

	for region in size:
		_expect(_is_contiguous(size, regions, region), label + " region %d is contiguous" % region)


func _check_search() -> void:
	for difficulty in Generator.DIFFICULTY_NAMES.size():
		var name: String = Generator.DIFFICULTY_NAMES[difficulty]
		for size in [6, 8]:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(["search", size, difficulty])
			for number in 2:
				var puzzle := Generator.search(size, difficulty, rng)
				var label := "searched %s %dx%d #%d" % [name, size, size, number]
				_check_puzzle(size, puzzle, label)
				_expect(Generator.rates_as(size, puzzle.regions, difficulty), label + " grades as " + name)


func _check_packs() -> void:
	# Round trip, including an odd size whose last byte holds a single cell.
	var puzzles := []
	for number in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["pack", number])
		puzzles.append(Generator.generate(7, Generator.Difficulty.MEDIUM, rng))
	var bytes := PuzzlePack.encode(7, Generator.Difficulty.MEDIUM, puzzles)
	_expect(bytes.size() == PuzzlePack.HEADER + 3 * PuzzlePack.entry_size(7), "packs store each puzzle compactly")
	var back := PuzzlePack.decode_all(bytes)
	_expect(back.size() == 3 and back[2].regions == puzzles[2].regions and back[2].solution == puzzles[2].solution,
			"a pack reads back the puzzles written to it")

	# Every shipped pack: a sample from each end must be sound and correctly graded.
	for size in PuzzlePack.sizes():
		for difficulty in Generator.DIFFICULTY_NAMES.size():
			var count := PuzzlePack.count(size, difficulty)
			var seen := {}
			for number in range(1, count + 1):
				var puzzle := PuzzlePack.puzzle(size, difficulty, number)
				_expect(not seen.has(puzzle.regions), "%dx%d %s pack #%d is not a repeat" % [size, size,
						Generator.DIFFICULTY_NAMES[difficulty], number])
				seen[puzzle.regions] = true
				if number <= 20 or number > count - 5:
					var label := "%dx%d %s pack #%d" % [size, size, Generator.DIFFICULTY_NAMES[difficulty], number]
					_check_puzzle(size, puzzle, label)
					_expect(Generator.rates_as(size, puzzle.regions, difficulty), label + " has its difficulty")
			_expect(PuzzlePack.puzzle(size, difficulty, count + 1).regions == PuzzlePack.puzzle(size, difficulty, 1).regions,
					"%dx%d pack numbers wrap around" % [size, size])
			print("%dx%d %s pack: %d puzzles" % [size, size, Generator.DIFFICULTY_NAMES[difficulty], count])


func _check_rules() -> void:
	var regions := PackedInt32Array([0, 0, 1, 1, 0, 2, 2, 1, 3, 2, 2, 1, 3, 3, 3, 3])
	var board := Board.new(4, regions, PackedInt32Array([1, 3, 0, 2]))
	board.set_mark(Vector2i(0, 0), Board.Mark.CROWN)
	board.set_mark(Vector2i(1, 1), Board.Mark.CROWN)
	var flags := board.conflicts()
	_expect(flags[0] == 1 and flags[5] == 1, "touching crowns are flagged")
	_expect(flags[15] == 0, "unrelated cells are not flagged")
	_expect(not board.is_solved(), "conflicting board is not solved")

	board.clear()
	board.set_mark(Vector2i(0, 2), Board.Mark.CROWN)
	board.set_mark(Vector2i(2, 3), Board.Mark.CROWN)
	flags = board.conflicts()
	_expect(flags[3] == 1 and flags[11] == 1, "cells in a region with two crowns are flagged")
	_expect(flags[15] == 0, "cells outside the broken region are not flagged")


func _check_grader() -> void:
	# Regions equal to rows allow many solutions, which logic alone can't pick between.
	var stripes := PackedInt32Array()
	for row in 5:
		for col in 5:
			stripes.append(row)
	_expect(Grader.grade(5, stripes) == Grader.STUCK, "a layout with several solutions is stuck")

	# Whenever the grader finishes, it must have found the one real solution.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var finished := 0
	for i in 150:
		var size := rng.randi_range(5, 9)
		var regions: PackedInt32Array = Generator._generate_unique(size, rng, 1.0, 0.4).regions
		var result := Grader.solve(size, regions)
		if result.grade != Grader.STUCK:
			finished += 1
			_expect(result.solution == Solver.find_solutions(size, regions, 1)[0], "grader solution #%d is the real one" % i)
	_expect(finished > 100, "grader finishes most unique layouts (%d/150)" % finished)

	# search() relies on this: a layout the grader finishes has one solution,
	# even straight after growing, before any repair.
	var grown := 0
	for i in 300:
		var size := rng.randi_range(5, 8)
		var solution := Generator._random_placement(size, rng)
		var regions := Generator._grow_regions(size, solution, rng, 1.0, 0.4)
		if Grader.grade(size, regions) != Grader.STUCK:
			grown += 1
			_expect(Solver.count_solutions(size, regions) == 1, "finished grown layout #%d has one solution" % i)
	_expect(grown > 10, "some grown layouts finish (%d/300)" % grown)


func _is_contiguous(size: int, regions: PackedInt32Array, region: int) -> bool:
	var members := []
	for i in regions.size():
		if regions[i] == region:
			members.append(i)
	if members.is_empty():
		return false
	var seen := {members[0]: true}
	var stack := [members[0]]
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p := Vector2i(cell / size, cell % size) + d
			if p.x < 0 or p.y < 0 or p.x >= size or p.y >= size:
				continue
			var n := p.x * size + p.y
			if regions[n] == region and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == members.size()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
