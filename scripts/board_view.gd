extends Control
## Draws a board and turns clicks and drags into mark changes.
##
## Left click crosses out an empty cell and clears a cross or crown. Double click
## (or double tap) places a crown. Dragging from an empty cell crosses out every
## empty cell it passes; dragging from a cross erases every cross it passes.
## Right click toggles a crown.
##
## With keyboard focus, the arrow keys move a cursor (Shift crosses out the empty
## cells it moves onto), Space or X crosses out or clears the cell, Enter or C
## toggles a crown, and Backspace or Delete empties it. A gamepad (see
## gamepad.gd) moves the cursor with the D-pad or left stick, which repeat when
## held; A crosses out or clears, and held while moving keeps doing so, like a
## drag; Y toggles a crown and X empties the cell.

const Board := preload("res://scripts/board.gd")
const Gamepad := preload("res://scripts/gamepad.gd")
## A held direction waits this long, then repeats this often, in milliseconds.
const REPEAT_DELAY_MS := 350
const REPEAT_EVERY_MS := 90
## How far the stick must lean to count as a direction.
const STICK_DEADZONE := 0.5
const CrownArt := preload("res://scripts/crown_art.gd")

## Emitted once per click or drag with every change it made, as
## [cell: Vector2i, old_mark: int, new_mark: int] entries.
signal edited(changes: Array)
## Emitted for each cell the player changes, as it happens, including auto crosses.
signal marked(cell: Vector2i, old_mark: int, new_mark: int)
## Paint mode: emitted once a press or drag has painted cells.
signal painted

# No reds, so conflict hatching always stands out.
const REGION_COLORS: Array[Color] = [
	Color("bba3e2"), Color("ffc992"), Color("96beff"), Color("b3dfa0"), Color("dfdfdf"),
	Color("e6f388"), Color("dfa0bf"), Color("a3d2d8"), Color("b9b29e"), Color("7fd1ae"),
	Color("f4a99b"), Color("e8c55e"), Color("a9bd72"), Color("a9b0f0"),
]
## The tray the tiles sit on, showing through the gaps between them.
const TRAY_LIGHT := Color("d9d2c3")
const TRAY_DARK := Color("121214")
## Gap between tiles and tile corner radius, as fractions of a cell.
const GAP := 0.07
const RADIUS := 0.16
const HINT_COLOR := Color("2f6fde")
const CURSOR_LIGHT := Color("2a2340")
const CURSOR_DARK := Color("f4f1ea")
const HINT_DIM := Color(0, 0, 0, 0.3)
const PATTERN_INK := Color(0, 0, 0, 0.2)
## Outline of a cell with no region yet, in the editor: an empty slot in the
## tray, so it can't be mistaken for the grey region.
const UNPAINTED_LIGHT := Color(1, 1, 1, 0.7)
const UNPAINTED_DARK := Color(1, 1, 1, 0.18)
const PATTERN_COUNT := 14
const MARK_COLOR := Color("1e1e1e")
const CONFLICT_COLOR := Color("d6312b")
const CONFLICT_BAND := Color("a8221d")
const DOUBLE_TAP_MS := 400
## How long a new crown or cross takes to pop in.
const POP_MS := {Board.Mark.CROWN: 220.0, Board.Mark.CROSS: 130.0, Board.Mark.AUTO_CROSS: 160.0}
## The win wave: each row's crowns hop this long after the row above.
const WAVE_STEP_MS := 70.0
const HOP_MS := 420.0
## The opening reveal: tiles grow in along diagonals from the bottom-left corner
## (bottom-right in right-to-left languages), each diagonal this long after the
## one before, each tile taking REVEAL_MS.
const REVEAL_STEP_MS := 36.0
const REVEAL_MS := 380.0

var board: Board:
	set(value):
		board = value
		# Marks already on a newly shown board appear without popping in.
		_shown_marks = board.marks.duplicate() if board else PackedInt32Array()
		_pops.clear()
		_celebrate_at = -1
		_reveal_at = -1
		mistake = Vector2i(-1, -1)
		hint_focus = PackedInt32Array()
		hint_targets = PackedInt32Array()
		if board and (cursor.x >= board.size or cursor.y >= board.size):
			cursor = Vector2i(board.size / 2, board.size / 2)
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
## Paint mode, for the editor: presses, drags and the keyboard's mark keys give
## cells this region instead of marks. -1 for normal play.
var paint := -1
## When false the board ignores input, e.g. after the puzzle is solved, and
## can't take the keyboard (stray clicks on it would leave the win panel without it).
var interactive := true:
	set(value):
		interactive = value
		focus_mode = FOCUS_ALL if value else FOCUS_NONE
## Placing or removing a crown also adds or removes the auto crosses it implies.
var auto_cross := false
## Gives each region its own texture so regions can be told apart without colour.
var patterns := false:
	set(value):
		patterns = value
		queue_redraw()
## A dark tray and a light cursor, to sit on a dark page.
var dark := false:
	set(value):
		dark = value
		queue_redraw()
## Dims the region colours so they don't glare on a dark page; high contrast keeps them bright.
var dim := false:
	set(value):
		dim = value
		queue_redraw()

## The keyboard's cell; it shows once a key is used and hides on a click.
var cursor := Vector2i.ZERO
## The direction the gamepad holds, and when it next repeats.
var _held := Vector2i.ZERO
var _repeat_at := 0
## Where the left stick leans, a cell's step on each axis.
var _stick := Vector2i.ZERO
## While A is held: the mark it set, which the cursor spreads as it moves.
var _pad_stroke := -1
var _cursor_shown := false
var _stroke: Array = []
var _painting := false
var _erasing := false
## Where the drag was at its last event, so a fast swipe marks every cell between.
var _drag_from := Vector2.ZERO
## Cross pressed to start a possible erase stroke; becomes a crown if the
## press is released without leaving it.
var _press_cell := Vector2i(-1, -1)
## Cell and time of the last press that stayed on its cell, for spotting double taps.
var _tap_cell := Vector2i(-1, -1)
var _tap_time := -DOUBLE_TAP_MS
## Marks as last drawn, to spot cells that changed and pop them in.
var _shown_marks := PackedInt32Array()
## Cell index -> time its mark started popping in.
var _pops := {}
## Time the win wave started, or -1.
var _celebrate_at := -1
## Time the opening reveal started, or -1.
var _reveal_at := -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_ALL if interactive else FOCUS_NONE
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	focus_exited.connect(_release_pad)
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if _held != Vector2i.ZERO and Time.get_ticks_msec() >= _repeat_at:
		_repeat_at += REPEAT_EVERY_MS
		_pad_move(_held, false)
	if not _pops.is_empty() or _celebrate_at >= 0 or _reveal_at >= 0 or not hint_targets.is_empty():
		queue_redraw()


## Sends a wave of hopping crowns down the board.
func celebrate() -> void:
	_celebrate_at = Time.get_ticks_msec()
	queue_redraw()


## Grows the tiles into place from the bottom-left corner to the top-right, or
## mirrored for right-to-left languages.
func reveal() -> void:
	_reveal_at = Time.get_ticks_msec()
	queue_redraw()


## How long reveal() runs on the current board.
func reveal_ms() -> float:
	return 2 * (board.size - 1) * REVEAL_STEP_MS + REVEAL_MS if board else 0.0


## How long celebrate() runs on the current board.
func celebration_ms() -> float:
	return (board.size - 1) * WAVE_STEP_MS + HOP_MS if board else 0.0


## The name hints use for a region's colour, matching REGION_COLORS.
func region_name(region: int) -> String:
	# TRANSLATORS: Region colours, used in hints like "the purple region".
	var names: Array[String] = [tr("purple"), tr("orange"), tr("blue"), tr("green"), tr("grey"), tr("yellow"),
			tr("pink"), tr("teal"), tr("tan"), tr("mint"), tr("salmon"), tr("gold"), tr("olive"), tr("periwinkle")]
	return names[region % names.size()]


func _gui_input(event: InputEvent) -> void:
	if board == null or not interactive:
		return
	if event is InputEventKey:
		_key_input(event)
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_input(event)
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var cell := _cell_at(button.position)
		if button.pressed:
			grab_focus()
			if _cursor_shown:
				_cursor_shown = false
				queue_redraw()
		if paint >= 0:
			_paint_input(button.pressed, cell, button.position)
		elif button.pressed and cell.x >= 0:
			_drag_from = button.position
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
					var next := Board.Mark.CROSS if old == Board.Mark.EMPTY else Board.Mark.EMPTY
					_change(cell, next)
					_painting = next == Board.Mark.CROSS
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				var crown := board.get_mark(cell) != Board.Mark.CROWN
				_change(cell, Board.Mark.CROWN if crown else Board.Mark.EMPTY)
			accept_event()
		elif not button.pressed:
			_finish_stroke()
	elif event is InputEventMouseMotion and paint >= 0 and _painting:
		var to := (event as InputEventMouseMotion).position
		for cell in _cells_along(_drag_from, to):
			_paint_cell(cell)
		_drag_from = to
		accept_event()
	elif event is InputEventMouseMotion and (_painting or _erasing):
		var to := (event as InputEventMouseMotion).position
		for cell in _cells_along(_drag_from, to):
			if _painting:
				if cell != _tap_cell:
					_tap_cell = Vector2i(-1, -1)
				if cell.x >= 0 and board.get_mark(cell) == Board.Mark.EMPTY:
					_change(cell, Board.Mark.CROSS)
			elif cell.x >= 0 and cell != _press_cell:
				_tap_cell = Vector2i(-1, -1)
				_change(_press_cell, Board.Mark.EMPTY)
				if board.is_cross(cell):
					_change(cell, Board.Mark.EMPTY)
		_drag_from = to
		accept_event()


func _paint_input(pressed: bool, cell: Vector2i, pos: Vector2) -> void:
	if pressed and cell.x >= 0:
		_painting = true
		_drag_from = pos
		_paint_cell(cell)
		accept_event()
	elif not pressed and _painting:
		_painting = false
		painted.emit()


func _paint_cell(cell: Vector2i) -> void:
	if cell.x >= 0 and board.region_at(cell) != paint:
		board.regions[board.index(cell)] = paint
		queue_redraw()


## The cells a drag from `from` to `to` passes through, in order, as
## _cell_at() gives them. Motion events can be far apart on a fast swipe, so
## the path between is checked every third of a cell.
func _cells_along(from: Vector2, to: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var steps := maxi(1, ceili(from.distance_to(to) / (_cell_size() / 3.0)))
	for step in range(1, steps + 1):
		var cell := _cell_at(from.lerp(to, float(step) / steps))
		if cells.is_empty() or cells[-1] != cell:
			cells.append(cell)
	return cells


func _key_input(key: InputEventKey) -> void:
	if not key.pressed or _painting or _erasing:
		return
	var keycode := key.keycode
	var move := Vector2i.ZERO
	if key.is_action_pressed("ui_left", true):
		move = Vector2i(0, -1)
	elif key.is_action_pressed("ui_right", true):
		move = Vector2i(0, 1)
	elif key.is_action_pressed("ui_up", true):
		move = Vector2i(-1, 0)
	elif key.is_action_pressed("ui_down", true):
		move = Vector2i(1, 0)
	var mark := -1
	# Leaves Ctrl+C, Ctrl+X and the like to the rest of the game.
	var mark_keys := not (key.ctrl_pressed or key.meta_pressed or key.alt_pressed)
	if mark_keys and keycode in [KEY_SPACE, KEY_X]:
		mark = Board.Mark.CROSS if board.get_mark(cursor) == Board.Mark.EMPTY else Board.Mark.EMPTY
	elif mark_keys and keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_C]:
		mark = Board.Mark.EMPTY if board.get_mark(cursor) == Board.Mark.CROWN else Board.Mark.CROWN
	elif mark_keys and keycode in [KEY_BACKSPACE, KEY_DELETE]:
		mark = Board.Mark.EMPTY
	if move == Vector2i.ZERO and mark < 0:
		return
	accept_event()
	# The first key shows the cursor where it is, without acting yet.
	if not _cursor_shown:
		_cursor_shown = true
		queue_redraw()
		return
	if move != Vector2i.ZERO:
		cursor = _step(cursor, move, not key.is_echo())
		queue_redraw()
		if key.shift_pressed and board.get_mark(cursor) == Board.Mark.EMPTY:
			mark = Board.Mark.CROSS
	if mark >= 0 and paint >= 0:
		_paint_cell(cursor)
		painted.emit()
	elif mark >= 0:
		_change(cursor, mark)
		_finish_stroke()


func _pad_input(event: InputEvent) -> void:
	if _painting or _erasing:
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			return
		var lean := 0
		if absf(motion.axis_value) >= STICK_DEADZONE:
			lean = int(signf(motion.axis_value))
		var stick := _stick
		if motion.axis == JOY_AXIS_LEFT_X:
			stick.y = lean
		else:
			stick.x = lean
		if stick == _stick:
			return
		_stick = stick
		accept_event()
		# The axis that just leaned moves the cursor; letting go stops the repeat.
		var step := Vector2i(0, lean) if motion.axis == JOY_AXIS_LEFT_X else Vector2i(lean, 0)
		_hold(step if lean != 0 else Vector2i.ZERO)
		return
	var button := event as InputEventJoypadButton
	var directions := {"ui_up": Vector2i(-1, 0), "ui_down": Vector2i(1, 0), "ui_left": Vector2i(0, -1), "ui_right": Vector2i(0, 1)}
	for action: String in directions:
		if button.is_action(action):
			accept_event()
			if button.pressed:
				_hold(directions[action])
			elif _held == directions[action]:
				_held = Vector2i.ZERO
			return
	if button.is_action(Gamepad.CROSS) and not button.pressed:
		if _pad_stroke >= 0:
			_pad_stroke = -1
			accept_event()
			if paint >= 0:
				painted.emit()
			else:
				_finish_stroke()
		return
	if not button.pressed:
		return
	var mark := -1
	if button.is_action(Gamepad.CROSS):
		mark = Board.Mark.CROSS if board.get_mark(cursor) == Board.Mark.EMPTY else Board.Mark.EMPTY
	elif button.is_action(Gamepad.CROWN):
		mark = Board.Mark.EMPTY if board.get_mark(cursor) == Board.Mark.CROWN else Board.Mark.CROWN
	elif button.is_action(Gamepad.CLEAR):
		mark = Board.Mark.EMPTY
	if mark < 0:
		return
	accept_event()
	if not _show_cursor():
		return
	if paint >= 0:
		# In the editor, A paints, and keeps painting while held.
		if button.is_action(Gamepad.CROSS):
			_pad_stroke = paint
			_paint_cell(cursor)
		return
	_change(cursor, mark)
	if button.is_action(Gamepad.CROSS):
		_pad_stroke = mark
	else:
		_finish_stroke()


## Lets go of whatever the gamepad held, as when the board loses focus mid-press.
func _release_pad() -> void:
	_held = Vector2i.ZERO
	_stick = Vector2i.ZERO
	if _pad_stroke >= 0:
		_pad_stroke = -1
		if paint >= 0:
			painted.emit()
		else:
			_finish_stroke()


## Starts moving the cursor in `direction`, repeating while it's held.
func _hold(direction: Vector2i) -> void:
	_held = direction
	if direction == Vector2i.ZERO:
		return
	_repeat_at = Time.get_ticks_msec() + REPEAT_DELAY_MS
	if _show_cursor():
		_pad_move(direction)


## Moves the cursor, spreading the held A button's mark onto the cell it reaches.
## Only a fresh press, not a held one repeating, wraps around the sides.
func _pad_move(direction: Vector2i, wrap := true) -> void:
	cursor = _step(cursor, direction, wrap)
	queue_redraw()
	if _pad_stroke < 0:
		return
	if paint >= 0:
		_paint_cell(cursor)
	elif _pad_stroke == Board.Mark.CROSS and board.get_mark(cursor) == Board.Mark.EMPTY:
		_change(cursor, Board.Mark.CROSS)
	elif _pad_stroke == Board.Mark.EMPTY and board.is_cross(cursor):
		_change(cursor, Board.Mark.EMPTY)


## The cell one step from `from`. Stepping off an edge comes back in on the
## opposite side when `wrap`; otherwise it stays put.
func _step(from: Vector2i, direction: Vector2i, wrap: bool) -> Vector2i:
	var to := from + direction
	if wrap:
		return Vector2i(posmod(to.x, board.size), posmod(to.y, board.size))
	return to.clamp(Vector2i.ZERO, Vector2i(board.size - 1, board.size - 1))


## Shows the cursor if it's hidden. Returns whether it was already showing, as
## the first press only brings it up, without acting.
func _show_cursor() -> bool:
	if _cursor_shown:
		return true
	_cursor_shown = true
	queue_redraw()
	return false


## Whether the keyboard cursor is showing.
func cursor_shown() -> bool:
	return _cursor_shown


func _change(cell: Vector2i, mark: int) -> void:
	var old := board.get_mark(cell)
	if old == mark:
		return
	board.set_mark(cell, mark)
	_stroke.append([cell, old, mark])
	marked.emit(cell, old, mark)
	queue_redraw()


func _finish_stroke() -> void:
	# A cross tapped without dragging is cleared; a quick second tap then crowns it.
	if _erasing and _stroke.is_empty():
		_change(_press_cell, Board.Mark.EMPTY)
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
	# Not laid out yet: nothing to draw, and shapes this small can't be drawn.
	if cs < 1.0:
		return
	var origin := _origin()
	var flags := board.conflicts()
	var now := Time.get_ticks_msec()
	_update_pops(now)
	var wave := float(now - _celebrate_at) if _celebrate_at >= 0 else -1.0
	if wave > celebration_ms():
		_celebrate_at = -1
		wave = -1.0
	var reveal := float(now - _reveal_at) if _reveal_at >= 0 else -1.0
	if reveal > reveal_ms():
		_reveal_at = -1
		reveal = -1.0
	var pulse := 0.65 + 0.35 * sin(now / 1000.0 * TAU * 1.2)

	# The tray behind the tiles, its edge as wide as the gaps between them.
	draw_style_box(_rounded(TRAY_DARK if dark else TRAY_LIGHT, cs * RADIUS * 1.3),
			Rect2(origin, Vector2(cs, cs) * n).grow(cs * GAP / 2.0))
	for row in n:
		for col in n:
			var cell := Vector2i(row, col)
			# The cell's square on the board; marks are sized to it, the tile sits inside it.
			var rect := Rect2(origin + Vector2(col, row) * cs, Vector2(cs, cs))
			var grow := 1.0
			if reveal >= 0.0:
				var diagonal := (n - 1 - row) + (n - 1 - col if is_layout_rtl() else col)
				grow = _ease_out_back((reveal - diagonal * REVEAL_STEP_MS) / REVEAL_MS)
				# Under a few pixels, a rounded tile can't be drawn yet.
				if grow * cs < 3.0:
					continue
				rect = _scaled(rect, grow)
			var tile := rect.grow(-cs * grow * GAP / 2.0)
			var radius := cs * grow * RADIUS
			var outline := _tile_outline(tile, radius)
			var region := board.region_at(cell)
			if region < 0:
				var slot := _rounded(Color.TRANSPARENT, radius)
				slot.draw_center = false
				slot.border_color = UNPAINTED_DARK if dark else UNPAINTED_LIGHT
				slot.set_border_width_all(roundi(maxf(1.5, cs * 0.04)))
				draw_style_box(slot, tile)
				continue
			var fill := REGION_COLORS[region % REGION_COLORS.size()]
			draw_style_box(_rounded(fill.darkened(0.18) if dim else fill, radius), tile)
			if patterns:
				_draw_pattern(tile, board.region_at(cell), outline)
			var conflicted := flags[board.index(cell)] == 1 or cell == mistake
			if conflicted:
				_draw_stripes(tile, outline)
			var i := board.index(cell)
			var mark := board.get_mark(cell)
			var mark_rect := rect
			if _pops.has(i):
				var t: float = (now - _pops[i]) / POP_MS.get(mark, 150.0)
				mark_rect = _scaled(rect, _ease_out_back(t))
			match mark:
				Board.Mark.CROSS:
					_draw_cross(mark_rect, MARK_COLOR)
				Board.Mark.AUTO_CROSS:
					_draw_cross(mark_rect, Color(MARK_COLOR, 0.7))
				Board.Mark.CROWN:
					if wave >= 0.0:
						var t := clampf((wave - row * WAVE_STEP_MS) / HOP_MS, 0.0, 1.0)
						var lift := sin(PI * t)
						draw_circle(rect.get_center(), cs * 0.45, Color(1, 1, 1, 0.45 * lift), true, -1.0, true)
						mark_rect = _scaled(rect, 1.0 + 0.15 * lift)
						mark_rect.position.y -= lift * cs * 0.18
					if conflicted:
						CrownArt.draw(self, mark_rect, CONFLICT_COLOR, CONFLICT_BAND)
					else:
						CrownArt.draw(self, mark_rect)
			if not hint_focus.is_empty() and not hint_focus.has(i):
				draw_style_box(_rounded(HINT_DIM, radius), tile)
			if hint_targets.has(i):
				var ring := _rounded(Color.TRANSPARENT, radius)
				ring.draw_center = false
				ring.border_color = Color(HINT_COLOR, pulse)
				ring.set_border_width_all(roundi(maxf(2.0, cs * 0.07)))
				draw_style_box(ring, tile)
	if _cursor_shown and interactive and has_focus() and reveal < 0.0:
		var cursor_tile := Rect2(origin + Vector2(cursor.y, cursor.x) * cs, Vector2(cs, cs)).grow(-cs * GAP / 4.0)
		var frame := _rounded(Color.TRANSPARENT, cs * RADIUS * 1.15)
		frame.draw_center = false
		frame.border_color = CURSOR_DARK if dark else CURSOR_LIGHT
		frame.set_border_width_all(roundi(maxf(2.0, cs * 0.06)))
		draw_style_box(frame, cursor_tile)


## A rounded box in `color`, for tiles and the tray behind them.
func _rounded(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(roundi(radius))
	box.corner_detail = 8
	box.anti_aliasing = true
	return box


## The tile's rounded outline as a polygon, to keep patterns and hatching inside it.
func _tile_outline(tile: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := roundf(radius)
	var corners := [tile.position + Vector2(r, r), Vector2(tile.end.x - r, tile.position.y + r),
			tile.end - Vector2(r, r), Vector2(tile.position.x + r, tile.end.y - r)]
	for k in 4:
		for step in 7:
			var angle := PI + k * PI / 2.0 + step * PI / 12.0
			points.append(corners[k] + Vector2(cos(angle), sin(angle)) * r)
	return points


## A line kept inside `outline`, so it doesn't poke past a tile's rounded corners.
func _clipped_line(a: Vector2, b: Vector2, outline: PackedVector2Array, color: Color, width: float) -> void:
	for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), outline):
		draw_polyline(part, color, width)


## One of PATTERN_COUNT faint textures, repeating every third or quarter of a
## cell so neighbouring cells of a region join up. None of them look like a
## cross, and the only diagonal lines run the opposite way to conflict hatching.
func _draw_pattern(rect: Rect2, region: int, outline: PackedVector2Array) -> void:
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
				_clipped_line(p + a, p + b, outline, ink, w)
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
						var square := Rect2(p + Vector2(i, j) * s / 4.0, Vector2.ONE * s / 4.0)
						var corners := PackedVector2Array([square.position, Vector2(square.end.x, square.position.y),
								square.end, Vector2(square.position.x, square.end.y)])
						for part in Geometry2D.intersect_polygons(corners, outline):
							draw_colored_polygon(part, Color(ink, ink.a * 0.6))
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
func _draw_stripes(rect: Rect2, outline: PackedVector2Array) -> void:
	var s := rect.size.x
	var gap := s / 5.0
	var color := Color(CONFLICT_COLOR, 0.55)
	var c := gap / 2.0
	while c < 2.0 * s:
		# Segment of the line x + y = c inside the square.
		var a := rect.position + Vector2(maxf(0.0, c - s), minf(c, s))
		var b := rect.position + Vector2(minf(c, s), maxf(0.0, c - s))
		_clipped_line(a, b, outline, color, maxf(1.5, s * 0.05))
		c += gap


func _draw_cross(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var r := rect.size.x * 0.13
	var width := maxf(1.5, rect.size.x * 0.05)
	draw_line(center + Vector2(-r, -r), center + Vector2(r, r), color, width, true)
	draw_line(center + Vector2(-r, r), center + Vector2(r, -r), color, width, true)


## Starts a pop for every cell that gained a mark since the last draw,
## whichever way it changed: a tap, a drag, a hint, undo or auto crosses.
func _update_pops(now: int) -> void:
	var marks := board.marks
	if _shown_marks.size() == marks.size():
		for i in marks.size():
			if marks[i] != _shown_marks[i]:
				if marks[i] == Board.Mark.EMPTY:
					_pops.erase(i)
				else:
					_pops[i] = now
	_shown_marks = marks.duplicate()
	for i: int in _pops.keys():
		if now - _pops[i] > POP_MS.get(marks[i], 150.0):
			_pops.erase(i)


func _scaled(rect: Rect2, factor: float) -> Rect2:
	var side := rect.size * factor
	return Rect2(rect.get_center() - side / 2.0, side)


## 0 -> 1 with a little overshoot, like a piece settling into place.
func _ease_out_back(t: float) -> float:
	if t >= 1.0:
		return 1.0
	var c := 1.70158
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u
