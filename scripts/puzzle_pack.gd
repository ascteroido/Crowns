extends RefCounted
## Pre-made puzzles for the board sizes too slow to generate on the spot (11×11
## and up). tools/make_packs.gd builds them offline; the game reads them here.
##
## One file per size and difficulty, e.g. res://puzzles/12_hard.pack (Hard+ is
## "hardplus"):
##   "CRPK", version, size, difficulty, 0, then the puzzle count (u32), then per
##   puzzle the solution (one byte per row: its crown's column) and the regions,
##   two cells to a byte, low nibble first.
## Puzzles are only ever added to the end, so "12×12 Hard #57" and its code
## always mean the same board.

const Generator := preload("res://scripts/generator.gd")

const DIR := "res://puzzles/"
const MAGIC := "CRPK"
const VERSION := 1
const HEADER := 12
## The largest board whose region ids fit a nibble.
const MAX_SIZE := 16

## Path -> the file's bytes, read once.
static var _files := {}


static func path(size: int, difficulty: int) -> String:
	return DIR + "%d_%s.pack" % [size, Generator.DIFFICULTY_NAMES[difficulty].to_lower().replace("+", "plus")]


## Sizes with a pack for every difficulty, smallest first.
static func sizes() -> Array[int]:
	var found: Array[int] = []
	for size in range(5, MAX_SIZE + 1):
		var complete := true
		for difficulty in Generator.DIFFICULTY_NAMES.size():
			complete = complete and count(size, difficulty) > 0
		if complete:
			found.append(size)
	return found


static func count(size: int, difficulty: int) -> int:
	var bytes := _bytes(size, difficulty)
	if bytes.size() < HEADER:
		return 0
	# A cut-short file only offers the puzzles it holds in full.
	return mini(bytes.decode_u32(8), (bytes.size() - HEADER) / entry_size(size))


## The puzzle numbered `number` (from 1); numbers past the end wrap around.
static func puzzle(size: int, difficulty: int, number: int) -> Dictionary:
	var total := count(size, difficulty)
	if total == 0:
		return {}
	var index := posmod(number - 1, total)
	return decode_entry(_bytes(size, difficulty), size, index)


static func entry_size(size: int) -> int:
	return size + (size * size + 1) / 2


static func decode_entry(bytes: PackedByteArray, size: int, index: int) -> Dictionary:
	var at := HEADER + index * entry_size(size)
	var solution := PackedInt32Array()
	for row in size:
		solution.append(bytes[at + row])
	at += size
	var regions := PackedInt32Array()
	regions.resize(size * size)
	for cell in size * size:
		var byte := bytes[at + cell / 2]
		regions[cell] = (byte >> 4) if cell % 2 else (byte & 0xf)
	return {"regions": regions, "solution": solution}


## A whole pack file for `puzzles` ({"regions", "solution"} each).
static func encode(size: int, difficulty: int, puzzles: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(MAGIC.to_ascii_buffer())
	bytes.append_array(PackedByteArray([VERSION, size, difficulty, 0]))
	bytes.resize(HEADER)
	bytes.encode_u32(8, puzzles.size())
	for puzzle: Dictionary in puzzles:
		for column: int in puzzle.solution:
			bytes.append(column)
		var regions: PackedInt32Array = puzzle.regions
		for cell in range(0, size * size, 2):
			var high: int = regions[cell + 1] if cell + 1 < size * size else 0
			bytes.append(regions[cell] | (high << 4))
	return bytes


## Every puzzle in a pack file's bytes, for the tool that extends it.
static func decode_all(bytes: PackedByteArray) -> Array:
	var puzzles := []
	if bytes.size() < HEADER or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return puzzles
	var size := bytes[5]
	for index in bytes.decode_u32(8):
		puzzles.append(decode_entry(bytes, size, index))
	return puzzles


static func _bytes(size: int, difficulty: int) -> PackedByteArray:
	var file := path(size, difficulty)
	if not _files.has(file):
		var bytes := FileAccess.get_file_as_bytes(file) if FileAccess.file_exists(file) else PackedByteArray()
		var valid := bytes.size() >= HEADER and bytes.slice(0, 4).get_string_from_ascii() == MAGIC \
				and bytes[4] == VERSION and bytes[5] == size
		_files[file] = bytes if valid else PackedByteArray()
	return _files[file]
