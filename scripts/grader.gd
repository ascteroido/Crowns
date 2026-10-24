extends RefCounted
## Rates a puzzle by solving it the way a person would, with deduction rules in
## tiers of increasing difficulty. The grade is the hardest tier the solve needed:
##   1. A row, column or region with one open cell takes the crown.
##   2. A region confined to one row or column clears the rest of that line (and
##      the reverse), and a cell whose crown would leave a line or region with
##      no open cells is ruled out.
##   3. k regions confined to k rows or columns clear the rest of those lines
##      (and the reverse).
## A puzzle these rules can't finish grades as STUCK.
##
## The same rules give hints: next_step() explains one deduction from a board.
## Groups are numbered rows 0..n-1, columns n..2n-1, regions 2n..3n-1.

const Board := preload("res://scripts/board.gd")

const STUCK := 4
enum Kind { ROW, COLUMN, REGION }


## Grade 1-3, or STUCK.
static func grade(size: int, regions: PackedInt32Array) -> int:
	return solve(size, regions).grade


## {"grade": int, "solution": column per row, empty when STUCK}.
static func solve(size: int, regions: PackedInt32Array) -> Dictionary:
	var state := _State.new(size, regions)
	var hardest := 1
	while not state.solved():
		var step := _find_step(state)
		if step.is_empty():
			return {"grade": STUCK, "solution": PackedInt32Array()}
		_apply(state, step)
		hardest = maxi(hardest, step.tier)
	return {"grade": hardest, "solution": state.crowns}


## The easiest deduction left on a board whose crowns and crosses are all
## correct, or {} when none applies. Cells a crown already rules out count as
## ruled out even if they aren't crossed. A step is a Dictionary:
##   tier, rule ("single", "confined" or "blocker"),
##   crown: cell index to crown, or -1,
##   cross: cell indices to rule out,
##   from / to: groups the deduction reasons about ("single" and "blocker"
##     put the group in `from`; "confined" fits `from` inside `to`),
##   focus: cells to highlight while explaining.
static func next_step(size: int, regions: PackedInt32Array, marks: PackedInt32Array) -> Dictionary:
	var state := _State.new(size, regions)
	for cell in marks.size():
		if marks[cell] == Board.Mark.CROWN:
			state.place(cell)
	for cell in marks.size():
		if marks[cell] == Board.Mark.CROSS or marks[cell] == Board.Mark.AUTO_CROSS:
			state.open[cell] = 0
	return _find_step(state)


static func group_kind(size: int, group: int) -> Kind:
	return group / size as Kind


static func group_index(size: int, group: int) -> int:
	return group % size


static func _find_step(state: _State) -> Dictionary:
	var step := _single(state)
	if step.is_empty():
		step = _confinement(state, 1)
	if step.is_empty():
		step = _blocker(state)
	for k in range(2, state.size - 1):
		if not step.is_empty():
			break
		step = _confinement(state, k)
	return step


static func _apply(state: _State, step: Dictionary) -> void:
	if step.crown >= 0:
		state.place(step.crown)
	for cell in step.cross:
		state.open[cell] = 0


static func _single(state: _State) -> Dictionary:
	for group in state.groups.size():
		if state.done[group]:
			continue
		var open := state.open_cells(group)
		if open.size() == 1:
			return {"tier": 1, "rule": "single", "crown": open[0], "cross": PackedInt32Array(),
					"from": [group], "to": [], "focus": state.groups[group]}
	return {}


## k groups of one kind whose open cells fit inside k groups of another kind
## leave no room there for anything else.
static func _confinement(state: _State, k: int) -> Dictionary:
	var n := state.size
	# Lines pair with regions both ways.
	for pair in [[Kind.REGION, Kind.ROW], [Kind.REGION, Kind.COLUMN], [Kind.ROW, Kind.REGION], [Kind.COLUMN, Kind.REGION]]:
		var from: int = pair[0]
		var to: int = pair[1]
		var cover := PackedInt32Array()
		var active := 0
		for g in n:
			cover.append(state.cover(from * n + g, to))
			if not state.done[from * n + g]:
				active |= 1 << g
		for mask in range(1, 1 << n):
			if mask & active != mask or _bits(mask) != k:
				continue
			var union := 0
			for g in n:
				if mask & (1 << g):
					union |= cover[g]
			if _bits(union) != k:
				continue
			var cross := PackedInt32Array()
			for g in n:
				if union & (1 << g):
					for cell in state.open_cells(to * n + g):
						if not mask & (1 << state.group_of(cell, from)):
							cross.append(cell)
			if cross.is_empty():
				continue
			var from_groups := []
			var to_groups := []
			var focus := PackedInt32Array()
			for g in n:
				if mask & (1 << g):
					from_groups.append(from * n + g)
					focus.append_array(state.groups[from * n + g])
				if union & (1 << g):
					to_groups.append(to * n + g)
			return {"tier": 2 if k == 1 else 3, "rule": "confined", "crown": -1, "cross": cross,
					"from": from_groups, "to": to_groups, "focus": focus}
	return {}


## Rules out a cell when a crown there would leave some other group with no open cells.
static func _blocker(state: _State) -> Dictionary:
	for cell in state.open.size():
		if not state.open[cell]:
			continue
		var seen := state.seen_by(cell)
		for group in state.groups.size():
			if state.done[group] or state.groups[group].has(cell):
				continue
			var open := state.open_cells(group)
			var blocked := true
			for other in open:
				if not seen[other]:
					blocked = false
					break
			if blocked:
				var focus := open.duplicate()
				focus.append(cell)
				return {"tier": 2, "rule": "blocker", "crown": -1, "cross": PackedInt32Array([cell]),
						"from": [group], "to": [], "focus": focus}
	return {}


static func _bits(value: int) -> int:
	var count := 0
	while value:
		value &= value - 1
		count += 1
	return count


class _State:
	var size: int
	var regions: PackedInt32Array
	## Rows, then columns, then regions; each a list of cell indices.
	var groups: Array[PackedInt32Array] = []
	var done := PackedByteArray()
	var open := PackedByteArray()
	## Crown column per row, -1 until placed.
	var crowns := PackedInt32Array()

	func _init(p_size: int, p_regions: PackedInt32Array) -> void:
		size = p_size
		regions = p_regions
		for g in 3 * size:
			groups.append(PackedInt32Array())
		for cell in size * size:
			for kind in 3:
				groups[kind * size + group_of(cell, kind)].append(cell)
		done.resize(3 * size)
		open.resize(size * size)
		open.fill(1)
		crowns.resize(size)
		crowns.fill(-1)

	func group_of(cell: int, kind: int) -> int:
		match kind:
			Kind.ROW: return cell / size
			Kind.COLUMN: return cell % size
		return regions[cell]

	func open_cells(group: int) -> PackedInt32Array:
		var result := PackedInt32Array()
		for cell in groups[group]:
			if open[cell]:
				result.append(cell)
		return result

	## Bitmask of the groups of `kind` holding this group's open cells.
	func cover(group: int, kind: int) -> int:
		var mask := 0
		for cell in open_cells(group):
			mask |= 1 << group_of(cell, kind)
		return mask

	## Flags for every cell a crown on `cell` would rule out, itself included.
	func seen_by(cell: int) -> PackedByteArray:
		var seen := PackedByteArray()
		seen.resize(size * size)
		var r := cell / size
		var c := cell % size
		for other in size * size:
			var orow := other / size
			var ocol := other % size
			if orow == r or ocol == c or regions[other] == regions[cell] \
					or (absi(orow - r) <= 1 and absi(ocol - c) <= 1):
				seen[other] = 1
		return seen

	func place(cell: int) -> void:
		var seen := seen_by(cell)
		for other in open.size():
			if seen[other]:
				open[other] = 0
		for kind in 3:
			done[kind * size + group_of(cell, kind)] = 1
		crowns[cell / size] = cell % size

	func solved() -> bool:
		return not done.has(0)
