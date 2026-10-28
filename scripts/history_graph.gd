extends Control
## A graph of recent solve times at one size, oldest on the left: a dot per
## solve coloured by its difficulty, joined by a line, with the average dashed
## across and the fastest ringed. Takes its colours from the theme.

## A colour per difficulty, Easy to Hard+; light and dark themes can both show them.
const DIFFICULTY_COLORS := [Color("4caf50"), Color("2f8fdd"), Color("e07a2e"), Color("b04fd0")]
const AXIS_WIDTH := 46.0
const FONT_SIZE := 13

## [unix time, seconds, difficulty] per solve, oldest first.
var entries: Array = []:
	set(value):
		entries = value
		queue_redraw()
## Turns seconds into the time shown on the axis.
var format := func(seconds: float) -> String: return str(roundi(seconds))


func _ready() -> void:
	custom_minimum_size.y = 170


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	if entries.is_empty():
		return
	var text := get_theme_color("font_color", "Label")
	var font := get_theme_default_font()
	var line_color: Color = text
	var button := get_theme_stylebox("normal", "Button")
	if button is StyleBoxFlat:
		# Nudged towards the text so it shows on dark backgrounds as well as light.
		line_color = button.bg_color.lerp(text, 0.3)
	var times: Array = entries.map(func(entry: Array) -> float: return entry[1])
	var slowest: float = times.max()
	var top := maxf(slowest * 1.1, 1.0)
	var plot := Rect2(AXIS_WIDTH, FONT_SIZE * 0.5, size.x - AXIS_WIDTH - 10.0, size.y - FONT_SIZE)
	var y_at := func(seconds: float) -> float: return plot.end.y - plot.size.y * seconds / top

	# Gridlines at nothing, half and the slowest time, labelled on the left.
	for seconds: float in [0.0, slowest / 2.0, slowest]:
		var y: float = y_at.call(seconds)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(text, 0.12), 1.0)
		var label: String = format.call(seconds)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(plot.position.x - 8.0 - width, y + FONT_SIZE * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(text, 0.6))

	var average: float = times.reduce(func(sum: float, seconds: float) -> float: return sum + seconds, 0.0) / times.size()
	var average_y: float = y_at.call(average)
	draw_dashed_line(Vector2(plot.position.x, average_y), Vector2(plot.end.x, average_y), Color(text, 0.45), 1.5, 6.0)

	var points := PackedVector2Array()
	for index in entries.size():
		var x := plot.position.x + plot.size.x * (0.5 if entries.size() == 1 else float(index) / (entries.size() - 1))
		points.append(Vector2(x, y_at.call(times[index])))
	if points.size() > 1:
		draw_polyline(points, line_color, 2.0, true)
	var fastest := times.find(times.min())
	for index in points.size():
		var radius := 5.0 if points.size() <= 15 else 4.0
		if index == fastest:
			draw_circle(points[index], radius + 3.5, text, false, 2.0, true)
		draw_circle(points[index], radius, DIFFICULTY_COLORS[clampi(entries[index][2], 0, DIFFICULTY_COLORS.size() - 1)], true, -1.0, true)
