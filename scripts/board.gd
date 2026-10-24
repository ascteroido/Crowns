extends RefCounted
## Puzzle state: the colour-region layout, its solution and the player's marks.

## AUTO_CROSS is a cross placed because a crown rules the cell out; it goes away with that crown.
enum Mark { EMPTY, CROSS, CROWN, AUTO_CROSS }

var size: int
## Region id per cell, row-major.
var regions: PackedInt32Array
## Solution column per row.
var solution: PackedInt32Array
## Mark per cell, row-major.
var marks: PackedInt32Array


func _init(p_size: int, p_regions: PackedInt32Array, p_solution: PackedInt32Array) -> void:
	size = p_size
	regions = p_regions
	solution = p_solution
	marks = PackedInt32Array()
	marks.resize(size * size)


func index(cell: Vector2i) -> int:
	return cell.x * size + cell.y


func region_at(cell: Vector2i) -> int:
	return regions[index(cell)]


func get_mark(cell: Vector2i) -> int:
	return marks[index(cell)]


func set_mark(cell: Vector2i, mark: int) -> void:
	marks[index(cell)] = mark


func is_cross(cell: Vector2i) -> bool:
	var mark := get_mark(cell)
	return mark == Mark.CROSS or mark == Mark.AUTO_CROSS


## [cell, old, new] changes that bring auto crosses in line with the crowns:
## empty cells a crown rules out get one, auto crosses no crown rules out lose theirs.
func auto_cross_changes() -> Array:
	var ruled_out := PackedByteArray()
	ruled_out.resize(size * size)
	for crown in crowns():
		for row in size:
			for col in size:
				var cell := Vector2i(row, col)
				if row == crown.x or col == crown.y or region_at(cell) == region_at(crown) \
						or (absi(row - crown.x) <= 1 and absi(col - crown.y) <= 1):
					ruled_out[index(cell)] = 1
	var changes := []
	for i in marks.size():
		var cell := Vector2i(i / size, i % size)
		if marks[i] == Mark.EMPTY and ruled_out[i] == 1:
			changes.append([cell, Mark.EMPTY, Mark.AUTO_CROSS])
		elif marks[i] == Mark.AUTO_CROSS and ruled_out[i] == 0:
			changes.append([cell, Mark.AUTO_CROSS, Mark.EMPTY])
	return changes


func clear() -> void:
	marks.fill(Mark.EMPTY)


## Crown positions as Vector2i(row, col).
func crowns() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in marks.size():
		if marks[i] == Mark.CROWN:
			result.append(Vector2i(i / size, i % size))
	return result


## One flag per cell: 1 when the cell lies in a row, column or region holding
## more than one crown, or holds a crown that touches another crown.
func conflicts() -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(size * size)
	var row_count := PackedInt32Array()
	var col_count := PackedInt32Array()
	var region_count := PackedInt32Array()
	row_count.resize(size)
	col_count.resize(size)
	region_count.resize(size)

	var placed := crowns()
	for c in placed:
		row_count[c.x] += 1
		col_count[c.y] += 1
		region_count[region_at(c)] += 1

	for row in size:
		for col in size:
			var cell := Vector2i(row, col)
			if row_count[row] > 1 or col_count[col] > 1 or region_count[region_at(cell)] > 1:
				flags[index(cell)] = 1

	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var a := placed[i]
			var b := placed[j]
			if absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1:
				flags[index(a)] = 1
				flags[index(b)] = 1
	return flags


func is_solved() -> bool:
	# With exactly `size` crowns and no conflicts, every row, column and
	# region holds exactly one crown.
	return crowns().size() == size and not conflicts().has(1)
