extends RefCounted
## Backtracking solver for Queens layouts. Free cells are kept as a column
## bitmask per row, and each step fills the region with the fewest free cells.


## Returns up to `limit` solutions, each a column index per row.
static func find_solutions(size: int, regions: PackedInt32Array, limit := 2) -> Array[PackedInt32Array]:
	# region_rows[region * size + row]: columns of that row inside the region.
	var region_rows := PackedInt32Array()
	region_rows.resize(size * size)
	for cell in size * size:
		region_rows[regions[cell] * size + cell / size] |= 1 << (cell % size)
	var free := PackedInt32Array()
	free.resize(size)
	free.fill((1 << size) - 1)
	var cols := PackedInt32Array()
	cols.resize(size)
	var found: Array[PackedInt32Array] = []
	_search(size, region_rows, free, 0, cols, found, limit)
	return found


static func count_solutions(size: int, regions: PackedInt32Array, limit := 2) -> int:
	return find_solutions(size, regions, limit).size()


static func _search(size: int, region_rows: PackedInt32Array, free: PackedInt32Array, used_regions: int,
		cols: PackedInt32Array, found: Array[PackedInt32Array], limit: int) -> void:
	if used_regions == (1 << size) - 1:
		found.append(cols.duplicate())
		return
	var best := -1
	var best_count := 1 << 30
	for region in size:
		if used_regions & (1 << region):
			continue
		var count := 0
		for row in size:
			count += _bits(free[row] & region_rows[region * size + row])
		if count == 0:
			return
		if count < best_count:
			best = region
			best_count = count
	for row in size:
		var options := free[row] & region_rows[best * size + row]
		while options:
			var bit := options & -options
			options &= options - 1
			var col := _bits(bit - 1)
			var next := free.duplicate()
			next[row] = 0
			var around := bit | (bit << 1) | (bit >> 1)
			for r in size:
				next[r] &= ~bit
			if row > 0:
				next[row - 1] &= ~around
			if row < size - 1:
				next[row + 1] &= ~around
			cols[row] = col
			_search(size, region_rows, next, used_regions | (1 << best), cols, found, limit)
			if found.size() >= limit:
				return


static func _bits(value: int) -> int:
	var count := 0
	while value:
		value &= value - 1
		count += 1
	return count
