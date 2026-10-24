extends Control
## Draws a board and turns clicks and drags into mark changes.
##
## Left click cycles empty -> cross -> crown -> empty. Dragging from an empty
## cell crosses out every empty cell it passes; dragging from a cross erases
## every cross it passes. Right click toggles a crown.

const Board := preload("res://scripts/board.gd")

## Emitted once per click or drag with every change it made, as
## [cell: Vector2i, old_mark: int, new_mark: int] entries.
signal edited(changes: Array)

# No reds, so conflict hatching always stands out.
const REGION_COLORS: Array[Color] = [
	Color("bba3e2"), Color("ffc992"), Color("96beff"), Color("b3dfa0"), Color("dfdfdf"),
	Color("e6f388"), Color("dfa0bf"), Color("a3d2d8"), Color("b9b29e"), Color("7fd1ae"),
]
const LINE_COLOR := Color(0.1, 0.1, 0.1, 0.35)
const BORDER_COLOR := Color("1e1e1e")
const MARK_COLOR := Color("1e1e1e")
const CONFLICT_COLOR := Color("d6312b")

var board: Board:
	set(value):
		board = value
		queue_redraw()
## When false the board ignores input, e.g. after the puzzle is solved.
var interactive := true
## Placing or removing a crown also adds or removes the auto crosses it implies.
var auto_cross := false
## Dims the region colours so they don't glare on a dark background.
var dark := false:
	set(value):
		dark = value
		queue_redraw()

var _stroke: Array = []
var _painting := false
var _erasing := false
## Cross pressed to start a possible erase stroke; becomes a crown if the
## press is released without leaving it.
var _press_cell := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if board == null or not interactive:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var cell := _cell_at(button.position)
		if button.pressed and cell.x >= 0:
			if button.button_index == MOUSE_BUTTON_LEFT:
				var old := board.get_mark(cell)
				if board.is_cross(cell):
					_erasing = true
					_press_cell = cell
				else:
					var next := (old + 1) % 3
					_change(cell, next)
					_painting = next == Board.Mark.CROSS
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				var crown := board.get_mark(cell) != Board.Mark.CROWN
				_change(cell, Board.Mark.CROWN if crown else Board.Mark.EMPTY)
			accept_event()
		elif not button.pressed:
			_finish_stroke()
	elif event is InputEventMouseMotion and _painting:
		var cell := _cell_at((event as InputEventMouseMotion).position)
		if cell.x >= 0 and board.get_mark(cell) == Board.Mark.EMPTY:
			_change(cell, Board.Mark.CROSS)
		accept_event()
	elif event is InputEventMouseMotion and _erasing:
		var cell := _cell_at((event as InputEventMouseMotion).position)
		if cell.x >= 0 and cell != _press_cell:
			_change(_press_cell, Board.Mark.EMPTY)
			if board.is_cross(cell):
				_change(cell, Board.Mark.EMPTY)
		accept_event()


func _change(cell: Vector2i, mark: int) -> void:
	var old := board.get_mark(cell)
	if old == mark:
		return
	board.set_mark(cell, mark)
	_stroke.append([cell, old, mark])
	queue_redraw()


func _finish_stroke() -> void:
	if _erasing and _stroke.is_empty():
		_change(_press_cell, Board.Mark.CROWN)
	_painting = false
	_erasing = false
	_press_cell = Vector2i(-1, -1)
	if _stroke.is_empty():
		return
	if auto_cross and _stroke.any(func(c: Array) -> bool: return c[1] == Board.Mark.CROWN or c[2] == Board.Mark.CROWN):
		for change in board.auto_cross_changes():
			_change(change[0], change[2])
	var changes := _stroke
	_stroke = []
	edited.emit(changes)


func _cell_size() -> float:
	return floorf(minf(size.x, size.y) / board.size)


func _origin() -> Vector2:
	var side := _cell_size() * board.size
	return ((size - Vector2(side, side)) / 2.0).floor()


## Vector2i(row, col) under `pos`, or Vector2i(-1, -1) outside the grid.
func _cell_at(pos: Vector2) -> Vector2i:
	var local := (pos - _origin()) / _cell_size()
	var row := floori(local.y)
	var col := floori(local.x)
	if row < 0 or col < 0 or row >= board.size or col >= board.size:
		return Vector2i(-1, -1)
	return Vector2i(row, col)


func _draw() -> void:
	if board == null:
		return
	var n := board.size
	var cs := _cell_size()
	var origin := _origin()
	var flags := board.conflicts()

	for row in n:
		for col in n:
			var cell := Vector2i(row, col)
			var rect := Rect2(origin + Vector2(col, row) * cs, Vector2(cs, cs))
			var fill := REGION_COLORS[board.region_at(cell) % REGION_COLORS.size()]
			draw_rect(rect, fill.darkened(0.18) if dark else fill)
			var conflicted := flags[board.index(cell)] == 1
			if conflicted:
				_draw_stripes(rect)
			match board.get_mark(cell):
				Board.Mark.CROSS:
					_draw_cross(rect, MARK_COLOR)
				Board.Mark.AUTO_CROSS:
					_draw_cross(rect, Color(MARK_COLOR, 0.45))
				Board.Mark.CROWN:
					_draw_crown(rect, CONFLICT_COLOR if conflicted else MARK_COLOR)

	# Thin lines between all cells, thick ones where regions meet.
	var thin := maxf(1.0, cs * 0.02)
	var thick := maxf(2.0, cs * 0.07)
	for row in n:
		for col in n:
			var cell := Vector2i(row, col)
			var top_left := origin + Vector2(col, row) * cs
			if col < n - 1:
				var right_differs := board.region_at(cell) != board.region_at(Vector2i(row, col + 1))
				var x := top_left.x + cs
				draw_line(Vector2(x, top_left.y), Vector2(x, top_left.y + cs),
						BORDER_COLOR if right_differs else LINE_COLOR, thick if right_differs else thin)
			if row < n - 1:
				var below_differs := board.region_at(cell) != board.region_at(Vector2i(row + 1, col))
				var y := top_left.y + cs
				draw_line(Vector2(top_left.x, y), Vector2(top_left.x + cs, y),
						BORDER_COLOR if below_differs else LINE_COLOR, thick if below_differs else thin)
	draw_rect(Rect2(origin, Vector2(cs, cs) * n), BORDER_COLOR, false, thick)


## Red diagonal hatching over a cell that breaks a rule.
func _draw_stripes(rect: Rect2) -> void:
	var s := rect.size.x
	var gap := s / 5.0
	var color := Color(CONFLICT_COLOR, 0.55)
	var c := gap / 2.0
	while c < 2.0 * s:
		# Segment of the line x + y = c inside the square.
		var a := rect.position + Vector2(maxf(0.0, c - s), minf(c, s))
		var b := rect.position + Vector2(minf(c, s), maxf(0.0, c - s))
		draw_line(a, b, color, maxf(1.5, s * 0.05))
		c += gap


func _draw_cross(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var r := rect.size.x * 0.13
	var width := maxf(1.5, rect.size.x * 0.05)
	draw_line(center + Vector2(-r, -r), center + Vector2(r, r), color, width, true)
	draw_line(center + Vector2(-r, r), center + Vector2(r, -r), color, width, true)


func _draw_crown(rect: Rect2, color: Color) -> void:
	var s := rect.size.x
	var p := rect.position
	var outline := PackedVector2Array([
		Vector2(0.22, 0.70), Vector2(0.17, 0.32), Vector2(0.36, 0.50), Vector2(0.50, 0.24),
		Vector2(0.64, 0.50), Vector2(0.83, 0.32), Vector2(0.78, 0.70),
	])
	for i in outline.size():
		outline[i] = p + outline[i] * s
	draw_colored_polygon(outline, color)
	draw_rect(Rect2(p + Vector2(0.22, 0.74) * s, Vector2(0.56, 0.08) * s), color)
	for tip in [Vector2(0.17, 0.30), Vector2(0.50, 0.21), Vector2(0.83, 0.30)]:
		draw_circle(p + tip * s, s * 0.045, color, true, -1.0, true)
