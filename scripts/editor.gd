extends Control
## The puzzle editor: paint regions onto a blank board, see whether the layout
## makes a fair puzzle (one solution) and how hard it is, then play or share it.

const Board := preload("res://scripts/board.gd")
const BoardView := preload("res://scripts/board_view.gd")
const CustomPuzzle := preload("res://scripts/custom_puzzle.gd")
const Generator := preload("res://scripts/generator.gd")

signal back
## The layout is a fair puzzle and the player wants to play it.
signal play(code: String, size: int, regions: PackedInt32Array, solution: PackedInt32Array)
## The draft changed, for the game to keep it.
signal changed(size: int, regions: PackedInt32Array)

const DEFAULT_SIZE := 7

var view: BoardView
var size_picker: OptionButton
var status_label: Label
var play_button: Button
var share_button: Button
var _palette: HBoxContainer
var _size := DEFAULT_SIZE
## The colour being painted.
var _color := 0
## check()'s verdict on the layout.
var _check := {}
## Difficulty names as shown, set by the game.
var difficulty_names: Array[String] = []


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	header.add_child(_button(tr("Back"), back.emit))
	# TRANSLATORS: The puzzle editor's title.
	var title := _label(tr("Create"), 34)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	size_picker = OptionButton.new()
	for size in range(CustomPuzzle.MIN_SIZE, CustomPuzzle.MAX_SIZE + 1):
		size_picker.add_item("%d×%d" % [size, size], size)
	size_picker.item_selected.connect(func(index: int) -> void: start(size_picker.get_item_id(index)))
	header.add_child(size_picker)

	var hint := _label(tr("Paint one region per colour. Tap or drag to fill cells."), 16)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.65)
	column.add_child(hint)

	view = BoardView.new()
	view.size_flags_vertical = SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(300, 300)
	view.painted.connect(_on_painted)
	column.add_child(view)

	_palette = HBoxContainer.new()
	_palette.alignment = BoxContainer.ALIGNMENT_CENTER
	_palette.add_theme_constant_override("separation", 6)
	column.add_child(_palette)

	status_label = _label("", 18)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size.y = 50
	column.add_child(status_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	actions.add_child(_button(tr("Clear"), func() -> void: start(_size)))
	# TRANSLATORS: Fills the editor with a random layout to start from.
	actions.add_child(_button(tr("Random"), _randomize))
	play_button = _button(tr("Play"), _play)
	actions.add_child(play_button)
	# TRANSLATORS: Copies the editor puzzle's code to share it.
	share_button = _button(tr("Share"), _share)
	actions.add_child(share_button)
	for control: Control in header.get_children() + actions.get_children():
		if control is Button:
			control.focus_mode = FOCUS_NONE


## Opens `regions` (unpainted cells -1) at `size`, or a blank board when they don't fit it.
func open(size: int, regions: PackedInt32Array) -> void:
	if regions.size() != size * size:
		regions = PackedInt32Array()
		regions.resize(size * size)
		regions.fill(-1)
	_size = size
	size_picker.select(size - CustomPuzzle.MIN_SIZE)
	view.board = Board.new(size, regions.duplicate(), PackedInt32Array())
	_build_palette()
	_select_color(clampi(_color, 0, size - 1))
	_update()


## A blank board of `size`.
func start(size: int) -> void:
	open(size, PackedInt32Array())
	changed.emit(_size, view.board.regions)


## The puzzle's code, or "" while it isn't fair.
func code() -> String:
	return CustomPuzzle.encode(_size, view.board.regions) if _check.problem.is_empty() else ""


func _build_palette() -> void:
	# Gone at once, as the new swatches are numbered by their place in the row.
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	for region in _size:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.focus_mode = FOCUS_NONE
		swatch.tooltip_text = view.region_name(region)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			swatch.add_theme_stylebox_override(state, _swatch_box(region, false))
		swatch.pressed.connect(_select_color.bind(region))
		_palette.add_child(swatch)


## The colour's swatch, ringed when it's the one being painted.
func _swatch_box(region: int, selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BoardView.REGION_COLORS[region]
	box.set_corner_radius_all(8)
	if selected:
		box.set_border_width_all(4)
		box.border_color = BoardView.MARK_COLOR
	return box


func _select_color(region: int) -> void:
	_color = region
	view.paint = region
	for swatch in _palette.get_child_count():
		var button: Button = _palette.get_child(swatch)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state, _swatch_box(swatch, swatch == region))


func _on_painted() -> void:
	_update()
	changed.emit(_size, view.board.regions)


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var layout: Dictionary = Generator._generate_unique(_size, rng, 1.0, 0.4)
	open(_size, layout.regions)
	changed.emit(_size, view.board.regions)


## Checks the layout and says what it needs, or how hard it is once it's fair.
func _update() -> void:
	_check = CustomPuzzle.check(_size, view.board.regions)
	var fair: bool = _check.problem.is_empty()
	play_button.disabled = not fair
	share_button.disabled = not fair
	share_button.text = tr("Share")
	status_label.text = _status()


func _status() -> String:
	match _check.problem:
		CustomPuzzle.UNPAINTED:
			return tr_n("%d cell left to paint.", "%d cells left to paint.", _check.count) % _check.count
		CustomPuzzle.MISSING:
			return tr_n("%d colour isn't used yet.", "%d colours aren't used yet.", _check.count) % _check.count
		CustomPuzzle.SPLIT:
			# TRANSLATORS: %s is a region colour, e.g. "The purple region is split…".
			return tr("The %s region is split in two. Each colour needs to be one piece.") % view.region_name(_check.region)
		CustomPuzzle.NO_SOLUTION:
			return tr("No way to place the crowns. Try moving some cells.")
		CustomPuzzle.MANY_SOLUTIONS:
			return tr("More than one solution. Reshape the regions until only one works.")
	if _check.difficulty == CustomPuzzle.BEYOND_HINTS:
		return tr("One solution, but harder than the hints can explain.")
	# TRANSLATORS: %s is a difficulty, e.g. "One solution · Medium".
	return tr("One solution · %s") % difficulty_names[_check.difficulty]


func _play() -> void:
	if _check.problem.is_empty():
		play.emit(code(), _size, view.board.regions.duplicate(), _check.solution)


func _share() -> void:
	var text := code()
	if text.is_empty():
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		# TRANSLATORS: Copied to share a puzzle; %s is its code. Keep the code as is.
		DisplayServer.clipboard_set(tr("Try this Crowns puzzle: %s") % text)
	share_button.text = tr("Copied!")
	status_label.text = text


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90, 40)
	button.pressed.connect(on_pressed)
	return button
