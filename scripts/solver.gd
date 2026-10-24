extends RefCounted
## Backtracking solver for Queens layouts. Places one crown per row, tracking
## used columns and regions as bitmasks.


## Returns up to `limit` solutions, each a column index per row.
static func find_solutions(size: int, regions: PackedInt32Array, limit := 2) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	var cols := PackedInt32Array()
	cols.resize(size)
	_search(size, regions, 0, 0, 0, cols, found, limit)
	return found


static func count_solutions(size: int, regions: PackedInt32Array, limit := 2) -> int:
	return find_solutions(size, regions, limit).size()


static func _search(size: int, regions: PackedInt32Array, row: int, used_cols: int,
		used_regions: int, cols: PackedInt32Array, found: Array[PackedInt32Array], limit: int) -> void:
	if row == size:
		found.append(cols.duplicate())
		return
	for col in size:
		if used_cols & (1 << col):
			continue
		# Crowns in neighbouring rows may not touch diagonally.
		if row > 0 and absi(col - cols[row - 1]) <= 1:
			continue
		var region := regions[row * size + col]
		if used_regions & (1 << region):
			continue
		cols[row] = col
		_search(size, regions, row + 1, used_cols | (1 << col), used_regions | (1 << region), cols, found, limit)
		if found.size() >= limit:
			return
