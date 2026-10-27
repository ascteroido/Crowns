extends RefCounted
## Builds Queens puzzles with exactly one solution.
##
## 1. Place `size` non-touching crowns, one per row and column.
## 2. Grow one region from each crown until the grid is filled.
## 3. While the solver finds a second solution, move one of that solution's
##    crown cells into a neighbouring region, which breaks that solution.
## 4. Keep only puzzles the grader rates at the requested difficulty. Hard+ is a
##    Hard puzzle that leans harder on tier 3: two or more of its deductions, or
##    one about three or more groups at once.
##
## search() is faster for big Hard and Hard+ boards, and builds those puzzle
## packs: it keeps nudging one layout towards the difficulty instead of
## throwing layouts away; Easy and Medium layouts are cheap enough to throw
## away. generate() stays as it is, since regular puzzles and their codes
## depend on the boards it makes from each seed.

const Solver := preload("res://scripts/solver.gd")
const Grader := preload("res://scripts/grader.gd")

enum Difficulty { EASY, MEDIUM, HARD, HARD_PLUS }
## Also the save keys' and pack files' names, lower-cased.
const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard", "Hard+"]
## Region growth weights per difficulty as [exponent, lowest base]: uneven
## regions hand out easy deductions, even ones need the deeper rules.
const REGION_WEIGHTS := [[4.0, 0.05], [2.0, 0.15], [1.0, 0.4], [1.0, 0.4]]

const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const REPAIR_STEPS := 80
## Moves search() tries on a layout without getting closer before it starts a
## fresh one; a fresh layout costs about as much as this many grades.
const SEARCH_PATIENCE := 40


## Returns {"regions": PackedInt32Array, "solution": PackedInt32Array} for a
## puzzle that rates as `difficulty`.
static func generate(size: int, difficulty: int, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Array = REGION_WEIGHTS[difficulty]
	while true:
		var puzzle := _generate_unique(size, rng, weights[0], weights[1])
		if rates_as(size, puzzle.regions, difficulty):
			return puzzle
	return {}


## Whether a layout rates as `difficulty`. Hard+ puzzles also count as Hard,
## so the Hard puzzles stay the same as before Hard+ existed.
static func rates_as(size: int, regions: PackedInt32Array, difficulty: int) -> bool:
	if difficulty < Difficulty.HARD_PLUS:
		return Grader.grade(size, regions) == difficulty + 1
	var solve := Grader.solve(size, regions)
	return solve.grade == 3 and (solve.tier3_steps >= 2 or solve.largest_group >= 3)


## Like generate(), but by local search: make a layout, then move single cells
## between regions, keeping each move that leaves the grader no further from
## `difficulty`. Crown cells never move, so `solution` stays a solution, and a
## layout the grader can finish has only that one.
static func search(size: int, difficulty: int, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Array = REGION_WEIGHTS[difficulty]
	while true:
		var start := _generate_unique(size, rng, weights[0], weights[1])
		var solution: PackedInt32Array = start.solution
		var regions: PackedInt32Array = start.regions
		var crowns := {}
		for row in size:
			crowns[row * size + solution[row]] = true
		var graded := Grader.solve(size, regions)
		var distance := _distance(graded, difficulty)
		var since_closer := 0
		while since_closer < SEARCH_PATIENCE:
			if distance == 0:
				return {"regions": regions, "solution": solution}
			# While the grader gets stuck, change the cells it couldn't decide.
			var stuck: PackedInt32Array = graded.stuck_cells
			var cell := stuck[rng.randi_range(0, stuck.size() - 1)] if not stuck.is_empty() and rng.randf() < 0.8 \
					else rng.randi_range(0, size * size - 1)
			since_closer += 1
			if crowns.has(cell):
				continue
			var targets := _neighbour_regions(size, regions, cell)
			if targets.is_empty() or not _stays_connected(size, regions, cell):
				continue
			var old := regions[cell]
			regions[cell] = targets[rng.randi_range(0, targets.size() - 1)]
			var regraded := Grader.solve(size, regions)
			var moved := _distance(regraded, difficulty)
			# Ties are kept too, so the search can drift across flat stretches.
			if moved <= distance:
				if moved < distance:
					since_closer = 0
				distance = moved
				graded = regraded
			else:
				regions[cell] = old
	return {}


## How far a graded layout is from rating as `difficulty`; 0 when it does.
## Layouts the grader can't finish are furthest, by how much they leave open.
static func _distance(solve: Dictionary, difficulty: int) -> int:
	if solve.grade == Grader.STUCK:
		return 1000 + solve.open_left
	match difficulty:
		Difficulty.EASY:
			return solve.tier2_steps + solve.tier3_steps
		Difficulty.MEDIUM:
			return solve.tier3_steps if solve.grade == 3 else (1 if solve.grade == 1 else 0)
		Difficulty.HARD:
			return 0 if solve.grade == 3 else 1
	if solve.grade < 3:
		return 2
	return 0 if solve.tier3_steps >= 2 or solve.largest_group >= 3 else 1


static func _generate_unique(size: int, rng: RandomNumberGenerator, spread: float, low: float) -> Dictionary:
	while true:
		var solution := _random_placement(size, rng)
		var regions := _grow_regions(size, solution, rng, spread, low)
		if _repair(size, regions, solution, rng):
			return {"regions": regions, "solution": solution}
	return {}


static func _random_placement(size: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var cols := PackedInt32Array()
	cols.resize(size)
	while not _place_row(size, 0, 0, cols, rng):
		pass
	return cols


static func _place_row(size: int, row: int, used_cols: int, cols: PackedInt32Array, rng: RandomNumberGenerator) -> bool:
	if row == size:
		return true
	var order := range(size)
	_shuffle(order, rng)
	for col: int in order:
		if used_cols & (1 << col):
			continue
		if row > 0 and absi(col - cols[row - 1]) <= 1:
			continue
		cols[row] = col
		if _place_row(size, row + 1, used_cols | (1 << col), cols, rng):
			return true
	return false


static func _grow_regions(size: int, solution: PackedInt32Array, rng: RandomNumberGenerator, spread: float, low: float) -> PackedInt32Array:
	var regions := PackedInt32Array()
	regions.resize(size * size)
	regions.fill(-1)

	# Shuffle ids so region colours don't follow row order.
	var ids := range(size)
	_shuffle(ids, rng)
	# Uneven growth weights give a mix of small and large regions, as in the original.
	var weights := PackedFloat32Array()
	for row in size:
		regions[row * size + solution[row]] = ids[row]
		weights.append(pow(rng.randf_range(low, 1.0), spread))

	var active: Array = ids.duplicate()
	var unassigned := size * size - size
	while unassigned > 0:
		var region: int = _pick_weighted(active, weights, rng)
		var frontier := _frontier(size, regions, region)
		if frontier.is_empty():
			active.erase(region)
			continue
		regions[frontier[rng.randi_range(0, frontier.size() - 1)]] = region
		unassigned -= 1
	return regions


static func _repair(size: int, regions: PackedInt32Array, solution: PackedInt32Array, rng: RandomNumberGenerator) -> bool:
	for step in REPAIR_STEPS:
		var found := Solver.find_solutions(size, regions, 2)
		if found.size() == 1:
			return true
		var other: PackedInt32Array = found[0] if found[0] != solution else found[1]

		# Try the other solution's off-solution crown cells in random order.
		var rows := range(size)
		_shuffle(rows, rng)
		var moved := false
		for row: int in rows:
			if other[row] == solution[row]:
				continue
			var cell := row * size + other[row]
			var targets := _neighbour_regions(size, regions, cell)
			if targets.is_empty() or not _stays_connected(size, regions, cell):
				continue
			regions[cell] = targets[rng.randi_range(0, targets.size() - 1)]
			moved = true
			break
		if not moved:
			return false
	return false


static func _frontier(size: int, regions: PackedInt32Array, region: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in regions.size():
		if regions[i] != -1:
			continue
		for n in _neighbours(size, i):
			if regions[n] == region:
				result.append(i)
				break
	return result


static func _neighbour_regions(size: int, regions: PackedInt32Array, cell: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for n in _neighbours(size, cell):
		var r := regions[n]
		if r != regions[cell] and not result.has(r):
			result.append(r)
	return result


## True when removing `cell` from its region leaves the rest of it connected.
static func _stays_connected(size: int, regions: PackedInt32Array, cell: int) -> bool:
	var region := regions[cell]
	var members := PackedInt32Array()
	for i in regions.size():
		if i != cell and regions[i] == region:
			members.append(i)
	if members.is_empty():
		return false

	var seen := {members[0]: true}
	var stack := [members[0]]
	while not stack.is_empty():
		var current: int = stack.pop_back()
		for n in _neighbours(size, current):
			if n != cell and regions[n] == region and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == members.size()


static func _neighbours(size: int, cell: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var pos := Vector2i(cell / size, cell % size)
	for d in NEIGHBOURS:
		var p := pos + d
		if p.x >= 0 and p.y >= 0 and p.x < size and p.y < size:
			result.append(p.x * size + p.y)
	return result


static func _pick_weighted(items: Array, weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for item: int in items:
		total += weights[item]
	var roll := rng.randf() * total
	for item: int in items:
		roll -= weights[item]
		if roll <= 0.0:
			return item
	return items[-1]


## Fisher-Yates shuffle driven by `rng`, so puzzles are reproducible from a seed.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
