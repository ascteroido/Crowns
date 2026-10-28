extends RefCounted
## Player-made puzzles from the editor: their codes, and whether a layout makes
## a fair puzzle.
##
## A code is the size, "C" and the layout, e.g. "7C-ABEgMQ…": regions numbered
## in order of first appearance, so the same layout always gets the same code,
## packed 3 bits a cell up to 8×8 and 4 bits after, in URL-safe base64.

const Solver := preload("res://scripts/solver.gd")
const Grader := preload("res://scripts/grader.gd")
const Generator := preload("res://scripts/generator.gd")

const MIN_SIZE := 5
const MAX_SIZE := 10
## check()'s verdict on a layout that can't be played yet, or "" when it can.
const UNPAINTED := "unpainted"
const MISSING := "missing"
const SPLIT := "split"
const NO_SOLUTION := "none"
const MANY_SOLUTIONS := "many"
## check()'s difficulty for a fair puzzle the hints can't work through.
const BEYOND_HINTS := -1


static func encode(size: int, regions: PackedInt32Array) -> String:
	var layout := canonical(regions)
	var bits := _bits(size)
	var bytes := PackedByteArray()
	bytes.resize((size * size * bits + 7) / 8)
	for cell in layout.size():
		for bit in bits:
			if layout[cell] & (1 << bit):
				var at := cell * bits + bit
				bytes[at / 8] |= 1 << (at % 8)
	var text := Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
	return "%dC-%s" % [size, text]


## {"size", "regions"} from the first editor code found in `text`, or {} when
## there's none or it can't be a layout. Says nothing of how many solutions it has.
static func decode(text: String) -> Dictionary:
	var regex := RegEx.create_from_string("(\\d{1,2})C-([A-Za-z0-9_-]+)")
	for found in regex.search_all(text):
		var size := found.get_string(1).to_int()
		var payload := found.get_string(2)
		if size < MIN_SIZE or size > MAX_SIZE:
			continue
		var bits := _bits(size)
		var length := (size * size * bits + 7) / 8
		var padded := payload.replace("-", "+").replace("_", "/")
		while padded.length() % 4:
			padded += "="
		var bytes := Marshalls.base64_to_raw(padded)
		if bytes.size() != length:
			continue
		var regions := PackedInt32Array()
		for cell in size * size:
			var region := 0
			for bit in bits:
				var at := cell * bits + bit
				if bytes[at / 8] & (1 << (at % 8)):
					region |= 1 << bit
			regions.append(region)
		if regions == canonical(regions) and Array(regions).max() < size:
			return {"size": size, "regions": regions}
	return {}


## `regions` renumbered in order of first appearance, unpainted cells (-1) kept.
static func canonical(regions: PackedInt32Array) -> PackedInt32Array:
	var ids := {}
	var result := PackedInt32Array()
	for region in regions:
		if region < 0:
			result.append(region)
			continue
		if not ids.has(region):
			ids[region] = ids.size()
		result.append(ids[region])
	return result


## What stands between a layout and a fair puzzle, as {"problem": one of the
## constants above or "" for none, "count": how many cells or colours the
## problem is about, "region": the split region, "solution", "difficulty":
## 0 Easy to 3 Hard+, or BEYOND_HINTS}.
static func check(size: int, regions: PackedInt32Array) -> Dictionary:
	var unpainted := regions.count(-1)
	if unpainted > 0:
		return {"problem": UNPAINTED, "count": unpainted}
	var missing := 0
	for region in size:
		if not regions.has(region):
			missing += 1
	if missing > 0:
		return {"problem": MISSING, "count": missing}
	for region in size:
		if not _connected(size, regions, region):
			return {"problem": SPLIT, "region": region}
	var found := Solver.find_solutions(size, regions, 2)
	if found.is_empty():
		return {"problem": NO_SOLUTION}
	if found.size() > 1:
		return {"problem": MANY_SOLUTIONS}
	var difficulty := BEYOND_HINTS
	var grade := Grader.grade(size, regions)
	if grade != Grader.STUCK:
		difficulty = Generator.Difficulty.HARD_PLUS if Generator.rates_as(size, regions, Generator.Difficulty.HARD_PLUS) \
				else grade - 1
	return {"problem": "", "solution": found[0], "difficulty": difficulty}


static func _bits(size: int) -> int:
	return 3 if size <= 8 else 4


static func _connected(size: int, regions: PackedInt32Array, region: int) -> bool:
	var start := regions.find(region)
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		for next in Generator._neighbours(size, cell):
			if regions[next] == region and not seen.has(next):
				seen[next] = true
				stack.append(next)
	return seen.size() == regions.count(region)
