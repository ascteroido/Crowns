extends Control
## Draws a board and turns clicks and drags into mark changes.
##
## Left click cycles empty -> cross -> crown -> empty. Dragging from an empty
## cell crosses out every empty cell it passes; dragging from a cross erases
## every cross it passes. Double click (or double tap) places a crown. Right
## click toggles a crown.

const Board := preload("res://scripts/board.gd")

## Emitted once per click or drag with every change it made, as
## [cell: Vector2i, old_mark: int, new_mark: int] entries.
signal edited(changes: Array)

# No reds, so conflict hatching always stands out.
const REGION_COLORS: Array[Color] = [
	Color("bba3e2"), Color("ffc992"), Color("96beff"), Color("b3dfa0"), Color("dfdfdf"),
	Color("e6f388"), Color("dfa0bf"), Color("a3d2d8"), Color("b9b29e"), Color("7fd1ae"),
	Color("f4a99b"), Color("e8c55e"), Color("a9bd72"), Color("a9b0f0"),
]
const REGION_NAMES := ["purple", "orange", "blue", "green", "grey", "yellow", "pink", "teal", "tan", "mint",
		"salmon", "gold", "olive", "periwinkle"]
const LINE_COLOR := Color(0.1, 0.1, 0.1, 0.35)
const HINT_COLOR := Color("2f6fde")
const HINT_DIM := Color(0, 0, 0, 0.3)
const PATTERN_INK := Color(0, 0, 0, 0.2)
const PATTERN_COUNT := 14
const BORDER_COLOR := Color("1e1e1e")
const MARK_COLOR := Color("1e1e1e")
const CONFLICT_COLOR := Color("d6312b")
const DOUBLE_TAP_MS := 400

var board: Board:
	set(value):
		board = value
		mistake = Vector2i(-1, -1)
		hint_focus = PackedInt32Array()
		hint_targets = PackedInt32Array()
		queue_redraw()
## Cell indices a hint is about; every other cell is dimmed while it's set.
var hint_focus := PackedInt32Array():
	set(value):
		hint_focus = value
		queue_redraw()
## Cell indices a hint would change, ringed in blue.
var hint_targets := PackedInt32Array():
	set(value):
		hint_targets = value
		queue_redraw()
## A wrongly placed crown to show in red, or (-1, -1).
var mistake := Vector2i(-1, -1):
	set(value):
		mistake = value
		queue_redraw()
## When false the board ignores input, e.g. after the puzzle is solved.
var interactive := true
## Placing or removing a crown also adds or removes the auto crosses it implies.
var auto_cross := false
## Gives each region its own texture so regions can be told apart without colour.
var patterns := false:
	set(value):
		patterns = value
		queue_redraw()
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
## Cell and time of the last press that stayed on its cell, for spotting double taps.
var _tap_cell := Vector2i(-1, -1)
var _tap_time := -DOUBLE_TAP_MS


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
				var now := Time.get_ticks_msec()
				var double_tap := cell == _tap_cell and now - _tap_time < DOUBLE_TAP_MS
				_tap_cell = Vector2i(-1, -1) if double_tap else cell
				_tap_time = now
				if double_tap:
					_change(cell, Board.Mark.CROWN)
				elif board.is_cross(cell):
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
		if cell != _tap_cell:
			_tap_cell = Vector2i(-1, -1)
		if cell.x >= 0 and board.get_mark(cell) == Board.Mark.EMPTY:
			_change(cell, Board.Mark.CROSS)
		accept_event()
	elif event is InputEventMouseMotion and _erasing:
		var cell := _cell_at((event as InputEventMouseMotion).position)
		if cell.x >= 0 and cell != _press_cell:
			_tap_cell = Vector2i(-1, -1)
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
			if patterns:
				_draw_pattern(rect, board.region_at(cell))
			var conflicted := flags[board.index(cell)] == 1 or cell == mistake
			if conflicted:
				_draw_stripes(rect)
			match board.get_mark(cell):
				Board.Mark.CROSS:
					_draw_cross(rect, MARK_COLOR)
				Board.Mark.AUTO_CROSS:
					_draw_cross(rect, Color(MARK_COLOR, 0.45))
				Board.Mark.CROWN:
					_draw_crown(rect, CONFLICT_COLOR if conflicted else MARK_COLOR)
			var i := board.index(cell)
			if not hint_focus.is_empty() and not hint_focus.has(i):
				draw_rect(rect, HINT_DIM)
			if hint_targets.has(i):
				var inset := cs * 0.1
				draw_rect(rect.grow(-inset), HINT_COLOR, false, maxf(2.0, cs * 0.07))

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


## One of PATTERN_COUNT faint textures, repeating every third or quarter of a
## cell so neighbouring cells of a region join up. None of them look like a
## cross, and the only diagonal lines run the opposite way to conflict hatching.
func _draw_pattern(rect: Rect2, region: int) -> void:
	var s := rect.size.x
	var p := rect.position
	var w := maxf(1.0, s * 0.035)
	var ink := PATTERN_INK
	match region % PATTERN_COUNT:
		0: # dots
			for i in 3:
				for j in 3:
					draw_circle(p + Vector2(i + 0.5, j + 0.5) * s / 3.0, s * 0.045, ink, true, -1.0, true)
		1: # horizontal lines
			for j in 3:
				var y := p.y + (j + 0.5) * s / 3.0
				draw_line(Vector2(p.x, y), Vector2(p.x + s, y), ink, w)
		2: # vertical lines
			for i in 3:
				var x := p.x + (i + 0.5) * s / 3.0
				draw_line(Vector2(x, p.y), Vector2(x, p.y + s), ink, w)
		3: # diagonals running top-left to bottom-right
			for k in range(-3, 4):
				var c := k * s / 3.0
				var a := Vector2(maxf(0.0, c), maxf(0.0, -c))
				var b := Vector2(minf(s, s + c), minf(s, s - c))
				draw_line(p + a, p + b, ink, w)
		4: # grid
			for k in 2:
				var t := (k + 0.5) * s / 2.0
				draw_line(p + Vector2(t, 0), p + Vector2(t, s), ink, w)
				draw_line(p + Vector2(0, t), p + Vector2(s, t), ink, w)
		5: # rings
			for i in 2:
				for j in 2:
					draw_arc(p + Vector2(i + 0.5, j + 0.5) * s / 2.0, s * 0.13, 0, TAU, 20, ink, w, true)
		6: # plus signs
			for i in 2:
				for j in 2:
					var c := p + Vector2(i + 0.5, j + 0.5) * s / 2.0
					var r := s * 0.09
					draw_line(c - Vector2(r, 0), c + Vector2(r, 0), ink, w)
					draw_line(c - Vector2(0, r), c + Vector2(0, r), ink, w)
		7: # small squares
			for i in 2:
				for j in 2:
					var c := p + Vector2(i + 0.5, j + 0.5) * s / 2.0
					draw_rect(Rect2(c - Vector2.ONE * s * 0.09, Vector2.ONE * s * 0.18), ink, false, w)
		8: # diamonds
			for i in 2:
				for j in 2:
					var c := p + Vector2(i + 0.5, j + 0.5) * s / 2.0
					var r := s * 0.12
					draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
							c + Vector2(-r, 0), c + Vector2(0, -r)]), ink, w, true)
		9: # triangles
			for i in 2:
				for j in 2:
					var c := p + Vector2(i + 0.5, j + 0.5) * s / 2.0
					var r := s * 0.1
					draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.8),
							c + Vector2(-r, r * 0.8)]), ink)
		10: # zigzags
			for j in 2:
				var y := p.y + (j + 0.5) * s / 2.0
				var points := PackedVector2Array()
				for k in 7:
					points.append(Vector2(p.x + k * s / 6.0, y + (s * 0.06 if k % 2 else -s * 0.06)))
				draw_polyline(points, ink, w, true)
		11: # checks
			for i in 4:
				for j in 4:
					if (i + j) % 2 == 0:
						draw_rect(Rect2(p + Vector2(i, j) * s / 4.0, Vector2.ONE * s / 4.0), Color(ink, ink.a * 0.6))
		12: # fine dots
			for i in 4:
				for j in 4:
					draw_circle(p + Vector2(i + 0.5, j + 0.5) * s / 4.0, s * 0.025, ink, true, -1.0, true)
		13: # dashes
			for j in 3:
				var y := p.y + (j + 0.5) * s / 3.0
				var shift := 0.0 if j % 2 == 0 else s / 6.0
				for k in 3:
					var x := p.x + shift + k * s / 3.0 - s / 12.0
					draw_line(Vector2(maxf(p.x, x), y), Vector2(minf(p.x + s, x + s / 6.0), y), ink, w)


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
